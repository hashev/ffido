#pragma once
#include <expected>
#include <functional>
#include <memory>
#include <string_view>

#include "service/hpt_auth.hpp"
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
  std::expected<storage::AuthenticatedUser, domain::ApiError> ValidateToken(std::string_view token) const;
  std::expected<std::string, domain::ApiError> Provision(std::string_view user, const domain::Profile& profile,
                                                         int64_t expires_at);
  std::expected<void, domain::ApiError> Revoke(std::string_view token);
  static std::expected<std::string, domain::ApiError> ExtractBearerToken(std::string_view header);

private:
  static std::expected<storage::TokenDigest, domain::ApiError> Digest(std::string_view token);
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::map<std::string, storage::TokenDigest> fingerprints_;
  HptCredentials credentials_;
  std::function<int64_t()> clock_;
  int64_t CurrentTime() const;
};
}  // namespace fidoback::service
