#include <fcntl.h>
#include <gtest/gtest.h>
#include <spawn.h>
#include <sys/wait.h>
extern char** environ;

#include <fstream>

#include "../support/jam_wire_record.hpp"
#include "../support/smapi_oracle.hpp"
#include "../support/temp_directory.hpp"
#include "../support/tls_certificate.hpp"
#include "ftn/uue.hpp"
#include "service/conference_service.hpp"
#include "service/crypto.hpp"
#include "service/grpc_runtime.hpp"
#include "service/grpc_service.hpp"
#include "service/mail_bridge.hpp"
#include "service/message_service.hpp"
#include "service/uue_service.hpp"
#include "storage/point_mailbox.hpp"
using namespace fidoback;
namespace {
class PrivateAreasTest : public ::testing::Test {
protected:
  test::TempDirectory temp;
  std::shared_ptr<storage::IMetadataStore> metadata;
  std::shared_ptr<storage::JamCatalog> catalog;
  service::HptConfiguration hpt;
  std::shared_ptr<const service::EchoAccess> access;
  std::unique_ptr<service::MessageService> messages;
  std::unique_ptr<service::ConferenceService> conferences;
  const std::string net = "@ffido/1/6d61696c", local = "@ffido/2/6c6f63616c";
  void SetUp() override {
    std::vector<EchoAreaConfig> areas;
    for (auto [name, kind] : {std::pair{"ECHO", AreaKind::kEcho},
                              {"MAIL", AreaKind::kNetmail},
                              {"LOCAL", AreaKind::kLocal},
                              {"BAD", AreaKind::kBad},
                              {"DUPE", AreaKind::kDupe},
                              {"ROBOT", AreaKind::kRobots}}) {
      msgapi::JamBaseHeader header{};
      header.signature = msgapi::kJamSignature;
      header.base_msg_num = 1;
      header.date_created = 123;
      header.password_crc = UINT32_MAX;
      auto bytes = msgapi::jam_wire::Encode(header);
      std::ofstream output(temp.path() / (std::string(name) + ".jhr"), std::ios::binary);
      output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
      for (auto ext : {".jdt", ".jdx"})
        std::ofstream(temp.path() / (std::string(name) + ext));
      EchoAreaConfig area;
      area.name = name;
      area.filename = name;
      area.msgbase_type = "JAM";
      area.kind = kind;
      area.aka = "2:1/2.1";
      areas.push_back(area);
    }
    auto old = areas.back();
    old.name = "OLD";
    old.filename = "old";
    old.msgbase_type = "Squish";
    areas.push_back(old);
    auto opened = storage::JamCatalog::Build(temp.path(), areas);
    ASSERT_TRUE(opened);
    catalog = std::shared_ptr<storage::JamCatalog>(std::move(*opened));
    metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
    ASSERT_TRUE(metadata->Init());
    for (auto [user, address] : {std::pair{"owner", "2:1/2.1"}, {"point1", "2:1/2.2"}, {"point2", "2:1/2.3"}}) {
      ASSERT_TRUE(metadata->SaveProfile(user, domain::Profile{"Нина", address, "", ""}));
      hpt.credentials.emplace(address, "fixture-password");
    }
    service::HptEcho echo{"ECHO", temp.path() / "ECHO", {}};
    for (const auto& [address, password] : hpt.credentials)
      echo.links.emplace(address, service::EchoPermissions{true, true});
    hpt.echoes.push_back(echo);
    auto policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
    ASSERT_TRUE(policy);
    access = *policy;
    messages = std::make_unique<service::MessageService>(catalog, metadata, access);
    conferences = std::make_unique<service::ConferenceService>(catalog, metadata, access);
  }
  AppConfig Mailboxes() {
    auto config = DefaultConfig();
    config.ftn.jam_base_path = temp.path().string();
    config.point_mail = {true, {"MAIL"}, "OUT", {{"2:1/2.2", "points/p1"}, {"2:1/2.3", "points/p2"}}};
    for (const auto& point : config.point_mail.points) {
      if (!storage::ProvisionMailbox(temp.path(), point, *metadata))
        throw std::runtime_error("provision failed");
    }
    std::filesystem::copy_file(temp.path() / "BAD.jhr", temp.path() / "OUT.jhr");
    for (auto extension : {".jdt", ".jdx"})
      std::ofstream(temp.path() / (std::string("OUT") + extension));
    std::vector<EchoAreaConfig> areas;
    for (const auto& [id, area] : catalog->areas())
      areas.push_back(area.config);
    EchoAreaConfig out;
    out.name = "OUT";
    out.filename = "OUT";
    out.msgbase_type = "JAM";
    out.kind = AreaKind::kNetmail;
    out.aka = "2:1/2";
    areas.push_back(out);
    auto mailbox_areas = storage::MailboxAreas(config.point_mail, *metadata);
    if (!mailbox_areas)
      throw std::runtime_error("mailboxes unavailable");
    areas.insert(areas.end(), mailbox_areas->begin(), mailbox_areas->end());
    auto opened = storage::JamCatalog::Build(temp.path(), areas);
    if (!opened)
      throw std::runtime_error("catalog failed");
    catalog = std::shared_ptr<storage::JamCatalog>(std::move(*opened));
    auto policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
    if (!policy)
      throw std::runtime_error("policy failed");
    access = *policy;
    messages = std::make_unique<service::MessageService>(catalog, metadata, access);
    conferences = std::make_unique<service::ConferenceService>(catalog, metadata, access);
    hpt.transport.own_addresses = {"2:1/2"};
    hpt.transport.link_akas = {{"2:1/2.2", "2:1/2"}, {"2:1/2.3", "2:1/2"}, {"2:1/2.4", "2:1/2"}};
    return config;
  }
  void Incoming(std::string to, std::string msgid = "2:1/9.7 same", std::string body = "Н входящее",
                std::string from = "2:1/9.7") {
    auto lease =
        storage::JamAccess::Open(*catalog, net, true, std::chrono::steady_clock::now() + std::chrono::seconds(5));
    if (!lease)
      throw std::runtime_error("ingress failed");
    msgapi::JamMessage message;
    message.SetSenderName("Same Name");
    message.SetReceiverName("Same Name");
    message.SetOriginAddress(from);
    message.SetDestAddress(to);
    message.SetMsgId(msgid);
    message.SetText(body);
    message.SetAttribute(msgapi::JamMessageAttribute::kPrivate, true);
    message.SetAttribute(msgapi::JamMessageAttribute::kTypeNet, true);
    if ((*lease)->messages().AddMessage(message) != msgapi::JamError::kSuccess)
      throw std::runtime_error("fixture append failed");
  }
  domain::CreateMessageRequest Request(std::string id = "private-op") {
    domain::CreateMessageRequest r;
    r.operation_id = id;
    r.to_name = "Николай";
    r.to_address = "2:1/3.4";
    r.subject = "Н тест";
    r.body = "Н текст";
    return r;
  }
};
}  // namespace
TEST_F(PrivateAreasTest, ExplicitOwnerAndPrivateMetadataBoundary) {
  EXPECT_FALSE(service::EchoAccess::Build(hpt, *catalog, {"2:1/9"}));
  EXPECT_FALSE(service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1", "02:001/002.1"}));
  auto none = service::EchoAccess::Build(hpt, *catalog);
  ASSERT_TRUE(none);
  EXPECT_FALSE((*none)->Permissions(*metadata, "owner", net)->read);
  auto owner = conferences->GetConferences({0, 2}, {}, "owner");
  ASSERT_TRUE(owner);
  EXPECT_EQ(owner->total, 7);
  EXPECT_TRUE(owner->has_more);
  auto old = conferences->GetConference("@ffido/5/6f6c64", "owner");
  ASSERT_TRUE(old);
  EXPECT_TRUE(old->unsupported_format);
  EXPECT_FALSE(old->statistics_known);
  EXPECT_FALSE(old->can_read);
  EXPECT_FALSE(old->can_post);
  EXPECT_EQ(old->storage_format, "Squish");
  for (auto user : {"point1", "point2"}) {
    auto list = conferences->GetConferences({}, {}, user);
    ASSERT_TRUE(list);
    EXPECT_EQ(list->total, 1);
    EXPECT_FALSE(list->has_more);
    EXPECT_EQ(conferences->GetConferences({}, "MAIL", user)->total, 0);
    for (const auto& [id, area] : catalog->areas()) {
      if (area.config.kind == AreaKind::kEcho)
        continue;
      auto conference = conferences->GetConference(id, user);
      ASSERT_FALSE(conference);
      EXPECT_EQ(conference.error().code, domain::ErrorCode::kForbidden);
      EXPECT_FALSE(messages->GetMessages(id, {}, "newest", user));
      EXPECT_FALSE(messages->GetMessage(id, "known", user));
      EXPECT_FALSE(messages->GetThread(id, "known", user, {}));
      EXPECT_FALSE(messages->MarkAsRead(id, "known", user));
      EXPECT_FALSE(messages->CreateMessage(id, Request(), user));
    }
    EXPECT_TRUE(metadata->GetHistory(user)->empty());
    EXPECT_FALSE(*metadata->FindOperation(user, "private-op"));
  }
  // The policy denies a point before touching even a replaced private base.
  std::filesystem::remove(temp.path() / "MAIL.jhr");
  auto denied = messages->GetMessages(net, {}, "newest", "point1");
  ASSERT_FALSE(denied);
  EXPECT_EQ(denied.error().code, domain::ErrorCode::kForbidden);
}
TEST_F(PrivateAreasTest, NetmailAndLocalUseOneDurableAppendWithCorrectWireTypes) {
  auto request = Request();
  auto created = messages->CreateMessage(net, request, "owner");
  ASSERT_TRUE(created) << created.error().message;
  auto wire = test::ReadJamWireRecord(temp.path() / "MAIL", 0);
  EXPECT_EQ(test::Wire32(wire.header, 52) & 0x03800004, 0x02000004u);
  EXPECT_EQ(wire.Field(0), "2:1/2.1");
  EXPECT_EQ(wire.Field(1), "2:1/3.4");
  EXPECT_EQ(wire.Field(2), std::string("H\xa8\xad\xa0", 4));
  EXPECT_EQ(wire.Field(3), std::string("H\xa8\xaa\xae\xab\xa0\xa9", 7));
  EXPECT_EQ(wire.Field(6), std::string("H \xe2\xa5\xe1\xe2", 6));
  EXPECT_EQ(wire.body, std::string("H \xe2\xa5\xaa\xe1\xe2\r", 8));
  for (auto word : {"AREA:", "SEEN-BY:", "PATH:", "Origin:"})
    EXPECT_EQ(wire.body.find(word), std::string::npos);
  EXPECT_TRUE(wire.HasField(2000, "CHRS: CP866 2"));
  auto repeat = messages->CreateMessage(net, request, "owner");
  ASSERT_TRUE(repeat);
  EXPECT_EQ(repeat->id, created->id);
  request.body += "!";
  auto conflict = messages->CreateMessage(net, request, "owner");
  ASSERT_FALSE(conflict);
  EXPECT_EQ(conflict.error().code, domain::ErrorCode::kConflict);
  auto reply = Request("reply");
  reply.in_reply_to = created->id;
  auto replied = messages->CreateMessage(net, reply, "owner");
  ASSERT_TRUE(replied);
  auto reply_wire = test::ReadJamWireRecord(temp.path() / "MAIL", 1);
  EXPECT_EQ(reply_wire.Field(1), "2:1/2.1");
  EXPECT_EQ(reply_wire.reply_to, 1);
  EXPECT_EQ(reply_wire.Field(5), created->ftn_message_id);
  auto local_send = messages->CreateMessage(local, Request("local"), "owner");
  ASSERT_TRUE(local_send);
  auto local_wire = test::ReadJamWireRecord(temp.path() / "LOCAL", 0);
  EXPECT_EQ(test::Wire32(local_wire.header, 52) & 0x03800004, 0x00800000u);
  EXPECT_EQ(local_wire.body.find("Origin:"), std::string::npos);
  for (auto id : {"@ffido/3/626164", "@ffido/4/64757065", "@ffido/5/726f626f74"}) {
    EXPECT_TRUE(conferences->GetConference(id, "owner")->can_read);
    EXPECT_FALSE(messages->CreateMessage(id, Request(), "owner"));
  }
}
TEST_F(PrivateAreasTest, ValidationHasNoIntentAndSenderIsNeverReplaced) {
  auto request = Request();
  request.to_address.clear();
  EXPECT_FALSE(messages->CreateMessage(net, request, "owner"));
  EXPECT_FALSE(*metadata->FindOperation("owner", request.operation_id));
  auto other_owner = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.2"});
  ASSERT_TRUE(other_owner);
  service::MessageService other(catalog, metadata, *other_owner);
  auto failed = other.CreateMessage(net, Request(), "point1");
  ASSERT_FALSE(failed);
  EXPECT_EQ(failed.error().code, domain::ErrorCode::kValidation);
  EXPECT_FALSE(*metadata->FindOperation("owner", request.operation_id));
}

namespace {
class FailPrivateSync : public storage::JamIo {
  int count = 0;

public:
  int Sync(int fd) override {
    if (++count == 3) {
      errno = EIO;
      return -1;
    }
    return storage::JamIo::Sync(fd);
  }
};
}  // namespace
TEST_F(PrivateAreasTest, UncertainNetmailCommitRecoversAndMalformedParentHasNoIntent) {
  service::MessageService failing(catalog, metadata, access, "cp866", std::make_shared<FailPrivateSync>());
  auto request = Request("uncertain");
  EXPECT_FALSE(failing.CreateMessage(net, request, "owner"));
  auto recovered = messages->CreateMessage(net, request, "owner");
  ASSERT_TRUE(recovered);
  EXPECT_EQ(messages->CreateMessage(net, request, "owner")->id, recovered->id);
  EXPECT_EQ(conferences->GetConference(net, "owner")->total_count, 1);
  std::string parent_id;
  {
    auto opened =
        storage::JamAccess::Open(*catalog, net, true, std::chrono::steady_clock::now() + std::chrono::seconds(5));
    ASSERT_TRUE(opened);
    msgapi::JamMessage parent;
    parent.SetSenderName("Unknown");
    parent.SetSubject("Old netmail");
    parent.SetText("Legacy");
    parent.SetMsgId("unknown-origin serial");
    EXPECT_EQ((*opened)->messages().AddMessage(parent), msgapi::JamError::kSuccess);
    parent_id = (*opened)->generation() + "#2";
  }
  request.operation_id = "bad-parent";
  request.in_reply_to = parent_id;
  auto reply = messages->CreateMessage(net, request, "owner");
  ASSERT_FALSE(reply);
  EXPECT_EQ(reply.error().code, domain::ErrorCode::kValidation);
  EXPECT_FALSE(*metadata->FindOperation("owner", request.operation_id));
}

TEST_F(PrivateAreasTest, ReadingHistoricalWrongTypeBitsNeverRewritesJam) {
  auto created = messages->CreateMessage(net, Request("historical"), "owner");
  ASSERT_TRUE(created);
  const auto index = test::ReadFile(temp.path() / "MAIL.jdx");
  const auto offset = test::Wire32(index, 4) + 52;
  {
    // Reproduce the old FFIDO TypeNet value, without using the corrected enum.
    std::fstream header(temp.path() / "MAIL.jhr", std::ios::binary | std::ios::in | std::ios::out);
    header.seekp(offset);
    const char old_flags[] = {5, 0, 0, 1};
    header.write(old_flags, sizeof(old_flags));
  }
  std::map<std::string, std::string> before;
  for (const auto* extension : {".jhr", ".jdx", ".jdt"})
    before[extension] = test::ReadFile(temp.path() / (std::string("MAIL") + extension));
  EXPECT_TRUE(messages->GetMessages(net, {}, "oldest", "owner"));
  EXPECT_TRUE(messages->GetMessage(net, created->id, "owner"));
  for (const auto& [extension, bytes] : before)
    EXPECT_EQ(test::ReadFile(temp.path() / ("MAIL" + extension)), bytes);
}

TEST_F(PrivateAreasTest, RealHptPackExportsNetmailAndEchoButNeverLocal) {
  const char* hpt_binary = std::getenv("FFIDO_TEST_HPT");
  if (!hpt_binary || !*hpt_binary)
    GTEST_SKIP() << "Set FFIDO_TEST_HPT to installed HPT";
  const auto root = temp.path();
  for (auto dir : {"inbound", "protinbound", "outbound", "tmpin", "tmpout", "logs", "dupes", "nodelist"})
    std::filesystem::create_directory(root / dir);
  std::ofstream(root / "wrapper.json") << nlohmann::json{
      {"ftn", {{"coordination_lock", (root / "hpt.lock").string()}}}};
  {
    std::ofstream config(root / "hpt.cfg");
    config << "Name FFIDO isolated private test\nSysop Test\nLocation Test\nAddress 2:1/2.1\n";
    for (auto [key, dir] : {std::pair{"Inbound", "inbound"},
                            {"ProtInbound", "protinbound"},
                            {"Outbound", "outbound"},
                            {"TempInbound", "tmpin"},
                            {"TempOutbound", "tmpout"},
                            {"LogFileDir", "logs"},
                            {"DupeHistoryDir", "dupes"},
                            {"NodelistDir", "nodelist"}})
      config << key << " " << (root / dir).string() << "\n";
    config << "MsgBaseDir " << root.string() << "\nEchoTossLog " << (root / "logs/toss.log").string()
           << "\n"
              "Link Remote\nAKA 2:1/3.4\nOurAKA 2:1/2.1\nAllowEmptyPktPwd on\n"
              "EchoMailFlavour direct\nNetMailFlavour direct\nRoute normal 2:1/3.4 2:1/3.4\n";
    for (auto [key, name] :
         {std::pair{"NetmailArea", "MAIL"}, {"LocalArea", "LOCAL"}, {"BadArea", "BAD"}, {"DupeArea", "DUPE"}})
      config << key << " " << name << " " << (root / name).string() << " -b JAM\n";
    config << "EchoArea ECHO " << (root / "ECHO").string() << " -b JAM -a 2:1/2.1 2:1/3.4\n";
  }
  auto netmail = messages->CreateMessage(net, Request("pack-net"), "owner");
  auto local_message = messages->CreateMessage(local, Request("pack-local"), "owner");
  auto echo1 = messages->CreateMessage("ECHO", Request("pack-echo1"), "owner");
  auto echo2 = messages->CreateMessage("ECHO", Request("pack-echo2"), "point1");
  ASSERT_TRUE(netmail);
  ASSERT_TRUE(local_message);
  ASSERT_TRUE(echo1);
  ASSERT_TRUE(echo2);
  // Unlike the wire assertions, this reader is linked only to the installed SMAPI.
  const auto smapi_before = test::SmapiOracle({"read", (root / "MAIL").string(), "1"});
  EXPECT_EQ(smapi_before.at("wire_attributes"), 0x02000005u);
  EXPECT_EQ(smapi_before.at("private"), true);
  EXPECT_EQ(smapi_before.at("local"), true);
  EXPECT_EQ(smapi_before.at("origin"), "2:1/2.1");
  EXPECT_EQ(smapi_before.at("destination"), "2:1/3.4");
  EXPECT_EQ(test::SmapiOracle({"read", (root / "LOCAL").string(), "1"}).at("wire_attributes"), 0x00800001u);
  EXPECT_EQ(test::SmapiOracle({"read", (root / "ECHO").string(), "1"}).at("wire_attributes"), 0x01000001u);
  // A real incoming netmail produced by SMAPI, then answered by FFIDO.
  test::SmapiOracle({"incoming", (root / "MAIL").string(), "1"});
  auto incoming = messages->GetMessages(net, {}, "oldest", "owner");
  ASSERT_TRUE(incoming);
  ASSERT_EQ(incoming->messages.size(), 2u);
  auto reply_request = Request("pack-reply");
  auto parent = std::find_if(incoming->messages.begin(), incoming->messages.end(),
                             [](const auto& message) { return message.subject == "Incoming from SMAPI"; });
  ASSERT_NE(parent, incoming->messages.end());
  reply_request.in_reply_to = parent->id;
  auto reply = messages->CreateMessage(net, reply_request, "owner");
  ASSERT_TRUE(reply);
  auto smapi_reply = test::SmapiOracle({"read", (root / "MAIL").string(), "3"});
  EXPECT_EQ(smapi_reply.at("wire_attributes"), 0x02000005u);
  EXPECT_EQ(smapi_reply.at("destination"), "2:1/3.4");
  auto run = [&](std::string command) {
    std::vector<std::string> args{
        FFIDO_PYTHON, FFIDO_HPT_WRAPPER, "--config", (root / "wrapper.json").string(), "--timeout", "10",
        "--",         hpt_binary,        "-c",       (root / "hpt.cfg").string(),      command};
    if (command == "scan")
      args.insert(args.end(), {"-w", "-a", "ECHO"});
    std::vector<char*> pointers;
    for (auto& arg : args)
      pointers.push_back(arg.data());
    pointers.push_back(nullptr);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, (root / "hpt.log").c_str(), O_WRONLY | O_CREAT | O_TRUNC,
                                     0600);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    pid_t child = -1;
    auto error = posix_spawn(&child, args[0].c_str(), &actions, nullptr, pointers.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    if (error)
      return -1;
    int status = 0;
    if (waitpid(child, &status, 0) != child)
      return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
  };
  ASSERT_EQ(run("pack"), 0) << test::ReadFile(root / "hpt.log");
  const auto smapi_after = test::SmapiOracle({"read", (root / "MAIL").string(), "1"});
  EXPECT_EQ(smapi_after.at("wire_attributes").get<uint32_t>() & 0x03800004u, 0x02000004u);
  EXPECT_EQ(smapi_after.at("sent"), true);
  EXPECT_EQ(smapi_after.at("origin"), "2:1/2.1");
  EXPECT_EQ(smapi_after.at("destination"), "2:1/3.4");
  EXPECT_EQ(test::SmapiOracle({"read", (root / "MAIL").string(), "3"}).at("sent"), true);
  std::string packed;
  for (auto& entry : std::filesystem::recursive_directory_iterator(root / "outbound"))
    if (entry.is_regular_file())
      packed += test::ReadFile(entry.path());
  if (packed.find(netmail->ftn_message_id) == std::string::npos) {
    for (auto& entry : std::filesystem::recursive_directory_iterator(root / "logs"))
      if (entry.is_regular_file())
        std::cerr << entry.path() << "\n" << test::ReadFile(entry.path());
  }
  EXPECT_NE(packed.find(netmail->ftn_message_id), std::string::npos) << test::ReadFile(root / "hpt.log");
  for (auto word : {"AREA:", "SEEN-BY:", "PATH:", "Origin:"})
    EXPECT_EQ(packed.find(word), std::string::npos);
  EXPECT_NE(packed.find(reply->ftn_message_id), std::string::npos);
  EXPECT_NE(packed.find("REPLY: 2:1/3.4 1234abcd"), std::string::npos);
  EXPECT_EQ(packed.find(local_message->ftn_message_id), std::string::npos);
  ASSERT_EQ(run("scan"), 0) << test::ReadFile(root / "hpt.log");
  packed.clear();
  for (auto& entry : std::filesystem::recursive_directory_iterator(root / "outbound"))
    if (entry.is_regular_file())
      packed += test::ReadFile(entry.path());
  EXPECT_NE(packed.find(echo1->ftn_message_id), std::string::npos);
  EXPECT_NE(packed.find(echo2->ftn_message_id), std::string::npos);
  EXPECT_NE(packed.find(reply->ftn_message_id), std::string::npos);
  EXPECT_NE(packed.find("REPLY: 2:1/3.4 1234abcd"), std::string::npos);
  EXPECT_EQ(packed.find(local_message->ftn_message_id), std::string::npos);
  EXPECT_EQ(test::SmapiOracle({"read", (root / "LOCAL").string(), "1"}).at("wire_attributes"), 0x00800001u);
  EXPECT_EQ(
      test::SmapiOracle({"read", (root / "ECHO").string(), "1"}).at("wire_attributes").get<uint32_t>() & 0x03800000u,
      0x01000000u);
  EXPECT_TRUE(messages->GetMessage(local, local_message->id, "owner"));
  EXPECT_TRUE(messages->GetMessage("ECHO", echo2->id, "point1"));
}

TEST_F(PrivateAreasTest, PersonalMailboxesAreSeparateFromOwnerAndEachOtherBeforeStorageAccess) {
  PointMailConfig config{true, {"IN"}, "OUT", {{"2:1/2.2", "points/p1"}, {"2:1/2.3", "points/p2"}}};
  for (const auto& point : config.points)
    ASSERT_TRUE(storage::ProvisionMailbox(temp.path(), point, *metadata));
  auto mailbox_areas = storage::MailboxAreas(config, *metadata);
  ASSERT_TRUE(mailbox_areas);
  std::vector<EchoAreaConfig> areas;
  for (const auto& [id, area] : catalog->areas())
    areas.push_back(area.config);
  areas.insert(areas.end(), mailbox_areas->begin(), mailbox_areas->end());
  auto opened = storage::JamCatalog::Build(temp.path(), areas);
  ASSERT_TRUE(opened);
  auto personal_catalog = std::shared_ptr<storage::JamCatalog>(std::move(*opened));
  auto policy = service::EchoAccess::Build(hpt, *personal_catalog, {"2:1/2.1"});
  ASSERT_TRUE(policy);
  service::ConferenceService catalog_service(personal_catalog, metadata, *policy);
  service::MessageService mail(personal_catalog, metadata, *policy);
  const auto first = storage::MailboxId("2:1/2.2"), second = storage::MailboxId("2:1/2.3");
  EXPECT_TRUE(catalog_service.GetConference(first, "point1"));
  EXPECT_TRUE(catalog_service.GetConference(second, "point2"));
  EXPECT_FALSE(catalog_service.GetConference(first, "point2"));
  EXPECT_FALSE(catalog_service.GetConference(first, "owner"));
  EXPECT_FALSE(catalog_service.GetConference(net, "point1"));
  auto list = catalog_service.GetConferences({}, std::nullopt, "point1");
  ASSERT_TRUE(list);
  EXPECT_EQ(list->total, 2);
  // Replacing a hidden base must not disclose a storage error before permission denial.
  std::filesystem::rename(temp.path() / "points/p1.jhr", temp.path() / "points/p1.old");
  std::ofstream(temp.path() / "points/p1.jhr") << "foreign";
  for (auto user : {"point2", "owner"}) {
    auto selected = mail.GetMessage(first, "known-id", user);
    ASSERT_FALSE(selected);
    EXPECT_EQ(selected.error().code, domain::ErrorCode::kForbidden);
    EXPECT_FALSE(mail.GetMessages(first, {}, "oldest", user, "private"));
    EXPECT_FALSE(mail.GetThread(first, "known-id", user));
    EXPECT_FALSE(mail.MarkAsRead(first, "known-id", user));
    EXPECT_FALSE(mail.CreateMessage(first, Request("forbidden"), user));
  }
  EXPECT_FALSE(catalog_service.GetConference(first, "point1"));
  auto still_other = catalog_service.GetConference(second, "point2");
  ASSERT_TRUE(still_other);
  EXPECT_EQ(still_other->total_count, 0);
  EXPECT_TRUE(metadata->MailboxBindings());
}

TEST_F(PrivateAreasTest, BridgeSeparatesRecipientsDeduplicatesAndRetainsOutgoingCopies) {
  auto config = Mailboxes();
  Incoming("2:1/2.2");
  Incoming("2:1/2.3");
  Incoming("2:1/2.2");
  Incoming("2:1/2", "2:1/9.7 boss");
  Incoming("2:1/2.4", "2:1/9.7 ordinary");
  Incoming("2:1/7.1", "2:1/9.7 transit");
  service::MailBridge bridge(config, hpt, catalog, metadata);
  ASSERT_TRUE(bridge.Dispatch());
  const auto p1 = storage::MailboxId("2:1/2.2"), p2 = storage::MailboxId("2:1/2.3");
  auto first = messages->GetMessages(p1, {}, "oldest", "point1");
  auto second = messages->GetMessages(p2, {}, "oldest", "point2");
  ASSERT_TRUE(first);
  ASSERT_TRUE(second);
  ASSERT_EQ(first->total, 1);
  ASSERT_EQ(second->total, 1);
  EXPECT_EQ(first->messages.front().direction, 1);
  EXPECT_FALSE(first->messages.front().is_read);
  auto original = messages->GetMessage(p1, first->messages.front().id, "point1");
  ASSERT_TRUE(original);
  EXPECT_EQ(original->body, "Н входящее");
  EXPECT_FALSE(messages->GetMessages(p1, {}, "oldest", "point2"));
  auto remote = messages->CreateMessage(p1, Request("remote"), "point1");
  ASSERT_TRUE(remote);
  auto local_request = Request("local");
  local_request.to_address = "2:1/2.3";
  auto local = messages->CreateMessage(p1, local_request, "point1");
  ASSERT_TRUE(local);
  EXPECT_EQ(metadata->PendingOutbox()->size(), 2u);
  auto own = messages->GetMessage(p1, remote->id, "point1");
  ASSERT_TRUE(own);
  EXPECT_TRUE(own->is_read);
  EXPECT_EQ(own->direction, 2);
  ASSERT_TRUE(bridge.Dispatch());
  EXPECT_TRUE(metadata->PendingOutbox()->empty());
  auto again = messages->GetMessages(p1, {}, "oldest", "point1");
  ASSERT_TRUE(again);
  EXPECT_EQ(again->total, 3);
  auto delivered = messages->GetMessages(p2, {}, "oldest", "point2");
  ASSERT_TRUE(delivered);
  EXPECT_EQ(delivered->total, 2);
  const auto transport = test::SmapiOracle({"read", (temp.path() / "OUT").string(), "1"});
  EXPECT_EQ(transport.at("origin"), "2:1/2.2");
  EXPECT_EQ(transport.at("destination"), "2:1/3.4");
  EXPECT_FALSE(transport.at("locked"));
  ASSERT_TRUE(bridge.Dispatch());
  EXPECT_EQ(messages->GetMessages(p1, {}, "oldest", "point1")->total, 3);
  EXPECT_EQ(messages->GetMessages(p2, {}, "oldest", "point2")->total, 2);
  const auto ingress = test::ReadJamWireRecord(temp.path() / "MAIL", 0);
  EXPECT_TRUE(test::Wire32(ingress.header, 52) & 0x40000000u);
  const auto ordinary = test::ReadJamWireRecord(temp.path() / "MAIL", 4);
  EXPECT_FALSE(test::Wire32(ordinary.header, 52) & 0x40000000u);
}

TEST_F(PrivateAreasTest, BridgeQuarantinesCollisionAndMissingIdentityWithoutLosingSource) {
  auto config = Mailboxes();
  Incoming("2:1/2.2");
  Incoming("2:1/2.2", "2:1/9.7 same", "Different body");
  Incoming("2:1/2.3", "");
  service::MailBridge bridge(config, hpt, catalog, metadata);
  ASSERT_TRUE(bridge.Dispatch());
  auto records = metadata->MailTransfers();
  ASSERT_TRUE(records);
  ASSERT_EQ(records->size(), 3u);
  EXPECT_EQ(records->at(1).state, storage::TransferState::kQuarantine);
  EXPECT_EQ(records->at(2).state, storage::TransferState::kQuarantine);
  EXPECT_EQ(messages->GetMessages(storage::MailboxId("2:1/2.2"), {}, "oldest", "point1")->total, 1);
  EXPECT_EQ(messages->GetMessages(storage::MailboxId("2:1/2.3"), {}, "oldest", "point2")->total, 0);
  for (size_t i = 0; i < 3; ++i)
    EXPECT_TRUE(test::Wire32(test::ReadJamWireRecord(temp.path() / "MAIL", i).header, 52) & 0x40000000u);
  ASSERT_TRUE(bridge.Recover());
}

namespace {
class MailBridgeCrashTest : public PrivateAreasTest,
                            public ::testing::WithParamInterface<std::pair<std::string, std::string>> {};
}  // namespace
TEST_P(MailBridgeCrashTest, RecoversEveryTransferBoundaryWithoutDuplicateAppend) {
  auto config = Mailboxes();
  const auto [mode, stage] = GetParam();
  const auto p1 = storage::MailboxId("2:1/2.2"), p2 = storage::MailboxId("2:1/2.3");
  if (mode == "incoming")
    Incoming("2:1/2.2");
  else {
    auto request = Request("fault-send");
    if (mode == "local")
      request.to_address = "2:1/2.3";
    if (mode == "self")
      request.to_address = "2:1/2.2";
    ASSERT_TRUE(messages->CreateMessage(p1, request, "point1"));
  }
  bool hit = false;
  service::MailBridge interrupted(config, hpt, catalog, metadata, std::make_shared<storage::JamIo>(),
                                  [&](std::string_view cut) {
                                    if (cut == stage && !hit) {
                                      hit = true;
                                      throw std::runtime_error("simulated crash");
                                    }
                                  });
  EXPECT_FALSE(interrupted.Dispatch());
  ASSERT_TRUE(hit);
  std::vector<EchoAreaConfig> areas;
  for (const auto& [id, area] : catalog->areas())
    areas.push_back(area.config);
  auto reopened = storage::JamCatalog::Build(temp.path(), areas);
  ASSERT_TRUE(reopened);
  catalog = std::shared_ptr<storage::JamCatalog>(std::move(*reopened));
  service::MailBridge recovered(config, hpt, catalog, metadata);
  ASSERT_TRUE(recovered.Recover());
  ASSERT_TRUE(recovered.Dispatch());
  ASSERT_TRUE(recovered.Dispatch());
  auto policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
  ASSERT_TRUE(policy);
  service::MessageService mail(catalog, metadata, *policy);
  auto first = mail.GetMessages(p1, {}, "oldest", "point1"), second = mail.GetMessages(p2, {}, "oldest", "point2");
  ASSERT_TRUE(first);
  ASSERT_TRUE(second);
  EXPECT_EQ(first->total, mode == "self" ? 2 : 1);
  EXPECT_EQ(second->total, mode == "local" ? 1 : 0);
  EXPECT_TRUE(metadata->PendingOutbox()->empty());
  EXPECT_EQ(std::filesystem::file_size(temp.path() / "OUT.jdx"), mode == "egress" ? 8u : 0u);
  if (mode == "self") {
    EXPECT_EQ(first->messages[0].direction, 2);
    EXPECT_TRUE(first->messages[0].is_read);
    EXPECT_EQ(first->messages[1].direction, 1);
    EXPECT_FALSE(first->messages[1].is_read);
  }
}
INSTANTIATE_TEST_SUITE_P(Boundaries, MailBridgeCrashTest,
                         ::testing::Values(std::pair{"incoming", "intent"}, std::pair{"incoming", "claim"},
                                           std::pair{"incoming", "append"}, std::pair{"incoming", "bind"},
                                           std::pair{"egress", "intent"}, std::pair{"egress", "append"},
                                           std::pair{"egress", "bind"}, std::pair{"egress", "unlock"},
                                           std::pair{"local", "intent"}, std::pair{"local", "append"},
                                           std::pair{"local", "bind"}, std::pair{"self", "intent"},
                                           std::pair{"self", "append"}, std::pair{"self", "bind"}));

namespace {
class TransferIoFault : public storage::JamIo {
public:
  int fail, calls = 0;
  bool write_fault, hit = false;
  TransferIoFault(int position, bool write) : fail(position), write_fault(write) {
  }
  ssize_t Write(int fd, const void* bytes, size_t size, off_t offset) override {
    if (write_fault && (hit || ++calls == fail)) {
      if (!hit && size > 1) {
        hit = true;
        return storage::JamIo::Write(fd, bytes, 1, offset);
      }
      hit = true;
      errno = ENOSPC;
      return -1;
    }
    return storage::JamIo::Write(fd, bytes, size, offset);
  }
  int Sync(int fd) override {
    if (!write_fault && ++calls == fail) {
      hit = true;
      errno = EIO;
      return -1;
    }
    return storage::JamIo::Sync(fd);
  }
};
class MailBridgeIoTest : public PrivateAreasTest, public ::testing::WithParamInterface<std::tuple<bool, bool, int>> {};
}  // namespace
TEST_P(MailBridgeIoTest, ShortWritesEnospcAndFailedFsyncRecoverTheSameDelivery) {
  const auto [outgoing, write, position] = GetParam();
  auto config = Mailboxes();
  const auto p1 = storage::MailboxId("2:1/2.2");
  if (outgoing)
    ASSERT_TRUE(messages->CreateMessage(p1, Request("io-send"), "point1"));
  else
    Incoming("2:1/2.2");
  auto io = std::make_shared<TransferIoFault>(position, write);
  service::MailBridge interrupted(config, hpt, catalog, metadata, io);
  EXPECT_FALSE(interrupted.Dispatch());
  ASSERT_TRUE(io->hit);
  std::vector<EchoAreaConfig> areas;
  for (const auto& [id, area] : catalog->areas())
    areas.push_back(area.config);
  auto reopened = storage::JamCatalog::Build(temp.path(), areas);
  ASSERT_TRUE(reopened);
  catalog = std::shared_ptr<storage::JamCatalog>(std::move(*reopened));
  service::MailBridge recovered(config, hpt, catalog, metadata);
  ASSERT_TRUE(recovered.Recover());
  ASSERT_TRUE(recovered.Dispatch());
  ASSERT_TRUE(recovered.Dispatch());
  auto policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
  ASSERT_TRUE(policy);
  service::MessageService mail(catalog, metadata, *policy);
  auto list = mail.GetMessages(p1, {}, "oldest", "point1");
  ASSERT_TRUE(list);
  EXPECT_EQ(list->total, 1);
  EXPECT_TRUE(metadata->PendingOutbox()->empty());
  EXPECT_EQ(std::filesystem::file_size(temp.path() / "OUT.jdx"), outgoing ? 8u : 0u);
}
INSTANTIATE_TEST_SUITE_P(Io, MailBridgeIoTest,
                         ::testing::Combine(::testing::Bool(), ::testing::Bool(), ::testing::Range(1, 6)));

TEST_F(PrivateAreasTest, PersonalSendRetryAndReplyUseDurableDirectionAndAuthenticatedAuthor) {
  auto config = Mailboxes();
  const auto p1 = storage::MailboxId("2:1/2.2");
  auto request = Request("personal-retry");
  auto sent = messages->CreateMessage(p1, request, "point1");
  ASSERT_TRUE(sent);
  auto retry = messages->CreateMessage(p1, request, "point1");
  ASSERT_TRUE(retry);
  EXPECT_EQ(retry->id, sent->id);
  EXPECT_EQ(retry->ftn_message_id, sent->ftn_message_id);
  EXPECT_EQ(metadata->PendingOutbox()->size(), 1u);
  request.body += " changed";
  auto conflict = messages->CreateMessage(p1, request, "point1");
  ASSERT_FALSE(conflict);
  EXPECT_EQ(conflict.error().code, domain::ErrorCode::kConflict);
  auto reply_request = Request("own-reply");
  reply_request.in_reply_to = sent->id;
  reply_request.to_address.clear();
  reply_request.to_name.clear();
  auto reply = messages->CreateMessage(p1, reply_request, "point1");
  ASSERT_TRUE(reply);
  auto detail = messages->GetMessage(p1, reply->id, "point1");
  ASSERT_TRUE(detail);
  EXPECT_EQ(detail->to_address, "2:1/3.4");
  EXPECT_EQ(detail->from_address, "2:1/2.2");
  EXPECT_EQ(detail->direction, 2);
  Incoming("2:1/2.2");
  service::MailBridge bridge(config, hpt, catalog, metadata);
  ASSERT_TRUE(bridge.Dispatch());
  auto all = messages->GetMessages(p1, {}, "oldest", "point1");
  ASSERT_TRUE(all);
  const auto incoming = std::find_if(all->messages.begin(), all->messages.end(),
                                     [](const auto& message) { return message.direction == 1; });
  ASSERT_NE(incoming, all->messages.end());
  reply_request.operation_id = "incoming-reply";
  reply_request.in_reply_to = incoming->id;
  auto answer = messages->CreateMessage(p1, reply_request, "point1");
  ASSERT_TRUE(answer);
  EXPECT_EQ(messages->GetMessage(p1, answer->id, "point1")->to_address, "2:1/9.7");
}

TEST_F(PrivateAreasTest, LastOpenedAnchorSurvivesPaginationAndNeverMarksAnotherMessage) {
  auto config = Mailboxes();
  for (int i = 0; i < 45; ++i)
    Incoming("2:1/2.2", "2:1/9.7 unique" + std::to_string(i));
  service::MailBridge bridge(config, hpt, catalog, metadata);
  ASSERT_TRUE(bridge.Dispatch());
  const auto p1 = storage::MailboxId("2:1/2.2");
  auto list = messages->GetMessages(p1, {0, 100}, "oldest", "point1");
  ASSERT_TRUE(list);
  ASSERT_EQ(list->total, 45);
  const auto id = list->messages.at(4).id;
  std::map<std::string, std::string> before;
  for (auto ext : {".jhr", ".jdt", ".jdx"})
    before[ext] = test::ReadFile(temp.path() / (std::string("points/p1") + ext));
  auto opened = messages->GetMessage(p1, id, "point1");
  ASSERT_TRUE(opened);
  EXPECT_GT(opened->position_revision, 0u);
  auto state = conferences->GetConference(p1, "point1");
  ASSERT_TRUE(state);
  EXPECT_TRUE(state->personal_mailbox);
  EXPECT_EQ(state->last_opened_message, id);
  EXPECT_EQ(state->position_revision, opened->position_revision);
  EXPECT_EQ(state->unread_count, 44);
  auto anchor = messages->GetMessages(p1, {0, 10}, "newest", "point1", "", id);
  ASSERT_TRUE(anchor);
  EXPECT_EQ(anchor->actual_offset, 40);
  EXPECT_TRUE(
      std::any_of(anchor->messages.begin(), anchor->messages.end(), [&](const auto& row) { return row.id == id; }));
  EXPECT_FALSE(messages->GetMessages(p1, {0, 10}, "newest", "point1", "absent-filter", id));
  EXPECT_FALSE(messages->GetMessages(p1, {0, 10}, "newest", "point2", "", id));
  EXPECT_EQ(metadata->LastOpened("point1", p1)->revision, opened->position_revision);
  for (const auto& [extension, bytes] : before)
    EXPECT_EQ(test::ReadFile(temp.path() / ("points/p1" + extension)), bytes);
  auto view = storage::JamAccess::Open(*catalog, p1, true, std::chrono::steady_clock::now() + std::chrono::seconds(5));
  ASSERT_TRUE(view);
  const auto index = test::ReadFile(temp.path() / "points/p1.jdx");
  const auto offset = test::Wire32(index, 4 * 8 + 4) + 52;
  std::array<uint8_t, 4> deleted{};
  msgapi::jam_wire::Put32(deleted.data(), 0x82000004u);
  ASSERT_EQ(pwrite((*view)->files().descriptors[0], deleted.data(), 4, offset), 4);
  auto base_header = (*view)->messages().base_header();
  --base_header.active_msgs;
  ++base_header.mod_counter;
  const auto changed = msgapi::jam_wire::Encode(base_header);
  ASSERT_EQ(pwrite((*view)->files().descriptors[0], changed.data(), changed.size(), 0), 1024);
  view->reset();
  EXPECT_FALSE(messages->GetMessages(p1, {0, 10}, "newest", "point1", "", id));
  auto removed = conferences->GetConference(p1, "point1");
  ASSERT_TRUE(removed);
  EXPECT_TRUE(removed->last_opened_message.empty());
  EXPECT_EQ(metadata->LastOpened("point1", p1)->revision, opened->position_revision);
}

TEST_F(PrivateAreasTest, ModifiedAcknowledgedCopyQuarantinesOutboxBeforeAnyTransportAppend) {
  auto config = Mailboxes();
  const auto p1 = storage::MailboxId("2:1/2.2");
  auto sent = messages->CreateMessage(p1, Request("tamper"), "point1");
  ASSERT_TRUE(sent);
  auto operation = metadata->FindOperation("point1", "tamper");
  ASSERT_TRUE(operation);
  ASSERT_TRUE(*operation);
  auto source =
      storage::JamAccess::Open(*catalog, p1, true, std::chrono::steady_clock::now() + std::chrono::seconds(5));
  ASSERT_TRUE(source);
  const char changed = 'X';
  ASSERT_EQ(pwrite((*source)->files().descriptors[1], &changed, 1, 0), 1);
  source->reset();
  service::MailBridge bridge(config, hpt, catalog, metadata);
  EXPECT_FALSE(bridge.Dispatch());
  EXPECT_EQ(std::filesystem::file_size(temp.path() / "OUT.jdx"), 0u);
  auto outbox = metadata->PendingOutbox();
  ASSERT_TRUE(outbox);
  ASSERT_EQ(outbox->size(), 1u);
  EXPECT_EQ(outbox->front().outbox_state, 3);
  EXPECT_EQ(outbox->front().plan.text, (**operation).plan.text);
  EXPECT_EQ(test::ReadFile(temp.path() / "points/p1.jdt").front(), 'X');
  EXPECT_FALSE(bridge.Dispatch());
  EXPECT_EQ(std::filesystem::file_size(temp.path() / "OUT.jdx"), 0u);
}

TEST_F(PrivateAreasTest, ChangedOutgoingPriorityCannotBecomeAnAuthenticatedClientIntent) {
  auto config = Mailboxes();
  const auto p1 = storage::MailboxId("2:1/2.2");
  ASSERT_TRUE(messages->CreateMessage(p1, Request("priority-tamper"), "point1"));
  auto operation = metadata->FindOperation("point1", "priority-tamper");
  ASSERT_TRUE(operation);
  ASSERT_TRUE(*operation);
  auto source =
      storage::JamAccess::Open(*catalog, p1, true, std::chrono::steady_clock::now() + std::chrono::seconds(5));
  ASSERT_TRUE(source);
  std::array<uint8_t, 4> flags{};
  msgapi::jam_wire::Put32(flags.data(), 0x02000105u);
  ASSERT_EQ(pwrite((*source)->files().descriptors[0], flags.data(), 4, (**operation).plan.original_sizes[0] + 52), 4);
  source->reset();
  service::MailBridge bridge(config, hpt, catalog, metadata);
  EXPECT_FALSE(bridge.Dispatch());
  ASSERT_EQ(metadata->PendingOutbox()->size(), 1u);
  EXPECT_EQ(metadata->PendingOutbox()->front().outbox_state, 3);
  EXPECT_EQ(std::filesystem::file_size(temp.path() / "OUT.jdx"), 0u);
}

TEST_F(PrivateAreasTest, SameMsgIdFromDifferentOriginsIsTwoAddressedDeliveries) {
  auto config = Mailboxes();
  Incoming("2:1/2.2", "same-msgid", "Same content", "2:1/9.7");
  Incoming("2:1/2.2", "same-msgid", "Same content", "2:1/9.8");
  service::MailBridge bridge(config, hpt, catalog, metadata);
  ASSERT_TRUE(bridge.Dispatch());
  ASSERT_TRUE(bridge.Dispatch());
  auto list = messages->GetMessages(storage::MailboxId("2:1/2.2"), {}, "oldest", "point1");
  ASSERT_TRUE(list);
  ASSERT_EQ(list->total, 2);
  EXPECT_EQ(list->messages[0].from_address, "2:1/9.7");
  EXPECT_EQ(list->messages[1].from_address, "2:1/9.8");
}

TEST_F(PrivateAreasTest, BulkReadAllSupportedAreasAndReadPermissionWithoutPost) {
  for (const auto& [id, area] : catalog->areas()) {
    const auto result = messages->MarkConferenceRead(id, "bulk-" + area.config.name, "owner");
    if (area.config.msgbase_type != "JAM") {
      EXPECT_FALSE(result);
    } else {
      ASSERT_TRUE(result) << id;
      EXPECT_EQ(result->snapshot_count, 0);
    }
  }
  for (auto& [address, permission] : hpt.echoes.front().links)
    permission.post = false;
  auto policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
  ASSERT_TRUE(policy);
  service::MessageService read_only(catalog, metadata, *policy);
  auto empty = read_only.MarkConferenceRead("ECHO", "empty", "point1");
  ASSERT_TRUE(empty);
  EXPECT_EQ(empty->snapshot_count, 0);
  EXPECT_TRUE(metadata->GetHistory("point1")->empty());
  EXPECT_EQ(metadata->LastOpened("point1", "ECHO")->revision, 0);
  auto missing = read_only.MarkConferenceRead("UNKNOWN", "bad", "point1");
  ASSERT_FALSE(missing);
  EXPECT_EQ(missing.error().code, domain::ErrorCode::kNotFound);
  hpt.echoes.front().links.erase("2:1/2.2");
  policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
  ASSERT_TRUE(policy);
  service::MessageService denied(catalog, metadata, *policy);
  EXPECT_FALSE(denied.MarkConferenceRead("ECHO", "empty", "point1"));
}

TEST_F(PrivateAreasTest, BulkReadPrivateSnapshotsReplayAndAccessBoundary) {
  const auto config = Mailboxes();
  const auto box = storage::MailboxId("2:1/2.2");
  int operation_number = 0;
  for (const auto& [id, area] : catalog->areas()) {
    if (area.config.msgbase_type != "JAM")
      continue;
    // Seed read-only areas through storage: the RPC must not grant publication.
    {
      auto view =
          storage::JamAccess::Open(*catalog, id, true, std::chrono::steady_clock::now() + std::chrono::seconds(2));
      ASSERT_TRUE(view) << id;
      msgapi::JamMessage message;
      message.SetText("fixture");
      message.SetSubject("fixture");
      EXPECT_EQ((*view)->messages().AddMessage(message), msgapi::JamError::kSuccess);
    }
    const std::string user = area.files->personal_mailbox ? (id == box ? "point1" : "point2") : "owner";
    const auto operation = "bulk-" + std::to_string(++operation_number);
    auto first = messages->MarkConferenceRead(id, operation, user);
    ASSERT_TRUE(first) << id;
    EXPECT_EQ(first->marked_count, 1);
    EXPECT_EQ(first->snapshot_count, 1);
    EXPECT_TRUE(*metadata->IsMessageRead(user, {id, first->generation, "1"}));
    const auto before = metadata->LastOpened(user, id).value();
    {
      auto view =
          storage::JamAccess::Open(*catalog, id, true, std::chrono::steady_clock::now() + std::chrono::seconds(2));
      ASSERT_TRUE(view);
      msgapi::JamMessage message;
      message.SetText("new arrival");
      EXPECT_EQ((*view)->messages().AddMessage(message), msgapi::JamError::kSuccess);
    }
    service::MessageService restarted(catalog, metadata, access);
    auto replay = restarted.MarkConferenceRead(id, operation, user);
    ASSERT_TRUE(replay);
    EXPECT_EQ(replay->snapshot_count, 1);
    EXPECT_FALSE(*metadata->IsMessageRead(user, {id, first->generation, "2"}));
    EXPECT_FALSE(*metadata->IsMessageRead("another", {id, first->generation, "1"}));
    EXPECT_EQ(metadata->LastOpened(user, id)->revision, before.revision);
    if (area.config.kind != AreaKind::kEcho) {
      const auto denied_user = user == "point1" ? "point2" : "point1";
      EXPECT_FALSE(messages->MarkConferenceRead(id, "denied", denied_user));
      EXPECT_FALSE(*metadata->FindBulkRead(denied_user, "denied", id));
    }
  }
  EXPECT_TRUE(metadata->GetHistory("owner")->empty());
  EXPECT_TRUE(metadata->GetHistory("point1")->empty());
  auto revoked = service::EchoAccess::Build(hpt, *catalog);
  ASSERT_TRUE(revoked);
  service::MessageService denied(catalog, metadata, *revoked);
  EXPECT_FALSE(denied.MarkConferenceRead(net, "bulk-MAIL", "owner"));
}

TEST_F(PrivateAreasTest, BulkReadSkipsDeletedAndNeverDecodesOrWritesJam) {
  ASSERT_TRUE(messages->CreateMessage("ECHO", Request("one"), "owner"));
  ASSERT_TRUE(messages->CreateMessage("ECHO", Request("two"), "owner"));
  {
    auto view =
        storage::JamAccess::Open(*catalog, "ECHO", true, std::chrono::steady_clock::now() + std::chrono::seconds(2));
    ASSERT_TRUE(view);
    EXPECT_EQ((*view)->messages().DeleteMessage(2), msgapi::JamError::kSuccess);
  }
  auto header = test::ReadFile(temp.path() / "ECHO.jhr");
  const auto chrs = header.find("CHRS: CP866");
  ASSERT_NE(chrs, std::string::npos);
  header.replace(chrs, 11, "CHRS: BOGUS");
  {
    std::ofstream out(temp.path() / "ECHO.jhr", std::ios::binary | std::ios::trunc);
    out.write(header.data(), header.size());
  }
  std::ofstream(temp.path() / "ECHO.jlr", std::ios::binary) << "fixture-jlr";
  std::map<std::string, std::string> before;
  for (auto extension : {"jhr", "jdx", "jdt", "jlr"})
    before[extension] = test::ReadFile(temp.path() / (std::string("ECHO.") + extension));
  auto result = messages->MarkConferenceRead("ECHO", "bulk", "point1");
  ASSERT_TRUE(result);
  EXPECT_EQ(result->snapshot_count, 1);
  EXPECT_EQ(result->marked_count, 1);
  EXPECT_FALSE(*metadata->IsMessageRead("point1", {"ECHO", result->generation, "2"}));
  for (const auto& [extension, bytes] : before)
    EXPECT_EQ(test::ReadFile(temp.path() / ("ECHO." + extension)), bytes);
}

TEST_F(PrivateAreasTest, HistoricalUtf8RepairPreservesApiIdentityAndMetadata) {
  std::vector<EchoAreaConfig> areas;
  for (const auto& [id, area] : catalog->areas())
    areas.push_back(area.config);
  auto rebuilt = storage::JamCatalog::Build(temp.path(), areas, {}, {{"ECHO", "UTF-8"}});
  ASSERT_TRUE(rebuilt);
  auto utf_catalog = std::shared_ptr<storage::JamCatalog>(std::move(*rebuilt));
  service::MessageService utf(utf_catalog, metadata, access);
  {
    auto view = storage::JamAccess::Open(*utf_catalog, "ECHO", true,
                                         std::chrono::steady_clock::now() + std::chrono::seconds(2));
    ASSERT_TRUE(view);
    for (int i = 0; i < 3; ++i) {
      msgapi::JamMessage message;
      message.SetSenderName("Автор");
      message.SetReceiverName("Получатель");
      message.SetSubject("Тема");
      message.SetText("Привет UTF-8");
      message.SetMsgId("2:1/2 fixture-" + std::to_string(i));
      EXPECT_EQ((*view)->messages().AddMessage(message), msgapi::JamError::kSuccess);
    }
  }
  const auto listed = utf.GetMessages("ECHO", {0, 1}, "oldest", "owner");
  ASSERT_TRUE(listed);
  const auto id = listed->messages.front().id;
  ASSERT_TRUE(utf.GetMessage("ECHO", id, "owner"));
  ASSERT_TRUE(metadata->AddBookmark("owner", "ECHO"));
  const auto position = metadata->LastOpened("owner", "ECHO").value();
  const auto history = metadata->GetHistory("owner")->size();
  const auto original_header = test::ReadFile(temp.path() / "ECHO.jhr");
  const auto original_text = test::ReadFile(temp.path() / "ECHO.jdt");
  for (const auto& [extension, original] : {std::pair{"jhr", original_header}, {"jdt", original_text}}) {
    // Single-byte transport mapping applied to UTF-8 bytes, as in the incident.
    auto damaged =
        storage::ConvertText(std::string_view(extension) == "jhr" ? std::string{} : original, "CP866", "KOI8-R");
    ASSERT_TRUE(damaged);
    // Header binary layout must not be transformed: only textual fields are damaged.
    if (std::string_view(extension) == "jhr") {
      *damaged = original;
      for (const auto& value : {std::string("Автор"), std::string("Получатель"), std::string("Тема")}) {
        const auto replacement = storage::ConvertText(value, "CP866", "KOI8-R").value();
        size_t offset = 0;
        while ((offset = damaged->find(value, offset)) != std::string::npos) {
          damaged->replace(offset, value.size(), replacement);
          offset += replacement.size();
        }
      }
    }
    std::ofstream output(temp.path() / (std::string("ECHO.") + extension), std::ios::binary | std::ios::trunc);
    output.write(damaged->data(), damaged->size());
  }
  EXPECT_FALSE(utf.GetMessages("ECHO", {}, "oldest", "owner"));
  std::ofstream(temp.path() / "hpt.lock");
  const nlohmann::json configuration = {{"ftn",
                                         {{"jam_base_path", temp.path().string()},
                                          {"coordination_lock", (temp.path() / "hpt.lock").string()},
                                          {"jam_encoding_overrides", {{"ECHO", "UTF-8"}}}}}};
  std::ofstream(temp.path() / "repair.json") << configuration;
  const std::string program = R"PY(
import hashlib, json, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1]); script = sys.argv[2]
report = root/'report.json'; marker = root/'maintenance.json'
command = [sys.executable, script, '--config', str(root/'repair.json'), '--base', 'ECHO', '--report', str(report)]
subprocess.run(command, check=True)
marker.write_text(json.dumps({'report_sha256': hashlib.sha256(report.read_bytes()).hexdigest(), 'stopped': ['backend','hpt','jamnntpd','cron']}))
subprocess.run(command + ['--apply', '--backup', str(root/'backup'), '--maintenance-file', str(marker)], check=True)
)PY";
  std::vector<std::string> args = {
      FFIDO_PYTHON, "-c", program, temp.path().string(),
      (std::filesystem::path(FFIDO_HPT_WRAPPER).parent_path() / "repair_jam_utf8.py").string()};
  std::vector<char*> pointers;
  for (auto& argument : args)
    pointers.push_back(argument.data());
  pointers.push_back(nullptr);
  pid_t child;
  ASSERT_EQ(posix_spawn(&child, args[0].c_str(), nullptr, nullptr, pointers.data(), environ), 0);
  int status = 0;
  ASSERT_EQ(waitpid(child, &status, 0), child);
  ASSERT_TRUE(WIFEXITED(status));
  ASSERT_EQ(WEXITSTATUS(status), 0);
  EXPECT_EQ(test::ReadFile(temp.path() / "ECHO.jhr"), original_header);
  EXPECT_EQ(test::ReadFile(temp.path() / "ECHO.jdt"), original_text);
  EXPECT_EQ(metadata->LastOpened("owner", "ECHO")->revision, position.revision);
  EXPECT_EQ(metadata->LastOpened("owner", "ECHO")->message, position.message);
  EXPECT_EQ(metadata->GetHistory("owner")->size(), history);
  EXPECT_TRUE(*metadata->IsBookmarked("owner", "ECHO"));
  for (int offset = 0; offset < 3; ++offset) {
    const auto page = utf.GetMessages("ECHO", {offset, 1}, "oldest", "owner");
    ASSERT_TRUE(page);
    ASSERT_EQ(page->messages.size(), 1);
    if (offset == 0) {
      EXPECT_EQ(page->messages.front().id, id);
      EXPECT_TRUE(page->messages.front().is_read);
    } else {
      EXPECT_FALSE(page->messages.front().is_read);
    }
    auto detail = utf.GetMessage("ECHO", page->messages.front().id, "owner");
    ASSERT_TRUE(detail);
    EXPECT_EQ(detail->body, "Привет UTF-8");
    EXPECT_EQ(detail->from_name, "Автор");
    EXPECT_EQ(detail->subject, "Тема");
  }
}

