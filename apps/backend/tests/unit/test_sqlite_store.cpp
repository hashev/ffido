#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>
#include <future>

#include "../support/temp_directory.hpp"
#include "domain/profile.hpp"
#include "storage/metadata_store.hpp"

namespace fs = std::filesystem;
using namespace fidoback;

class SQLiteStoreTest : public ::testing::Test {
protected:
  void SetUp() override {
    db_path_ = temp_.path() / "metadata.db";
    store_ = storage::CreateSQLiteStore(db_path_);
    auto init = store_->Init();
    ASSERT_TRUE(init);
  }

  void TearDown() override {
    store_.reset();
    fs::remove_all(temp_.path());
    EXPECT_FALSE(fs::exists(temp_.path()));
  }

  test::TempDirectory temp_;
  fs::path db_path_;
  std::shared_ptr<storage::IMetadataStore> store_;
};

TEST_F(SQLiteStoreTest, InitCreatesTables) {
  // If we got here, Init() succeeded — tables are created
  auto profile = store_->GetProfile("default");
  // Profile doesn't exist yet (not created automatically)
  EXPECT_FALSE(profile);
}

TEST_F(SQLiteStoreTest, SaveAndGetProfile) {
  domain::Profile p;
  p.name = "Test User";
  p.address = "2:5015/0.0";
  p.email = "test@example.com";
  p.registered_at = "2026-01-01T00:00:00Z";

  auto save = store_->SaveProfile("user1", p);
  ASSERT_TRUE(save);

  auto get = store_->GetProfile("user1");
  ASSERT_TRUE(get);
  EXPECT_EQ(get->name, "Test User");
  EXPECT_EQ(get->address, "2:5015/0.0");
  EXPECT_EQ(get->email, "test@example.com");
}

TEST_F(SQLiteStoreTest, UpdateProfile) {
  domain::Profile p;
  p.name = "Old Name";
  p.address = "2:5015/0.0";
  p.registered_at = "2026-01-01T00:00:00Z";

  ASSERT_TRUE(store_->SaveProfile("user1", p));
  p.name = "New Name";
  ASSERT_TRUE(store_->SaveProfile("user1", p));

  auto get = store_->GetProfile("user1");
  ASSERT_TRUE(get);
  EXPECT_EQ(get->name, "New Name");
}

TEST_F(SQLiteStoreTest, GetProfileNotFound) {
  auto result = store_->GetProfile("nonexistent");
  EXPECT_FALSE(result);
}

TEST_F(SQLiteStoreTest, AddAndGetBookmarks) {
  ASSERT_TRUE(store_->SaveProfile("user1", domain::Profile{"User", "2:5015/0", "", "2026-01-01T00:00:00Z"}));

  ASSERT_TRUE(store_->AddBookmark("user1", "comp.lang.dart"));
  ASSERT_TRUE(store_->AddBookmark("user1", "ru.fido"));

  auto bookmarks = store_->GetBookmarks("user1");
  ASSERT_TRUE(bookmarks);
  EXPECT_EQ(bookmarks->size(), 2);
}

TEST_F(SQLiteStoreTest, RemoveBookmark) {
  ASSERT_TRUE(store_->SaveProfile("user1", domain::Profile{"User", "2:5015/0", "", "2026-01-01T00:00:00Z"}));
  ASSERT_TRUE(store_->AddBookmark("user1", "comp.lang.dart"));

  auto before = store_->GetBookmarks("user1");
  ASSERT_TRUE(before);
  EXPECT_EQ(before->size(), 1);

  ASSERT_TRUE(store_->RemoveBookmark("user1", "comp.lang.dart"));
  auto after = store_->GetBookmarks("user1");
  ASSERT_TRUE(after);
  EXPECT_EQ(after->size(), 0);
}

TEST_F(SQLiteStoreTest, IsBookmarked) {
  ASSERT_TRUE(store_->SaveProfile("user1", domain::Profile{"User", "2:5015/0", "", "2026-01-01T00:00:00Z"}));

  auto before = store_->IsBookmarked("user1", "test.echo");
  ASSERT_TRUE(before);
  EXPECT_FALSE(*before);

  ASSERT_TRUE(store_->AddBookmark("user1", "test.echo"));
  auto after = store_->IsBookmarked("user1", "test.echo");
  ASSERT_TRUE(after);
  EXPECT_TRUE(*after);
}

TEST_F(SQLiteStoreTest, AddToHistory) {
  ASSERT_TRUE(store_->SaveProfile("user1", domain::Profile{"User", "2:5015/0", "", "2026-01-01T00:00:00Z"}));

  ASSERT_TRUE(store_->AddToHistory("user1", "conf1"));
  ASSERT_TRUE(store_->AddToHistory("user1", "conf2"));
  ASSERT_TRUE(store_->AddToHistory("user1", "conf3"));

  auto history = store_->GetHistory("user1");
  ASSERT_TRUE(history);
  EXPECT_EQ(history->size(), 3);
}

TEST_F(SQLiteStoreTest, ClearHistory) {
  ASSERT_TRUE(store_->SaveProfile("user1", domain::Profile{"User", "2:5015/0", "", "2026-01-01T00:00:00Z"}));
  ASSERT_TRUE(store_->AddToHistory("user1", "conf1"));
  ASSERT_TRUE(store_->AddToHistory("user1", "conf2"));

  ASSERT_TRUE(store_->ClearHistory("user1"));
  auto history = store_->GetHistory("user1");
  ASSERT_TRUE(history);
  EXPECT_EQ(history->size(), 0);
}

TEST_F(SQLiteStoreTest, HistoryUpsert) {
  ASSERT_TRUE(store_->SaveProfile("user1", domain::Profile{"User", "2:5015/0", "", "2026-01-01T00:00:00Z"}));

  // Adding same conference twice updates viewed_at, doesn't duplicate
  ASSERT_TRUE(store_->AddToHistory("user1", "conf1"));
  ASSERT_TRUE(store_->AddToHistory("user1", "conf1"));

  auto history = store_->GetHistory("user1");
  ASSERT_TRUE(history);
  EXPECT_EQ(history->size(), 1);
}

TEST_F(SQLiteStoreTest, MarkMessageRead) {
  ASSERT_TRUE(store_->SaveProfile("user1", domain::Profile{"User", "2:5015/0", "", "2026-01-01T00:00:00Z"}));

  auto before = store_->IsMessageRead("user1", {"conf1", "generation", "msg_1"});
  ASSERT_TRUE(before);
  EXPECT_FALSE(*before);

  ASSERT_TRUE(store_->MarkMessageRead("user1", {"conf1", "generation", "msg_1"}));
  auto after = store_->IsMessageRead("user1", {"conf1", "generation", "msg_1"});
  ASSERT_TRUE(after);
  EXPECT_TRUE(*after);
}

