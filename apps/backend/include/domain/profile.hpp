#pragma once

#include <string>

namespace fidoback::domain {

/// @brief Профиль пользователя.
struct Profile {
  std::string name;
  std::string address;  ///< FTN-адрес
  std::string email;
  std::string registered_at;
};

}  // namespace fidoback::domain
