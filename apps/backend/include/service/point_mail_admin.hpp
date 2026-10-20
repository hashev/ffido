#pragma once
#include <filesystem>
#include <string_view>
namespace fidoback::service {
int RunMailStage(const std::filesystem::path& configuration, const std::filesystem::path& helper,
                 std::string_view stage, int lease_fd);
int ProvisionMailboxes(const std::filesystem::path& configuration, const std::filesystem::path& helper);
}  // namespace fidoback::service