TEST_F(SQLiteStoreTest, DuplicateBookmarkIsIdempotent) {
  ASSERT_TRUE(store_->SaveProfile("user1", domain::Profile{"User", "2:5015/0", "", "2026-01-01T00:00:00Z"}));

  ASSERT_TRUE(store_->AddBookmark("user1", "conf1"));
  ASSERT_TRUE(store_->AddBookmark("user1", "conf1"));  // should not duplicate

  auto bookmarks = store_->GetBookmarks("user1");
  ASSERT_TRUE(bookmarks);
  EXPECT_EQ(bookmarks->size(), 1);
}

namespace {
class RawDb {
public:
  explicit RawDb(const fs::path& path) {
    EXPECT_EQ(sqlite3_open(path.c_str(), &db), SQLITE_OK);
  }
  ~RawDb() {
    sqlite3_close(db);
  }
  void Exec(const char* sql) {
    ASSERT_EQ(sqlite3_exec(db, sql, nullptr, nullptr, nullptr), SQLITE_OK);
  }
  int Scalar(const char* sql) {
    sqlite3_stmt* statement = nullptr;
    EXPECT_EQ(sqlite3_prepare_v2(db, sql, -1, &statement, nullptr), SQLITE_OK);
    if (!statement)
      return -1;
    EXPECT_EQ(sqlite3_step(statement), SQLITE_ROW);
    const int value = sqlite3_column_int(statement, 0);
    sqlite3_finalize(statement);
    return value;
  }
  sqlite3* db = nullptr;
};
}  // namespace

TEST_F(SQLiteStoreTest, StringViewsAndEmbeddedNulKeepExactIdentity) {
  const std::string padded = "!user!";
  const std::string_view user(padded.data() + 1, 4);
  const std::string conference("echo\0tail", 9);
  domain::Profile profile{"Имя", "2:5015/1", std::string("a\0b", 3), "2026-01-01T00:00:00Z"};
  ASSERT_TRUE(store_->SaveProfile(user, profile));
  ASSERT_TRUE(store_->AddBookmark(user, conference));
  ASSERT_TRUE(store_->AddToHistory(user, conference));
  auto read = store_->GetProfile("user");
  ASSERT_TRUE(read);
  EXPECT_EQ(read->email, profile.email);
  auto bookmarks = store_->GetBookmarks(user);
  ASSERT_TRUE(bookmarks);
  ASSERT_EQ(bookmarks->size(), 1);
  EXPECT_EQ(bookmarks->front().conference_id, conference);
  auto history = store_->GetHistory(user);
  ASSERT_TRUE(history);
  EXPECT_EQ(history->at(0).conference_id, conference);
  EXPECT_FALSE(store_->GetProfile("user!"));
}

TEST_F(SQLiteStoreTest, ForeignKeysRejectUnknownUsers) {
  EXPECT_FALSE(store_->AddBookmark("unknown", "echo"));
  EXPECT_FALSE(store_->AddToHistory("unknown", "echo"));
  auto bookmarks = store_->GetBookmarks("unknown");
  ASSERT_TRUE(bookmarks);
  EXPECT_TRUE(bookmarks->empty());
}

TEST_F(SQLiteStoreTest, BusyWriteFailsAndCanBeRetried) {
  RawDb other(db_path_);
  other.Exec("BEGIN IMMEDIATE");
  auto failed = store_->SaveProfile("user", domain::Profile{});
  EXPECT_FALSE(failed);
  EXPECT_FALSE(store_->GetProfile("user"));
  other.Exec("ROLLBACK");
  EXPECT_TRUE(store_->SaveProfile("user", domain::Profile{}));
}

TEST_F(SQLiteStoreTest, StepAndPrepareErrorsAreNotEmptyResults) {
  RawDb other(db_path_);
  other.Exec("DROP TABLE bookmarks; DROP TABLE history; DROP TABLE read_status; DROP TABLE users;");
  EXPECT_FALSE(store_->GetBookmarks("user"));
  EXPECT_FALSE(store_->IsBookmarked("user", "echo"));
  EXPECT_FALSE(store_->GetHistory("user"));
  EXPECT_FALSE(store_->IsMessageRead("user", {"echo", "generation", "1"}));
  EXPECT_FALSE(store_->GetReadCount("user", "echo", "generation"));
  auto error = store_->GetProfile("user");
  ASSERT_FALSE(error);
  EXPECT_EQ(error.error().code, domain::ErrorCode::kServer);
  EXPECT_EQ(error.error().message.find(db_path_.string()), std::string::npos);
}

TEST_F(SQLiteStoreTest, ReinitializationPreservesDataAndVersion) {
  ASSERT_TRUE(store_->SaveProfile("user", domain::Profile{}));
  ASSERT_TRUE(store_->Init());
  store_.reset();
  store_ = storage::CreateSQLiteStore(db_path_);
  ASSERT_TRUE(store_->Init());
  EXPECT_TRUE(store_->GetProfile("user"));
  RawDb other(db_path_);
  EXPECT_EQ(other.Scalar("PRAGMA user_version"), 10);
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM users"), 1);
}

TEST(SQLiteMigration, SchemaFailureRollsBackAndAllowsRetry) {
  test::TempDirectory temporary;
  auto path = temporary.path() / "metadata.db";
  {
    RawDb db(path);
    db.Exec("CREATE TABLE history(unrelated TEXT)");
  }
  auto store = storage::CreateSQLiteStore(path);
  EXPECT_FALSE(store->Init());
  {
    RawDb db(path);
    EXPECT_EQ(db.Scalar("PRAGMA user_version"), 0);
    EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM sqlite_master WHERE name='users'"), 0);
    db.Exec("DROP TABLE history");
  }
  EXPECT_TRUE(store->Init());
}

TEST(SQLiteMigration, OpenFailureAndFutureSchemaAreRejected) {
  test::TempDirectory temporary;
  auto bad = storage::CreateSQLiteStore(temporary.path() / "absent" / "metadata.db");
  EXPECT_FALSE(bad->Init());
  auto path = temporary.path() / "metadata.db";
  {
    RawDb db(path);
    db.Exec("PRAGMA user_version=999");
  }
  auto future = storage::CreateSQLiteStore(path);
  EXPECT_FALSE(future->Init());
  RawDb db(path);
  EXPECT_EQ(db.Scalar("PRAGMA user_version"), 999);
}

TEST_F(SQLiteStoreTest, NegativeHistoryLimitIsRejected) {
  EXPECT_FALSE(store_->GetHistory("user", -1));
}

