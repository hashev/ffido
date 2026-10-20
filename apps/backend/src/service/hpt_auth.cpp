#include "service/hpt_auth.hpp"

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <nlohmann/json.hpp>
#include <set>

extern char** environ;

namespace fidoback::service {
std::expected<HptConfiguration, domain::ApiError> ReadHptConfiguration(const std::filesystem::path& helper,
                                                                       const std::filesystem::path& config,
                                                                       std::chrono::milliseconds timeout,
                                                                       std::span<const ftn::PathMapping> mappings) {
  const auto failure = [] {
    return std::unexpected(domain::ApiError::Server("HPT authentication configuration unavailable"));
  };
  if (helper.empty() || config.empty() || timeout <= std::chrono::milliseconds::zero())
    return failure();
  nlohmann::json rules = nlohmann::json::array();
  for (const auto& rule : mappings)
    rules.push_back({{"from", rule.from.string()}, {"to", rule.to.string()}});
  const auto mapping_input = rules.dump();
  if (mapping_input.size() > 65536)
    return failure();
  int pipefd[2];
  if (pipe(pipefd) != 0)
    return failure();
  fcntl(pipefd[0], F_SETFD, FD_CLOEXEC);
  fcntl(pipefd[1], F_SETFD, FD_CLOEXEC);
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
  posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
  posix_spawn_file_actions_addclose(&actions, pipefd[0]);
  const auto executable = helper.string(), path = config.string();
  char* args[] = {const_cast<char*>(executable.c_str()), const_cast<char*>(path.c_str()),
                  mappings.empty() ? nullptr : const_cast<char*>(mapping_input.c_str()), nullptr};
  pid_t child = -1;
  const int spawned = posix_spawn(&child, executable.c_str(), &actions, nullptr, args, environ);
  posix_spawn_file_actions_destroy(&actions);
  close(pipefd[1]);
  if (spawned != 0) {
    close(pipefd[0]);
    return failure();
  }
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  std::string data;
  bool success = false;
  while (std::chrono::steady_clock::now() < deadline) {
    pollfd descriptor{pipefd[0], POLLIN, 0};
    const auto remaining =
        std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now());
    const int ready = poll(&descriptor, 1, static_cast<int>(remaining.count()));
    if (ready < 0 && errno == EINTR)
      continue;
    if (ready <= 0)
      break;
    char buffer[4096];
    const auto count = read(pipefd[0], buffer, sizeof(buffer));
    if (count == 0) {
      success = true;
      break;
    }
    if (count < 0)
      break;
    data.append(buffer, static_cast<size_t>(count));
    if (data.size() > 16 * 1024 * 1024)
      break;
  }
  close(pipefd[0]);
  // Even a child that closes stdout without exiting is bounded by the deadline.
  int status = 0;
  bool reaped = false;
  while (success && std::chrono::steady_clock::now() < deadline) {
    const auto waited = waitpid(child, &status, WNOHANG);
    if (waited == child) {
      reaped = true;
      break;
    }
    if (waited < 0 && errno != EINTR)
      break;
    poll(nullptr, 0, 1);
  }
  if (!reaped) {
    kill(child, SIGKILL);
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
    }
    return failure();
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
    return failure();
  try {
    auto document = nlohmann::json::parse(data);
    if (document.value("error", std::string{}) == "mapped_include_adapter_unavailable")
      return std::unexpected(domain::ApiError::Server(
          "HPT mapped include adapter unavailable; rebuild helper with FFIDO_FIDOCONFIG_SOURCE"));
    const auto& rows = document.at("credentials");
    if (!rows.is_array() || rows.size() > 10000)
      return failure();
    HptCredentials credentials;
    for (const auto& row : rows) {
      auto address = domain::CanonicalFtnAddress(row.at("address").get<std::string>());
      auto password = row.at("password").get<std::string>();
      if (!address || password.size() > 4096 || !credentials.emplace(*address, password).second)
        return failure();
    }
    HptConfiguration result;
    result.credentials = std::move(credentials);
    const auto& echoes = document.at("echoes");
    if (!echoes.is_array() || echoes.size() > 10000)
      return failure();
    size_t subscriptions = 0;
    std::set<std::string> names;
    for (const auto& row : echoes) {
      HptEcho echo;
      echo.name = row.at("name").get<std::string>();
      echo.description = row.value("description", std::string{});
      echo.filename = row.at("filename").get<std::string>();
      auto name = echo.name;
      for (auto& c : name)
        if (c >= 'A' && c <= 'Z')
          c += 'a' - 'A';
      if (name.empty() || name.size() > 256 || name.find('\0') != std::string::npos || !names.insert(name).second ||
          !echo.filename.is_absolute() || echo.filename.string().find('\0') != std::string::npos)
        return failure();
      const auto& links = row.at("links");
      if (!links.is_array())
        return failure();
      for (const auto& link : links) {
        auto address = domain::CanonicalFtnAddress(link.at("address").get<std::string>());
        if (!address || ++subscriptions > 100000 ||
            !echo.links.emplace(*address, EchoPermissions{link.at("read").get<bool>(), link.at("post").get<bool>()})
                 .second)
          return failure();
      }
      result.echoes.push_back(std::move(echo));
    }
    const auto areas = document.value("private_areas", nlohmann::json::array());
    if (!areas.is_array() || areas.size() + echoes.size() > 10000)
      return failure();
    std::set<std::pair<AreaKind, std::string>> private_names;
    for (const auto& row : areas) {
      EchoAreaConfig area;
      area.name = row.at("name").get<std::string>();
      const auto description = row.value("description", std::string{});
      if (!description.empty())
        area.description = description;
      area.filename = row.at("filename").get<std::string>();
      area.msgbase_type = row.at("format").get<std::string>();
      const auto kind = row.at("kind").get<std::string>();
      if (kind == "netmail")
        area.kind = AreaKind::kNetmail;
      else if (kind == "local")
        area.kind = AreaKind::kLocal;
      else if (kind == "bad")
        area.kind = AreaKind::kBad;
      else if (kind == "dupe")
        area.kind = AreaKind::kDupe;
      else if (kind == "robots")
        area.kind = AreaKind::kRobots;
      else
        return failure();
      auto name = area.name;
      for (auto& c : name)
        if (c >= 'A' && c <= 'Z')
          c += 'a' - 'A';
      if (name.empty() || name.size() > 256 || name.find('\0') != std::string::npos ||
          !private_names.emplace(area.kind, name).second || !std::filesystem::path(area.filename).is_absolute() ||
          area.filename.find('\0') != std::string::npos ||
          (*area.msgbase_type != "JAM" && *area.msgbase_type != "Squish" && *area.msgbase_type != "MSG" &&
           *area.msgbase_type != "Passthrough"))
        return failure();
      const auto aka = row.at("aka").get<std::string>();
      if (!aka.empty()) {
        auto address = domain::CanonicalFtnAddress(aka);
        if (!address)
          return failure();
        area.aka = *address;
      }
      result.private_areas.push_back(std::move(area));
    }
    if (document.contains("mail_transport")) {
      const auto& mail = document.at("mail_transport");
      auto& t = result.transport;
      t.keep_transit = mail.at("keep_transit").get<bool>();
      t.pack_on_scan = mail.at("pack_on_scan").get<bool>();
      std::set<std::string> own;
      for (const auto& value : mail.at("own_addresses")) {
        auto address = domain::CanonicalFtnAddress(value.get<std::string>());
        if (!address || !own.insert(*address).second || own.size() > 10000)
          return failure();
        t.own_addresses.push_back(*address);
      }
      for (const auto& value : mail.at("links")) {
        auto address = domain::CanonicalFtnAddress(value.at("address").get<std::string>());
        auto aka = domain::CanonicalFtnAddress(value.at("our_aka").get<std::string>());
        if (!address || !aka || !t.link_akas.emplace(*address, *aka).second || t.link_akas.size() > 10000)
          return failure();
      }
      if (mail.at("netmail").size() > 10000 || mail.at("routes").size() > 10000)
        return failure();
      for (const auto& value : mail.at("netmail"))
        t.netmail.push_back({value.at("name").get<std::string>(), value.at("dupe_check_off").get<bool>()});
      for (const auto& value : mail.at("routes")) {
        auto pattern = value.at("pattern").get<std::string>();
        if (pattern.size() > 65536 || pattern.find('\0') != std::string::npos)
          return failure();
        t.routes.push_back({pattern, value.at("nopack").get<bool>(), value.at("mail").get<bool>()});
      }
      t.available = true;
    }
    if (!mappings.empty()) {
      const auto& files = document.at("included_files");
      if (!files.is_array() || files.size() > 1024)
        return failure();
      for (const auto& file : files)
        result.included_files.emplace_back(file.at("device").get<uint64_t>(), file.at("inode").get<uint64_t>());
    }
    return result;
  } catch (const std::exception&) {
    return failure();
  }
}
}  // namespace fidoback::service
