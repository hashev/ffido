#include <limits>

#include "domain/ftn_address.hpp"
#include "storage/metadata_store.hpp"

namespace fidoback::storage {

namespace {

// ─────────────────────────────────────────────────────────────────────────────
// RAII-обёртки для SQLite C API
// ─────────────────────────────────────────────────────────────────────────────

/// @brief RAII-обёртка для SQLite database handle.
/// Заменяет сырой sqlite3* с автоматическим sqlite3_close.
class SQLiteDb {
public:
  SQLiteDb() = default;
  explicit SQLiteDb(sqlite3* db) : db_(db) {
  }
  ~SQLiteDb() {
    reset();
  }

  SQLiteDb(const SQLiteDb&) = delete;
  SQLiteDb& operator=(const SQLiteDb&) = delete;

  SQLiteDb(SQLiteDb&& other) noexcept : db_(other.db_) {
    other.db_ = nullptr;
  }
  SQLiteDb& operator=(SQLiteDb&& other) noexcept {
    if (this != &other) {
      reset();
      db_ = other.db_;
      other.db_ = nullptr;
    }
    return *this;
  }

  sqlite3* get() const {
    return db_;
  }
  sqlite3** ptr() {
    return &db_;
  }
  explicit operator bool() const {
    return db_ != nullptr;
  }
  void reset() {
    if (db_) {
      sqlite3_close_v2(db_);
      db_ = nullptr;
    }
  }

private:
  sqlite3* db_ = nullptr;
};

/// @brief RAII-обёртка для SQLite statement.
class StatementGuard {
public:
  explicit StatementGuard(sqlite3_stmt* stmt) : stmt_(stmt) {
  }
  ~StatementGuard() {
    if (stmt_)
      sqlite3_finalize(stmt_);
  }
  sqlite3_stmt* get() const {
    return stmt_;
  }
  bool Bind(int index, std::string_view value) {
    if (value.size() > static_cast<size_t>(std::numeric_limits<int>::max()))
      return false;
    return sqlite3_bind_text(stmt_, index, value.empty() ? "" : value.data(), static_cast<int>(value.size()),
                             SQLITE_TRANSIENT) == SQLITE_OK;
  }
  bool Bind(int index, int64_t value) {
    return sqlite3_bind_int64(stmt_, index, value) == SQLITE_OK;
  }
  bool Bind(int index, const TokenDigest& digest) {
    return sqlite3_bind_blob(stmt_, index, digest.data(), static_cast<int>(digest.size()), SQLITE_TRANSIENT) ==
           SQLITE_OK;
  }
  bool Blob(int index, std::span<const uint8_t> value) {
    if (value.size() > INT_MAX)
      return false;
    return sqlite3_bind_blob(stmt_, index, value.empty() ? static_cast<const void*>("") : value.data(),
                             static_cast<int>(value.size()), SQLITE_TRANSIENT) == SQLITE_OK;
  }
  StatementGuard(const StatementGuard&) = delete;
  StatementGuard& operator=(const StatementGuard&) = delete;

private:
  sqlite3_stmt* stmt_;
};

// Public errors intentionally omit SQLite diagnostics and filesystem paths.
domain::ApiError SqliteError(sqlite3*, std::string_view) {
  return domain::ApiError::Server("Metadata storage operation failed");
}

std::string ColumnText(sqlite3_stmt* statement, int column) {
  const auto* value = sqlite3_column_text(statement, column);
  const auto length = sqlite3_column_bytes(statement, column);
  return value ? std::string(reinterpret_cast<const char*>(value), length) : std::string{};
}

constexpr const char* kSchema = R"(
  CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    name TEXT NOT NULL DEFAULT '',
    ftn_address TEXT NOT NULL DEFAULT '',
    email TEXT NOT NULL DEFAULT '',
    registered_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS bookmarks (
    user_id TEXT NOT NULL,
    conference_id TEXT NOT NULL,
    added_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, conference_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS history (
    user_id TEXT NOT NULL,
    conference_id TEXT NOT NULL,
    viewed_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, conference_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS read_status (
    user_id TEXT NOT NULL,
    message_id TEXT NOT NULL,
    conference_id TEXT NOT NULL,
    read_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, message_id)
  );

  CREATE INDEX IF NOT EXISTS idx_history_user_time
    ON history(user_id, viewed_at DESC);
  CREATE INDEX IF NOT EXISTS idx_read_status_user_conf
    ON read_status(user_id, conference_id);
)";

}  // namespace

class SQLiteMetadataStore final : public IMetadataStore {
public:
  explicit SQLiteMetadataStore(std::filesystem::path db_path) : db_path_(std::move(db_path)) {
  }

  ~SQLiteMetadataStore() override {
    std::lock_guard lock(mutex_);
    db_.reset();  // RAII — sqlite3_close внутри SQLiteDb
  }

