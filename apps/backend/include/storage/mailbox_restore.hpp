#pragma once

#include <expected>
#include <filesystem>
#include <nlohmann/json.hpp>
#include <string>

namespace fidoback::storage {
class JamCatalog;
nlohmann::json CheckMetadataSchema(const std::filesystem::path& database);
std::expected<void, std::string> BindRestoredGenerations(JamCatalog& catalog, const std::filesystem::path& database);
// Opens only existing schema 11/12 databases; never calls the migrator.
nlohmann::json RestoreMailboxes(const std::filesystem::path& root, const std::filesystem::path& manifest,
                                const std::string& digest, const std::string& plan_digest = {},
                                int maintenance_lock_fd = -1);
}  // namespace fidoback::storage
