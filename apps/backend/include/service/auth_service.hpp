#pragma once
#include <expected>
#include <functional>
#include <memory>
#include <optional>
#include <string_view>

#include "service/hpt_auth.hpp"
#include "service/telegram_auth.hpp"
#include "storage/metadata_store.hpp"
namespace fidoback::service {
bool ValidFtnAddress(std::string_view address);
struct LoginResult {
  std::string token;
  storage::AuthenticatedUser user;
};
std::expected<std::string, domain::ApiError> LoadSessionKey(const std::filesystem::path& path);
class AuthService {
public:
  explicit AuthService(std::shared_ptr<storage::IMetadataStore> metadata) : metadata_(std::move(metadata)) {
  }
  std::expected<void, domain::ApiError> Configure(HptCredentials credentials, std::string_view key);
  std::expected<LoginResult, domain::ApiError> Login(std::string_view name, std::string_view address,
                                                     std::string_view password);
  void SetClockForTesting(std::function<int64_t()> clock) {
    clock_ = std::move(clock);
  }
  void SetTelegramKeyForTesting(TelegramPublicKey key) {
    telegram_test_key_ = key;
  }
  std::expected<storage::AuthenticatedUser, domain::ApiError> ValidateToken(std::string_view token) const;
  std::expected<std::string, domain::ApiError> Provision(std::string_view user, const domain::Profile& profile,
                                                         int64_t expires_at);
  std::expected<void, domain::ApiError> Revoke(std::string_view token);
  void ConfigureTelegram(TelegramConfig config) {
    telegram_ = config;
  }
  bool SupportsTelegram() const {
    return telegram_.bot_id > 0;
  }
  std::expected<int64_t, domain::ApiError> TelegramUser(std::string_view data) const;
  std::expected<std::vector<storage::AuthenticatedUser>, domain::ApiError> TelegramProfiles(std::string_view data);
  std::expected<LoginResult, domain::ApiError> TelegramLogin(std::string_view data, std::string_view address);
  std::expected<void, domain::ApiError> BindTelegram(const storage::AuthenticatedUser& user, std::string_view data,
                                                     std::string_view password, bool replace);
  static std::expected<std::string, domain::ApiError> ExtractBearerToken(std::string_view header);

private:
  static std::expected<storage::TokenDigest, domain::ApiError> Digest(std::string_view token);
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::map<std::string, storage::TokenDigest> fingerprints_;
  HptCredentials credentials_;
  TelegramConfig telegram_;
  std::optional<TelegramPublicKey> telegram_test_key_;
  std::function<int64_t()> clock_;
  int64_t CurrentTime() const;
};
}  // namespace fidoback::service
