#include "storage/coordination_lock.hpp"

#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <condition_variable>
#include <mutex>
namespace fidoback::storage {
CoordinationLease::~CoordinationLease() {
  close(fd_);
}
std::expected<std::shared_ptr<CoordinationLock>, CoordinationError> CoordinationLock::Open(
    const std::filesystem::path& path) {
  if (path.empty() || path.string().find('\0') != std::string::npos)
    return std::unexpected(CoordinationError::kIo);
  std::error_code error;
  auto absolute = std::filesystem::absolute(path, error);
  if (error)
    return std::unexpected(CoordinationError::kIo);
  int fd = open(absolute.c_str(), O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0600);
  if (fd < 0)
    return std::unexpected(CoordinationError::kIo);
  struct stat identity{};
  const bool valid = fstat(fd, &identity) == 0 && S_ISREG(identity.st_mode);
  close(fd);
  if (!valid)
    return std::unexpected(CoordinationError::kIo);
  return std::shared_ptr<CoordinationLock>(new CoordinationLock(absolute, identity));
}
CoordinationLock::~CoordinationLock() {
  if (inherited_fd_ >= 0)
    close(inherited_fd_);
}
std::expected<std::shared_ptr<CoordinationLock>, CoordinationError> CoordinationLock::Inherit(
    const std::filesystem::path& path, int fd) {
  auto lock = Open(path);
  if (!lock)
    return std::unexpected(lock.error());
  struct stat file{};
  if (fd < 0 || fstat(fd, &file) != 0 || !S_ISREG(file.st_mode) || !(*lock)->Matches(file) ||
      (fcntl(fd, F_GETFL) & O_ACCMODE) != O_RDWR || flock(fd, LOCK_EX | LOCK_NB) != 0)
    return std::unexpected(CoordinationError::kChanged);
  const int owned = fcntl(fd, F_DUPFD_CLOEXEC, 3);
  if (owned < 0)
    return std::unexpected(CoordinationError::kIo);
  (*lock)->inherited_fd_ = owned;
  return lock;
}
std::expected<std::unique_ptr<CoordinationLease>, CoordinationError> CoordinationLock::Shared(
    JamDeadline deadline, std::stop_token cancellation) const {
  if (inherited_fd_ >= 0) {
    if (cancellation.stop_requested())
      return std::unexpected(CoordinationError::kCancelled);
    if (std::chrono::steady_clock::now() >= deadline)
      return std::unexpected(CoordinationError::kTimeout);
    struct stat identity{};
    struct stat current{};
    if (fstat(inherited_fd_, &identity) != 0 || !Matches(identity) || lstat(path_.c_str(), &current) != 0 ||
        !S_ISREG(current.st_mode) || !Matches(current))
      return std::unexpected(CoordinationError::kChanged);
    const int fd = fcntl(inherited_fd_, F_DUPFD_CLOEXEC, 3);
    if (fd < 0)
      return std::unexpected(CoordinationError::kIo);
    return std::unique_ptr<CoordinationLease>(new CoordinationLease(fd));
  }
  int fd = open(path_.c_str(), O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (fd < 0)
    return std::unexpected(CoordinationError::kChanged);
  auto lease = std::unique_ptr<CoordinationLease>(new CoordinationLease(fd));
  struct stat identity{};
  if (fstat(fd, &identity) != 0 || !S_ISREG(identity.st_mode) || identity.st_dev != identity_.st_dev ||
      identity.st_ino != identity_.st_ino)
    return std::unexpected(CoordinationError::kChanged);
  std::mutex mutex;
  std::condition_variable wake;
  std::stop_callback stop(cancellation, [&] { wake.notify_all(); });
  for (;;) {
    if (cancellation.stop_requested())
      return std::unexpected(CoordinationError::kCancelled);
    auto now = std::chrono::steady_clock::now();
    if (now >= deadline)
      return std::unexpected(CoordinationError::kTimeout);
    if (flock(fd, LOCK_SH | LOCK_NB) == 0)
      return lease;
    if (errno == EINTR)
      continue;
    if (errno != EWOULDBLOCK && errno != EAGAIN)
      return std::unexpected(CoordinationError::kIo);
    std::unique_lock lock(mutex);
    wake.wait_until(lock, std::min(deadline, now + std::chrono::milliseconds(10)),
                    [&] { return cancellation.stop_requested(); });
  }
}
}  // namespace fidoback::storage