TEST_F(PrivateAreasTest, UueOwnerAndPointMailboxesStayIsolated) {
  Mailboxes();
  service::UueService uue(catalog, metadata, access);
  const auto box = storage::MailboxId("2:1/2.2");
  auto request = Request("uue-private");
  request.body = ftn::uue::Encode("private bytes", "secret.bin").value();
  auto sent = messages->CreateMessage(box, request, "point1");
  ASSERT_TRUE(sent);
  auto found = uue.Search(box, "", 0, 10, "point1");
  ASSERT_TRUE(found);
  ASSERT_EQ(found->parts.size(), 1);
  auto file = uue.Assemble({found->parts[0].source}, false, "point1");
  ASSERT_TRUE(file);
  EXPECT_EQ(file->state, service::UueState::kReady);
  for (auto user : {"owner", "point2"}) {
    EXPECT_FALSE(uue.Search(box, "", 0, 10, user));
    EXPECT_FALSE(uue.Assemble({found->parts[0].source}, false, user));
    EXPECT_FALSE(uue.Chunk(file->id, 0, 20, user));
  }
  EXPECT_EQ(uue.Chunk(file->id, 0, 20, "point1")->bytes, "private bytes");
}

TEST_F(PrivateAreasTest, UueOwnerAndPointNetmailPublishAllPartsWithFrozenRecipient) {
  Mailboxes();
  UueConfig config;
  config.max_file_bytes = 50000;
  config.part_body_bytes = 4096;
  service::UueService uue(catalog, metadata, access, "cp866", std::chrono::steady_clock::now, config);
  for (const auto& [user, area] : {std::pair{"owner", net}, std::pair{"point1", storage::MailboxId("2:1/2.2")}}) {
    std::string bytes(10000, 'a');
    const auto digest = service::Sha256(bytes).value();
    std::string hash;
    for (auto b : digest) {
      hash += "0123456789abcdef"[b >> 4];
      hash += "0123456789abcdef"[b & 15];
    }
    const std::string operation = std::string("uue-net-") + user;
    ASSERT_TRUE(uue.Upload(operation, "a.bin", bytes.size(), hash, 0, bytes, user));
    auto request = Request(operation);
    auto sent = uue.Commit(area, request, user);
    ASSERT_TRUE(sent);
    ASSERT_EQ(sent->state, "completed");
    EXPECT_GT(sent->saved, 1);
    for (const auto& id : sent->messages) {
      auto part = messages->PeekMessage(area, id, user);
      ASSERT_TRUE(part);
      EXPECT_EQ(part->to_address, request.to_address);
      EXPECT_TRUE(part->attributes & uint32_t(msgapi::JamMessageAttribute::kPrivate));
      EXPECT_TRUE(part->attributes & uint32_t(msgapi::JamMessageAttribute::kTypeNet));
    }
    auto found = uue.Search(area, "", 0, 100, user);
    ASSERT_TRUE(found);
    std::vector<service::UueReference> sources;
    for (const auto& part : found->parts)
      sources.push_back(part.source);
    auto file = uue.Assemble(sources, false, user);
    ASSERT_TRUE(file);
    ASSERT_EQ(file->state, service::UueState::kReady);
    EXPECT_EQ(uue.Chunk(file->id, 0, 65536, user)->bytes, bytes);
  }
}

