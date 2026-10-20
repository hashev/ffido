#pragma once
#include <functional>

#include "service/point_mail.hpp"
#include "storage/jam_writer.hpp"
namespace fidoback::service {
// The operator holds the exclusive lifecycle lease. RPC never constructs this coordinator.
class MailBridge {
public:
  MailBridge(const AppConfig& config, const HptConfiguration& hpt, std::shared_ptr<storage::JamCatalog> catalog,
             std::shared_ptr<storage::IMetadataStore> metadata,
             std::shared_ptr<storage::JamIo> io = std::make_shared<storage::JamIo>(),
             std::function<void(std::string_view)> cut = {})
      : config_(config),
        hpt_(hpt),
        catalog_(std::move(catalog)),
        metadata_(std::move(metadata)),
        io_(std::move(io)),
        writer_(metadata_, io_),
        cut_(std::move(cut)) {
  }
  std::expected<void, domain::ApiError> Recover();
  std::expected<void, domain::ApiError> Dispatch();

private:
  void Cut(std::string_view stage) {
    if (cut_)
      cut_(stage);
  }
  void Finish(storage::MailTransfer transfer);
  std::string AreaId(std::string_view name) const;
  const AppConfig& config_;
  const HptConfiguration& hpt_;
  std::shared_ptr<storage::JamCatalog> catalog_;
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::shared_ptr<storage::JamIo> io_;
  storage::JamWriter writer_;
  std::function<void(std::string_view)> cut_;
};
}  // namespace fidoback::service
