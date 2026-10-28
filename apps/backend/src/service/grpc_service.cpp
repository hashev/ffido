#include "service/grpc_service.hpp"

#include <google/protobuf/util/time_util.h>

#include <condition_variable>
#include <thread>

#include "service/jam_mapping.hpp"
namespace fidoback::service {
namespace {
namespace wire = ffido::v1;
using Result = std::expected<void, domain::ApiError>;
domain::PaginationRequest Page(const wire::PageRequest& page) {
  return {page.offset(), page.limit()};
}
bool Timestamp(std::string date, google::protobuf::Timestamp* result) {
  if (date.empty())
    return true;
  if (date.size() == 19 && date[10] == ' ') {
    date[10] = 'T';
    date += 'Z';
  }
  return google::protobuf::util::TimeUtil::FromString(date, result);
}
void Map(const domain::Conference& source, wire::Conference* result) {
  result->set_id(source.id);
  result->set_can_read(source.can_read);
  result->set_can_post(source.can_post);
  result->set_kind(static_cast<wire::AreaKind>(source.kind));
  result->set_storage_format(source.storage_format);
  result->set_availability(source.unsupported_format ? wire::AREA_AVAILABILITY_UNSUPPORTED_FORMAT
                                                     : wire::AREA_AVAILABILITY_AVAILABLE);
  result->set_statistics_known(source.statistics_known);
  result->set_personal_mailbox(source.personal_mailbox);
  result->set_last_opened_message_id(source.last_opened_message);
  result->set_position_revision(source.position_revision);
  result->set_name(source.name);
  result->set_description(source.description);
  result->set_unread_count(source.unread_count);
  result->set_total_count(source.total_count);
  result->set_is_bookmarked(source.is_bookmarked);
  if (!source.last_message_date.empty())
    Timestamp(source.last_message_date, result->mutable_last_message_date());
}
template <class Message>
void Map(const Message& source, std::string_view conference, wire::Message* result) {
  result->set_id(source.id);
  result->set_conference_id(std::string(conference));
  result->set_from_name(source.from_name);
  result->set_from_address(source.from_address);
  result->set_to_name(source.to_name);
  result->set_to_address(source.to_address);
  result->set_subject(source.subject);
  Timestamp(source.date, result->mutable_date());
  result->set_is_read(source.is_read);
  result->set_thread_id(source.thread_id);
  result->set_ftn_message_id(source.ftn_message_id);
  result->set_attributes(source.attributes);
  result->set_direction(static_cast<wire::MailDirection>(source.direction));
  result->set_position_revision(source.position_revision);
  if constexpr (requires { source.body; }) {
    result->set_body(source.body);
    result->set_in_reply_to(source.in_reply_to);
  } else
    result->set_body_preview(source.body_preview);
}
grpc::Status Error(grpc::ServerContext* context, const domain::ApiError& error) {
  grpc::StatusCode code = grpc::StatusCode::INTERNAL;
  switch (error.code) {
    case domain::ErrorCode::kForbidden:
      code = grpc::StatusCode::PERMISSION_DENIED;
      break;
    case domain::ErrorCode::kUnauthorized:
      code = grpc::StatusCode::UNAUTHENTICATED;
      break;
    case domain::ErrorCode::kNotFound:
      code = grpc::StatusCode::NOT_FOUND;
      break;
    case domain::ErrorCode::kValidation:
      code = grpc::StatusCode::INVALID_ARGUMENT;
      break;
    case domain::ErrorCode::kResource:
      code = grpc::StatusCode::RESOURCE_EXHAUSTED;
      break;
    case domain::ErrorCode::kConflict:
      code = grpc::StatusCode::ALREADY_EXISTS;
      break;
    case domain::ErrorCode::kUnavailable:
      code = grpc::StatusCode::UNAVAILABLE;
      break;
    case domain::ErrorCode::kDeadline:
      code = grpc::StatusCode::DEADLINE_EXCEEDED;
      break;
    case domain::ErrorCode::kCancelled:
      code = grpc::StatusCode::CANCELLED;
      break;
    case domain::ErrorCode::kPrecondition:
      code = grpc::StatusCode::FAILED_PRECONDITION;
      break;
    default:
      break;
  }
  if (!error.details.empty()) {
    wire::ErrorDetails details;
    for (const auto& item : error.details) {
      auto* violation = details.add_violations();
      violation->set_field(item.field);
      violation->set_message(item.message);
    }
    context->AddTrailingMetadata("ffido-error-details-bin", details.SerializeAsString());
  }
  return {code, error.message};
}
Result ValidatePage(const wire::PageRequest& page) {
  if (ValidPage(Page(page)))
    return {};
  std::vector<domain::ErrorDetail> details;
  if (page.offset() < 0)
    details.push_back({"page.offset", "Must be nonnegative"});
  if (page.limit() < 1 || page.limit() > 100)
    details.push_back({"page.limit", "Must be between 1 and 100"});
  return std::unexpected(domain::ApiError::Validation(std::move(details)));
}
class CancelMonitor {
public:
  explicit CancelMonitor(grpc::ServerContext* context)
      : thread_([this, context] {
          std::unique_lock lock(mutex_);
          while (!done_) {
            if (context->IsCancelled()) {
              source_.request_stop();
              break;
            }
            wake_.wait_for(lock, std::chrono::milliseconds(10), [&] { return done_; });
          }
        }) {
  }
  ~CancelMonitor() {
    {
      std::lock_guard lock(mutex_);
      done_ = true;
    }
    wake_.notify_all();
    thread_.join();
  }
  std::stop_token token() const {
    return source_.get_token();
  }

private:
  std::stop_source source_;
  std::mutex mutex_;
  std::condition_variable wake_;
  bool done_ = false;
  std::thread thread_;
};
}  // namespace
grpc::Status GrpcService::Dispatch(grpc::ServerContext* context,
                                   const std::function<Result(const storage::AuthenticatedUser&)>& function) {
  try {
    const auto now = std::chrono::system_clock::now();
    if (context->deadline() <= now)
      return {grpc::StatusCode::DEADLINE_EXCEEDED, "Request deadline exceeded"};
    const auto& metadata = context->client_metadata();
    const auto range = metadata.equal_range("authorization");
    if (range.first == range.second || std::next(range.first) != range.second)
      return {grpc::StatusCode::UNAUTHENTICATED, "Invalid access token"};
    auto header = range.first->second;
    auto token = AuthService::ExtractBearerToken({header.data(), header.size()});
    if (!token)
      return Error(context, token.error());
    auto identity = auth_.ValidateToken(*token);
    if (!identity)
      return Error(context, identity.error());
    if (!slots_.try_acquire())
      return {grpc::StatusCode::RESOURCE_EXHAUSTED, "Too many concurrent requests"};
    struct Slot {
      std::counting_semaphore<256>& semaphore;
      ~Slot() {
        semaphore.release();
      }
    } slot{slots_};
    if (context->IsCancelled())
      return {grpc::StatusCode::CANCELLED, "Request cancelled"};
    CancelMonitor cancellation(context);
    const auto remaining =
        std::min(context->deadline() - std::chrono::system_clock::now(), std::chrono::system_clock::duration(timeout_));
    RequestBudget budget{std::chrono::steady_clock::now() + remaining, cancellation.token()};
    RequestScope scope(budget);
    auto result = function(*identity);
    if (!result && !RequestActive())
      return {std::chrono::steady_clock::now() >= budget.deadline ? grpc::StatusCode::DEADLINE_EXCEEDED
                                                                  : grpc::StatusCode::CANCELLED,
              "Request no longer active"};
    return result ? grpc::Status::OK : Error(context, result.error());
  } catch (const std::exception&) {
    return {grpc::StatusCode::INTERNAL, "Request processing failed"};
  }
}
grpc::Status GrpcService::ListConferences(grpc::ServerContext* context, const wire::ListConferencesRequest* request,
                                          wire::ListConferencesResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto valid = ValidatePage(request->page());
    if (!valid)
      return valid;
    std::string sort;
    switch (request->sort()) {
      case wire::CONFERENCE_SORT_NAME:
        sort = "name";
        break;
      case wire::CONFERENCE_SORT_LAST_MESSAGE:
        sort = "date";
        break;
      case wire::CONFERENCE_SORT_UNREAD:
        sort = "unread";
        break;
      default:
        return std::unexpected(domain::ApiError::Validation({domain::ErrorDetail{"sort", "Unknown conference sort"}}));
    }
    auto result = conferences_.GetConferences(Page(request->page()), request->query(), user.id, sort);
    if (!result)
      return std::unexpected(result.error());
    for (const auto& conference : result->conferences)
      Map(conference, response->add_conferences());
    response->set_total(result->total);
    response->set_has_more(result->has_more);
    return {};
  });
}
grpc::Status GrpcService::GetConference(grpc::ServerContext* context, const wire::GetConferenceRequest* request,
                                        wire::Conference* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto result = conferences_.GetConference(request->conference_id(), user.id);
    if (!result)
      return std::unexpected(result.error());
    Map(*result, response);
    return {};
  });
}
grpc::Status GrpcService::ListMessages(grpc::ServerContext* context, const wire::ListMessagesRequest* request,
                                       wire::ListMessagesResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto valid = ValidatePage(request->page());
    if (!valid)
      return valid;
    std::string sort;
    switch (request->sort()) {
      case wire::MESSAGE_SORT_DATE_ASCENDING:
        sort = "oldest";
        break;
      case wire::MESSAGE_SORT_DATE_DESCENDING:
        sort = "newest";
        break;
      default:
        return std::unexpected(domain::ApiError::Validation({domain::ErrorDetail{"sort", "Unknown message sort"}}));
    }
    auto result = messages_.GetMessages(request->conference_id(), Page(request->page()), sort, user.id,
                                        request->query(), request->anchor_message_id());
    if (!result)
      return std::unexpected(result.error());
    for (const auto& message : result->messages)
      Map(message, request->conference_id(), response->add_messages());
    response->set_total(result->total);
    response->set_has_more(result->has_more);
    response->set_actual_offset(result->actual_offset);
    return {};
  });
}
grpc::Status GrpcService::GetMessage(grpc::ServerContext* context, const wire::MessageReference* request,
                                     wire::Message* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto result = messages_.GetMessage(request->conference_id(), request->message_id(), user.id);
    if (!result)
      return std::unexpected(result.error());
    Map(*result, request->conference_id(), response);
    return {};
  });
}
grpc::Status GrpcService::CreateMessage(grpc::ServerContext* context, const wire::CreateMessageRequest* request,
                                        wire::CreateMessageResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    domain::CreateMessageRequest value;
    value.operation_id = request->operation_id();
    value.to_name = request->to_name();
    value.to_address = request->to_address();
    value.subject = request->subject();
    value.body = request->body();
    value.in_reply_to = request->in_reply_to();
    if (request->has_footer())
      value.footer = domain::MessageFooter{request->footer().tagline(), request->footer().origin()};
    auto result = messages_.CreateMessage(request->conference_id(), value, user.id);
    if (!result)
      return std::unexpected(result.error());
    response->mutable_message()->set_conference_id(request->conference_id());
    response->mutable_message()->set_message_id(result->id);
    response->set_ftn_message_id(result->ftn_message_id);
    response->set_status(wire::SAVE_STATUS_SAVED_LOCALLY);
    return {};
  });
}
grpc::Status GrpcService::CreateCrosspost(grpc::ServerContext* context, const wire::CreateCrosspostRequest* request,
                                          wire::CreateCrosspostResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    const auto& source = request->message();
    domain::CreateMessageRequest value{source.operation_id(), source.to_name(), source.to_address(),
                                       source.subject(),      source.body(),    source.in_reply_to()};
    if (source.has_footer())
      value.footer = domain::MessageFooter{source.footer().tagline(), source.footer().origin()};
    auto result = messages_.CreateCrosspost(
        source.conference_id(), value,
        {request->additional_conference_ids().begin(), request->additional_conference_ids().end()}, user.id);
    if (!result)
      return std::unexpected(result.error());
    response->set_complete(result->complete);
    response->set_total(result->total);
    response->set_pending_code(result->pending_code);
    for (const auto& saved : result->saved) {
      auto* copy = response->add_saved();
      copy->mutable_message()->set_conference_id(saved.conference);
      copy->mutable_message()->set_message_id(saved.id);
      copy->set_ftn_message_id(saved.ftn_message_id);
    }
    return {};
  });
}
grpc::Status GrpcService::MarkConferenceRead(grpc::ServerContext* context,
                                             const wire::MarkConferenceReadRequest* request,
                                             wire::MarkConferenceReadResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto result = messages_.MarkConferenceRead(request->conference_id(), request->operation_id(), user.id);
    if (!result)
      return std::unexpected(result.error());
    response->set_marked_count(result->marked_count);
    response->set_snapshot_count(result->snapshot_count);
    response->set_generation(result->generation);
    return {};
  });
}
grpc::Status GrpcService::MarkRead(grpc::ServerContext* context, const wire::MessageReference* request,
                                   google::protobuf::Empty*) {
  return Dispatch(context, [&](const auto& user) -> Result {
    return messages_.MarkAsRead(request->conference_id(), request->message_id(), user.id);
  });
}
grpc::Status GrpcService::GetThread(grpc::ServerContext* context, const wire::GetThreadRequest* request,
                                    wire::ListMessagesResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto valid = ValidatePage(request->page());
    if (!valid)
      return valid;
    auto result = messages_.GetThread(request->conference_id(), request->thread_id(), user.id, Page(request->page()));
    if (!result)
      return std::unexpected(result.error());
    for (const auto& message : result->messages)
      Map(message, request->conference_id(), response->add_messages());
    response->set_total(result->total);
    response->set_has_more(result->has_more);
    return {};
  });
}
grpc::Status GrpcService::ListBookmarks(grpc::ServerContext* context, const wire::PageRequest* request,
                                        wire::ListBookmarksResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto valid = ValidatePage(*request);
    if (!valid)
      return valid;
    auto saved = metadata_->GetBookmarks(user.id);
    if (!saved)
      return std::unexpected(saved.error());
    std::vector<wire::Bookmark> available;
    for (const auto& bookmark : *saved) {
      auto conference = conferences_.GetConference(bookmark.conference_id, user.id);
      if (!conference) {
        if (conference.error().code == domain::ErrorCode::kNotFound ||
            conference.error().code == domain::ErrorCode::kForbidden)
          continue;
        return std::unexpected(conference.error());
      }
      if (!conference->can_read)
        continue;
      wire::Bookmark value;
      Map(*conference, value.mutable_conference());
      if (!Timestamp(bookmark.added_at, value.mutable_added_at()))
        return std::unexpected(domain::ApiError::Server("Invalid bookmark timestamp"));
      available.push_back(std::move(value));
    }
    const auto start = std::min<uint64_t>(request->offset(), available.size()),
               end = std::min<uint64_t>(start + request->limit(), available.size());
    for (auto i = start; i < end; ++i)
      *response->add_bookmarks() = std::move(available.at(i));
    response->set_total(available.size());
    response->set_has_more(end < available.size());
    return {};
  });
}
grpc::Status GrpcService::AddBookmark(grpc::ServerContext* context, const wire::GetConferenceRequest* request,
                                      google::protobuf::Empty*) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto conference = conferences_.GetConference(request->conference_id(), user.id);
    if (!conference)
      return std::unexpected(conference.error());
    if (!conference->can_read)
      return std::unexpected(EchoAccess::Denied());
    return metadata_->AddBookmark(user.id, request->conference_id());
  });
}
grpc::Status GrpcService::RemoveBookmark(grpc::ServerContext* context, const wire::GetConferenceRequest* request,
                                         google::protobuf::Empty*) {
  return Dispatch(context, [&](const auto& user) -> Result {
    // Preserve removal of stale echo bookmarks after unsubscription. Private
    // IDs live exclusively in this namespace and require current owner access.
    if (request->conference_id().starts_with("@ffido/")) {
      auto conference = conferences_.GetConference(request->conference_id(), user.id);
      if (!conference)
        return std::unexpected(conference.error());
      if (!conference->can_read)
        return std::unexpected(EchoAccess::Denied());
    }
    return metadata_->RemoveBookmark(user.id, request->conference_id());
  });
}
grpc::Status GrpcService::ListHistory(grpc::ServerContext* context, const wire::PageRequest* request,
                                      wire::ListHistoryResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto valid = ValidatePage(*request);
    if (!valid)
      return valid;
    auto saved = metadata_->GetHistory(user.id, INT64_MAX);
    if (!saved)
      return std::unexpected(saved.error());
    std::vector<wire::HistoryEntry> available;
    for (const auto& entry : *saved) {
      auto conference = conferences_.GetConference(entry.conference_id, user.id);
      if (!conference) {
        if (conference.error().code == domain::ErrorCode::kNotFound ||
            conference.error().code == domain::ErrorCode::kForbidden)
          continue;
        return std::unexpected(conference.error());
      }
      if (!conference->can_read)
        continue;
      wire::HistoryEntry value;
      Map(*conference, value.mutable_conference());
      if (!Timestamp(entry.viewed_at, value.mutable_viewed_at()))
        return std::unexpected(domain::ApiError::Server("Invalid history timestamp"));
      available.push_back(std::move(value));
    }
    const auto start = std::min<uint64_t>(request->offset(), available.size()),
               end = std::min<uint64_t>(start + request->limit(), available.size());
    for (auto i = start; i < end; ++i)
      *response->add_history() = std::move(available.at(i));
    response->set_total(available.size());
    response->set_has_more(end < available.size());
    return {};
  });
}
grpc::Status GrpcService::ClearHistory(grpc::ServerContext* context, const google::protobuf::Empty*,
                                       google::protobuf::Empty*) {
  return Dispatch(context, [&](const auto& user) -> Result { return metadata_->ClearHistory(user.id); });
}
bool GrpcService::AllowLogin(std::string_view address, std::string peer) {
  // gRPC's peer is authenticated by the transport; forwarded metadata is ignored.
  if (const auto colon = peer.rfind(':'); colon != std::string::npos)
    peer.resize(colon);
  const auto now = std::chrono::steady_clock::now();
  std::lock_guard lock(login_mutex_);
  std::erase_if(login_attempts_,
                [&](const auto& entry) { return now - entry.second.start >= std::chrono::minutes(1); });
  const std::string keys[] = {"address:" + std::string(address), "peer:" + peer};
  for (const auto& key : keys) {
    const auto it = login_attempts_.find(key);
    if (it == login_attempts_.end() && login_attempts_.size() >= 2048)
      return false;
    if (it != login_attempts_.end() && it->second.count >= 10)
      return false;
  }
  for (const auto& key : keys) {
    auto [it, inserted] = login_attempts_.try_emplace(key, Attempts{now, 0});
    ++it->second.count;
  }
  return true;
}
grpc::Status GrpcService::Login(grpc::ServerContext* context, const wire::LoginRequest* request,
                                wire::LoginResponse* response) {
  if (context->deadline() <= std::chrono::system_clock::now())
    return {grpc::StatusCode::DEADLINE_EXCEEDED, "Request deadline exceeded"};
  if (context->IsCancelled())
    return {grpc::StatusCode::CANCELLED, "Request cancelled"};
  if (request->ByteSizeLong() > 8192)
    return {grpc::StatusCode::RESOURCE_EXHAUSTED, "Login request too large"};
  const auto address = domain::CanonicalFtnAddress(request->address());
  if (!AllowLogin(address ? *address : "invalid", context->peer()))
    return {grpc::StatusCode::RESOURCE_EXHAUSTED, "Too many login attempts; retry later"};
  if (!slots_.try_acquire())
    return {grpc::StatusCode::RESOURCE_EXHAUSTED, "Server busy"};
  struct Release {
    std::counting_semaphore<256>& slots;
    ~Release() {
      slots.release();
    }
  } release{slots_};
  try {
    const auto login = auth_.Login(request->name(), request->address(), request->password());
    if (!login)
      return Error(context, login.error());
    response->set_session_secret(login->token);
    auto* session = response->mutable_session();
    session->set_supports_message_footer(true);
    auto* profile = session->mutable_profile();
    profile->set_user_id(login->user.id);
    profile->set_name(login->user.profile.name);
    profile->set_address(login->user.profile.address);
    profile->set_email(login->user.profile.email);
    Timestamp(login->user.profile.registered_at, profile->mutable_registered_at());
    session->mutable_expires_at()->set_seconds(login->user.expires_at);
    return grpc::Status::OK;
  } catch (const std::exception&) {
    return {grpc::StatusCode::INTERNAL, "Login failed"};
  }
}
grpc::Status GrpcService::RestoreSession(grpc::ServerContext* context, const google::protobuf::Empty*,
                                         wire::SessionInfo* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto* profile = response->mutable_profile();
    profile->set_user_id(user.id);
    profile->set_name(user.profile.name);
    profile->set_address(user.profile.address);
    profile->set_email(user.profile.email);
    if (!Timestamp(user.profile.registered_at, profile->mutable_registered_at()))
      return std::unexpected(domain::ApiError::Server("Invalid profile timestamp"));
    response->mutable_expires_at()->set_seconds(user.expires_at);
    response->set_supports_message_footer(true);
    return {};
  });
}
grpc::Status GrpcService::Logout(grpc::ServerContext* context, const google::protobuf::Empty*,
                                 google::protobuf::Empty*) {
  return Dispatch(context, [&](const auto&) -> Result {
    const auto header = context->client_metadata().find("authorization")->second;
    const auto token = AuthService::ExtractBearerToken({header.data(), header.size()});
    if (!token)
      return std::unexpected(token.error());
    return auth_.Revoke(*token);
  });
}
grpc::Status GrpcService::GetProfile(grpc::ServerContext* context, const google::protobuf::Empty*,
                                     wire::Profile* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    response->set_user_id(user.id);
    response->set_name(user.profile.name);
    response->set_address(user.profile.address);
    response->set_email(user.profile.email);
    if (!Timestamp(user.profile.registered_at, response->mutable_registered_at()))
      return std::unexpected(domain::ApiError::Server("Invalid profile timestamp"));
    return {};
  });
}

