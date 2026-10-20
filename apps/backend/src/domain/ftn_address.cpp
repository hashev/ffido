#include "domain/ftn_address.hpp"

#include <charconv>

namespace fidoback::domain {
std::expected<std::string, ApiError> CanonicalFtnAddress(std::string_view address) {
  std::string result;
  size_t offset = 0;
  for (int part = 0; part < 4; ++part) {
    const auto end = address.find(part == 0 ? ':' : part == 1 ? '/' : '.', offset);
    const auto text = address.substr(offset, end == std::string_view::npos ? end : end - offset);
    unsigned value = 0;
    const auto [last, error] = std::from_chars(text.data(), text.data() + text.size(), value);
    if (text.empty() || error != std::errc{} || last != text.data() + text.size() || value > 65535 ||
        (part < 2 && value == 0) || (part < 2 && end == std::string_view::npos) ||
        (part == 3 && end != std::string_view::npos))
      return std::unexpected(ApiError::Validation("Invalid FTN address"));
    if (part < 3 || value)
      result += (part == 0 ? "" : part == 1 ? ":" : part == 2 ? "/" : ".") + std::to_string(value);
    if (part >= 2 && end == std::string_view::npos)
      return result;
    offset = end + 1;
  }
  return result;
}

}  // namespace fidoback::domain
