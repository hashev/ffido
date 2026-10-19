#pragma once

#include <chrono>
#include <map>
#include <mutex>
#include <optional>

#include "AppConfig.h"
#include "ftn/uue_metadata.hpp"
#include "service/message_service.hpp"

namespace fidoback::service {
struct UueReference {
  std::string conference, message;
  uint32_t block = 0;
  bool operator==(const UueReference&) const = default;
};
struct UuePart {
  UueReference source;
  std::string from, to, subject, filename, diagnostic, date;
  std::optional<ftn::uue::Metadata> metadata;
  uint32_t part = 1, total = 1, begin = 0, end = 0;
  int direction = 0;
};
struct UueSearch {
  std::vector<UuePart> parts;
  std::string generation;
  uint32_t next = 0;
  bool more = false;
};
enum class UueState { kReady = 1, kIncomplete = 2, kConflict = 3, kCorrupt = 4 };
struct UueAttachment {
  std::string id, filename, sha256, diagnostic;
  uint64_t size = 0;
  bool verified = false;
  UueState state = UueState::kIncomplete;
  std::vector<uint32_t> missing;
  std::vector<UueReference> sources;
};
struct UueSendStatus {
  std::string operation, state, conference, diagnostic, filename, sha256;
  uint64_t file_size = 0;
  uint32_t total = 0, saved = 0;
  std::vector<std::string> messages;
};
struct UueChunk {
  std::string bytes;
  uint64_t offset = 0, size = 0;
  bool eof = false;
};
class UueService {
public:
  UueService(std::shared_ptr<storage::JamCatalog> catalog, std::shared_ptr<storage::IMetadataStore> metadata,
             std::shared_ptr<const EchoAccess> access, std::string encoding = "cp866",
             std::function<std::chrono::steady_clock::time_point()> clock = std::chrono::steady_clock::now,
             UueConfig config = {}, std::shared_ptr<storage::JamIo> io = std::make_shared<storage::JamIo>())
      : catalog_(std::move(catalog)),
        metadata_(std::move(metadata)),
        access_(std::move(access)),
        encoding_(std::move(encoding)),
        messages_(catalog_, metadata_, access_, encoding_, std::move(io)),
        clock_(std::move(clock)),
        config_(config) {
  }
  std::expected<UueSearch, domain::ApiError> Search(std::string_view conference, std::string_view generation,
                                                    uint32_t after, uint32_t limit, std::string_view user);
  std::expected<UueAttachment, domain::ApiError> Assemble(const std::vector<UueReference>& sources, bool explicit_order,
                                                          std::string_view user);
  std::expected<UueChunk, domain::ApiError> Chunk(std::string_view id, uint64_t offset, uint32_t max_bytes,
                                                  std::string_view user);

  const UueConfig& config() const {
    return config_;
  }
  std::expected<uint64_t, domain::ApiError> Upload(std::string_view operation, std::string_view filename, uint64_t size,
                                                   std::string_view sha256, uint64_t offset, std::string_view bytes,
                                                   std::string_view user);
  std::expected<UueSendStatus, domain::ApiError> Commit(std::string_view conference,
                                                        const domain::CreateMessageRequest& request,
                                                        std::string_view user);
  std::expected<UueSendStatus, domain::ApiError> SendStatus(std::string_view operation, std::string_view user);

private:
  ftn::uue::Limits CodecLimits() const {
    return {static_cast<size_t>(config_.max_file_bytes), static_cast<size_t>(config_.max_file_bytes * 2 + 4096),
            config_.max_parts};
  }
  std::expected<void, domain::ApiError> Save(storage::UueUpload& upload);
  std::array<std::timed_mutex, 64> send_mutexes_;
  struct CachedIndex {
    std::vector<UuePart> parts;
    std::chrono::steady_clock::time_point expires;
  };
  struct CachedFile {
    UueAttachment attachment;
    std::string user, bytes;
    std::vector<std::string> fingerprints;
    std::chrono::steady_clock::time_point expires;
  };
  std::expected<std::vector<UuePart>, domain::ApiError> Parts(std::string_view conference,
                                                              const domain::MessageDetail& message);
  std::expected<std::string, domain::ApiError> Fingerprint(const domain::MessageDetail& message);
  void Prune();
  std::shared_ptr<storage::JamCatalog> catalog_;
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::shared_ptr<const EchoAccess> access_;
  std::string encoding_;
  MessageService messages_;
  std::function<std::chrono::steady_clock::time_point()> clock_;
  UueConfig config_;
  std::mutex mutex_;
  std::map<std::string, CachedIndex> index_;
  std::map<std::string, CachedFile> files_;
};
}  // namespace fidoback::service
