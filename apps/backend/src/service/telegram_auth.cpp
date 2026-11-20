#include "service/telegram_auth.hpp"

#include <openssl/evp.h>

#include <charconv>
#include <map>
#include <memory>
#include <nlohmann/json.hpp>
#include <optional>
#include <string>

namespace fidoback::service {
namespace {
int Hex(char c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}
std::optional<std::string> Decode(std::string_view value) {
  std::string result;
  for (size_t i = 0; i < value.size(); ++i) {
    char c = value[i];
    if (c == '%') {
      if (i + 2 >= value.size() || Hex(value[i + 1]) < 0 || Hex(value[i + 2]) < 0)
        return {};
      c = static_cast<char>(Hex(value[i + 1]) * 16 + Hex(value[i + 2]));
      i += 2;
    } else if (c == '+')
      c = ' ';
    if (c == '\0' || c == '\r' || c == '\n')
      return {};
    result += c;
  }
  return result;
}
}  // namespace
TelegramPublicKey TelegramKey(bool test_environment) {
  const std::string_view hex = test_environment ? "40055058a4ee38156a06562e52eece92a771bcd8346a8c4615cb7376eddf72ec"
                                                : "e7bf03a2fa4602af4580703d88dda5bb59f32ed8b02a56c187fe7d34caed242d";
  TelegramPublicKey result{};
  for (size_t i = 0; i < result.size(); ++i)
    result[i] = static_cast<unsigned char>(Hex(hex[2 * i]) * 16 + Hex(hex[2 * i + 1]));
  return result;
}
std::expected<int64_t, domain::ApiError> VerifyTelegramProof(std::string_view data, const TelegramConfig& config,
                                                             int64_t now, const TelegramPublicKey& key) {
  auto fail = [] { return std::unexpected(domain::ApiError::Unauthorized("Invalid Telegram credentials")); };
  if (data.size() > 8192)
    return std::unexpected(domain::ApiError{domain::ErrorCode::kResource, "Telegram request too large", {}});
  if (config.bot_id <= 0 || data.empty() || now < 0 || config.max_age_seconds < 1 || config.clock_skew_seconds < 0)
    return fail();
  std::map<std::string, std::string> fields;
  while (!data.empty()) {
    const auto end = data.find('&');
    const auto part = data.substr(0, end);
    const auto equal = part.find('=');
    if (equal == std::string_view::npos)
      return fail();
    auto name = Decode(part.substr(0, equal));
    auto value = Decode(part.substr(equal + 1));
    if (!name || name->empty() || !value || !fields.emplace(*name, *value).second || fields.size() > 64)
      return fail();
    if (end == std::string_view::npos)
      break;
    data.remove_prefix(end + 1);
    if (data.empty())
      return fail();
  }
  if (!fields.contains("auth_date") || !fields.contains("signature") || !fields.contains("user"))
    return fail();
  int64_t date = 0;
  const auto& date_text = fields.at("auth_date");
  auto parsed = std::from_chars(date_text.data(), date_text.data() + date_text.size(), date);
  if (parsed.ec != std::errc{} || parsed.ptr != date_text.data() + date_text.size() || date < 0 ||
      (date > now && date - now > config.clock_skew_seconds) || (now > date && now - date > config.max_age_seconds))
    return fail();
  std::string check = std::to_string(config.bot_id) + ":WebAppData";
  for (const auto& [name, value] : fields)
    if (name != "hash" && name != "signature")
      check += "\n" + name + "=" + value;
  std::string signature = fields.at("signature");
  // 64 bytes have exactly 86 base64url digits and optional '==' padding.
  if (signature.size() == 88 && signature.ends_with("=="))
    signature.resize(86);
  if (signature.size() != 86)
    return fail();
  for (char& c : signature) {
    if (c == '-')
      c = '+';
    else if (c == '_')
      c = '/';
    else if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')))
      return fail();
  }
  signature += "==";
  std::array<unsigned char, 66> bytes{};
  if (EVP_DecodeBlock(bytes.data(), reinterpret_cast<const unsigned char*>(signature.data()),
                      static_cast<int>(signature.size())) != 66)
    return fail();
  std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> public_key(
      EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, nullptr, key.data(), key.size()), EVP_PKEY_free);
  std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(), EVP_MD_CTX_free);
  if (!public_key || !ctx || EVP_DigestVerifyInit(ctx.get(), nullptr, nullptr, nullptr, public_key.get()) != 1 ||
      EVP_DigestVerify(ctx.get(), bytes.data(), 64, reinterpret_cast<const unsigned char*>(check.data()),
                       check.size()) != 1)
    return fail();
  try {
    const auto user = nlohmann::json::parse(fields.at("user"));
    if (!user.is_object() || !user.contains("id") || !user.at("id").is_number_integer())
      return fail();
    if (user.at("id").is_number_unsigned() && user.at("id").get<uint64_t>() > INT64_MAX)
      return fail();
    const auto id = user.at("id").get<int64_t>();
    if (id <= 0)
      return fail();
    return id;
  } catch (const nlohmann::json::exception&) {
    return fail();
  }
}
}  // namespace fidoback::service
