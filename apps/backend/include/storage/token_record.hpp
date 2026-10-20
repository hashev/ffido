#pragma once
#include <array>
#include <cstdint>
#include <string>

#include "domain/profile.hpp"
namespace fidoback::storage {
using TokenDigest = std::array<unsigned char, 32>;
struct AuthenticatedUser {
  std::string id;
  domain::Profile profile;
  int64_t expires_at = 0;
};
}  // namespace fidoback::storage
