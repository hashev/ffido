#include <gtest/gtest.h>

#include <fstream>

#include "../support/temp_directory.hpp"
#include "service/mail_addressing.hpp"
#include "service/point_mail.hpp"
#include "storage/point_mailbox.hpp"
using namespace fidoback;
namespace {
AppConfig Config() {
  auto c = DefaultConfig();
  c.ftn.jam_base_path = "/fixture";
  c.ftn.coordination_lock = "/fixture/lock";
  c.point_mail = {true, {"IN"}, "OUT", {{"2:1/2.1", "points/one"}}};
  return c;
}
service::HptConfiguration Hpt() {
  service::HptConfiguration h;
  h.credentials["2:1/2.1"] = "fixture";
  h.transport = {true,
                 true,
                 false,
                 {"2:1/2"},
                 {{"2:1/2.1", "2:1/2"}},
                 {{"IN", true}, {"OUT", false}},
                 {{"2:1/2.1", true, true}, {"*", false, true}}};
  for (auto name : {"IN", "OUT"}) {
    EchoAreaConfig a;
    a.name = name;
    a.filename = std::string("/fixture/") + name;
    a.kind = AreaKind::kNetmail;
    a.msgbase_type = "JAM";
    a.aka = "2:1/2";
    h.private_areas.push_back(a);
  }
  return h;
}
}  // namespace
TEST(PointMail, RequiresExplicitLocalLinkAndSafeEffectiveHptPolicy) {
  const auto c = Config();
  const auto h = Hpt();
  ASSERT_TRUE(service::ValidatePointMail(c, h));
  for (int fault = 0; fault < 12; ++fault) {
    auto config = c;
    auto hpt = h;
    switch (fault) {
      case 0:
        hpt.transport.available = false;
        break;
      case 1:
        hpt.transport.keep_transit = false;
        break;
      case 2:
        hpt.transport.pack_on_scan = true;
        break;
      case 3:
        hpt.transport.link_akas.clear();
        break;
      case 4:
        hpt.transport.link_akas["2:1/2.1"] = "2:1/9";
        break;
      case 5:
        hpt.transport.own_addresses.push_back("2:1/2.1");
        break;
      case 6:
        hpt.transport.netmail[0].dupe_check_off = false;
        break;
      case 7:
        config.point_mail.ingress_areas = {"UNKNOWN"};
        break;
      case 8:
        config.point_mail.egress_area = "IN";
        break;
      case 9:
        hpt.transport.routes[0].nopack = false;
        break;
      case 10:
        hpt.transport.routes[0].pattern = "2:1/2.*";
        break;
      case 11:
        config.point_mail.points[0].jam_base = "IN";
        break;
    }
    EXPECT_FALSE(service::ValidatePointMail(config, hpt)) << fault;
    config.point_mail.enabled = false;
    EXPECT_TRUE(service::ValidatePointMail(config, hpt));
  }
}

TEST(PointMail, ProvisioningIsExplicitIdempotentAndRejectsForeignFilesAndAliases) {
  test::TempDirectory temp;
  auto metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(metadata->Init());
  PointMailboxConfig point{"2:1/2.1", "points/one"};
  ASSERT_TRUE(storage::ProvisionMailbox(temp.path(), point, *metadata));
  auto bindings = metadata->MailboxBindings();
  ASSERT_TRUE(bindings);
  ASSERT_EQ(bindings->size(), 1u);
  const auto generation = bindings->front().generation;
  ASSERT_TRUE(storage::ProvisionMailbox(temp.path(), point, *metadata));
  EXPECT_EQ(metadata->MailboxBindings()->front().generation, generation);
  PointMailConfig config{true, {"IN"}, "OUT", {point}};
  auto areas = storage::MailboxAreas(config, *metadata);
  ASSERT_TRUE(areas);
  auto catalog = storage::JamCatalog::Build(temp.path(), *areas);
  ASSERT_TRUE(catalog);
  EXPECT_TRUE((*catalog)->Resolve(storage::MailboxId(point.address)));
  EXPECT_FALSE(storage::ProvisionMailbox(temp.path(), {"2:1/2.2", point.jam_base}, *metadata));
  EXPECT_FALSE(storage::ProvisionMailbox(temp.path(), {"2:1/2.2", "../escape"}, *metadata));
  std::filesystem::create_directory_symlink(temp.path() / "points", temp.path() / "alias");
  EXPECT_FALSE(storage::ProvisionMailbox(temp.path(), {"2:1/2.2", "alias/other"}, *metadata));
  std::ofstream(temp.path() / "foreign.jhr") << "external";
  EXPECT_FALSE(storage::ProvisionMailbox(temp.path(), {"2:1/2.2", "foreign"}, *metadata));
  EXPECT_EQ(metadata->MailboxBindings()->size(), 1u);
  // All physical files, not only .jhr, are bound. Replacing text cannot reassign mail.
  std::filesystem::rename(temp.path() / "points/one.jdt", temp.path() / "old.jdt");
  std::ofstream(temp.path() / "points/one.jdt") << "foreign text";
  EXPECT_FALSE(storage::ProvisionMailbox(temp.path(), point, *metadata));
  EXPECT_FALSE(storage::JamCatalog::Build(temp.path(), *areas));
  config.points.push_back({"2:1/2.2", "points/two"});
  EXPECT_FALSE(storage::MailboxAreas(config, *metadata));
}

