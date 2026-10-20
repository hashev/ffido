#include "service/conference_service.hpp"

#include "service/jam_mapping.hpp"
#include "service/request_context.hpp"

namespace fidoback::service {
std::expected<domain::Conference, domain::ApiError> ConferenceService::GetConference(std::string_view id,
                                                                                     std::string_view user) {
  auto permission = access_->Permissions(*metadata_, user, id);
  if (!permission)
    return std::unexpected(permission.error());
  if (!permission->read && !permission->post && !permission->visible)
    return std::unexpected(EchoAccess::Denied());
  const auto entry = catalog_->areas().find(id);
  if (entry == catalog_->areas().end())
    return std::unexpected(EchoAccess::Denied());
  const auto& area = entry->second;
  domain::Conference result;
  result.id = id;
  result.name = area.config.description.value_or(area.config.name);
  result.description = area.config.description.value_or("");
  result.kind = area.config.kind;
  result.personal_mailbox = !area.config.mailbox_address.empty();
  result.storage_format = area.config.msgbase_type.value_or("");
  result.unsupported_format = !area.files;
  result.statistics_known = permission->read && !result.unsupported_format;
  result.can_read = permission->read;
  result.can_post = permission->post;
  if (!permission->read)
    return result;
  auto access = storage::JamAccess::Open(*catalog_, id, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return std::unexpected(JamError(access.error()));
  auto numbers = (*access)->messages().GetMessageNumbers();
  if (!numbers)
    return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
  auto bookmarked = metadata_->IsBookmarked(user, id);
  if (!bookmarked)
    return std::unexpected(bookmarked.error());
  result.is_bookmarked = *bookmarked;
  result.total_count = static_cast<int64_t>(numbers->size());
  uint32_t latest = 0;
  for (auto number : *numbers) {
    auto message = (*access)->messages().GetHeader(number);
    if (!message)
      return std::unexpected(domain::ApiError::Server("Message storage operation failed"));
    const auto key_number = std::to_string(number);
    auto read = metadata_->IsMessageRead(user, {id, (*access)->generation(), key_number});
    if (!read)
      return std::unexpected(read.error());
    if (!*read)
      ++result.unread_count;
    latest = std::max(latest, message->date_written);
  }
  if (!numbers->empty())
    result.last_message_date = UtcDate(latest);
  if (result.personal_mailbox) {
    auto position = metadata_->LastOpened(user, id);
    if (!position)
      return std::unexpected(position.error());
    result.position_revision = position->revision;
    if (position->generation == (*access)->generation() && !position->message.empty()) {
      auto number = MessageNumber(**access, position->generation + "#" + position->message);
      if (number && std::find(numbers->begin(), numbers->end(), *number) != numbers->end())
        result.last_opened_message = position->generation + "#" + position->message;
    }
  }
  return result;
}
std::expected<domain::ConferenceListResponse, domain::ApiError> ConferenceService::GetConferences(
    const domain::PaginationRequest& page, std::optional<std::string_view> search, std::string_view user,
    std::string_view sort) {
  if (!ValidPage(page) || (sort != "name" && sort != "date" && sort != "unread"))
    return std::unexpected(domain::ApiError::Validation("Invalid page"));
  std::vector<std::string_view> ids;
  for (const auto& [id, area] : catalog_->areas()) {
    auto permission = access_->Permissions(*metadata_, user, id);
    if (!permission)
      return std::unexpected(permission.error());
    if (!permission->read && !permission->post && !permission->visible)
      continue;
    const auto name = area.config.description.value_or(area.config.name);
    if (!search || search->empty() || id.find(*search) != std::string::npos || name.find(*search) != std::string::npos)
      ids.push_back(id);
  }
  std::vector<domain::Conference> sorted;
  if (sort != "name") {
    for (auto id : ids) {
      auto item = GetConference(id, user);
      if (!item)
        return std::unexpected(item.error());
      sorted.push_back(std::move(*item));
    }
    std::sort(sorted.begin(), sorted.end(), [&](const auto& a, const auto& b) {
      if (sort == "date" && a.last_message_date != b.last_message_date)
        return a.last_message_date > b.last_message_date;
      if (sort == "unread" && a.unread_count != b.unread_count)
        return a.unread_count > b.unread_count;
      return a.id < b.id;
    });
  } else {
    std::sort(ids.begin(), ids.end(), [&](auto a, auto b) {
      const auto& ac = catalog_->areas().at(std::string(a)).config;
      const auto& bc = catalog_->areas().at(std::string(b)).config;
      const auto an = ac.description.value_or(ac.name);
      const auto bn = bc.description.value_or(bc.name);
      return an == bn ? a < b : an < bn;
    });
  }
  domain::ConferenceListResponse result;
  result.total = static_cast<int64_t>(ids.size());
  const auto start = std::min<uint64_t>(page.offset, ids.size());
  const auto end = std::min<uint64_t>(start + page.limit, ids.size());
  for (auto i = start; i < end; ++i) {
    if (sort != "name")
      result.conferences.push_back(std::move(sorted.at(i)));
    else {
      auto conference = GetConference(ids.at(i), user);
      if (!conference)
        return std::unexpected(conference.error());
      result.conferences.push_back(std::move(*conference));
    }
  }
  result.has_more = end < ids.size();
  return result;
}
}  // namespace fidoback::service
