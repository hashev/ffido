#include <gtest/gtest.h>

#include <fstream>

#include "../support/echo_access.hpp"
#include "../support/temp_directory.hpp"
#include "service/message_service.hpp"
#include "storage/jam_writer.hpp"
using namespace fidoback;
using namespace fidoback::storage;
namespace {
using namespace std::chrono_literals;
std::string Contents(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(input), {}};
}
class FaultIo : public JamIo {
public:
  int fail_write = 0, fail_sync = 0, writes = 0, syncs = 0;
  bool partial = false, failed = false, short_writes = false;
  bool interrupt_write = false, interrupt_sync = false, interrupt_truncate = false;
  bool fail_truncate = false;
  int fail_read = 0, fail_stat = 0, reads = 0, stats = 0;
  bool interrupt_read = false, negative_size = false;
  ssize_t Read(int fd, void* data, size_t size, off_t offset) override {
    if (std::exchange(interrupt_read, false)) {
      errno = EINTR;
      return -1;
    }
    if (++reads == fail_read) {
      errno = EIO;
      return -1;
    }
    return JamIo::Read(fd, data, short_writes ? std::min<size_t>(size, 7) : size, offset);
  }
  int Stat(int fd, struct stat* info) override {
    if (++stats == fail_stat) {
      if (!negative_size) {
        errno = EIO;
        return -1;
      }
      const auto result = JamIo::Stat(fd, info);
      info->st_size = -1;
      return result;
    }
    return JamIo::Stat(fd, info);
  }
  ssize_t Write(int fd, const void* data, size_t size, off_t offset) override {
    if (std::exchange(interrupt_write, false)) {
      errno = EINTR;
      return -1;
    }
    if (failed) {
      errno = ENOSPC;
      return -1;
    }
    if (++writes == fail_write) {
      failed = true;
      if (partial && size > 1)
        return JamIo::Write(fd, data, size / 2, offset);
      errno = ENOSPC;
      return -1;
    }
    return JamIo::Write(fd, data, short_writes ? std::min<size_t>(size, 7) : size, offset);
  }
  int Sync(int fd) override {
    if (std::exchange(interrupt_sync, false)) {
      errno = EINTR;
      return -1;
    }
    if (++syncs == fail_sync) {
      errno = EIO;
      return -1;
    }
    return JamIo::Sync(fd);
  }
  int Truncate(int fd, off_t size) override {
    if (std::exchange(interrupt_truncate, false)) {
      errno = EINTR;
      return -1;
    }
    if (fail_truncate) {
      errno = EIO;
      return -1;
    }
    return JamIo::Truncate(fd, size);
  }
};
class JamRecoveryTest : public ::testing::Test {
protected:
  test::TempDirectory temp;
  std::shared_ptr<IMetadataStore> metadata;
  std::shared_ptr<JamCatalog> catalog;
  std::filesystem::path base;
  void SetUp() override {
    base = temp.path() / "base";
    msgapi::JamBaseHeader header{};
    header.signature = msgapi::kJamSignature;
    header.base_msg_num = 42;
    header.date_created = 123;
    header.password_crc = UINT32_MAX;
    auto bytes = msgapi::jam_wire::Encode(header);
    {
      std::ofstream output(base.string() + ".jhr", std::ios::binary);
      output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    }
    for (auto extension : {".jdt", ".jdx"}) {
      std::ofstream output(base.string() + extension, std::ios::binary);
    }
    metadata = CreateSQLiteStore(temp.path() / "metadata.db");
    ASSERT_TRUE(metadata->Init());
    ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{}));
    EchoAreaConfig area;
    area.name = "echo";
    area.filename = "base";
    area.msgbase_type = "JAM";
    auto opened = JamCatalog::Build(temp.path(), {area});
    ASSERT_TRUE(opened);
    catalog = std::shared_ptr<JamCatalog>(std::move(*opened));
    auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
    ASSERT_TRUE(access);
    msgapi::JamMessage previous;
    previous.SetSubject("confirmed");
    previous.SetText("старое сообщение");
    previous.SetMsgId("2:1/1 previous");
    ASSERT_EQ((*access)->messages().AddMessage(previous), msgapi::JamError::kSuccess);
    for (int fd : (*access)->files().descriptors)
      ASSERT_EQ(fsync(fd), 0);
  }
  JamDeadline Deadline() {
    return std::chrono::steady_clock::now() + 2s;
  }
  Operation Plan(JamAccess& access, std::string id = "operation") {
    msgapi::JamMessage message;
    message.SetSubject("new");
    message.SetText("новое сообщение");
    message.SetMsgId("2:1/1 " + id);
    auto plan = access.messages().PrepareAppend(message);
    EXPECT_TRUE(plan);
    Operation operation;
    operation.user = "A";
    operation.id = std::move(id);
    operation.conference = "echo";
    operation.generation = access.generation();
    operation.ftn_msgid = message.msg_id();
    if (plan)
      operation.plan = std::move(*plan);
    return operation;
  }
  void RestartCatalog() {
    catalog.reset();
    EchoAreaConfig area;
    area.name = "echo";
    area.filename = "base";
    area.msgbase_type = "JAM";
    auto opened = JamCatalog::Build(temp.path(), {area});
    ASSERT_TRUE(opened);
    catalog = std::shared_ptr<JamCatalog>(std::move(*opened));
    metadata.reset();
    metadata = CreateSQLiteStore(temp.path() / "metadata.db");
    ASSERT_TRUE(metadata->Init());
  }
  void ConfirmOldAndState(OperationState state) {
    auto operation = metadata->FindOperation("A", "operation");
    ASSERT_TRUE(operation);
    ASSERT_TRUE(*operation);
    EXPECT_EQ((*operation)->state, state);
    auto access = JamAccess::Open(*catalog, "echo", false, Deadline());
    ASSERT_TRUE(access);
    auto previous = (*access)->messages().ReadMessage(42);
    ASSERT_TRUE(previous);
    EXPECT_EQ(previous->subject(), "confirmed");
    EXPECT_EQ(previous->text(), "старое сообщение");
    EXPECT_EQ((*access)->messages().message_count(), state == OperationState::kCommitted ? 2 : 1);
  }
};
}  // namespace
TEST_F(JamRecoveryTest, DurableSuccessAndShortWritesAreFullyCommitted) {
  auto io = std::make_shared<FaultIo>();
  io->short_writes = true;
  JamWriter writer(metadata, io);
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  ASSERT_TRUE(writer.Append(**access, operation));
  EXPECT_GT(io->writes, 4);
  EXPECT_EQ(io->syncs, 4);
  access->reset();
  RestartCatalog();
  JamWriter restored(metadata);
  ASSERT_TRUE(restored.RecoverAll(*catalog, Deadline()));
  ConfirmOldAndState(OperationState::kCommitted);
}
TEST_F(JamRecoveryTest, WriteFailuresNeverReportSuccessAndBlockFurtherViews) {
  for (int stage = 1; stage <= 4; ++stage) {
    SCOPED_TRACE(stage);
    auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
    ASSERT_TRUE(access);
    auto operation = Plan(**access, "write-" + std::to_string(stage));
    auto io = std::make_shared<FaultIo>();
    io->fail_write = stage;
    io->partial = true;
    JamWriter writer(metadata, io);
    EXPECT_FALSE(writer.Append(**access, operation));
    access->reset();
    EXPECT_FALSE(JamAccess::Open(*catalog, "echo", false, Deadline()));
    RestartCatalog();
    JamWriter restored(metadata);
    ASSERT_TRUE(restored.RecoverAll(*catalog, Deadline()));
    auto saved = metadata->FindOperation("A", operation.id);
    ASSERT_TRUE(saved);
    ASSERT_TRUE(*saved);
    EXPECT_EQ((*saved)->state, stage == 4 ? OperationState::kCommitted : OperationState::kRolledBack);
    auto read = JamAccess::Open(*catalog, "echo", false, Deadline());
    ASSERT_TRUE(read);
    EXPECT_EQ((*read)->messages().ReadMessage(42)->text(), "старое сообщение");
  }
}
TEST_F(JamRecoveryTest, FsyncFailuresAreResolvedByRestart) {
  for (int stage = 1; stage <= 4; ++stage) {
    SCOPED_TRACE(stage);
    auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
    ASSERT_TRUE(access);
    auto operation = Plan(**access, "sync-" + std::to_string(stage));
    auto io = std::make_shared<FaultIo>();
    io->fail_sync = stage;
    JamWriter writer(metadata, io);
    EXPECT_FALSE(writer.Append(**access, operation));
    access->reset();
    RestartCatalog();
    JamWriter restored(metadata);
    ASSERT_TRUE(restored.RecoverAll(*catalog, Deadline()));
    auto saved = metadata->FindOperation("A", operation.id);
    ASSERT_TRUE(saved);
    ASSERT_TRUE(*saved);
    EXPECT_EQ((*saved)->state, stage >= 3 ? OperationState::kCommitted : OperationState::kRolledBack);
    auto read = JamAccess::Open(*catalog, "echo", false, Deadline());
    ASSERT_TRUE(read);
    EXPECT_EQ((*read)->messages().ReadMessage(42)->subject(), "confirmed");
  }
}
TEST_F(JamRecoveryTest, ForeignTailIsQuarantinedAndNeverTruncated) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  auto io = std::make_shared<FaultIo>();
  io->fail_write = 2;
  JamWriter writer(metadata, io);
  EXPECT_FALSE(writer.Append(**access, operation));
  access->reset();
  {
    std::ofstream output(base.string() + ".jdt", std::ios::binary | std::ios::app);
    output << "foreign HPT data";
  }
  std::array<std::string, 3> before{Contents(base.string() + ".jhr"), Contents(base.string() + ".jdt"),
                                    Contents(base.string() + ".jdx")};
  RestartCatalog();
  JamWriter restored(metadata);
  EXPECT_FALSE(restored.RecoverAll(*catalog, Deadline()));
  auto saved = metadata->FindOperation("A", "operation");
  ASSERT_TRUE(saved);
  ASSERT_TRUE(*saved);
  EXPECT_EQ((*saved)->state, OperationState::kQuarantine);
  for (size_t i = 0; i < 3; ++i)
    EXPECT_EQ(Contents(base.string() + std::array<const char*, 3>{".jhr", ".jdt", ".jdx"}[i]), before[i]);
  EXPECT_FALSE(JamAccess::Open(*catalog, "echo", true, Deadline()));
  RestartCatalog();
  JamWriter repeated(metadata);
  EXPECT_FALSE(repeated.RecoverAll(*catalog, Deadline()));
}
TEST_F(JamRecoveryTest, IntentFailureMakesNoJamChanges) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  operation.user = "missing";
  auto before = Contents(base.string() + ".jhr");
  auto text = Contents(base.string() + ".jdt");
  auto index = Contents(base.string() + ".jdx");
  JamWriter writer(metadata);
  EXPECT_FALSE(writer.Append(**access, operation));
  EXPECT_EQ(Contents(base.string() + ".jhr"), before);
  EXPECT_EQ(Contents(base.string() + ".jdt"), text);
  EXPECT_EQ(Contents(base.string() + ".jdx"), index);
}

