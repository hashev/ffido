#pragma once
#include <sys/stat.h>

#include <expected>
#include <filesystem>
#include <memory>

#include "storage/deadline.hpp"
namespace fidoback::storage {
enum class CoordinationError { kTimeout, kCancelled, kIo, kChanged };
class CoordinationLease {
public:
  ~CoordinationLease();
  CoordinationLease(const CoordinationLease&) = delete;
  CoordinationLease& operator=(const CoordinationLease&) = delete;

private:
  friend class CoordinationLock;
  explicit CoordinationLease(int fd) : fd_(fd) {
  }
  int fd_;
};
class CoordinationLock {
public:
  static std::expected<std::shared_ptr<CoordinationLock>, CoordinationError> Open(const std::filesystem::path& path);
  static std::expected<std::shared_ptr<CoordinationLock>, CoordinationError> Inherit(const std::filesystem::path& path,
                                                                                     int fd);
  ~CoordinationLock();
  bool Matches(const struct stat& file) const {
    return file.st_dev == identity_.st_dev && file.st_ino == identity_.st_ino;
  }
  std::expected<std::unique_ptr<CoordinationLease>, CoordinationError> Shared(JamDeadline deadline,
                                                                              std::stop_token cancellation = {}) const;

private:
  CoordinationLock(std::filesystem::path path, const struct stat& identity)
      : path_(std::move(path)), identity_(identity) {
  }
  std::filesystem::path path_;
  struct stat identity_{};
  int inherited_fd_ = -1;
};
}  // namespace fidoback::storage