TEST(PointMail, HardlinksAndUnassignedPartialProvisioningNeverBecomeMailboxes) {
  test::TempDirectory temp;
  auto metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(metadata->Init());
  ASSERT_TRUE(storage::ProvisionMailbox(temp.path(), {"2:1/2.1", "one"}, *metadata));
  for (auto extension : {".jhr", ".jdt", ".jdx"})
    std::filesystem::create_hard_link(temp.path() / (std::string("one") + extension),
                                      temp.path() / (std::string("two") + extension));
  EXPECT_FALSE(storage::ProvisionMailbox(temp.path(), {"2:1/2.2", "two"}, *metadata));
  EXPECT_FALSE(storage::ProvisionMailbox(temp.path(), {"2:1/2.1", "one"}, *metadata));
  std::ofstream(temp.path() / "partial.jhr");
  EXPECT_FALSE(storage::ProvisionMailbox(temp.path(), {"2:1/2.3", "partial"}, *metadata));
  EXPECT_EQ(metadata->MailboxBindings()->size(), 1u);
  ASSERT_TRUE(metadata->Init());
  EXPECT_EQ(metadata->MailboxBindings()->size(), 1u);
}

TEST(PointMail, TransferJournalSeparatesRecipientsAndPersistsClaimsAcrossRestart) {
  test::TempDirectory temp;
  auto metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(metadata->Init());
  storage::MailTransfer first;
  first.source_key = "IN:g:1:hash";
  first.delivery_key = "origin|2:1/2.1|same-msgid";
  first.source_conference = "IN";
  first.source_generation = "g";
  first.source_number = 1;
  first.target_conference = "P1";
  first.target_operation = "copy1";
  first.payload_hash[0] = 1;
  first.source_hash[0] = 2;
  auto saved = metadata->PrepareTransfer(first);
  ASSERT_TRUE(saved);
  EXPECT_FALSE(saved->duplicate);
  ASSERT_TRUE(metadata->SetTransferState(first.source_key, storage::TransferState::kClaimed));
  ASSERT_TRUE(metadata->Init());
  auto repeated = metadata->PrepareTransfer(first);
  ASSERT_TRUE(repeated);
  EXPECT_EQ(repeated->state, storage::TransferState::kClaimed);
  auto second = first;
  second.source_key = "IN:g:2:hash";
  second.source_number = 2;
  second.delivery_key = "origin|2:1/2.2|same-msgid";
  second.target_conference = "P2";
  second.target_operation = "copy2";
  auto recipient = metadata->PrepareTransfer(second);
  ASSERT_TRUE(recipient);
  EXPECT_FALSE(recipient->duplicate);
  auto replay = first;
  replay.source_key = "IN:g:3:hash";
  replay.source_number = 3;
  auto duplicate = metadata->PrepareTransfer(replay);
  ASSERT_TRUE(duplicate);
  EXPECT_TRUE(duplicate->duplicate);
  auto collision = replay;
  collision.source_key = "IN:g:4:hash";
  collision.source_number = 4;
  collision.payload_hash[0] = 3;
  auto conflicted = metadata->PrepareTransfer(collision);
  ASSERT_TRUE(conflicted);
  EXPECT_TRUE(conflicted->collision);
  EXPECT_EQ(conflicted->state, storage::TransferState::kQuarantine);
  auto changed_source = first;
  changed_source.source_hash[0] = 9;
  EXPECT_FALSE(metadata->PrepareTransfer(changed_source));
  EXPECT_FALSE(metadata->SetTransferState(first.source_key, storage::TransferState::kIntent));
  EXPECT_EQ(metadata->MailTransfers()->size(), 4u);
}

TEST(PointMail, AddressInspectionUsesFullAddressAndRejectsContradictions) {
  msgapi::JamMessage message;
  message.SetOriginAddress("2:1/9.7");
  message.SetDestAddress("2:1/2.1");
  message.SetMsgId("2:1/9.7 abc");
  message.SetSenderName("Same Name");
  message.SetReceiverName("Same Name");
  message.SetText("Н incoming");
  message.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "INTL 2:1/2 2:1/9");
  message.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "TOPT 1");
  message.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "FMPT 7");
  const std::set<std::string> managed{"2:1/2.1", "2:1/2.2"}, own{"2:1/2"}, links{"2:1/2.3"};
  auto inspected = service::InspectMail(message, managed, own, links);
  ASSERT_TRUE(inspected);
  EXPECT_EQ(inspected->recipient, service::MailRecipient::kManaged);
  auto via = message;
  via.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "Via 2:1/99 1234");
  EXPECT_EQ(service::InspectMail(via, managed, own, links)->payload_hash, inspected->payload_hash);
  auto same_id = message;
  same_id.SetDestAddress("2:1/2.2");
  // Existing TOPT 1 contradicts the full destination .2.
  EXPECT_FALSE(service::InspectMail(same_id, managed, own, links));
  for (auto address : {"2:1/2", "2:1/2.3", "2:1/7.1"}) {
    msgapi::JamMessage other;
    other.SetOriginAddress("2:1/9.7");
    other.SetDestAddress(address);
    other.SetMsgId("same-id");
    auto result = service::InspectMail(other, managed, own, links);
    ASSERT_TRUE(result);
    EXPECT_NE(result->recipient, service::MailRecipient::kManaged);
    EXPECT_NE(result->delivery_key, inspected->delivery_key);
  }
  auto conflict = message;
  conflict.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "TOPT 2");
  EXPECT_FALSE(service::InspectMail(conflict, managed, own, links));
  for (const auto& id : {std::string("bad\1id", 6), std::string("bad\0id", 6), std::string("\xff", 1)}) {
    auto malformed = message;
    malformed.SetMsgId(id);
    EXPECT_FALSE(service::InspectMail(malformed, managed, own, links));
  }
  auto no_id = message;
  no_id.SetMsgId("");
  EXPECT_FALSE(service::InspectMail(no_id, managed, own, links));
}
