#include "storage/point_mailbox.hpp"

#include <fcntl.h>
#include <unistd.h>

#include <ctime>

#include "JamMessageBase.h"
#include "domain/ftn_address.hpp"

namespace fidoback::storage {
namespace {
constexpr std::array<const char*, 3> extensions{".jhr", ".jdt", ".jdx"};
struct Directory {
  int fd = -1;
  ~Directory() {
    if (fd >= 0)
      close(fd);
  }
};
std::expected<MailboxBinding, domain::ApiError> Identity(int parent, const PointMailboxConfig& point) {
  struct stat info{};
  const auto name = point.jam_base.filename().string() + ".jhr";
  int fd = openat(parent, name.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  if (fd < 0)
    return std::unexpected(domain::ApiError::Server("Mailbox identity unavailable"));
  std::array<uint8_t, 1024> header{};
  const bool valid = fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_nlink == 1 &&
                     pread(fd, header.data(), header.size(), 0) == 1024;
  close(fd);
  if (!valid)
    return std::unexpected(domain::ApiError::Server("Mailbox identity unavailable"));
  const auto base = msgapi::jam_wire::Decode(header);
  if (base.signature != msgapi::kJamSignature)
    return std::unexpected(domain::ApiError::Server("Mailbox identity unavailable"));
  std::string files;
  for (const auto* extension : extensions) {
    struct stat file{};
    if (fstatat(parent, (point.jam_base.filename().string() + extension).c_str(), &file, AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISREG(file.st_mode) || file.st_nlink != 1)
      return std::unexpected(domain::ApiError::Server("Mailbox identity unavailable"));
    files += std::to_string(file.st_dev) + ":" + std::to_string(file.st_ino) + ";";
  }
  return MailboxBinding{point.address, point.jam_base.generic_string(),
                        std::to_string(info.st_dev) + ":" + std::to_string(info.st_ino) + ":" +
                            std::to_string(base.date_created) + ":" + std::to_string(base.base_msg_num),
                        files};
}
}  // namespace
std::string MailboxId(std::string_view address) {
  std::string id = "@ffido/mailbox/";
  constexpr char hex[] = "0123456789abcdef";
  for (unsigned char c : address) {
    id += hex[c >> 4];
    id += hex[c & 15];
  }
  return id;
}
std::expected<void, domain::ApiError> ProvisionMailbox(const std::filesystem::path& root,
                                                       const PointMailboxConfig& point, IMetadataStore& metadata) {
  const auto failure = [] {
    return std::unexpected(
        domain::ApiError{domain::ErrorCode::kPrecondition, "Mailbox provisioning requires administrator review", {}});
  };
  auto address = domain::CanonicalFtnAddress(point.address);
  if (!address || *address != point.address || point.address.find('.') == std::string::npos || point.jam_base.empty() ||
      point.jam_base.is_absolute())
    return failure();
  for (const auto& part : point.jam_base)
    if (part == "." || part == ".." || part.empty())
      return failure();
  Directory parent{open(std::filesystem::canonical(root).c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)};
  if (parent.fd < 0)
    return failure();
  for (const auto& part : point.jam_base.parent_path()) {
    // Provisioning may create directories, but never follows their symlink aliases.
    const int created = mkdirat(parent.fd, part.c_str(), 0700);
    if ((created != 0 && errno != EEXIST) || (created == 0 && fsync(parent.fd) != 0))
      return failure();
    int next = openat(parent.fd, part.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (next < 0)
      return failure();
    close(parent.fd);
    parent.fd = next;
  }
  auto bindings = metadata.MailboxBindings();
  if (!bindings)
    return std::unexpected(bindings.error());
  for (const auto& binding : *bindings) {
    if (binding.address != point.address && binding.base != point.jam_base.generic_string())
      continue;
    auto current = Identity(parent.fd, point);
    if (!current || binding.address != point.address || binding.base != current->base ||
        binding.generation != current->generation || binding.files != current->files)
      return failure();
    for (const auto* extension : extensions) {
      struct stat info{};
      if (fstatat(parent.fd, (point.jam_base.filename().string() + extension).c_str(), &info, AT_SYMLINK_NOFOLLOW) !=
              0 ||
          !S_ISREG(info.st_mode) || info.st_nlink != 1)
        return failure();
    }
    return {};
  }
  for (const auto* extension : extensions) {
    struct stat info{};
    if (fstatat(parent.fd, (point.jam_base.filename().string() + extension).c_str(), &info, AT_SYMLINK_NOFOLLOW) == 0 ||
        errno != ENOENT)
      return failure();
  }
  // A crash before binding leaves unassigned files; a retry refuses them rather than guessing ownership.
  for (size_t i = 0; i < extensions.size(); ++i) {
    const auto name = point.jam_base.filename().string() + extensions[i];
    int fd = openat(parent.fd, name.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0)
      return failure();
    bool valid = true;
    if (i == 0) {
      msgapi::JamBaseHeader header{};
      header.signature = msgapi::kJamSignature;
      header.date_created = static_cast<uint32_t>(time(nullptr));
      header.base_msg_num = 1;
      header.password_crc = UINT32_MAX;
      auto bytes = msgapi::jam_wire::Encode(header);
      valid = write(fd, bytes.data(), bytes.size()) == static_cast<ssize_t>(bytes.size());
    }
    valid = valid && fsync(fd) == 0;
    close(fd);
    if (!valid)
      return failure();
  }
  if (fsync(parent.fd) != 0)
    return failure();
  auto identity = Identity(parent.fd, point);
  if (!identity)
    return std::unexpected(identity.error());
  return metadata.BindMailbox(*identity);
}
std::expected<std::vector<EchoAreaConfig>, domain::ApiError> MailboxAreas(const PointMailConfig& config,
                                                                          IMetadataStore& metadata) {
  std::vector<EchoAreaConfig> areas;
  if (!config.enabled)
    return areas;
  auto bindings = metadata.MailboxBindings();
  if (!bindings)
    return std::unexpected(bindings.error());
  for (const auto& point : config.points) {
    const auto found = std::find_if(bindings->begin(), bindings->end(), [&](const auto& binding) {
      return binding.address == point.address && binding.base == point.jam_base.generic_string();
    });
    if (found == bindings->end())
      return std::unexpected(domain::ApiError::Server("Mailbox is not provisioned"));
    EchoAreaConfig area;
    area.name = point.address;
    area.filename = point.jam_base.string();
    area.kind = AreaKind::kNetmail;
    area.msgbase_type = "JAM";
    area.aka = point.address;
    area.description = "Моя почта";
    area.mailbox_address = point.address;
    area.mailbox_generation = found->generation;
    area.mailbox_files = found->files;
    areas.push_back(std::move(area));
  }
  return areas;
}
}  // namespace fidoback::storage