#include <sys/wait.h>
namespace {
class ExitAfterIo : public JamIo {
public:
  explicit ExitAfterIo(int stage) : stage_(stage) {
  }
  ssize_t Write(int fd, const void* bytes, size_t size, off_t offset) override {
    auto result = JamIo::Write(fd, bytes, size, offset);
    if (++events_ == stage_)
      _exit(77);
    return result;
  }
  int Sync(int fd) override {
    auto result = JamIo::Sync(fd);
    if (++events_ == stage_)
      _exit(77);
    return result;
  }

private:
  int stage_, events_ = 0;
};
}  // namespace
TEST_F(JamRecoveryTest, ProcessExitAtEveryPublicationBoundaryPreservesConfirmedMessages) {
  for (int stage = 1; stage <= 8; ++stage) {
    SCOPED_TRACE(stage);
    const auto id = "restart-" + std::to_string(stage);
    const auto pid = fork();
    ASSERT_GE(pid, 0);
    if (pid == 0) {
      auto db = CreateSQLiteStore(temp.path() / "metadata.db");
      if (!db->Init())
        _exit(2);
      auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
      if (!access)
        _exit(3);
      auto operation = Plan(**access, id);
      JamWriter writer(db, std::make_shared<ExitAfterIo>(stage));
      const auto appended = writer.Append(**access, operation);
      _exit(appended ? 4 : 5);
    }
    int status = 0;
    ASSERT_EQ(waitpid(pid, &status, 0), pid);
    ASSERT_TRUE(WIFEXITED(status));
    ASSERT_EQ(WEXITSTATUS(status), 77);
    RestartCatalog();
    JamWriter restored(metadata);
    ASSERT_TRUE(restored.RecoverAll(*catalog, Deadline()));
    auto saved = metadata->FindOperation("A", id);
    ASSERT_TRUE(saved);
    ASSERT_TRUE(*saved);
    EXPECT_EQ((*saved)->state, stage >= 5 ? OperationState::kCommitted : OperationState::kRolledBack);
    auto read = JamAccess::Open(*catalog, "echo", false, Deadline());
    ASSERT_TRUE(read);
    EXPECT_EQ((*read)->messages().ReadMessage(42)->subject(), "confirmed");
    auto numbers = (*read)->messages().GetMessageNumbers();
    ASSERT_TRUE(numbers);
    EXPECT_EQ(numbers->size(), (*read)->messages().message_count());
  }
}
TEST_F(JamRecoveryTest, CompleteForeignAppendAfterIntentIsQuarantined) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  auto io = std::make_shared<FaultIo>();
  io->fail_write = 1;
  JamWriter writer(metadata, io);
  EXPECT_FALSE(writer.Append(**access, operation));
  access->reset();
  {
    msgapi::JamMessageBase external(base.string());
    ASSERT_EQ(external.Open(), msgapi::JamError::kSuccess);
    msgapi::JamMessage message;
    message.SetSubject("HPT foreign confirmed");
    message.SetText("foreign");
    message.SetMsgId("2:1/1 FOREIGN");
    ASSERT_EQ(external.AddMessage(message), msgapi::JamError::kSuccess);
  }
  const auto before = Contents(base.string() + ".jhr"), text = Contents(base.string() + ".jdt"),
             index = Contents(base.string() + ".jdx");
  RestartCatalog();
  JamWriter restored(metadata);
  EXPECT_FALSE(restored.RecoverAll(*catalog, Deadline()));
  EXPECT_EQ(Contents(base.string() + ".jhr"), before);
  EXPECT_EQ(Contents(base.string() + ".jdt"), text);
  EXPECT_EQ(Contents(base.string() + ".jdx"), index);
  msgapi::JamMessageBase external(base.string());
  ASSERT_EQ(external.Open(), msgapi::JamError::kSuccess);
  EXPECT_EQ(external.ReadMessage(43)->subject(), "HPT foreign confirmed");
}
TEST_F(JamRecoveryTest, ReplacementGenerationIsQuarantinedWithoutWritingNewFiles) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  ASSERT_TRUE(metadata->PrepareOperation(operation));
  access->reset();
  for (auto extension : {".jhr", ".jdt", ".jdx"}) {
    auto path = base.string() + extension, replacement = path + ".replacement";
    std::filesystem::copy_file(path, replacement);
    std::filesystem::rename(replacement, path);
  }
  auto before = Contents(base.string() + ".jhr");
  RestartCatalog();
  JamWriter writer(metadata);
  EXPECT_FALSE(writer.RecoverAll(*catalog, Deadline()));
  EXPECT_EQ(Contents(base.string() + ".jhr"), before);
  auto saved = metadata->FindOperation("A", "operation");
  ASSERT_TRUE(saved);
  ASSERT_TRUE(*saved);
  EXPECT_EQ((*saved)->state, OperationState::kQuarantine);
}

