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
domain::ApiError StorageError(const storage::JamAccessError& error) {
  if (!RequestActive())
    return SearchInterrupted();
  if (auto* changed = std::get_if<storage::CatalogError>(&error);
      changed && *changed == storage::CatalogError::kChangedBase)
    return Stale();
  return JamError(error);
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
  // A try-lock bounds contention instead of letting queued searches ignore deadlines.
  std::unique_lock lock(archive_mutex_, std::try_to_lock);
  if (!lock.owns_lock())
    return std::unexpected(domain::ApiError{domain::ErrorCode::kResource, "Archive search busy", {}});
  const auto now = std::chrono::steady_clock::now();
  std::erase_if(archive_scans_, [&](const auto& pair) { return pair.second.expires <= now; });
  std::string cursor = request.cursor;
  request.cursor.clear();
  auto it = archive_scans_.find(cursor);
  if (cursor.empty()) {
    const auto count = std::count_if(archive_scans_.begin(), archive_scans_.end(),
                                     [&](const auto& p) { return p.second.user == user; });
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
    ArchiveScan scan;
    scan.request = request;
    scan.user = user;
    scan.filters_revision = filters->revision;
    scan.expires = now + archive_ttl_;
    it = archive_scans_.emplace(cursor, std::move(scan)).first;
  } else if (it == archive_scans_.end() || it->second.user != user) {
    return std::unexpected(Stale());
  }
  auto& scan = it->second;
  if (scan.filters_revision != filters->revision) {
    archive_scans_.erase(it);
    return std::unexpected(Stale());
  }
  if (scan.request.conferences != request.conferences || scan.request.query != request.query ||
      scan.request.scope != request.scope || scan.request.sort != request.sort || scan.request.limit != request.limit ||
      scan.request.from != request.from || scan.request.to != request.to || scan.filters_revision != filters->revision)
    return std::unexpected(Stale());
  const auto fail = [&](domain::ApiError error) -> std::expected<domain::ArchiveSearchResponse, domain::ApiError> {
    archive_scans_.erase(it);
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
        return fail(StorageError(storage::JamAccessError(header.error())));
      }
      if ((request.from && int64_t(header->date_written) < *request.from) ||
          (request.to && int64_t(header->date_written) >= *request.to))
        continue;
      bool found = request.query.empty();
      if (!found) {
        auto detail = Detail(**access, area, number, user, request.scope == 2);
        if (!detail)
          return fail(detail.error());
        auto raw = (*access)->messages().ReadMessage(number, false);
        if (!raw)
          return fail(StorageError(storage::JamAccessError(raw.error())));
        auto encoding = (*access)->messages().EffectiveEncoding(*raw);
        if (!encoding)
          return fail(domain::ApiError::Server("Invalid archive encoding"));
        const std::array<std::string_view, 6> fields{detail->from_name,  detail->from_address, detail->to_name,
                                                     detail->to_address, detail->subject,      detail->body};
        for (int field = 0; field < (request.scope == 1 ? 5 : 6); ++field) {
          auto matches = SearchRanges(fields[field], request.query, SearchCp866(*encoding), field + 1);
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
        scan.hits.push_back({header->date_written, number, scan.area});
      }
    }
    if (scan.number == count) {
      ++scan.area;
      scan.number = 0;
    }
  }
  size_t global_bytes = 0;
  for (const auto& [key, value] : archive_scans_) {
    size_t bytes = sizeof(ArchiveScan) + value.hits.capacity() * sizeof(ArchiveHit) + value.user.capacity() +
                   key.capacity() + value.request.query.capacity() + value.request.cursor.capacity() +
                   value.request.conferences.capacity() * sizeof(std::string) +
                   value.fingerprints.capacity() * sizeof(ArchiveFingerprint) + 16384;
    for (const auto& area : value.request.conferences)
      bytes += area.capacity();
    for (const auto& fingerprint : value.fingerprints)
      bytes += fingerprint.generation.capacity();
    if (bytes > 32 * 1024 * 1024)
      return fail(Resource());
    global_bytes += bytes;
  }
  if (global_bytes > 128 * 1024 * 1024)
    return fail(Resource());
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
        auto raw = (*access)->messages().ReadMessage(hit.number, false);
        if (!raw)
          return fail(StorageError(storage::JamAccessError(raw.error())));
        auto encoding = (*access)->messages().EffectiveEncoding(*raw);
        if (!encoding)
          return fail(domain::ApiError::Server("Invalid archive encoding"));
        const std::array<std::string_view, 6> fields{detail->from_name,  detail->from_address, detail->to_name,
                                                     detail->to_address, detail->subject,      detail->body};
        for (int field = 0; field < (request.scope == 1 ? 5 : 6); ++field) {
          auto matches = SearchRanges(fields[field], request.query, SearchCp866(*encoding), field + 1);
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
  if (response.complete)
    archive_scans_.erase(it);
  else {
    response.next_cursor = cursor;
    response.incomplete_reason = scan.sorted ? "page_limit" : "scan_budget";
  }
  return response;
}
}  // namespace fidoback::service
