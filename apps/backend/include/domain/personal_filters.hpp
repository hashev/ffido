#pragma once
#include <cstdint>
#include <string>
#include <vector>
namespace fidoback::domain {
struct PersonalMessageFilter {
  std::string id;
  bool enabled = true;
  int scope = 1;
  std::string conference, author, address, subject;
  bool operator==(const PersonalMessageFilter&) const = default;
};
struct PersonalMessageFilterSet {
  uint64_t revision = 0;
  std::vector<PersonalMessageFilter> rules;
};
struct PersonalMessageCollapse {
  uint64_t revision = 0;
  std::vector<std::string> rules;
};
}  // namespace fidoback::domain
