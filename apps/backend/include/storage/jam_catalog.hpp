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
#include "storage/jam_encoding_corrections.hpp"

namespace fidoback::storage {
class CoordinationLock;

enum class CatalogError { kInvalidConfiguration, kNotFound, kChangedBase, kIo, kResource, kUnsupportedFormat };

// One physical owner serializes open/lock/unlock/close, including aliases and catalogs.
// Descriptors are borrowed only while a JamLease holds mutex.
struct JamFiles {
  std::array<int, 3> descriptors{-1, -1, -1};
  std::array<struct stat, 3> identities{};
  std::filesystem::path root_path, relative_path;
  struct stat root_identity{};
  std::expected<void, CatalogError> Open();  // Requires mutex.
  void Close();                              // Requires mutex; unlock byte lock first.
  bool private_area = false;
  bool personal_mailbox = false;
  bool local_area = false;
  std::atomic<bool> role_read_only{false};
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
  std::string forced_encoding;
  std::shared_ptr<const JamEncodingCorrectionIndex> encoding_corrections{};
};

struct CatalogDiagnostic {
  std::string area;
  int system_error = 0;
};

class JamCatalog {
public:
  static std::expected<std::unique_ptr<JamCatalog>, CatalogError> Build(
      const std::filesystem::path& root, const std::vector<EchoAreaConfig>& areas,
      std::shared_ptr<CoordinationLock> coordination = {},
      const std::map<std::string, std::string>& encoding_overrides = {}, CatalogDiagnostic* diagnostic = nullptr);
  // Bind before publishing the catalog to readers.
  std::expected<void, std::string> BindEncodingCorrections(JamEncodingCorrections manifest);
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
