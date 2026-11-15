#include <fcntl.h>
#include <gtest/gtest.h>
#include <poll.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <fstream>
#include <future>
#include <iostream>
#include <nlohmann/json.hpp>
#include <thread>
#include <vector>

#include "../support/temp_directory.hpp"
#include "service/request_context.hpp"
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

TEST(Coordination, ExclusiveProbeUnderSustainedReadersHasBoundedTestLifetime) {
  fidoback::test::TempDirectory temp;
  const auto path = temp.path() / "probe.lock";
  auto coordinator = CoordinationLock::Open(path);
  ASSERT_TRUE(coordinator);
  std::vector<double> samples;
  int timeouts = 0;
  for (int sample = 0; sample < 20; ++sample) {
    int ready[2], result[2];
    ASSERT_EQ(pipe(ready), 0);
    ASSERT_EQ(pipe(result), 0);
    const auto child = fork();
    ASSERT_GE(child, 0);
    if (child == 0) {
      close(ready[1]);
      close(result[0]);
      char command;
      if (read(ready[0], &command, 1) != 1)
        _exit(2);
      const int fd = open(path.c_str(), O_RDWR);
      const auto begin = std::chrono::steady_clock::now();
      bool acquired = false;
      while (std::chrono::steady_clock::now() - begin < 200ms) {
        if (fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0) {
          acquired = true;
          break;
        }
        poll(nullptr, 0, 1);
      }
      const double output[2] = {
          acquired ? 1.0 : 0.0,
          std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - begin).count()};
      const auto written = write(result[1], output, sizeof(output));
      if (fd >= 0)
        close(fd);
      _exit(written == sizeof(output) ? 0 : 3);
    }
    close(ready[0]);
    close(result[1]);
    std::atomic<bool> done = false;
    std::atomic<int> started = 0;
    std::vector<std::thread> readers;
    for (int i = 0; i < 4; ++i)
      readers.emplace_back([&] {
        auto first = (*coordinator)->Shared(std::chrono::steady_clock::now() + 1s);
        ++started;
        if (first)
          poll(nullptr, 0, 2);
        if (first)
          first->reset();
        while (!done.load()) {
          auto lease = (*coordinator)->Shared(std::chrono::steady_clock::now() + 1s);
          if (lease)
            poll(nullptr, 0, 1);
        }
      });
    while (started.load() != 4)
      std::this_thread::yield();
    const char command = 'x';
    EXPECT_EQ(write(ready[1], &command, 1), 1);
    close(ready[1]);
    double observed[2]{};
    const auto count = read(result[0], observed, sizeof(observed));
    close(result[0]);
    done = true;
    for (auto& reader : readers)
      reader.join();
    int status = 0;
    EXPECT_EQ(waitpid(child, &status, 0), child);
    EXPECT_TRUE(WIFEXITED(status));
    ASSERT_EQ(count, sizeof(observed));
    samples.push_back(observed[1]);
    if (observed[0] == 0)
      ++timeouts;
  }
  std::sort(samples.begin(), samples.end());
  std::cout << "COORDINATION_BENCH "
            << nlohmann::json{{"samples", samples},     {"timeouts", timeouts}, {"readers", 4},
                              {"probe_budget_ms", 200}, {"p50_ms", samples[9]}, {"p95_ms", samples[18]}}
                   .dump()
            << '\n';
  const int exclusive = open(path.c_str(), O_RDWR);
  ASSERT_GE(exclusive, 0);
  EXPECT_EQ(flock(exclusive, LOCK_EX | LOCK_NB), 0);
  close(exclusive);
}

TEST(RequestLock, DoesNotAcquireAfterCancellationOrDeadline) {
  using namespace fidoback::service;
  std::timed_mutex mutex;
  std::stop_source stop;
  stop.request_stop();
  for (const auto& budget : {RequestBudget{std::chrono::steady_clock::now() + 5s, stop.get_token()},
                             RequestBudget{std::chrono::steady_clock::now() - 1ms, {}}}) {
    RequestScope scope(budget);
    std::unique_lock lock(mutex, std::defer_lock);
    EXPECT_FALSE(AcquireRequestLock(lock));
    EXPECT_FALSE(lock.owns_lock());
  }
  std::stop_source after_acquisition;
  RequestBudget active{std::chrono::steady_clock::now() + 5s, after_acquisition.get_token()};
  RequestScope scope(active);
  std::unique_lock lock(mutex, std::defer_lock);
  EXPECT_TRUE(AcquireRequestLock(lock));
  after_acquisition.request_stop();
  EXPECT_FALSE(RequestActive());
  EXPECT_TRUE(lock.owns_lock());  // Cancellation cannot expose a half-finished critical section.
}
TEST(RequestLock, ContentionDoesNotResetTheAbsoluteDeadline) {
  using namespace fidoback::service;
  std::timed_mutex mutex;
  std::unique_lock owner(mutex);
  const auto deadline = std::chrono::steady_clock::now() + 50ms;
  auto waiter = std::async(std::launch::async, [&] {
    RequestBudget budget{deadline, {}};
    RequestScope scope(budget);
    std::unique_lock lock(mutex, std::defer_lock);
    return std::pair{AcquireRequestLock(lock), std::chrono::steady_clock::now()};
  });
  const auto ready = waiter.wait_for(1s);
  owner.unlock();
  const auto [acquired, finished] = waiter.get();
  EXPECT_EQ(ready, std::future_status::ready);
  EXPECT_FALSE(acquired);
  EXPECT_GE(finished, deadline);
}
