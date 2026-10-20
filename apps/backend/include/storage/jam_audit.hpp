#pragma once
#include <filesystem>
#include <nlohmann/json.hpp>

namespace fidoback::storage {
// Operator-only, read-only snapshot. Throws on incomplete or unsafe snapshots.
nlohmann::json AuditJam(const std::filesystem::path& database, const std::filesystem::path& base,
                        const std::filesystem::path& coordination_lock);
}  // namespace fidoback::storage
