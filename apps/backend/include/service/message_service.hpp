#pragma once
#include <array>
#include <atomic>
#include <expected>
#include <map>
#include <memory>
#include <mutex>
#include <string_view>
#include <vector>

#include "domain/archive.hpp"
#include "domain/error.hpp"
#include "domain/message.hpp"
#include "domain/pagination.hpp"
#include "service/echo_access.hpp"
#include "storage/jam_access.hpp"
#include "storage/jam_writer.hpp"
#include "storage/metadata_store.hpp"
namespace fidoback::service {
struct UuePublishOptions {
  std::string kludge, msgid, generation, from_name, from_address, to_name, to_address;
  bool freeze_recipient = false;
};
struct CrosspostPublishOptions {
  domain::Profile profile;
  std::string generation, msgid, to_name, to_address;
};
class MessageService {
public:
  MessageService(std::shared_ptr<storage::JamCatalog> catalog, std::shared_ptr<storage::IMetadataStore> metadata,
                 std::shared_ptr<const EchoAccess> access, std::string encoding = "cp866",
                 std::shared_ptr<storage::JamIo> io = std::make_shared<storage::JamIo>())
      : catalog_(std::move(catalog)),
        metadata_(std::move(metadata)),
        access_(std::move(access)),
        encoding_(std::move(encoding)),
        writer_(metadata_, std::move(io)) {
  }
  std::expected<domain::MessageListResponse, domain::ApiError> GetMessages(
      std::string_view conference, const domain::PaginationRequest& page, std::string_view sort, std::string_view user,
      std::string_view query = {}, std::string_view anchor_message_id = {}, bool respect_filters = false);
  std::expected<domain::MessageDetail, domain::ApiError> GetMessage(std::string_view conference,
                                                                    std::string_view message, std::string_view user);
  std::expected<domain::ArchiveSearchResponse, domain::ApiError> SearchArchive(
      const domain::ArchiveSearchRequest& request, std::string_view user);
  void SetArchiveScanBudgetForTesting(size_t budget, size_t max_hits = 100000, int ttl_seconds = 600) {
    archive_scan_budget_ = budget;
    archive_max_hits_ = max_hits;
    archive_ttl_ = std::chrono::seconds(ttl_seconds);
  }
  std::expected<domain::ArchiveMessage, domain::ApiError> ReadArchiveMessage(std::string_view conference,
                                                                             std::string_view message,
                                                                             std::string_view user,
                                                                             uint64_t body_offset, uint32_t body_limit,
                                                                             bool reveal = false);
  std::expected<domain::ThreadListResponse, domain::ApiError> GetArchiveThread(
      std::string_view conference, std::string_view message, std::string_view user,
      const domain::PaginationRequest& page = {});
  std::expected<domain::MessageTechnicalData, domain::ApiError> GetMessageTechnicalData(std::string_view conference,
                                                                                        std::string_view message,
                                                                                        std::string_view user);
  std::expected<domain::FindMessageResponse, domain::ApiError> FindMessage(
      std::string_view conference, std::string_view query, int scope, std::string_view sort, std::string_view start,
      bool include_start, std::string_view user, bool respect_filters = false);
  std::expected<domain::PersonalMessageFilterSet, domain::ApiError> GetPersonalFilters(std::string_view user);
  std::expected<uint64_t, domain::ApiError> ReplacePersonalFilters(std::string_view user, uint64_t expected,
                                                                   std::string_view operation,
                                                                   std::vector<domain::PersonalMessageFilter> rules);
  std::expected<domain::MessagePresentation, domain::ApiError> GetPresentation(std::string_view conference,
                                                                               std::string_view id,
                                                                               std::string_view user, bool reveal,
                                                                               std::string_view query = {},
                                                                               int scope = 0);
  // Read without changing read status, history or reading position (attachment indexing).
  std::expected<domain::MessageDetail, domain::ApiError> PeekMessage(std::string_view conference,
                                                                     std::string_view message, std::string_view user);
  std::expected<domain::CreateMessageResponse, domain::ApiError> CreateMessage(
      std::string_view conference, const domain::CreateMessageRequest& request, std::string_view user,
      const UuePublishOptions* uue = nullptr, bool validate_only = false,
      const CrosspostPublishOptions* crosspost = nullptr);
  std::expected<domain::CreateCrosspostResponse, domain::ApiError> CreateCrosspost(
      std::string_view conference, const domain::CreateMessageRequest& request, std::vector<std::string> additional,
      std::string_view user);
  std::expected<storage::BulkReadResult, domain::ApiError> MarkConferenceRead(std::string_view conference,
                                                                              std::string_view operation,
                                                                              std::string_view user);
  std::expected<void, domain::ApiError> MarkAsRead(std::string_view conference, std::string_view message,
                                                   std::string_view user);
  std::expected<void, domain::ApiError> MarkAsUnread(std::string_view conference, std::string_view message,
                                                     std::string_view user);
  std::expected<domain::ThreadListResponse, domain::ApiError> GetThread(std::string_view conference,
                                                                        std::string_view thread, std::string_view user,
                                                                        const domain::PaginationRequest& page = {},
                                                                        bool respect_filters = false,
                                                                        bool headers_only = false);

private:
  struct ArchiveFingerprint {
    std::string generation;
    uint32_t mod_counter = 0;
    std::array<int64_t, 21> files{};
    bool operator==(const ArchiveFingerprint&) const = default;
  };
  struct ArchiveHit {
    uint32_t date = 0, number = 0;
    size_t area = 0;
  };
  struct ArchiveScan {
    std::mutex mutex;
    std::atomic<bool> retired{false};
    std::shared_ptr<std::atomic<size_t>> budget;
    size_t base_bytes = 0, reserved_bytes = 0;
    bool Reserve(size_t bytes) {
      if (bytes > 32 * 1024 * 1024)
        return false;
      if (bytes <= reserved_bytes)
        return true;
      const auto extra = bytes - reserved_bytes;
      auto total = budget->load();
      do {
        if (total > 128 * 1024 * 1024 - extra)
          return false;
      } while (!budget->compare_exchange_weak(total, total + extra));
      reserved_bytes = bytes;
      return true;
    }
    ~ArchiveScan() {
      if (budget)
        budget->fetch_sub(reserved_bytes);
    }

