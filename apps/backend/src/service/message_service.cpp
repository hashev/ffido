#include "service/message_service.hpp"

#include <openssl/rand.h>

#include <algorithm>
#include <compare>
#include <mutex>
#include <nlohmann/json.hpp>
#include <regex>
#include <set>

#include "domain/ftn_address.hpp"
#include "ftn/uue_metadata.hpp"
#include "service/auth_service.hpp"
#include "service/crypto.hpp"
#include "service/jam_mapping.hpp"
#include "service/message_search.hpp"
#include "service/personal_filters.hpp"
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

std::expected<void, domain::ApiError> ValidateFooter(const domain::CreateMessageRequest& request,
                                                     std::string_view encoding) {
  if (request.footer) {
    for (const auto& [name, text] :
         {std::pair{"tagline", &request.footer->tagline}, std::pair{"origin", &request.footer->origin}}) {
      if (text->empty() || text->size() > 256 || !storage::ConvertText(*text, "UTF-8", "UTF-8") ||
          std::any_of(text->begin(), text->end(), [](unsigned char c) { return c < 32 || c == 127; }))
        return std::unexpected(domain::ApiError::Validation(
            std::vector<domain::ErrorDetail>{{name, "Use a single line of 1-256 UTF-8 bytes without controls"}}));
      if (!storage::ConvertText(NormalizeOutgoingText(*text), "UTF-8", encoding))
        return std::unexpected(domain::ApiError::Validation(
            std::vector<domain::ErrorDetail>{{name, "Footer cannot be represented in configured JAM encoding"}}));
    }
  }
  return {};
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
  auto candidate = std::string_view(id).substr(0, separator);
  if (const auto at = candidate.find('@'); at != std::string_view::npos) {
    const auto domain = candidate.substr(at + 1);
    const auto alnum = [](unsigned char c) {
      return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
    };
    if (domain.empty() || domain.size() > 255 || !alnum(domain.front()) || !alnum(domain.back()) ||
        !std::all_of(domain.begin(), domain.end(), [&](unsigned char c) { return alnum(c) || c == '-' || c == '.'; }))
      return {};
    candidate = candidate.substr(0, at);
  }
  const auto canonical = domain::CanonicalFtnAddress(candidate);
  return canonical ? *canonical : std::string{};
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
                                                                              uint32_t number, std::string_view user,
                                                                              bool body) {
  auto message = access.messages().ReadMessage(number, body);
  if (!message) {
    if (message.error() == msgapi::JamError::kInvalidMessageNumber ||
        message.error() == msgapi::JamError::kMessageDeleted)
      return std::unexpected(domain::ApiError::NotFound("Message not found"));
    return std::unexpected(JamError(storage::JamAccessError{message.error()}));
  }
  const auto key_number = std::to_string(number);
  auto read = metadata_->IsMessageRead(user, {conference, access.generation(), key_number});
  if (!read)
    return std::unexpected(read.error());
  domain::MessageDetail result;
  result.id = MessageId(access, number);
  result.effective_encoding = *access.messages().EffectiveEncoding(*message);
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
std::expected<domain::ArchiveMessage, domain::ApiError> MessageService::ReadArchiveMessage(
    std::string_view conference, std::string_view id, std::string_view user, uint64_t body_offset, uint32_t body_limit,
    bool reveal) {
  RequestBudget budget{std::min(RequestDeadline(), std::chrono::steady_clock::now() + std::chrono::seconds(5)),
                       RequestCancellation()};
  RequestScope scope(budget);
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(RequestActive() ? permission.error() : SearchInterrupted());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  if (body_limit == 0 || body_limit > 65536)
    return std::unexpected(domain::ApiError::Validation("Body limit must be between 1 and 65536"));
  auto filters = metadata_->GetPersonalFilters(user);
  if (!filters)
    return std::unexpected(RequestActive() ? filters.error() : SearchInterrupted());
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(RequestActive() ? JamError(access.error()) : SearchInterrupted());
  auto number = MessageNumber(**access, id);
  if (!number)
    return std::unexpected(number.error());
  auto detail = FilteredDetail(**access, conference, *number, user, &*filters);
  if (!detail)
    return std::unexpected(RequestActive() ? detail.error() : SearchInterrupted());
  domain::ArchiveMessage result;
  result.collapsed = !reveal && !detail->personal_collapse->rules.empty();
  if (result.collapsed) {
    detail->ftn_kludges.clear();
    if (body_offset != 0)
      return std::unexpected(domain::ApiError::Validation("Collapsed message has no body offset"));
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    result.message = std::move(*detail);
    result.complete = true;
    return result;
  }
  if (reveal && !detail->personal_collapse->rules.empty()) {
    auto collapse = std::move(detail->personal_collapse);
    detail = Detail(**access, conference, *number, user);
    if (!detail)
      return std::unexpected(RequestActive() ? detail.error() : SearchInterrupted());
    detail->personal_collapse = std::move(collapse);
  }
  const auto& text = detail->body;
  const auto continuation = [&](size_t offset) {
    return offset < text.size() && (static_cast<unsigned char>(text[offset]) & 0xc0) == 0x80;
  };
  if (body_offset > text.size() || continuation(static_cast<size_t>(body_offset)))
    return std::unexpected(domain::ApiError::Validation("Body offset is not a UTF-8 boundary"));
  auto end = std::min<uint64_t>(text.size(), body_offset + body_limit);
  while (end > body_offset && continuation(static_cast<size_t>(end)))
    --end;
  if (end == body_offset && end < text.size())
    return std::unexpected(domain::ApiError::Validation("Body limit cannot hold the next UTF-8 character"));
  result.body_offset = body_offset;
  result.next_offset = end;
  result.complete = end == text.size();
  detail->body = text.substr(static_cast<size_t>(body_offset), static_cast<size_t>(end - body_offset));
  if (!RequestActive())
    return std::unexpected(SearchInterrupted());
  result.message = std::move(*detail);
  return result;
}
std::expected<domain::ThreadListResponse, domain::ApiError> MessageService::GetArchiveThread(
    std::string_view conference, std::string_view id, std::string_view user, const domain::PaginationRequest& page) {
  RequestBudget budget{std::min(RequestDeadline(), std::chrono::steady_clock::now() + std::chrono::seconds(5)),
                       RequestCancellation()};
  RequestScope scope(budget);
  auto result = GetThread(conference, id, user, page, true, true);
  if (!RequestActive())
    return std::unexpected(SearchInterrupted());
  return result;
}

std::expected<domain::MessageTechnicalData, domain::ApiError> MessageService::GetMessageTechnicalData(
    std::string_view conference, std::string_view id, std::string_view user) {
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
  auto raw = (*access)->messages().ReadRawMetadata(*number);
  if (!raw)
    return std::unexpected(JamError(raw.error()));
  domain::MessageTechnicalData result;
  result.conference = conference;
  result.id = MessageId(**access, *number);
  result.attributes = raw->attributes();
  result.attributes2 = raw->attributes2();
  for (const auto& field : raw->subfields()) {
    const auto low = static_cast<uint32_t>(field.type());
    if (low == 4 || low == 5 || low == 2000)
      result.subfields.push_back({low, field.high_id(), field.ToString()});
  }
  auto encoding = (*access)->messages().EffectiveEncoding(*raw);
  if (encoding && storage::ConvertText("", *encoding, "UTF-8"))
    result.effective_encoding = *encoding;
  if (!RequestActive())
    return std::unexpected(domain::ApiError{
        RequestCancellation().stop_requested() ? domain::ErrorCode::kCancelled : domain::ErrorCode::kDeadline,
        "Request interrupted",
        {}});
  return result;
}

std::expected<domain::PersonalMessageFilterSet, domain::ApiError> MessageService::GetPersonalFilters(
    std::string_view user) {
  return metadata_->GetPersonalFilters(user);
}
std::expected<uint64_t, domain::ApiError> MessageService::ReplacePersonalFilters(
    std::string_view user, uint64_t expected, std::string_view operation,
    std::vector<domain::PersonalMessageFilter> rules) {
  if (rules.size() > 200 || operation.empty() || operation.size() > 128)
    return std::unexpected(domain::ApiError::Validation("Invalid personal filters"));
  auto previous = metadata_->GetPersonalFilters(user);
  if (!previous)
    return std::unexpected(previous.error());
  std::set<std::string> ids;
  static const std::regex uuid("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
  for (auto& r : rules) {
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    for (auto* value : {&r.author, &r.address, &r.subject}) {
      auto trimmed = TrimPersonalFilterText(*value);
      if (!trimmed)
        return std::unexpected(trimmed.error());
    }
    for (auto& c : r.id)
      if (c >= 'A' && c <= 'F')
        c += 'a' - 'A';
    if (!std::regex_match(r.id, uuid) || !ids.insert(r.id).second || (r.scope != 1 && r.scope != 2) ||
        (r.scope == 1 && !r.conference.empty()) || r.conference.size() > 1024 || r.author.size() > 256 ||
        r.subject.size() > 256 || r.address.size() > 64 ||
        (r.author.empty() && r.address.empty() && r.subject.empty()) ||
        !storage::ConvertText(r.author, "UTF-8", "UTF-8") || !storage::ConvertText(r.subject, "UTF-8", "UTF-8"))
      return std::unexpected(domain::ApiError::Validation("Invalid personal filter rule"));
    if (!r.address.empty()) {
      auto address = domain::CanonicalFtnAddress(r.address);
      if (!address)
        return std::unexpected(address.error());
      r.address = *address;
    }
    if (r.scope == 2) {
      auto permission = access_->Permissions(*metadata_, user, r.conference);
      auto area = catalog_->areas().find(r.conference);
      const bool readable = permission && permission->read && area != catalog_->areas().end() &&
                            area->second.config.kind == AreaKind::kEcho && area->second.config.msgbase_type == "JAM";
      const bool existing = std::ranges::any_of(previous->rules, [&](const auto& old) {
        return old.id == r.id && old.scope == r.scope && old.conference == r.conference && (!r.enabled || old == r);
      });
      if (!readable && !existing)
        return std::unexpected(EchoAccess::Denied());
    }
  }
  return metadata_->ReplacePersonalFilters(user, expected, operation, rules, RequestActive);
}
std::expected<domain::MessageDetail, domain::ApiError> MessageService::FilteredDetail(
    storage::JamAccess& access, std::string_view conference, uint32_t number, std::string_view user,
    const domain::PersonalMessageFilterSet* filters, bool body) {
  auto result = Detail(access, conference, number, user, body && filters == nullptr);
  if (!result || !filters)
    return result;
  const bool echo = catalog_->areas().find(conference)->second.config.kind == AreaKind::kEcho;
  auto matched =
      MatchPersonalFilters(*filters, conference, echo, result->from_name, result->from_address, result->subject);
  if (!matched)
    return std::unexpected(matched.error());
  if (matched->empty() && body) {
    result = Detail(access, conference, number, user);
    if (!result)
      return result;
  }
  result->personal_collapse = domain::PersonalMessageCollapse{filters->revision, *matched};
  return result;
}
std::expected<domain::MessagePresentation, domain::ApiError> MessageService::GetPresentation(
    std::string_view conference, std::string_view id, std::string_view user, bool reveal, std::string_view query,
    int scope) {
  if ((!query.empty() &&
       (query.size() > 256 || !storage::ConvertText(query, "UTF-8", "UTF-8") || (scope != 1 && scope != 2))) ||
      (query.empty() && scope != 0))
    return std::unexpected(domain::ApiError::Validation("Invalid search context"));
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  auto filters = metadata_->GetPersonalFilters(user);
  if (!filters)
    return std::unexpected(filters.error());
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto number = MessageNumber(**access, id);
  if (!number)
    return std::unexpected(number.error());
  auto detail = FilteredDetail(**access, conference, *number, user, &*filters);
  if (!detail)
    return std::unexpected(detail.error());
  domain::MessagePresentation result;
  result.revision = filters->revision;
  result.rules = detail->personal_collapse->rules;
  result.collapsed = !reveal && !result.rules.empty();
  if (!result.collapsed) {
    if (reveal && !result.rules.empty())
      detail = Detail(**access, conference, *number, user);
    if (!detail)
      return std::unexpected(detail.error());
    if (!query.empty()) {
      const std::array<std::string_view, 6> values{detail->from_name,  detail->from_address, detail->to_name,
                                                   detail->to_address, detail->subject,      detail->body};
      for (int f = 0; f < (scope == 1 ? 5 : 6); ++f) {
        auto ranges = SearchRanges(values[f], query, SearchCp866(detail->effective_encoding), f + 1);
        if (!ranges)
          return std::unexpected(ranges.error());
        result.matches.insert(result.matches.end(), ranges->begin(), ranges->end());
      }
    }
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    auto marked = RecordView(**access, conference, *number, user, *detail);
    if (!marked)
      return std::unexpected(marked.error());
  }
  result.message = std::move(*detail);
  return result;
}

std::expected<domain::MessageListResponse, domain::ApiError> MessageService::GetMessages(
    std::string_view conference, const domain::PaginationRequest& page, std::string_view sort, std::string_view user,
    std::string_view query, std::string_view anchor_message_id, bool respect_filters) {
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  if (!ValidPage(page) || (sort != "newest" && sort != "oldest"))
    return std::unexpected(domain::ApiError::Validation("Invalid page or sort"));
  auto filters =
      respect_filters
          ? metadata_->GetPersonalFilters(user)
          : std::expected<domain::PersonalMessageFilterSet, domain::ApiError>{domain::PersonalMessageFilterSet{}};
  if (!filters)
    return std::unexpected(filters.error());
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
        return std::unexpected(JamError(storage::JamAccessError{message.error()}));
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
    auto header = (*access)->messages().GetHeader(numbers->at(i));
    if (!header)
      return std::unexpected(JamError(storage::JamAccessError{header.error()}));
    auto detail = FilteredDetail(**access, conference, numbers->at(i), user, respect_filters ? &*filters : nullptr,
                                 header->txt_len <= msgapi::jam_wire::kMaxReadBody);
    if (!detail)
      return std::unexpected(detail.error());
    auto preview = storage::Utf8Preview(detail->body, 200);
    if (!preview)
      return std::unexpected(domain::ApiError::Server("Invalid message text"));
    domain::MessageSummary summary;
    summary.personal_collapse = detail->personal_collapse;
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
  auto marked = RecordView(**access, conference, *number, user, *result);
  if (!marked)
    return std::unexpected(marked.error());
  return result;
}
std::expected<void, domain::ApiError> MessageService::RecordView(storage::JamAccess& access,
                                                                 std::string_view conference, uint32_t number,
                                                                 std::string_view user, domain::MessageDetail& detail) {
  const auto key = std::to_string(number);
  auto marked = metadata_->RecordMessageView(user, {conference, access.generation(), key});
  if (!marked)
    return std::unexpected(marked.error());
  detail.is_read = true;
  detail.position_revision = marked->revision;
  return {};
}
std::expected<domain::FindMessageResponse, domain::ApiError> MessageService::FindMessage(
    std::string_view conference, std::string_view query, int scope, std::string_view sort, std::string_view start,
    bool include_start, std::string_view user, bool respect_filters) {
  // Trim the same whitespace as the client; the query itself remains literal.
  auto folded = FoldSearch(query, false);
  if (!folded)
    return std::unexpected(folded.error());
  const auto whitespace = [](char32_t c) {
    return (c >= 9 && c <= 13) || c == 32 || c == 0x85 || c == 0xa0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200a) ||
           c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f || c == 0x3000 || c == 0xfeff;
  };
  // Trim at scalar boundaries without splitting UTF-8 characters.
  size_t first = 0, last = folded->folded.size();
  while (first < last && whitespace(folded->folded[first]))
    ++first;
  while (last > first && whitespace(folded->folded[last - 1]))
    --last;
  size_t scalar = 0, begin_byte = query.size(), end_byte = query.size();
  for (size_t i = 0; i < query.size(); ++i) {
    if ((static_cast<unsigned char>(query[i]) & 0xc0) == 0x80)
      continue;
    if (scalar == first)
      begin_byte = i;
    if (scalar == last)
      end_byte = i;
    ++scalar;
  }
  query = query.substr(begin_byte, end_byte - begin_byte);
  if (query.empty() || query.size() > 256 || (scope != 1 && scope != 2) || (sort != "newest" && sort != "oldest"))
    return std::unexpected(domain::ApiError::Validation("Invalid search parameters"));
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  auto filters =
      respect_filters
          ? metadata_->GetPersonalFilters(user)
          : std::expected<domain::PersonalMessageFilterSet, domain::ApiError>{domain::PersonalMessageFilterSet{}};
  if (!filters)
    return std::unexpected(filters.error());
  auto access =
      storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto numbers = (*access)->messages().GetMessageNumbers();
  if (!numbers) {
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    return std::unexpected(domain::ApiError::Server("Cannot list search messages"));
  }
  std::vector<std::pair<uint32_t, uint32_t>> ordered;
  for (auto number : *numbers) {
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    auto header = (*access)->messages().GetHeader(number);
    if (!header)
      return std::unexpected(domain::ApiError::Server("Cannot read search header"));
    ordered.emplace_back(header->date_written, number);
  }
  std::sort(ordered.begin(), ordered.end());
  if (sort == "newest")
    std::reverse(ordered.begin(), ordered.end());
  size_t begin = 0;
  if (!start.empty()) {
    auto number = MessageNumber(**access, start);
    if (!number)
      return std::unexpected(number.error());
    const auto found = std::find_if(ordered.begin(), ordered.end(), [&](auto row) { return row.second == *number; });
    if (found == ordered.end())
      return std::unexpected(domain::ApiError::NotFound("Search anchor unavailable"));
    begin = static_cast<size_t>(found - ordered.begin()) + (include_start ? 0 : 1);
  }
  for (size_t i = begin; i < ordered.size(); ++i) {
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    const auto number = ordered[i].second;
    auto detail = Detail(**access, conference, number, user);
    if (!detail) {
      if (!RequestActive())
        return std::unexpected(SearchInterrupted());
      return std::unexpected(detail.error());
    }
    domain::FindMessageResponse result;
    const std::array<std::string_view, 6> fields{detail->from_name,  detail->from_address, detail->to_name,
                                                 detail->to_address, detail->subject,      detail->body};
    for (size_t f = 0; f < (scope == 1 ? 5u : 6u); ++f) {
      auto ranges = SearchRanges(fields[f], query, SearchCp866(detail->effective_encoding), static_cast<int>(f + 1));
      if (!ranges)
        return std::unexpected(ranges.error());
      result.matches.insert(result.matches.end(), ranges->begin(), ranges->end());
    }
    if (result.matches.empty())
      continue;
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    if (respect_filters) {
      const bool echo = catalog_->areas().find(conference)->second.config.kind == AreaKind::kEcho;
      auto matched =
          MatchPersonalFilters(*filters, conference, echo, detail->from_name, detail->from_address, detail->subject);
      if (!matched)
        return std::unexpected(matched.error());
      detail->personal_collapse = domain::PersonalMessageCollapse{filters->revision, *matched};
      if (!matched->empty()) {
        detail->body.clear();
        detail->attachments.clear();
        detail->ftn_kludges.clear();
        result.matches.clear();
        result.message = std::move(*detail);
        return result;
      }
    }
    auto marked = RecordView(**access, conference, number, user, *detail);
    if (!marked)
      return std::unexpected(marked.error());
    result.message = std::move(*detail);
    return result;
  }
  if (!RequestActive())
    return std::unexpected(SearchInterrupted());
  return domain::FindMessageResponse{};
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
std::expected<void, domain::ApiError> MessageService::MarkAsUnread(std::string_view conference, std::string_view id,
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
  return metadata_->MarkMessageUnread(user, {conference, (*access)->generation(), key_number});
}
std::expected<domain::CreateMessageResponse, domain::ApiError> MessageService::CreateMessage(
    std::string_view conference, const domain::CreateMessageRequest& request, std::string_view user,
    const UuePublishOptions* uue, bool validate_only, const CrosspostPublishOptions* crosspost) {
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
      (!crosspost && request.operation_id.find_first_not_of(
                         "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") != std::string::npos) ||
      request.in_reply_to.size() > 256 || request.subject.find_first_of("\r\n") != std::string::npos ||
      request.to_name.find_first_of("\r\n") != std::string::npos || !safe(request.subject, 256, true) ||
      !safe(request.body, msgapi::jam_wire::kMaxBody - 256, true) || !safe(request.to_name, 256, false) ||
      (!request.to_address.empty() && !ValidFtnAddress(request.to_address)))
    return std::unexpected(domain::ApiError::Validation("Invalid operation, recipient, subject or body"));
  if (auto footer = ValidateFooter(request, encoding_); !footer)
    return std::unexpected(footer.error());
  auto profile = metadata_->GetProfile(user);
  if (!profile)
    return std::unexpected(profile.error());
  if (crosspost)
    *profile = crosspost->profile;
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
  if (crosspost) {
    for (const auto& field : {crosspost->profile.name, crosspost->profile.address, crosspost->generation,
                              crosspost->msgid, crosspost->to_name, crosspost->to_address})
      payload += std::to_string(field.size()) + ":" + field;
  }
  if (request.footer) {
    payload += "FOOTER1:";
    for (const auto& text : {request.footer->tagline, request.footer->origin})
      payload += std::to_string(text.size()) + ":" + text;
  }
  if (!request.expected_preview_digest.empty())
    payload += "PREVIEW1:" + request.expected_preview_digest;
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
    if (validate_only && !uue && !crosspost)
      return std::unexpected(domain::ApiError{domain::ErrorCode::kConflict, "Preview requires a new operation ID", {}});
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
  if (crosspost && crosspost->generation != (*access)->generation())
    return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "Crosspost base generation changed", {}});
  if (uue && uue->generation != (*access)->generation())
    return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "UUE base generation changed", {}});
  existing = metadata_->FindOperation(user, request.operation_id);
  if (!existing)
    return std::unexpected(existing.error());
  if (*existing) {
    if (validate_only && !uue && !crosspost)
      return std::unexpected(domain::ApiError{domain::ErrorCode::kConflict, "Preview requires a new operation ID", {}});
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
    if (!parent) {
      if (parent.error() == msgapi::JamError::kResourceLimit)
        return std::unexpected(JamError(storage::JamAccessError{parent.error()}));
      return std::unexpected(domain::ApiError::NotFound("Reply parent not found"));
    }
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
  if (crosspost) {
    message.SetReceiverName(crosspost->to_name);
    message.SetDestAddress(crosspost->to_address);
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
  if (kind == AreaKind::kEcho) {
    const auto tagline = request.footer ? request.footer->tagline : "FFIDO";
    const auto origin = request.footer ? request.footer->origin : "FFIDO";
    body += "--- " + tagline + "\r * Origin: " + origin + " (" + profile->address + ")\r";
  }
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
  if (crosspost)
    operation.ftn_msgid = crosspost->msgid;
  else if (uue)
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
  std::optional<domain::MessagePreview> preview;
  if (validate_only || !request.expected_preview_digest.empty()) {
    domain::MessagePreview value;
    value.conference = conference;
    value.from_name = message.sender_name();
    value.from_address = message.origin_address();
    value.to_name = message.receiver_name();
    value.to_address = message.dest_address();
    value.subject = message.subject();
    value.in_reply_to = request.in_reply_to;
    auto encoding = (*access)->messages().EffectiveEncoding(message);
    if (!encoding)
      return std::unexpected(domain::ApiError::Validation("Invalid publication encoding"));
    value.encoding = *encoding;
    auto decoded = storage::ConvertText(operation.plan.text, value.encoding, "UTF-8");
    if (!decoded)
      return std::unexpected(domain::ApiError::Validation("Invalid publication encoding"));
    value.body = DisplayText(*decoded);
    value.wire_body_bytes = operation.plan.text.size();
    value.kind = static_cast<int>(kind);
    value.public_message = kind == AreaKind::kEcho;
    const auto reply_id = message.reply_id();
    std::string canonical = "FFIDO-PREVIEW-1:";
    for (const std::string_view part :
         {user, conference, std::string_view(operation.generation), std::string_view(value.from_name),
          std::string_view(value.from_address), std::string_view(value.to_name), std::string_view(value.to_address),
          std::string_view(value.subject), std::string_view(operation.plan.text), std::string_view(value.encoding),
          std::string_view(value.in_reply_to), std::string_view(reply_id)})
      canonical += std::to_string(part.size()) + ":" + std::string(part);
    canonical += std::to_string(value.kind);
    auto digest = Sha256(canonical);
    if (!digest)
      return std::unexpected(digest.error());
    constexpr char hex[] = "0123456789abcdef";
    for (auto byte : *digest) {
      value.digest += hex[byte >> 4];
      value.digest += hex[byte & 15];
    }
    if (!request.expected_preview_digest.empty() && request.expected_preview_digest != value.digest)
      return std::unexpected(
          domain::ApiError{domain::ErrorCode::kPrecondition, "Publication preview changed; prepare again", {}});
    preview = std::move(value);
  }
  if (validate_only) {
    domain::CreateMessageResponse result;
    result.wire_body_bytes = operation.plan.text.size();
    result.status = "validated";
    result.preview = std::move(preview);
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
std::expected<domain::CreateCrosspostResponse, domain::ApiError> MessageService::CreateCrosspost(
    std::string_view conference, const domain::CreateMessageRequest& request, std::vector<std::string> additional,
    std::string_view user) {
  using Json = nlohmann::json;
  using domain::ApiError;
  if (request.operation_id.empty() || request.operation_id.size() > 128 ||
      request.operation_id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") !=
          std::string::npos ||
      additional.empty() || additional.size() > 20 || request.body.empty())
    return std::unexpected(ApiError::Validation("Invalid crosspost request or destination limit"));
  // Shared across service instances, but unrelated groups never share a send lock.
  static std::mutex registry_mutex;
  static std::map<std::string, std::weak_ptr<std::timed_mutex>> registry;
  std::shared_ptr<std::timed_mutex> send_mutex;
  {
    std::lock_guard guard(registry_mutex);
    std::erase_if(registry, [](const auto& item) { return item.second.expired(); });
    const auto key = std::to_string(user.size()) + ":" + std::string(user) + request.operation_id;
    send_mutex = registry[key].lock();
    if (!send_mutex)
      registry[key] = send_mutex = std::make_shared<std::timed_mutex>();
  }
  std::unique_lock lock(*send_mutex, std::defer_lock);
  if (!AcquireRequestLock(lock))
    return std::unexpected(
        ApiError{RequestCancellation().stop_requested() ? domain::ErrorCode::kCancelled : domain::ErrorCode::kDeadline,
                 "Crosspost operation busy",
                 {}});
  std::sort(additional.begin(), additional.end(), [](std::string_view a, std::string_view b) {
    auto fold = [](unsigned char c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : int(c); };
    const auto order = std::lexicographical_compare_three_way(
        a.begin(), a.end(), b.begin(), b.end(), [&](unsigned char x, unsigned char y) { return fold(x) <=> fold(y); });
    return order == 0 ? a < b : order < 0;
  });
  if (std::adjacent_find(additional.begin(), additional.end()) != additional.end() ||
      std::find(additional.begin(), additional.end(), conference) != additional.end())
    return std::unexpected(ApiError::Validation("Duplicate crosspost destination"));
  std::vector<std::string> areas{std::string(conference)};
  areas.insert(areas.end(), additional.begin(), additional.end());
  auto check_permissions = [&]() -> std::expected<void, ApiError> {
    for (const auto& id : areas) {
      auto permission = access_->Permissions(*metadata_, user, id);
      if (!permission)
        return std::unexpected(permission.error());
      if (!permission->post || (id == conference && !request.in_reply_to.empty() && !permission->read))
        return std::unexpected(EchoAccess::Denied());
      const auto area = catalog_->areas().find(id);
      if (area == catalog_->areas().end() || area->second.config.kind != AreaKind::kEcho)
        return std::unexpected(ApiError::Validation("Crosspost requires echo areas"));
    }
    return {};
  };
  auto allowed = check_permissions();
  if (!allowed)
    return std::unexpected(allowed.error());
  if (auto footer = ValidateFooter(request, encoding_); !footer)
    return std::unexpected(footer.error());
  // Hash the input, not mutable derived fields such as profile or display names.
  Json input = {std::string(conference), additional,   request.to_name,    request.to_address,
                request.subject,         request.body, request.in_reply_to};
  if (request.footer)
    input.push_back({{"tagline", request.footer->tagline}, {"origin", request.footer->origin}});
  auto hash = Sha256(input.dump());
  if (!hash)
    return std::unexpected(hash.error());
  std::string fingerprint;
  for (auto b : *hash) {
    fingerprint += "0123456789abcdef"[b >> 4];
    fingerprint += "0123456789abcdef"[b & 15];
  }
  auto stored = metadata_->GetCrosspost(user, request.operation_id);
  if (!stored)
    return std::unexpected(stored.error());
  Json manifest;
  if (*stored) {
    manifest = Json::parse(**stored, nullptr, false);
    if (manifest.is_discarded())
      return std::unexpected(ApiError::Server("Invalid crosspost manifest"));
    if (manifest.at("hash") != fingerprint)
      return std::unexpected(ApiError{domain::ErrorCode::kConflict, "Operation ID already has another payload", {}});
  } else {
    auto profile = metadata_->GetProfile(user);
    if (!profile)
      return std::unexpected(profile.error());
    std::string block = "* Originally in " + catalog_->areas().at(areas.front()).config.name + "\n";
    for (const auto& id : additional)
      block += "* Crossposted in " + catalog_->areas().at(id).config.name + "\n";
    manifest = {{"hash", fingerprint},
                {"from_name", profile->name},
                {"from_address", profile->address},
                {"to_name", request.to_name.empty() ? "All" : request.to_name},
                {"to_address", request.to_address},
                {"body", block + "\n" + request.body},
                {"copies", Json::array()}};
    if (request.footer)
      manifest["footer"] = {{"tagline", request.footer->tagline}, {"origin", request.footer->origin}};
    // Validate the parent and resolve its recipient using the same composer path.
    auto probe = request;
    std::array<unsigned char, 16> probe_nonce{};
    if (RAND_bytes(probe_nonce.data(), probe_nonce.size()) != 1)
      return std::unexpected(ApiError::Server("Validation identity generation failed"));
    probe.operation_id = "crosspost-validation-";
    for (auto b : probe_nonce) {
      probe.operation_id += "0123456789abcdef"[b >> 4];
      probe.operation_id += "0123456789abcdef"[b & 15];
    }
    probe.body = manifest.at("body").get<std::string>();
    auto validated = CreateMessage(conference, probe, user, nullptr, true);
    if (!validated)
      return std::unexpected(validated.error());
    manifest["to_name"] = validated->resolved_to_name;
    manifest["to_address"] = validated->resolved_to_address;
    std::array<unsigned char, 16> nonce{};
    if (RAND_bytes(nonce.data(), nonce.size()) != 1)
      return std::unexpected(ApiError::Server("Crosspost identity generation failed"));
    std::string token;
    for (auto b : nonce) {
      token += "0123456789abcdef"[b >> 4];
      token += "0123456789abcdef"[b & 15];
    }
    for (size_t i = 0; i < areas.size(); ++i) {
      auto opened =
          storage::JamAccess::Open(*catalog_, areas[i], false, RequestDeadline(), RequestCancellation(), encoding_);
      if (!opened)
        return std::unexpected(JamError(opened.error()));
      const auto generation = (*opened)->generation();
      opened->reset();
      std::array<unsigned char, 4> serial{};
      if (RAND_bytes(serial.data(), serial.size()) != 1)
        return std::unexpected(ApiError::Server("Message identity generation failed"));
      std::string msgid = profile->address + " ";
      for (auto b : serial) {
        msgid += "0123456789abcdef"[b >> 4];
        msgid += "0123456789abcdef"[b & 15];
      }
      manifest["copies"].push_back({{"area", areas[i]},
                                    {"generation", generation},
                                    {"key", "@crosspost-" + token + "-" + std::to_string(i)},
                                    {"msgid", msgid}});
    }
    // Prepare all encodings and complete envelopes before publishing any copy.
    for (size_t i = 0; i < areas.size(); ++i) {
      const auto& copy = manifest["copies"][i];
      CrosspostPublishOptions options{*profile, copy["generation"], copy["msgid"], manifest["to_name"],
                                      manifest["to_address"]};
      auto child = probe;
      child.operation_id = copy["key"];
      if (i)
        child.in_reply_to.clear();
      auto checked = CreateMessage(areas[i], child, user, nullptr, true, &options);
      if (!checked)
        return std::unexpected(checked.error());
    }
    auto prepared = metadata_->PrepareCrosspost(user, request.operation_id, manifest.dump());
    if (!prepared)
      return std::unexpected(prepared.error());
  }
  domain::CreateCrosspostResponse result;
  result.total = static_cast<int>(areas.size());
  for (size_t i = 0; i < areas.size(); ++i) {
    allowed = check_permissions();
    if (!allowed)
      return std::unexpected(allowed.error());
    const auto& copy = manifest.at("copies").at(i);
    const std::string generation = copy.at("generation"), key = copy.at("key");
    auto previous = metadata_->FindOperation(user, key);
    if (!previous)
      return std::unexpected(previous.error());
    if (*previous && (*previous)->state == storage::OperationState::kPending) {
      auto recovery = writer_.Recover(*catalog_, **previous, RequestDeadline());
      if (!recovery) {
        result.pending_code = 9;
        break;
      }
    }
    auto opened =
        storage::JamAccess::Open(*catalog_, areas[i], false, RequestDeadline(), RequestCancellation(), encoding_);
    if (!opened || (*opened)->generation() != generation) {
      result.pending_code = 9;  // FAILED_PRECONDITION: preserve previous confirmed copies.
      break;
    }
    opened->reset();
    domain::Profile profile;
    profile.name = manifest.at("from_name");
    profile.address = manifest.at("from_address");
    CrosspostPublishOptions options{profile, generation, copy.at("msgid"), manifest.at("to_name"),
                                    manifest.at("to_address")};
    auto child = request;
    if (manifest.contains("footer"))
      child.footer = domain::MessageFooter{manifest["footer"]["tagline"], manifest["footer"]["origin"]};
    else
      child.footer.reset();
    child.operation_id = key;
    child.body = manifest.at("body");
    if (i)
      child.in_reply_to.clear();
    auto sent = CreateMessage(areas[i], child, user, nullptr, false, &options);
    if (!sent) {
      if (sent.error().code == domain::ErrorCode::kForbidden)
        return std::unexpected(sent.error());
      result.pending_code = sent.error().code == domain::ErrorCode::kPrecondition ? 9 : 14;
      break;
    }
    result.saved.push_back({areas[i], sent->id, sent->ftn_message_id});
  }
  allowed = check_permissions();
  if (!allowed)
    return std::unexpected(allowed.error());
  result.complete = result.saved.size() == areas.size();
  return result;
}

std::expected<domain::ThreadListResponse, domain::ApiError> MessageService::GetThread(
    std::string_view conference, std::string_view id, std::string_view user, const domain::PaginationRequest& page,
    bool respect_filters, bool headers_only) {
  auto permission = access_->Permissions(*metadata_, user, conference);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read)
    return std::unexpected(EchoAccess::Denied());
  if (!ValidPage(page))
    return std::unexpected(domain::ApiError::Validation("Invalid page"));
  auto filters =
      respect_filters
          ? metadata_->GetPersonalFilters(user)
          : std::expected<domain::PersonalMessageFilterSet, domain::ApiError>{domain::PersonalMessageFilterSet{}};
  if (!filters)
    return std::unexpected(filters.error());
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
        return std::unexpected(JamError(storage::JamAccessError{message.error()}));
      uint32_t matched = 0;
      bool ambiguous = false;
      for (auto candidate_number : msgid_crc.at(header.reply_crc)) {
        auto candidate = (*access)->messages().ReadMessage(candidate_number, false);
        if (!candidate)
          return std::unexpected(JamError(storage::JamAccessError{candidate.error()}));
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
    auto detail =
        FilteredDetail(**access, conference, pending[i], user, respect_filters ? &*filters : nullptr, !headers_only);
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
