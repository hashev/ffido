#pragma once
#include <charconv>
#include <ctime>

#include "domain/error.hpp"
#include "domain/pagination.hpp"
#include "storage/jam_access.hpp"
namespace fidoback::service {
inline domain::ApiError JamError(const storage::JamAccessError& error) {
  if (auto* catalog = std::get_if<storage::CatalogError>(&error);
      catalog && *catalog == storage::CatalogError::kNotFound)
    return domain::ApiError::NotFound("Conference not found");
  if (auto* coordination = std::get_if<storage::CoordinationError>(&error)) {
    if (*coordination == storage::CoordinationError::kTimeout)
      return {domain::ErrorCode::kDeadline, "Request deadline exceeded", {}};
    if (*coordination == storage::CoordinationError::kCancelled)
      return {domain::ErrorCode::kCancelled, "Request cancelled", {}};
    return {domain::ErrorCode::kPrecondition, "Coordination lock unavailable", {}};
  }
  if (auto* lock = std::get_if<storage::JamLockError>(&error)) {
    if (*lock == storage::JamLockError::kTimeout)
      return {domain::ErrorCode::kDeadline, "Request deadline exceeded", {}};
    if (*lock == storage::JamLockError::kCancelled)
      return {domain::ErrorCode::kCancelled, "Request cancelled", {}};
    if (*lock == storage::JamLockError::kReadOnly)
      return {domain::ErrorCode::kPrecondition, "Message base is read-only", {}};
  }
  return domain::ApiError::Server("Message storage operation failed");
}
inline std::string MessageId(const storage::JamAccess& access, uint32_t number) {
  return access.generation() + "#" + std::to_string(number);
}
inline std::expected<uint32_t, domain::ApiError> MessageNumber(const storage::JamAccess& access, std::string_view id) {
  const auto prefix = access.generation() + "#";
  if (!id.starts_with(prefix))
    return std::unexpected(domain::ApiError::NotFound("Message not found"));
  id.remove_prefix(prefix.size());
  uint32_t number = 0;
  auto [end, error] = std::from_chars(id.data(), id.data() + id.size(), number);
  if (error != std::errc{} || end != id.data() + id.size() || number == 0)
    return std::unexpected(domain::ApiError::NotFound("Message not found"));
  return number;
}
inline std::string UtcDate(uint32_t seconds) {
  const time_t timestamp = seconds;
  std::tm date{};
  if (!gmtime_r(&timestamp, &date))
    return {};
  char text[32];
  if (std::strftime(text, sizeof(text), "%Y-%m-%dT%H:%M:%SZ", &date) == 0)
    return {};
  return text;
}
inline bool ValidPage(const domain::PaginationRequest& page) {
  return page.offset >= 0 && page.limit >= 1 && page.limit <= 100;
}
}  // namespace fidoback::service