namespace {
void UueSource(const UueReference& source, wire::UuePartReference* target) {
  target->mutable_message()->set_conference_id(source.conference);
  target->mutable_message()->set_message_id(source.message);
  target->set_block_index(source.block);
}
}  // namespace
grpc::Status GrpcService::SearchUueParts(grpc::ServerContext* context, const wire::SearchUuePartsRequest* request,
                                         wire::SearchUuePartsResponse* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto result = uue_.Search(request->conference_id(), request->generation(), request->after_number(),
                              request->limit(), user.id);
    if (!result)
      return std::unexpected(result.error());
    response->set_generation(result->generation);
    response->set_next_number(result->next);
    response->set_has_more(result->more);
    for (const auto& item : result->parts) {
      auto* part = response->add_parts();
      UueSource(item.source, part->mutable_source());
      part->set_from_address(item.from);
      part->set_to_address(item.to);
      part->set_subject(item.subject);
      part->set_filename(item.filename);
      part->set_part(item.part);
      part->set_total(item.total);
      part->set_body_start(item.begin);
      part->set_body_end(item.end);
      part->set_diagnostic(item.diagnostic);
      part->set_date(item.date);
      part->set_direction(static_cast<wire::MailDirection>(item.direction));
      if (item.metadata) {
        part->set_transfer_id(item.metadata->transfer_id);
        part->set_decoded_size(item.metadata->size);
        part->set_sha256(item.metadata->sha256);
      }
    }
    return {};
  });
}
grpc::Status GrpcService::AssembleUue(grpc::ServerContext* context, const wire::AssembleUueRequest* request,
                                      wire::UueAttachment* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    std::vector<UueReference> sources;
    if (static_cast<uint32_t>(request->sources_size()) > uue_.config().max_parts)
      return std::unexpected(domain::ApiError::Validation("Too many UUE sources"));
    for (const auto& source : request->sources())
      sources.push_back({source.message().conference_id(), source.message().message_id(), source.block_index()});
    auto result = uue_.Assemble(sources, request->explicit_order(), user.id);
    if (!result)
      return std::unexpected(result.error());
    response->set_id(result->id);
    response->set_filename(result->filename);
    response->set_size(result->size);
    response->set_sha256(result->sha256);
    response->set_checksum_verified(result->verified);
    response->set_state(static_cast<wire::UueState>(result->state));
    response->set_diagnostic(result->diagnostic);
    for (auto missing : result->missing)
      response->add_missing_parts(missing);
    for (const auto& source : result->sources)
      UueSource(source, response->add_sources());
    return {};
  });
}
grpc::Status GrpcService::GetUueChunk(grpc::ServerContext* context, const wire::GetUueChunkRequest* request,
                                      wire::UueChunk* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto result = uue_.Chunk(request->attachment_id(), request->offset(), request->max_bytes(), user.id);
    if (!result)
      return std::unexpected(result.error());
    response->set_data(result->bytes);
    response->set_offset(result->offset);
    response->set_total_size(result->size);
    response->set_eof(result->eof);
    return {};
  });
}