TEST_F(JamRecoveryTest, StalePendingSnapshotCannotQuarantineLaterConfirmedAppend) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto first = Plan(**access, "first");
  JamWriter writer(metadata);
  ASSERT_TRUE(writer.Append(**access, first));
  access->reset();
  access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto second = Plan(**access, "second");
  ASSERT_TRUE(writer.Append(**access, second));
  access->reset();
  // A waiter had read the first pending journal before its commit; its lock arrives later.
  ASSERT_TRUE(writer.Recover(*catalog, first, Deadline()));
  auto read = JamAccess::Open(*catalog, "echo", false, Deadline());
  ASSERT_TRUE(read);
  EXPECT_EQ((*read)->messages().message_count(), 3);
}

TEST_F(JamRecoveryTest, InterruptedWritesAndSyncsRetryWithoutDuplicateAppend) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  auto io = std::make_shared<FaultIo>();
  io->interrupt_write = io->interrupt_sync = true;
  JamWriter writer(metadata, io);
  ASSERT_TRUE(writer.Append(**access, operation));
  EXPECT_EQ(io->writes, 4);
  EXPECT_EQ(io->syncs, 4);
  access->reset();
  ConfirmOldAndState(OperationState::kCommitted);
}

TEST_F(JamRecoveryTest, RecoveryIoFailuresKeepIntentUntilSuccessfulRetry) {
  for (int stage = 0; stage <= 5; ++stage) {
    SCOPED_TRACE(stage);
    auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
    ASSERT_TRUE(access);
    auto operation = Plan(**access, "recover-" + std::to_string(stage));
    auto initial = std::make_shared<FaultIo>();
    initial->fail_write = 2;
    JamWriter initial_writer(metadata, initial);
    EXPECT_FALSE(initial_writer.Append(**access, operation));
    access->reset();
    RestartCatalog();
    auto recovery_io = std::make_shared<FaultIo>();
    recovery_io->fail_truncate = stage == 0;
    recovery_io->fail_write = stage == 1 ? 1 : 0;
    recovery_io->fail_sync = stage >= 2 ? stage - 1 : 0;
    JamWriter failing(metadata, recovery_io);
    EXPECT_FALSE(failing.Recover(*catalog, operation, Deadline()));
    auto pending = metadata->FindOperation("A", operation.id);
    ASSERT_TRUE(pending);
    ASSERT_TRUE(*pending);
    EXPECT_EQ((*pending)->state, OperationState::kPending);
    EXPECT_FALSE(JamAccess::Open(*catalog, "echo", false, Deadline()));
    auto retry_io = std::make_shared<FaultIo>();
    retry_io->interrupt_truncate = true;
    JamWriter retry(metadata, retry_io);
    ASSERT_TRUE(retry.Recover(*catalog, operation, Deadline()));
    auto restored = metadata->FindOperation("A", operation.id);
    ASSERT_TRUE(restored);
    ASSERT_TRUE(*restored);
    EXPECT_EQ((*restored)->state, OperationState::kRolledBack);
    auto read = JamAccess::Open(*catalog, "echo", false, Deadline());
    ASSERT_TRUE(read);
    EXPECT_EQ((*read)->messages().message_count(), 1);
    EXPECT_EQ((*read)->messages().ReadMessage(42)->text(), "старое сообщение");
  }
}