TEST_F(PrivateAreasTest, CompletedIngressSurvivesEncodingPolicyChangeWithoutReappend) {
  auto config = Mailboxes();
  Incoming("2:1/2.2", "2:1/9.7 encoding-change", "Привет Ёё");
  service::MailBridge original(config, hpt, catalog, metadata);
  ASSERT_TRUE(original.Dispatch());
  ASSERT_EQ(metadata->MailTransfers()->size(), 1u);
  const auto mailbox = temp.path() / "points/p1";
  const auto body = test::ReadFile(mailbox.string() + ".jdt");
  const auto index = test::ReadFile(mailbox.string() + ".jdx");
  const auto header = test::ReadFile(mailbox.string() + ".jhr");
  std::vector<EchoAreaConfig> areas;
  for (const auto& [id, area] : catalog->areas())
    areas.push_back(area.config);
  config.ftn.jam_encoding_overrides = {{"MAIL", "KOI8-R"}};
  auto rebuilt = storage::JamCatalog::Build(temp.path(), areas, {}, config.ftn.jam_encoding_overrides);
  ASSERT_TRUE(rebuilt);
  auto next = std::shared_ptr<storage::JamCatalog>(std::move(*rebuilt));
  service::MailBridge changed(config, hpt, next, metadata);
  ASSERT_TRUE(changed.Dispatch());
  ASSERT_TRUE(changed.Dispatch());
  EXPECT_EQ(metadata->MailTransfers()->size(), 1u);
  EXPECT_EQ(test::ReadFile(mailbox.string() + ".jdt"), body);
  EXPECT_EQ(test::ReadFile(mailbox.string() + ".jdx"), index);
  EXPECT_EQ(test::ReadFile(mailbox.string() + ".jhr"), header);
}

