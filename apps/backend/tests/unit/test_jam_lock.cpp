#include <fcntl.h>
#include <gtest/gtest.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include <fstream>
#include <future>
#include <thread>

#include "../support/temp_directory.hpp"
#include "storage/jam_lock.hpp"

using namespace fidoback::storage;
namespace {
using namespace std::chrono_literals;
EchoAreaConfig Config(std::string name, std::string filename) {
  EchoAreaConfig result;
  result.name = std::move(name);
  result.filename = std::move(filename);
  result.msgbase_type = "JAM";
  return result;
}
void Files(const std::filesystem::path& path) {
  for (const char* extension : {".jhr", ".jdt", ".jdx"}) {
    std::ofstream output(path.string() + extension);
    output << "unchanged";
  }
}
// Child uses only async-signal-safe POSIX functions after fork. A pipe is the barrier.
class ChildLock {
public:
  ChildLock(const std::filesystem::path& path, short type, bool keep = true) {
    const auto filename = path.string();
    int ready[2], release[2];
    if (pipe(ready) != 0 || pipe(release) != 0)
      throw std::runtime_error("pipe");
    pid_ = fork();
    if (pid_ < 0)
      throw std::runtime_error("fork");
    if (pid_ == 0) {
      close(ready[0]);
      close(release[1]);
      int fd = open(filename.c_str(), O_RDWR);
      struct flock lock{};
      lock.l_type = type;
      lock.l_whence = SEEK_SET;
      lock.l_len = 1;
      char status = fd >= 0 && fcntl(fd, F_SETLK, &lock) == 0 ? 'Y' : 'N';
      if (write(ready[1], &status, 1) != 1)
        _exit(2);
      if (status == 'Y' && keep) {
        char command;
        (void)read(release[0], &command, 1);
      }
      if (fd >= 0)
        close(fd);
      _exit(0);
    }
    close(ready[1]);
    close(release[0]);
    release_ = release[1];
    char status = 0;
    const auto count = read(ready[0], &status, 1);
    close(ready[0]);
    locked = count == 1 && status == 'Y';
  }
  ~ChildLock() {
    Release();
  }
  void Kill() {
    if (pid_ >= 0)
      ::kill(pid_, SIGKILL);
    Release();
  }
  void Release() {
    if (pid_ < 0)
      return;
    close(release_);
    release_ = -1;
    int status;
    while (waitpid(pid_, &status, 0) < 0 && errno == EINTR) {
    }
    pid_ = -1;
  }
  bool locked = false;

private:
  pid_t pid_ = -1;
  int release_ = -1;
};
}  // namespace

