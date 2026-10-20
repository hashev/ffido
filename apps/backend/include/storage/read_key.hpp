#pragma once
#include <string_view>
namespace fidoback::storage {
struct ReadKey {
  std::string_view conference;
  std::string_view generation;
  std::string_view message;
};
}  // namespace fidoback::storage