TEST_F(JamRecoveryTest, InvalidGenerationAndRecoveryFlagRefuseAppendBeforeIntent) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  operation.generation = "wrong";
  JamWriter writer(metadata);
  EXPECT_FALSE(writer.Append(**access, operation));
  operation.generation = (*access)->generation();
  (*access)->files().needs_recovery = true;
  EXPECT_FALSE(writer.Append(**access, operation));
  (*access)->files().needs_recovery = false;
  (*access)->files().writable = false;
  EXPECT_FALSE(writer.Append(**access, operation));
  auto pending = metadata->PendingOperations();
  ASSERT_TRUE(pending);
  EXPECT_TRUE(pending->empty());
}

TEST_F(JamRecoveryTest, CommitJournalFailureLeavesCompleteFilesRecoverable) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  sqlite3* db = nullptr;
  ASSERT_EQ(sqlite3_open((temp.path() / "metadata.db").c_str(), &db), SQLITE_OK);
  ASSERT_EQ(sqlite3_exec(db,
                         "CREATE TRIGGER reject_commit BEFORE UPDATE ON operations BEGIN "
                         "SELECT RAISE(ABORT,'private commit failure'); END",
                         nullptr, nullptr, nullptr),
            SQLITE_OK);
  JamWriter writer(metadata);
  EXPECT_FALSE(writer.Append(**access, operation));
  EXPECT_TRUE((*access)->files().needs_recovery);
  access->reset();
  EXPECT_FALSE(writer.Recover(*catalog, operation, Deadline()));
  ASSERT_EQ(sqlite3_exec(db, "DROP TRIGGER reject_commit", nullptr, nullptr, nullptr), SQLITE_OK);
  sqlite3_close(db);
  ASSERT_TRUE(writer.Recover(*catalog, operation, Deadline()));
  ConfirmOldAndState(OperationState::kCommitted);
}

