#include "storage/text_codec.hpp"

#include <iconv.h>

#include <array>
#include <cerrno>

namespace fidoback::storage {
std::expected<std::string, TextError> ConvertText(std::string_view text, std::string_view from, std::string_view to) {
  if (text.size() > 4 * 1024 * 1024)
    return std::unexpected(TextError::kLimit);
  if (from.empty() || to.empty() || from.find('\0') != std::string_view::npos ||
      to.find('\0') != std::string_view::npos || from.size() > 64 || to.size() > 64 ||
      from.find("//") != std::string_view::npos || to.find("//") != std::string_view::npos)
    return std::unexpected(TextError::kEncoding);
  auto converter = iconv_open(std::string(to).c_str(), std::string(from).c_str());
  if (converter == reinterpret_cast<iconv_t>(-1))
    return std::unexpected(TextError::kEncoding);
  struct Closer {
    iconv_t handle;
    ~Closer() {
      iconv_close(handle);
    }
  } closer{converter};
  char* input = const_cast<char*>(text.data());
  size_t left = text.size();
  std::string output;
  bool flushing = false;
  do {
    std::array<char, 4096> buffer{};
    char* cursor = buffer.data();
    size_t space = buffer.size();
    const size_t previous = left;
    auto result = iconv(converter, flushing ? nullptr : &input, flushing ? nullptr : &left, &cursor, &space);
    const size_t produced = buffer.size() - space;
    if (output.size() + produced > 4 * 1024 * 1024)
      return std::unexpected(TextError::kLimit);
    output.append(buffer.data(), produced);
    if (result == static_cast<size_t>(-1)) {
      if (errno != E2BIG || (produced == 0 && previous == left))
        return std::unexpected(TextError::kInvalidText);
    } else if (result != 0)
      return std::unexpected(TextError::kInvalidText);
    else if (flushing)
      break;
    if (left == 0)
      flushing = true;
  } while (true);
  return output;
}

std::expected<std::string, TextError> Utf8Preview(std::string_view text, size_t codepoints) {
  if (!ConvertText(text, "UTF-8", "UTF-8"))
    return std::unexpected(TextError::kInvalidText);
  size_t count = 0;
  size_t end = 0;
  for (; end < text.size(); ++end) {
    if ((static_cast<unsigned char>(text[end]) & 0xc0) != 0x80) {
      if (count == codepoints)
        break;
      ++count;
    }
  }
  return std::string(text.substr(0, end));
}
}  // namespace fidoback::storage
