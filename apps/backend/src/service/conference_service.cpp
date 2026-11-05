#include "service/conference_service.hpp"

#include <spdlog/spdlog.h>

#include <locale>
#include <set>

#include "service/jam_mapping.hpp"
#include "service/message_search.hpp"
#include "service/request_context.hpp"

namespace fidoback::service {
std::expected<domain::Conference, domain::ApiError> ConferenceService::GetConference(std::string_view id,
                                                                                     std::string_view user,
                                                                                     bool omit_statistics) {
  return Describe(id, user, false, omit_statistics);
}
std::expected<domain::Conference, domain::ApiError> ConferenceService::Describe(std::string_view id,
                                                                                std::string_view user, bool tolerant,
                                                                                bool omit_statistics) {
  if (!RequestActive())
    return std::unexpected(SearchInterrupted());
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
  result.statistics_known = !omit_statistics && permission->read && !result.unsupported_format;
  result.can_read = permission->read;
  result.can_post = permission->post;
  if (!permission->read)
    return result;
  auto bookmarked = metadata_->IsBookmarked(user, id);
  if (!bookmarked)
    return std::unexpected(bookmarked.error());
  result.is_bookmarked = *bookmarked;
  if (omit_statistics || result.unsupported_format)
    return result;
  const auto storage_failure =
      [&](const storage::JamAccessError& error) -> std::expected<domain::Conference, domain::ApiError> {
    if (!RequestActive())
      return std::unexpected(domain::ApiError{
          RequestCancellation().stop_requested() ? domain::ErrorCode::kCancelled : domain::ErrorCode::kDeadline,
          "Request no longer active",
          {}});
    auto mapped = JamError(error);
    if (!tolerant || std::holds_alternative<storage::CoordinationError>(error) ||
        mapped.code == domain::ErrorCode::kResource || mapped.code == domain::ErrorCode::kDeadline ||
        mapped.code == domain::ErrorCode::kCancelled)
      return std::unexpected(mapped);
    spdlog::warn("Conference statistics unavailable: area={} category={}", id, error.index());
    result.statistics_known = false;
    result.total_count = result.unread_count = 0;
    result.last_message_date.clear();
    return result;
  };
  auto access = storage::JamAccess::Open(*catalog_, id, false, RequestDeadline(), RequestCancellation(), encoding_);
  if (!access)
    return storage_failure(access.error());
  auto numbers = (*access)->messages().GetMessageNumbers();
  if (!numbers)
    return storage_failure(storage::JamAccessError{numbers.error()});
  result.total_count = static_cast<int64_t>(numbers->size());
  auto read = metadata_->GetReadCountForMessages(user, id, (*access)->generation(), *numbers, RequestActive);
  if (!read)
    return std::unexpected(read.error());
  result.unread_count = result.total_count - *read;
  uint32_t latest = 0;
  for (auto number : *numbers) {
    auto message = (*access)->messages().GetHeader(number);
    if (!message)
      return storage_failure(storage::JamAccessError{message.error()});
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
    std::string_view sort, bool omit_statistics, bool bookmarked_only) {
  if (!ValidPage(page) || (sort != "name" && sort != "date" && sort != "unread" && sort != "catalog"))
    return std::unexpected(domain::ApiError::Validation("Invalid page"));
  if (omit_statistics && (sort == "date" || sort == "unread"))
    return std::unexpected(domain::ApiError::Validation("Statistics sort requires statistics"));
  std::set<std::string> bookmarks;
  if (bookmarked_only) {
    auto saved = metadata_->GetBookmarks(user);
    if (!saved)
      return std::unexpected(saved.error());
    for (const auto& bookmark : *saved)
      bookmarks.insert(bookmark.conference_id);
  }
  std::vector<std::string_view> ids;
  for (const auto& [id, area] : catalog_->areas()) {
    if (!RequestActive())
      return std::unexpected(SearchInterrupted());
    auto permission = access_->Permissions(*metadata_, user, id);
    if (!permission)
      return std::unexpected(permission.error());
    if (!permission->read && !permission->post && !permission->visible)
      continue;
    if (bookmarked_only && (!permission->read || !bookmarks.contains(id)))
      continue;
    const auto name = area.config.description.value_or(area.config.name);
    if (!search || search->empty() || id.find(*search) != std::string::npos || name.find(*search) != std::string::npos)
      ids.push_back(id);
  }
  std::vector<domain::Conference> sorted;
  if (sort == "date" || sort == "unread") {
    for (auto id : ids) {
      auto item = Describe(id, user, true);
      if (!item)
        return std::unexpected(item.error());
      sorted.push_back(std::move(*item));
    }
    std::sort(sorted.begin(), sorted.end(), [&](const auto& a, const auto& b) {
      if (a.statistics_known != b.statistics_known)
        return a.statistics_known;
      if (sort == "date" && a.last_message_date != b.last_message_date)
        return a.last_message_date > b.last_message_date;
      if (sort == "unread" && a.unread_count != b.unread_count)
        return a.unread_count > b.unread_count;
      return a.id < b.id;
    });
  } else if (sort == "catalog") {
    // Pin UTF-8 casing independently of the process locale on supported hosts.
#ifdef __APPLE__
    static const std::locale casing("en_US.UTF-8");
#else
    static const std::locale casing("C.UTF-8");
#endif
    const auto& unicode = std::use_facet<std::ctype<wchar_t>>(casing);
    std::map<std::string_view, std::pair<int, std::u32string>> keys;
    for (auto id : ids) {
      const auto& config = catalog_->areas().at(std::string(id)).config;
      auto folded = FoldSearch(config.description.value_or(config.name), false);
      if (!folded)
        return std::unexpected(folded.error());
      for (auto& point : folded->folded)
        point = static_cast<char32_t>(unicode.tolower(static_cast<wchar_t>(point)));
      const int group = config.kind == AreaKind::kEcho ? 5 : static_cast<int>(config.kind) - 1;
      keys.emplace(id, std::pair{group, std::move(folded->folded)});
    }
    std::sort(ids.begin(), ids.end(),
              [&](auto a, auto b) { return keys.at(a) == keys.at(b) ? a < b : keys.at(a) < keys.at(b); });
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
    if (sort == "date" || sort == "unread")
      result.conferences.push_back(std::move(sorted.at(i)));
    else {
      auto conference = Describe(ids.at(i), user, true, omit_statistics);
      if (!conference)
        return std::unexpected(conference.error());
      result.conferences.push_back(std::move(*conference));
    }
  }
  result.has_more = end < ids.size();
  if (!RequestActive())
    return std::unexpected(domain::ApiError{
        RequestCancellation().stop_requested() ? domain::ErrorCode::kCancelled : domain::ErrorCode::kDeadline,
        "Request no longer active",
        {}});
  return result;
}
}  // namespace fidoback::service
