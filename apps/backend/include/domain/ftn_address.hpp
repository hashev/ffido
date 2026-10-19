#pragma once
#include <expected>
#include <string>
#include <string_view>

#include "domain/error.hpp"

namespace fidoback::domain {
std::expected<std::string, ApiError> CanonicalFtnAddress(std::string_view address);
}  // namespace fidoback::domain
