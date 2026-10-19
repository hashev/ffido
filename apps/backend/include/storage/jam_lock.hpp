#pragma once

#include <chrono>
#include <expected>
#include <memory>
#include <stop_token>

#include "storage/deadline.hpp"
#include "storage/jam_catalog.hpp"

namespace fidoback::storage {
enum class JamLockError { kTimeout, kCancelled, kIo, kReadOnly };

// Holds the physical owner through unlock; no JAM descriptor is opened/closed here.
class JamLease {
public:
  static std::expected<std::unique_ptr<JamLease>, JamLockError> Acquire(std::shared_ptr<JamFiles> owner, bool write,
                                                                        JamDeadline deadline,
                                                                        std::stop_token cancellation = {});
  ~JamLease();
  JamLease(const JamLease&) = delete;
  JamLease& operator=(const JamLease&) = delete;
  JamFiles& files() const {
    return *owner_;
  }

private:
  JamLease(std::shared_ptr<JamFiles> owner, std::unique_lock<std::mutex> lock)
      : owner_(std::move(owner)), process_lock_(std::move(lock)) {
  }
  std::shared_ptr<JamFiles> owner_;
  std::unique_lock<std::mutex> process_lock_;
};

class BackendInstanceLock {
public:
  static std::expected<std::unique_ptr<BackendInstanceLock>, JamLockError> Acquire(const std::filesystem::path& path);
  ~BackendInstanceLock();
  BackendInstanceLock(const BackendInstanceLock&) = delete;
  BackendInstanceLock& operator=(const BackendInstanceLock&) = delete;

private:
  explicit BackendInstanceLock(int fd) : fd_(fd) {
  }
  int fd_;
};
}  // namespace fidoback::storage