TEST_F(JamRecoveryTest, UnknownAreaQuarantinesJournalAndMissingJournalFails) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  operation.conference = "removed-area";
  ASSERT_TRUE(metadata->PrepareOperation(operation));
  access->reset();
  JamWriter writer(metadata);
  EXPECT_FALSE(writer.Recover(*catalog, operation, Deadline()));
  auto saved = metadata->FindOperation("A", operation.id);
  ASSERT_TRUE(saved);
  ASSERT_TRUE(*saved);
  EXPECT_EQ((*saved)->state, OperationState::kQuarantine);
  operation.conference = "echo";
  operation.id = "absent";
  EXPECT_FALSE(writer.Recover(*catalog, operation, Deadline()));
  operation.state = OperationState::kCommitted;
  EXPECT_TRUE(writer.Recover(*catalog, operation, Deadline()));
  operation.state = OperationState::kRolledBack;
  EXPECT_TRUE(writer.Recover(*catalog, operation, Deadline()));
  auto read = JamAccess::Open(*catalog, "echo", false, Deadline());
  ASSERT_TRUE(read);
  EXPECT_EQ((*read)->messages().message_count(), 1);
}

TEST_F(JamRecoveryTest, QuarantineStateRefreshBlocksStalePendingSnapshot) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  ASSERT_TRUE(metadata->PrepareOperation(operation));
  ASSERT_TRUE(metadata->SetOperationState("A", operation.id, OperationState::kQuarantine));
  access->reset();
  JamWriter writer(metadata);
  EXPECT_FALSE(writer.Recover(*catalog, operation, Deadline()));
  EXPECT_FALSE(JamAccess::Open(*catalog, "echo", false, Deadline()));
}

