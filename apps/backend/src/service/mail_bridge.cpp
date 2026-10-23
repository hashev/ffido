#include "service/mail_bridge.hpp"

#include <map>
#include <stdexcept>

#include "service/crypto.hpp"
#include "service/mail_addressing.hpp"
#include "storage/point_mailbox.hpp"
namespace fidoback::service {
namespace {
using namespace storage;
constexpr uint32_t locked = static_cast<uint32_t>(msgapi::JamMessageAttribute::kLocked);
auto Deadline() {
  return std::chrono::steady_clock::now() + std::chrono::seconds(10);
}
template <class T>
T Value(std::expected<T, domain::ApiError> value) {
  if (!value)
    throw std::runtime_error("Mail bridge requires recovery");
  return std::move(*value);
}
void Require(std::expected<void, domain::ApiError> value) {
  if (!value)
    throw std::runtime_error("Mail bridge requires recovery");
}
std::unique_ptr<JamAccess> Open(const JamCatalog& catalog, std::string_view id, bool write,
                                const std::string& encoding) {
  auto opened = JamAccess::Open(catalog, id, write, Deadline(), {}, encoding);
  if (!opened)
    throw std::runtime_error("Mail bridge storage unavailable");
  return std::move(*opened);
}
std::string Hex(const TokenDigest& value) {
  constexpr char hex[] = "0123456789abcdef";
  std::string result;
  for (auto c : value) {
    result += hex[c >> 4];
    result += hex[c & 15];
  }
  return result;
}
struct Snapshot {
  msgapi::JamMessage message;
  TokenDigest hash{};
  uint32_t flags = 0;
  uint64_t header_offset = 0;
};
void Read(JamIo& io, int fd, std::span<uint8_t> bytes, uint64_t offset) {
  while (!bytes.empty()) {
    const auto n = io.Read(fd, bytes.data(), bytes.size(), static_cast<off_t>(offset));
    if (n <= 0 || static_cast<size_t>(n) > bytes.size())
      throw std::runtime_error("Mail bridge snapshot failed");
    bytes = bytes.subspan(static_cast<size_t>(n));
    offset += static_cast<size_t>(n);
  }
}
Snapshot Take(JamIo& io, JamAccess& access, uint32_t number) {
  const auto& base = access.messages().base_header();
  if (number < base.base_msg_num)
    throw std::runtime_error("Mail source identity changed");
  std::array<uint8_t, 8> index{};
  Read(io, access.files().descriptors[2], index, uint64_t(number - base.base_msg_num) * 8);
  const auto offset = msgapi::jam_wire::Get32(index.data() + 4);
  if (offset == UINT32_MAX)
    throw std::runtime_error("Mail source disappeared");
  std::array<uint8_t, 76> wire{};
  Read(io, access.files().descriptors[0], wire, offset);
  auto header = msgapi::jam_wire::Decode(wire);
  if (header.subfield_len > 65536 || header.txt_len > 1048576 || header.message_number != number)
    throw std::runtime_error("Invalid mail source limits");
  std::vector<uint8_t> fields(header.subfield_len), body(header.txt_len);
  Read(io, access.files().descriptors[0], fields, uint64_t(offset) + 76);
  Read(io, access.files().descriptors[1], body, header.offset);
  const auto flags = header.attribute;
  // Transport claim bits may change during recovery; the rest of the source is immutable.
  header.attribute = 0;
  wire = msgapi::jam_wire::Encode(header);
  std::string content(reinterpret_cast<const char*>(wire.data()), wire.size());
  if (!fields.empty())
    content.append(reinterpret_cast<const char*>(fields.data()), fields.size());
  if (!body.empty())
    content.append(reinterpret_cast<const char*>(body.data()), body.size());
  auto hash = Value(Sha256(content));
  auto message = access.messages().ReadMessage(number);
  return Snapshot{message ? std::move(*message) : msgapi::JamMessage{}, hash, flags, offset};
}
void Flags(JamIo& io, JamAccess& access, const Snapshot& snapshot, uint32_t before, uint32_t after) {
  std::array<uint8_t, 4> old{}, next{}, actual{};
  msgapi::jam_wire::Put32(old.data(), before);
  msgapi::jam_wire::Put32(next.data(), after);
  Read(io, access.files().descriptors[0], actual, snapshot.header_offset + 52);
  bool known = false;
  for (size_t split = 0; split <= 4; ++split)
    known |= std::equal(actual.begin(), actual.begin() + split, next.begin()) &&
             std::equal(actual.begin() + split, actual.end(), old.begin() + split);
  if (!known)
    throw std::runtime_error("Mail flag claim is ambiguous");
  size_t position = 0;
  while (position < 4) {
    auto n = io.Write(access.files().descriptors[0], next.data() + position, 4 - position,
                      static_cast<off_t>(snapshot.header_offset + 52 + position));
    if (n <= 0 || static_cast<size_t>(n) > 4 - position)
      throw std::runtime_error("Mail flag claim requires recovery");
    position += static_cast<size_t>(n);
  }
  if (io.Sync(access.files().descriptors[0]) != 0)
    throw std::runtime_error("Mail flag claim requires recovery");
}
TokenDigest PlanHash(const msgapi::JamAppendPlan& plan) {
  if (plan.header.size() < 76)
    throw std::runtime_error("Invalid transport plan");
  auto wire = plan.header;
  msgapi::jam_wire::Put32(wire.data() + 52, 0);
  std::string content(reinterpret_cast<const char*>(wire.data()), wire.size());
  content += plan.text;
  return Value(Sha256(content));
}
std::string Fold(std::string value) {
  for (auto& c : value)
    if (c >= 'A' && c <= 'Z')
      c += 'a' - 'A';
  return value;
}
}  // namespace
std::string MailBridge::AreaId(std::string_view name) const {
  for (const auto& [id, area] : catalog_->areas())
    if (area.config.mailbox_address.empty() && area.config.kind == AreaKind::kNetmail &&
        Fold(area.config.name) == Fold(std::string(name)))
      return id;
  throw std::runtime_error("Mail transport area unavailable");
}
void MailBridge::Finish(storage::MailTransfer transfer) {
  auto source = Open(*catalog_, transfer.source_conference, true, config_.ftn.default_encoding);
  if (source->generation() != transfer.source_generation)
    throw std::runtime_error("Mail source generation changed");
  auto snapshot = Take(*io_, *source, transfer.source_number);
  if (snapshot.hash != transfer.source_hash)
    throw std::runtime_error("Mail source payload changed");
  const bool outbound = transfer.source_key.starts_with("out:");
  const bool claim = !outbound && (!transfer.target_conference.empty() || transfer.duplicate || transfer.collision ||
                                   transfer.state == TransferState::kQuarantine);
  if (claim) {
    if (transfer.state != TransferState::kDone || (snapshot.flags & locked) == 0)
      Flags(*io_, *source, snapshot, transfer.original_flags, transfer.original_flags | locked);
    Cut("claim");
  }
  source.reset();
  if (transfer.collision || transfer.state == TransferState::kQuarantine) {
    if (outbound)
      throw std::runtime_error("Outgoing mail transfer is quarantined");
    Require(metadata_->SetTransferState(transfer.source_key, TransferState::kQuarantine));
    return;
  }
  if (transfer.state == TransferState::kDone)
    return;
  if (transfer.target_conference.empty() || transfer.duplicate) {
    Require(metadata_->SetTransferState(transfer.source_key, TransferState::kDone));
    return;
  }
  if (transfer.state == TransferState::kIntent) {
    Require(metadata_->SetTransferState(transfer.source_key, TransferState::kClaimed));
    transfer.state = TransferState::kClaimed;
  }
  const auto entry = catalog_->areas().find(transfer.target_conference);
  if (entry == catalog_->areas().end())
    throw std::runtime_error("Mailbox binding was revoked");
  const bool transport = entry->second.config.mailbox_address.empty();
  const auto actor = transport ? Value(metadata_->MailboxUser(snapshot.message.origin_address()))
                               : Value(metadata_->MailboxUser(entry->second.config.mailbox_address));
  auto previous = Value(metadata_->FindOperation(actor, transfer.target_operation));
  if (previous && previous->state == OperationState::kPending) {
    Require(writer_.Recover(*catalog_, *previous, Deadline()));
    previous = Value(metadata_->FindOperation(actor, transfer.target_operation));
  }
  if (previous && previous->state == OperationState::kQuarantine)
    throw std::runtime_error("Transfer append is quarantined");
  if (!previous || previous->state == OperationState::kRolledBack) {
    auto target = Open(*catalog_, transfer.target_conference, true, config_.ftn.default_encoding);
    auto message = snapshot.message;
    message.SetReplyLinks(0, 0, 0);
    for (auto flag : {msgapi::JamMessageAttribute::kTypeLocal, msgapi::JamMessageAttribute::kTypeEcho,
                      msgapi::JamMessageAttribute::kLocal, msgapi::JamMessageAttribute::kSent,
                      msgapi::JamMessageAttribute::kInTransit, msgapi::JamMessageAttribute::kKillSent})
      message.SetAttribute(flag, false);
    message.SetAttribute(msgapi::JamMessageAttribute::kTypeNet, true);
    message.SetAttribute(msgapi::JamMessageAttribute::kPrivate, true);
    message.SetAttribute(msgapi::JamMessageAttribute::kLocked, transport);
    if (transport)
      message.SetAttribute(msgapi::JamMessageAttribute::kLocal, true);
    auto plan = target->messages().PrepareAppend(message);
    if (!plan)
      throw std::runtime_error("Mail transfer cannot be encoded");
    Operation operation;
    operation.user = actor;
    operation.id = transfer.target_operation;
    operation.conference = transfer.target_conference;
    operation.generation = target->generation();
    operation.ftn_msgid = message.msg_id();
    operation.payload_hash = transfer.payload_hash;
    operation.plan = std::move(*plan);
    operation.mail_direction = transport ? 3 : 1;
    operation.recipient = message.dest_address();
    Require(writer_.Append(*target, operation));
    Cut("append");
    previous = Value(metadata_->FindOperation(actor, transfer.target_operation));
  }
  if (!previous || previous->state != OperationState::kCommitted ||
      previous->conference != transfer.target_conference || previous->payload_hash != transfer.payload_hash ||
      previous->ftn_msgid != snapshot.message.msg_id())
    throw std::runtime_error("Mail target binding is ambiguous");
  if (static_cast<int>(transfer.state) < static_cast<int>(TransferState::kBound))
    Require(metadata_->SetTransferState(transfer.source_key, TransferState::kBound));
  Cut("bind");
  if (transport) {
    auto target = Open(*catalog_, transfer.target_conference, true, config_.ftn.default_encoding);
    if (target->generation() != previous->generation)
      throw std::runtime_error("Transport generation changed");
    auto published = Take(*io_, *target, previous->plan.number);
    if (published.hash != PlanHash(previous->plan))
      throw std::runtime_error("Transport payload changed");
    auto expected = msgapi::jam_wire::Get32(previous->plan.header.data() + 52);
    Flags(*io_, *target, published, expected, expected & ~locked);
    Cut("unlock");
  }
  Require(metadata_->SetTransferState(transfer.source_key, TransferState::kDone));
}
std::expected<void, domain::ApiError> MailBridge::Recover() {
  try {
    Require(writer_.RecoverAll(*catalog_, Deadline()));
    for (const auto& transfer : Value(metadata_->MailTransfers(false)))
      if (transfer.state != TransferState::kDone)
        Finish(transfer);
    return {};
  } catch (const std::exception&) {
    return std::unexpected(domain::ApiError::Server("Mail bridge recovery requires administrator attention"));
  }
}
std::expected<void, domain::ApiError> MailBridge::Dispatch() {
  try {
    Require(Recover());
    std::set<std::string> managed, own(hpt_.transport.own_addresses.begin(), hpt_.transport.own_addresses.end()), links;
    for (const auto& point : config_.point_mail.points)
      managed.insert(point.address);
    for (const auto& [address, aka] : hpt_.transport.link_akas)
      links.insert(address);
    // The raw source identity is stable across local decoding-policy changes.
    // Reuse completed journal entries instead of reinterpreting their payload hash.
    std::map<std::string, MailTransfer> completed;
    for (const auto& transfer : Value(metadata_->MailTransfers()))
      if (transfer.state == TransferState::kDone)
        completed.emplace(transfer.source_key, transfer);
    for (const auto& name : config_.point_mail.ingress_areas) {
      const auto id = AreaId(name);
      auto source = Open(*catalog_, id, false, config_.ftn.default_encoding);
      const auto generation = source->generation();
      auto numbers = source->messages().GetMessageNumbers();
      if (!numbers)
        throw std::runtime_error("Ingress unavailable");
      const auto slots = *numbers;
      source.reset();
      for (auto number : slots) {
        auto access = Open(*catalog_, id, false, config_.ftn.default_encoding);
        auto snapshot = Take(*io_, *access, number);
        if (access->generation() != generation)
          throw std::runtime_error("Ingress changed");
        access.reset();
        MailTransfer input;
        input.source_conference = id;
        input.source_generation = generation;
        input.source_number = number;
        input.original_flags = snapshot.flags;
        input.source_hash = snapshot.hash;
        input.source_key =
            "in:" + Hex(Value(Sha256(id + ":" + generation + ":" + std::to_string(number) + ":" + Hex(snapshot.hash))));
        if (auto previous = completed.find(input.source_key); previous != completed.end()) {
          Finish(previous->second);
          continue;
        }
        auto envelope = InspectMail(snapshot.message, managed, own, links);
        if (!envelope) {
          input.delivery_key = "quarantine:" + input.source_key;
          input.payload_hash = snapshot.hash;
          input.state = TransferState::kQuarantine;
        } else {
          input.delivery_key = Hex(envelope->delivery_key);
          input.payload_hash = envelope->payload_hash;
          if (envelope->recipient == MailRecipient::kManaged)
            input.target_conference = MailboxId(envelope->destination);
        }
        input.target_operation = "transfer:" + input.source_key;
        auto transfer = Value(metadata_->PrepareTransfer(input));
        Cut("intent");
        Finish(transfer);
      }
    }
    for (const auto& event : Value(metadata_->PendingOutbox())) {
      if (event.outbox_state == 3)
        throw std::runtime_error("Outbox source is quarantined");
      auto source = Open(*catalog_, event.conference, false, config_.ftn.default_encoding);
      if (source->generation() != event.generation)
        throw std::runtime_error("Outbox source changed");
      auto snapshot = Take(*io_, *source, event.plan.number);
      const auto entry = catalog_->areas().find(event.conference);
      const auto direction =
          Value(metadata_->MailDirection({event.conference, event.generation, std::to_string(event.plan.number)}));
      const auto origin = domain::CanonicalFtnAddress(snapshot.message.origin_address());
      if (snapshot.hash != PlanHash(event.plan) ||
          snapshot.flags != msgapi::jam_wire::Get32(event.plan.header.data() + 52) ||
          snapshot.message.msg_id() != event.ftn_msgid || direction != 2 || entry == catalog_->areas().end() ||
          entry->second.config.mailbox_address.empty() || !origin || *origin != entry->second.config.mailbox_address) {
        Require(metadata_->SetOutboxState(event.user, event.id, 3));
        throw std::runtime_error("Acknowledged outbox source changed");
      }
      source.reset();
      auto envelope = InspectMail(snapshot.message, managed, own, links);
      if (!envelope)
        throw std::runtime_error("Outbox addressing is ambiguous");
      MailTransfer input;
      input.source_key = "out:" + Hex(Value(Sha256(event.user + ":" + event.id)));
      input.delivery_key = Hex(envelope->delivery_key);
      input.source_conference = event.conference;
      input.source_generation = event.generation;
      input.source_number = event.plan.number;
      input.original_flags = snapshot.flags;
      input.source_hash = snapshot.hash;
      input.payload_hash = envelope->payload_hash;
      input.target_conference = envelope->recipient == MailRecipient::kManaged ? MailboxId(envelope->destination)
                                                                               : AreaId(config_.point_mail.egress_area);
      input.target_operation = "transfer:" + input.source_key;
      auto transfer = Value(metadata_->PrepareTransfer(input));
      Cut("intent");
      Finish(transfer);
      Require(metadata_->SetOutboxState(event.user, event.id, 2));
    }
    return {};
  } catch (const std::exception&) {
    return std::unexpected(domain::ApiError::Server("Mail dispatch requires administrator attention"));
  }
}
}  // namespace fidoback::service
