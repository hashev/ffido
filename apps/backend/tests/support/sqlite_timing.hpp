#pragma once

#include <sqlite3.h>

#include <chrono>
#include <future>
#include <string_view>

namespace fidoback::test {
struct SqlTiming {
  std::chrono::steady_clock::time_point started, first;
  double elapsed_ms = 0, begin_ms = 0;
  size_t statements = 0;
  std::promise<void>* began = nullptr;
};
inline thread_local SqlTiming* sql_timing = nullptr;
inline int ObserveSql(unsigned kind, void*, void* statement, void* elapsed) {
  if (!sql_timing)
    return 0;
  const auto* sql = sqlite3_sql(static_cast<sqlite3_stmt*>(statement));
  if (kind == SQLITE_TRACE_STMT) {
    if (sql_timing->statements++ == 0)
      sql_timing->first = std::chrono::steady_clock::now();
    if (sql && std::string_view(sql) == "BEGIN IMMEDIATE" && sql_timing->began) {
      sql_timing->began->set_value();
      sql_timing->began = nullptr;
    }
  } else if (kind == SQLITE_TRACE_PROFILE && sql && std::string_view(sql) == "BEGIN IMMEDIATE") {
    sql_timing->begin_ms += *static_cast<sqlite3_int64*>(elapsed) / 1000000.0;
  }
  return 0;
}
inline int TraceConnection(sqlite3* db, char**, const sqlite3_api_routines*) {
  return sqlite3_trace_v2(db, SQLITE_TRACE_STMT | SQLITE_TRACE_PROFILE, ObserveSql, nullptr);
}
template <typename Action>
auto TimedSql(SqlTiming& timing, Action action) {
  timing.started = std::chrono::steady_clock::now();
  sql_timing = &timing;
  auto result = action();
  sql_timing = nullptr;
  timing.elapsed_ms =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - timing.started).count();
  return result;
}
}  // namespace fidoback::test
