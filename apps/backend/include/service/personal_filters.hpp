#pragma once
#include "domain/ftn_address.hpp"
#include "domain/personal_filters.hpp"
#include "service/message_search.hpp"
namespace fidoback::service {
inline std::expected<void, domain::ApiError> TrimPersonalFilterText(std::string& value) {
  auto text = FoldSearch(value, false);
  if (!text)
    return std::unexpected(text.error());
  auto space = [](char32_t c) {
    return (c >= 9 && c <= 13) || c == 32 || c == 0x85 || c == 0xa0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200a) ||
           c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f || c == 0x3000 || c == 0xfeff;
  };
  size_t first = 0, last = text->folded.size();
  while (first < last && space(text->folded[first]))
    ++first;
  while (last > first && space(text->folded[last - 1]))
    --last;
  std::vector<size_t> bytes;
  for (size_t i = 0; i < value.size();) {
    bytes.push_back(i);
    const auto c = static_cast<unsigned char>(value[i]);
    i += c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
  }
  bytes.push_back(value.size());
  value = value.substr(bytes[first], bytes[last] - bytes[first]);
  return {};
}

inline std::expected<std::vector<std::string>, domain::ApiError> MatchPersonalFilters(
    const domain::PersonalMessageFilterSet& set, std::string_view conference, bool echo, std::string_view author,
    std::string_view address, std::string_view subject) {
  std::vector<std::string> result;
  if (!echo)
    return result;
  for (const auto& r : set.rules) {
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    if (!r.enabled || (r.scope == 2 && r.conference != conference))
      continue;
    bool match = true;
    for (const auto& pair :
         {std::pair{author, std::string_view(r.author)}, std::pair{subject, std::string_view(r.subject)}}) {
      if (pair.second.empty())
        continue;
      auto ranges = SearchRanges(pair.first, pair.second, false, 1);
      if (!ranges)
        return std::unexpected(ranges.error());
      if (ranges->empty()) {
        match = false;
        break;
      }
    }
    if (!match)
      continue;
    if (!r.address.empty()) {
      auto parsed = domain::CanonicalFtnAddress(address);
      if (!parsed || *parsed != r.address)
        continue;
    }
    result.push_back(r.id);
  }
  return result;
}
}  // namespace fidoback::service
