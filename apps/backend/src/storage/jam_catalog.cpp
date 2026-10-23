#include "storage/jam_catalog.hpp"

#include <fcntl.h>
#include <unistd.h>

#include <cerrno>
#include <set>

#include "JamMessageBase.h"
#include "storage/coordination_lock.hpp"
#include "storage/point_mailbox.hpp"

namespace fidoback::storage {
namespace {
struct Directory {
  int fd = -1;
  ~Directory() {
    if (fd >= 0)
      close(fd);
  }
};

bool SameFile(const struct stat& a, const struct stat& b) {
  return a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

bool SafeRelative(const std::filesystem::path& path) {
  if (path.empty() || path.is_absolute() || path.filename().empty())
    return false;
  for (const auto& component : path) {
    if (component == ".." || component == "." || component.empty())
      return false;
  }
  const auto text = path.string();
  return text.find('\0') == std::string::npos;
}

int OpenParent(int root_fd, const std::filesystem::path& relative) {
  int current = dup(root_fd);
  if (current < 0)
    return -1;
  for (const auto& part : relative.parent_path()) {
    int next = openat(current, part.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    close(current);
    if (next < 0)
      return -1;
    current = next;
  }
  return current;
}

constexpr std::array<std::string_view, 3> kExtensions{".jhr", ".jdt", ".jdx"};
}  // namespace

JamFiles::~JamFiles() {
  for (int fd : descriptors)
    if (fd >= 0)
      close(fd);
}

JamCatalog::~JamCatalog() {
  close(root_fd_);
}

std::expected<std::unique_ptr<JamCatalog>, CatalogError> JamCatalog::Build(
    const std::filesystem::path& root, const std::vector<EchoAreaConfig>& areas,
    std::shared_ptr<CoordinationLock> coordination, const std::map<std::string, std::string>& encoding_overrides) {
  std::unique_ptr<CoordinationLease> lease;
  if (coordination) {
    auto acquired = coordination->Shared(std::chrono::steady_clock::now() + std::chrono::seconds(5));
    if (!acquired)
      return std::unexpected(CatalogError::kIo);
    lease = std::move(*acquired);
  }
  std::error_code error;
  const auto canonical_root = std::filesystem::canonical(root, error);
  if (error)
    return std::unexpected(CatalogError::kInvalidConfiguration);
  const int root_fd = open(canonical_root.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (root_fd < 0)
    return std::unexpected(CatalogError::kIo);
  auto catalog = std::unique_ptr<JamCatalog>(new JamCatalog(root_fd));
  catalog->coordination_ = std::move(coordination);
  std::map<std::pair<dev_t, ino_t>, std::shared_ptr<JamFiles>> physical;
  std::set<std::string> matched_overrides;
  for (const auto& config : areas) {
    if (config.kind == AreaKind::kEcho && (config.is_passthrough || config.msgbase_type != "JAM"))
      continue;
    std::string id = config.name;
    if (id.empty() || id.size() > 256 || id.find('\0') != std::string::npos || id.starts_with("@ffido/"))
      return std::unexpected(CatalogError::kInvalidConfiguration);
    if (config.kind != AreaKind::kEcho) {
      id = "@ffido/" + std::to_string(static_cast<int>(config.kind)) + "/";
      constexpr char hex[] = "0123456789abcdef";
      for (unsigned char c : config.name) {
        if (c >= 'A' && c <= 'Z')
          c += 'a' - 'A';
        id += hex[c >> 4];
        id += hex[c & 15];
      }
    }
    if (!config.mailbox_address.empty()) {
      if (config.kind != AreaKind::kNetmail || config.msgbase_type != "JAM" || config.mailbox_generation.empty())
        return std::unexpected(CatalogError::kInvalidConfiguration);
      id = MailboxId(config.mailbox_address);
    }
    if (catalog->areas_.contains(id))
      return std::unexpected(CatalogError::kInvalidConfiguration);
    std::filesystem::path relative(config.filename);
    if (relative.is_absolute()) {
      auto candidate = relative.lexically_relative(std::filesystem::absolute(root).lexically_normal());
      if (!SafeRelative(candidate))
        candidate = relative.lexically_relative(canonical_root);
      relative = std::move(candidate);
    }
    if (!SafeRelative(relative))
      return std::unexpected(CatalogError::kInvalidConfiguration);
    Directory parent{OpenParent(root_fd, relative)};
    if (parent.fd < 0)
      return std::unexpected(CatalogError::kInvalidConfiguration);
    if (config.msgbase_type != "JAM") {
      catalog->areas_.emplace(id, JamArea{config, relative, {}});
      continue;
    }
    auto files = std::make_shared<JamFiles>();
    if (auto rule = encoding_overrides.find(relative.generic_string()); rule != encoding_overrides.end()) {
      files->forced_encoding = rule->second;
      matched_overrides.insert(rule->first);
    }
    files->personal_mailbox = !config.mailbox_address.empty();
    files->private_area = config.kind != AreaKind::kEcho;
    files->local_area = config.kind == AreaKind::kLocal;
    files->role_read_only =
        config.kind == AreaKind::kBad || config.kind == AreaKind::kDupe || config.kind == AreaKind::kRobots;
    for (size_t i = 0; i < kExtensions.size(); ++i) {
      auto name = relative.filename().string() + std::string(kExtensions[i]);
      int fd = openat(parent.fd, name.c_str(), O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
      if (fd < 0 && (errno == EACCES || errno == EROFS)) {
        files->writable = false;
        fd = openat(parent.fd, name.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
      }
      if (fd < 0)
        return std::unexpected(CatalogError::kInvalidConfiguration);
      files->descriptors[i] = fd;
      if (fstat(fd, &files->identities[i]) != 0 || !S_ISREG(files->identities[i].st_mode) ||
          (!config.mailbox_address.empty() && files->identities[i].st_nlink != 1) ||
          (catalog->coordination_ && catalog->coordination_->Matches(files->identities[i])))
        return std::unexpected(CatalogError::kInvalidConfiguration);
    }
    if (!config.mailbox_address.empty()) {
      std::array<uint8_t, 1024> bytes{};
      if (pread(files->descriptors[0], bytes.data(), bytes.size(), 0) != 1024)
        return std::unexpected(CatalogError::kInvalidConfiguration);
      const auto header = msgapi::jam_wire::Decode(bytes);
      const auto& identity = files->identities[0];
      const auto generation = std::to_string(identity.st_dev) + ":" + std::to_string(identity.st_ino) + ":" +
                              std::to_string(header.date_created) + ":" + std::to_string(header.base_msg_num);
      std::string identities;
      for (const auto& file : files->identities)
        identities += std::to_string(file.st_dev) + ":" + std::to_string(file.st_ino) + ";";
      if (generation != config.mailbox_generation || identities != config.mailbox_files)
        return std::unexpected(CatalogError::kInvalidConfiguration);
    }
    const auto key = std::pair{files->identities[0].st_dev, files->identities[0].st_ino};
    auto [entry, inserted] = physical.emplace(key, files);
    if (!inserted) {
      if (entry->second->forced_encoding != files->forced_encoding || entry->second->personal_mailbox ||
          files->personal_mailbox || entry->second->private_area != files->private_area)
        return std::unexpected(CatalogError::kInvalidConfiguration);
      // A local alias of a netmail base cannot promise local-only publication.
      entry->second->role_read_only |= files->role_read_only || entry->second->local_area != files->local_area;
      for (size_t i = 1; i < kExtensions.size(); ++i)
        if (!SameFile(entry->second->identities[i], files->identities[i]))
          return std::unexpected(CatalogError::kInvalidConfiguration);
      files = entry->second;
    }
    catalog->areas_.emplace(id, JamArea{config, relative, files});
  }
  if (matched_overrides.size() != encoding_overrides.size())
    return std::unexpected(CatalogError::kInvalidConfiguration);
  return catalog;
}

std::expected<const JamArea*, CatalogError> JamCatalog::Resolve(std::string_view id) const {
  auto entry = areas_.find(id);
  if (entry == areas_.end())
    return std::unexpected(CatalogError::kNotFound);
  const auto& area = entry->second;
  if (!area.files)
    return std::unexpected(CatalogError::kUnsupportedFormat);
  Directory parent{OpenParent(root_fd_, area.relative_filename)};
  if (parent.fd < 0)
    return std::unexpected(CatalogError::kChangedBase);
  for (size_t i = 0; i < kExtensions.size(); ++i) {
    auto name = area.relative_filename.filename().string() + std::string(kExtensions[i]);
    struct stat current{};
    if (fstatat(parent.fd, name.c_str(), &current, AT_SYMLINK_NOFOLLOW) != 0 || !S_ISREG(current.st_mode) ||
        !SameFile(current, area.files->identities[i]) || (area.files->personal_mailbox && current.st_nlink != 1))
      return std::unexpected(CatalogError::kChangedBase);
  }
  return &area;
}
}  // namespace fidoback::storage
