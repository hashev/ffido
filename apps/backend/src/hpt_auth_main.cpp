#include <fcntl.h>
#include <fidoconf/fidoconf.h>

// Husky C headers define these macros on some Linux installations.
#undef min
#undef max
#include <sys/stat.h>
#include <unistd.h>

#ifdef FFIDO_CONFIG_OPEN_ADAPTER
#include "ftn/path_mapping.hpp"
#endif

#include <algorithm>
#include <filesystem>
#include <nlohmann/json.hpp>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {
#ifdef FFIDO_CONFIG_OPEN_ADAPTER
std::vector<fidoback::ftn::PathMapping> mappings;
std::vector<std::pair<uint64_t, uint64_t>> include_stack;
nlohmann::json included_files = nlohmann::json::array();
uint64_t config_bytes = 0;
bool open_failed = false;
#endif

bool Same(const hs_addr& a, const hs_addr& b) {
  return a.zone == b.zone && a.net == b.net && a.node == b.node && a.point == b.point;
}
std::string Address(const hs_addr& a) {
  return std::to_string(a.zone) + ":" + std::to_string(a.net) + "/" + std::to_string(a.node) +
         (a.point ? "." + std::to_string(a.point) : "");
}
bool Virtual(const s_fidoconfig& config, const s_link& link) {
  if (!link.name || !std::string_view(link.name).starts_with("Our virtual link for aka: "))
    return false;
  for (unsigned i = 0; i < config.addrCount; ++i)
    if (Same(config.addr[i], link.hisAka))
      return true;
  return false;
}
}  // namespace
#ifdef FFIDO_CONFIG_OPEN_ADAPTER
extern "C" FILE* ffido_config_open(const char* name, unsigned depth) {
  if (mappings.empty())
    return fopen(name, "rb");
  try {
    if (depth > 32 || included_files.size() >= 1024)
      throw std::runtime_error("Configuration limit");
    auto path = std::filesystem::absolute(name);
    if (depth != 0) {
      auto mapped = fidoback::ftn::MapPath(path, mappings);
      if (!mapped)
        throw std::runtime_error("Configuration path");
      path = *mapped;
    }
    FILE* file = fopen(path.c_str(), "rb");
    if (!file)
      throw std::runtime_error("Configuration unavailable");
    struct stat info{};
    if (fstat(fileno(file), &info) != 0 || !S_ISREG(info.st_mode) || info.st_size < 0 ||
        static_cast<uint64_t>(info.st_size) > 16 * 1024 * 1024 - config_bytes) {
      fclose(file);
      throw std::runtime_error("Configuration size");
    }
    const auto identity = std::pair<uint64_t, uint64_t>{info.st_dev, info.st_ino};
    if (depth > include_stack.size()) {
      fclose(file);
      throw std::runtime_error("Configuration depth");
    }
    include_stack.resize(depth);
    if (std::find(include_stack.begin(), include_stack.end(), identity) != include_stack.end()) {
      fclose(file);
      throw std::runtime_error("Configuration cycle");
    }
    include_stack.push_back(identity);
    config_bytes += static_cast<uint64_t>(info.st_size);
    if (depth != 0)
      included_files.push_back({{"device", info.st_dev}, {"inode", info.st_ino}});
    return file;
  } catch (const std::exception&) {
    open_failed = true;
    return nullptr;
  }
}
#endif
// libfidoconfig can exit() and print configuration values. Only this process
// loads it; its diagnostics never reach the server log or protocol pipe.
int main(int argc, char** argv) try {
  if (argc != 2 && argc != 3)
    return 2;
  const int output = dup(STDOUT_FILENO);
  if (output < 0 || fcntl(output, F_SETFD, FD_CLOEXEC) != 0)
    return 1;
  const int null = open("/dev/null", O_RDWR);
  if (output < 0 || null < 0 || dup2(null, STDOUT_FILENO) < 0 || dup2(null, STDERR_FILENO) < 0)
    return 1;
  close(null);
  if (argc == 3) {
#ifdef FFIDO_CONFIG_OPEN_ADAPTER
    if (std::string_view(argv[2]).size() > 65536)
      return 1;
    const auto rules = nlohmann::json::parse(argv[2]);
    if (!rules.is_array() || rules.size() > 128)
      return 1;
    for (const auto& rule : rules)
      mappings.push_back({rule.at("from").get<std::string>(), rule.at("to").get<std::string>()});
    auto validated = fidoback::ftn::ValidateMappings(mappings);
    if (!validated)
      return 1;
    mappings = std::move(*validated);
#else
    const std::string error = "{\"error\":\"mapped_include_adapter_unavailable\"}";
    static_cast<void>(write(output, error.data(), error.size()));
    return 0;
#endif
  }
  fc_trycreate = 0;
  SetAppModule(M_HPT);
  char module_name[] = "module", module_value[] = "hpt";
  setvar(module_name, module_value);
  auto* config = readConfig(argv[1]);
  if (!config)
    return 1;
#ifdef FFIDO_CONFIG_OPEN_ADAPTER
  if (open_failed)
    return 1;
#endif
  nlohmann::json rows = nlohmann::json::array();
  std::set<std::string> explicit_addresses;
  std::set<std::string> local_points;
  for (unsigned i = 0; i < config->linkCount; ++i) {
    const auto* link = config->links[i];
    if (!link)
      continue;
    if (Virtual(*config, *link))
      continue;
    const auto& a = link->hisAka;
    if (link->hisAka.zone <= 0 || link->hisAka.net <= 0 || link->hisAka.node < 0 || link->hisAka.point < 0)
      return 1;  // A wildcard is not a concrete authenticated identity.
    const char* password = link->sessionPwd ? link->sessionPwd : link->defaultPwd;
    const auto address = Address(a);
    explicit_addresses.insert(address);
    rows.push_back({{"address", address}, {"password", password ? password : ""}});
    if (rows.size() > 10000)
      return 1;
  }
  for (unsigned i = 0; i < config->addrCount; ++i) {
    const auto& own = config->addr[i];
    const auto address = Address(own);
    if (own.point <= 0 || explicit_addresses.contains(address) || local_points.contains(address))
      continue;
    const s_link* boss = nullptr;
    for (unsigned j = 0; j < config->linkCount; ++j) {
      const auto* link = config->links[j];
      if (!link || Virtual(*config, *link) || !link->ourAka || !Same(*link->ourAka, own))
        continue;
      const auto& remote = link->hisAka;
      if (remote.point != 0 || remote.zone != own.zone || remote.net != own.net || remote.node != own.node)
        continue;
      if (boss)
        return 1;
      boss = link;
    }
    if (!boss)
      continue;
    const char* password = boss->sessionPwd ? boss->sessionPwd : boss->defaultPwd;
    if (!password || !*password)
      continue;
    rows.push_back({{"address", address}, {"password", password}});
    local_points.insert(address);
    if (rows.size() > 10000)
      return 1;
  }
  nlohmann::json echoes = nlohmann::json::array();
  size_t subscriptions = 0;
  for (unsigned i = 0; i < config->echoAreaCount; ++i) {
    const auto& area = config->echoAreas[i];
    if (area.msgbType != MSGTYPE_JAM)
      continue;
    if (!area.areaName || !area.fileName || echoes.size() >= 10000)
      return 1;
    nlohmann::json links = nlohmann::json::array();
    for (unsigned j = 0; j < area.downlinkCount; ++j) {
      const auto* permission = area.downlinks[j];
      if (!permission || !permission->link || ++subscriptions > 100000)
        return 1;
      const auto& a = permission->link->hisAka;
      const auto address = Address(a);
      if (local_points.contains(address))
        continue;
      links.push_back({{"address", address}, {"read", permission->aexport != 0}, {"post", permission->import != 0}});
    }
    if (area.useAka && local_points.contains(Address(*area.useAka))) {
      if (++subscriptions > 100000)
        return 1;
      links.push_back({{"address", Address(*area.useAka)}, {"read", true}, {"post", true}});
    }
    auto filename = std::filesystem::path(area.fileName);
#ifdef FFIDO_CONFIG_OPEN_ADAPTER
    if (!mappings.empty() && !fidoback::ftn::MapPath(std::filesystem::absolute(filename), {}))
      return 1;
#endif
    if (filename.is_relative())
      filename = std::filesystem::absolute(filename);
    echoes.push_back({{"name", area.areaName},
                      {"filename", filename.lexically_normal().string()},
                      {"links", links},
                      {"description", argc == 3 && area.description ? area.description : ""}});
  }
  nlohmann::json private_areas = nlohmann::json::array();
  auto fold = [](std::string text) {
    for (auto& c : text)
      if (c >= 'A' && c <= 'Z')
        c += 'a' - 'A';
    return text;
  };
  bool robots_found = !config->robotsArea || !*config->robotsArea;
  auto add = [&](const s_area& area, std::string kind) {
    if (!area.areaName || !*area.areaName)
      return true;  // Optional BadArea/DupeArea.
    if (!area.fileName || private_areas.size() >= 10000)
      return false;
    if (kind == "netmail" && config->robotsArea && fold(area.areaName) == fold(config->robotsArea)) {
      kind = "robots";
      robots_found = true;
    }
    std::string format;
    switch (area.msgbType) {
      case MSGTYPE_JAM:
        format = "JAM";
        break;
      case MSGTYPE_SQUISH:
        format = "Squish";
        break;
      case MSGTYPE_SDM:
        format = "MSG";
        break;
      case MSGTYPE_PASSTHROUGH:
        format = "Passthrough";
        break;
      default:
        return false;
    }
    auto filename = std::filesystem::absolute(area.fileName);
#ifdef FFIDO_CONFIG_OPEN_ADAPTER
    if (!mappings.empty() && !fidoback::ftn::MapPath(filename, {}))
      return false;
#endif
    filename = filename.lexically_normal();
    private_areas.push_back({{"name", area.areaName},
                             {"filename", filename.string()},
                             {"kind", kind},
                             {"description", argc == 3 && area.description ? area.description : ""},
                             {"format", format},
                             {"aka", area.useAka ? Address(*area.useAka) : ""}});
    return true;
  };
  for (unsigned i = 0; i < config->netMailAreaCount; ++i)
    if (!add(config->netMailAreas[i], "netmail"))
      return 1;
  for (unsigned i = 0; i < config->localAreaCount; ++i)
    if (!add(config->localAreas[i], "local"))
      return 1;
  if (!add(config->badArea, "bad") || !add(config->dupeArea, "dupe") || !robots_found)
    return 1;
  nlohmann::json transport = {
      {"own_addresses", nlohmann::json::array()}, {"links", nlohmann::json::array()},
      {"netmail", nlohmann::json::array()},       {"routes", nlohmann::json::array()},
      {"keep_transit", config->keepTrsMail != 0}, {"pack_on_scan", config->packNetMailOnScan != 0}};
  for (unsigned i = 0; i < config->addrCount; ++i)
    transport["own_addresses"].push_back(Address(config->addr[i]));
  for (unsigned i = 0; i < config->linkCount; ++i) {
    const auto* link = config->links[i];
    if (link && !Virtual(*config, *link) && link->ourAka)
      transport["links"].push_back({{"address", Address(link->hisAka)}, {"our_aka", Address(*link->ourAka)}});
  }
  for (unsigned i = 0; i < config->netMailAreaCount; ++i) {
    const auto& area = config->netMailAreas[i];
    transport["netmail"].push_back(
        {{"name", area.areaName ? area.areaName : ""}, {"dupe_check_off", area.dupeCheck == dcOff}});
  }
  for (unsigned i = 0; i < config->routeCount; ++i) {
    const auto& route = config->route[i];
    transport["routes"].push_back({{"pattern", route.pattern ? route.pattern : ""},
                                   {"nopack", route.routeVia == nopack},
                                   {"mail", route.id == id_route || route.id == id_routeMail}});
  }
  disposeConfig(config);
  auto document = nlohmann::json{
      {"credentials", rows}, {"echoes", echoes}, {"private_areas", private_areas}, {"mail_transport", transport}};
#ifdef FFIDO_CONFIG_OPEN_ADAPTER
  if (!mappings.empty())
    document["included_files"] = included_files;
#endif
  const auto data = document.dump();
  if (data.size() > 16 * 1024 * 1024)
    return 1;
  size_t offset = 0;
  while (offset < data.size()) {
    const auto written = write(output, data.data() + offset, data.size() - offset);
    if (written <= 0)
      return 1;
    offset += static_cast<size_t>(written);
  }
  close(output);
  return 0;
} catch (const std::exception&) {
  return 1;
}