TEST_F(SQLiteStoreTest, StepFailureRollsBackStatement) {
  RawDb other(db_path_);
  other.Exec(
      "CREATE TRIGGER reject_profile BEFORE INSERT ON users BEGIN SELECT RAISE(ABORT, 'private diagnostic'); END");
  auto failed = store_->SaveProfile("user", domain::Profile{});
  ASSERT_FALSE(failed);
  EXPECT_EQ(failed.error().message.find("private diagnostic"), std::string::npos);
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM users"), 0);
  other.Exec("DROP TRIGGER reject_profile");
  EXPECT_TRUE(store_->SaveProfile("user", domain::Profile{}));
}

TEST(SQLiteMigration, CorruptedFileDoesNotInitializeOrOverwrite) {
  test::TempDirectory temporary;
  auto path = temporary.path() / "metadata.db";
  const std::string contents = "This is not a SQLite database";
  {
    std::ofstream output(path, std::ios::binary);
    output << contents;
  }
  auto store = storage::CreateSQLiteStore(path);
  EXPECT_FALSE(store->Init());
  std::ifstream input(path, std::ios::binary);
  EXPECT_EQ(std::string(std::istreambuf_iterator<char>(input), {}), contents);
}

namespace {
void LegacySchema(RawDb& db) {
  db.Exec("CREATE TABLE users(user_id TEXT PRIMARY KEY, name TEXT NOT NULL, ftn_address TEXT NOT NULL, email TEXT NOT "
          "NULL, registered_at TEXT NOT NULL);"
          "CREATE TABLE bookmarks(user_id TEXT, conference_id TEXT, added_at TEXT, PRIMARY KEY(user_id,conference_id));"
          "CREATE TABLE history(user_id TEXT, conference_id TEXT, viewed_at TEXT, PRIMARY KEY(user_id,conference_id));"
          "CREATE TABLE read_status(user_id TEXT, message_id TEXT, conference_id TEXT, read_at TEXT, PRIMARY "
          "KEY(user_id,message_id));"
          "INSERT INTO users VALUES('A','name','2:1/1','','2020-01-01');"
          "INSERT INTO bookmarks VALUES('A','echo','2020-01-02');"
          "INSERT INTO history VALUES('A','echo','2020-01-03');"
          "INSERT INTO read_status VALUES('A','42','echo','2020-01-04'),('missing-user','43','other','2020-01-05');"
          "PRAGMA user_version=1;");
}
}  // namespace

TEST(SQLiteMigration, BacksUpEveryLegacyReadWithoutReassigningNumbers) {
  test::TempDirectory temporary;
  auto path = temporary.path() / "metadata.db";
  {
    RawDb db(path);
    LegacySchema(db);
  }
  auto store = storage::CreateSQLiteStore(path);
  ASSERT_TRUE(store->Init());
  auto unread = store->IsMessageRead("A", {"echo", "current", "42"});
  ASSERT_TRUE(unread);
  EXPECT_FALSE(*unread);
  auto bookmarks = store->GetBookmarks("A");
  ASSERT_TRUE(bookmarks);
  ASSERT_EQ(bookmarks->size(), 1);
  EXPECT_EQ(bookmarks->front().conference_id, "echo");
  EXPECT_EQ(bookmarks->front().added_at, "2020-01-02");
  auto history = store->GetHistory("A");
  ASSERT_TRUE(history);
  ASSERT_EQ(history->size(), 1);
  EXPECT_EQ(history->front().conference_id, "echo");
  EXPECT_EQ(history->front().viewed_at, "2020-01-03");
  ASSERT_TRUE(store->MarkMessageRead("A", {"echo", "current", "42"}));
  store.reset();
  store = storage::CreateSQLiteStore(path);
  ASSERT_TRUE(store->Init());
  auto read = store->IsMessageRead("A", {"echo", "current", "42"});
  ASSERT_TRUE(read);
  EXPECT_TRUE(*read);
  RawDb db(path);
  EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status_legacy_backup"), 2);
  EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status_legacy_backup WHERE user_id='A' AND message_id='42' AND "
                      "conference_id='echo' AND read_at='2020-01-04'"),
            1);
  EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status_legacy_backup WHERE user_id='missing-user'"), 1);
  EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status"), 1);
  EXPECT_EQ(db.Scalar("PRAGMA user_version"), 10);
}

TEST(SQLiteMigration, BackupCollisionRollsBackWholeMigration) {
  test::TempDirectory temporary;
  auto path = temporary.path() / "metadata.db";
  {
    RawDb db(path);
    LegacySchema(db);
    db.Exec("CREATE TABLE read_status_legacy_backup(sentinel TEXT); INSERT INTO read_status_legacy_backup "
            "VALUES('preserve')");
  }
  auto store = storage::CreateSQLiteStore(path);
  EXPECT_FALSE(store->Init());
  {
    RawDb db(path);
    EXPECT_EQ(db.Scalar("PRAGMA user_version"), 1);
    EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status"), 2);
    EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status_legacy_backup WHERE sentinel='preserve'"), 1);
    EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM bookmarks"), 1);
    db.Exec("ALTER TABLE read_status_legacy_backup RENAME TO preserved_backup");
  }
  ASSERT_TRUE(store->Init());
  RawDb db(path);
  EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status_legacy_backup"), 2);
}

TEST_F(SQLiteStoreTest, ReadKeySeparatesUserConferenceAndGeneration) {
  ASSERT_TRUE(store_->SaveProfile("A", domain::Profile{"A", "2:1/1", "", ""}));
  ASSERT_TRUE(store_->SaveProfile("B", domain::Profile{"B", "2:1/2", "", ""}));
  ASSERT_TRUE(store_->MarkMessageRead("A", {"one", "first", "42"}));
  ASSERT_TRUE(store_->MarkMessageRead("A", {"two", "first", "42"}));
  ASSERT_TRUE(store_->MarkMessageRead("A", {"one", "second", "42"}));
  ASSERT_TRUE(store_->MarkMessageRead("A", {"one", "first", "42"}));
  auto read = store_->IsMessageRead("B", {"one", "first", "42"});
  ASSERT_TRUE(read);
  EXPECT_FALSE(*read);
  read = store_->IsMessageRead("A", {"one", "third", "42"});
  ASSERT_TRUE(read);
  EXPECT_FALSE(*read);
  auto count = store_->GetReadCount("A", "one", "first");
  ASSERT_TRUE(count);
  EXPECT_EQ(*count, 1);
  EXPECT_FALSE(store_->MarkMessageRead("A", {"one", "", "42"}));
  RawDb db(db_path_);
  EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status"), 3);
}

