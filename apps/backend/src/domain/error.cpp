#include "domain/error.hpp"

namespace fidoback::domain {

ApiError ApiError::Validation(std::vector<ErrorDetail> d) {
  return {ErrorCode::kValidation, "Validation error", std::move(d)};
}

ApiError ApiError::Validation(std::string_view msg) {
  return {ErrorCode::kValidation, std::string(msg), {}};
}

ApiError ApiError::NotFound(std::string_view msg) {
  return {ErrorCode::kNotFound, std::string(msg), {}};
}

ApiError ApiError::Server(std::string_view msg) {
  return {ErrorCode::kServer, std::string(msg), {}};
}

ApiError ApiError::Unauthorized(std::string_view msg) {
  return {ErrorCode::kUnauthorized, std::string(msg), {}};
}

}  // namespace fidoback::domain