  std::expected<void, domain::ApiError> Init() override {
    std::lock_guard lock(mutex_);

    if (db_)
      return {};
    if (db_path_.string().find('\0') != std::string::npos)
      return std::unexpected(SqliteError(nullptr, "path"));
    int rc = sqlite3_open_v2(db_path_.string().c_str(), db_.ptr(),
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nullptr);
    auto fail = [&]() -> std::expected<void, domain::ApiError> {
      db_.reset();
      return std::unexpected(SqliteError(nullptr, "initialization"));
    };
    if (rc != SQLITE_OK)
      return fail();
    if (sqlite3_busy_timeout(db_.get(), 250) != SQLITE_OK)
      return fail();
    if (sqlite3_exec(db_.get(), "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;", nullptr,
                     nullptr, nullptr) != SQLITE_OK)
      return fail();
    int schema_version;
    {
      StatementGuard version(prepare("PRAGMA user_version"));
      if (!version.get() || sqlite3_step(version.get()) != SQLITE_ROW)
        return fail();
      schema_version = sqlite3_column_int(version.get(), 0);
    }
    {
      StatementGuard mode(prepare("PRAGMA journal_mode"));
      if (!mode.get() || sqlite3_step(mode.get()) != SQLITE_ROW || ColumnText(mode.get(), 0) != "wal")
        return fail();
    }
    if (schema_version > 9 || schema_version < 0)
      return fail();
    if (schema_version == 0) {
      if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
        return fail();
      if (sqlite3_exec(db_.get(), kSchema, nullptr, nullptr, nullptr) != SQLITE_OK ||
          sqlite3_exec(db_.get(), "PRAGMA user_version=1; COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    if (schema_version < 2) {
      constexpr const char* migration = R"(
        BEGIN IMMEDIATE;
        ALTER TABLE read_status RENAME TO read_status_legacy_backup;
        DROP INDEX IF EXISTS idx_read_status_user_conf;
        CREATE TABLE read_status (
          user_id TEXT NOT NULL, conference_id TEXT NOT NULL,
          generation TEXT NOT NULL CHECK(length(generation)>0), message_id TEXT NOT NULL,
          read_at TEXT NOT NULL DEFAULT (datetime('now')),
          PRIMARY KEY(user_id, conference_id, generation, message_id),
          FOREIGN KEY(user_id) REFERENCES users(user_id) ON DELETE CASCADE
        );
        PRAGMA user_version=2;
        COMMIT;
      )";
      if (sqlite3_exec(db_.get(), migration, nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    if (schema_version < 3) {
      constexpr const char* migration = R"(
        BEGIN IMMEDIATE;
        ALTER TABLE users ADD COLUMN active INTEGER NOT NULL DEFAULT 1 CHECK(active IN(0,1));
        CREATE TABLE tokens (
          digest BLOB PRIMARY KEY CHECK(length(digest)=32), user_id TEXT NOT NULL,
          expires_at INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0 CHECK(revoked IN(0,1)),
          FOREIGN KEY(user_id) REFERENCES users(user_id) ON DELETE CASCADE
        );
        PRAGMA user_version=3;
        COMMIT;
      )";
      if (sqlite3_exec(db_.get(), migration, nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    if (schema_version < 4) {
      constexpr const char* migration = R"(
        BEGIN IMMEDIATE;
        CREATE TABLE operations (
          user_id TEXT NOT NULL, operation_id TEXT NOT NULL, conference TEXT NOT NULL, generation TEXT NOT NULL,
          ftn_msgid TEXT NOT NULL UNIQUE, payload_hash BLOB NOT NULL CHECK(length(payload_hash)=32),
          message_number INTEGER NOT NULL, header_size INTEGER NOT NULL, text_size INTEGER NOT NULL, index_size INTEGER NOT NULL,
          base_before BLOB NOT NULL CHECK(length(base_before)=1024), base_after BLOB NOT NULL CHECK(length(base_after)=1024),
          header_append BLOB NOT NULL CHECK(length(header_append) BETWEEN 76 AND 65612),
          text_append BLOB NOT NULL CHECK(length(text_append)<=1048576), index_append BLOB NOT NULL CHECK(length(index_append)=8),
          state INTEGER NOT NULL DEFAULT 0 CHECK(state BETWEEN 0 AND 3),
          PRIMARY KEY(user_id,operation_id), FOREIGN KEY(user_id) REFERENCES users(user_id)
        );
        PRAGMA user_version=4;
        COMMIT;
      )";
      if (sqlite3_exec(db_.get(), migration, nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    if (schema_version < 5) {
      if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
        return fail();
      bool valid = true;
      {
        StatementGuard users(prepare("SELECT user_id,ftn_address FROM users"));
        std::map<std::string, std::string> addresses;
        if (!users.get())
          valid = false;
        int row = SQLITE_DONE;
        while (valid && (row = sqlite3_step(users.get())) == SQLITE_ROW) {
          const auto id = ColumnText(users.get(), 0);
          auto address = domain::CanonicalFtnAddress(ColumnText(users.get(), 1));
          if (!address || !addresses.emplace(*address, id).second) {
            valid = false;
            break;
          }
        }
        if (row != SQLITE_DONE)
          valid = false;
        for (const auto& [address, id] : addresses) {
          StatementGuard update(prepare("UPDATE users SET ftn_address=? WHERE user_id=?"));
          if (!update.get() || !update.Bind(1, address) || !update.Bind(2, id) ||
              sqlite3_step(update.get()) != SQLITE_DONE)
            valid = false;
        }
      }
      constexpr const char* migration = R"(
        CREATE UNIQUE INDEX users_ftn_address ON users(ftn_address);
        CREATE TABLE auth_credentials(address TEXT PRIMARY KEY, fingerprint BLOB NOT NULL CHECK(length(fingerprint)=32));
        ALTER TABLE tokens ADD COLUMN fingerprint BLOB;
        UPDATE tokens SET revoked=1;
        PRAGMA user_version=5;
      )";
      if (!valid || sqlite3_exec(db_.get(), migration, nullptr, nullptr, nullptr) != SQLITE_OK ||
          sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    if (schema_version < 6) {
      constexpr const char* migration = R"(
        BEGIN IMMEDIATE;
        CREATE TABLE mailbox_bindings(address TEXT PRIMARY KEY, base TEXT NOT NULL UNIQUE, generation TEXT NOT NULL UNIQUE, files TEXT NOT NULL UNIQUE);
        PRAGMA user_version=6;
        COMMIT;
      )";
      if (sqlite3_exec(db_.get(), migration, nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    if (schema_version < 7) {
      constexpr const char* migration = R"(
        BEGIN IMMEDIATE;
        CREATE TABLE operations_next (
          user_id TEXT NOT NULL, operation_id TEXT NOT NULL, conference TEXT NOT NULL, generation TEXT NOT NULL,
          ftn_msgid TEXT NOT NULL, payload_hash BLOB NOT NULL CHECK(length(payload_hash)=32),
          message_number INTEGER NOT NULL, header_size INTEGER NOT NULL, text_size INTEGER NOT NULL, index_size INTEGER NOT NULL,
          base_before BLOB NOT NULL CHECK(length(base_before)=1024), base_after BLOB NOT NULL CHECK(length(base_after)=1024),
          header_append BLOB NOT NULL CHECK(length(header_append) BETWEEN 76 AND 65612),
          text_append BLOB NOT NULL CHECK(length(text_append)<=1048576), index_append BLOB NOT NULL CHECK(length(index_append)=8),
          state INTEGER NOT NULL DEFAULT 0 CHECK(state BETWEEN 0 AND 3), copy_scope TEXT NOT NULL DEFAULT '',
          PRIMARY KEY(user_id,operation_id), UNIQUE(ftn_msgid,copy_scope), FOREIGN KEY(user_id) REFERENCES users(user_id));
        INSERT INTO operations_next SELECT user_id,operation_id,conference,generation,ftn_msgid,payload_hash,message_number,header_size,text_size,index_size,base_before,base_after,header_append,text_append,index_append,state,'' FROM operations;
        DROP TABLE operations;
        ALTER TABLE operations_next RENAME TO operations;
        CREATE TABLE mail_intents(user_id TEXT NOT NULL, operation_id TEXT NOT NULL, direction INTEGER NOT NULL CHECK(direction BETWEEN 1 AND 3),
          recipient TEXT NOT NULL, PRIMARY KEY(user_id,operation_id), FOREIGN KEY(user_id,operation_id) REFERENCES operations(user_id,operation_id));
        CREATE TABLE mail_provenance(conference TEXT NOT NULL,generation TEXT NOT NULL,message_number INTEGER NOT NULL,
          direction INTEGER NOT NULL CHECK(direction BETWEEN 1 AND 3),user_id TEXT NOT NULL,operation_id TEXT NOT NULL,
          PRIMARY KEY(conference,generation,message_number), UNIQUE(user_id,operation_id),
          FOREIGN KEY(user_id,operation_id) REFERENCES operations(user_id,operation_id));
        CREATE TABLE mail_outbox(user_id TEXT NOT NULL,operation_id TEXT NOT NULL,state INTEGER NOT NULL DEFAULT 0 CHECK(state BETWEEN 0 AND 3),
          PRIMARY KEY(user_id,operation_id),FOREIGN KEY(user_id,operation_id) REFERENCES operations(user_id,operation_id));
        CREATE TABLE reading_positions(user_id TEXT NOT NULL,conference TEXT NOT NULL,generation TEXT NOT NULL,message_id TEXT NOT NULL,
          revision INTEGER NOT NULL CHECK(revision>0),PRIMARY KEY(user_id,conference),FOREIGN KEY(user_id) REFERENCES users(user_id));
        CREATE TABLE mail_export_log(id INTEGER PRIMARY KEY, phase TEXT NOT NULL CHECK(phase IN('begin','complete','uncertain','reconciled')),
          recorded_at TEXT NOT NULL DEFAULT (datetime('now')));
        CREATE TABLE mail_pipeline(id INTEGER PRIMARY KEY CHECK(id=1), state INTEGER NOT NULL CHECK(state BETWEEN 0 AND 2));
        INSERT INTO mail_pipeline VALUES(1,0);
        CREATE TABLE mail_deliveries(delivery_key TEXT PRIMARY KEY, payload_hash BLOB NOT NULL CHECK(length(payload_hash)=32));
        CREATE TABLE mail_transfers(
          source_key TEXT PRIMARY KEY, delivery_key TEXT NOT NULL, source_conference TEXT NOT NULL,
          source_generation TEXT NOT NULL, source_number INTEGER NOT NULL, original_flags INTEGER NOT NULL,
          payload_hash BLOB NOT NULL CHECK(length(payload_hash)=32), source_hash BLOB NOT NULL CHECK(length(source_hash)=32),
          target_conference TEXT NOT NULL, target_operation TEXT NOT NULL,
          state INTEGER NOT NULL CHECK(state BETWEEN 0 AND 5), duplicate INTEGER NOT NULL CHECK(duplicate IN(0,1)),
          collision INTEGER NOT NULL CHECK(collision IN(0,1)));
        CREATE INDEX mail_transfers_pending ON mail_transfers(state);
        PRAGMA user_version=7;
        COMMIT;
      )";
      if (sqlite3_exec(db_.get(), migration, nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    if (schema_version < 8) {
      if (sqlite3_exec(db_.get(), R"(
        BEGIN IMMEDIATE;
        CREATE TABLE bulk_read_operations(user_id TEXT NOT NULL,operation_id TEXT NOT NULL,
          conference TEXT NOT NULL,generation TEXT NOT NULL,marked_count INTEGER NOT NULL CHECK(marked_count>=0),
          snapshot_count INTEGER NOT NULL CHECK(snapshot_count>=marked_count),PRIMARY KEY(user_id,operation_id),
          FOREIGN KEY(user_id) REFERENCES users(user_id));
        PRAGMA user_version=8;
        COMMIT;
      )",
                       nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    if (schema_version < 9) {
      if (sqlite3_exec(db_.get(), R"(
        BEGIN IMMEDIATE;
        CREATE TABLE uue_uploads(user_id TEXT NOT NULL,operation_id TEXT NOT NULL,
          filename TEXT NOT NULL,sha256 TEXT NOT NULL,size INTEGER NOT NULL CHECK(size>=0),
          data BLOB NOT NULL,manifest TEXT NOT NULL,state TEXT NOT NULL,revision INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,PRIMARY KEY(user_id,operation_id),
          FOREIGN KEY(user_id) REFERENCES users(user_id));
        PRAGMA user_version=9;
        COMMIT;
      )",
                       nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
        return fail();
      }
    }
    return {};
  }

  std::expected<std::optional<UueUpload>, domain::ApiError> GetUueUpload(std::string_view user,
                                                                         std::string_view id) override {
    std::lock_guard lock(mutex_);
    StatementGuard query(prepare("SELECT filename,sha256,size,data,manifest,state,revision,updated_at FROM uue_uploads "
                                 "WHERE user_id=? AND operation_id=?"));
    if (!query.get() || !query.Bind(1, user) || !query.Bind(2, id))
      return std::unexpected(SqliteError(db_.get(), "uue"));
    const auto status = sqlite3_step(query.get());
    if (status == SQLITE_DONE)
      return std::optional<UueUpload>{};
    if (status != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "uue"));
    UueUpload value;
    value.user = user;
    value.id = id;
    value.filename = ColumnText(query.get(), 0);
    value.sha256 = ColumnText(query.get(), 1);
    value.size = static_cast<uint64_t>(sqlite3_column_int64(query.get(), 2));
    const auto* blob = sqlite3_column_blob(query.get(), 3);
    const auto length = sqlite3_column_bytes(query.get(), 3);
    if (length)
      value.data.assign(static_cast<const char*>(blob), length);
    value.manifest = ColumnText(query.get(), 4);
    value.state = ColumnText(query.get(), 5);
    value.revision = sqlite3_column_int64(query.get(), 6);
    value.updated_at = sqlite3_column_int64(query.get(), 7);
    return std::optional<UueUpload>{std::move(value)};
  }
  std::expected<void, domain::ApiError> SaveUueUpload(const UueUpload& value, uint64_t user_quota,
                                                      uint64_t global_quota) override {
    std::lock_guard lock(mutex_);
    if (value.revision < 0 || value.revision == INT64_MAX || value.size > 16 * 1024 * 1024 ||
        value.data.size() > value.size || value.manifest.size() > 32 * 1024 * 1024)
      return std::unexpected(domain::ApiError::Validation("Invalid UUE staging record"));
    if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "uue"));
    struct Rollback {
      sqlite3* db;
      bool active = true;
      ~Rollback() {
        if (active)
          sqlite3_exec(db, "ROLLBACK", nullptr, nullptr, nullptr);
      }
      void Committed() {
        active = false;
      }
    } rollback{db_.get()};
    StatementGuard quota(
        prepare("SELECT coalesce(sum(length(data)+length(manifest)),0),coalesce(sum(CASE WHEN user_id=? THEN "
                "length(data)+length(manifest) ELSE 0 END),0) FROM uue_uploads WHERE state!='completed' AND "
                "NOT(user_id=? AND operation_id=?)"));
    if (!quota.get() || !quota.Bind(1, value.user) || !quota.Bind(2, value.user) || !quota.Bind(3, value.id) ||
        sqlite3_step(quota.get()) != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "uue"));
    const uint64_t addition = value.state == "completed" ? 0 : value.data.size() + value.manifest.size();
    if (addition > user_quota || addition > global_quota ||
        static_cast<uint64_t>(sqlite3_column_int64(quota.get(), 0)) > global_quota - addition ||
        static_cast<uint64_t>(sqlite3_column_int64(quota.get(), 1)) > user_quota - addition)
      return std::unexpected(domain::ApiError{domain::ErrorCode::kResource, "UUE staging quota exceeded", {}});
    StatementGuard previous(prepare("SELECT revision FROM uue_uploads WHERE user_id=? AND operation_id=?"));
    if (!previous.get() || !previous.Bind(1, value.user) || !previous.Bind(2, value.id))
      return std::unexpected(SqliteError(db_.get(), "uue"));
    const auto status = sqlite3_step(previous.get());
    if ((status == SQLITE_DONE && value.revision != 0) ||
        (status == SQLITE_ROW && sqlite3_column_int64(previous.get(), 0) != value.revision))
      return std::unexpected(domain::ApiError{domain::ErrorCode::kConflict, "UUE staging changed", {}});
    if (status != SQLITE_DONE && status != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "uue"));
    StatementGuard query(prepare(
        R"(INSERT INTO uue_uploads(user_id,operation_id,filename,sha256,size,data,manifest,state,revision,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(user_id,operation_id) DO UPDATE SET data=excluded.data,manifest=excluded.manifest,
      state=excluded.state,revision=excluded.revision,updated_at=excluded.updated_at
      WHERE uue_uploads.revision=? AND uue_uploads.filename=excluded.filename AND uue_uploads.sha256=excluded.sha256 AND uue_uploads.size=excluded.size)"));
    if (!query.get() || !query.Bind(1, value.user) || !query.Bind(2, value.id) || !query.Bind(3, value.filename) ||
        !query.Bind(4, value.sha256) || !query.Bind(5, static_cast<int64_t>(value.size)) ||
        !query.Blob(6, {reinterpret_cast<const uint8_t*>(value.data.data()), value.data.size()}) ||
        !query.Bind(7, value.manifest) || !query.Bind(8, value.state) || !query.Bind(9, value.revision + 1) ||
        !query.Bind(10, value.updated_at) || !query.Bind(11, value.revision) ||
        sqlite3_step(query.get()) != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "uue"));
    if (sqlite3_changes(db_.get()) != 1)
      return std::unexpected(domain::ApiError{domain::ErrorCode::kConflict, "UUE staging changed", {}});
    if (sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "uue"));
    rollback.Committed();
    return {};
  }
  std::expected<void, domain::ApiError> PruneUueUploads(int64_t older_than) override {
    std::lock_guard lock(mutex_);
    StatementGuard query(prepare("DELETE FROM uue_uploads WHERE state='uploading' AND updated_at<?"));
    if (!query.get() || !query.Bind(1, older_than) || sqlite3_step(query.get()) != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "uue"));
    return {};
  }
  std::expected<std::vector<MailboxBinding>, domain::ApiError> MailboxBindings() override {
    std::lock_guard lock(mutex_);
    StatementGuard query(prepare("SELECT address,base,generation,files FROM mailbox_bindings ORDER BY address"));
    if (!query.get())
      return std::unexpected(SqliteError(db_.get(), "mailboxes"));
    std::vector<MailboxBinding> result;
    int status;
    while ((status = sqlite3_step(query.get())) == SQLITE_ROW)
      result.push_back({ColumnText(query.get(), 0), ColumnText(query.get(), 1), ColumnText(query.get(), 2),
                        ColumnText(query.get(), 3)});
    if (status != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "mailboxes"));
    return result;
  }
  std::expected<void, domain::ApiError> BindMailbox(const MailboxBinding& binding) override {
    std::lock_guard lock(mutex_);
    auto address = domain::CanonicalFtnAddress(binding.address);
    if (!address || *address != binding.address || binding.base.empty() || binding.generation.empty() ||
        binding.files.empty())
      return std::unexpected(domain::ApiError::Validation("Invalid mailbox binding"));
    StatementGuard query(prepare(
        "INSERT INTO mailbox_bindings(address,base,generation,files) VALUES(?,?,?,?) ON CONFLICT(address) DO UPDATE "
        "SET address=excluded.address WHERE mailbox_bindings.base=excluded.base AND "
        "mailbox_bindings.generation=excluded.generation AND mailbox_bindings.files=excluded.files"));
    if (!query.get() || !query.Bind(1, binding.address) || !query.Bind(2, binding.base) ||
        !query.Bind(3, binding.generation) || !query.Bind(4, binding.files) ||
        sqlite3_step(query.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1)
      return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "Mailbox binding conflicts", {}});
    return {};
  }

  std::expected<std::vector<MailTransfer>, domain::ApiError> MailTransfers(bool include_done) override {
    std::lock_guard lock(mutex_);
    return TransfersUnlocked({}, include_done);
  }
  std::expected<MailTransfer, domain::ApiError> PrepareTransfer(const MailTransfer& input) override {
    std::lock_guard lock(mutex_);
    const auto failure = [&] { return std::unexpected(SqliteError(db_.get(), "transfer")); };
    if (input.source_key.empty() || input.delivery_key.empty() || input.source_generation.empty())
      return failure();
    if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return failure();
    struct Transaction {
      sqlite3* db;
      ~Transaction() {
        sqlite3_exec(db, "ROLLBACK", nullptr, nullptr, nullptr);
      }
    } transaction{db_.get()};
    auto all = TransfersUnlocked(input.source_key);
    if (!all)
      return failure();
    for (const auto& existing : *all)
      if (existing.source_key == input.source_key) {
        if (existing.source_hash != input.source_hash || existing.payload_hash != input.payload_hash ||
            existing.delivery_key != input.delivery_key || existing.target_conference != input.target_conference ||
            existing.target_operation != input.target_operation ||
            existing.source_conference != input.source_conference ||
            existing.source_generation != input.source_generation || existing.source_number != input.source_number)
          return failure();
        if (sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
          return failure();
        return existing;
      }
    auto transfer = input;
    {
      StatementGuard delivery(prepare("SELECT payload_hash FROM mail_deliveries WHERE delivery_key=?"));
      if (!delivery.get() || !delivery.Bind(1, input.delivery_key))
        return failure();
      const auto status = sqlite3_step(delivery.get());
      if (status == SQLITE_ROW) {
        if (sqlite3_column_bytes(delivery.get(), 0) != 32)
          return failure();
        const auto* hash = static_cast<const uint8_t*>(sqlite3_column_blob(delivery.get(), 0));
        transfer.duplicate = std::equal(input.payload_hash.begin(), input.payload_hash.end(), hash);
        transfer.collision = !transfer.duplicate;
        if (transfer.collision)
          transfer.state = TransferState::kQuarantine;
      } else if (status == SQLITE_DONE) {
        StatementGuard insert(prepare("INSERT INTO mail_deliveries VALUES(?,?)"));
        if (!insert.get() || !insert.Bind(1, input.delivery_key) || !insert.Bind(2, input.payload_hash) ||
            sqlite3_step(insert.get()) != SQLITE_DONE)
          return failure();
      } else
        return failure();
    }
    StatementGuard insert(prepare("INSERT INTO mail_transfers VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"));
    if (!insert.get() || !insert.Bind(1, transfer.source_key) || !insert.Bind(2, transfer.delivery_key) ||
        !insert.Bind(3, transfer.source_conference) || !insert.Bind(4, transfer.source_generation) ||
        !insert.Bind(5, int64_t(transfer.source_number)) || !insert.Bind(6, int64_t(transfer.original_flags)) ||
        !insert.Bind(7, transfer.payload_hash) || !insert.Bind(8, transfer.source_hash) ||
        !insert.Bind(9, transfer.target_conference) || !insert.Bind(10, transfer.target_operation) ||
        !insert.Bind(11, int64_t(transfer.state)) || !insert.Bind(12, int64_t(transfer.duplicate)) ||
        !insert.Bind(13, int64_t(transfer.collision)) || sqlite3_step(insert.get()) != SQLITE_DONE ||
        sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return failure();
    return transfer;
  }
  std::expected<void, domain::ApiError> SetTransferState(std::string_view key, TransferState state) override {
    std::lock_guard lock(mutex_);
    StatementGuard update(prepare("UPDATE mail_transfers SET state=? WHERE source_key=? AND (state<=? OR state=?)"));
    if (!update.get() || !update.Bind(1, int64_t(state)) || !update.Bind(2, key) || !update.Bind(3, int64_t(state)) ||
        !update.Bind(4, int64_t(state)) || sqlite3_step(update.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1)
      return std::unexpected(SqliteError(db_.get(), "transfer state"));
    return {};
  }
  std::expected<std::vector<MailTransfer>, domain::ApiError> TransfersUnlocked(std::string_view source_key = {},
                                                                               bool include_done = true) {
    const auto sql = !source_key.empty() ? "SELECT * FROM mail_transfers WHERE source_key=?"
                     : include_done      ? "SELECT * FROM mail_transfers ORDER BY rowid"
                                         : "SELECT * FROM mail_transfers WHERE state IN(0,1,2,3,5) ORDER BY rowid";
    StatementGuard query(prepare(sql));
    if (query.get() && !source_key.empty() && !query.Bind(1, source_key))
      return std::unexpected(SqliteError(db_.get(), "transfer key"));
    if (!query.get())
      return std::unexpected(SqliteError(db_.get(), "transfers"));
    std::vector<MailTransfer> result;
    int status;
    while ((status = sqlite3_step(query.get())) == SQLITE_ROW) {
      MailTransfer t;
      t.source_key = ColumnText(query.get(), 0);
      t.delivery_key = ColumnText(query.get(), 1);
      t.source_conference = ColumnText(query.get(), 2);
      t.source_generation = ColumnText(query.get(), 3);
      const auto number = sqlite3_column_int64(query.get(), 4), flags = sqlite3_column_int64(query.get(), 5);
      if (number < 0 || number > UINT32_MAX || flags < 0 || flags > UINT32_MAX ||
          sqlite3_column_bytes(query.get(), 6) != 32 || sqlite3_column_bytes(query.get(), 7) != 32 ||
          result.size() >= 100000)
        return std::unexpected(SqliteError(db_.get(), "transfer record"));
      t.source_number = static_cast<uint32_t>(number);
      t.original_flags = static_cast<uint32_t>(flags);
      std::copy_n(static_cast<const uint8_t*>(sqlite3_column_blob(query.get(), 6)), 32, t.payload_hash.begin());
      std::copy_n(static_cast<const uint8_t*>(sqlite3_column_blob(query.get(), 7)), 32, t.source_hash.begin());
      t.target_conference = ColumnText(query.get(), 8);
      t.target_operation = ColumnText(query.get(), 9);
      const auto state = sqlite3_column_int(query.get(), 10);
      if (state < 0 || state > 5)
        return std::unexpected(SqliteError(db_.get(), "transfer state"));
      t.state = static_cast<TransferState>(state);
      t.duplicate = sqlite3_column_int(query.get(), 11) != 0;
      t.collision = sqlite3_column_int(query.get(), 12) != 0;
      result.push_back(std::move(t));
    }
    if (status != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "transfers"));
    return result;
  }

  std::expected<int, domain::ApiError> ExportState() override {
    std::lock_guard lock(mutex_);
    StatementGuard query(prepare("SELECT state FROM mail_pipeline WHERE id=1"));
    if (!query.get() || sqlite3_step(query.get()) != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "export state"));
    return sqlite3_column_int(query.get(), 0);
  }
  std::expected<void, domain::ApiError> SetExportState(int expected, int next) override {
    std::lock_guard lock(mutex_);
    if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "export begin"));
    struct Transaction {
      sqlite3* db;
      ~Transaction() {
        sqlite3_exec(db, "ROLLBACK", nullptr, nullptr, nullptr);
      }
    } transaction{db_.get()};
    StatementGuard update(prepare("UPDATE mail_pipeline SET state=? WHERE id=1 AND state=?"));
    if (!update.get() || !update.Bind(1, int64_t(next)) || !update.Bind(2, int64_t(expected)) ||
        sqlite3_step(update.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1)
      return std::unexpected(SqliteError(db_.get(), "export transition"));
    const std::string phase = next == 1 ? "begin" : next == 2 ? "uncertain" : expected == 2 ? "reconciled" : "complete";
    StatementGuard log(prepare("INSERT INTO mail_export_log(phase) VALUES(?)"));
    if (!log.get() || !log.Bind(1, phase) || sqlite3_step(log.get()) != SQLITE_DONE ||
        sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "export log"));
    return {};
  }
  std::expected<std::string, domain::ApiError> MailboxUser(std::string_view address) override {
    std::lock_guard lock(mutex_);
    StatementGuard insert(prepare("INSERT INTO users(user_id,ftn_address) SELECT ?,address FROM mailbox_bindings WHERE "
                                  "address=? ON CONFLICT(ftn_address) DO NOTHING"));
    if (!insert.get() || !insert.Bind(1, "ftn:" + std::string(address)) || !insert.Bind(2, address) ||
        sqlite3_step(insert.get()) != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "mailbox identity"));
    StatementGuard query(prepare("SELECT user_id FROM users WHERE ftn_address=?"));
    if (!query.get() || !query.Bind(1, address) || sqlite3_step(query.get()) != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "mailbox identity"));
    return ColumnText(query.get(), 0);
  }
  std::expected<int, domain::ApiError> MailDirection(ReadKey key) override {
    std::lock_guard lock(mutex_);
    StatementGuard query(prepare("SELECT direction FROM mail_provenance WHERE conference=? AND generation=? AND "
                                 "CAST(message_number AS TEXT)=?"));
    if (!query.get() || !query.Bind(1, key.conference) || !query.Bind(2, key.generation) || !query.Bind(3, key.message))
      return std::unexpected(SqliteError(db_.get(), "direction"));
    const auto status = sqlite3_step(query.get());
    if (status == SQLITE_DONE)
      return 0;
    if (status != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "direction"));
    return sqlite3_column_int(query.get(), 0);
  }
  std::expected<std::vector<Operation>, domain::ApiError> PendingOutbox() override {
    std::lock_guard lock(mutex_);
    StatementGuard query(
        prepare("SELECT "
                "o.user_id,o.operation_id,o.conference,o.generation,o.ftn_msgid,o.payload_hash,o.message_number,o."
                "header_size,o.text_size,o.index_size,o.base_before,o.base_after,o.header_append,o.text_append,o.index_"
                "append,o.state,b.state FROM operations o JOIN mail_outbox b USING(user_id,operation_id) WHERE b.state "
                "IN(0,1,3) AND o.state=1 ORDER BY o.rowid"));
    if (!query.get())
      return std::unexpected(SqliteError(db_.get(), "outbox"));
    std::vector<Operation> result;
    int status;
    while ((status = sqlite3_step(query.get())) == SQLITE_ROW) {
      auto operation = DecodeOperation(query.get());
      if (!operation || result.size() >= 100000)
        return std::unexpected(SqliteError(db_.get(), "outbox"));
      operation->outbox_state = sqlite3_column_int(query.get(), 16);
      result.push_back(std::move(*operation));
    }
    if (status != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "outbox"));
    return result;
  }
  std::expected<void, domain::ApiError> SetOutboxState(std::string_view user, std::string_view operation,
                                                       int state) override {
    std::lock_guard lock(mutex_);
    StatementGuard update(prepare("UPDATE mail_outbox SET state=? WHERE user_id=? AND operation_id=? AND state<=?"));
    if (!update.get() || !update.Bind(1, int64_t(state)) || !update.Bind(2, user) || !update.Bind(3, operation) ||
        !update.Bind(4, int64_t(state)) || sqlite3_step(update.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1)
      return std::unexpected(SqliteError(db_.get(), "outbox state"));
    return {};
  }

  std::expected<std::vector<domain::Bookmark>, domain::ApiError> GetBookmarks(std::string_view user_id) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "SELECT conference_id, added_at FROM bookmarks WHERE user_id = ? "
                                "ORDER BY added_at DESC";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "GetBookmarks"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    std::vector<domain::Bookmark> result;
    int rc;
    while ((rc = sqlite3_step(stmt.get())) == SQLITE_ROW) {
      domain::Bookmark b;
      b.conference_id = ColumnText(stmt.get(), 0);
      b.added_at = ColumnText(stmt.get(), 1);
      result.push_back(std::move(b));
    }
    if (rc != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "query"));
    return result;
  }

