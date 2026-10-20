#pragma once
#include "AppConfig.h"
#include "service/hpt_auth.hpp"

namespace fidoback::service {
std::expected<void, domain::ApiError> ValidatePointMail(const AppConfig& config, const HptConfiguration& hpt);
}
