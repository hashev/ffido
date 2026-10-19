#pragma once
#include "AppConfig.h"
#include "storage/jam_catalog.hpp"
#include "storage/metadata_store.hpp"

namespace fidoback::storage {
std::string MailboxId(std::string_view address);
// Caller holds the exclusive backend instance and coordination leases.
std::expected<void, domain::ApiError> ProvisionMailbox(const std::filesystem::path& root,
                                                       const PointMailboxConfig& point, IMetadataStore& metadata);
std::expected<std::vector<EchoAreaConfig>, domain::ApiError> MailboxAreas(const PointMailConfig& config,
                                                                          IMetadataStore& metadata);
}  // namespace fidoback::storage
