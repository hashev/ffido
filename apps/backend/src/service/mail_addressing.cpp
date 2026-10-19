#include "service/mail_addressing.hpp"

#include <algorithm>
#include <charconv>
#include <map>
#include <sstream>

#include "domain/ftn_address.hpp"
#include "service/crypto.hpp"

namespace fidoback::service {
namespace {
std::string Fold(std::string value) {
  for (auto& c : value)
    if (c >= 'a' && c <= 'z')
      c -= 'a' - 'A';
  return value;
}
std::string Packed(std::initializer_list<std::string_view> fields) {
  std::string result;
  for (auto value : fields) {
    result += std::to_string(value.size());
    result += ':';
    result += value;
  }
  return result;
}
}  // namespace
std::expected<MailEnvelope, domain::ApiError> InspectMail(const msgapi::JamMessage& message,
                                                          const std::set<std::string>& managed,
                                                          const std::set<std::string>& own,
                                                          const std::set<std::string>& links) {
  const auto failure = [] {
    return std::unexpected(domain::ApiError::Validation("Netmail addressing requires quarantine"));
  };
  auto origin = domain::CanonicalFtnAddress(message.origin_address()),
       destination = domain::CanonicalFtnAddress(message.dest_address());
  const auto id = message.msg_id();
  if (!origin || !destination || id.empty() || id.size() > 1024 ||
      id.find_first_of("\r\n\0", 0, 3) != std::string::npos)
    return failure();
  if (!storage::ConvertText(id, "UTF-8", "UTF-8") ||
      std::any_of(id.begin(), id.end(), [](unsigned char c) { return c < 0x20 || c == 0x7f; }))
    return failure();
  std::map<std::string, std::string> addresses;
  size_t total = 0;
  for (const auto& field : message.subfields()) {
    if ((total += field.data().size()) > 65536)
      return failure();
    if (field.high_id() != 0)
      continue;
    if (field.type() == msgapi::JamSubFieldType::kOAddress || field.type() == msgapi::JamSubFieldType::kDAddress) {
      auto value = domain::CanonicalFtnAddress(field.ToString());
      if (!value || *value != (field.type() == msgapi::JamSubFieldType::kOAddress ? *origin : *destination))
        return failure();
    }
    if (field.type() != msgapi::JamSubFieldType::kFtsKludge)
      continue;
    const auto text = field.ToString();
    const auto space = text.find_first_of(" :\t");
    if (space == std::string::npos)
      continue;
    const auto key = Fold(text.substr(0, space));
    if (key != "INTL" && key != "TOPT" && key != "FMPT")
      continue;
    if (text.size() > 256)
      return failure();
    const auto begin = text.find_first_not_of(" :\t", space);
    if (begin == std::string::npos || !addresses.emplace(key, text.substr(begin)).second)
      return failure();
  }
  auto point = [](const std::string& address) {
    const auto dot = address.find('.');
    return dot == std::string::npos ? std::string("0") : address.substr(dot + 1);
  };
  for (auto key : {"TOPT", "FMPT"}) {
    auto found = addresses.find(key);
    if (found == addresses.end())
      continue;
    uint32_t value = 0;
    const auto& text = found->second;
    auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value);
    if (error != std::errc{} || end != text.data() + text.size() || value > 65535 ||
        std::to_string(value) != point(key == std::string_view("TOPT") ? *destination : *origin))
      return failure();
  }
  if (addresses.contains("INTL")) {
    std::istringstream input(addresses.at("INTL"));
    std::string to, from, extra;
    input >> to >> from;
    if (input >> extra)
      return failure();
    auto a = domain::CanonicalFtnAddress(to), b = domain::CanonicalFtnAddress(from);
    auto boss = [](const std::string& address) { return address.substr(0, address.find('.')); };
    if (!a || !b || a->find('.') != std::string::npos || b->find('.') != std::string::npos ||
        *a != boss(*destination) || *b != boss(*origin))
      return failure();
  }
  auto delivery = Sha256(Packed({*origin, *destination, id}));
  std::string payload = Packed({*origin, *destination, id, message.sender_name(), message.receiver_name(),
                                message.subject(), message.text(), message.reply_id()});
  // Via is a transport trace, not part of the delivered content's identity.
  for (const auto& field : message.subfields()) {
    if (field.type() != msgapi::JamSubFieldType::kFtsKludge)
      continue;
    auto text = field.ToString();
    auto upper = Fold(text);
    if (upper.starts_with("VIA ") || upper.starts_with("VIA:") || upper.starts_with("FLAGS ") ||
        upper.starts_with("FLAGS:"))
      continue;
    payload += Packed({text});
  }
  auto hash = Sha256(payload);
  if (!delivery || !hash)
    return failure();
  MailEnvelope envelope{*origin, *destination, id, MailRecipient::kTransit, *delivery, *hash};
  if (managed.contains(*destination))
    envelope.recipient = MailRecipient::kManaged;
  else if (own.contains(*destination))
    envelope.recipient = MailRecipient::kBoss;
  else if (links.contains(*destination))
    envelope.recipient = MailRecipient::kOrdinary;
  return envelope;
}
}  // namespace fidoback::service
