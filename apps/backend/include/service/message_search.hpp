#pragma once
#include "domain/error.hpp"
#include "domain/message.hpp"
#include "service/request_context.hpp"
#include "storage/text_codec.hpp"

namespace fidoback::service {
inline domain::ApiError SearchInterrupted() {
  return {RequestCancellation().stop_requested() ? domain::ErrorCode::kCancelled : domain::ErrorCode::kDeadline,
          "Search interrupted",
          {}};
}
inline bool SearchCp866(std::string encoding) {
  for (auto& c : encoding)
    if (c >= 'A' && c <= 'Z')
      c += 'a' - 'A';
  return encoding == "cp866" || encoding == "866" || encoding == "ibm866" || encoding == "+7_fido";
}
struct SearchText {
  std::u32string folded;
  std::vector<uint32_t> utf16;
};
inline std::expected<SearchText, domain::ApiError> FoldSearch(std::string_view text, bool cp866) {
  if (!storage::ConvertText(text, "UTF-8", "UTF-8"))
    return std::unexpected(domain::ApiError::Validation("Invalid UTF-8 search text"));
  SearchText result;
  uint32_t units = 0;
  for (size_t i = 0; i < text.size();) {
    if ((result.folded.size() % 1024) == 0 && !RequestActive())
      return std::unexpected(SearchInterrupted());
    const auto first = static_cast<unsigned char>(text[i++]);
    char32_t c = first;
    const int extra = first < 0x80 ? 0 : first < 0xe0 ? 1 : first < 0xf0 ? 2 : 3;
    if (extra) {
      c = first & ((1u << (6 - extra)) - 1);
      for (int j = 0; j < extra; ++j)
        c = (c << 6) | (static_cast<unsigned char>(text[i++]) & 0x3f);
    }
    result.utf16.push_back(units);
    units += c > 0xffff ? 2 : 1;
    if ((c >= U'A' && c <= U'Z') || (c >= U'А' && c <= U'Я'))
      c += 32;
    if (c == U'Ё')
      c = U'ё';
    if (cp866) {
      if (c == U'н')
        c = U'h';
      if (c == U'р')
        c = U'p';
      if (c == U'у')
        c = U'y';
    }
    result.folded.push_back(c);
  }
  result.utf16.push_back(units);
  return result;
}
inline std::expected<std::vector<domain::SearchMatch>, domain::ApiError> SearchRanges(std::string_view text,
                                                                                      std::string_view query,
                                                                                      bool cp866, int field) {
  auto haystack = FoldSearch(text, cp866);
  auto needle = FoldSearch(query, cp866);
  if (!haystack)
    return std::unexpected(haystack.error());
  if (!needle)
    return std::unexpected(needle.error());
  std::vector<domain::SearchMatch> result;
  if (needle->folded.empty())
    return result;
  for (size_t i = 0; i + needle->folded.size() <= haystack->folded.size();) {
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    if (haystack->folded.compare(i, needle->folded.size(), needle->folded) == 0) {
      const auto end = i + needle->folded.size();
      result.push_back({field, haystack->utf16[i], haystack->utf16[end] - haystack->utf16[i]});
      i = end;
    } else
      ++i;
  }
  return result;
}
}  // namespace fidoback::service
