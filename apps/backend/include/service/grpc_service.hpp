#pragma once
#include <grpcpp/grpcpp.h>

#include <algorithm>
#include <mutex>
#include <semaphore>

#include "ffido/v1/ffido.grpc.pb.h"
#include "service/auth_service.hpp"
#include "service/conference_service.hpp"
#include "service/message_service.hpp"
#include "service/request_context.hpp"
#include "service/uue_service.hpp"
namespace fidoback::service {
class GrpcService final : public ffido::v1::Ffido::Service {
public:
  GrpcService(std::shared_ptr<storage::JamCatalog> catalog, std::shared_ptr<storage::IMetadataStore> metadata,
              std::shared_ptr<const EchoAccess> access, std::string encoding = "cp866", int max_concurrent = 16,
              int timeout_ms = 5000, UueConfig uue_config = {})
      : metadata_(std::move(metadata)),
        auth_(metadata_),
        conferences_(catalog, metadata_, access, encoding),
        messages_(catalog, metadata_, access, encoding),
        uue_(catalog, metadata_, access, encoding, std::chrono::steady_clock::now, uue_config),
        slots_(std::clamp(max_concurrent, 1, 256)),
        timeout_(std::chrono::milliseconds(std::clamp(timeout_ms, 1, 60000))) {
  }
  std::expected<void, domain::ApiError> ConfigureAuth(HptCredentials credentials, std::string_view key) {
    return auth_.Configure(std::move(credentials), key);
  }
#define FFIDO_RPC(name, request, response) \
  grpc::Status name(grpc::ServerContext* context, const request* input, response* output) override;
  FFIDO_RPC(Login, ffido::v1::LoginRequest, ffido::v1::LoginResponse)
  FFIDO_RPC(RestoreSession, google::protobuf::Empty, ffido::v1::SessionInfo)
  FFIDO_RPC(Logout, google::protobuf::Empty, google::protobuf::Empty)
  FFIDO_RPC(ListConferences, ffido::v1::ListConferencesRequest, ffido::v1::ListConferencesResponse)
  FFIDO_RPC(GetConference, ffido::v1::GetConferenceRequest, ffido::v1::Conference)
  FFIDO_RPC(ListMessages, ffido::v1::ListMessagesRequest, ffido::v1::ListMessagesResponse)
  FFIDO_RPC(GetMessage, ffido::v1::MessageReference, ffido::v1::Message)
  FFIDO_RPC(CreateMessage, ffido::v1::CreateMessageRequest, ffido::v1::CreateMessageResponse)
  FFIDO_RPC(CreateCrosspost, ffido::v1::CreateCrosspostRequest, ffido::v1::CreateCrosspostResponse)
  FFIDO_RPC(MarkConferenceRead, ffido::v1::MarkConferenceReadRequest, ffido::v1::MarkConferenceReadResponse)
  FFIDO_RPC(MarkRead, ffido::v1::MessageReference, google::protobuf::Empty)
  FFIDO_RPC(MarkUnread, ffido::v1::MessageReference, google::protobuf::Empty)
  FFIDO_RPC(GetThread, ffido::v1::GetThreadRequest, ffido::v1::ListMessagesResponse)
  FFIDO_RPC(ListBookmarks, ffido::v1::PageRequest, ffido::v1::ListBookmarksResponse)
  FFIDO_RPC(AddBookmark, ffido::v1::GetConferenceRequest, google::protobuf::Empty)
  FFIDO_RPC(RemoveBookmark, ffido::v1::GetConferenceRequest, google::protobuf::Empty)
  FFIDO_RPC(ListHistory, ffido::v1::PageRequest, ffido::v1::ListHistoryResponse)
  FFIDO_RPC(ClearHistory, google::protobuf::Empty, google::protobuf::Empty)
  FFIDO_RPC(GetProfile, google::protobuf::Empty, ffido::v1::Profile)
  FFIDO_RPC(SearchUueParts, ffido::v1::SearchUuePartsRequest, ffido::v1::SearchUuePartsResponse)
  FFIDO_RPC(AssembleUue, ffido::v1::AssembleUueRequest, ffido::v1::UueAttachment)
  FFIDO_RPC(GetUueChunk, ffido::v1::GetUueChunkRequest, ffido::v1::UueChunk)
  FFIDO_RPC(GetUueLimits, google::protobuf::Empty, ffido::v1::UueLimits)
  FFIDO_RPC(UploadUueChunk, ffido::v1::UploadUueChunkRequest, ffido::v1::UueUploadStatus)
  FFIDO_RPC(CommitUue, ffido::v1::CommitUueRequest, ffido::v1::UueSendStatus)
  FFIDO_RPC(GetUueSendStatus, ffido::v1::UueOperationReference, ffido::v1::UueSendStatus)
#undef FFIDO_RPC
private:
  grpc::Status Dispatch(
      grpc::ServerContext* context,
      const std::function<std::expected<void, domain::ApiError>(const storage::AuthenticatedUser&)>& operation);
  std::shared_ptr<storage::IMetadataStore> metadata_;
  AuthService auth_;
  struct Attempts {
    std::chrono::steady_clock::time_point start;
    unsigned count = 0;
  };
  std::mutex login_mutex_;
  std::map<std::string, Attempts> login_attempts_;
  bool AllowLogin(std::string_view address, std::string peer);
  ConferenceService conferences_;
  MessageService messages_;
  UueService uue_;
  std::counting_semaphore<256> slots_;
  std::chrono::milliseconds timeout_;
};
}  // namespace fidoback::service
