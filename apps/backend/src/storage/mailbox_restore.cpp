#include "storage/mailbox_restore.hpp"

#include <fcntl.h>
#include <openssl/evp.h>
#include <sqlite3.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cerrno>
#include <initializer_list>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <vector>

#include "domain/ftn_address.hpp"
#include "storage/jam_catalog.hpp"

namespace fidoback::storage {
namespace {
using Json = nlohmann::json;
void Require(bool ok) {
  if (!ok)
    throw std::runtime_error("Restore verification failed; no unverified files may be assigned");
}
struct File {
  int fd = -1;
  struct stat identity{};
  explicit File(int value) : fd(value) {
    Require(fd >= 0);
    if (fstat(fd, &identity) != 0 || !S_ISREG(identity.st_mode) || identity.st_nlink != 1) {
      close(fd);
      fd = -1;
      Require(false);
    }
  }
  ~File() {
    if (fd >= 0)
      close(fd);
  }
  File(const File&) = delete;
  File& operator=(const File&) = delete;
};
std::vector<std::string> Parts(const std::string& path) {
  std::filesystem::path p(path);
  Require(!p.empty() && !p.is_absolute() && !path.ends_with('/') && path.find("//") == std::string::npos &&
          path.find('\0') == std::string::npos);
  std::vector<std::string> result;
  for (const auto& part : p) {
    Require(part != "." && part != ".." && !part.empty());
    result.push_back(part.string());
  }
  return result;
}
std::unique_ptr<File> Open(int root, const std::string& path, int mode = O_RDONLY) {
  auto parts = Parts(path);
  int parent = dup(root);
  Require(parent >= 0);
  for (size_t i = 0; i + 1 < parts.size(); ++i) {
    int next = openat(parent, parts[i].c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    close(parent);
    Require(next >= 0);
    parent = next;
  }
  int fd = openat(parent, parts.back().c_str(), mode | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  close(parent);
  return std::make_unique<File>(fd);
}
std::string Hex(const unsigned char* bytes, size_t size) {
  constexpr char hex[] = "0123456789abcdef";
  std::string result;
  for (size_t i = 0; i < size; ++i) {
    result += hex[bytes[i] >> 4];
    result += hex[bytes[i] & 15];
  }
  return result;
}
std::string Hash(const File& file) {
  std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(), EVP_MD_CTX_free);
  Require(ctx && EVP_DigestInit_ex(ctx.get(), EVP_sha256(), nullptr) == 1);
  std::array<char, 65536> buffer{};
  struct stat before{};
  Require(fstat(file.fd, &before) == 0);
  off_t offset = 0;
  while (true) {
    auto size = pread(file.fd, buffer.data(), buffer.size(), offset);
    Require(size >= 0);
    if (size == 0)
      break;
    Require(EVP_DigestUpdate(ctx.get(), buffer.data(), static_cast<size_t>(size)) == 1);
    offset += size;
  }
  struct stat current{};
  Require(fstat(file.fd, &current) == 0 && current.st_size == before.st_size && current.st_mtime == before.st_mtime);
  std::array<unsigned char, EVP_MAX_MD_SIZE> bytes{};
  unsigned int size = 0;
  Require(EVP_DigestFinal_ex(ctx.get(), bytes.data(), &size) == 1);
  return Hex(bytes.data(), size);
}
std::string Digest(const std::string& text) {
  std::array<unsigned char, EVP_MAX_MD_SIZE> bytes{};
  unsigned int size = 0;
  Require(EVP_Digest(text.data(), text.size(), bytes.data(), &size, EVP_sha256(), nullptr) == 1);
  return Hex(bytes.data(), size);
}
Json Read(const File& file) {
  Require(file.identity.st_size >= 0 && file.identity.st_size <= 64 * 1024 * 1024);
  std::string text(static_cast<size_t>(file.identity.st_size), '\0');
  Require(pread(file.fd, text.data(), text.size(), 0) == static_cast<ssize_t>(text.size()));
  return Json::parse(text);
}
struct Database {
  sqlite3* db = nullptr;
  explicit Database(const std::filesystem::path& path, bool writable, bool immutable = true) {
    int flags = (writable ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_NOFOLLOW;
    const auto resolved = std::filesystem::canonical(path.parent_path()) / path.filename();
    std::string input = resolved.string();
    if (!writable && immutable) {
      std::string uri = "file:";
      constexpr char hex[] = "0123456789ABCDEF";
      for (unsigned char c : resolved.string()) {
        if (std::isalnum(c) || c == '/' || c == '.' || c == '_' || c == '-')
          uri += static_cast<char>(c);
        else {
          uri += '%';
          uri += hex[c >> 4];
          uri += hex[c & 15];
        }
      }
      input = uri + "?immutable=1";
      flags |= SQLITE_OPEN_URI;
    }
    const int status = sqlite3_open_v2(input.c_str(), &db, flags, nullptr);
    if (status != SQLITE_OK) {
      if (db)
        sqlite3_close(db);
      db = nullptr;
      Require(false);
    }
    sqlite3_busy_timeout(db, 0);
  }
  ~Database() {
    sqlite3_close(db);
  }
  Database(const Database&) = delete;
  Database& operator=(const Database&) = delete;
};
struct Query {
  sqlite3_stmt* value = nullptr;
  Query(sqlite3* db, const std::string& sql) {
    Require(sqlite3_prepare_v2(db, sql.c_str(), -1, &value, nullptr) == SQLITE_OK);
  }
  ~Query() {
    sqlite3_finalize(value);
  }
  void Bind(int index, const std::string& value_text) {
    Require(sqlite3_bind_text(value, index, value_text.c_str(), -1, SQLITE_TRANSIENT) == SQLITE_OK);
  }
  std::string Text(int index) const {
    const auto* text = sqlite3_column_text(value, index);
    Require(text != nullptr);
    return reinterpret_cast<const char*>(text);
  }
};
void Execute(sqlite3* db, const std::string& sql) {
  Require(sqlite3_exec(db, sql.c_str(), nullptr, nullptr, nullptr) == SQLITE_OK);
}
int64_t Integer(sqlite3* db, const std::string& sql) {
  Query query(db, sql);
  Require(sqlite3_step(query.value) == SQLITE_ROW);
  return sqlite3_column_int64(query.value, 0);
}
void Integrity(sqlite3* db) {
  Query check(db, "PRAGMA integrity_check");
  Require(sqlite3_step(check.value) == SQLITE_ROW && check.Text(0) == "ok");
  Query foreign(db, "PRAGMA foreign_key_check");
  Require(sqlite3_step(foreign.value) == SQLITE_DONE);
}
void ValidateSchema(sqlite3* db, int64_t schema) {
  Require(schema == 11 || schema == 12);
  const auto columns = [&](const std::string& table, std::initializer_list<std::string> expected) {
    Require(Integer(db, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='" + table + "'") == 1);
    Query query(db, "PRAGMA table_info(" + table + ")");
    std::set<std::string> actual;
    int status;
    while ((status = sqlite3_step(query.value)) == SQLITE_ROW)
      Require(actual.insert(query.Text(1)).second);
    Require(status == SQLITE_DONE && actual == std::set<std::string>(expected));
  };
  columns("users", {"user_id", "name", "ftn_address", "email", "registered_at", "active"});
  columns("bookmarks", {"user_id", "conference_id", "added_at"});
  columns("history", {"user_id", "conference_id", "viewed_at"});
  columns("read_status", {"user_id", "conference_id", "generation", "message_id", "read_at"});
  columns("read_status_legacy_backup", {"user_id", "message_id", "conference_id", "read_at"});
  columns("auth_credentials", {"address", "fingerprint"});
  columns("mailbox_bindings", {"address", "base", "generation", "files"});
  columns("operations", {"user_id", "operation_id", "conference", "generation", "ftn_msgid", "payload_hash",
                         "message_number", "header_size", "text_size", "index_size", "base_before", "base_after",
                         "header_append", "text_append", "index_append", "state", "copy_scope"});
  columns("mail_intents", {"user_id", "operation_id", "direction", "recipient"});
  columns("mail_provenance", {"conference", "generation", "message_number", "direction", "user_id", "operation_id"});
  columns("mail_outbox", {"user_id", "operation_id", "state"});
  columns("reading_positions", {"user_id", "conference", "generation", "message_id", "revision"});
  columns("mail_export_log", {"id", "phase", "recorded_at"});
  columns("mail_pipeline", {"id", "state"});
  columns("mail_deliveries", {"delivery_key", "payload_hash"});
  columns("mail_transfers",
          {"source_key", "delivery_key", "source_conference", "source_generation", "source_number", "original_flags",
           "payload_hash", "source_hash", "target_conference", "target_operation", "state", "duplicate", "collision"});
  columns("bulk_read_operations",
          {"user_id", "operation_id", "conference", "generation", "marked_count", "snapshot_count"});
  columns("uue_uploads", {"user_id", "operation_id", "filename", "sha256", "size", "data", "manifest", "state",
                          "revision", "updated_at"});
  columns("crosspost_groups", {"user_id", "operation_id", "manifest"});
  columns("personal_filters", {"user_id", "revision", "rules"});
  columns("personal_filter_mutations", {"user_id", "operation_id", "expected_revision", "payload_hash", "revision"});
  if (schema == 12) {
    columns("tokens", {"digest", "user_id", "expires_at", "revoked", "fingerprint", "telegram_revision"});
    columns("telegram_bindings", {"user_id", "bot_id", "telegram_user_id", "fingerprint", "revision"});
    Require(Integer(db, "SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name='telegram_binding_delete'") ==
            1);
    Require(Integer(db, "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='telegram_owner'") == 1);
  } else {
    columns("tokens", {"digest", "user_id", "expires_at", "revoked", "fingerprint"});
    Require(Integer(db, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='telegram_bindings'") == 0);
  }
  if (Integer(db, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='restored_generations'") != 0)
    columns("restored_generations", {"base", "physical_generation", "logical_generation"});
  if (Integer(db, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='restore_receipts'") != 0)
    columns("restore_receipts", {"manifest", "plan", "logical_hash"});
}
std::string LogicalHash(sqlite3* db) {
  Json content = Json::object();
  Query tables(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND "
                   "name!='restore_receipts' ORDER BY name");
  int status;
  while ((status = sqlite3_step(tables.value)) == SQLITE_ROW) {
    const auto name = tables.Text(0);
    Require(name.find('"') == std::string::npos);
    Require(name.find_first_not_of("abcdefghijklmnopqrstuvwxyz_") == std::string::npos);
    Query query(db, "SELECT * FROM " + name);
    std::vector<std::string> rows;
    int row;
    while ((row = sqlite3_step(query.value)) == SQLITE_ROW) {
      Json values = Json::array();
      for (int i = 0; i < sqlite3_column_count(query.value); ++i) {
        const int type = sqlite3_column_type(query.value, i);
        if (type == SQLITE_NULL)
          values.push_back(nullptr);
        else if (type == SQLITE_INTEGER)
          values.push_back(sqlite3_column_int64(query.value, i));
        else if (type == SQLITE_FLOAT)
          values.push_back(sqlite3_column_double(query.value, i));
        else {
          const auto* bytes = static_cast<const unsigned char*>(sqlite3_column_blob(query.value, i));
          values.push_back({type, Hex(bytes, static_cast<size_t>(sqlite3_column_bytes(query.value, i)))});
        }
      }
      rows.push_back(values.dump());
    }
    Require(row == SQLITE_DONE);
    std::sort(rows.begin(), rows.end());
    content[name] = rows;
  }
  Require(status == SQLITE_DONE);
  return Digest(content.dump());
}
struct Reference {
  const char* table;
  const char* conference;
  const char* generation;
};
constexpr std::array<Reference, 6> references{{{"read_status", "conference_id", "generation"},
                                               {"reading_positions", "conference", "generation"},
                                               {"operations", "conference", "generation"},
                                               {"mail_provenance", "conference", "generation"},
                                               {"mail_transfers", "source_conference", "source_generation"},
                                               {"bulk_read_operations", "conference", "generation"}}};
bool ValidGeneration(const std::string& value) {
  size_t words = 0;
  bool digit = false;
  for (unsigned char c : value) {
    if (c == ':') {
      if (!digit)
        return false;
      ++words;
      digit = false;
    } else {
      if (c < '0' || c > '9')
        return false;
      digit = true;
    }
  }
  return words == 3 && digit;
}
std::string Generation(const File& header) {
  std::array<unsigned char, 24> bytes{};
  Require(pread(header.fd, bytes.data(), bytes.size(), 0) == static_cast<ssize_t>(bytes.size()));
  Require(bytes[0] == 'J' && bytes[1] == 'A' && bytes[2] == 'M' && bytes[3] == 0);
  auto word = [&](size_t offset) {
    uint32_t result = 0;
    for (unsigned int i = 0; i < 4; ++i)
      result |= uint32_t{bytes[offset + i]} << (i * 8);
    return result;
  };
  return std::to_string(header.identity.st_dev) + ":" + std::to_string(header.identity.st_ino) + ":" +
         std::to_string(word(4)) + ":" + std::to_string(word(20));
}
void SaveBackup(sqlite3* db, int root, const std::filesystem::path& directory, const std::string& path) {
  // A new, exclusive file prevents overwriting either a previous backup or a link.
  const int fd = openat(root, path.c_str(), O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0) {
    auto existing = Open(root, path);
    Database backup(directory / path, false);
    Require(LogicalHash(backup.db) == LogicalHash(db));
    Require(fsync(existing->fd) == 0 && fsync(root) == 0);
    return;
  }
  close(fd);
  Database backup(directory / path, true);
  auto* copy = sqlite3_backup_init(backup.db, "main", db, "main");
  Require(copy != nullptr);
  const int result = sqlite3_backup_step(copy, -1);
  const int finished = sqlite3_backup_finish(copy);
  Require(result == SQLITE_DONE && finished == SQLITE_OK);
  auto file = Open(root, path);
  Require(fsync(file->fd) == 0 && fsync(root) == 0);
}
}  // namespace

Json CheckMetadataSchema(const std::filesystem::path& path) {
  File file(open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
  for (const char* suffix : {"-wal", "-shm", "-journal"}) {
    struct stat info{};
    if (lstat((path.string() + suffix).c_str(), &info) == 0)
      Require(S_ISREG(info.st_mode) && info.st_nlink == 1 && info.st_size == 0);
  }
  Database database(path, false);
  const int64_t schema = Integer(database.db, "PRAGMA user_version");
  ValidateSchema(database.db, schema);
  Integrity(database.db);
  return {{"schema", schema}, {"complete_schema", true}};
}

std::expected<void, std::string> BindRestoredGenerations(JamCatalog& catalog, const std::filesystem::path& path) {
  try {
    Database database(path, false, false);
    if (Integer(database.db, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='restored_generations'") ==
        0)
      return {};
    std::map<std::string, std::pair<std::string, std::string>> mappings;
    Query rows(database.db, "SELECT base,physical_generation,logical_generation FROM restored_generations");
    int status;
    while ((status = sqlite3_step(rows.value)) == SQLITE_ROW) {
      Parts(rows.Text(0));
      Require(ValidGeneration(rows.Text(1)) && ValidGeneration(rows.Text(2)));
      Require(mappings.emplace(rows.Text(0), std::pair{rows.Text(1), rows.Text(2)}).second);
    }
    Require(status == SQLITE_DONE);
    std::set<std::string> used;
    for (const auto& [id, area] : catalog.areas()) {
      const auto base = area.relative_filename.string();
      const auto found = mappings.find(base);
      if (found == mappings.end())
        continue;  // New bases provisioned after restore have their own physical identity.
      auto& files = *area.files;
      std::lock_guard guard(files.mutex);
      const int root = open(files.root_path.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
      Require(root >= 0);
      std::unique_ptr<File> header;
      try {
        header = Open(root, base + ".jhr");
      } catch (...) {
        close(root);
        throw;
      }
      close(root);
      Require(header->identity.st_dev == files.identities[0].st_dev &&
              header->identity.st_ino == files.identities[0].st_ino);
      Require(Generation(*header) == found->second.first && !found->second.second.empty());
      used.insert(base);
    }
    Require(used.size() == mappings.size());
    for (const auto& [id, area] : catalog.areas()) {
      const auto found = mappings.find(area.relative_filename.string());
      if (found != mappings.end()) {
        area.files->restored_physical_generation = found->second.first;
        area.files->restored_logical_generation = found->second.second;
      }
    }
    return {};
  } catch (const std::exception&) {
    return std::unexpected("Restored JAM identity verification failed");
  }
}

Json RestoreMailboxes(const std::filesystem::path& root_path, const std::filesystem::path& manifest_path,
                      const std::string& digest, const std::string& plan_digest, int maintenance_lock_fd) {
  const bool apply = !plan_digest.empty();
  Require(digest.size() == 64);
  const int root_fd = open(root_path.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  Require(root_fd >= 0);
  struct Root {
    int fd;
    ~Root() {
      close(fd);
    }
  } root{root_fd};
  File manifest_file(open(manifest_path.c_str(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
  Require(Hash(manifest_file) == digest);
  const auto manifest = Read(manifest_file);
  Require(manifest.at("version") == 1 && manifest.at("complete") == true);
  Require(manifest.at("locks").size() == 3);
  std::set<std::string> lock_names;
  std::vector<std::unique_ptr<File>> locks;
  for (const auto& path : manifest.at("locks")) {
    Require(lock_names.insert(path.get<std::string>()).second);
    auto lock = Open(root.fd, path.get<std::string>());
    if (maintenance_lock_fd != -1 && locks.empty()) {
      Require(maintenance_lock_fd >= 3);
      auto lease = std::make_unique<File>(fcntl(maintenance_lock_fd, F_DUPFD_CLOEXEC, 3));
      Require(lease->identity.st_dev == lock->identity.st_dev && lease->identity.st_ino == lock->identity.st_ino);
      // A separate description cannot acquire even a shared lock while the
      // inherited lease is exclusive. Re-locking that exact description must work.
      const int result = flock(lock->fd, LOCK_SH | LOCK_NB);
      Require(result == -1 && (errno == EWOULDBLOCK || errno == EAGAIN));
      Require(flock(lease->fd, LOCK_EX | LOCK_NB) == 0);
      lock = std::move(lease);
    } else {
      Require(flock(lock->fd, LOCK_EX | LOCK_NB) == 0);
    }
    locks.push_back(std::move(lock));
  }
  const std::string database_path = manifest.at("database");
  Require(lock_names.contains(database_path + ".lock"));
  auto database_file = Open(root.fd, database_path);
  for (const char* suffix : {"-wal", "-shm", "-journal"}) {
    const auto sidecar = root_path / (database_path + suffix);
    struct stat info{};
    if (lstat(sidecar.c_str(), &info) == 0)
      Require(S_ISREG(info.st_mode) && info.st_nlink == 1 && (apply || info.st_size == 0));
  }
  Database database(root_path / database_path, apply);
  const int64_t schema = Integer(database.db, "PRAGMA user_version");
  Require(manifest.at("schema") == schema);
  ValidateSchema(database.db, schema);
  Integrity(database.db);
  Require(Integer(database.db, "SELECT count(*) FROM operations WHERE state!=1") == 0);
  Require(Integer(database.db, "SELECT count(*) FROM mail_outbox WHERE state!=1") == 0);
  Require(Integer(database.db, "SELECT count(*) FROM mail_transfers WHERE state NOT IN (4,5)") == 0);
  Require(Integer(database.db, "SELECT count(*) FROM mail_pipeline WHERE state!=0") == 0);
  std::map<std::string, std::string> hashes;
  std::map<std::string, std::unique_ptr<File>> files;
  Json identities = Json::array();
  std::set<std::string> names;
  for (const auto& item : manifest.at("files")) {
    const std::string path = item.at("path");
    Require(names.insert(path).second);
    hashes.emplace(path, item.at("sha256").get<std::string>());
    auto file = Open(root.fd, path);
    if (path != database_path)
      Require(Hash(*file) == item.at("sha256").get<std::string>());
    identities.push_back({path, file->identity.st_dev, file->identity.st_ino});
    files.emplace(path, std::move(file));
  }
  Require(files.contains(database_path));
  for (const auto& name : lock_names)
    Require(files.contains(name));
  const std::string config_path = manifest.at("config");
  Require(files.contains(config_path));
  const auto config = Read(*files.at(config_path));
  std::map<std::string, std::pair<std::string, std::string>> generations;
  Json mappings = Json::array();
  Json restored = Json::array();
  std::set<std::string> original_generations;
  std::map<std::string, std::pair<std::string, std::string>> mailbox_files;
  for (const auto& jam : manifest.at("jam")) {
    const std::string base = jam.at("base");
    std::string physical;
    for (const char* extension : {".jhr", ".jdt", ".jdx"}) {
      Require(files.contains(base + extension));
      const auto& st = files.at(base + extension)->identity;
      physical += std::to_string(st.st_dev) + ":" + std::to_string(st.st_ino) + ";";
    }
    const auto current = Generation(*files.at(base + ".jhr"));
    const std::string original = jam.at("generation");
    Require(ValidGeneration(original) && original_generations.insert(original).second);
    Require(original.substr(original.find(':', original.find(':') + 1)) ==
            current.substr(current.find(':', current.find(':') + 1)));
    for (const auto& id : jam.at("conferences")) {
      const std::string conference = id;
      Require(generations.emplace(conference, std::pair{original, current}).second);
      mappings.push_back({conference, original, current});
    }
    Require(mailbox_files.emplace(base, std::pair{current, physical}).second);
    restored.push_back({base, current, original});
  }
  Json bindings = Json::array();
  std::set<std::string> addresses;
  for (const auto& expected : config.at("point_mail").at("points")) {
    const std::string address = expected.at("address"), base = expected.at("jam_base");
    const auto canonical = domain::CanonicalFtnAddress(address);
    Require(canonical && *canonical == address);
    Parts(base);
    Require(addresses.insert(address).second);
    const auto row = std::find_if(manifest.at("mailboxes").begin(), manifest.at("mailboxes").end(),
                                  [&](const auto& value) { return value.at("address") == address; });
    Require(row != manifest.at("mailboxes").end() && row->at("base") == base);
    const auto physical = mailbox_files.find(manifest.at("jam_root").get<std::string>() + "/" + base);
    Require(physical != mailbox_files.end());
    Query query(database.db, "SELECT base,generation,files FROM mailbox_bindings WHERE address=?");
    query.Bind(1, address);
    Require(sqlite3_step(query.value) == SQLITE_ROW && query.Text(0) == base);
    Require((query.Text(1) == row->at("generation").get<std::string>() &&
             query.Text(2) == row->at("files").get<std::string>()) ||
            (query.Text(1) == physical->second.first && query.Text(2) == physical->second.second));
    bindings.push_back({address, base, physical->second.first, physical->second.second});
  }
  Require(addresses.size() == manifest.at("mailboxes").size() &&
          static_cast<size_t>(Integer(database.db, "SELECT count(*) FROM mailbox_bindings")) == addresses.size());
  for (const auto& ref : references) {
    Query query(database.db,
                "SELECT DISTINCT " + std::string(ref.conference) + "," + ref.generation + " FROM " + ref.table);
    int status;
    while ((status = sqlite3_step(query.value)) == SQLITE_ROW) {
      const auto found = generations.find(query.Text(0));
      Require(found != generations.end() && (query.Text(1) == found->second.first));
    }
    Require(status == SQLITE_DONE);
  }
  // The plan binds both the data snapshot and the destination's physical identities.
  const Json plan = {{"manifest", digest}, {"identities", identities}, {"mappings", mappings}, {"bindings", bindings}};
  const std::string checked_digest = Digest(plan.dump());
  const auto backup_name = ".ffido-restore-" + checked_digest + ".db";
  if (Integer(database.db, "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='restore_receipts'") != 0) {
    Query saved(database.db, "SELECT plan,logical_hash FROM restore_receipts WHERE manifest=?");
    saved.Bind(1, digest);
    if (sqlite3_step(saved.value) == SQLITE_ROW) {
      Require(saved.Text(0) == checked_digest && saved.Text(1) == LogicalHash(database.db));
      Require(!apply || plan_digest == checked_digest);
      Require(sqlite3_step(saved.value) == SQLITE_DONE);
      if (apply) {
        Require(sqlite3_wal_checkpoint_v2(database.db, nullptr, SQLITE_CHECKPOINT_TRUNCATE, nullptr, nullptr) ==
                SQLITE_OK);
        Require(fsync(database_file->fd) == 0 && fsync(root.fd) == 0);
      }
      return {{"plan_digest", checked_digest}, {"already_applied", true}, {"schema", schema}};
    }
  }
  Require(Hash(*database_file) == [&]() -> std::string {
    for (const auto& item : manifest.at("files"))
      if (item.at("path") == database_path)
        return item.at("sha256");
    throw std::runtime_error("Restore database missing from manifest");
  }());
  if (!apply)
    return {
        {"plan_digest", checked_digest}, {"already_applied", false}, {"schema", schema}, {"bases", mappings.size()}};
  Require(plan_digest == checked_digest);
  SaveBackup(database.db, root.fd, root_path, backup_name);
  Execute(database.db, "PRAGMA foreign_keys=ON");
  Execute(database.db, "BEGIN IMMEDIATE");
  try {
    for (const auto& [path, file] : files) {
      auto current = Open(root.fd, path);
      Require(current->identity.st_dev == file->identity.st_dev && current->identity.st_ino == file->identity.st_ino);
      Require(Hash(*current) == hashes.at(path));
    }
    Execute(database.db, "CREATE TABLE IF NOT EXISTS restored_generations(base TEXT PRIMARY KEY,"
                         "physical_generation TEXT NOT NULL,logical_generation TEXT NOT NULL)");
    Execute(database.db, "DELETE FROM restored_generations");
    for (const auto& row : restored) {
      Query insert(database.db, "INSERT INTO restored_generations VALUES(?,?,?)");
      // Runtime catalogs use paths relative to jam_root, not the snapshot root.
      const std::string base = row[0];
      const std::string jam_root = manifest.at("jam_root").get<std::string>() + "/";
      Require(base.starts_with(jam_root));
      insert.Bind(1, base.substr(jam_root.size()));
      insert.Bind(2, row[1]);
      insert.Bind(3, row[2]);
      Require(sqlite3_step(insert.value) == SQLITE_DONE);
    }
    for (const auto& binding : bindings) {
      Query update(database.db, "UPDATE mailbox_bindings SET generation=?,files=? WHERE address=? AND base=?");
      update.Bind(1, binding[2]);
      update.Bind(2, binding[3]);
      update.Bind(3, binding[0]);
      update.Bind(4, binding[1]);
      Require(sqlite3_step(update.value) == SQLITE_DONE && sqlite3_changes(database.db) == 1);
    }
    Integrity(database.db);
    Execute(database.db, "CREATE TABLE IF NOT EXISTS restore_receipts(manifest TEXT PRIMARY KEY,plan TEXT NOT "
                         "NULL,logical_hash TEXT NOT NULL)");
    Query receipt(database.db, "INSERT INTO restore_receipts VALUES(?,?,?)");
    receipt.Bind(1, digest);
    receipt.Bind(2, checked_digest);
    receipt.Bind(3, LogicalHash(database.db));
    Require(sqlite3_step(receipt.value) == SQLITE_DONE);
    Execute(database.db, "COMMIT");
  } catch (...) {
    sqlite3_exec(database.db, "ROLLBACK", nullptr, nullptr, nullptr);
    throw;
  }
  Require(sqlite3_wal_checkpoint_v2(database.db, nullptr, SQLITE_CHECKPOINT_TRUNCATE, nullptr, nullptr) == SQLITE_OK);
  Require(fsync(database_file->fd) == 0 && fsync(root.fd) == 0);
  return {{"plan_digest", checked_digest}, {"already_applied", false}, {"applied", true}, {"schema", schema}};
}
}  // namespace fidoback::storage