TEST_F(SQLiteStoreTest, ReadAndHistoryCommitTogetherAndRollBackTogether) {
  ASSERT_TRUE(store_->SaveProfile("A", domain::Profile{"A", "2:1/1", "", ""}));
  RawDb other(db_path_);
  other.Exec(
      "CREATE TRIGGER reject_view BEFORE INSERT ON history BEGIN SELECT RAISE(ABORT,'private history failure'); END");
  EXPECT_FALSE(store_->RecordMessageView("A", {"echo", "generation", "42"}));
  auto read = store_->IsMessageRead("A", {"echo", "generation", "42"});
  ASSERT_TRUE(read);
  EXPECT_FALSE(*read);
  auto history = store_->GetHistory("A");
  ASSERT_TRUE(history);
  EXPECT_TRUE(history->empty());
  other.Exec("DROP TRIGGER reject_view");
  ASSERT_TRUE(store_->RecordMessageView("A", {"echo", "generation", "42"}));
  ASSERT_TRUE(store_->RecordMessageView("A", {"echo", "generation", "42"}));
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM read_status"), 1);
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM history"), 1);
}

TEST(SQLiteLifecycle, EveryOperationRejectsAnUnopenedStore) {
  test::TempDirectory temporary;
  auto store = storage::CreateSQLiteStore(temporary.path() / "metadata.db");
  storage::TokenDigest digest{};
  EXPECT_FALSE(store->GetBookmarks("A"));
  EXPECT_FALSE(store->AddBookmark("A", "echo"));
  EXPECT_FALSE(store->RemoveBookmark("A", "echo"));
  EXPECT_FALSE(store->IsBookmarked("A", "echo"));
  EXPECT_FALSE(store->GetHistory("A"));
  EXPECT_FALSE(store->ClearHistory("A"));
  EXPECT_FALSE(store->AddToHistory("A", "echo"));
  EXPECT_FALSE(store->IsMessageRead("A", {"echo", "generation", "1"}));
  EXPECT_FALSE(store->MarkMessageRead("A", {"echo", "generation", "1"}));
  EXPECT_FALSE(store->GetReadCount("A", "echo", "generation"));
  EXPECT_FALSE(store->RecordMessageView("A", {"echo", "generation", "1"}));
  EXPECT_FALSE(store->GetProfile("A"));
  EXPECT_FALSE(store->SaveProfile("A", {}));
  EXPECT_FALSE(store->ProvisionToken("A", {}, digest, 100));
  EXPECT_FALSE(store->RevokeToken(digest));
  EXPECT_FALSE(store->AuthenticateToken(digest, 0));
  EXPECT_FALSE(store->FindOperation("A", "op"));
  EXPECT_FALSE(store->PrepareOperation({}));
  EXPECT_FALSE(store->SetOperationState("A", "op", storage::OperationState::kCommitted));
  EXPECT_FALSE(store->PendingOperations());
  EXPECT_FALSE(fs::exists(temporary.path() / "metadata.db"));
  ASSERT_TRUE(store->Init());
  EXPECT_TRUE(store->GetBookmarks("A"));
}

TEST_F(SQLiteStoreTest, MissingTablesRejectWritesAndTokenJournalQueries) {
  RawDb other(db_path_);
  other.Exec("DROP TABLE operations; DROP TABLE tokens; DROP TABLE bookmarks; DROP TABLE history; "
             "DROP TABLE read_status; DROP TABLE users;");
  storage::TokenDigest digest{};
  EXPECT_FALSE(store_->AddBookmark("A", "echo"));
  EXPECT_FALSE(store_->RemoveBookmark("A", "echo"));
  EXPECT_FALSE(store_->ClearHistory("A"));
  EXPECT_FALSE(store_->AddToHistory("A", "echo"));
  EXPECT_FALSE(store_->MarkMessageRead("A", {"echo", "generation", "1"}));
  EXPECT_FALSE(store_->RecordMessageView("A", {"echo", "generation", "1"}));
  EXPECT_FALSE(store_->SaveProfile("A", {}));
  EXPECT_FALSE(store_->ProvisionToken("A", {}, digest, 100));
  EXPECT_FALSE(store_->RevokeToken(digest));
  EXPECT_FALSE(store_->AuthenticateToken(digest, 0));
  EXPECT_FALSE(store_->FindOperation("A", "op"));
  EXPECT_FALSE(store_->PrepareOperation({}));
  EXPECT_FALSE(store_->SetOperationState("A", "op", storage::OperationState::kCommitted));
  EXPECT_FALSE(store_->PendingOperations());
}

TEST_F(SQLiteStoreTest, FailedTokenInsertRollsBackAssignedProfile) {
  const domain::Profile original{"Original", "2:1/1", "", "old"};
  ASSERT_TRUE(store_->SaveProfile("A", original));
  RawDb other(db_path_);
  other.Exec("CREATE TRIGGER reject_token BEFORE INSERT ON tokens BEGIN SELECT RAISE(ABORT,'secret'); END");
  storage::TokenDigest digest{};
  EXPECT_FALSE(store_->ProvisionToken("A", {"Changed", "2:1/2", "", "new"}, digest, 100));
  auto profile = store_->GetProfile("A");
  ASSERT_TRUE(profile);
  EXPECT_EQ(profile->name, original.name);
  EXPECT_EQ(profile->address, original.address);
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM tokens"), 0);
  other.Exec("DROP TRIGGER reject_token");
  ASSERT_TRUE(store_->ProvisionToken("A", original, digest, 100));
  EXPECT_TRUE(store_->AuthenticateToken(digest, 99));
  EXPECT_FALSE(store_->AuthenticateToken(digest, 100));
  EXPECT_FALSE(store_->ProvisionToken("B", original, digest, 100));
  EXPECT_FALSE(store_->GetProfile("B"));
}

TEST_F(SQLiteStoreTest, FailedDeletesPreserveBookmarksAndHistory) {
  ASSERT_TRUE(store_->SaveProfile("A", {}));
  ASSERT_TRUE(store_->AddBookmark("A", "echo"));
  ASSERT_TRUE(store_->AddToHistory("A", "echo"));
  RawDb other(db_path_);
  other.Exec("CREATE TRIGGER keep_bookmark BEFORE DELETE ON bookmarks BEGIN SELECT RAISE(ABORT,'secret'); END; "
             "CREATE TRIGGER keep_history BEFORE DELETE ON history BEGIN SELECT RAISE(ABORT,'secret'); END;");
  EXPECT_FALSE(store_->RemoveBookmark("A", "echo"));
  EXPECT_FALSE(store_->ClearHistory("A"));
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM bookmarks"), 1);
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM history"), 1);
  other.Exec("DROP TRIGGER keep_bookmark; DROP TRIGGER keep_history");
  EXPECT_TRUE(store_->RemoveBookmark("A", "echo"));
  EXPECT_TRUE(store_->ClearHistory("A"));
}

