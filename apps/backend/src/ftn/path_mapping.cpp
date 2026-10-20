#include "ftn/path_mapping.hpp"

#include <set>

namespace fidoback::ftn {
namespace {
bool Valid(const std::filesystem::path& path, bool rule) {
  if (!path.is_absolute() || path.string().find('\0') != std::string::npos)
    return false;
  for (const auto& part : path)
    if ((rule && part == ".") || part == "..")
      return false;
  return true;
}
std::filesystem::path Normalize(const std::filesystem::path& path) {
  auto result = path.lexically_normal();
  if (result != result.root_path() && result.filename().empty())
    result = result.parent_path();
  return result;
}
}  // namespace
std::expected<std::vector<PathMapping>, PathError> ValidateMappings(std::span<const PathMapping> mappings) {
  if (mappings.size() > 128)
    return std::unexpected(PathError::kInvalid);
  std::set<std::filesystem::path> sources;
  std::vector<PathMapping> result;
  for (const auto& mapping : mappings) {
    if (!Valid(mapping.from, true) || !Valid(mapping.to, true))
      return std::unexpected(PathError::kInvalid);
    PathMapping normalized{Normalize(mapping.from), Normalize(mapping.to)};
    if (!sources.insert(normalized.from).second)
      return std::unexpected(PathError::kInvalid);
    result.push_back(std::move(normalized));
  }
  return result;
}
std::expected<std::filesystem::path, PathError> MapPath(const std::filesystem::path& path,
                                                        std::span<const PathMapping> mappings) {
  if (!Valid(path, false))
    return std::unexpected(PathError::kInvalid);
  const auto normalized = Normalize(path);
  const PathMapping* selected = nullptr;
  size_t length = 0;
  std::filesystem::path suffix;
  for (const auto& mapping : mappings) {
    auto source = mapping.from.begin(), candidate = normalized.begin();
    size_t matched = 0;
    while (source != mapping.from.end() && candidate != normalized.end() && *source == *candidate) {
      ++source;
      ++candidate;
      ++matched;
    }
    if (source != mapping.from.end() || matched <= length)
      continue;
    selected = &mapping;
    length = matched;
    suffix.clear();
    for (; candidate != normalized.end(); ++candidate)
      suffix /= *candidate;
  }
  return selected ? Normalize(selected->to / suffix) : normalized;
}
}  // namespace fidoback::ftn