TEST_F(PrivateAreasTest, MarkUnreadSupportsPrivateMailboxesAndReadOnlyAreasWithoutJamWrites) {
  Mailboxes();
  service::GrpcRuntime runtime;
  for (auto& [address, permission] : hpt.echoes.front().links)
    permission.post = false;
  auto rpc_policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
  ASSERT_TRUE(rpc_policy);
  service::GrpcService rpc(catalog, metadata, *rpc_policy);
  test::GenerateTlsCertificate(temp.path());
  grpc::SslServerCredentialsOptions tls;
  tls.pem_key_cert_pairs.push_back(
      {test::ReadFile(temp.path() / "key.pem"), test::ReadFile(temp.path() / "certificate.pem")});
  grpc::ServerBuilder builder;
  int port = 0;
  builder.AddListeningPort("127.0.0.1:0", grpc::SslServerCredentials(tls), &port);
  builder.RegisterService(&rpc);
  auto server = builder.BuildAndStart();
  ASSERT_TRUE(server);
  struct StopServer {
    grpc::Server& server;
    ~StopServer() {
      server.Shutdown();
      server.Wait();
    }
  } stop{*server};
  grpc::SslCredentialsOptions roots;
  roots.pem_root_certs = test::ReadFile(temp.path() / "certificate.pem");
  auto client =
      ffido::v1::Ffido::NewStub(grpc::CreateChannel("127.0.0.1:" + std::to_string(port), grpc::SslCredentials(roots)));
  service::AuthService auth(metadata);
  std::map<std::string, std::string> tokens;
  const auto expires =
      std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count() +
      3600;
  for (const auto& user : {"owner", "point1", "point2"}) {
    auto profile = metadata->GetProfile(user);
    ASSERT_TRUE(profile);
    auto token = auth.Provision(user, *profile, expires);
    ASSERT_TRUE(token);
    tokens.emplace(user, *token);
  }
  const auto mark = [&](const std::string& id, const std::string& message, const std::string& user) {
    ffido::v1::MessageReference request;
    request.set_conference_id(id);
    request.set_message_id(message);
    grpc::ClientContext context;
    context.AddMetadata("authorization", "Bearer " + tokens.at(user));
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(3));
    google::protobuf::Empty response;
    return client->MarkUnread(&context, request, &response);
  };
  for (const auto& [id, area] : catalog->areas()) {
    if (area.config.msgbase_type != "JAM") {
      EXPECT_FALSE(mark(id, "invalid#1", "owner").ok());
      continue;
    }
    std::string generation;
    {
      auto view =
          storage::JamAccess::Open(*catalog, id, true, std::chrono::steady_clock::now() + std::chrono::seconds(2));
      ASSERT_TRUE(view);
      msgapi::JamMessage message;
      message.SetText("fixture");
      message.SetSubject("fixture");
      ASSERT_EQ((*view)->messages().AddMessage(message), msgapi::JamError::kSuccess);
      generation = (*view)->generation();
    }
    const std::string user =
        area.files->personal_mailbox ? (id == storage::MailboxId("2:1/2.2") ? "point1" : "point2") : "owner";
    const auto key = storage::ReadKey{id, generation, "1"};
    ASSERT_TRUE(metadata->RecordMessageView(user, key));
    const auto position = *metadata->LastOpened(user, id);
    const auto path = temp.path() / area.config.filename;
    const auto header = test::ReadFile(path.string() + ".jhr");
    const auto text = test::ReadFile(path.string() + ".jdt");
    ASSERT_TRUE(mark(id, generation + "#1", user).ok()) << id;
    EXPECT_FALSE(*metadata->IsMessageRead(user, key));
    EXPECT_EQ(metadata->LastOpened(user, id)->revision, position.revision);
    EXPECT_EQ(test::ReadFile(path.string() + ".jhr"), header);
    EXPECT_EQ(test::ReadFile(path.string() + ".jdt"), text);
    if (area.config.kind != AreaKind::kEcho) {
      EXPECT_FALSE(mark(id, generation + "#1", user == "point1" ? "point2" : "point1").ok());
    }
  }
  for (auto& [address, permission] : hpt.echoes.front().links)
    permission.post = false;
  auto policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
  ASSERT_TRUE(policy);
  service::MessageService read_only(catalog, metadata, *policy);
  auto view =
      storage::JamAccess::Open(*catalog, "ECHO", false, std::chrono::steady_clock::now() + std::chrono::seconds(2));
  ASSERT_TRUE(view);
  const auto generation = (*view)->generation();
  view->reset();
  ASSERT_TRUE(read_only.MarkAsUnread("ECHO", generation + "#1", "point1"));
  ASSERT_TRUE(mark("ECHO", generation + "#1", "point1").ok());
  hpt.echoes.front().links.erase("2:1/2.2");
  policy = service::EchoAccess::Build(hpt, *catalog, {"2:1/2.1"});
  ASSERT_TRUE(policy);
  service::MessageService denied(catalog, metadata, *policy);
  EXPECT_FALSE(denied.MarkAsUnread("ECHO", generation + "#1", "point1"));
}
