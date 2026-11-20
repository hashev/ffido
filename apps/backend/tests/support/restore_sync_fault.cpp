#include <fcntl.h>
#include <limits.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#ifndef __APPLE__
#include <dlfcn.h>
#endif

namespace {
bool Fault(int fd) {
  const auto* root = std::getenv("FFIDO_TEST_RESTORE_ROOT");
  const auto* stage = std::getenv("FFIDO_TEST_RESTORE_STAGE");
  if (!root || !stage)
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
  const auto* name = path + length + 1;
  const bool readonly = (fcntl(fd, F_GETFL) & O_ACCMODE) == O_RDONLY;
  // Match the explicit verification FDs, not SQLite's own directory/journal syncs.
  const bool match = (std::strcmp(stage, "before-commit") == 0 && readonly &&
                      std::strncmp(name, ".ffido-restore-", 15) == 0 && std::strstr(name, ".db")) ||
                     (std::strcmp(stage, "after-commit") == 0 && readonly && std::strcmp(name, "metadata.db") == 0) ||
                     (std::strcmp(stage, "transaction") == 0 && std::strcmp(name, "metadata.db-wal") == 0);
  if (!match)
    return false;
  const auto* action = std::getenv("FFIDO_TEST_RESTORE_ACTION");
  if (action && std::strcmp(action, "exit") == 0)
    _exit(86);
  return true;
}
}  // namespace
#ifdef __APPLE__
extern "C" int RestoreSync(int fd) {
  if (Fault(fd)) {
    errno = EIO;
    return -1;
  }
  return fsync(fd);
}
__attribute__((used, section("__DATA,__interpose"))) static const struct {
  const void* replacement;
  const void* original;
} interpose_restore_sync = {reinterpret_cast<const void*>(&RestoreSync), reinterpret_cast<const void*>(&fsync)};
#else
extern "C" int fsync(int fd) {
  if (Fault(fd)) {
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
