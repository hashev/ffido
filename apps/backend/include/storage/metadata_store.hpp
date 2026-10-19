#pragma once

#include <sqlite3.h>

#include <expected>
#include <filesystem>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "domain/bookmark.hpp"
#include "domain/error.hpp"
#include "domain/history.hpp"
#include "domain/profile.hpp"
#include "storage/mail_transfer.hpp"
#include "storage/operation.hpp"
#include "storage/read_key.hpp"
#include "storage/token_record.hpp"
#include "storage/uue_upload.hpp"

namespace fidoback::storage {

/// @brief Абстрактный интерфейс для хранения метаданных.
/// @thread_safety Потокобезопасен (internal mutex).
struct BulkReadResult {
  int64_t marked_count = 0, snapshot_count = 0;
  std::string generation;
};
struct ReadingPosition {
  std::string generation, message;
  uint64_t revision = 0;
};
struct MailboxBinding {
  std::string address, base, generation, files;
};
class IMetadataStore {
public:
  virtual ~IMetadataStore() = default;

  virtual std::expected<std::vector<MailboxBinding>, domain::ApiError> MailboxBindings() = 0;
  virtual std::expected<void, domain::ApiError> BindMailbox(const MailboxBinding& binding) = 0;

  virtual std::expected<MailTransfer, domain::ApiError> PrepareTransfer(const MailTransfer& transfer) = 0;
  virtual std::expected<std::vector<MailTransfer>, domain::ApiError> MailTransfers(bool include_done = true) = 0;
  virtual std::expected<void, domain::ApiError> SetTransferState(std::string_view source_key, TransferState state) = 0;

  virtual std::expected<int, domain::ApiError> ExportState() = 0;
  virtual std::expected<void, domain::ApiError> SetExportState(int expected, int next) = 0;
  virtual std::expected<std::string, domain::ApiError> MailboxUser(std::string_view address) = 0;
  virtual std::expected<int, domain::ApiError> MailDirection(ReadKey key) = 0;
  virtual std::expected<std::vector<Operation>, domain::ApiError> PendingOutbox() = 0;
  virtual std::expected<void, domain::ApiError> SetOutboxState(std::string_view user, std::string_view operation,
                                                               int state) = 0;

  virtual std::expected<std::optional<UueUpload>, domain::ApiError> GetUueUpload(std::string_view user,
                                                                                 std::string_view id) = 0;
  // Compare-and-swap revision and quota accounting are in one durable transaction.
  virtual std::expected<void, domain::ApiError> SaveUueUpload(const UueUpload& upload, uint64_t user_quota,
                                                              uint64_t global_quota) = 0;
  virtual std::expected<void, domain::ApiError> PruneUueUploads(int64_t older_than) = 0;

  // Bookmarks
  [[nodiscard]] virtual std::expected<std::vector<domain::Bookmark>, domain::ApiError> GetBookmarks(
      std::string_view user_id) = 0;
  [[nodiscard]] virtual std::expected<void, domain::ApiError> AddBookmark(std::string_view user_id,
                                                                          std::string_view conference_id) = 0;
  [[nodiscard]] virtual std::expected<void, domain::ApiError> RemoveBookmark(std::string_view user_id,
                                                                             std::string_view conference_id) = 0;
  [[nodiscard]] virtual std::expected<bool, domain::ApiError> IsBookmarked(std::string_view user_id,
                                                                           std::string_view conference_id) = 0;

  // History
  [[nodiscard]] virtual std::expected<std::vector<domain::HistoryEntry>, domain::ApiError> GetHistory(
      std::string_view user_id, int64_t limit = 50) = 0;
  [[nodiscard]] virtual std::expected<void, domain::ApiError> ClearHistory(std::string_view user_id) = 0;
  [[nodiscard]] virtual std::expected<void, domain::ApiError> AddToHistory(std::string_view user_id,
                                                                           std::string_view conference_id) = 0;

  virtual std::expected<std::optional<BulkReadResult>, domain::ApiError> FindBulkRead(std::string_view user,
                                                                                      std::string_view operation,
                                                                                      std::string_view conference) = 0;
  virtual std::expected<BulkReadResult, domain::ApiError> MarkConferenceRead(
      std::string_view user, std::string_view operation, std::string_view conference, std::string_view generation,
      const std::vector<uint32_t>& numbers, const std::function<bool()>& active = {}) = 0;

  // Read status
  [[nodiscard]] virtual std::expected<bool, domain::ApiError> IsMessageRead(std::string_view user_id, ReadKey key) = 0;
  [[nodiscard]] virtual std::expected<void, domain::ApiError> MarkMessageRead(std::string_view user_id,
                                                                              ReadKey key) = 0;
  [[nodiscard]] virtual std::expected<int64_t, domain::ApiError> GetReadCount(std::string_view user_id,
                                                                              std::string_view conference_id,
                                                                              std::string_view generation) = 0;

  virtual std::expected<ReadingPosition, domain::ApiError> RecordMessageView(std::string_view user, ReadKey key) = 0;

  virtual std::expected<ReadingPosition, domain::ApiError> LastOpened(std::string_view user,
                                                                      std::string_view conference) = 0;

  // Profile
  [[nodiscard]] virtual std::expected<domain::Profile, domain::ApiError> GetProfile(std::string_view user_id) = 0;
  [[nodiscard]] virtual std::expected<void, domain::ApiError> SaveProfile(std::string_view user_id,
                                                                          const domain::Profile& profile) = 0;

  virtual std::expected<void, domain::ApiError> ProvisionToken(std::string_view user, const domain::Profile& profile,
                                                               const TokenDigest& digest, int64_t expires_at) = 0;
  virtual std::expected<void, domain::ApiError> RevokeToken(const TokenDigest& digest) = 0;
  virtual std::expected<AuthenticatedUser, domain::ApiError> AuthenticateToken(const TokenDigest& digest,
                                                                               int64_t now) = 0;

  virtual std::expected<void, domain::ApiError> SyncCredentials(
      const std::map<std::string, TokenDigest>& fingerprints) = 0;
  virtual std::expected<AuthenticatedUser, domain::ApiError> CreateSession(
      std::string_view address, std::string_view name, std::string_view registered_at, const TokenDigest& digest,
      const TokenDigest& fingerprint, int64_t expires_at) = 0;
  virtual std::expected<void, domain::ApiError> RevokeUserSessions(std::string_view user) = 0;

  virtual std::expected<std::optional<Operation>, domain::ApiError> FindOperation(std::string_view user,
                                                                                  std::string_view id) = 0;
  // Only a committed send with the exact current JAM identity can supply a missing DADDRESS.
  virtual std::expected<std::string, domain::ApiError> GetCommittedRecipient(ReadKey key,
                                                                             std::string_view ftn_msgid) = 0;
  virtual std::expected<void, domain::ApiError> PrepareOperation(const Operation& operation) = 0;
  virtual std::expected<void, domain::ApiError> SetOperationState(std::string_view user, std::string_view id,
                                                                  OperationState state) = 0;
  virtual std::expected<std::vector<Operation>, domain::ApiError> PendingOperations() = 0;

  /// @brief Инициализирует БД (создаёт таблицы если нет).
  [[nodiscard]] virtual std::expected<void, domain::ApiError> Init() = 0;
};

/// @brief Фабрика SQLite хранилища.
[[nodiscard]] std::shared_ptr<IMetadataStore> CreateSQLiteStore(std::filesystem::path db_path);

}  // namespace fidoback::storage
