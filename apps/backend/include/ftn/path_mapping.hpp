#pragma once

#include <expected>
#include <filesystem>
#include <span>
#include <vector>

namespace fidoback::ftn {
struct PathMapping {
  std::filesystem::path from, to;
};
enum class PathError { kInvalid };
std::expected<std::vector<PathMapping>, PathError> ValidateMappings(std::span<const PathMapping> mappings);
std::expected<std::filesystem::path, PathError> MapPath(const std::filesystem::path& path,
                                                        std::span<const PathMapping> mappings);
}  // namespace fidoback::ftn