TEST_F(JamRecoveryTest, RecoveryCannotConfirmFailedResyncOrBasePublication) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  auto initial = std::make_shared<FaultIo>();
  initial->fail_sync = 4;
  JamWriter writer(metadata, initial);
  EXPECT_FALSE(writer.Append(**access, operation));
  access->reset();
  RestartCatalog();
  for (int stage = 1; stage <= 5; ++stage) {
    auto io = std::make_shared<FaultIo>();
    io->fail_write = stage == 5 ? 1 : 0;
    io->fail_sync = stage <= 4 ? stage : 0;
    JamWriter recovering(metadata, io);
    EXPECT_FALSE(recovering.Recover(*catalog, operation, Deadline()));
    auto record = metadata->FindOperation("A", operation.id);
    ASSERT_TRUE(record);
    ASSERT_TRUE(*record);
    EXPECT_EQ((*record)->state, OperationState::kPending);
  }
  JamWriter retry(metadata);
  ASSERT_TRUE(retry.Recover(*catalog, operation, Deadline()));
  ConfirmOldAndState(OperationState::kCommitted);
}

TEST_F(JamRecoveryTest, RecoveryReadAndStatFailuresNeverModifyFilesOrConfirmIntent) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  auto initial = std::make_shared<FaultIo>();
  initial->fail_sync = 4;
  JamWriter writer(metadata, initial);
  EXPECT_FALSE(writer.Append(**access, operation));
  access->reset();
  RestartCatalog();
  const std::array<std::string, 3> before{Contents(base.string() + ".jhr"), Contents(base.string() + ".jdt"),
                                          Contents(base.string() + ".jdx")};
  for (int fault = 1; fault <= 10; ++fault) {
    auto io = std::make_shared<FaultIo>();
    if (fault <= 4)
      io->fail_read = fault;
    else {
      io->fail_stat = (fault - 5) % 3 + 1;
      io->negative_size = fault >= 8;
    }
    JamWriter recovery(metadata, io);
    EXPECT_FALSE(recovery.Recover(*catalog, operation, Deadline()));
    for (size_t i = 0; i < 3; ++i)
      EXPECT_EQ(Contents(base.string() + std::array<const char*, 3>{".jhr", ".jdt", ".jdx"}[i]), before[i]);
    auto record = metadata->FindOperation("A", operation.id);
    ASSERT_TRUE(record);
    ASSERT_TRUE(*record);
    EXPECT_EQ((*record)->state, OperationState::kPending);
  }
  auto io = std::make_shared<FaultIo>();
  io->interrupt_read = true;
  io->short_writes = true;
  JamWriter retry(metadata, io);
  ASSERT_TRUE(retry.Recover(*catalog, operation, Deadline()));
  ConfirmOldAndState(OperationState::kCommitted);
}