TEST_F(SQLiteStoreTest, BusyTransactionsDoNotStartViewOrTokenMutation) {
  ASSERT_TRUE(store_->SaveProfile("A", {}));
  RawDb other(db_path_);
  other.Exec("BEGIN IMMEDIATE");
  storage::TokenDigest digest{};
  EXPECT_FALSE(store_->RecordMessageView("A", {"echo", "generation", "1"}));
  EXPECT_FALSE(store_->ProvisionToken("B", {}, digest, 100));
  EXPECT_FALSE(store_->GetProfile("B"));
  other.Exec("ROLLBACK");
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM read_status"), 0);
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM history"), 0);
  EXPECT_EQ(other.Scalar("SELECT COUNT(*) FROM tokens"), 0);
}

TEST_F(SQLiteStoreTest, JournalRejectsDamagedRecordsWithoutReturningPartialResults) {
  ASSERT_TRUE(store_->SaveProfile("A", {}));
  storage::Operation operation;
  operation.user = "A";
  operation.id = "op";
  operation.conference = "echo";
  operation.generation = "generation";
  operation.ftn_msgid = "2:1/1 op";
  operation.plan.number = 1;
  operation.plan.header.resize(76);
  ASSERT_TRUE(store_->PrepareOperation(operation));
  RawDb other(db_path_);
  other.Exec("PRAGMA ignore_check_constraints=ON");
  for (const auto* damage : {"payload_hash=x'00'", "payload_hash='text'", "base_before=x'00'", "base_after=x'00'",
                             "index_append=x'00'", "message_number=-1", "message_number=4294967296",
                             "message_number='text'", "header_size=-1", "text_size=4294967296", "index_size=-1",
                             "header_append=x'00'", "header_append=zeroblob(65613)", "header_append=printf('%076d',0)",
                             "text_append='text'", "text_append=zeroblob(1048577)", "state=-1", "state=4"}) {
    SCOPED_TRACE(damage);
    other.Exec((std::string("UPDATE operations SET ") + damage).c_str());
    auto found = store_->FindOperation("A", "op");
    ASSERT_FALSE(found);
    EXPECT_EQ(found.error().message, "Invalid operation journal");
    // Out-of-range state is deliberately outside the pending query predicate.
    if (std::string_view(damage).find("state=") != 0)
      EXPECT_FALSE(store_->PendingOperations());
    other.Exec("DELETE FROM operations");
    ASSERT_TRUE(store_->PrepareOperation(operation));
  }
  EXPECT_FALSE(store_->SetOperationState("A", "missing", storage::OperationState::kCommitted));
  EXPECT_TRUE(store_->SetOperationState("A", "op", storage::OperationState::kCommitted));
  EXPECT_FALSE(store_->PrepareOperation(operation));
  ASSERT_TRUE(store_->SetOperationState("A", "op", storage::OperationState::kRolledBack));
  auto changed = operation;
  changed.payload_hash[0] = 1;
  EXPECT_FALSE(store_->PrepareOperation(changed));
  changed = operation;
  changed.conference = "other";
  EXPECT_FALSE(store_->PrepareOperation(changed));
  changed = operation;
  changed.ftn_msgid = "other";
  EXPECT_FALSE(store_->PrepareOperation(changed));
  EXPECT_TRUE(store_->PrepareOperation(operation));
}

TEST(SQLiteMigration, EmbeddedNulPathAndMemoryDatabaseRejectInitialization) {
  test::TempDirectory temporary;
  const auto prefix = (temporary.path() / "metadata.db").string();
  auto invalid = storage::CreateSQLiteStore(fs::path(prefix + std::string("\0suffix", 7)));
  EXPECT_FALSE(invalid->Init());
  EXPECT_FALSE(fs::exists(prefix));
  auto memory = storage::CreateSQLiteStore(":memory:");
  EXPECT_FALSE(memory->Init());  // WAL is mandatory, including after a successful sqlite open.
}

namespace {
// SQLite's documented allocator interface injects a single allocation failure.
// Configure only with all SQLite connections closed; always restore the allocator.
class SQLiteAllocationFault {
public:
  SQLiteAllocationFault() {
    EXPECT_EQ(sqlite3_shutdown(), SQLITE_OK);
    EXPECT_EQ(sqlite3_config(SQLITE_CONFIG_GETMALLOC, &original), SQLITE_OK);
    auto injected = original;
    injected.xMalloc = Allocate;
    injected.xRealloc = Reallocate;
    EXPECT_EQ(sqlite3_config(SQLITE_CONFIG_MALLOC, &injected), SQLITE_OK);
    EXPECT_EQ(sqlite3_config(SQLITE_CONFIG_LOOKASIDE, 0, 0), SQLITE_OK);
  }
  ~SQLiteAllocationFault() {
    countdown = 0;
    sqlite3_shutdown();
    sqlite3_config(SQLITE_CONFIG_MALLOC, &original);
    sqlite3_config(SQLITE_CONFIG_LOOKASIDE, 1200, 40);
  }
  static void FailAt(int allocation) {
    countdown = allocation;
  }
  static bool Reject() {
    return countdown > 0 && --countdown == 0;
  }
  static void* Allocate(int size) {
    return Reject() ? nullptr : original.xMalloc(size);
  }
  static void* Reallocate(void* memory, int size) {
    return Reject() ? nullptr : original.xRealloc(memory, size);
  }
  static inline sqlite3_mem_methods original{};
  static inline int countdown = 0;
};
}  // namespace

