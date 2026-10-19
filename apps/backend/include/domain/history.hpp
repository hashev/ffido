#pragma once
#include <string>
namespace fidoback::domain {
struct HistoryEntry {
  std::string conference_id, viewed_at;
};
}  // namespace fidoback::domain