namespace {
void UueStatus(const UueSendStatus& result, wire::UueSendStatus* response) {
  response->set_filename(result.filename);
  response->set_file_size(result.file_size);
  response->set_sha256(result.sha256);
  response->set_operation_id(result.operation);
  response->set_state(result.state);
  response->set_total_parts(result.total);
  response->set_saved_parts(result.saved);
  response->set_diagnostic(result.diagnostic);
  for (const auto& id : result.messages) {
    auto* message = response->add_messages();
    message->set_conference_id(result.conference);
    message->set_message_id(id);
  }
}
}  // namespace
grpc::Status GrpcService::GetUueLimits(grpc::ServerContext* context, const google::protobuf::Empty*,
                                       wire::UueLimits* response) {
  return Dispatch(context, [&](const auto&) -> Result {
    const auto& config = uue_.config();
    response->set_max_file_bytes(config.max_file_bytes);
    response->set_part_body_bytes(config.part_body_bytes);
    response->set_max_parts(config.max_parts);
    response->set_chunk_bytes(config.chunk_bytes);
    response->set_preview_pixels(config.preview_pixels);
    response->set_preview_dimension(config.preview_dimension);
    return {};
  });
}
grpc::Status GrpcService::UploadUueChunk(grpc::ServerContext* context, const wire::UploadUueChunkRequest* request,
                                         wire::UueUploadStatus* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto result = uue_.Upload(request->operation_id(), request->filename(), request->file_size(), request->sha256(),
                              request->offset(), request->data(), user.id);
    if (!result)
      return std::unexpected(result.error());
    response->set_received_bytes(*result);
    response->set_complete(*result == request->file_size());
    return {};
  });
}
grpc::Status GrpcService::CommitUue(grpc::ServerContext* context, const wire::CommitUueRequest* request,
                                    wire::UueSendStatus* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    const auto& message = request->message();
    domain::CreateMessageRequest value;
    value.operation_id = message.operation_id();
    value.subject = message.subject();
    value.body = message.body();
    value.to_name = message.to_name();
    value.to_address = message.to_address();
    value.in_reply_to = message.in_reply_to();
    if (message.has_footer())
      value.footer = domain::MessageFooter{message.footer().tagline(), message.footer().origin()};
    auto result = uue_.Commit(message.conference_id(), value, user.id);
    if (!result)
      return std::unexpected(result.error());
    UueStatus(*result, response);
    return {};
  });
}
grpc::Status GrpcService::GetUueSendStatus(grpc::ServerContext* context, const wire::UueOperationReference* request,
                                           wire::UueSendStatus* response) {
  return Dispatch(context, [&](const auto& user) -> Result {
    auto result = uue_.SendStatus(request->operation_id(), user.id);
    if (!result)
      return std::unexpected(result.error());
    UueStatus(*result, response);
    return {};
  });
}
}  // namespace fidoback::service
