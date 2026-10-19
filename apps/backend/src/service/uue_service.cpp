#include "service/uue_service.hpp"

#include <openssl/rand.h>

#include <algorithm>
#include <charconv>
#include <nlohmann/json.hpp>

#include "service/crypto.hpp"
#include "service/jam_mapping.hpp"
#include "service/request_context.hpp"

namespace fidoback::service {
namespace {
using domain::ApiError;
ApiError Invalid(std::string_view message) {
  return ApiError::Validation(message);
}
std::expected<std::string, ApiError> HexDigest(std::string_view bytes) {
  auto digest = Sha256(bytes);
  if (!digest)
    return std::unexpected(digest.error());
  constexpr char alphabet[] = "0123456789abcdef";
  std::string result;
  for (auto b : *digest) {
    result += alphabet[b >> 4];
    result += alphabet[b & 15];
  }
  return result;
}
std::pair<uint32_t, uint32_t> Numbering(std::string_view subject) {
  const auto open = subject.rfind('['), slash = subject.rfind('/');
  if (open == subject.npos || slash == subject.npos || open >= slash || !subject.ends_with(']'))
    return {1, 1};
  uint32_t part = 0, total = 0;
  auto a = subject.substr(open + 1, slash - open - 1);
  auto b = subject.substr(slash + 1, subject.size() - slash - 2);
  auto [ae, ac] = std::from_chars(a.data(), a.data() + a.size(), part);
  auto [be, bc] = std::from_chars(b.data(), b.data() + b.size(), total);
  if (ac != std::errc{} || bc != std::errc{} || ae != a.data() + a.size() || be != b.data() + b.size() || !part ||
      part > total || total > 1024)
    return {1, 1};
  return {part, total};
}
size_t PayloadEnd(std::string_view body) {
  size_t end = body.size();
  for (auto marker : {"\n--- ", "\n * Origin:", "\nSEEN-BY:", "\n\1PATH:"}) {
    auto pos = body.find(marker);
    if (pos != body.npos)
      end = std::min(end, pos + 1);
  }
  return end;
}
std::string_view LegacySubject(std::string_view subject) {
  subject = subject.substr(0, subject.rfind('['));
  const auto end = subject.find_last_not_of(" \t\r\n");
  return end == subject.npos ? std::string_view{} : subject.substr(0, end + 1);
}
}  // namespace

std::expected<std::string, ApiError> UueService::Fingerprint(const domain::MessageDetail& message) {
  std::string text;
  for (const auto& item : {message.id, message.ftn_message_id, message.from_address, message.to_address,
                           message.subject, message.body, std::to_string(message.direction)}) {
    text += std::to_string(item.size()) + ":" + item;
  }
  for (const auto& line : message.ftn_kludges)
    text += std::to_string(line.size()) + ":" + line;
  return HexDigest(text);
}
void UueService::Prune() {
  const auto now = clock_();
  std::erase_if(index_, [&](const auto& item) { return item.second.expires <= now; });
  std::erase_if(files_, [&](const auto& item) { return item.second.expires <= now; });
}
std::expected<std::vector<UuePart>, ApiError> UueService::Parts(std::string_view conference,
                                                                const domain::MessageDetail& message) {
  auto fingerprint = Fingerprint(message);
  if (!fingerprint)
    return std::unexpected(fingerprint.error());
  // Fingerprints include source identity; no stale content is served from this derived index.
  const auto key = std::string(conference) + ":" + *fingerprint;
  {
    std::lock_guard lock(mutex_);
    Prune();
    if (auto cached = index_.find(key); cached != index_.end())
      return cached->second.parts;
  }
  std::optional<ftn::uue::Metadata> meta;
  std::string diagnostic;
  for (const auto& line : message.ftn_kludges) {
    if (!line.starts_with("FFIDO-UUE:"))
      continue;
    auto parsed = ftn::uue::ParseMetadata(line, CodecLimits());
    if (!parsed || meta) {
      diagnostic = "Invalid or duplicate FFIDO-UUE metadata";
      meta.reset();
      break;
    }
    meta = std::move(*parsed);
  }
  const auto numbering = Numbering(message.subject);
  uint32_t part = numbering.first;
  uint32_t total = numbering.second;
  if (meta) {
    part = meta->part;
    total = meta->total;
  }
  const auto body = std::string_view(message.body).substr(0, PayloadEnd(message.body));
  auto scanned = ftn::uue::Scan(body, CodecLimits());
  if (!scanned)
    return std::unexpected(ApiError{domain::ErrorCode::kResource, "UUE input limit exceeded", {}});
  std::vector<UuePart> result;
  auto add = [&](size_t begin, size_t end, std::string name, size_t block) {
    UuePart value;
    value.source = {std::string(conference), message.id, static_cast<uint32_t>(block)};
    value.from = message.from_address;
    value.to = message.to_address;
    value.direction = message.direction;
    value.subject = message.subject;
    value.date = message.date;
    value.filename = ftn::uue::SafeFilename(name);
    value.metadata = meta;
    value.part = part;
    value.total = total;
    value.begin = static_cast<uint32_t>(begin);
    value.end = static_cast<uint32_t>(end);
    value.diagnostic = diagnostic;
    result.push_back(std::move(value));
  };
  for (size_t i = 0; i < scanned->size(); ++i) {
    const auto& block = scanned->at(i);
    add(block.begin, block.end, meta ? meta->filename : block.filename, i);
  }
  const auto first_line = body.substr(0, body.find('\n'));
  const size_t count = first_line.empty() ? 0 : (static_cast<unsigned char>(first_line[0]) - 32u) & 63u;
  const bool continuation =
      count > 0 && count <= 45 && first_line.size() == 1 + 4 * ((count + 2) / 3) &&
      std::all_of(first_line.begin(), first_line.end(), [](unsigned char c) { return c >= 32 && c <= 96; });
  if (scanned->empty() && (meta || total > 1 || continuation || !diagnostic.empty()))
    add(0, body.size(), meta ? meta->filename : "attachment.bin", 0);
  if (meta && result.size() != 1)
    for (auto& value : result)
      value.diagnostic = "Multipart metadata must identify exactly one stream";
  {
    std::lock_guard lock(mutex_);
    if (index_.size() >= 512)
      index_.erase(index_.begin());
    index_[key] = {result, clock_() + std::chrono::minutes(5)};
  }
  return result;
}
std::expected<UueSearch, ApiError> UueService::Search(std::string_view conference, std::string_view generation,
                                                      uint32_t after, uint32_t limit, std::string_view user) {
  if (!limit || limit > 100 || (after && generation.empty()))
    return std::unexpected(Invalid("Invalid UUE page"));
  auto permissions = access_->Permissions(*metadata_, user, conference);
  if (!permissions)
    return std::unexpected(permissions.error());
  if (!permissions->read)
    return std::unexpected(EchoAccess::Denied());
  UueSearch result;
  std::vector<uint32_t> numbers;
  {
    auto access =
        storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
    if (!access)
      return std::unexpected(JamError(access.error()));
    result.generation = (*access)->generation();
    if (!generation.empty() && generation != result.generation)
      return std::unexpected(ApiError{domain::ErrorCode::kPrecondition, "UUE search generation changed", {}});
    auto entries = (*access)->messages().GetMessageNumbers();
    if (!entries)
      return std::unexpected(ApiError::Server("UUE message index unavailable"));
    numbers = std::move(*entries);
  }
  std::sort(numbers.begin(), numbers.end());
  auto start = std::upper_bound(numbers.begin(), numbers.end(), after);
  size_t count = 0, scanned_bytes = 0;
  for (auto i = start; i != numbers.end() && count < limit; ++i, ++count) {
    if (!RequestActive())
      return std::unexpected(ApiError{domain::ErrorCode::kDeadline, "UUE search deadline", {}});
    auto message = messages_.PeekMessage(conference, result.generation + "#" + std::to_string(*i), user);
    if (!message)
      return std::unexpected(message.error());
    // Bound aggregate decoding work per page, even when an area contains huge messages.
    if (scanned_bytes && (scanned_bytes >= 4 * 1024 * 1024 || message->body.size() > 4 * 1024 * 1024 - scanned_bytes)) {
      result.more = true;
      break;
    }
    scanned_bytes += message->body.size();
    auto parts = Parts(conference, *message);
    if (!parts)
      return std::unexpected(parts.error());
    if (result.parts.size() + parts->size() > 256) {
      result.more = true;
      break;
    }
    result.parts.insert(result.parts.end(), parts->begin(), parts->end());
    result.next = *i;
    result.more = std::next(i) != numbers.end();
  }
  if (start == numbers.end())
    result.next = after;
  return result;
}
std::expected<UueAttachment, ApiError> UueService::Assemble(const std::vector<UueReference>& sources,
                                                            bool explicit_order, std::string_view user) {
  if (sources.empty() || sources.size() > config_.max_parts)
    return std::unexpected(Invalid("Invalid UUE sources"));
  std::vector<UuePart> parts;
  std::vector<std::string> bodies, fingerprints;
  size_t input = 0;
  for (const auto& source : sources) {
    if (source.conference != sources[0].conference)
      return std::unexpected(Invalid("Cross-area UUE assembly denied"));
    auto message = messages_.PeekMessage(source.conference, source.message, user);
    if (!message)
      return std::unexpected(message.error());
    auto candidates = Parts(source.conference, *message);
    if (!candidates)
      return std::unexpected(candidates.error());
    if (source.block >= candidates->size())
      return std::unexpected(Invalid("UUE source block unavailable"));
    auto part = candidates->at(source.block);
    if (!parts.empty() &&
        (part.from != parts[0].from || part.to != parts[0].to || part.direction != parts[0].direction))
      return std::unexpected(Invalid("UUE source identity differs"));
    const auto size = part.end - part.begin;
    if (size > CodecLimits().input_bytes - input)
      return std::unexpected(ApiError{domain::ErrorCode::kResource, "UUE assembly limit", {}});
    input += size;
    auto fingerprint = Fingerprint(*message);
    if (!fingerprint)
      return std::unexpected(fingerprint.error());
    fingerprints.push_back(std::move(*fingerprint));
    bodies.push_back(message->body.substr(part.begin, size));
    parts.push_back(std::move(part));
  }
  UueAttachment result;
  result.filename = parts[0].filename;
  result.sources = sources;
  std::vector<size_t> order;
  const auto meta = parts[0].metadata;
  const bool multipart = sources.size() > 1 || parts[0].total > 1;
  const bool legacy_numbered = !meta && parts[0].total > 1;
  if (multipart && !meta && !legacy_numbered && !explicit_order)
    return std::unexpected(ApiError{domain::ErrorCode::kPrecondition, "Choose the unnumbered UUE parts and order", {}});
  if (multipart && parts[0].from.empty())
    return std::unexpected(Invalid("UUE source has no FTN origin"));
  std::map<uint32_t, size_t> numbered;
  for (size_t i = 0; i < parts.size(); ++i) {
    if (!parts[i].diagnostic.empty()) {
      result.state = UueState::kCorrupt;
      result.diagnostic = parts[i].diagnostic;
      return result;
    }
    if (meta) {
      if (!parts[i].metadata || parts[i].metadata->transfer_id != meta->transfer_id ||
          parts[i].metadata->sha256 != meta->sha256 || parts[i].metadata->size != meta->size ||
          parts[i].metadata->filename != meta->filename || parts[i].total != meta->total) {
        result.state = UueState::kConflict;
        return result;
      }
      auto [found, inserted] = numbered.emplace(parts[i].part, i);
      if (!inserted && bodies[found->second] != bodies[i]) {
        result.state = UueState::kConflict;
        return result;
      }
    } else {
      if (parts[i].metadata) {
        result.state = UueState::kConflict;
        return result;
      }
      if (legacy_numbered) {
        if (parts[i].total != parts[0].total ||
            (!explicit_order && LegacySubject(parts[i].subject) != LegacySubject(parts[0].subject))) {
          result.state = UueState::kConflict;
          return result;
        }
        auto [found, inserted] = numbered.emplace(parts[i].part, i);
        if (!inserted) {
          if (bodies[found->second] != bodies[i]) {
            result.state = UueState::kConflict;
            return result;
          }
          continue;
        }
      }
      order.push_back(i);
    }
  }
  if (legacy_numbered) {
    for (uint32_t n = 1; n <= parts[0].total; ++n)
      if (!numbered.contains(n))
        result.missing.push_back(n);
    if (!result.missing.empty())
      return result;
    result.filename = parts[numbered.at(1)].filename;
    if (!explicit_order) {
      order.clear();
      for (const auto& [number, index] : numbered)
        order.push_back(index);
    }
  }
  if (meta) {
    for (uint32_t n = 1; n <= meta->total; ++n) {
      if (!numbered.contains(n))
        result.missing.push_back(n);
      else
        order.push_back(numbered[n]);
    }
    if (!result.missing.empty())
      return result;
  }
  std::vector<std::string_view> ordered;
  for (size_t i : order)
    ordered.push_back(bodies[i]);
  auto decoded = ftn::uue::Assemble(ordered, CodecLimits());
  if (!decoded) {
    result.state = decoded.error() == ftn::uue::Error::kIncomplete ? UueState::kIncomplete : UueState::kCorrupt;
    return result;
  }
  if (meta && !ftn::uue::Verify(*decoded, *meta)) {
    result.state = UueState::kCorrupt;
    return result;
  }
  auto hash = HexDigest(*decoded);
  if (!hash)
    return std::unexpected(hash.error());
  result.sha256 = *hash;
  result.verified = bool(meta);
  if (multipart && !meta)
    result.diagnostic = "No checksum; parts from different transfers may have been mixed";
  result.size = decoded->size();
  result.state = UueState::kReady;
  std::string identity = std::string(user) + ":" + result.sha256;
  for (size_t i = 0; i < fingerprints.size(); ++i)
    identity += ":" + sources[i].conference + ":" + std::to_string(sources[i].block) + ":" + fingerprints[i];
  auto id = HexDigest(identity);
  if (!id)
    return std::unexpected(id.error());
  result.id = *id;
  {
    std::lock_guard lock(mutex_);
    Prune();
    size_t total_bytes = decoded->size(), user_bytes = decoded->size();
    for (const auto& [key, entry] : files_) {
      if (key == result.id)
        continue;
      total_bytes += entry.bytes.size();
      if (entry.user == user)
        user_bytes += entry.bytes.size();
    }
    if (files_.size() >= 256 || total_bytes > config_.global_quota_bytes || user_bytes > config_.user_quota_bytes)
      return std::unexpected(ApiError{domain::ErrorCode::kResource, "UUE cache quota exceeded", {}});
    files_[result.id] = {result, std::string(user), std::move(*decoded), std::move(fingerprints),
                         clock_() + std::chrono::minutes(5)};
  }
  return result;
}
std::expected<UueChunk, ApiError> UueService::Chunk(std::string_view id, uint64_t offset, uint32_t max_bytes,
                                                    std::string_view user) {
  if (!max_bytes || max_bytes > config_.chunk_bytes)
    return std::unexpected(Invalid("Invalid UUE chunk size"));
  CachedFile cached;
  {
    std::lock_guard lock(mutex_);
    Prune();
    auto found = files_.find(std::string(id));
    if (found == files_.end() || found->second.user != user)
      return std::unexpected(ApiError::NotFound("UUE file unavailable"));
    cached = found->second;
  }
  for (size_t i = 0; i < cached.attachment.sources.size(); ++i) {
    const auto& source = cached.attachment.sources[i];
    auto message = messages_.PeekMessage(source.conference, source.message, user);
    if (!message) {
      std::lock_guard lock(mutex_);
      files_.erase(std::string(id));
      return std::unexpected(message.error());
    }
    auto fingerprint = Fingerprint(*message);
    if (!fingerprint)
      return std::unexpected(fingerprint.error());
    if (*fingerprint != cached.fingerprints[i]) {
      std::lock_guard lock(mutex_);
      files_.erase(std::string(id));
      return std::unexpected(ApiError{domain::ErrorCode::kPrecondition, "UUE source changed", {}});
    }
  }
  if (offset > cached.bytes.size())
    return std::unexpected(Invalid("UUE offset exceeds size"));
  UueChunk result;
  result.offset = offset;
  result.size = cached.bytes.size();
  result.bytes = cached.bytes.substr(static_cast<size_t>(offset), max_bytes);
  result.eof = offset + result.bytes.size() == result.size;
  return result;
}

namespace {
int64_t UueNow() {
  return std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count();
}
bool OperationId(std::string_view id) {
  return !id.empty() && id.size() <= 128 &&
         id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") == id.npos;
}
}  // namespace
std::expected<void, ApiError> UueService::Save(storage::UueUpload& upload) {
  upload.updated_at = UueNow();
  auto result = metadata_->SaveUueUpload(upload, config_.user_quota_bytes, config_.global_quota_bytes);
  if (result)
    ++upload.revision;
  return result;
}
std::expected<uint64_t, ApiError> UueService::Upload(std::string_view operation, std::string_view filename,
                                                     uint64_t size, std::string_view sha256, uint64_t offset,
                                                     std::string_view bytes, std::string_view user) {
  if (!OperationId(operation) || filename.empty() || filename.size() > 255 ||
      !storage::ConvertText(filename, "UTF-8", "UTF-8") || size > config_.max_file_bytes ||
      bytes.size() > config_.chunk_bytes || offset > size || bytes.size() > size - offset || sha256.size() != 64 ||
      sha256.find_first_not_of("0123456789abcdef") != sha256.npos)
    return std::unexpected(Invalid("Invalid UUE upload or server limit exceeded"));
  std::unique_lock lock(send_mutexes_[std::hash<std::string_view>{}(user) % send_mutexes_.size()], std::defer_lock);
  if (!lock.try_lock_until(RequestDeadline()))
    return std::unexpected(ApiError{domain::ErrorCode::kUnavailable, "UUE operation busy", {}});
  auto pruned = metadata_->PruneUueUploads(UueNow() - config_.upload_ttl_seconds);
  if (!pruned)
    return std::unexpected(pruned.error());
  auto previous = metadata_->GetUueUpload(user, operation);
  if (!previous)
    return std::unexpected(previous.error());
  storage::UueUpload upload;
  if (*previous) {
    upload = std::move(**previous);
    if (upload.filename != filename || upload.sha256 != sha256 || upload.size != size || upload.state != "uploading")
      return std::unexpected(
          ApiError{domain::ErrorCode::kConflict, "UUE operation has another file or is committed", {}});
  } else {
    if (offset)
      return std::unexpected(Invalid("UUE upload starts at offset zero"));
    upload.user = user;
    upload.id = operation;
    upload.filename = filename;
    upload.size = size;
    upload.sha256 = sha256;
  }
  if (offset > upload.data.size())
    return std::unexpected(Invalid("UUE upload has a gap"));
  if (offset < upload.data.size()) {
    if (bytes.size() > upload.data.size() - offset ||
        upload.data.compare(static_cast<size_t>(offset), bytes.size(), bytes) != 0)
      return std::unexpected(ApiError{domain::ErrorCode::kConflict, "UUE chunk differs", {}});
  } else
    upload.data += bytes;
  if (upload.data.size() == size) {
    auto digest = HexDigest(upload.data);
    if (!digest)
      return std::unexpected(digest.error());
    if (*digest != sha256)
      return std::unexpected(Invalid("UUE file checksum mismatch"));
  }
  if (!RequestActive())
    return std::unexpected(ApiError{domain::ErrorCode::kDeadline, "UUE upload deadline", {}});
  auto saved = Save(upload);
  if (!saved)
    return std::unexpected(saved.error());
  return upload.data.size();
}

namespace {
using Json = nlohmann::json;
std::expected<std::string, ApiError> RandomHex(size_t size) {
  std::array<unsigned char, 16> data{};
  if (size > data.size() || RAND_bytes(data.data(), static_cast<int>(size)) != 1)
    return std::unexpected(ApiError::Server("UUE identity generation failed"));
  std::string result;
  constexpr char alphabet[] = "0123456789abcdef";
  for (size_t i = 0; i < size; ++i) {
    result += alphabet[data[i] >> 4];
    result += alphabet[data[i] & 15];
  }
  return result;
}
std::expected<Json, ApiError> Manifest(const storage::UueUpload& upload) {
  auto parsed = Json::parse(upload.manifest, nullptr, false);
  if (!parsed.is_object() || !parsed.contains("parts") || !parsed["parts"].is_array() || !parsed.contains("request") ||
      !parsed["request"].is_object())
    return std::unexpected(ApiError::Server("UUE journal is invalid"));
  return parsed;
}
UueSendStatus Status(const storage::UueUpload& upload, const Json& manifest) {
  UueSendStatus result;
  result.filename = upload.filename;
  result.sha256 = upload.sha256;
  result.file_size = upload.size;
  result.operation = upload.id;
  result.state = upload.state;
  result.conference = manifest.value("conference", "");
  result.total = manifest.at("parts").size();
  for (const auto& part : manifest.at("parts")) {
    const auto id = part.value("message", "");
    if (!id.empty())
      result.messages.push_back(id);
  }
  result.saved = result.messages.size();
  result.diagnostic = manifest.value("diagnostic", "");
  return result;
}
}  // namespace
std::expected<UueSendStatus, ApiError> UueService::SendStatus(std::string_view operation, std::string_view user) {
  if (!OperationId(operation))
    return std::unexpected(Invalid("Invalid UUE operation"));
  auto upload = metadata_->GetUueUpload(user, operation);
  if (!upload)
    return std::unexpected(upload.error());
  if (!*upload)
    return std::unexpected(ApiError::NotFound("UUE operation unavailable"));
  if ((**upload).manifest.empty()) {
    UueSendStatus result;
    result.operation = operation;
    result.state = "uploading";
    result.filename = (**upload).filename;
    result.sha256 = (**upload).sha256;
    result.file_size = (**upload).size;
    return result;
  }
  auto manifest = Manifest(**upload);
  if (!manifest)
    return std::unexpected(manifest.error());
  return Status(**upload, *manifest);
}
std::expected<UueSendStatus, ApiError> UueService::Commit(std::string_view conference,
                                                          const domain::CreateMessageRequest& request,
                                                          std::string_view user) {
  if (!OperationId(request.operation_id) || request.subject.empty())
    return std::unexpected(Invalid("Invalid UUE operation"));
  std::unique_lock lock(send_mutexes_[std::hash<std::string_view>{}(user) % send_mutexes_.size()], std::defer_lock);
  if (!lock.try_lock_until(RequestDeadline()))
    return std::unexpected(ApiError{domain::ErrorCode::kUnavailable, "UUE operation busy", {}});
  auto record = metadata_->GetUueUpload(user, request.operation_id);
  if (!record)
    return std::unexpected(record.error());
  if (!*record)
    return std::unexpected(ApiError::NotFound("UUE upload unavailable"));
  auto upload = std::move(**record);
  for (const auto& text : {request.subject, request.body, request.to_name, request.to_address, request.in_reply_to})
    if (!storage::ConvertText(text, "UTF-8", "UTF-8"))
      return std::unexpected(Invalid("Invalid UUE message text"));
  Json original{{"conference", conference},         {"operation", request.operation_id}, {"to_name", request.to_name},
                {"to_address", request.to_address}, {"subject", request.subject},        {"body", request.body},
                {"reply", request.in_reply_to}};
  Json manifest;
  if (!upload.manifest.empty()) {
    auto parsed = Manifest(upload);
    if (!parsed)
      return std::unexpected(parsed.error());
    manifest = std::move(*parsed);
    if (manifest.at("request") != original)
      return std::unexpected(ApiError{domain::ErrorCode::kConflict, "UUE operation has another message", {}});
    if (upload.state == "completed")
      return Status(upload, manifest);
  } else {
    auto permission = access_->Permissions(*metadata_, user, conference);
    if (!permission)
      return std::unexpected(permission.error());
    if (!permission->post)
      return std::unexpected(EchoAccess::Denied());
    auto area = catalog_->areas().find(conference);
    if (area == catalog_->areas().end())
      return std::unexpected(ApiError::NotFound("UUE area unavailable"));
    if (area->second.config.kind != AreaKind::kEcho && area->second.config.kind != AreaKind::kNetmail)
      return std::unexpected(Invalid("UUE posting requires echo or Netmail"));
    if (upload.data.size() != upload.size)
      return std::unexpected(Invalid("UUE upload is incomplete"));
    auto digest = HexDigest(upload.data);
    if (!digest)
      return std::unexpected(digest.error());
    if (*digest != upload.sha256)
      return std::unexpected(Invalid("UUE file checksum mismatch"));
    auto profile = metadata_->GetProfile(user);
    if (!profile)
      return std::unexpected(profile.error());
    std::string generation;
    {
      auto base =
          storage::JamAccess::Open(*catalog_, conference, false, RequestDeadline(), RequestCancellation(), encoding_);
      if (!base)
        return std::unexpected(JamError(base.error()));
      generation = (*base)->generation();
    }
    auto wire_text = storage::ConvertText(request.body, "UTF-8", encoding_);
    if (!wire_text || wire_text->size() + 768 >= config_.part_body_bytes)
      return std::unexpected(Invalid("Text with attachment does not fit the first UUE part"));
    auto encoded = ftn::uue::Encode(upload.data, ftn::uue::SafeFilename(upload.filename, true), CodecLimits());
    if (!encoded)
      return std::unexpected(Invalid("UUE encoding limit exceeded"));
    std::vector<std::string> bodies{request.body.empty() ? "" : request.body + "\n"};
    size_t used = wire_text->size() + (request.body.empty() ? 0 : 1);
    const size_t budget = config_.part_body_bytes - 512;
    for (size_t offset = 0; offset < encoded->size();) {
      const auto end = encoded->find('\n', offset) + 1;
      const auto count = end - offset;
      if (used + count > budget) {
        bodies.emplace_back();
        used = 0;
      }
      bodies.back().append(*encoded, offset, count);
      used += count;
      offset = end;
    }
    if (bodies.size() > config_.max_parts)
      return std::unexpected(Invalid("Too many UUE parts"));
    auto transfer_id = RandomHex(16);
    if (!transfer_id)
      return std::unexpected(transfer_id.error());
    manifest = {{"conference", conference},         {"generation", generation}, {"from_name", profile->name},
                {"from_address", profile->address}, {"request", original},      {"parts", Json::array()}};
    std::string to_name, to_address;
    for (size_t i = 0; i < bodies.size(); ++i) {
      ftn::uue::Metadata meta{
          *transfer_id,  static_cast<uint32_t>(i + 1),           static_cast<uint32_t>(bodies.size()), upload.size,
          upload.sha256, ftn::uue::SafeFilename(upload.filename)};
      auto kludge = ftn::uue::FormatMetadata(meta, CodecLimits());
      auto serial = RandomHex(4);
      auto operation = HexDigest(std::string(user) + ":" + upload.id + ":" + std::to_string(i));
      if (!kludge || !serial || !operation)
        return std::unexpected(ApiError::Server("UUE envelope failed"));
      domain::CreateMessageRequest part = request;
      part.operation_id = "uue_" + *operation;
      part.subject += " [" + std::to_string(i + 1) + "/" + std::to_string(bodies.size()) + "]";
      part.body = bodies[i];
      UuePublishOptions options{
          *kludge, profile->address + " " + *serial, generation, profile->name, profile->address, to_name, to_address,
          i != 0};
      auto checked = messages_.CreateMessage(conference, part, user, &options, true);
      if (!checked)
        return std::unexpected(checked.error());
      if (checked->wire_body_bytes > config_.part_body_bytes)
        return std::unexpected(Invalid("UUE part exceeds body limit"));
      if (!i) {
        to_name = checked->resolved_to_name;
        to_address = checked->resolved_to_address;
      }
      manifest["parts"].push_back({{"operation", part.operation_id},
                                   {"subject", part.subject},
                                   {"body", part.body},
                                   {"kludge", options.kludge},
                                   {"msgid", options.msgid},
                                   {"message", ""}});
    }
    manifest["to_name"] = to_name;
    manifest["to_address"] = to_address;
    upload.manifest = manifest.dump();
    upload.state = "prepared";
    auto saved = Save(upload);
    if (!saved)
      return std::unexpected(saved.error());
  }
  upload.state = "publishing";
  if (auto saved = Save(upload); !saved)
    return std::unexpected(saved.error());
  for (auto& item : manifest["parts"]) {
    domain::CreateMessageRequest part = request;
    part.operation_id = item.at("operation");
    part.subject = item.at("subject");
    part.body = item.at("body");
    UuePublishOptions options{
        item.at("kludge"),           item.at("msgid"),       manifest.at("generation"), manifest.at("from_name"),
        manifest.at("from_address"), manifest.at("to_name"), manifest.at("to_address"), true};
    auto sent = messages_.CreateMessage(conference, part, user, &options);
    if (!sent) {
      upload.state = "partial";
      manifest["diagnostic"] = "Publication interrupted; retry the same operation";
      upload.manifest = manifest.dump();
      if (auto saved = Save(upload); !saved)
        return std::unexpected(saved.error());
      return Status(upload, manifest);
    }
    item["message"] = sent->id;
    upload.manifest = manifest.dump();
    if (auto saved = Save(upload); !saved)
      return std::unexpected(saved.error());
  }
  upload.state = "completed";
  upload.data.clear();
  manifest["diagnostic"] = "";
  for (auto& part : manifest["parts"])
    part["body"] = "";
  upload.manifest = manifest.dump();
  if (auto saved = Save(upload); !saved)
    return std::unexpected(saved.error());
  return Status(upload, manifest);
}
}  // namespace fidoback::service
