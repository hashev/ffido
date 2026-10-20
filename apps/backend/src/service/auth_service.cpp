#include "service/auth_service.hpp"

#include <fcntl.h>
#include <openssl/crypto.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>

#include "service/crypto.hpp"
#include "service/jam_mapping.hpp"
#include "storage/text_codec.hpp"
namespace fidoback::service {
namespace {
int64_t Now() {
  return std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count();
}
bool TokenFormat(std::string_view token) {
  return token.size() == 64 && token.find_first_not_of("0123456789abcdef") == std::string_view::npos;
}
}  // namespace
bool ValidFtnAddress(std::string_view address) {
  return domain::CanonicalFtnAddress(address).has_value();
}
int64_t AuthService::CurrentTime() const {
  return clock_ ? clock_() : Now();
}
std::expected<std::string, domain::ApiError> LoadSessionKey(const std::filesystem::path& path) {
  auto fail = [] {
    return std::unexpected(domain::ApiError::Server("Session key unavailable or insecure permissions"));
  };
  if (path.empty())
    return fail();
  int fd = open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  if (fd < 0 && errno == ENOENT) {
    std::array<unsigned char, 32> key{};
    if (RAND_bytes(key.data(), key.size()) != 1)
      return fail();
    fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0)
      return fail();
    const bool saved = write(fd, key.data(), key.size()) == static_cast<ssize_t>(key.size()) && fsync(fd) == 0;
    close(fd);
    if (!saved) {
      unlink(path.c_str());
      return fail();
    }
    return std::string(reinterpret_cast<const char*>(key.data()), key.size());
  }
  if (fd < 0)
    return fail();
  struct stat st{};
  std::array<char, 33> key{};
  const bool secure = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == geteuid() && (st.st_mode & 077) == 0 &&
                      st.st_nlink == 1 && st.st_size == 32;
  const auto length = secure ? read(fd, key.data(), key.size()) : -1;
  close(fd);
  if (length != 32)
    return fail();
  return std::string(key.data(), 32);
}
std::expected<void, domain::ApiError> AuthService::Configure(HptCredentials credentials, std::string_view key) {
  if (key.size() != 32)
    return std::unexpected(domain::ApiError::Server("Invalid session key"));
  std::map<std::string, storage::TokenDigest> fingerprints;
  for (const auto& [address, password] : credentials) {
    auto canonical = domain::CanonicalFtnAddress(address);
    if (!canonical || *canonical != address)
      return std::unexpected(domain::ApiError::Server("Invalid HPT identity"));
    if (password.empty())
      continue;
    auto bytes = address + std::string(1, '\0') + password;
    storage::TokenDigest digest{};
    unsigned length = 0;
    if (!HMAC(EVP_sha256(), key.data(), static_cast<int>(key.size()),
              reinterpret_cast<const unsigned char*>(bytes.data()), bytes.size(), digest.data(), &length) ||
        length != digest.size())
      return std::unexpected(domain::ApiError::Server("Credential fingerprint failed"));
    fingerprints.emplace(address, digest);
  }
  auto synced = metadata_->SyncCredentials(fingerprints);
  if (!synced)
    return synced;
  credentials_ = std::move(credentials);
  fingerprints_ = std::move(fingerprints);
  return {};
}
std::expected<LoginResult, domain::ApiError> AuthService::Login(std::string_view name, std::string_view address,
                                                                std::string_view password) {
  if (name.empty() || name.find_first_not_of(" \t") == std::string_view::npos || name.size() > 256 ||
      name.find_first_of("\0\r\n", 0, 3) != std::string_view::npos || !storage::ConvertText(name, "UTF-8", "UTF-8"))
    return std::unexpected(domain::ApiError::Validation({{"name", "Укажите имя длиной до 256 байт"}}));
  auto canonical = domain::CanonicalFtnAddress(address);
  if (!canonical)
    return std::unexpected(domain::ApiError::Validation({{"address", "Укажите FTN-адрес zone:net/node.point"}}));
  const auto entry = credentials_.find(*canonical);
  // Hash first to compare a fixed number of bytes regardless of matching prefix.
  const auto given = Sha256(password);
  const auto expected = Sha256(entry == credentials_.end() ? "" : entry->second);
  if (!given || !expected)
    return std::unexpected(domain::ApiError::Server("Credential verification failed"));
  if (entry == credentials_.end() || entry->second.empty() || password.empty() || password.size() > 4096 ||
      CRYPTO_memcmp(given->data(), expected->data(), given->size()) != 0)
    return std::unexpected(domain::ApiError::Unauthorized("Invalid credentials"));
  std::array<unsigned char, 32> bytes{};
  if (RAND_bytes(bytes.data(), bytes.size()) != 1)
    return std::unexpected(domain::ApiError::Server("Session generation failed"));
  std::string token;
  constexpr char hex[] = "0123456789abcdef";
  for (auto byte : bytes) {
    token += hex[byte >> 4];
    token += hex[byte & 15];
  }
  const auto digest = Digest(token);
  if (!digest)
    return std::unexpected(digest.error());
  const auto now = CurrentTime();
  const auto user = metadata_->CreateSession(*canonical, name, UtcDate(static_cast<uint32_t>(now)), *digest,
                                             fingerprints_.at(*canonical), now + 30 * 24 * 3600);
  if (!user)
    return std::unexpected(user.error());
  return LoginResult{std::move(token), *user};
}
std::expected<storage::TokenDigest, domain::ApiError> AuthService::Digest(std::string_view token) {
  if (!TokenFormat(token))
    return std::unexpected(domain::ApiError::Unauthorized("Invalid access token"));
  return Sha256(token);
}
std::expected<storage::AuthenticatedUser, domain::ApiError> AuthService::ValidateToken(std::string_view token) const {
  auto digest = Digest(token);
  if (!digest)
    return std::unexpected(digest.error());
  auto identity = metadata_->AuthenticateToken(*digest, CurrentTime());
  if (!identity)
    return identity;
  if (!ValidFtnAddress(identity->profile.address))
    return std::unexpected(domain::ApiError::Unauthorized("Invalid access token"));
  return identity;
}
std::expected<std::string, domain::ApiError> AuthService::Provision(std::string_view user,
                                                                    const domain::Profile& profile,
                                                                    int64_t expires_at) {
  if (user.empty() || user.size() > 128 || user.find_first_of("\0\r\n", 0, 3) != std::string_view::npos ||
      profile.name.empty() || profile.name.size() > 256 ||
      profile.name.find_first_of("\0\r\n", 0, 3) != std::string::npos ||
      !storage::ConvertText(profile.name, "UTF-8", "UTF-8") || !ValidFtnAddress(profile.address) || expires_at <= Now())
    return std::unexpected(domain::ApiError::Validation("Invalid assigned user profile or expiry"));
  std::array<unsigned char, 32> bytes{};
  if (RAND_bytes(bytes.data(), bytes.size()) != 1)
    return std::unexpected(domain::ApiError::Server("Token generation failed"));
  constexpr char hex[] = "0123456789abcdef";
  std::string token;
  token.reserve(64);
  for (auto byte : bytes) {
    token += hex[byte >> 4];
    token += hex[byte & 15];
  }
  auto digest = Digest(token);
  if (!digest)
    return std::unexpected(digest.error());
  auto saved = metadata_->ProvisionToken(user, profile, *digest, expires_at);
  if (!saved)
    return std::unexpected(saved.error());
  return token;
}
std::expected<void, domain::ApiError> AuthService::Revoke(std::string_view token) {
  auto digest = Digest(token);
  if (!digest)
    return std::unexpected(digest.error());
  return metadata_->RevokeToken(*digest);
}
std::expected<std::string, domain::ApiError> AuthService::ExtractBearerToken(std::string_view header) {
  constexpr std::string_view prefix = "Bearer ";
  if (!header.starts_with(prefix) || !TokenFormat(header.substr(prefix.size())))
    return std::unexpected(domain::ApiError::Unauthorized("Invalid access token"));
  return std::string(header.substr(prefix.size()));
}
}  // namespace fidoback::service