  std::expected<void, domain::ApiError> AddBookmark(std::string_view user_id, std::string_view conference_id) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "INSERT OR IGNORE INTO bookmarks (user_id, conference_id) VALUES (?, ?)";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "AddBookmark"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(2, conference_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
      return std::unexpected(SqliteError(db_.get(), "AddBookmark exec"));
    }
    return {};
  }

  std::expected<void, domain::ApiError> RemoveBookmark(std::string_view user_id,
                                                       std::string_view conference_id) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "DELETE FROM bookmarks WHERE user_id = ? AND conference_id = ?";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "RemoveBookmark"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(2, conference_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
      return std::unexpected(SqliteError(db_.get(), "RemoveBookmark exec"));
    }
    return {};
  }

  std::expected<bool, domain::ApiError> IsBookmarked(std::string_view user_id,
                                                     std::string_view conference_id) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "SELECT COUNT(1) FROM bookmarks WHERE user_id = ? AND conference_id = ?";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "IsBookmarked"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(2, conference_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    const int rc = sqlite3_step(stmt.get());
    if (rc == SQLITE_ROW) {
      return sqlite3_column_int(stmt.get(), 0) > 0;
    }
    if (rc != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "query"));
    return false;
  }

  std::expected<std::vector<domain::HistoryEntry>, domain::ApiError> GetHistory(std::string_view user_id,
                                                                                int64_t limit) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "SELECT conference_id, viewed_at FROM history WHERE user_id = ? "
                                "ORDER BY viewed_at DESC LIMIT ?";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "GetHistory"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (limit < 0 || !stmt.Bind(2, limit))
      return std::unexpected(domain::ApiError::Validation("Invalid history limit"));

    std::vector<domain::HistoryEntry> result;
    int rc;
    while ((rc = sqlite3_step(stmt.get())) == SQLITE_ROW) {
      result.push_back({ColumnText(stmt.get(), 0), ColumnText(stmt.get(), 1)});
    }
    if (rc != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "query"));
    return result;
  }

  std::expected<void, domain::ApiError> ClearHistory(std::string_view user_id) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "DELETE FROM history WHERE user_id = ?";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "ClearHistory"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
      return std::unexpected(SqliteError(db_.get(), "ClearHistory exec"));
    }
    return {};
  }

  std::expected<void, domain::ApiError> AddToHistory(std::string_view user_id,
                                                     std::string_view conference_id) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "INSERT INTO history (user_id, conference_id) VALUES (?, ?) "
                                "ON CONFLICT(user_id, conference_id) "
                                "DO UPDATE SET viewed_at = datetime('now')";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "AddToHistory"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(2, conference_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
      return std::unexpected(SqliteError(db_.get(), "AddToHistory exec"));
    }
    return {};
  }

  std::expected<bool, domain::ApiError> IsMessageRead(std::string_view user_id, ReadKey key) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "SELECT COUNT(1) FROM read_status WHERE user_id = ? AND message_id = ? AND "
                                "conference_id = ? AND generation = ?";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "IsMessageRead"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(2, key.message) || !stmt.Bind(3, key.conference) || !stmt.Bind(4, key.generation))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    const int rc = sqlite3_step(stmt.get());
    if (rc == SQLITE_ROW) {
      return sqlite3_column_int(stmt.get(), 0) > 0;
    }
    if (rc != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "query"));
    return false;
  }

  std::expected<void, domain::ApiError> MarkMessageRead(std::string_view user_id, ReadKey key) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "INSERT INTO read_status (user_id, message_id, conference_id, generation) "
                                "VALUES (?, ?, ?, ?) "
                                "ON CONFLICT(user_id, conference_id, generation, message_id) "
                                "DO UPDATE SET read_at = datetime('now')";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "MarkMessageRead"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(2, key.message) || !stmt.Bind(3, key.conference) || !stmt.Bind(4, key.generation))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
      return std::unexpected(SqliteError(db_.get(), "MarkMessageRead exec"));
    }
    return {};
  }

  std::expected<int64_t, domain::ApiError> GetReadCount(std::string_view user_id, std::string_view conference_id,
                                                        std::string_view generation) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql =
        "SELECT COUNT(1) FROM read_status WHERE user_id = ? AND conference_id = ? AND generation = ?";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "GetUnreadCount"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(3, generation))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(2, conference_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    const int rc = sqlite3_step(stmt.get());
    if (rc == SQLITE_ROW) {
      return sqlite3_column_int64(stmt.get(), 0);
    }
    if (rc != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "query"));
    return 0;
  }

  std::expected<std::optional<BulkReadResult>, domain::ApiError> FindBulkReadUnlocked(std::string_view user,
                                                                                      std::string_view operation,
                                                                                      std::string_view conference) {
    StatementGuard query(prepare("SELECT conference,generation,marked_count,snapshot_count FROM bulk_read_operations "
                                 "WHERE user_id=? AND operation_id=?"));
    if (!query.get() || !query.Bind(1, user) || !query.Bind(2, operation))
      return std::unexpected(SqliteError(db_.get(), "bulk lookup"));
    const auto status = sqlite3_step(query.get());
    if (status == SQLITE_DONE)
      return std::optional<BulkReadResult>{};
    if (status != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "bulk lookup"));
    if (ColumnText(query.get(), 0) != conference)
      return std::unexpected(
          domain::ApiError{domain::ErrorCode::kConflict, "Operation belongs to another conference", {}});
    return std::optional<BulkReadResult>{
        {sqlite3_column_int64(query.get(), 2), sqlite3_column_int64(query.get(), 3), ColumnText(query.get(), 1)}};
  }
  std::expected<std::optional<BulkReadResult>, domain::ApiError> FindBulkRead(std::string_view user,
                                                                              std::string_view operation,
                                                                              std::string_view conference) override {
    std::lock_guard lock(mutex_);
    return FindBulkReadUnlocked(user, operation, conference);
  }
  std::expected<BulkReadResult, domain::ApiError> MarkConferenceRead(std::string_view user, std::string_view operation,
                                                                     std::string_view conference,
                                                                     std::string_view generation,
                                                                     const std::vector<uint32_t>& numbers,
                                                                     const std::function<bool()>& active) override {
    std::lock_guard lock(mutex_);
    if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "bulk begin"));
    auto rollback = [&](domain::ApiError error) -> std::expected<BulkReadResult, domain::ApiError> {
      sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
      return std::unexpected(std::move(error));
    };
    auto previous = FindBulkReadUnlocked(user, operation, conference);
    if (!previous)
      return rollback(previous.error());
    if (*previous) {
      sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
      return **previous;
    }
    BulkReadResult result{0, static_cast<int64_t>(numbers.size()), std::string(generation)};
    StatementGuard insert(
        prepare("INSERT INTO read_status(user_id,conference_id,generation,message_id) VALUES(?,?,?,?) "
                "ON CONFLICT(user_id,conference_id,generation,message_id) DO NOTHING"));
    if (!insert.get())
      return rollback(SqliteError(db_.get(), "bulk prepare"));
    for (auto number : numbers) {
      if (active && !active())
        return rollback({domain::ErrorCode::kCancelled, "Bulk read cancelled before commit", {}});
      sqlite3_reset(insert.get());
      sqlite3_clear_bindings(insert.get());
      if (!insert.Bind(1, user) || !insert.Bind(2, conference) || !insert.Bind(3, generation) ||
          !insert.Bind(4, std::to_string(number)) || sqlite3_step(insert.get()) != SQLITE_DONE)
        return rollback(SqliteError(db_.get(), "bulk insert"));
      result.marked_count += sqlite3_changes(db_.get());
    }
    StatementGuard receipt(prepare("INSERT INTO bulk_read_operations VALUES(?,?,?,?,?,?)"));
    if (!receipt.get() || !receipt.Bind(1, user) || !receipt.Bind(2, operation) || !receipt.Bind(3, conference) ||
        !receipt.Bind(4, generation) || !receipt.Bind(5, result.marked_count) ||
        !receipt.Bind(6, result.snapshot_count) || sqlite3_step(receipt.get()) != SQLITE_DONE)
      return rollback(SqliteError(db_.get(), "bulk receipt"));
    if (active && !active())
      return rollback({domain::ErrorCode::kCancelled, "Bulk read cancelled before commit", {}});
    if (sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return rollback(SqliteError(db_.get(), "bulk commit"));
    return result;
  }

  std::expected<ReadingPosition, domain::ApiError> RecordMessageView(std::string_view user, ReadKey key) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "view begin"));
    auto fail = [&]() -> std::expected<ReadingPosition, domain::ApiError> {
      sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
      return std::unexpected(SqliteError(db_.get(), "record view"));
    };
    StatementGuard read(
        prepare("INSERT INTO read_status(user_id,conference_id,generation,message_id) VALUES(?,?,?,?) "
                "ON CONFLICT(user_id,conference_id,generation,message_id) DO UPDATE SET read_at=datetime('now')"));
    if (!read.get() || !read.Bind(1, user) || !read.Bind(2, key.conference) || !read.Bind(3, key.generation) ||
        !read.Bind(4, key.message) || sqlite3_step(read.get()) != SQLITE_DONE)
      return fail();
    StatementGuard history(prepare("INSERT INTO history(user_id,conference_id) VALUES(?,?) "
                                   "ON CONFLICT(user_id,conference_id) DO UPDATE SET viewed_at=datetime('now')"));
    if (!history.get() || !history.Bind(1, user) || !history.Bind(2, key.conference) ||
        sqlite3_step(history.get()) != SQLITE_DONE)
      return fail();
    StatementGuard position(
        prepare("INSERT INTO reading_positions VALUES(?,?,?,?,1) ON CONFLICT(user_id,conference) DO UPDATE SET "
                "generation=excluded.generation,message_id=excluded.message_id,revision=reading_positions.revision+1 "
                "WHERE reading_positions.revision<9223372036854775807"));
    if (!position.get() || !position.Bind(1, user) || !position.Bind(2, key.conference) ||
        !position.Bind(3, key.generation) || !position.Bind(4, key.message) ||
        sqlite3_step(position.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1)
      return fail();
    StatementGuard revision(prepare("SELECT revision FROM reading_positions WHERE user_id=? AND conference=?"));
    if (!revision.get() || !revision.Bind(1, user) || !revision.Bind(2, key.conference) ||
        sqlite3_step(revision.get()) != SQLITE_ROW)
      return fail();
    ReadingPosition result{std::string(key.generation), std::string(key.message),
                           static_cast<uint64_t>(sqlite3_column_int64(revision.get(), 0))};
    if (sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return fail();
    return result;
  }

  std::expected<ReadingPosition, domain::ApiError> LastOpened(std::string_view user,
                                                              std::string_view conference) override {
    std::lock_guard lock(mutex_);
    StatementGuard query(
        prepare("SELECT generation,message_id,revision FROM reading_positions WHERE user_id=? AND conference=?"));
    if (!query.get() || !query.Bind(1, user) || !query.Bind(2, conference))
      return std::unexpected(SqliteError(db_.get(), "position"));
    const auto status = sqlite3_step(query.get());
    if (status == SQLITE_DONE)
      return ReadingPosition{};
    if (status != SQLITE_ROW || sqlite3_column_int64(query.get(), 2) <= 0)
      return std::unexpected(SqliteError(db_.get(), "position"));
    return ReadingPosition{ColumnText(query.get(), 0), ColumnText(query.get(), 1),
                           static_cast<uint64_t>(sqlite3_column_int64(query.get(), 2))};
  }

  std::expected<domain::Profile, domain::ApiError> GetProfile(std::string_view user_id) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "SELECT name, ftn_address, email, registered_at FROM users "
                                "WHERE user_id = ?";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "GetProfile"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    const int rc = sqlite3_step(stmt.get());
    if (rc != SQLITE_ROW) {
      if (rc != SQLITE_DONE)
        return std::unexpected(SqliteError(db_.get(), "query"));
      return std::unexpected(domain::ApiError::NotFound("Profile not found for user"));
    }

    domain::Profile p;
    p.name = ColumnText(stmt.get(), 0);
    p.address = ColumnText(stmt.get(), 1);
    p.email = ColumnText(stmt.get(), 2);
    p.registered_at = ColumnText(stmt.get(), 3);
    return p;
  }

  std::expected<void, domain::ApiError> SaveProfile(std::string_view user_id, const domain::Profile& profile) override {
    std::lock_guard lock(mutex_);
    if (!db_.get())
      return std::unexpected(domain::ApiError::Server("DB not open"));

    constexpr const char* sql = "INSERT INTO users (user_id, name, ftn_address, email, registered_at) "
                                "VALUES (?, ?, ?, ?, ?) "
                                "ON CONFLICT(user_id) DO UPDATE SET "
                                "name = excluded.name, ftn_address = excluded.ftn_address, "
                                "email = excluded.email, registered_at = excluded.registered_at";
    StatementGuard stmt(prepare(sql));
    if (!stmt.get())
      return std::unexpected(SqliteError(db_.get(), "SaveProfile"));

    if (!stmt.Bind(1, user_id))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(2, profile.name))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(3, profile.address))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(4, profile.email))
      return std::unexpected(SqliteError(db_.get(), "bind"));
    if (!stmt.Bind(5, profile.registered_at))
      return std::unexpected(SqliteError(db_.get(), "bind"));

    if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
      return std::unexpected(SqliteError(db_.get(), "SaveProfile exec"));
    }
    return {};
  }

  std::expected<void, domain::ApiError> ProvisionToken(std::string_view user, const domain::Profile& profile,
                                                       const TokenDigest& digest, int64_t expires_at) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "begin"));
    auto fail = [&]() -> std::expected<void, domain::ApiError> {
      sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
      return std::unexpected(SqliteError(db_.get(), "provision"));
    };
    StatementGuard account(
        prepare("INSERT INTO users(user_id,name,ftn_address,email,registered_at,active) VALUES(?,?,?,?,?,1) "
                "ON CONFLICT(user_id) DO UPDATE SET "
                "name=excluded.name,ftn_address=excluded.ftn_address,email=excluded.email,active=1"));
    if (!account.get() || !account.Bind(1, user) || !account.Bind(2, profile.name) ||
        !account.Bind(3, profile.address) || !account.Bind(4, profile.email) ||
        !account.Bind(5, profile.registered_at) || sqlite3_step(account.get()) != SQLITE_DONE)
      return fail();
    StatementGuard token(prepare("INSERT INTO tokens(digest,user_id,expires_at) VALUES(?,?,?)"));
    if (!token.get() || !token.Bind(1, digest) || !token.Bind(2, user) || !token.Bind(3, expires_at) ||
        sqlite3_step(token.get()) != SQLITE_DONE)
      return fail();
    if (sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return fail();
    return {};
  }
  std::expected<void, domain::ApiError> RevokeToken(const TokenDigest& digest) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    StatementGuard statement(prepare("UPDATE tokens SET revoked=1 WHERE digest=?"));
    if (!statement.get() || !statement.Bind(1, digest) || sqlite3_step(statement.get()) != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "revoke"));
    return {};
  }
  std::expected<AuthenticatedUser, domain::ApiError> AuthenticateToken(const TokenDigest& digest,
                                                                       int64_t now) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    StatementGuard statement(
        prepare("SELECT u.user_id,u.name,u.ftn_address,u.email,u.registered_at,t.expires_at FROM tokens t JOIN "
                "users u ON u.user_id=t.user_id "
                "WHERE t.digest=? AND t.revoked=0 AND t.expires_at>? AND u.active=1"));
    if (!statement.get() || !statement.Bind(1, digest) || !statement.Bind(2, now))
      return std::unexpected(SqliteError(db_.get(), "authenticate"));
    const auto rc = sqlite3_step(statement.get());
    if (rc == SQLITE_DONE)
      return std::unexpected(domain::ApiError::Unauthorized("Invalid access token"));
    if (rc != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "authenticate"));
    return AuthenticatedUser{ColumnText(statement.get(), 0),
                             {ColumnText(statement.get(), 1), ColumnText(statement.get(), 2),
                              ColumnText(statement.get(), 3), ColumnText(statement.get(), 4)},
                             sqlite3_column_int64(statement.get(), 5)};
  }

  std::expected<void, domain::ApiError> SyncCredentials(
      const std::map<std::string, TokenDigest>& fingerprints) override {
    std::lock_guard lock(mutex_);
    if (!db_ || sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "credentials"));
    auto fail = [&]() -> std::expected<void, domain::ApiError> {
      sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
      return std::unexpected(SqliteError(db_.get(), "credentials"));
    };
    if (sqlite3_exec(db_.get(), "DELETE FROM auth_credentials", nullptr, nullptr, nullptr) != SQLITE_OK)
      return fail();
    for (const auto& [address, fingerprint] : fingerprints) {
      StatementGuard row(prepare("INSERT INTO auth_credentials VALUES(?,?)"));
      if (!row.get() || !row.Bind(1, address) || !row.Bind(2, fingerprint) || sqlite3_step(row.get()) != SQLITE_DONE)
        return fail();
    }
    const char* revoke = "UPDATE tokens SET revoked=1 WHERE fingerprint IS NULL OR NOT EXISTS "
                         "(SELECT 1 FROM users u JOIN auth_credentials c ON c.address=u.ftn_address "
                         "WHERE u.user_id=tokens.user_id AND c.fingerprint=tokens.fingerprint)";
    if (sqlite3_exec(db_.get(), revoke, nullptr, nullptr, nullptr) != SQLITE_OK ||
        sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return fail();
    return {};
  }
  std::expected<AuthenticatedUser, domain::ApiError> CreateSession(std::string_view address, std::string_view name,
                                                                   std::string_view registered_at,
                                                                   const TokenDigest& digest,
                                                                   const TokenDigest& fingerprint,
                                                                   int64_t expires_at) override {
    std::lock_guard lock(mutex_);
    if (!db_ || sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "session"));
    auto fail = [&]() -> std::expected<AuthenticatedUser, domain::ApiError> {
      sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
      return std::unexpected(SqliteError(db_.get(), "session"));
    };
    StatementGuard account(
        prepare("INSERT INTO users(user_id,name,ftn_address,email,registered_at,active) "
                "VALUES(?,?,?,'',?,1) ON CONFLICT(ftn_address) DO UPDATE SET name=excluded.name WHERE users.name=''"));
    const std::string id = "ftn:" + std::string(address);
    if (!account.get() || !account.Bind(1, id) || !account.Bind(2, name) || !account.Bind(3, address) ||
        !account.Bind(4, registered_at) || sqlite3_step(account.get()) != SQLITE_DONE)
      return fail();
    StatementGuard user(
        prepare("SELECT user_id,name,ftn_address,email,registered_at FROM users WHERE ftn_address=? AND active=1"));
    if (!user.get() || !user.Bind(1, address))
      return fail();
    const auto code = sqlite3_step(user.get());
    if (code == SQLITE_DONE) {
      sqlite3_exec(db_.get(), "ROLLBACK", nullptr, nullptr, nullptr);
      return std::unexpected(domain::ApiError::Unauthorized("Invalid credentials"));
    }
    if (code != SQLITE_ROW)
      return fail();
    AuthenticatedUser result{
        ColumnText(user.get(), 0),
        {ColumnText(user.get(), 1), ColumnText(user.get(), 2), ColumnText(user.get(), 3), ColumnText(user.get(), 4)},
        expires_at};
    StatementGuard token(
        prepare("INSERT INTO tokens(digest,user_id,expires_at,fingerprint) "
                "SELECT ?,?,?,? WHERE EXISTS (SELECT 1 FROM auth_credentials WHERE address=? AND fingerprint=?)"));
    if (!token.get() || !token.Bind(1, digest) || !token.Bind(2, result.id) || !token.Bind(3, expires_at) ||
        !token.Bind(4, fingerprint) || !token.Bind(5, address) || !token.Bind(6, fingerprint) ||
        sqlite3_step(token.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1)
      return fail();
    if (sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return fail();
    return result;
  }
  std::expected<void, domain::ApiError> RevokeUserSessions(std::string_view user) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    StatementGuard update(prepare("UPDATE tokens SET revoked=1 WHERE user_id=?"));
    if (!update.get() || !update.Bind(1, user) || sqlite3_step(update.get()) != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "revoke sessions"));
    return {};
  }

  std::expected<std::optional<Operation>, domain::ApiError> FindOperation(std::string_view user,
                                                                          std::string_view id) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    StatementGuard statement(prepare("SELECT "
                                     "user_id,operation_id,conference,generation,ftn_msgid,payload_hash,message_number,"
                                     "header_size,text_size,index_size,base_before,base_after,header_append,text_"
                                     "append,index_append,state FROM operations WHERE user_id=? AND operation_id=?"));
    if (!statement.get() || !statement.Bind(1, user) || !statement.Bind(2, id))
      return std::unexpected(SqliteError(db_.get(), "find"));
    auto rc = sqlite3_step(statement.get());
    if (rc == SQLITE_DONE)
      return std::optional<Operation>{};
    if (rc != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "find"));
    auto record = DecodeOperation(statement.get());
    if (!record)
      return std::unexpected(record.error());
    return std::optional<Operation>(std::move(*record));
  }
  std::expected<std::string, domain::ApiError> GetCommittedRecipient(ReadKey key, std::string_view ftn_msgid) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    if (ftn_msgid.empty())
      return std::string{};
    // Controlled copies can share MsgID; only the exact committed JAM identity supplies an address.
    StatementGuard statement(prepare("SELECT header_append FROM operations WHERE ftn_msgid=? AND conference=? "
                                     "AND generation=? AND message_number=? AND state=1"));
    if (!statement.get() || !statement.Bind(1, ftn_msgid) || !statement.Bind(2, key.conference) ||
        !statement.Bind(3, key.generation) || !statement.Bind(4, key.message))
      return std::unexpected(SqliteError(db_.get(), "recipient"));
    const auto rc = sqlite3_step(statement.get());
    if (rc == SQLITE_DONE)
      return std::string{};
    if (rc != SQLITE_ROW)
      return std::unexpected(SqliteError(db_.get(), "recipient"));
    auto corrupt = [] { return std::unexpected(domain::ApiError::Server("Invalid operation journal")); };
    const auto size = sqlite3_column_bytes(statement.get(), 0);
    const auto* bytes = static_cast<const uint8_t*>(sqlite3_column_blob(statement.get(), 0));
    if (sqlite3_column_type(statement.get(), 0) != SQLITE_BLOB || !bytes || size < 76 ||
        size > 76 + int(msgapi::jam_wire::kMaxSubfields) || msgapi::jam_wire::Get32(bytes) != msgapi::kJamSignature ||
        msgapi::jam_wire::Get32(bytes + 8) != uint32_t(size - 76))
      return corrupt();
    std::string address, msgid;
    bool found_address = false, found_msgid = false;
    for (size_t offset = 76; offset < size_t(size);) {
      const auto remaining = size_t(size) - offset;
      if (remaining < 8)
        return corrupt();
      const auto lo = msgapi::jam_wire::Get16(bytes + offset);
      const auto hi = msgapi::jam_wire::Get16(bytes + offset + 2);
      const auto length = msgapi::jam_wire::Get32(bytes + offset + 4);
      if (length > remaining - 8)
        return corrupt();
      if (hi == 0 &&
          (lo == uint16_t(msgapi::JamSubFieldType::kDAddress) || lo == uint16_t(msgapi::JamSubFieldType::kMsgId))) {
        auto& found = lo == uint16_t(msgapi::JamSubFieldType::kDAddress) ? found_address : found_msgid;
        auto& value = lo == uint16_t(msgapi::JamSubFieldType::kDAddress) ? address : msgid;
        if (found)
          return corrupt();
        found = true;
        value.assign(reinterpret_cast<const char*>(bytes + offset + 8), length);
      }
      offset += 8 + length;
    }
    if (msgid != ftn_msgid)
      return corrupt();
    return address;
  }
  std::expected<void, domain::ApiError> PrepareOperation(const Operation& operation) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    const bool mail = operation.mail_direction != 0;
    if (operation.mail_direction < 0 || operation.mail_direction > 3)
      return std::unexpected(SqliteError(db_.get(), "direction"));
    if (mail && !domain::CanonicalFtnAddress(operation.recipient))
      return std::unexpected(SqliteError(db_.get(), "recipient"));
    if (mail && sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "intent begin"));
    struct Transaction {
      sqlite3* db;
      bool active;
      ~Transaction() {
        if (active)
          sqlite3_exec(db, "ROLLBACK", nullptr, nullptr, nullptr);
      }
    } transaction{db_.get(), mail};
    StatementGuard statement(
        prepare("INSERT INTO "
                "operations(user_id,operation_id,conference,generation,ftn_msgid,payload_hash,message_number,header_"
                "size,text_size,index_size,base_before,base_after,header_append,text_append,index_append,copy_scope) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
                "ON CONFLICT(user_id,operation_id) DO UPDATE SET "
                "generation=excluded.generation,message_number=excluded.message_number,"
                "header_size=excluded.header_size,text_size=excluded.text_size,index_size=excluded.index_size,base_"
                "before=excluded.base_before,"
                "base_after=excluded.base_after,header_append=excluded.header_append,text_append=excluded.text_append,"
                "index_append=excluded.index_append,state=0 "
                "WHERE operations.state=2 AND operations.payload_hash=excluded.payload_hash AND "
                "operations.conference=excluded.conference AND operations.ftn_msgid=excluded.ftn_msgid"));
    const auto& plan = operation.plan;
    if (!statement.get() || !statement.Bind(1, operation.user) || !statement.Bind(2, operation.id) ||
        !statement.Bind(3, operation.conference) || !statement.Bind(4, operation.generation) ||
        !statement.Bind(5, operation.ftn_msgid) || !statement.Bind(6, operation.payload_hash) ||
        !statement.Bind(7, int64_t(plan.number)) || !statement.Bind(8, int64_t(plan.original_sizes[0])) ||
        !statement.Bind(9, int64_t(plan.original_sizes[1])) || !statement.Bind(10, int64_t(plan.original_sizes[2])) ||
        !statement.Blob(11, plan.original_base) || !statement.Blob(12, plan.published_base) ||
        !statement.Blob(13, plan.header) ||
        !statement.Blob(14, std::span(reinterpret_cast<const uint8_t*>(plan.text.data()), plan.text.size())) ||
        !statement.Blob(15, plan.index) ||
        !statement.Bind(16,
                        operation.mail_direction == 1 || operation.mail_direction == 3
                            ? operation.conference + ":" + std::to_string(operation.mail_direction) + ":" + operation.id
                            : std::string{}))
      return std::unexpected(SqliteError(db_.get(), "prepare intent"));
    if (sqlite3_step(statement.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1)
      return std::unexpected(SqliteError(db_.get(), "prepare intent"));
    if (mail) {
      StatementGuard tag(prepare("INSERT INTO mail_intents VALUES(?,?,?,?) ON CONFLICT(user_id,operation_id) DO UPDATE "
                                 "SET direction=excluded.direction WHERE mail_intents.direction=excluded.direction AND "
                                 "mail_intents.recipient=excluded.recipient"));
      if (!tag.get() || !tag.Bind(1, operation.user) || !tag.Bind(2, operation.id) ||
          !tag.Bind(3, int64_t(operation.mail_direction)) || !tag.Bind(4, operation.recipient) ||
          sqlite3_step(tag.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1 ||
          sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
        return std::unexpected(SqliteError(db_.get(), "mail intent"));
    }
    return {};
  }
  std::expected<void, domain::ApiError> SetOperationState(std::string_view user, std::string_view id,
                                                          OperationState state) override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    if (sqlite3_exec(db_.get(), "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "commit begin"));
    struct Transaction {
      sqlite3* db;
      ~Transaction() {
        sqlite3_exec(db, "ROLLBACK", nullptr, nullptr, nullptr);
      }
    } transaction{db_.get()};
    StatementGuard statement(prepare("UPDATE operations SET state=? WHERE user_id=? AND operation_id=?"));
    if (!statement.get() || !statement.Bind(1, int64_t(state)) || !statement.Bind(2, user) || !statement.Bind(3, id) ||
        sqlite3_step(statement.get()) != SQLITE_DONE || sqlite3_changes(db_.get()) != 1)
      return std::unexpected(SqliteError(db_.get(), "commit intent"));
    if (state == OperationState::kCommitted) {
      const char* statements[] = {
          "INSERT INTO mail_provenance SELECT "
          "o.conference,o.generation,o.message_number,i.direction,o.user_id,o.operation_id FROM operations o JOIN "
          "mail_intents i USING(user_id,operation_id) WHERE o.user_id=? AND o.operation_id=? ON "
          "CONFLICT(conference,generation,message_number) DO NOTHING",
          "INSERT INTO mail_outbox(user_id,operation_id) SELECT user_id,operation_id FROM mail_intents WHERE user_id=? "
          "AND operation_id=? AND direction=2 ON CONFLICT DO NOTHING",
          "INSERT INTO read_status(user_id,conference_id,generation,message_id) SELECT "
          "o.user_id,o.conference,o.generation,CAST(o.message_number AS TEXT) FROM operations o JOIN mail_intents i "
          "USING(user_id,operation_id) WHERE o.user_id=? AND o.operation_id=? AND i.direction=2 ON CONFLICT DO "
          "NOTHING"};
      for (const auto* sql : statements) {
        StatementGuard commit(prepare(sql));
        if (!commit.get() || !commit.Bind(1, user) || !commit.Bind(2, id) || sqlite3_step(commit.get()) != SQLITE_DONE)
          return std::unexpected(SqliteError(db_.get(), "mail commit"));
      }
    }
    if (sqlite3_exec(db_.get(), "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK)
      return std::unexpected(SqliteError(db_.get(), "commit"));
    return {};
  }
  std::expected<std::vector<Operation>, domain::ApiError> PendingOperations() override {
    std::lock_guard lock(mutex_);
    if (!db_)
      return std::unexpected(SqliteError(nullptr, "closed"));
    StatementGuard statement(prepare("SELECT "
                                     "user_id,operation_id,conference,generation,ftn_msgid,payload_hash,message_number,"
                                     "header_size,text_size,index_size,base_before,base_after,header_append,text_"
                                     "append,index_append,state FROM operations WHERE state IN(0,3) ORDER BY rowid"));
    if (!statement.get())
      return std::unexpected(SqliteError(db_.get(), "pending"));
    std::vector<Operation> records;
    int rc;
    while ((rc = sqlite3_step(statement.get())) == SQLITE_ROW) {
      auto record = DecodeOperation(statement.get());
      if (!record)
        return std::unexpected(record.error());
      records.push_back(std::move(*record));
    }
    if (rc != SQLITE_DONE)
      return std::unexpected(SqliteError(db_.get(), "pending"));
    return records;
  }

private:
  std::expected<Operation, domain::ApiError> DecodeOperation(sqlite3_stmt* statement) {
    auto corrupt = [] { return std::unexpected(domain::ApiError::Server("Invalid operation journal")); };
    Operation operation;
    operation.user = ColumnText(statement, 0);
    operation.id = ColumnText(statement, 1);
    operation.conference = ColumnText(statement, 2);
    operation.generation = ColumnText(statement, 3);
    operation.ftn_msgid = ColumnText(statement, 4);
    auto fixed = [&](int column, auto& output) {
      if (sqlite3_column_type(statement, column) != SQLITE_BLOB ||
          sqlite3_column_bytes(statement, column) != int(output.size()))
        return false;
      std::memcpy(output.data(), sqlite3_column_blob(statement, column), output.size());
      return true;
    };
    if (!fixed(5, operation.payload_hash) || !fixed(10, operation.plan.original_base) ||
        !fixed(11, operation.plan.published_base) || !fixed(14, operation.plan.index))
      return corrupt();
    for (int i = 6; i <= 9; ++i) {
      if (sqlite3_column_type(statement, i) != SQLITE_INTEGER || sqlite3_column_int64(statement, i) < 0 ||
          sqlite3_column_int64(statement, i) > UINT32_MAX)
        return corrupt();
    }
    operation.plan.number = static_cast<uint32_t>(sqlite3_column_int64(statement, 6));
    for (int i = 0; i < 3; ++i)
      operation.plan.original_sizes[i] = static_cast<uint64_t>(sqlite3_column_int64(statement, 7 + i));
    const auto header_size = sqlite3_column_bytes(statement, 12), text_size = sqlite3_column_bytes(statement, 13);
    if (header_size < 76 || header_size > 65612 || text_size < 0 || text_size > 1048576 ||
        sqlite3_column_type(statement, 12) != SQLITE_BLOB || sqlite3_column_type(statement, 13) != SQLITE_BLOB)
      return corrupt();
    const auto* header = static_cast<const uint8_t*>(sqlite3_column_blob(statement, 12));
    operation.plan.header.assign(header, header + header_size);
    if (text_size)
      operation.plan.text.assign(static_cast<const char*>(sqlite3_column_blob(statement, 13)), text_size);
    const auto state = sqlite3_column_int(statement, 15);
    if (state < 0 || state > 3)
      return corrupt();
    operation.state = static_cast<OperationState>(state);
    return operation;
  }
  sqlite3_stmt* prepare(const char* sql) {
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_.get(), sql, -1, &stmt, nullptr);
    if (rc != SQLITE_OK) {
      return nullptr;
    }
    return stmt;
  }

  std::filesystem::path db_path_;
  SQLiteDb db_;  // RAII-обёртка вместо сырого sqlite3*
  mutable std::mutex mutex_;
};

std::shared_ptr<IMetadataStore> CreateSQLiteStore(std::filesystem::path db_path) {
  return std::make_shared<SQLiteMetadataStore>(std::move(db_path));
}

}  // namespace fidoback::storage
