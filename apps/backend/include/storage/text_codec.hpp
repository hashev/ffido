#pragma once

#include <expected>
#include <string>
#include <string_view>

namespace fidoback::storage {
enum class TextError { kEncoding, kInvalidText, kLimit };
std::expected<std::string, TextError> ConvertText(std::string_view text, std::string_view from, std::string_view to);
std::expected<std::string, TextError> Utf8Preview(std::string_view text, size_t codepoints);
}  // namespace fidoback::storage
