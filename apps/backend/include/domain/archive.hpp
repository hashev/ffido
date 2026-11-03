#pragma once
#include <optional>
#include <string>
#include <vector>

#include "domain/message.hpp"
namespace fidoback::domain {
struct ArchiveSearchRequest {
  std::vector<std::string> conferences;
  std::string query, cursor;
  int scope = 2, sort = 1, limit = 20;
  std::optional<int64_t> from, to;
};
struct ArchiveSearchItem {
  std::string conference, snippet;
  MessageDetail message;
  std::vector<SearchMatch> matches;
};
struct ArchiveSearchResponse {
  std::vector<ArchiveSearchItem> results;
  bool complete = false;
  std::string incomplete_reason, next_cursor;
};
}  // namespace fidoback::domain
