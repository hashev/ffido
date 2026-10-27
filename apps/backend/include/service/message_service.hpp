#pragma once
#include <expected>
#include <memory>
#include <string_view>
#include <vector>

#include "domain/error.hpp"
#include "domain/message.hpp"
#include "domain/pagination.hpp"
#include "service/echo_access.hpp"
#include "storage/jam_access.hpp"
#include "storage/jam_writer.hpp"
#include "storage/metadata_store.hpp"
namespace fidoback::service {
struct UuePublishOptions {
  std::string kludge, msgid, generation, from_name, from_address, to_name, to_address;
  bool freeze_recipient = false;
};
struct CrosspostPublishOptions {
  domain::Profile profile;
  std::string generation, msgid, to_name, to_address;
};
class MessageService {
public:
  MessageService(std::shared_ptr<storage::JamCatalog> catalog, std::shared_ptr<storage::IMetadataStore> metadata,
                 std::shared_ptr<const EchoAccess> access, std::string encoding = "cp866",
                 std::shared_ptr<storage::JamIo> io = std::make_shared<storage::JamIo>())
      : catalog_(std::move(catalog)),
        metadata_(std::move(metadata)),
        access_(std::move(access)),
        encoding_(std::move(encoding)),
        writer_(metadata_, std::move(io)) {
  }
  std::expected<domain::MessageListResponse, domain::ApiError> GetMessages(std::string_view conference,
                                                                           const domain::PaginationRequest& page,
                                                                           std::string_view sort, std::string_view user,
                                                                           std::string_view query = {},
                                                                           std::string_view anchor_message_id = {});
  std::expected<domain::MessageDetail, domain::ApiError> GetMessage(std::string_view conference,
                                                                    std::string_view message, std::string_view user);
  // Read without changing read status, history or reading position (attachment indexing).
  std::expected<domain::MessageDetail, domain::ApiError> PeekMessage(std::string_view conference,
                                                                     std::string_view message, std::string_view user);
  std::expected<domain::CreateMessageResponse, domain::ApiError> CreateMessage(
      std::string_view conference, const domain::CreateMessageRequest& request, std::string_view user,
      const UuePublishOptions* uue = nullptr, bool validate_only = false,
      const CrosspostPublishOptions* crosspost = nullptr);
  std::expected<domain::CreateCrosspostResponse, domain::ApiError> CreateCrosspost(
      std::string_view conference, const domain::CreateMessageRequest& request, std::vector<std::string> additional,
      std::string_view user);
  std::expected<storage::BulkReadResult, domain::ApiError> MarkConferenceRead(std::string_view conference,
                                                                              std::string_view operation,
                                                                              std::string_view user);
  std::expected<void, domain::ApiError> MarkAsRead(std::string_view conference, std::string_view message,
                                                   std::string_view user);
  std::expected<domain::ThreadListResponse, domain::ApiError> GetThread(std::string_view conference,
                                                                        std::string_view thread, std::string_view user,
                                                                        const domain::PaginationRequest& page = {});

private:
  std::expected<domain::MessageDetail, domain::ApiError> Detail(storage::JamAccess& access, std::string_view conference,
                                                                uint32_t number, std::string_view user);
  std::shared_ptr<storage::JamCatalog> catalog_;
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::shared_ptr<const EchoAccess> access_;
  std::string encoding_;
  storage::JamWriter writer_;
};
}  // namespace fidoback::service
