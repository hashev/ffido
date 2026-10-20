#include "service/message_service.hpp"

#include <openssl/rand.h>

#include <algorithm>
#include <set>

#include "ftn/uue_metadata.hpp"
#include "service/auth_service.hpp"
#include "service/crypto.hpp"
#include "service/jam_mapping.hpp"
#include "service/request_context.hpp"

namespace fidoback::service {
namespace {
std::string NormalizeOutgoingText(std::string_view text) {
  constexpr std::string_view cyrillic_n = "Н";
  std::string result;
  result.reserve(text.size());
  while (!text.empty()) {
    const auto position = text.find(cyrillic_n);
    if (position == std::string_view::npos) {
      result += text;
      break;
    }
    result += text.substr(0, position);
    result += 'H';
    text.remove_prefix(position + cyrillic_n.size());
  }
  return result;
}

std::string OriginAddress(const msgapi::JamMessage& message) {
  auto address = message.origin_address();
  if (!address.empty())
    return address;
  // Echomail may omit OADDRESS; a FTN MSGID starts with its origin address.
  const auto id = message.msg_id();
  const auto separator = id.find_first_of(" \t");
  if (separator == std::string::npos || id.find_first_not_of(" \t", separator) == std::string::npos)
    return {};
  const auto candidate = std::string_view(id).substr(0, separator);
  return ValidFtnAddress(candidate) ? std::string(candidate) : std::string{};
}

std::string DisplayText(std::string_view text) {
  std::string result;
  result.reserve(text.size());
  for (size_t i = 0; i < text.size(); ++i) {
    if (text[i] == '\r') {
      result += '\n';
      if (i + 1 < text.size() && text[i + 1] == '\n')
        ++i;
    } else {
      result += text[i];
    }
  }
  return result;
}
}  // namespace

std::expected<domain::MessageDetail, domain::ApiError> MessageService::Detail(storage::JamAccess& access,
                                                                              std::string_view conference,
                                                                              uint32_t number, std::string_view user) {
  auto message = access.messages().ReadMessage(number);
  if (!message) {
    if (message.error() == msgapi::JamError::kInvalidMessageNumber ||
        message.error() == msgapi::JamError::kMessageDeleted)
      return std::unexpected(domain::ApiError::NotFound("Message not found"));
    return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
  }
  const auto key_number = std::to_string(number);
  auto read = metadata_->IsMessageRead(user, {conference, access.generation(), key_number});
  if (!read)
    return std::unexpected(read.error());
  domain::MessageDetail result;
  result.id = MessageId(access, number);
  for (const auto& field : message->subfields())
    if (field.type() == msgapi::JamSubFieldType::kFtsKludge && field.high_id() == 0)
      result.ftn_kludges.push_back(field.ToString());
  result.from_name = message->sender_name();
  result.to_name = message->receiver_name();
  result.from_address = OriginAddress(*message);
  result.to_address = message->dest_address();
  if (result.to_address.empty()) {
    // SMAPI rewrites echo headers without DADDRESS. Recover only a proven local send;
    // REPLY and the current user's profile do not establish an explicit recipient.
    auto recipient = metadata_->GetCommittedRecipient({conference, access.generation(), key_number}, message->msg_id());
    if (!recipient)
      return std::unexpected(recipient.error());
    if (!recipient->empty() && !ValidFtnAddress(*recipient))
      return std::unexpected(domain::ApiError::Server("Invalid operation recipient"));
    result.to_address = std::move(*recipient);
  }
  result.subject = message->subject();
  result.body = DisplayText(message->text());
  result.date = UtcDate(message->date_written());
  result.is_read = *read;
  result.in_reply_to = message->reply_to() ? MessageId(access, message->reply_to()) : "";
  result.ftn_message_id = message->msg_id();
  result.attributes = message->attributes();
  auto direction = metadata_->MailDirection({conference, access.generation(), key_number});
  if (!direction)
    return std::unexpected(direction.error());
  result.direction = *direction == 1 || *direction == 2 ? *direction : 0;
  result.thread_id = message->reply_to() ? MessageId(access, message->reply_to()) : result.id;
  return result;
}
std::expected<domain::MessageListResponse, domain::ApiError> MessageService::GetMessages(
    std::string_view conference, const domain::PaginationRequest& page, std::string_view sort, std::string_view user,
    std::string_view query, std::string_view anchor_message_id) {
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  if (!ValidPage(page) || (sort != "newest" && sort != "oldest"))
    return std::unexpected(domain::ApiError::Validation("Invalid page or sort"));
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto numbers = (*access)->messages().GetMessageNumbers();
  if (!numbers)
    return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
  std::vector<std::pair<uint32_t, uint32_t>> ordered;
  for (auto number : *numbers) {
    auto header = (*access)->messages().GetHeader(number);
    if (!header)
      return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
    if (!query.empty()) {
      auto message = (*access)->messages().ReadMessage(number);
      if (!message)
        return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
      if (message->subject().find(query) == std::string::npos &&
          message->sender_name().find(query) == std::string::npos && message->text().find(query) == std::string::npos)
        continue;
    }
    ordered.emplace_back(header->date_written, number);
  }
  std::sort(ordered.begin(), ordered.end());
  if (sort == "newest")
    std::reverse(ordered.begin(), ordered.end());
  numbers->clear();
  for (auto [date, number] : ordered) {
    (void)date;
    numbers->push_back(number);
  }
  domain::MessageListResponse result;
  result.total = static_cast<int64_t>(numbers->size());
  auto start = std::min<uint64_t>(page.offset, numbers->size());
  if (!anchor_message_id.empty()) {
    auto anchor = MessageNumber(**access, anchor_message_id);
    if (!anchor)
      return std::unexpected(anchor.error());
    auto found = std::find(numbers->begin(), numbers->end(), *anchor);
    if (found == numbers->end())
      return std::unexpected(domain::ApiError::NotFound("Anchor message is unavailable in this view"));
    const auto index = static_cast<uint64_t>(found - numbers->begin());
    start = (index / static_cast<uint64_t>(page.limit)) * static_cast<uint64_t>(page.limit);
  }
  result.actual_offset = static_cast<int64_t>(start);
  const auto end = std::min<uint64_t>(start + page.limit, numbers->size());
  for (auto i = start; i < end; ++i) {
    auto detail = Detail(**access, conference, numbers->at(i), user);
    if (!detail)
      return std::unexpected(detail.error());
    auto preview = storage::Utf8Preview(detail->body, 200);
    if (!preview)
      return std::unexpected(domain::ApiError::Server("Invalid message text"));
    domain::MessageSummary summary;
    summary.id = detail->id;
    summary.from_name = detail->from_name;
    summary.to_name = detail->to_name;
    summary.from_address = detail->from_address;
    summary.to_address = detail->to_address;
    summary.subject = detail->subject;
    summary.date = detail->date;
    summary.ftn_message_id = detail->ftn_message_id;
    summary.direction = detail->direction;
    summary.attributes = detail->attributes;
    summary.body_preview = *preview;
    summary.is_read = detail->is_read;
    summary.thread_id = detail->thread_id;
    result.messages.push_back(std::move(summary));
  }
  result.has_more = end < numbers->size();
  return result;
}
std::expected<domain::MessageDetail, domain::ApiError> MessageService::GetMessage(std::string_view conference,
                                                                                  std::string_view id,
                                                                                  std::string_view user) {
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto number = MessageNumber(**access, id);
  if (!number)
    return std::unexpected(number.error());
  auto result = Detail(**access, conference, *number, user);
  if (!result)
    return result;
  const auto key_number = std::to_string(*number);
  auto marked = metadata_->RecordMessageView(user, {conference, (*access)->generation(), key_number});
  if (!marked)
    return std::unexpected(marked.error());
  result->is_read = true;
  result->position_revision = marked->revision;
  return result;
}
std::expected<domain::MessageDetail, domain::ApiError> MessageService::PeekMessage(std::string_view conference,
                                                                                   std::string_view id,
                                                                                   std::string_view user) {
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto number = MessageNumber(**access, id);
  if (!number)
    return std::unexpected(number.error());
  return Detail(**access, conference, *number, user);
}
std::expected<storage::BulkReadResult, domain::ApiError> MessageService::MarkConferenceRead(std::string_view conference,
                                                                                            std::string_view operation,
                                                                                            std::string_view user) {
  auto area = catalog_->areas().find(conference);
  if (area == catalog_->areas().end())
    return std::unexpected(domain::ApiError::NotFound("Conference not found"));
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  if (area->second.config.kind != AreaKind::kEcho)
    return std::unexpected(
        domain::ApiError{domain::ErrorCode::kPrecondition, "Bulk read is available only for echoes", {}});
  if (operation.empty() || operation.size() > 128 ||
      operation.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") !=
          std::string_view::npos)
    return std::unexpected(domain::ApiError::Validation("Invalid operation_id"));
  auto previous = metadata_->FindBulkRead(user, operation, conference);
  if (!previous)
    return std::unexpected(previous.error());
  if (*previous)
    return **previous;
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto numbers = (*access)->messages().GetMessageNumbers();
  if (!numbers)
    return std::unexpected(JamError(storage::JamAccessError{numbers.error()}));
  return metadata_->MarkConferenceRead(user, operation, conference, (*access)->generation(), *numbers, RequestActive);
}
std::expected<void, domain::ApiError> MessageService::MarkAsRead(std::string_view conference, std::string_view id,
                                                                 std::string_view user) {
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto number = MessageNumber(**access, id);
  if (!number)
    return std::unexpected(number.error());
  auto result = Detail(**access, conference, *number, user);
  if (!result)
    return std::unexpected(result.error());
  const auto key_number = std::to_string(*number);
  return metadata_->MarkMessageRead(user, {conference, (*access)->generation(), key_number});
}
std::expected<domain::CreateMessageResponse, domain::ApiError> MessageService::CreateMessage(
    std::string_view conference, const domain::CreateMessageRequest& request, std::string_view user,
    const UuePublishOptions* uue, bool validate_only) {
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!(permission->post && (request.in_reply_to.empty() || permission->read)))
    return std::unexpected(EchoAccess::Denied());
  auto safe = [](std::string_view value, size_t limit, bool required) {
    return value.size() <= limit && (!required || !value.empty()) && value.find('\0') == std::string_view::npos &&
           value.find('\1') == std::string_view::npos && bool(storage::ConvertText(value, "UTF-8", "UTF-8"));
  };
  if (request.operation_id.empty() || request.operation_id.size() > 128 ||
      request.operation_id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") !=
          std::string::npos ||
      request.in_reply_to.size() > 256 || request.subject.find_first_of("\r\n") != std::string::npos ||
      request.to_name.find_first_of("\r\n") != std::string::npos || !safe(request.subject, 256, true) ||
      !safe(request.body, msgapi::jam_wire::kMaxBody - 256, true) || !safe(request.to_name, 256, false) ||
      (!request.to_address.empty() && !ValidFtnAddress(request.to_address)))
    return std::unexpected(domain::ApiError::Validation("Invalid operation, recipient, subject or body"));
  auto profile = metadata_->GetProfile(user);
  if (!profile)
    return std::unexpected(profile.error());
  if (!ValidFtnAddress(profile->address) || !safe(profile->name, 256, true))
    return std::unexpected(domain::ApiError::Validation("Invalid assigned sender profile"));
  if (uue) {
    const auto prefix = profile->address + " ";
    if (!ftn::uue::ParseMetadata(uue->kludge, {16 * 1024 * 1024, 32 * 1024 * 1024, 1024}) ||
        !uue->msgid.starts_with(prefix) || uue->msgid.size() != prefix.size() + 8 ||
        std::string_view(uue->msgid).substr(prefix.size()).find_first_not_of("0123456789abcdef") !=
            std::string_view::npos)
      return std::unexpected(domain::ApiError::Validation("Invalid internal UUE envelope"));
    if (profile->name != uue->from_name || profile->address != uue->from_address)
      return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "UUE sender profile changed", {}});
  }
  const auto& area = catalog_->areas().at(std::string(conference)).config;
  const auto kind = area.kind;
  if (kind != AreaKind::kEcho && area.aka &&
      domain::CanonicalFtnAddress(*area.aka).value_or("") != domain::CanonicalFtnAddress(profile->address).value_or(""))
    return std::unexpected(domain::ApiError::Validation("Sender is incompatible with area AKA"));
  if (kind == AreaKind::kNetmail && request.in_reply_to.empty() &&
      (request.to_name.find_first_not_of(" \t") == std::string::npos || !ValidFtnAddress(request.to_address)))
    return std::unexpected(domain::ApiError::Validation("Netmail requires recipient name and FTN address"));
  std::string payload;
  for (auto field :
       {conference, std::string_view(request.to_name), std::string_view(request.to_address),
        std::string_view(request.subject), std::string_view(request.body), std::string_view(request.in_reply_to)}) {
    payload += std::to_string(field.size());
    payload += ':';
    payload += field;
  }
  if (uue) {
    payload += "UUE1:";
    for (const auto& field : {uue->kludge, uue->msgid, uue->generation, uue->from_name, uue->from_address, uue->to_name,
                              uue->to_address, std::to_string(uue->freeze_recipient)})
      payload += std::to_string(field.size()) + ":" + field;
  }
  auto hashed = Sha256(payload);
  if (!hashed)
    return std::unexpected(hashed.error());
  const auto& hash = *hashed;
  auto existing = metadata_->FindOperation(user, request.operation_id);
  if (!existing)
    return std::unexpected(existing.error());
  auto check = [&](const storage::Operation& previous) -> std::expected<void, domain::ApiError> {
    if (previous.payload_hash != hash || previous.conference != conference)
      return std::unexpected(
          domain::ApiError{domain::ErrorCode::kConflict, "Operation ID already has another payload", {}});
    if (previous.state == storage::OperationState::kQuarantine)
      return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "Message base is quarantined", {}});
    return {};
  };
  auto response = [](const storage::Operation& operation) {
    domain::CreateMessageResponse result;
    result.id = operation.generation + "#" + std::to_string(operation.plan.number);
    result.ftn_message_id = operation.ftn_msgid;
    return result;
  };
  if (*existing) {
    auto checked = check(**existing);
    if (!checked)
      return std::unexpected(checked.error());
    if ((*existing)->state == storage::OperationState::kCommitted)
      return response(**existing);
    if ((*existing)->state == storage::OperationState::kPending) {
      auto recovery = writer_.Recover(*catalog_, **existing, RequestDeadline());
      if (!recovery)
        return std::unexpected(recovery.error());
    }
  }
  auto access =
      storage::JamAccess::Open(*catalog_, conference, true, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  if (uue && uue->generation != (*access)->generation())
    return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "UUE base generation changed", {}});
  existing = metadata_->FindOperation(user, request.operation_id);
  if (!existing)
    return std::unexpected(existing.error());
  if (*existing) {
    auto checked = check(**existing);
    if (!checked)
      return std::unexpected(checked.error());
    if ((*existing)->state == storage::OperationState::kCommitted)
      return response(**existing);
    if ((*existing)->state != storage::OperationState::kRolledBack)
      return std::unexpected(domain::ApiError{domain::ErrorCode::kUnavailable, "Operation requires recovery", {}});
  }
  msgapi::JamMessage message;
  message.SetSenderName(profile->name);
  message.SetOriginAddress(profile->address);
  message.SetReceiverName(request.to_name.empty() ? "All" : request.to_name);
  message.SetDestAddress(request.to_address);
  message.SetSubject(request.subject);
  if (!request.in_reply_to.empty()) {
    auto parent_number = MessageNumber(**access, request.in_reply_to);
    if (!parent_number)
      return std::unexpected(parent_number.error());
    auto parent = (*access)->messages().ReadMessage(*parent_number);
    if (!parent)
      return std::unexpected(domain::ApiError::NotFound("Reply parent not found"));
    auto parent_address = OriginAddress(*parent);
    auto parent_name = parent->sender_name();
    if (!area.mailbox_address.empty()) {
      auto direction = metadata_->MailDirection({conference, (*access)->generation(), std::to_string(*parent_number)});
      if (!direction)
        return std::unexpected(direction.error());
      if (*direction == 2) {
        parent_address = parent->dest_address();
        parent_name = parent->receiver_name();
      } else if (*direction != 1)
        return std::unexpected(domain::ApiError::Validation("Reply parent has no confirmed mailbox provenance"));
      if (!request.to_address.empty()) {
        if (!ValidFtnAddress(request.to_address) || request.to_name.empty())
          return std::unexpected(domain::ApiError::Validation("Invalid explicit recipient"));
        parent_address = request.to_address;
        parent_name = request.to_name;
      }
    }
    if (parent->msg_id().empty() || !ValidFtnAddress(parent_address))
      return std::unexpected(domain::ApiError::Validation("Reply parent has no valid FTN identity"));
    message.SetReceiverName(parent_name);
    message.SetDestAddress(parent_address);
    message.SetReplyId(parent->msg_id());
    message.SetReplyLinks(*parent_number, 0, 0);
  }
  if (uue && uue->freeze_recipient &&
      (message.receiver_name() != uue->to_name || message.dest_address() != uue->to_address))
    return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "UUE reply recipient changed", {}});
  const auto resolved_to_name = message.receiver_name(), resolved_to_address = message.dest_address();
  std::string body;
  body.reserve(request.body.size() + 128);
  for (size_t i = 0; i < request.body.size(); ++i) {
    if (request.body[i] == '\r') {
      body += '\r';
      if (i + 1 < request.body.size() && request.body[i + 1] == '\n')
        ++i;
    } else
      body += request.body[i] == '\n' ? '\r' : request.body[i];
  }
  if (!body.empty() && body.back() != '\r')
    body += '\r';
  if (kind == AreaKind::kEcho)
    body += "--- FFIDO\r * Origin: FFIDO (" + profile->address + ")\r";
  message.SetText(body);
  message.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "PID: FFIDO gRPC");
  if (uue)
    message.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, uue->kludge);
  message.SetAttribute(msgapi::JamMessageAttribute::kLocal, true);
  message.SetAttribute(kind == AreaKind::kNetmail ? msgapi::JamMessageAttribute::kTypeNet
                       : kind == AreaKind::kLocal ? msgapi::JamMessageAttribute::kTypeLocal
                                                  : msgapi::JamMessageAttribute::kTypeEcho,
                       true);
  if (kind == AreaKind::kNetmail)
    message.SetAttribute(msgapi::JamMessageAttribute::kPrivate, true);
  storage::Operation operation;
  operation.user = user;
  operation.id = request.operation_id;
  operation.conference = conference;
  operation.generation = (*access)->generation();
  operation.payload_hash = hash;
  if (uue)
    operation.ftn_msgid = uue->msgid;
  else if (*existing)
    operation.ftn_msgid = (*existing)->ftn_msgid;
  else {
    std::array<unsigned char, 4> serial{};
    if (RAND_bytes(serial.data(), serial.size()) != 1)
      return std::unexpected(domain::ApiError::Server("Message identity generation failed"));
    constexpr char hex[] = "0123456789abcdef";
    operation.ftn_msgid = profile->address + " ";
    for (auto byte : serial) {
      operation.ftn_msgid += hex[byte >> 4];
      operation.ftn_msgid += hex[byte & 15];
    }
  }
  message.SetMsgId(operation.ftn_msgid);
  // Normalize the completed fields, including trusted profile and reply names.
  message.SetText(NormalizeOutgoingText(message.text()));
  message.SetSubject(NormalizeOutgoingText(message.subject()));
  message.SetSenderName(NormalizeOutgoingText(message.sender_name()));
  message.SetReceiverName(NormalizeOutgoingText(message.receiver_name()));
  auto plan = (*access)->messages().PrepareAppend(message);
  if (!plan)
    return std::unexpected(
        domain::ApiError::Validation("Message cannot be represented in configured JAM encoding or limits"));
  operation.plan = std::move(*plan);
  if (!area.mailbox_address.empty()) {
    operation.mail_direction = 2;
    operation.recipient = message.dest_address();
  }
  if (validate_only) {
    domain::CreateMessageResponse result;
    result.wire_body_bytes = operation.plan.text.size();
    result.status = "validated";
    result.resolved_to_name = resolved_to_name;
    result.resolved_to_address = resolved_to_address;
    return result;
  }
  auto appended = writer_.Append(**access, operation);
  if (!appended) {
    auto concurrent = metadata_->FindOperation(user, request.operation_id);
    if (concurrent && *concurrent && (*concurrent)->state == storage::OperationState::kCommitted &&
        (*concurrent)->payload_hash == hash)
      return response(**concurrent);
    return std::unexpected(appended.error());
  }
  return response(operation);
}
std::expected<domain::ThreadListResponse, domain::ApiError> MessageService::GetThread(
    std::string_view conference, std::string_view id, std::string_view user, const domain::PaginationRequest& page) {
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  if (!ValidPage(page))
    return std::unexpected(domain::ApiError::Validation("Invalid page"));
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto selected = MessageNumber(**access, id);
  if (!selected)
    return std::unexpected(selected.error());
  auto numbers = (*access)->messages().GetMessageNumbers();
  if (!numbers)
    return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
  if (numbers->size() > 100000)
    return std::unexpected(
        domain::ApiError{domain::ErrorCode::kResource, "Thread index exceeds request resource limit", {}});
  std::map<uint32_t, uint32_t> parents;
  std::map<uint32_t, std::vector<uint32_t>> children;
  std::map<uint32_t, msgapi::JamMessageHeader> headers;
  std::map<uint32_t, std::vector<uint32_t>> msgid_crc;
  for (auto number : *numbers) {
    auto header = (*access)->messages().GetHeader(number);
    if (!header)
      return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
    headers[number] = *header;
    msgid_crc[header->msgid_crc].push_back(number);
  }
  for (auto number : *numbers) {
    const auto& header = headers.at(number);
    uint32_t parent = header.reply_to;
    if ((!headers.contains(parent) || parent == 0) && header.reply_crc != UINT32_MAX &&
        msgid_crc.contains(header.reply_crc)) {
      auto message = (*access)->messages().ReadMessage(number, false);
      if (!message)
        return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
      uint32_t matched = 0;
      bool ambiguous = false;
      for (auto candidate_number : msgid_crc.at(header.reply_crc)) {
        auto candidate = (*access)->messages().ReadMessage(candidate_number, false);
        if (!candidate)
          return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
        if (!message->reply_id().empty() && candidate->msg_id() == message->reply_id()) {
          if (matched != 0)
            ambiguous = true;
          matched = candidate_number;
        }
      }
      if (!ambiguous && matched != 0)
        parent = matched;
    }
    parents[number] = parent;
    children[parent].push_back(number);
  }
  if (!parents.contains(*selected))
    return std::unexpected(domain::ApiError::NotFound("Thread message not found"));
  uint32_t root = *selected;
  std::set<uint32_t> ancestors;
  while (parents.contains(root) && parents[root] != 0 && parents.contains(parents[root])) {
    if (!ancestors.insert(root).second) {
      root = *ancestors.begin();
      break;
    }
    root = parents[root];
  }
  std::set<uint32_t> visited{root};
  std::vector<uint32_t> pending{root};
  for (size_t i = 0; i < pending.size(); ++i)
    for (auto child : children[pending[i]])
      if (visited.insert(child).second)
        pending.push_back(child);
  domain::ThreadListResponse result;
  result.total = static_cast<int64_t>(pending.size());
  const auto start = std::min<uint64_t>(page.offset, pending.size()),
             end = std::min<uint64_t>(start + page.limit, pending.size());
  size_t response_bytes = 0;
  for (auto i = start; i < end; ++i) {
    auto detail = Detail(**access, conference, pending[i], user);
    if (!detail)
      return std::unexpected(detail.error());
    response_bytes +=
        detail->body.size() + detail->subject.size() + detail->from_name.size() + detail->to_name.size() + 512;
    if (response_bytes > 3 * 1024 * 1024)
      return std::unexpected(
          domain::ApiError{domain::ErrorCode::kResource, "Thread page exceeds response resource limit", {}});
    if (parents.contains(pending[i]) && parents.contains(parents.at(pending[i])))
      detail->in_reply_to = MessageId(**access, parents.at(pending[i]));
    detail->thread_id = MessageId(**access, root);
    result.messages.push_back(std::move(*detail));
  }
  result.has_more = end < pending.size();
  return result;
}
}  // namespace fidoback::service
