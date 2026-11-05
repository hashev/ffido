#include "storage/jam_lock.hpp"

#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <condition_variable>

#include "storage/work_metrics.hpp"

namespace fidoback::storage {
namespace {
int FileLock(int fd, short type) {
  struct flock request{};
  request.l_type = type;
  request.l_whence = SEEK_SET;
  request.l_start = 0;
  request.l_len = 1;
  int result;
  do {
    result = fcntl(fd, F_SETLK, &request);
  } while (result < 0 && errno == EINTR);
  return result;
}
}  // namespace

std::expected<std::unique_ptr<JamLease>, JamLockError> JamLease::Acquire(std::shared_ptr<JamFiles> owner, bool write,
                                                                         JamDeadline deadline,
                                                                         std::stop_token cancellation) {
  if (!owner || owner->root_path.empty())
    return std::unexpected(JamLockError::kIo);
  if (write && !owner->writable)
    return std::unexpected(JamLockError::kReadOnly);
  std::unique_lock<std::mutex> process_lock(owner->mutex, std::defer_lock);
  constexpr auto interval = std::chrono::milliseconds(10);
  std::mutex wait_mutex;
  std::condition_variable wake;
  std::stop_callback on_cancel(cancellation, [&] { wake.notify_all(); });
  WorkTimer mutex_wait(&WorkMetrics::jam_mutex_wait_ns);
  while (!process_lock.owns_lock()) {
    if (cancellation.stop_requested())
      return std::unexpected(JamLockError::kCancelled);
    auto now = std::chrono::steady_clock::now();
    if (now >= deadline)
      return std::unexpected(JamLockError::kTimeout);
    if (process_lock.try_lock())
      break;
    std::unique_lock wait_lock(wait_mutex);
    wake.wait_until(wait_lock, std::min(deadline, now + interval), [&] { return cancellation.stop_requested(); });
  }
  mutex_wait.Stop();
  auto opened = owner->Open();
  if (!opened) {
    if (opened.error() == CatalogError::kResource)
      return std::unexpected(JamLockError::kResource);
    if (opened.error() == CatalogError::kChangedBase)
      return std::unexpected(JamLockError::kChangedBase);
    return std::unexpected(JamLockError::kIo);
  }
  struct Cleanup {
    JamFiles* owner;
    ~Cleanup() {
      if (owner)
        owner->Close();
    }
  } cleanup{owner.get()};
  if (write && !owner->writable)
    return std::unexpected(JamLockError::kReadOnly);
  WorkTimer byte_lock_wait(&WorkMetrics::jam_byte_lock_wait_ns);
  for (;;) {
    if (cancellation.stop_requested())
      return std::unexpected(JamLockError::kCancelled);
    auto now = std::chrono::steady_clock::now();
    if (now >= deadline)
      return std::unexpected(JamLockError::kTimeout);
    if (FileLock(owner->descriptors[0], write ? F_WRLCK : F_RDLCK) == 0) {
      auto result = std::unique_ptr<JamLease>(new JamLease(owner, std::move(process_lock)));
      cleanup.owner = nullptr;
      return result;
    }
    if (errno != EACCES && errno != EAGAIN)
      return std::unexpected(JamLockError::kIo);
    std::unique_lock wait_lock(wait_mutex);
    wake.wait_until(wait_lock, std::min(deadline, now + interval), [&] { return cancellation.stop_requested(); });
  }
}

JamLease::~JamLease() {
  // process_lock_ remains held until the kernel lock is released.
  if (FileLock(owner_->descriptors[0], F_UNLCK) < 0)
    owner_->writable = false;
  owner_->Close();
}

std::expected<std::unique_ptr<BackendInstanceLock>, JamLockError> BackendInstanceLock::Acquire(
    const std::filesystem::path& path) {
  if (path.empty() || path.string().find('\0') != std::string::npos)
    return std::unexpected(JamLockError::kIo);
  int fd = open(path.c_str(), O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0600);
  if (fd < 0)
    return std::unexpected(JamLockError::kIo);
  struct stat info{};
  if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)) {
    close(fd);
    return std::unexpected(JamLockError::kIo);
  }
  if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
    const auto error = errno == EWOULDBLOCK ? JamLockError::kTimeout : JamLockError::kIo;
    close(fd);
    return std::unexpected(error);
  }
  return std::unique_ptr<BackendInstanceLock>(new BackendInstanceLock(fd));
}
BackendInstanceLock::~BackendInstanceLock() {
  close(fd_);
}
}  // namespace fidoback::storage
