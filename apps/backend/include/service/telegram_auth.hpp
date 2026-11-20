#pragma once

#include <array>
#include <cstdint>
#include <expected>
#include <string_view>

#include "domain/error.hpp"

namespace fidoback::service {
struct TelegramConfig {
  int64_t bot_id = 0;
  bool test_environment = false;
  int64_t max_age_seconds = 300;
  int64_t clock_skew_seconds = 30;
};
using TelegramPublicKey = std::array<unsigned char, 32>;
TelegramPublicKey TelegramKey(bool test_environment);
// The caller chooses a trusted key, never one supplied by the request.
std::expected<int64_t, domain::ApiError> VerifyTelegramProof(std::string_view data, const TelegramConfig& config,
                                                             int64_t now, const TelegramPublicKey& key);
}  // namespace fidoback::service
