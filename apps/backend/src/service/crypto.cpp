#include "service/crypto.hpp"

#include <openssl/evp.h>

#include <memory>
namespace fidoback::service {
std::expected<storage::TokenDigest, domain::ApiError> Sha256(std::string_view bytes) {
  // Resolve the provider once with C++ static initialization synchronization.
  // Per-request digest contexts use the immutable fetched algorithm directly.
  static const std::unique_ptr<EVP_MD, decltype(&EVP_MD_free)> method(EVP_MD_fetch(nullptr, "SHA256", nullptr),
                                                                      EVP_MD_free);
  storage::TokenDigest digest{};
  unsigned int length = 0;
  if (!method || EVP_Digest(bytes.data(), bytes.size(), digest.data(), &length, method.get(), nullptr) != 1 ||
      length != digest.size())
    return std::unexpected(domain::ApiError::Server("Digest processing failed"));
  return digest;
}
}  // namespace fidoback::service
