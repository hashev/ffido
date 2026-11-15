#include <fcntl.h>
#include <limits.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#ifndef __APPLE__
#include <dlfcn.h>
#endif

namespace {
std::atomic<bool> failed{false};
bool FailSync(int fd) {
  const auto* root = std::getenv("FFIDO_TEST_SYNC_ROOT");
  const auto* stage = std::getenv("FFIDO_TEST_SYNC_STATE");
  if (!root || !*root || !stage || failed.load())
    return false;
  char path[PATH_MAX]{};
#ifdef __APPLE__
  if (fcntl(fd, F_GETPATH, path) != 0)
    return false;
#else
  char link[64];
  std::snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
  const auto size = readlink(link, path, sizeof(path) - 1);
  if (size <= 0)
    return false;
  path[size] = '\0';
#endif
  const auto length = std::strlen(root);
  if (std::strncmp(path, root, length) != 0 || path[length] != '/')
    return false;
  const auto* name = std::strrchr(path, '/');
  if (!name || std::strncmp(name + 1, ".tmp-", 5) != 0)
    return false;
  const int input = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (input < 0)
    return false;
  char text[4096]{};
  const auto read = pread(input, text, sizeof(text) - 1, 0);
  close(input);
  if (read <= 0)
    return false;
  char marker[128];
  std::snprintf(marker, sizeof(marker), "\"state\":\"%s\"", stage);
  return std::strstr(text, marker) && !failed.exchange(true);
}
}  // namespace

#ifdef __APPLE__
extern "C" int FailingSecretSync(int fd) {
  if (FailSync(fd)) {
    errno = EIO;
    return -1;
  }
  return fsync(fd);
}
// Dyld excludes references from this image from its own interposition.
__attribute__((used, section("__DATA,__interpose"))) static const struct {
  const void* replacement;
  const void* original;
} interpose_sync = {reinterpret_cast<const void*>(&FailingSecretSync), reinterpret_cast<const void*>(&fsync)};
#else
extern "C" int fsync(int fd) {
  if (FailSync(fd)) {
    errno = EIO;
    return -1;
  }
  static const auto original = reinterpret_cast<int (*)(int)>(dlsym(RTLD_NEXT, "fsync"));
  if (!original) {
    errno = EIO;
    return -1;
  }
  return original(fd);
}
#endif