TEST(SQLiteFaults, AllocationFailuresPropagateThroughQueriesBindingsAndTransactions) {
  SQLiteAllocationFault allocation_fault;
  test::TempDirectory temporary;
  const auto path = temporary.path() / "metadata.db";
  auto store = storage::CreateSQLiteStore(path);
  ASSERT_TRUE(store->Init());
  const domain::Profile profile{"Name", "2:1/1", "mail", "date"};
  storage::TokenDigest digest{};
  ASSERT_TRUE(store->ProvisionToken("A", profile, digest, 100));
  ASSERT_TRUE(store->AddBookmark("A", "echo"));
  ASSERT_TRUE(store->AddToHistory("A", "echo"));
  ASSERT_TRUE(store->MarkMessageRead("A", {"echo", "generation", "1"}));
  storage::Operation operation;
  operation.user = "A";
  operation.id = "op";
  operation.conference = "echo";
  operation.generation = "generation";
  operation.ftn_msgid = "2:1/1 op";
  operation.plan.number = 1;
  operation.plan.header.resize(76);
  ASSERT_TRUE(store->PrepareOperation(operation));
  RawDb raw(path);
  auto run_faults = [&](std::string_view name, auto action, std::function<void()> before = {}) {
    int failures = 0;
    for (int position = 1; position <= 100; ++position) {
      SCOPED_TRACE(std::string(name) + " allocation " + std::to_string(position));
      if (before)
        before();
      SQLiteAllocationFault::FailAt(position);
      auto result = action();
      SQLiteAllocationFault::FailAt(0);
      if (!result) {
        ++failures;
        EXPECT_EQ(result.error().code, domain::ErrorCode::kServer);
        EXPECT_EQ(result.error().message.find(path.string()), std::string::npos);
      }
    }
    EXPECT_GT(failures, 0) << name;
  };
  run_faults("bookmarks", [&] { return store->GetBookmarks("A"); });
  run_faults("add bookmark", [&] { return store->AddBookmark("A", "echo"); });
  run_faults("remove bookmark", [&] { return store->RemoveBookmark("A", "echo"); });
  run_faults("is bookmarked", [&] { return store->IsBookmarked("A", "echo"); });
  run_faults("history", [&] { return store->GetHistory("A"); });
  run_faults("clear history", [&] { return store->ClearHistory("A"); });
  run_faults("add history", [&] { return store->AddToHistory("A", "echo"); });
  run_faults("is read", [&] { return store->IsMessageRead("A", {"echo", "generation", "1"}); });
  run_faults("mark read", [&] { return store->MarkMessageRead("A", {"echo", "generation", "1"}); });
  run_faults("read count", [&] { return store->GetReadCount("A", "echo", "generation"); });
  run_faults("record view", [&] { return store->RecordMessageView("A", {"echo", "generation", "1"}); });
  run_faults("profile", [&] { return store->GetProfile("A"); });
  run_faults("save profile", [&] { return store->SaveProfile("A", profile); });
  run_faults("authenticate", [&] { return store->AuthenticateToken(digest, 0); });
  run_faults("revoke", [&] { return store->RevokeToken(digest); });
  run_faults("find operation", [&] { return store->FindOperation("A", "op"); });
  run_faults("pending operations", [&] { return store->PendingOperations(); });
  run_faults("operation state", [&] { return store->SetOperationState("A", "op", storage::OperationState::kPending); });
  storage::TokenDigest provision_digest{};
  provision_digest[0] = 1;
  run_faults(
      "provision", [&] { return store->ProvisionToken("B", profile, provision_digest, 100); },
      [&] { raw.Exec("DELETE FROM tokens WHERE user_id='B'; DELETE FROM users WHERE user_id='B'"); });
  run_faults(
      "prepare intent", [&] { return store->PrepareOperation(operation); },
      [&] { raw.Exec("UPDATE operations SET state=2 WHERE operation_id='op'"); });
  ASSERT_TRUE(store->SetOperationState("A", "op", storage::OperationState::kPending));
  auto pending = store->PendingOperations();
  ASSERT_TRUE(pending);
  ASSERT_EQ(pending->size(), 1);
  EXPECT_EQ(pending->front().ftn_msgid, operation.ftn_msgid);
  RawDb db(path);
  sqlite3_stmt* check = nullptr;
  ASSERT_EQ(sqlite3_prepare_v2(db.db, "PRAGMA integrity_check", -1, &check, nullptr), SQLITE_OK);
  ASSERT_EQ(sqlite3_step(check), SQLITE_ROW);
  EXPECT_STREQ(reinterpret_cast<const char*>(sqlite3_column_text(check, 0)), "ok");
  sqlite3_finalize(check);
}

TEST(SQLiteFaults, AllocationFailuresDuringInitializationAllowCleanRetry) {
  SQLiteAllocationFault allocation_fault;
  test::TempDirectory temporary;
  int failures = 0;
  for (int position = 1; position <= 350; ++position) {
    SCOPED_TRACE(position);
    auto path = temporary.path() / (std::to_string(position) + ".db");
    auto store = storage::CreateSQLiteStore(path);
    SQLiteAllocationFault::FailAt(position);
    auto initialized = store->Init();
    SQLiteAllocationFault::FailAt(0);
    if (!initialized)
      ++failures;
    ASSERT_TRUE(store->Init());
    ASSERT_TRUE(store->SaveProfile("A", {}));
    RawDb db(path);
    EXPECT_EQ(db.Scalar("PRAGMA user_version"), 10);
    EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM users"), 1);
    EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM read_status"), 0);
  }
  EXPECT_GT(failures, 0);
}

TEST(SQLiteMigration, CanonicalAddressConflictRollsBackVersionFiveAndCanRetry) {
  test::TempDirectory temp;
  const auto path = temp.path() / "metadata.db";
  {
    auto store = storage::CreateSQLiteStore(path);
    ASSERT_TRUE(store->Init());
    ASSERT_TRUE(store->SaveProfile("A", {"Name", "2:1/3", "", ""}));
    ASSERT_TRUE(store->AddBookmark("A", "RU.TEST"));
  }
  {
    RawDb db(path);
    db.Exec("DROP TABLE crosspost_groups; DROP TABLE uue_uploads; DROP TABLE bulk_read_operations; DROP TABLE "
            "mail_export_log; DROP TABLE "
            "reading_positions; DROP TABLE "
            "mail_pipeline; DROP TABLE "
            "mail_outbox; DROP TABLE "
            "mail_provenance; DROP TABLE mail_intents; "
            "DROP TABLE mail_transfers; "
            "DROP TABLE mail_deliveries; DROP TABLE mailbox_bindings; DROP INDEX "
            "users_ftn_address; DROP TABLE auth_credentials; ALTER TABLE "
            "tokens DROP COLUMN fingerprint; "
            "PRAGMA user_version=4;");
    db.Exec("INSERT INTO users(user_id,name,ftn_address) VALUES('B','Other','02:1/3.0')");
  }
  auto store = storage::CreateSQLiteStore(path);
  EXPECT_FALSE(store->Init());
  {
    RawDb db(path);
    EXPECT_EQ(db.Scalar("PRAGMA user_version"), 4);
    EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM users"), 2);
    EXPECT_EQ(db.Scalar("SELECT COUNT(*) FROM bookmarks WHERE user_id='A'"), 1);
    db.Exec("UPDATE users SET ftn_address='2:1/4.0' WHERE user_id='B'");
  }
  ASSERT_TRUE(store->Init());
  EXPECT_EQ(store->GetProfile("B")->address, "2:1/4");
  EXPECT_TRUE(*store->IsBookmarked("A", "RU.TEST"));
}