TEST(JamLock, ExternalWriterTimeoutAndCancellationDoNotMutate) {
  fidoback::test::TempDirectory temp;
  Files(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  auto owner = (*catalog)->Resolve("echo").value()->files;
  ChildLock other(temp.path() / "base.jhr", F_WRLCK);
  ASSERT_TRUE(other.locked);
  auto expired = JamLease::Acquire(owner, true, std::chrono::steady_clock::now() + 20ms);
  ASSERT_FALSE(expired);
  EXPECT_EQ(expired.error(), JamLockError::kTimeout);
  std::stop_source cancel;
  cancel.request_stop();
  auto stopped = JamLease::Acquire(owner, true, std::chrono::steady_clock::now() + 1s, cancel.get_token());
  ASSERT_FALSE(stopped);
  EXPECT_EQ(stopped.error(), JamLockError::kCancelled);
  char bytes[9];
  ASSERT_EQ(pread(owner->descriptors[0], bytes, sizeof(bytes), 0), 9);
  EXPECT_EQ(std::string(bytes, sizeof(bytes)), "unchanged");
  other.Release();
  EXPECT_TRUE(JamLease::Acquire(owner, true, std::chrono::steady_clock::now() + 1s));
}

TEST(JamLock, ReadLockSharesExternallyAndBlocksExternalWriteAcrossResolve) {
  fidoback::test::TempDirectory temp;
  Files(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  auto owner = (*catalog)->Resolve("echo").value()->files;
  auto lease = JamLease::Acquire(owner, false, std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(lease);
  for (int i = 0; i < 4; ++i)
    EXPECT_TRUE((*catalog)->Resolve("echo"));
  {
    ChildLock writer(temp.path() / "base.jhr", F_WRLCK, false);
    EXPECT_FALSE(writer.locked);
  }
  {
    ChildLock reader(temp.path() / "base.jhr", F_RDLCK, false);
    EXPECT_TRUE(reader.locked);
  }
  lease->reset();
  ChildLock writer(temp.path() / "base.jhr", F_WRLCK, false);
  EXPECT_TRUE(writer.locked);
}

TEST(JamLock, AliasesSerializeAndDifferentBasesRemainIndependent) {
  fidoback::test::TempDirectory temp;
  Files(temp.path() / "first");
  Files(temp.path() / "second");
  for (const char* extension : {".jhr", ".jdt", ".jdx"})
    std::filesystem::create_hard_link((temp.path() / "first").string() + extension,
                                      (temp.path() / "alias").string() + extension);
  auto catalog =
      JamCatalog::Build(temp.path(), {Config("A", "first"), Config("alias", "alias"), Config("B", "second")});
  ASSERT_TRUE(catalog);
  auto a = (*catalog)->Resolve("A").value()->files;
  auto alias = (*catalog)->Resolve("alias").value()->files;
  EXPECT_EQ(a, alias);
  auto lease = JamLease::Acquire(a, true, std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(lease);
  auto wait = std::async(std::launch::async,
                         [&] { return JamLease::Acquire(alias, false, std::chrono::steady_clock::now() + 30ms); });
  auto b = (*catalog)->Resolve("B").value()->files;
  EXPECT_TRUE(JamLease::Acquire(b, true, std::chrono::steady_clock::now() + 1s));
  auto blocked = wait.get();
  ASSERT_FALSE(blocked);
  EXPECT_EQ(blocked.error(), JamLockError::kTimeout);
  lease->reset();
  EXPECT_TRUE(JamLease::Acquire(alias, true, std::chrono::steady_clock::now() + 1s));
}

TEST(JamLock, CancellationDuringMutexWaitAndOwnerLifetime) {
  fidoback::test::TempDirectory temp;
  Files(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  auto owner = (*catalog)->Resolve("echo").value()->files;
  auto lease = JamLease::Acquire(owner, true, std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(lease);
  std::stop_source stop;
  std::promise<void> started;
  auto wait = std::async(std::launch::async, [&] {
    started.set_value();
    return JamLease::Acquire(owner, false, std::chrono::steady_clock::now() + 1s, stop.get_token());
  });
  started.get_future().wait();
  stop.request_stop();
  auto cancelled = wait.get();
  ASSERT_FALSE(cancelled);
  EXPECT_EQ(cancelled.error(), JamLockError::kCancelled);
  const int fd = owner->descriptors[0];
  owner.reset();
  catalog->reset();
  EXPECT_GE(fcntl(fd, F_GETFD), 0);
  lease->reset();
  EXPECT_EQ(fcntl(fd, F_GETFD), -1);
}

TEST(JamLock, InstanceLockRejectsSecondOwnerAndSymlink) {
  fidoback::test::TempDirectory temp;
  const auto path = temp.path() / "backend.lock";
  auto first = BackendInstanceLock::Acquire(path);
  ASSERT_TRUE(first);
  auto second = BackendInstanceLock::Acquire(path);
  ASSERT_FALSE(second);
  EXPECT_EQ(second.error(), JamLockError::kTimeout);
  first->reset();
  EXPECT_TRUE(BackendInstanceLock::Acquire(path));
  std::filesystem::create_symlink(path, temp.path() / "alias");
  EXPECT_FALSE(BackendInstanceLock::Acquire(temp.path() / "alias"));
}

TEST(JamLock, InvalidReadonlyAndExpiredRequestsFail) {
  EXPECT_FALSE(JamLease::Acquire({}, true, std::chrono::steady_clock::now() + 1s));
  auto owner = std::make_shared<JamFiles>();
  owner->descriptors[0] = -1;
  EXPECT_FALSE(JamLease::Acquire(owner, true, std::chrono::steady_clock::now() + 1s));
  EXPECT_FALSE(BackendInstanceLock::Acquire({}));
  fidoback::test::TempDirectory temp;
  Files(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  owner = (*catalog)->Resolve("echo").value()->files;
  owner->writable = false;
  auto readonly = JamLease::Acquire(owner, true, std::chrono::steady_clock::now() + 1s);
  ASSERT_FALSE(readonly);
  EXPECT_EQ(readonly.error(), JamLockError::kReadOnly);
  auto expired = JamLease::Acquire(owner, false, std::chrono::steady_clock::now());
  ASSERT_FALSE(expired);
  EXPECT_EQ(expired.error(), JamLockError::kTimeout);
}

#include "storage/jam_access.hpp"

namespace {
void EmptyJam(const std::filesystem::path& path) {
  Files(path);
  msgapi::JamBaseHeader header{};
  header.signature = msgapi::kJamSignature;
  header.date_created = 123;
  header.base_msg_num = 42;
  header.password_crc = UINT32_MAX;
  const auto bytes = msgapi::jam_wire::Encode(header);
  std::ofstream output(path.string() + ".jhr", std::ios::binary);
  output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  for (const char* extension : {".jdt", ".jdx"}) {
    std::ofstream empty(path.string() + extension, std::ios::binary);
  }
}
}  // namespace

TEST(JamAccess, BorrowedViewsNeverCloseOwnersOrDropPosixLock) {
  fidoback::test::TempDirectory temp;
  EmptyJam(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  auto owner = (*catalog)->Resolve("echo").value()->files;
  auto access = JamAccess::Open(**catalog, "echo", true, std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(access);
  for (int i = 0; i < 4; ++i) {
    msgapi::JamMessageBase view(owner->descriptors);
    ASSERT_EQ(view.Open(), msgapi::JamError::kSuccess);
    auto numbers = view.GetMessageNumbers();
    ASSERT_TRUE(numbers);
    EXPECT_TRUE(numbers->empty());
    view.Close();
    ChildLock other(temp.path() / "base.jhr", F_WRLCK, false);
    EXPECT_FALSE(other.locked);
  }
  access->reset();
  EXPECT_GE(fcntl(owner->descriptors[0], F_GETFD), 0);
  ChildLock other(temp.path() / "base.jhr", F_WRLCK, false);
  EXPECT_TRUE(other.locked);
}

TEST(JamAccess, RefreshesIndexAndCountersAfterEveryLock) {
  fidoback::test::TempDirectory temp;
  EmptyJam(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  std::string generation;
  {
    auto access = JamAccess::Open(**catalog, "echo", false, std::chrono::steady_clock::now() + 1s);
    ASSERT_TRUE(access);
    generation = (*access)->generation();
    EXPECT_EQ((*access)->messages().message_count(), 0);
  }
  {  // Simulate a cooperating external writer between requests.
    msgapi::JamMessageBase external((temp.path() / "base").string());
    ASSERT_EQ(external.Open(), msgapi::JamError::kSuccess);
    msgapi::JamMessage message;
    message.SetSubject("external");
    ASSERT_EQ(external.AddMessage(message), msgapi::JamError::kSuccess);
  }
  auto access = JamAccess::Open(**catalog, "echo", false, std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(access);
  EXPECT_EQ((*access)->generation(), generation);
  EXPECT_EQ((*access)->messages().message_count(), 1);
  EXPECT_EQ(*(*access)->messages().GetMessageNumbers(), (std::vector<uint32_t>{42}));
  EXPECT_EQ((*access)->messages().ReadMessage(42)->subject(), "external");
}

TEST(JamAccess, ReplacementIsRejectedAndNewCatalogHasNewGeneration) {
  fidoback::test::TempDirectory temp;
  EmptyJam(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  auto original = JamAccess::Open(**catalog, "echo", false, std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(original);
  const auto generation = (*original)->generation();
  original->reset();
  EmptyJam(temp.path() / "new");
  for (const char* extension : {".jhr", ".jdt", ".jdx"})
    std::filesystem::rename((temp.path() / "new").string() + extension, (temp.path() / "base").string() + extension);
  auto stale = JamAccess::Open(**catalog, "echo", false, std::chrono::steady_clock::now() + 1s);
  ASSERT_FALSE(stale);
  EXPECT_EQ(std::get<CatalogError>(stale.error()), CatalogError::kChangedBase);
  catalog->reset();
  catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  auto fresh = JamAccess::Open(**catalog, "echo", false, std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(fresh);
  EXPECT_NE((*fresh)->generation(), generation);
}

TEST(JamAccess, ParallelReadWriteViewsUseOneOwner) {
  fidoback::test::TempDirectory temp;
  EmptyJam(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  std::vector<std::future<bool>> work;
  for (unsigned i = 0; i < 4; ++i)
    work.push_back(std::async(std::launch::async, [&, i] {
      for (unsigned n = 0; n < 20; ++n) {
        auto access = JamAccess::Open(**catalog, "echo", i == 0, std::chrono::steady_clock::now() + 2s);
        if (!access)
          return false;
        if (i == 0) {
          msgapi::JamMessage message;
          message.SetSubject(std::to_string(n));
          if ((*access)->messages().AddMessage(message) != msgapi::JamError::kSuccess)
            return false;
        } else {
          auto numbers = (*access)->messages().GetMessageNumbers();
          if (!numbers || numbers->size() != (*access)->messages().message_count())
            return false;
          for (auto number : *numbers)
            if (!(*access)->messages().ReadMessage(number))
              return false;
        }
      }
      return true;
    }));
  for (auto& item : work)
    EXPECT_TRUE(item.get());
  auto access = JamAccess::Open(**catalog, "echo", false, std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(access);
  EXPECT_EQ((*access)->messages().message_count(), 20);
}

TEST(JamLock, KilledExternalWriterReleasesLock) {
  fidoback::test::TempDirectory temp;
  Files(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  ChildLock child(temp.path() / "base.jhr", F_WRLCK);
  ASSERT_TRUE(child.locked);
  child.Kill();
  EXPECT_TRUE(
      JamLease::Acquire((*catalog)->Resolve("echo").value()->files, true, std::chrono::steady_clock::now() + 1s));
}

TEST(JamLock, CancellationDuringExternalLockWait) {
  fidoback::test::TempDirectory temp;
  Files(temp.path() / "base");
  auto catalog = JamCatalog::Build(temp.path(), {Config("echo", "base")});
  ASSERT_TRUE(catalog);
  auto owner = (*catalog)->Resolve("echo").value()->files;
  ChildLock child(temp.path() / "base.jhr", F_WRLCK);
  ASSERT_TRUE(child.locked);
  std::stop_source stop;
  std::promise<void> started;
  auto wait = std::async(std::launch::async, [&] {
    started.set_value();
    return JamLease::Acquire(owner, true, std::chrono::steady_clock::now() + 1s, stop.get_token());
  });
  started.get_future().wait();
  stop.request_stop();
  auto cancelled = wait.get();
  ASSERT_FALSE(cancelled);
  EXPECT_EQ(cancelled.error(), JamLockError::kCancelled);
  child.Release();
  EXPECT_TRUE(JamLease::Acquire(owner, true, std::chrono::steady_clock::now() + 1s));
}

TEST(JamFile, BorrowedCloseInvalidatesViewWithoutClosingOwner) {
  fidoback::test::TempDirectory temporary;
  const auto path = temporary.path() / "file";
  const int descriptor = open(path.c_str(), O_CREAT | O_RDWR, 0600);
  ASSERT_GE(descriptor, 0);
  {
    msgapi::JamFile borrowed(descriptor);
    ASSERT_TRUE(borrowed.is_open());
    borrowed.close();
    EXPECT_FALSE(borrowed.is_open());
    EXPECT_GE(fcntl(descriptor, F_GETFD), 0);
    char byte{};
    borrowed.read(&byte, 1);
    EXPECT_TRUE(borrowed.fail());
  }
  EXPECT_GE(fcntl(descriptor, F_GETFD), 0);
  close(descriptor);
}

TEST(JamFile, PositionalSeekMoveAndErrorsPreserveFileContents) {
  fidoback::test::TempDirectory temporary;
  const auto path = temporary.path() / "file";
  {
    std::ofstream output(path);
    output << "abcdef";
  }
  msgapi::JamFile file;
  file.open(path.string(), std::ios::in | std::ios::out);
  ASSERT_TRUE(file.is_open());
  file.seekg(-2, std::ios::end);
  char bytes[2]{};
  file.read(bytes, 2);
  EXPECT_EQ(std::string(bytes, 2), "ef");
  file.seekg(-2, std::ios::cur);
  EXPECT_EQ(file.tellg(), std::streampos(4));
  file.seekp(1);
  file.write("XY", 2);
  EXPECT_EQ(file.tellp(), std::streampos(3));
  file.flush();
  msgapi::JamFile moved(std::move(file));
  EXPECT_TRUE(moved.is_open());
  auto* same_view = &moved;
  moved = std::move(*same_view);
  EXPECT_TRUE(moved.is_open());
  moved.seekg(-1);
  EXPECT_TRUE(moved.fail());
  EXPECT_EQ(moved.tellg(), std::streampos(-1));
  moved.seekp(0);
  moved.write("Z", 1);
  moved.clear();
  moved.seekg(0);
  moved.read(bytes, -1);
  EXPECT_TRUE(moved.fail());
  moved.clear();
  moved.write("Z", -1);
  EXPECT_TRUE(moved.fail());
  moved.clear();
  moved.seekp(std::numeric_limits<std::streamoff>::max());
  moved.seekp(1, std::ios::cur);
  EXPECT_TRUE(moved.fail());
  EXPECT_EQ(moved.tellp(), std::streampos(-1));
  moved.close();
  moved.seekg(0, std::ios::end);
  EXPECT_TRUE(moved.fail());
  moved.open((temporary.path() / "absent").string(), std::ios::in);
  EXPECT_FALSE(moved.is_open());
  EXPECT_TRUE(moved.fail());
  std::ifstream input(path);
  EXPECT_EQ(std::string(std::istreambuf_iterator<char>(input), {}), "aXYdef");
}
