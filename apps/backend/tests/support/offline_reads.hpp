#pragma once
#include <sqlite3.h>

#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "JamMessageBase.h"

namespace fidoback::test {
// Include every column (also revisions), and compare around each read/error.
inline std::vector<std::string> ReadingSnapshot(const std::filesystem::path& path) {
  sqlite3* raw = nullptr;
  const int opened = sqlite3_open(path.c_str(), &raw);
  std::unique_ptr<sqlite3, decltype(&sqlite3_close)> db(raw, sqlite3_close);
  if (opened != SQLITE_OK)
    throw std::runtime_error("Cannot open fixture metadata");
  std::vector<std::string> result;
  for (const char* table : {"read_status", "history", "reading_positions", "personal_filters"}) {
    sqlite3_stmt* statement = nullptr;
    const auto sql = std::string("SELECT * FROM ") + table + " ORDER BY rowid";
    if (sqlite3_prepare_v2(db.get(), sql.c_str(), -1, &statement, nullptr) != SQLITE_OK)
      throw std::runtime_error("Cannot snapshot fixture table");
    std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> query(statement, sqlite3_finalize);
    int status = 0;
    while ((status = sqlite3_step(query.get())) == SQLITE_ROW) {
      std::string row = table;
      for (int i = 0; i < sqlite3_column_count(query.get()); ++i) {
        row += ":" + std::to_string(sqlite3_column_type(query.get(), i)) + ":";
        const int length = sqlite3_column_bytes(query.get(), i);
        row += std::to_string(length) + ":";
        if (length)
          row.append(static_cast<const char*>(sqlite3_column_blob(query.get(), i)), length);
      }
      result.push_back(std::move(row));
    }
    if (status != SQLITE_DONE)
      throw std::runtime_error("Cannot finish fixture snapshot");
  }
  return result;
}
inline msgapi::JamMessage OfflineRawMessage() {
  msgapi::JamMessage raw;
  raw.SetText("body");
  raw.SetSubject("hidden");
  raw.set_attributes2(0x80000001u);
  for (uint16_t low : {4, 5, 2000, 2001, 2002, 2004, 7, 60000}) {
    raw.AddRawSubField(static_cast<msgapi::JamSubFieldType>(low), "value");
    raw.AddRawSubField(static_cast<msgapi::JamSubFieldType>(low), std::string("A\0\xff", 3), 9);
    raw.AddRawSubField(static_cast<msgapi::JamSubFieldType>(low), "", 17);
  }
  return raw;
}
}  // namespace fidoback::test
