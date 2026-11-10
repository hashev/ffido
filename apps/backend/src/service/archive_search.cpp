#include <openssl/rand.h>
#include <sys/stat.h>

#include <algorithm>
#include <tuple>

#include "service/jam_mapping.hpp"
#include "service/message_search.hpp"
#include "service/message_service.hpp"
#include "service/request_context.hpp"
namespace fidoback::service {
namespace {
domain::ApiError Stale() {
  return {domain::ErrorCode::kPrecondition, "Archive cursor is stale; restart the search", {}};
}
domain::ApiError StorageError(const storage::JamAccessError& error, std::string_view area = {},
                              uint32_t number = 0) {
  if (!RequestActive())
    return SearchInterrupted();
  if (auto* changed = std::get_if<storage::CatalogError>(&error);
      changed && *changed == storage::CatalogError::kChangedBase)
    return Stale();
  return JamError(error, area, number);
}
domain::ApiError Resource() {
  return {domain::ErrorCode::kResource, "Archive search resource limit exceeded; narrow the search", {}};
}
std::string Trim(std::string text) {
  const auto start = text.find_first_not_of(" \t\r\n");
  if (start == std::string::npos)
    return {};
  return text.substr(start, text.find_last_not_of(" \t\r\n") - start + 1);
}
std::string Snippet(std::string_view text, uint32_t utf16_offset) {
  size_t offset = 0;
  uint32_t units = 0;
  while (offset < text.size() && units < utf16_offset) {
    const auto c = static_cast<unsigned char>(text[offset]);
    offset += c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
    units += c < 0xf0 ? 1 : 2;
  }
  auto start = offset > 80 ? offset - 80 : 0;
  while (start < text.size() && (static_cast<unsigned char>(text[start]) & 0xc0) == 0x80)
    ++start;
  return storage::Utf8Preview(text.substr(start), 300).value_or("");
}
}  // namespace
std::expected<MessageService::ArchiveFingerprint, domain::ApiError> MessageService::Fingerprint(
    storage::JamAccess& access) {
  ArchiveFingerprint result;
  result.generation = access.generation();
  result.mod_counter = access.messages().base_header().mod_counter;
  for (size_t i = 0; i < 3; ++i) {
    struct stat info{};
    if (fstat(access.files().descriptors[i], &info) != 0)
      return std::unexpected(domain::ApiError::Server("Archive storage unavailable"));
#ifdef __APPLE__
    const auto mtime = info.st_mtimespec, ctime = info.st_ctimespec;
#else
    const auto mtime = info.st_mtim, ctime = info.st_ctim;
#endif
    auto* f = result.files.data() + 7 * i;
    f[0] = info.st_dev;
    f[1] = info.st_ino;
    f[2] = info.st_size;
    f[3] = mtime.tv_sec;
    f[4] = mtime.tv_nsec;
    f[5] = ctime.tv_sec;
    f[6] = ctime.tv_nsec;
  }
  return result;
}
std::expected<domain::ArchiveSearchResponse, domain::ApiError> MessageService::SearchArchive(
    const domain::ArchiveSearchRequest& input, std::string_view user) {
  RequestBudget budget{std::min(RequestDeadline(), std::chrono::steady_clock::now() + std::chrono::seconds(5)),
                       RequestCancellation()};
  RequestScope scope(budget);
  auto request = input;
  request.query = Trim(request.query);
  if (request.conferences.empty() || request.conferences.size() > 20 || request.limit < 1 || request.limit > 100 ||
      request.query.size() > 256 || !storage::ConvertText(request.query, "UTF-8", "UTF-8") ||
      (request.scope != 1 && request.scope != 2) || (request.sort != 1 && request.sort != 2) ||
      (request.from && request.to && *request.from >= *request.to) ||
      (request.query.empty() && (!request.from || !request.to)))
    return std::unexpected(domain::ApiError::Validation("Invalid archive search parameters"));
  std::sort(request.conferences.begin(), request.conferences.end());
  if (std::adjacent_find(request.conferences.begin(), request.conferences.end()) != request.conferences.end())
    return std::unexpected(domain::ApiError::Validation("Duplicate archive area"));
  for (const auto& area : request.conferences) {
    auto permission = access_->Permissions(*metadata_, user, area);
    if (!permission)
      return std::unexpected(permission.error());
    if (!permission->read)
      return std::unexpected(EchoAccess::Denied());
  }
  auto filters = metadata_->GetPersonalFilters(user);
  if (!filters)
    return std::unexpected(filters.error());
  // The registry protects lookup only; each cursor owns its scan and memory reservation.
  std::unique_lock lock(archive_mutex_);
  const auto now = std::chrono::steady_clock::now();
  std::erase_if(archive_scans_, [&](const auto& pair) {
    if (pair.second->expires > now)
      return false;
    pair.second->retired = true;
    return true;
  });
  std::string cursor = request.cursor;
  request.cursor.clear();
  auto it = archive_scans_.find(cursor);
  if (cursor.empty()) {
    const auto count = std::count_if(archive_scans_.begin(), archive_scans_.end(),
                                     [&](const auto& p) { return p.second->user == user; });
    if (archive_scans_.size() >= 64 || count >= 16)
      return std::unexpected(Resource());
    std::array<unsigned char, 24> random{};
    if (RAND_bytes(random.data(), random.size()) != 1)
      return std::unexpected(domain::ApiError::Server("Cursor generation failed"));
    constexpr char hex[] = "0123456789abcdef";
    for (auto c : random) {
      cursor += hex[c >> 4];
      cursor += hex[c & 15];
    }
    auto owner = std::make_shared<ArchiveScan>();
    auto& scan = *owner;
    scan.budget = archive_bytes_;
    scan.request = request;
    scan.user = user;
    scan.filters_revision = filters->revision;
    scan.expires = now + archive_ttl_;
    scan.base_bytes = sizeof(ArchiveScan) + scan.user.capacity() + cursor.capacity() + scan.request.query.capacity() +
                      scan.request.cursor.capacity() + scan.request.conferences.capacity() * sizeof(std::string) +
                      request.conferences.size() * (sizeof(ArchiveFingerprint) + 128) + 16384;
    for (const auto& area : scan.request.conferences)
      scan.base_bytes += area.capacity();
    if (!scan.Reserve(scan.base_bytes))
      return std::unexpected(Resource());
    scan.fingerprints.reserve(request.conferences.size());
    it = archive_scans_.emplace(cursor, std::move(owner)).first;
  } else if (it == archive_scans_.end() || it->second->user != user) {
    return std::unexpected(Stale());
  }
  auto owner = it->second;
  std::unique_lock cursor_lock(owner->mutex, std::try_to_lock);
  if (!cursor_lock.owns_lock())
    return std::unexpected(domain::ApiError{domain::ErrorCode::kResource, "Archive cursor busy", {}});
  lock.unlock();
  if (owner->retired)
    return std::unexpected(Stale());
  auto& scan = *owner;
  const auto discard = [&] {
    std::lock_guard registry(archive_mutex_);
    owner->retired = true;
    auto found = archive_scans_.find(cursor);
    if (found != archive_scans_.end() && found->second == owner)
      archive_scans_.erase(found);
  };
  if (scan.filters_revision != filters->revision) {
    discard();
    return std::unexpected(Stale());
  }
  if (scan.request.conferences != request.conferences || scan.request.query != request.query ||
      scan.request.scope != request.scope || scan.request.sort != request.sort || scan.request.limit != request.limit ||
      scan.request.from != request.from || scan.request.to != request.to || scan.filters_revision != filters->revision)
    return std::unexpected(Stale());
  const auto fail = [&](domain::ApiError error) -> std::expected<domain::ArchiveSearchResponse, domain::ApiError> {
    discard();
    return std::unexpected(std::move(error));
  };
  // Verify every selected base at each boundary; never retain file leases in cursors.
  const auto verify = [&]() -> std::expected<void, domain::ApiError> {
    for (size_t i = 0; i < request.conferences.size(); ++i) {
      auto access = storage::JamAccess::Open(*catalog_, request.conferences[i], false, RequestDeadline(),
                                             RequestCancellation(), encoding_);
      if (!access)
        return std::unexpected(StorageError(access.error()));
      auto fp = Fingerprint(**access);
      if (!fp)
        return std::unexpected(fp.error());
      if (scan.fingerprints.size() <= i)
        scan.fingerprints.push_back(*fp);
      else if (scan.fingerprints[i] != *fp)
        return std::unexpected(Stale());
    }
    return {};
  };
  auto verified = verify();
  if (!verified)
    return fail(verified.error());
  size_t scanned = 0;
  while (!scan.sorted && scan.area < request.conferences.size() && scanned < archive_scan_budget_) {
    const auto& area = request.conferences[scan.area];
    auto access = storage::JamAccess::Open(*catalog_, area, false, RequestDeadline(), RequestCancellation(), encoding_);
    if (!access)
      return fail(StorageError(access.error()));
    auto fp = Fingerprint(**access);
    if (!fp)
      return fail(fp.error());
    if (*fp != scan.fingerprints[scan.area])
      return fail(Stale());
    const auto count = static_cast<uint64_t>(fp->files[16]) / sizeof(msgapi::JamIndexRecord);
    const auto base = (*access)->messages().base_header().base_msg_num;
    while (scan.number < count && scanned < archive_scan_budget_) {
      if (!RequestActive())
        return fail(SearchInterrupted());
      const auto number = static_cast<uint32_t>(base + scan.number++);
      ++scanned;
      auto header = (*access)->messages().GetHeader(number);
      if (!header) {
        if (header.error() == msgapi::JamError::kMessageDeleted)
          continue;
        return fail(StorageError(storage::JamAccessError(header.error()), area, number));
      }
      if ((request.from && int64_t(header->date_written) < *request.from) ||
          (request.to && int64_t(header->date_written) >= *request.to))
        continue;
      bool found = request.query.empty();
      if (!found) {
        auto detail = Detail(**access, area, number, user, request.scope == 2);
        if (!detail)
          return fail(detail.error());
        const std::array<std::string_view, 6> fields{detail->from_name,  detail->from_address, detail->to_name,
                                                     detail->to_address, detail->subject,      detail->body};
        for (int field = 0; field < (request.scope == 1 ? 5 : 6); ++field) {
          auto matches = SearchRanges(fields[field], request.query, SearchCp866(detail->effective_encoding), field + 1);
          if (!matches)
            return fail(matches.error());
          if (!matches->empty()) {
            found = true;
            break;
          }
        }
      }
      if (found) {
        if (scan.hits.size() >= archive_max_hits_)
          return fail(Resource());
        if (scan.hits.size() == scan.hits.capacity()) {
          const auto capacity = std::min(archive_max_hits_, std::max<size_t>(64, scan.hits.capacity() * 2));
          if (capacity >
                  (32 * 1024 * 1024 - std::min<size_t>(scan.base_bytes, 32 * 1024 * 1024)) / sizeof(ArchiveHit) ||
              !scan.Reserve(scan.base_bytes + capacity * sizeof(ArchiveHit)))
            return fail(Resource());
          scan.hits.reserve(capacity);
        }
        scan.hits.push_back({header->date_written, number, scan.area});
      }
    }
    if (scan.number == count) {
      ++scan.area;
      scan.number = 0;
    }
  }
  domain::ArchiveSearchResponse response;
  if (scan.area == request.conferences.size()) {
    if (!scan.sorted) {
      std::sort(scan.hits.begin(), scan.hits.end(), [](const auto& a, const auto& b) {
        return std::tie(a.date, a.area, a.number) < std::tie(b.date, b.area, b.number);
      });
      if (request.sort == 2)
        std::reverse(scan.hits.begin(), scan.hits.end());
      scan.sorted = true;
    }
    const auto end = std::min(scan.hits.size(), scan.page + static_cast<size_t>(request.limit));
    size_t response_bytes = 0;
    for (auto index = scan.page; index < end; ++index) {
      const auto& hit = scan.hits[index];
      const auto& area = request.conferences[hit.area];
      auto access =
          storage::JamAccess::Open(*catalog_, area, false, RequestDeadline(), RequestCancellation(), encoding_);
      if (!access)
        return fail(StorageError(access.error()));
      auto detail = FilteredDetail(**access, area, hit.number, user, &*filters);
      if (!detail)
        return fail(detail.error());
      domain::ArchiveSearchItem item;
      item.conference = area;
      const bool hidden = detail->personal_collapse && !detail->personal_collapse->rules.empty();
      if (!hidden && !request.query.empty()) {
        const std::array<std::string_view, 6> fields{detail->from_name,  detail->from_address, detail->to_name,
                                                     detail->to_address, detail->subject,      detail->body};
        for (int field = 0; field < (request.scope == 1 ? 5 : 6); ++field) {
          auto matches = SearchRanges(fields[field], request.query, SearchCp866(detail->effective_encoding), field + 1);
          if (!matches)
            return fail(matches.error());
          if (matches->size() > 4096 || item.matches.size() + matches->size() > 4096)
            return fail(Resource());
          if (item.snippet.empty() && !matches->empty())
            item.snippet = Snippet(fields[field], matches->front().start_utf16);
          item.matches.insert(item.matches.end(), matches->begin(), matches->end());
        }
      } else if (!hidden)
        item.snippet = Snippet(detail->body, 0);
      detail->body.clear();
      detail->ftn_kludges.clear();
      response_bytes += detail->from_name.size() + detail->from_address.size() + detail->to_name.size() +
                        detail->to_address.size() + detail->subject.size() + item.snippet.size() +
                        item.matches.size() * sizeof(domain::SearchMatch) + 1024;
      if (response_bytes > 3 * 1024 * 1024)
        return fail(Resource());
      item.message = std::move(*detail);
      response.results.push_back(std::move(item));
    }
    scan.page = end;
    response.complete = end == scan.hits.size();
  }
  verified = verify();
  if (!verified)
    return fail(verified.error());
  if (!RequestActive())
    return fail(SearchInterrupted());
  if (owner->retired)
    return fail(Stale());
  if (response.complete)
    discard();
  else {
    response.next_cursor = cursor;
    response.incomplete_reason = scan.sorted ? "page_limit" : "scan_budget";
  }
  return response;
}
}  // namespace fidoback::service
