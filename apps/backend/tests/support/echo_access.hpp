#pragma once
#include "service/echo_access.hpp"
namespace fidoback::test {
inline std::shared_ptr<const service::EchoAccess> EchoAccess(const storage::JamCatalog& catalog,
                                                             const std::filesystem::path& root) {
  service::HptConfiguration configuration;
  for (const auto& [id, area] : catalog.areas()) {
    service::HptEcho echo{id, root / area.relative_filename, {}};
    for (const auto* address : {"2:5015/1.1", "2:5015/1.2"})
      echo.links.emplace(address, service::EchoPermissions{true, true});
    configuration.echoes.push_back(std::move(echo));
  }
  return service::EchoAccess::Build(configuration, catalog).value();
}
}  // namespace fidoback::test