TEST_F(JamRecoveryTest, JournalUnavailableNeverAllowsRecoveryOrQuarantineAcknowledgement) {
  auto access = JamAccess::Open(*catalog, "echo", true, Deadline());
  ASSERT_TRUE(access);
  auto operation = Plan(**access);
  ASSERT_TRUE(metadata->PrepareOperation(operation));
  access->reset();
  sqlite3* db = nullptr;
  ASSERT_EQ(sqlite3_open((temp.path() / "metadata.db").c_str(), &db), SQLITE_OK);
  ASSERT_EQ(sqlite3_exec(db, "ALTER TABLE operations RENAME TO saved_operations", nullptr, nullptr, nullptr),
            SQLITE_OK);
  JamWriter writer(metadata);
  EXPECT_FALSE(writer.RecoverAll(*catalog, Deadline()));
  EXPECT_FALSE(writer.Recover(*catalog, operation, Deadline()));
  operation.conference = "removed";
  EXPECT_FALSE(writer.Recover(*catalog, operation, Deadline()));
  ASSERT_EQ(
      sqlite3_exec(db,
                   "ALTER TABLE saved_operations RENAME TO operations; UPDATE operations SET generation='foreign'; "
                   "CREATE TRIGGER reject_quarantine BEFORE UPDATE ON operations BEGIN "
                   "SELECT RAISE(ABORT,'private'); END",
                   nullptr, nullptr, nullptr),
      SQLITE_OK);
  operation.conference = "echo";
  operation.generation = "foreign";
  EXPECT_FALSE(writer.Recover(*catalog, operation, Deadline()));
  auto record = metadata->FindOperation("A", operation.id);
  ASSERT_TRUE(record);
  ASSERT_TRUE(*record);
  EXPECT_EQ((*record)->state, OperationState::kPending);
  sqlite3_close(db);
}

TEST_F(JamRecoveryTest, CrosspostDerivesProgressFromDurableChildrenAndHonorsQuarantine) {
  ASSERT_TRUE(metadata->SaveProfile("A", {"Alice", "2:5015/1.1", "", ""}));
  std::vector<EchoAreaConfig> areas{catalog->areas().at("echo").config};
  auto extra = areas.front();
  extra.name = "echo.copy";
  extra.filename = "copy";
  for (const auto* suffix : {".jhr", ".jdt", ".jdx"})
    std::filesystem::copy_file(base.string() + suffix, (temp.path() / "copy").string() + suffix);
  areas.push_back(extra);
  auto built = JamCatalog::Build(temp.path(), areas);
  ASSERT_TRUE(built);
  auto expanded = std::shared_ptr<JamCatalog>(std::move(*built));
  service::MessageService publisher(expanded, metadata, test::EchoAccess(*expanded, temp.path()));
  domain::CreateMessageRequest request{"recovery-group", "All", "", "Text", "Body", ""};
  auto sent = publisher.CreateCrosspost("echo", request, {"echo.copy"}, "A");
  ASSERT_TRUE(sent && sent->complete);
  const auto record = metadata->GetCrosspost("A", request.operation_id);
  ASSERT_TRUE(record && *record);
  const auto manifest = nlohmann::json::parse(**record);
  const std::string key = manifest["copies"][1]["key"];
  // No group progress flag exists: a lost response is reconciled from child commits.
  service::MessageService restarted(expanded, metadata, test::EchoAccess(*expanded, temp.path()));
  auto retry = restarted.CreateCrosspost("echo", request, {"echo.copy"}, "A");
  ASSERT_TRUE(retry && retry->complete);
  EXPECT_EQ(retry->saved[1].id, sent->saved[1].id);
  ASSERT_TRUE(metadata->SetOperationState("A", key, OperationState::kQuarantine));
  const auto before = Contents(temp.path() / "copy.jdt");
  auto quarantined = restarted.CreateCrosspost("echo", request, {"echo.copy"}, "A");
  ASSERT_TRUE(quarantined);
  EXPECT_FALSE(quarantined->complete);
  EXPECT_EQ(quarantined->pending_code, 9);
  EXPECT_EQ(Contents(temp.path() / "copy.jdt"), before);
}
