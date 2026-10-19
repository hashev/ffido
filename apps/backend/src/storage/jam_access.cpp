#include "storage/jam_access.hpp"

namespace fidoback::storage {
std::expected<std::unique_ptr<JamAccess>, JamAccessError> JamAccess::Open(const JamCatalog& catalog,
                                                                          std::string_view conference, bool write,
                                                                          JamDeadline deadline,
                                                                          std::stop_token cancellation,
                                                                          std::string encoding) {
  std::unique_ptr<CoordinationLease> coordination;
  if (catalog.coordination()) {
    auto acquired = catalog.coordination()->Shared(deadline, cancellation);
    if (!acquired)
      return std::unexpected(JamAccessError(acquired.error()));
    coordination = std::move(*acquired);
  }
  auto area = catalog.Resolve(conference);
  if (!area)
    return std::unexpected(JamAccessError(area.error()));
  auto lease = JamLease::Acquire((*area)->files, write, deadline, cancellation);
  if (!lease)
    return std::unexpected(JamAccessError(lease.error()));
  if ((*area)->files->needs_recovery)
    return std::unexpected(JamAccessError(CatalogError::kChangedBase));
  area = catalog.Resolve(conference);
  if (!area)
    return std::unexpected(JamAccessError(area.error()));
  auto access = std::unique_ptr<JamAccess>(
      new JamAccess(std::move(coordination), std::move(*lease), std::move(encoding), deadline, cancellation));
  auto error = access->messages_.Open();
  if (error != msgapi::JamError::kSuccess)
    return std::unexpected(JamAccessError(error));
  const auto& identity = access->files().identities[0];
  const auto& header = access->messages_.base_header();
  access->generation_ = std::to_string(identity.st_dev) + ":" + std::to_string(identity.st_ino) + ":" +
                        std::to_string(header.date_created) + ":" + std::to_string(header.base_msg_num);
  return access;
}
}  // namespace fidoback::storage