TEST(SQLiteFaults, MailCommitKeepsCopyProvenanceOutboxAndReadStatusAtomic) {
  test::TempDirectory temp;
  for (int position = 1; position <= 150; ++position) {
    SCOPED_TRACE(position);
    auto path = temp.path() / (std::to_string(position) + ".db");
    auto store = storage::CreateSQLiteStore(path);
    ASSERT_TRUE(store->Init());
    ASSERT_TRUE(store->SaveProfile("A", {"Name", "2:1/2.1", "", ""}));
    storage::Operation operation;
    operation.user = "A";
    operation.id = "mail";
    operation.conference = "P1";
    operation.generation = "g";
    operation.ftn_msgid = "2:1/2.1 same";
    operation.plan.header.resize(76);
    operation.plan.number = 1;
    operation.mail_direction = 2;
    operation.recipient = "2:1/9.7";
    ASSERT_TRUE(store->PrepareOperation(operation));
    SQLiteAllocationFault::FailAt(position);
    auto committed = store->SetOperationState("A", "mail", storage::OperationState::kCommitted);
    SQLiteAllocationFault::FailAt(0);
    auto found = store->FindOperation("A", "mail");
    ASSERT_TRUE(found);
    ASSERT_TRUE(*found);
    const bool durable = (*found)->state == storage::OperationState::kCommitted;
    auto outbox = store->PendingOutbox();
    ASSERT_TRUE(outbox);
    EXPECT_EQ(outbox->size(), durable ? 1u : 0u);
    EXPECT_EQ(*store->MailDirection({"P1", "g", "1"}), durable ? 2 : 0);
    EXPECT_EQ(*store->IsMessageRead("A", {"P1", "g", "1"}), durable);
    if (committed)
      EXPECT_TRUE(durable);
    ASSERT_TRUE(store->SetOperationState("A", "mail", storage::OperationState::kCommitted));
    EXPECT_EQ(store->PendingOutbox()->size(), 1u);
  }
}

TEST(SQLiteStore, ConcurrentViewsUseCommitRevisionsAndKeepBothReadMarks) {
  test::TempDirectory temp;
  const auto path = temp.path() / "positions.db";
  auto phone = storage::CreateSQLiteStore(path), laptop = storage::CreateSQLiteStore(path);
  ASSERT_TRUE(phone->Init());
  ASSERT_TRUE(laptop->Init());
  ASSERT_TRUE(phone->SaveProfile("A", {"Same", "2:1/2.1", "", ""}));
  ASSERT_TRUE(phone->SaveProfile("B", {"Same", "2:1/2.2", "", ""}));
  auto first = std::async(std::launch::async, [&] { return phone->RecordMessageView("A", {"P1", "generation", "1"}); });
  auto second =
      std::async(std::launch::async, [&] { return laptop->RecordMessageView("A", {"P1", "generation", "2"}); });
  auto a = first.get(), b = second.get();
  ASSERT_TRUE(a);
  ASSERT_TRUE(b);
  EXPECT_NE(a->revision, b->revision);
  EXPECT_EQ(std::max(a->revision, b->revision), 2u);
  auto position = phone->LastOpened("A", "P1");
  ASSERT_TRUE(position);
  EXPECT_EQ(position->message, a->revision > b->revision ? "1" : "2");
  EXPECT_EQ(position->revision, 2u);
  EXPECT_TRUE(*laptop->IsMessageRead("A", {"P1", "generation", "1"}));
  EXPECT_TRUE(*phone->IsMessageRead("A", {"P1", "generation", "2"}));
  EXPECT_EQ(phone->LastOpened("B", "P1")->revision, 0u);
  EXPECT_FALSE(*phone->IsMessageRead("B", {"P1", "generation", "1"}));
  ASSERT_TRUE(phone->RecordMessageView("A", {"P1", "new-generation", "1"}));
  EXPECT_EQ(phone->LastOpened("A", "P1")->revision, 3u);
  EXPECT_EQ(*phone->GetReadCount("A", "P1", "generation"), 2);
  EXPECT_EQ(*phone->GetReadCount("A", "P1", "new-generation"), 1);
}

TEST_F(SQLiteStoreTest, BulkReadAtomicReplayAndIsolation) {
  ASSERT_TRUE(store_->SaveProfile("A", {"A", "2:1/2.1", "", ""}));
  ASSERT_TRUE(store_->SaveProfile("B", {"B", "2:1/2.2", "", ""}));
  ASSERT_TRUE(store_->RecordMessageView("A", {"@ffido/2/local", "g", "1"}));
  const auto position = *store_->LastOpened("A", "@ffido/2/local");
  auto result = store_->MarkConferenceRead("A", "bulk", "@ffido/2/local", "g", {1, 3, 7});
  ASSERT_TRUE(result);
  EXPECT_EQ(result->marked_count, 2);
  EXPECT_EQ(result->snapshot_count, 3);
  EXPECT_FALSE(*store_->IsMessageRead("B", {"@ffido/2/local", "g", "3"}));
  EXPECT_EQ(store_->LastOpened("A", "@ffido/2/local")->revision, position.revision);
  EXPECT_EQ(store_->GetHistory("A")->size(), 1);
  store_.reset();
  store_ = storage::CreateSQLiteStore(db_path_);
  ASSERT_TRUE(store_->Init());
  auto replay = store_->MarkConferenceRead("A", "bulk", "@ffido/2/local", "new-generation", {1, 3, 7, 8});
  ASSERT_TRUE(replay);
  EXPECT_EQ(replay->generation, "g");
  EXPECT_EQ(replay->marked_count, 2);
  EXPECT_FALSE(*store_->IsMessageRead("A", {"@ffido/2/local", "g", "8"}));
  EXPECT_FALSE(*store_->IsMessageRead("A", {"@ffido/2/local", "new-generation", "1"}));
  auto conflict = store_->MarkConferenceRead("A", "bulk", "OTHER", "g", {});
  ASSERT_FALSE(conflict);
  EXPECT_EQ(conflict.error().code, domain::ErrorCode::kConflict);
  auto empty = store_->MarkConferenceRead("A", "empty", "@ffido/2/local", "g", {});
  ASSERT_TRUE(empty);
  EXPECT_EQ(empty->snapshot_count, 0);
}
TEST_F(SQLiteStoreTest, BulkReadRollsBackOnCancellationOrSqlFailure) {
  ASSERT_TRUE(store_->SaveProfile("A", {"A", "2:1/2.1", "", ""}));
  int checked = 0;
  auto cancelled =
      store_->MarkConferenceRead("A", "cancel", "@ffido/2/local", "g", {1, 2, 3}, [&] { return ++checked < 3; });
  EXPECT_FALSE(cancelled);
  EXPECT_EQ(*store_->GetReadCount("A", "@ffido/2/local", "g"), 0);
  EXPECT_FALSE(*store_->FindBulkRead("A", "cancel", "@ffido/2/local"));
  sqlite3* db = nullptr;
  ASSERT_EQ(sqlite3_open(db_path_.c_str(), &db), SQLITE_OK);
  ASSERT_EQ(
      sqlite3_exec(
          db, "CREATE TRIGGER fail_bulk BEFORE INSERT ON bulk_read_operations BEGIN SELECT RAISE(ABORT,'fixture'); END",
          nullptr, nullptr, nullptr),
      SQLITE_OK);
  auto failed = store_->MarkConferenceRead("A", "failure", "@ffido/2/local", "g", {1, 2, 3});
  EXPECT_FALSE(failed);
  EXPECT_EQ(*store_->GetReadCount("A", "@ffido/2/local", "g"), 0);
  ASSERT_EQ(sqlite3_exec(db, "DROP TRIGGER fail_bulk", nullptr, nullptr, nullptr), SQLITE_OK);
  sqlite3_close(db);
  auto reading =
      std::async(std::launch::async, [&] { return store_->RecordMessageView("A", {"@ffido/2/local", "g", "1"}); });
  ASSERT_TRUE(store_->MarkConferenceRead("A", "success", "@ffido/2/local", "g", {1, 2, 3}));
  ASSERT_TRUE(reading.get());
  EXPECT_EQ(*store_->GetReadCount("A", "@ffido/2/local", "g"), 3);
}
TEST_F(SQLiteStoreTest, BulkReadMigratesSevenWithoutLosingExistingData) {
  ASSERT_TRUE(store_->SaveProfile("A", {"A", "2:1/2.1", "", ""}));
  ASSERT_TRUE(store_->RecordMessageView("A", {"ECHO", "g", "9"}));
  store_.reset();
  sqlite3* db = nullptr;
  ASSERT_EQ(sqlite3_open(db_path_.c_str(), &db), SQLITE_OK);
  ASSERT_EQ(
      sqlite3_exec(
          db,
          "DROP TABLE crosspost_groups; DROP TABLE uue_uploads; DROP TABLE bulk_read_operations; PRAGMA user_version=7",
          nullptr, nullptr, nullptr),
      SQLITE_OK);
  sqlite3_close(db);
  store_ = storage::CreateSQLiteStore(db_path_);
  ASSERT_TRUE(store_->Init());
  EXPECT_TRUE(*store_->IsMessageRead("A", {"ECHO", "g", "9"}));
  EXPECT_EQ(store_->LastOpened("A", "ECHO")->message, "9");
  EXPECT_EQ(store_->GetProfile("A")->address, "2:1/2.1");
}

