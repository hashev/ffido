#pragma once
#include <expected>
#include <string_view>

#include "domain/error.hpp"
#include "storage/token_record.hpp"
namespace fidoback::service {
std::expected<storage::TokenDigest, domain::ApiError> Sha256(std::string_view bytes);
}
