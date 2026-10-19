#pragma once

#include <string>
#include <vector>

namespace fidoback::domain {

/// @brief Закладка пользователя.
struct Bookmark {
  std::string conference_id;
  std::string added_at;
};

/// @brief Список закладок.
struct BookmarkListResponse {
  std::vector<Bookmark> bookmarks;
};

}  // namespace fidoback::domain