TEST_F(SQLiteStoreTest, UueStagingIsDurableBinaryScopedAndCompareAndSwapBounded) {
  ASSERT_TRUE(store_->SaveProfile("A", domain::Profile{"A", "2:1/2.1", "", ""}));
  ASSERT_TRUE(store_->SaveProfile("B", domain::Profile{"B", "2:1/2.2", "", ""}));
  storage::UueUpload value;
  value.user = "A";
  value.id = "uue";
  value.filename = "file.bin";
  value.sha256 = std::string(64, 'a');
  value.size = 4;
  value.data = std::string("\0\xff\x01", 3);
  value.updated_at = 100;
  ASSERT_TRUE(store_->SaveUueUpload(value, 10, 20));
  EXPECT_FALSE(store_->SaveUueUpload(value, 10, 20));
  auto first = store_->GetUueUpload("A", "uue");
  ASSERT_TRUE(first);
  ASSERT_TRUE(*first);
  EXPECT_EQ((**first).data, value.data);
  EXPECT_EQ((**first).revision, 1);
  EXPECT_FALSE(store_->GetUueUpload("B", "uue")->has_value());
  auto changed = **first;
  changed.filename = "other.bin";
  EXPECT_FALSE(store_->SaveUueUpload(changed, 10, 20));
  changed = **first;
  changed.data += 'z';
  ASSERT_TRUE(store_->SaveUueUpload(changed, 10, 20));
  store_.reset();
  store_ = storage::CreateSQLiteStore(db_path_);
  ASSERT_TRUE(store_->Init());
  auto second = store_->GetUueUpload("A", "uue");
  ASSERT_TRUE(second);
  ASSERT_TRUE(*second);
  EXPECT_EQ((**second).data, value.data + 'z');
  auto quota = **second;
  quota.manifest = "too large";
  EXPECT_FALSE(store_->SaveUueUpload(quota, 10, 20));
  EXPECT_EQ(store_->GetUueUpload("A", "uue")->value().manifest, "");
  ASSERT_TRUE(store_->PruneUueUploads(101));
  EXPECT_FALSE(store_->GetUueUpload("A", "uue")->has_value());
  // A stale revision cannot recreate an expired row.
  EXPECT_FALSE(store_->SaveUueUpload(**second, 10, 20));
}

TEST_F(SQLiteStoreTest, UueMigrationFromEightPreservesReadingAndProfile) {
  ASSERT_TRUE(store_->SaveProfile("A", {"A", "2:1/2.1", "", ""}));
  ASSERT_TRUE(store_->RecordMessageView("A", {"ECHO", "generation", "9"}));
  store_.reset();
  sqlite3* db = nullptr;
  ASSERT_EQ(sqlite3_open(db_path_.c_str(), &db), SQLITE_OK);
  ASSERT_EQ(sqlite3_exec(db, "DROP TABLE crosspost_groups; DROP TABLE uue_uploads; PRAGMA user_version=8", nullptr,
                         nullptr, nullptr),
            SQLITE_OK);
  sqlite3_close(db);
  store_ = storage::CreateSQLiteStore(db_path_);
  ASSERT_TRUE(store_->Init());
  EXPECT_TRUE(store_->IsMessageRead("A", {"ECHO", "generation", "9"}).value());
  EXPECT_EQ(store_->LastOpened("A", "ECHO")->message, "9");
  EXPECT_EQ(store_->GetProfile("A")->address, "2:1/2.1");
  EXPECT_FALSE(store_->GetUueUpload("A", "absent")->has_value());
}

TEST_F(SQLiteStoreTest, CrosspostManifestIsImmutableAndIsolatedAcrossUsersAndReopen) {
  ASSERT_TRUE(store_->SaveProfile("A", {"Alice", "2:1/1.1", "", ""}));
  ASSERT_TRUE(store_->SaveProfile("B", {"Bob", "2:1/1.2", "", ""}));
  ASSERT_TRUE(store_->PrepareCrosspost("A", "group", "manifest"));
  ASSERT_TRUE(store_->PrepareCrosspost("A", "group", "manifest"));
  EXPECT_FALSE(store_->PrepareCrosspost("A", "group", "other"));
  ASSERT_TRUE(store_->PrepareCrosspost("B", "group", "other"));
  store_.reset();
  store_ = storage::CreateSQLiteStore(db_path_);
  ASSERT_TRUE(store_->Init());
  auto a = store_->GetCrosspost("A", "group");
  auto b = store_->GetCrosspost("B", "group");
  ASSERT_TRUE(a && *a);
  ASSERT_TRUE(b && *b);
  EXPECT_EQ(**a, "manifest");
  EXPECT_EQ(**b, "other");
}
