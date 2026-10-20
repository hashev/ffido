#pragma once

#include <string>
#include <vector>

namespace fidoback::domain {

/// @brief Коды ошибок API.
enum class ErrorCode : int {
  kUnauthorized = 401,
  kForbidden = 403,
  kConflict = 409,
  kResource = 429,
  kUnavailable = 503,
  kDeadline = 504,
  kCancelled = 499,
  kPrecondition = 412,
  kNotFound = 404,
  kValidation = 422,
  kServer = 500,
  kNetwork = 503,
};

/// @brief Детализация ошибки валидации.
struct ErrorDetail {
  std::string field;
  std::string message;
};

/// @brief Стандартный формат ошибки API.
struct ApiError {
  ErrorCode code = ErrorCode::kServer;
  std::string message;
  std::vector<ErrorDetail> details;

  /// Фабрика для ошибки валидации.
  static ApiError Validation(std::vector<ErrorDetail> d);
  /// Фабрика для валидации (строка).
  static ApiError Validation(std::string_view msg);
  /// Фабрика для 404.
  static ApiError NotFound(std::string_view msg);
  /// Фабрика для 500.
  static ApiError Server(std::string_view msg);
  /// Фабрика для 401.
  static ApiError Unauthorized(std::string_view msg);
};

}  // namespace fidoback::domain
