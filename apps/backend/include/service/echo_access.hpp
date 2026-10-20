#pragma once
#include <set>

#include "service/hpt_auth.hpp"
#include "storage/jam_catalog.hpp"
#include "storage/metadata_store.hpp"
namespace fidoback::service {
class EchoAccess {
public:
  static std::expected<std::shared_ptr<const EchoAccess>, domain::ApiError> Build(
      const HptConfiguration& configuration, const storage::JamCatalog& catalog,
      const std::vector<std::string>& owners = {});
  std::expected<EchoPermissions, domain::ApiError> Permissions(storage::IMetadataStore& metadata, std::string_view user,
                                                               std::string_view conference) const;
  static domain::ApiError Denied() {
    return {domain::ErrorCode::kForbidden, "Echo access denied", {}};
  }

private:
  std::set<std::string> owners_;
  std::map<std::string, std::pair<std::string, EchoPermissions>, std::less<>> mailboxes_;
  std::map<std::string, EchoPermissions, std::less<>> private_;
  std::map<std::string, std::map<std::string, EchoPermissions>, std::less<>> echoes_;
};
}  // namespace fidoback::service