    domain::ArchiveSearchRequest request;
    std::string user;
    uint64_t filters_revision = 0;
    std::vector<ArchiveFingerprint> fingerprints;
    std::vector<ArchiveHit> hits;
    size_t area = 0, number = 0, page = 0;
    bool sorted = false;
    std::chrono::steady_clock::time_point expires;
  };
  static std::expected<ArchiveFingerprint, domain::ApiError> Fingerprint(storage::JamAccess& access);
  std::mutex archive_mutex_;
  std::map<std::string, std::shared_ptr<ArchiveScan>> archive_scans_;
  std::shared_ptr<std::atomic<size_t>> archive_bytes_ = std::make_shared<std::atomic<size_t>>(0);
  size_t archive_scan_budget_ = 100000, archive_max_hits_ = 100000;
  std::chrono::seconds archive_ttl_{600};
  std::expected<domain::MessageDetail, domain::ApiError> FilteredDetail(storage::JamAccess& access,
                                                                        std::string_view conference, uint32_t number,
                                                                        std::string_view user,
                                                                        const domain::PersonalMessageFilterSet* filters,
                                                                        bool body = true);
  std::expected<domain::MessageDetail, domain::ApiError> Detail(storage::JamAccess& access, std::string_view conference,
                                                                uint32_t number, std::string_view user,
                                                                bool body = true);
  std::expected<void, domain::ApiError> RecordView(storage::JamAccess& access, std::string_view conference,
                                                   uint32_t number, std::string_view user,
                                                   domain::MessageDetail& detail);
  std::shared_ptr<storage::JamCatalog> catalog_;
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::shared_ptr<const EchoAccess> access_;
  std::string encoding_;
  storage::JamWriter writer_;
};
}  // namespace fidoback::service
