#include <fcntl.h>
#include <gtest/gtest.h>
#include <sys/file.h>
#include <unistd.h>

#include <fstream>
#include <future>

#include "../support/temp_directory.hpp"
#include "storage/jam_access.hpp"
using namespace fidoback::storage;
using namespace std::chrono_literals;

TEST(Coordination, SharedLeaseDescriptionsReleaseIndependently) {
  fidoback::test::TempDirectory temp;
  const auto path = temp.path() / "hpt.lock";
  auto coordinator = CoordinationLock::Open(path);
  ASSERT_TRUE(coordinator);
  auto first = (*coordinator)->Shared(std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(first);
  auto second = (*coordinator)->Shared(std::chrono::steady_clock::now() + 1s);
  ASSERT_TRUE(second);
  const int hpt = open(path.c_str(), O_RDWR);
  ASSERT_GE(hpt, 0);
  EXPECT_EQ(flock(hpt, LOCK_EX | LOCK_NB), -1);
  first->reset();
  EXPECT_EQ(flock(hpt, LOCK_EX | LOCK_NB), -1);
  second->reset();
  EXPECT_EQ(flock(hpt, LOCK_EX | LOCK_NB), 0);
  auto blocked = (*coordinator)->Shared(std::chrono::steady_clock::now() + 20ms);
  ASSERT_FALSE(blocked);
  EXPECT_EQ(blocked.error(), CoordinationError::kTimeout);
  close(hpt);
  EXPECT_TRUE((*coordinator)->Shared(std::chrono::steady_clock::now() + 1s));
}
TEST(Coordination, CancelledAndReplacedLocksAreRejected) {
  fidoback::test::TempDirectory temp;
  const auto path = temp.path() / "hpt.lock";
  auto coordinator = CoordinationLock::Open(path);
  ASSERT_TRUE(coordinator);
  std::stop_source stop;
  stop.request_stop();
  auto cancelled = (*coordinator)->Shared(std::chrono::steady_clock::now() + 1s, stop.get_token());
  ASSERT_FALSE(cancelled);
  EXPECT_EQ(cancelled.error(), CoordinationError::kCancelled);
  {
    std::ofstream replacement(temp.path() / "new.lock");
  }
  std::filesystem::rename(temp.path() / "new.lock", path);
  auto replaced = (*coordinator)->Shared(std::chrono::steady_clock::now() + 1s);
  ASSERT_FALSE(replaced);
  EXPECT_EQ(replaced.error(), CoordinationError::kChanged);
  std::filesystem::create_symlink(path, temp.path() / "alias");
  EXPECT_FALSE(CoordinationLock::Open(temp.path() / "alias"));
  EXPECT_FALSE(CoordinationLock::Open({}));
  EXPECT_FALSE(CoordinationLock::Open(temp.path()));
}
TEST(Coordination, HptLifecycleBlocksAccessWithoutHoldingPhysicalMutex) {
  fidoback::test::TempDirectory temp;
  auto coordination = CoordinationLock::Open(temp.path() / "hpt.lock");
  ASSERT_TRUE(coordination);
  auto base = temp.path() / "base";
  msgapi::JamBaseHeader header{};
  header.signature = msgapi::kJamSignature;
  header.base_msg_num = 1;
  auto bytes = msgapi::jam_wire::Encode(header);
  {
    std::ofstream output(base.string() + ".jhr", std::ios::binary);
    output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  }
  for (auto extension : {".jdt", ".jdx"}) {
    std::ofstream output(base.string() + extension);
  }
  EchoAreaConfig area;
  area.name = "echo";
  area.filename = "base";
  area.msgbase_type = "JAM";
  auto catalog = JamCatalog::Build(temp.path(), {area}, *coordination);
  ASSERT_TRUE(catalog);
  const int hpt = open((temp.path() / "hpt.lock").c_str(), O_RDWR);
  ASSERT_GE(hpt, 0);
  ASSERT_EQ(flock(hpt, LOCK_EX | LOCK_NB), 0);
  auto wait = std::async(std::launch::async, [&] {
    return JamAccess::Open(**catalog, "echo", true, std::chrono::steady_clock::now() + 30ms);
  });
  auto owner = (*catalog)->Resolve("echo").value()->files;
  ASSERT_TRUE(owner->mutex.try_lock());
  owner->mutex.unlock();
  auto timeout = wait.get();
  ASSERT_FALSE(timeout);
  EXPECT_EQ(std::get<CoordinationError>(timeout.error()), CoordinationError::kTimeout);
  EXPECT_EQ(std::filesystem::file_size(base.string() + ".jhr"), 1024);
  close(hpt);
  EXPECT_TRUE(JamAccess::Open(**catalog, "echo", false, std::chrono::steady_clock::now() + 1s));
}

TEST(Coordination, LockCannotAliasJamCompanionFile) {
  fidoback::test::TempDirectory temp;
  for (const char* extension : {".jhr", ".jdt", ".jdx"}) {
    std::ofstream output((temp.path() / "base").string() + extension);
    output << "fixture";
  }
  auto coordination = CoordinationLock::Open(temp.path() / "base.jhr");
  ASSERT_TRUE(coordination);
  EchoAreaConfig area;
  area.name = "echo";
  area.filename = "base";
  area.msgbase_type = "JAM";
  auto catalog = JamCatalog::Build(temp.path(), {area}, *coordination);
  ASSERT_FALSE(catalog);
  EXPECT_EQ(catalog.error(), CatalogError::kInvalidConfiguration);
}

TEST(Coordination, RemovedAndNonregularLockCannotBeReacquired) {
  fidoback::test::TempDirectory temporary;
  const auto path = temporary.path() / "lock";
  EXPECT_FALSE(CoordinationLock::Open(std::filesystem::path(path.string() + std::string("\0other", 6))));
  auto lock = CoordinationLock::Open(path);
  ASSERT_TRUE(lock);
  std::filesystem::remove(path);
  EXPECT_FALSE((*lock)->Shared(std::chrono::steady_clock::now() + 1s));
  std::filesystem::create_directory(path);
  EXPECT_FALSE((*lock)->Shared(std::chrono::steady_clock::now() + 1s));
}

TEST(Coordination, InheritedExclusiveLeaseDoesNotReacquireOrDowngradeLifecycleLock) {
  fidoback::test::TempDirectory temp;
  const auto path = temp.path() / "inherited.lock", other = temp.path() / "other.lock";
  const int fd = open(path.c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
  ASSERT_GE(fd, 0);
  ASSERT_EQ(flock(fd, LOCK_EX | LOCK_NB), 0);
  auto inherited = fidoback::storage::CoordinationLock::Inherit(path, fd);
  ASSERT_TRUE(inherited);
  auto first = (*inherited)->Shared(std::chrono::steady_clock::now() + std::chrono::seconds(1));
  ASSERT_TRUE(first);
  auto second = (*inherited)->Shared(std::chrono::steady_clock::now() + std::chrono::seconds(1));
  ASSERT_TRUE(second);
  const int contender = open(path.c_str(), O_RDWR | O_CLOEXEC);
  ASSERT_GE(contender, 0);
  EXPECT_NE(flock(contender, LOCK_SH | LOCK_NB), 0);
  first->reset();
  second->reset();
  EXPECT_NE(flock(contender, LOCK_SH | LOCK_NB), 0);
  EXPECT_FALSE(fidoback::storage::CoordinationLock::Inherit(other, fd));
  inherited->reset();
  EXPECT_NE(flock(contender, LOCK_SH | LOCK_NB), 0);
  close(fd);
  EXPECT_EQ(flock(contender, LOCK_EX | LOCK_NB), 0);
  close(contender);
}
