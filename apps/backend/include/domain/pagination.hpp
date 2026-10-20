#pragma once

#include <expected>
#include <string>
#include <string_view>

namespace fidoback::domain {

/// @brief Параметры пагинации.
struct PaginationRequest {
  int64_t offset = 0;
  int64_t limit = 20;
};

}  // namespace fidoback::domain
