#pragma once
#include <atomic>
#include <chrono>
#include <map>
#include <memory>
#include <mutex>
#include <optional>

#include "AppConfig.h"
#include "ftn/uue_metadata.hpp"
#include "service/message_service.hpp"
#include "storage/measurements.hpp"

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
  std::shared_ptr<measurements::Bytes> observation;
  std::shared_ptr<void> reservation;
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

  // Map-owned and live immutable payload bytes, including readers after eviction.
  std::pair<uint64_t, uint64_t> CacheBytes();
  std::pair<uint64_t, uint64_t> CacheCapacityBytes();
  uint64_t TransientBytes();
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
  struct TransientBudget {
    std::mutex mutex;
    uint64_t bytes = 0;
    std::map<std::string, uint64_t> users;
  };
  struct TransientReservation {
    std::shared_ptr<TransientBudget> budget;
    std::string user;
    uint64_t bytes = 0;
    ~TransientReservation() {
      if (!bytes)
        return;
      std::lock_guard lock(budget->mutex);
      budget->bytes -= bytes;
      auto found = budget->users.find(user);
      found->second -= bytes;
      if (!found->second)
        budget->users.erase(found);
      measurements::Gauge(measurements::reserved_bytes, measurements::reserved_peak_bytes, budget->bytes);
    }
  };
  std::expected<std::shared_ptr<void>, domain::ApiError> Reserve(uint64_t bytes, std::string_view user);
  std::shared_ptr<TransientBudget> transient_ = std::make_shared<TransientBudget>();
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
    std::string user;
    std::shared_ptr<const std::string> bytes;
    std::vector<std::string> fingerprints;
    std::chrono::steady_clock::time_point expires;
  };
  std::expected<std::vector<UuePart>, domain::ApiError> Parts(std::string_view conference,
                                                              const domain::MessageDetail& message);
  std::expected<std::string, domain::ApiError> Fingerprint(const domain::MessageDetail& message);
  void Prune();
  std::pair<uint64_t, uint64_t> CacheUsage(bool capacity);
  std::shared_ptr<storage::JamCatalog> catalog_;
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::shared_ptr<const EchoAccess> access_;
  std::string encoding_;
  MessageService messages_;
  std::function<std::chrono::steady_clock::time_point()> clock_;
  UueConfig config_;
  std::atomic<uint64_t> in_flight_bytes_{0};
  std::mutex mutex_;
  std::map<std::string, CachedIndex> index_;
  std::map<std::string, CachedFile> files_;
  std::vector<std::pair<std::weak_ptr<const std::string>, std::string>> live_payloads_;
};
}  // namespace fidoback::service
