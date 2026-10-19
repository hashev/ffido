#include "storage/jam_audit.hpp"

#include <fcntl.h>
#include <sqlite3.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <memory>
#include <stdexcept>
#include <vector>

namespace fidoback::storage {
namespace {
struct Fd {
  int value;
  explicit Fd(const std::filesystem::path& path)
      : value(open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)) {
    struct stat info{};
    if (value < 0 || fstat(value, &info) != 0 || !S_ISREG(info.st_mode)) {
      if (value >= 0)
        close(value);
      throw std::runtime_error("Audit file unavailable");
    }
  }
  ~Fd() {
    close(value);
  }
};
std::vector<uint8_t> Read(const Fd& file) {
  struct stat info{};
  if (fstat(file.value, &info) != 0 || info.st_size < 0 || info.st_size > 256 * 1024 * 1024)
    throw std::runtime_error("Audit input exceeds snapshot limits");
  std::vector<uint8_t> result(static_cast<size_t>(info.st_size));
  size_t position = 0;
  while (position < result.size()) {
    const auto n = pread(file.value, result.data() + position, result.size() - position, static_cast<off_t>(position));
    if (n <= 0)
      throw std::runtime_error("Incomplete audit snapshot");
    position += static_cast<size_t>(n);
  }
  return result;
}
uint32_t Word(const std::vector<uint8_t>& bytes, size_t offset) {
  if (offset > bytes.size() || bytes.size() - offset < 4)
    throw std::runtime_error("Invalid JAM snapshot");
  return uint32_t(bytes[offset]) | uint32_t(bytes[offset + 1]) << 8 | uint32_t(bytes[offset + 2]) << 16 |
         uint32_t(bytes[offset + 3]) << 24;
}
bool EqualBlob(sqlite3_stmt* statement, int column, const std::vector<uint8_t>& bytes, size_t offset, size_t size) {
  if (sqlite3_column_bytes(statement, column) != static_cast<int>(size) || offset > bytes.size() ||
      size > bytes.size() - offset)
    return false;
  const auto* blob = static_cast<const uint8_t*>(sqlite3_column_blob(statement, column));
  return size == 0 || (blob && std::equal(blob, blob + size, bytes.begin() + static_cast<ptrdiff_t>(offset)));
}
}  // namespace
nlohmann::json AuditJam(const std::filesystem::path& database, const std::filesystem::path& base,
                        const std::filesystem::path& coordination_lock) {
  Fd coordination(coordination_lock);
  if (flock(coordination.value, LOCK_SH | LOCK_NB) != 0)
    throw std::runtime_error("Audit coordination busy");
  Fd header_file(base.string() + ".jhr"), index_file(base.string() + ".jdx"), text_file(base.string() + ".jdt");
  struct stat identity{};
  if (fstat(header_file.value, &identity) != 0)
    throw std::runtime_error("Audit identity unavailable");
  const auto headers = Read(header_file), index = Read(index_file), text = Read(text_file);
  if (headers.size() < 1024 || Word(headers, 0) != 0x004d414a || index.size() % 8 != 0)
    throw std::runtime_error("Invalid JAM snapshot");
  const auto generation = std::to_string(identity.st_dev) + ":" + std::to_string(identity.st_ino) + ":" +
                          std::to_string(Word(headers, 4)) + ":" + std::to_string(Word(headers, 20));
  // An immutable offline snapshot avoids even WAL/SHM read-lock mutations.
  // Never ignore an uncheckpointed WAL: it may contain committed operations.
  const auto canonical_database = std::filesystem::canonical(database.parent_path()) / database.filename();
  std::unique_ptr<Fd> instance;
  const auto instance_path = canonical_database.string() + ".lock";
  if (std::filesystem::exists(instance_path)) {
    instance = std::make_unique<Fd>(instance_path);
    if (flock(instance->value, LOCK_EX | LOCK_NB) != 0)
      throw std::runtime_error("Audit requires a stopped backend or an offline backup");
  }
  Fd database_file(canonical_database);
  const auto wal = canonical_database.string() + "-wal";
  struct stat wal_info{};
  if (lstat(wal.c_str(), &wal_info) == 0 && (!S_ISREG(wal_info.st_mode) || wal_info.st_size != 0))
    throw std::runtime_error("Audit requires an offline checkpointed database snapshot");
  std::string uri = "file:";
  constexpr char hex[] = "0123456789ABCDEF";
  for (unsigned char c : canonical_database.string()) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '/' || c == '.' ||
        c == '_' || c == '-')
      uri += c;
    else {
      uri += '%';
      uri += hex[c >> 4];
      uri += hex[c & 15];
    }
  }
  uri += "?immutable=1";
  sqlite3* raw = nullptr;
  const int opened =
      sqlite3_open_v2(uri.c_str(), &raw, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOFOLLOW, nullptr);
  std::unique_ptr<sqlite3, decltype(&sqlite3_close)> db(raw, sqlite3_close);
  if (opened != SQLITE_OK)
    throw std::runtime_error("Audit database unavailable");
  sqlite3_stmt* query = nullptr;
  const char* sql = "SELECT state,message_number,header_size,text_size,header_append,text_append,index_append FROM "
                    "operations WHERE generation=?";
  const int prepared = sqlite3_prepare_v2(db.get(), sql, -1, &query, nullptr);
  std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement(query, sqlite3_finalize);
  if (prepared != SQLITE_OK || sqlite3_bind_text(query, 1, generation.c_str(), -1, SQLITE_TRANSIENT) != SQLITE_OK)
    throw std::runtime_error("Audit schema unavailable");
  nlohmann::json report = {{"read_only", true},
                           {"pending_operations", 0},
                           {"quarantined_operations", 0},
                           {"records", nlohmann::json::array()}};
  std::map<uint32_t, bool> proven;
  int status;
  while ((status = sqlite3_step(query)) == SQLITE_ROW) {
    const auto state = sqlite3_column_int(query, 0);
    if (state == 0)
      report["pending_operations"] = report["pending_operations"].get<int>() + 1;
    if (state == 3)
      report["quarantined_operations"] = report["quarantined_operations"].get<int>() + 1;
    const auto offset = sqlite3_column_int64(query, 2), text_offset = sqlite3_column_int64(query, 3);
    const auto number = sqlite3_column_int64(query, 1);
    const auto size = sqlite3_column_bytes(query, 4), body_size = sqlite3_column_bytes(query, 5);
    if (state == 1 && number >= 0 && number <= UINT32_MAX && offset >= 1024 && text_offset >= 0 && size >= 76 &&
        EqualBlob(query, 4, headers, static_cast<size_t>(offset), static_cast<size_t>(size)) &&
        EqualBlob(query, 5, text, static_cast<size_t>(text_offset), static_cast<size_t>(body_size)) &&
        number >= Word(headers, 20) &&
        EqualBlob(query, 6, index, static_cast<size_t>(number - Word(headers, 20)) * 8, 8))
      proven[static_cast<uint32_t>(number)] = true;
  }
  if (status != SQLITE_DONE)
    throw std::runtime_error("Audit query failed");
  for (size_t slot = 0; slot < index.size() / 8; ++slot) {
    const auto offset = Word(index, slot * 8 + 4);
    if (offset == UINT32_MAX)
      continue;
    const auto flags = Word(headers, static_cast<size_t>(offset) + 52);
    const auto number = Word(headers, static_cast<size_t>(offset) + 48);
    const bool ours = proven.contains(number);
    // Old and new type bits overlap. Even proven old appends require explicit migration approval.
    const auto type = flags & 0x03c00000u;
    report["records"].push_back(
        {{"message_number", number},
         {"attributes", flags},
         {"provenance", ours ? "committed_ffido" : "unproven"},
         {"ambiguous_type", !ours || type == 0x00400000u || type == 0x00800000u || type == 0x01000000u || type == 0},
         {"migration_performed", false}});
  }
  return report;
}
}  // namespace fidoback::storage
