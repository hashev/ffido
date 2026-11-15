#pragma once

#include <expected>
#include <functional>
#include <string>
#include <string_view>

namespace fidoback::storage {
enum class TextError { kEncoding, kInvalidText, kLimit, kInterrupted };
std::expected<std::string, TextError> ConvertText(std::string_view text, std::string_view from, std::string_view to,
                                                  size_t max_bytes = 4 * 1024 * 1024,
                                                  const std::function<bool()>& active = {});
std::expected<std::string, TextError> Utf8Preview(std::string_view text, size_t codepoints);
}  // namespace fidoback::storage
