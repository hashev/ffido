#include <sys/stat.h>

#include <algorithm>

#include "service/hpt_auth.hpp"

namespace fidoback::service {
std::expected<HptConfiguration, domain::ApiError> LoadHptConfiguration(const std::filesystem::path& helper,
                                                                       const AppConfig& config) {
  auto result =
      ReadHptConfiguration(helper, config.auth.hpt_config_path, std::chrono::seconds(5), config.ftn.path_mappings);
  if (!result || config.ftn.path_mappings.empty())
    return result;
  struct stat info{};
  if (stat(config.ftn.areacfg_path.c_str(), &info) != 0 || !S_ISREG(info.st_mode) ||
      std::find(result->included_files.begin(), result->included_files.end(),
                std::pair<uint64_t, uint64_t>{info.st_dev, info.st_ino}) == result->included_files.end())
    return std::unexpected(domain::ApiError::Server("Configured areas file is not an active HPT include"));
  for (auto& echo : result->echoes) {
    auto path = ftn::MapPath(echo.filename, config.ftn.path_mappings);
    if (!path)
      return std::unexpected(domain::ApiError::Server("Invalid HPT area path"));
    echo.filename = *path;
  }
  for (auto& area : result->private_areas) {
    auto path = ftn::MapPath(area.filename, config.ftn.path_mappings);
    if (!path)
      return std::unexpected(domain::ApiError::Server("Invalid HPT area path"));
    area.filename = path->string();
  }
  return result;
}

std::expected<std::vector<EchoAreaConfig>, domain::ApiError> CatalogAreas(const AppConfig& config,
                                                                          const HptConfiguration& hpt) {
  std::vector<EchoAreaConfig> areas;
  if (config.ftn.path_mappings.empty()) {
    ConfigManager manager(config.ftn.areacfg_path);
    auto parsed = manager.GetConfig();
    if (!parsed)
      return std::unexpected(domain::ApiError::Server("Invalid conference configuration"));
    areas = std::move(*parsed);
  } else {
    for (const auto& echo : hpt.echoes) {
      EchoAreaConfig area;
      area.name = echo.name;
      area.filename = echo.filename.string();
      area.msgbase_type = "JAM";
      if (!echo.description.empty())
        area.description = echo.description;
      areas.push_back(std::move(area));
    }
  }
  areas.insert(areas.end(), hpt.private_areas.begin(), hpt.private_areas.end());
  return areas;
}
}  // namespace fidoback::service
