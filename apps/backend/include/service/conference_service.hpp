#pragma once
#include <expected>
#include <memory>
#include <optional>

#include "domain/conference.hpp"
#include "domain/error.hpp"
#include "domain/pagination.hpp"
#include "service/echo_access.hpp"
#include "storage/jam_access.hpp"
#include "storage/metadata_store.hpp"
namespace fidoback::service {
class ConferenceService {
public:
  ConferenceService(std::shared_ptr<storage::JamCatalog> catalog, std::shared_ptr<storage::IMetadataStore> metadata,
                    std::shared_ptr<const EchoAccess> access, std::string encoding = "cp866")
      : catalog_(std::move(catalog)),
        metadata_(std::move(metadata)),
        access_(std::move(access)),
        encoding_(std::move(encoding)) {
  }
  std::expected<domain::ConferenceListResponse, domain::ApiError> GetConferences(const domain::PaginationRequest& page,
                                                                                 std::optional<std::string_view> search,
                                                                                 std::string_view user,
                                                                                 std::string_view sort = "name");
  std::expected<domain::Conference, domain::ApiError> GetConference(std::string_view id, std::string_view user);

private:
  std::shared_ptr<storage::JamCatalog> catalog_;
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::shared_ptr<const EchoAccess> access_;
  std::string encoding_;
};
}  // namespace fidoback::service
