#pragma once

#include <sys/stat.h>

#include <array>
#include <atomic>
#include <expected>
#include <filesystem>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>

#include "EchoAreaConfig.h"

namespace fidoback::storage {
class CoordinationLock;

enum class CatalogError { kInvalidConfiguration, kNotFound, kChangedBase, kIo, kUnsupportedFormat };

// Дескрипторы принадлежат одному объекту на физическую базу. Resolve не открывает
// и не закрывает .jhr: закрытие другого fd того же inode снимает POSIX locks.
struct JamFiles {
  std::array<int, 3> descriptors{-1, -1, -1};
  std::array<struct stat, 3> identities{};
  std::string forced_encoding;
  bool private_area = false;
  bool personal_mailbox = false;
  bool local_area = false;
  bool role_read_only = false;
  std::atomic<bool> writable{true};
  std::atomic<bool> needs_recovery{false};
  std::mutex mutex;
  ~JamFiles();
  JamFiles() = default;
  JamFiles(const JamFiles&) = delete;
  JamFiles& operator=(const JamFiles&) = delete;
};

struct JamArea {
  EchoAreaConfig config;
  std::filesystem::path relative_filename;
  std::shared_ptr<JamFiles> files;
};

class JamCatalog {
public:
  static std::expected<std::unique_ptr<JamCatalog>, CatalogError> Build(
      const std::filesystem::path& root, const std::vector<EchoAreaConfig>& areas,
      std::shared_ptr<CoordinationLock> coordination = {},
      const std::map<std::string, std::string>& encoding_overrides = {});
  ~JamCatalog();
  JamCatalog(const JamCatalog&) = delete;
  JamCatalog& operator=(const JamCatalog&) = delete;
  std::expected<const JamArea*, CatalogError> Resolve(std::string_view id) const;
  const std::shared_ptr<CoordinationLock>& coordination() const {
    return coordination_;
  }
  const std::map<std::string, JamArea, std::less<>>& areas() const {
    return areas_;
  }

private:
  explicit JamCatalog(int root_fd) : root_fd_(root_fd) {
  }
  int root_fd_;
  std::shared_ptr<CoordinationLock> coordination_;
  std::map<std::string, JamArea, std::less<>> areas_;
};

}  // namespace fidoback::storage
