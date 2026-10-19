#pragma once
#include <chrono>
#include <stop_token>
namespace fidoback::storage {
using JamDeadline = std::chrono::steady_clock::time_point;
}
