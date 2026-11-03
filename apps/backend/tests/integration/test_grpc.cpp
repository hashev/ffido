#include <gtest/gtest.h>
#include <spawn.h>
#include <sys/resource.h>
#include <sys/wait.h>

#include <condition_variable>
#include <future>
#include <thread>

#include "../support/echo_access.hpp"
#include "../support/jam_wire_record.hpp"
#include "../support/mcp_process.hpp"
#include "../support/temp_directory.hpp"
#include "../support/tls_certificate.hpp"
#include "service/grpc_runtime.hpp"
#include "service/grpc_service.hpp"
using namespace fidoback;
namespace wire = ffido::v1;
TEST(GrpcRuntime, DeadlineDoesNotFreeLiveReferencesAndFinishedCleanupIsObserved) {
  service::GrpcRuntime runtime;
  grpc_init();
  EXPECT_FALSE(runtime.Shutdown(std::chrono::steady_clock::now()));
  grpc_shutdown();
  EXPECT_TRUE(runtime.Shutdown(std::chrono::steady_clock::now() + std::chrono::seconds(5)));
  EXPECT_TRUE(runtime.Shutdown(std::chrono::steady_clock::now()));
}
namespace {
class GrpcTest : public ::testing::Test {
protected:
  service::GrpcRuntime runtime;
  test::TempDirectory temp;
  std::shared_ptr<storage::IMetadataStore> metadata;
  std::shared_ptr<storage::JamCatalog> catalog;
  std::unique_ptr<service::GrpcService> service;
  std::unique_ptr<grpc::Server> server;
  std::unique_ptr<wire::Ffido::Stub> client;
  std::string a, b, address;
  virtual int AreaCount() const {
    return 1;
  }
  virtual std::string Encoding() const {
    return "cp866";
  }
  virtual std::map<std::string, std::string> EncodingOverrides() const {
    return {};
  }
  virtual std::shared_ptr<const service::EchoAccess> AccessPolicy() const {
    return test::EchoAccess(*catalog, temp.path());
  }
  virtual grpc::Service* RegisteredService() {
    return service.get();
  }
  void SetUp() override {
    test::GenerateTlsCertificate(temp.path());
    auto base = temp.path() / "file";
    msgapi::JamBaseHeader header{};
    header.signature = msgapi::kJamSignature;
    header.base_msg_num = 42;
    header.date_created = 123;
    header.password_crc = UINT32_MAX;
    auto bytes = msgapi::jam_wire::Encode(header);
    {
      std::ofstream output(base.string() + ".jhr", std::ios::binary);
      output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    }
    for (auto extension : {".jdt", ".jdx"}) {
      std::ofstream output(base.string() + extension, std::ios::binary);
    }
    EchoAreaConfig area;
    area.name = "RU.TEST";
    area.filename = "file";
    area.msgbase_type = "JAM";
    auto coordination = storage::CoordinationLock::Open(temp.path() / "hpt.lock");
    ASSERT_TRUE(coordination);
    std::vector<EchoAreaConfig> areas{area};
    for (int i = 1; i < AreaCount(); ++i) {
      auto extra = area;
      extra.name = "RU.EXTRA" + std::to_string(i);
      extra.filename = "extra" + std::to_string(i);
      for (const auto* extension : {".jhr", ".jdt", ".jdx"})
        std::filesystem::copy_file(base.string() + extension, (temp.path() / extra.filename).string() + extension);
      areas.push_back(extra);
    }
    auto opened = storage::JamCatalog::Build(temp.path(), areas, *coordination, EncodingOverrides());
    ASSERT_TRUE(opened);
    catalog = std::shared_ptr<storage::JamCatalog>(std::move(*opened));
    metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
    ASSERT_TRUE(metadata->Init());
    service::AuthService auth(metadata);
    const auto expiry =
        std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count() +
        3600;
    auto issued = auth.Provision("A", domain::Profile{"Алексей", "2:5015/1.1", "", "2026-01-01T00:00:00Z"}, expiry);
    ASSERT_TRUE(issued);
    a = *issued;
    issued = auth.Provision("B", domain::Profile{"Борис", "2:5015/1.2", "", "2026-01-01T00:00:00Z"}, expiry);
    ASSERT_TRUE(issued);
    b = *issued;
    service = std::make_unique<service::GrpcService>(catalog, metadata, AccessPolicy(), Encoding());
    grpc::SslServerCredentialsOptions tls;
    tls.pem_key_cert_pairs.push_back(
        {test::ReadFile(temp.path() / "key.pem"), test::ReadFile(temp.path() / "certificate.pem")});
    grpc::ServerBuilder builder;
    int port = 0;
    builder.AddListeningPort("127.0.0.1:0", grpc::SslServerCredentials(tls), &port);
    builder.SetMaxReceiveMessageSize(2 * 1024 * 1024);
    builder.SetMaxSendMessageSize(32 * 1024 * 1024);
    builder.RegisterService(RegisteredService());
    server = builder.BuildAndStart();
    ASSERT_TRUE(server);
    ASSERT_GT(port, 0);
    address = "127.0.0.1:" + std::to_string(port);
    grpc::SslCredentialsOptions roots;
    roots.pem_root_certs = test::ReadFile(temp.path() / "certificate.pem");
    client = wire::Ffido::NewStub(grpc::CreateChannel(address, grpc::SslCredentials(roots)));
  }
  void TearDown() override {
    if (server) {
      server->Shutdown();
      server->Wait();
    }
    client.reset();
    server.reset();
    service.reset();
    EXPECT_TRUE(runtime.Shutdown(std::chrono::steady_clock::now() + std::chrono::seconds(5)));
  }
  void Auth(grpc::ClientContext& context, const std::string& token) {
    context.AddMetadata("authorization", "Bearer " + token);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(3));
  }
  wire::CreateMessageRequest Request(std::string id = "operation") {
    wire::CreateMessageRequest request;
    request.set_conference_id("RU.TEST");
    request.set_operation_id(id);
    request.set_subject("Русская тема");
    request.set_body("Привет, мир!");
    request.set_to_name("All");
    return request;
  }
};
}  // namespace
TEST_F(GrpcTest, TechnicalDataReturnsRawBytesWithoutReadingOrChangingStorage) {
  wire::MessageReference reference;
  {
    auto lease =
        storage::JamAccess::Open(*catalog, "RU.TEST", true, std::chrono::steady_clock::now() + std::chrono::seconds(2));
    ASSERT_TRUE(lease);
    msgapi::JamMessage raw;
    raw.SetText("Unrelated body");
    raw.SetMsgId("2:1/2@fidonet original");
    raw.SetReplyId("2:9/9 absent-parent");
    raw.SetAttribute(msgapi::JamMessageAttribute::kRead, true);
    raw.set_attributes2(0x80000001u);
    raw.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, std::string("X: \xff\0", 5));
    raw.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "", 7);
    ASSERT_EQ((*lease)->messages().AddMessage(raw), msgapi::JamError::kSuccess);
    reference.set_conference_id("RU.TEST");
    reference.set_message_id((*lease)->generation() + "#42");
  }
  const auto before = test::ReadJamWireRecord(temp.path() / "file", 0);
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto body = test::ReadFile(temp.path() / "file.jdt");
  const auto index = test::ReadFile(temp.path() / "file.jdx");
  for (int i = 0; i < 2; ++i) {
    wire::MessageTechnicalData result;
    grpc::ClientContext context;
    Auth(context, b);
    ASSERT_TRUE(client->GetMessageTechnicalData(&context, reference, &result).ok());
    EXPECT_EQ(result.message().message_id(), reference.message_id());
    EXPECT_EQ(result.attributes2(), 0x80000001u);
    EXPECT_EQ(result.attributes() & 8u, 8u);
    std::multimap<uint16_t, std::string> returned;
    bool empty_high = false;
    for (const auto& field : result.subfields()) {
      if (field.high_id() == 0)
        returned.emplace(field.low_id(), field.value());
      if (field.high_id() == 7)
        empty_high = field.value().empty();
    }
    EXPECT_TRUE(empty_high);
    EXPECT_EQ(returned, before.fields);
    EXPECT_EQ(result.attributes(), test::Wire32(before.header, 52));
    EXPECT_EQ(result.attributes2(), test::Wire32(before.header, 56));
    EXPECT_EQ(returned.find(5)->second, "2:9/9 absent-parent");
    EXPECT_TRUE(returned.contains(2000));
    EXPECT_FALSE(*metadata->IsMessageRead(
        "B", {"RU.TEST", reference.message_id().substr(0, reference.message_id().rfind('#')), "42"}));
    EXPECT_TRUE(metadata->GetHistory("B")->empty());
    EXPECT_EQ(metadata->LastOpened("B", "RU.TEST")->revision, 0);
  }
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), body);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
  grpc::ClientContext expired;
  Auth(expired, b);
  expired.set_deadline(std::chrono::system_clock::now() - std::chrono::seconds(1));
  wire::MessageTechnicalData ignored;
  EXPECT_EQ(client->GetMessageTechnicalData(&expired, reference, &ignored).error_code(),
            grpc::StatusCode::DEADLINE_EXCEEDED);
  grpc::ClientContext cancelled;
  Auth(cancelled, b);
  cancelled.TryCancel();
  EXPECT_EQ(client->GetMessageTechnicalData(&cancelled, reference, &ignored).error_code(), grpc::StatusCode::CANCELLED);
  {
    std::fstream file(temp.path() / "file.jhr", std::ios::in | std::ios::out | std::ios::binary);
    const std::array<char, 4> oversized{1, 0, 1, 0};  // 65537, little endian.
    file.seekp(test::Wire32(index, 4) + 8);
    file.write(oversized.data(), oversized.size());
  }
  ignored.Clear();
  grpc::ClientContext corrupt;
  Auth(corrupt, b);
  EXPECT_FALSE(client->GetMessageTechnicalData(&corrupt, reference, &ignored).ok());
  EXPECT_EQ(ignored.subfields_size(), 0);
}

TEST_F(GrpcTest, AllRpcTlsUnicodeEmptyAndTwoUsers) {
  wire::ListConferencesRequest list;
  list.mutable_page()->set_limit(20);
  list.set_sort(wire::CONFERENCE_SORT_NAME);
  wire::ListConferencesResponse conferences;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->ListConferences(&context, list, &conferences).ok());
    ASSERT_EQ(conferences.conferences_size(), 1);
  }
  wire::GetConferenceRequest conference;
  conference.set_conference_id("RU.TEST");
  wire::Conference detail;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->GetConference(&context, conference, &detail).ok());
    EXPECT_EQ(detail.total_count(), 0);
  }
  wire::ListMessagesRequest messages;
  messages.set_conference_id("RU.TEST");
  messages.mutable_page()->set_limit(20);
  messages.set_sort(wire::MESSAGE_SORT_DATE_DESCENDING);
  wire::ListMessagesResponse rows;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->ListMessages(&context, messages, &rows).ok());
    EXPECT_EQ(rows.total(), 0);
  }
  auto request = Request();
  wire::CreateMessageResponse created;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
    EXPECT_EQ(created.status(), wire::SAVE_STATUS_SAVED_LOCALLY);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    wire::CreateMessageResponse repeated;
    ASSERT_TRUE(client->CreateMessage(&context, request, &repeated).ok());
    EXPECT_EQ(repeated.message().message_id(), created.message().message_id());
  }
  wire::Message message;
  {
    grpc::ClientContext context;
    Auth(context, a);
    context.AddMetadata("x-user-id", "B");
    ASSERT_TRUE(client->GetMessage(&context, created.message(), &message).ok());
    EXPECT_EQ(message.from_name(), "Алексей");
    EXPECT_EQ(message.from_address(), "2:5015/1.1");
    EXPECT_EQ(message.subject(), "Русская тема");
    EXPECT_EQ(message.ftn_message_id(), created.ftn_message_id());
    EXPECT_TRUE(message.is_read());
    EXPECT_GT(message.date().seconds(), 0);
  }
  request = Request("reply");
  request.set_in_reply_to(created.message().message_id());
  request.set_to_name("wrong");
  request.set_to_address("2:999/999");
  wire::CreateMessageResponse reply;
  {
    grpc::ClientContext context;
    Auth(context, b);
    ASSERT_TRUE(client->CreateMessage(&context, request, &reply).ok());
  }
  wire::GetThreadRequest thread;
  thread.set_conference_id("RU.TEST");
  thread.set_thread_id(created.message().message_id());
  thread.mutable_page()->set_limit(20);
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->GetThread(&context, thread, &rows).ok());
    EXPECT_EQ(rows.total(), 2);
    ASSERT_EQ(rows.messages_size(), 2);
    EXPECT_EQ(rows.messages(1).to_name(), "Алексей");
    EXPECT_EQ(rows.messages(1).in_reply_to(), created.message().message_id());
  }
  google::protobuf::Empty empty, none;
  {
    grpc::ClientContext context;
    Auth(context, b);
    ASSERT_TRUE(client->MarkRead(&context, reply.message(), &none).ok());
    EXPECT_EQ(none.ByteSizeLong(), 0);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->AddBookmark(&context, conference, &none).ok());
  }
  wire::PageRequest page;
  page.set_limit(20);
  wire::ListBookmarksResponse bookmarks;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->ListBookmarks(&context, page, &bookmarks).ok());
    EXPECT_EQ(bookmarks.total(), 1);
    EXPECT_GT(bookmarks.bookmarks(0).added_at().seconds(), 0);
  }
  {
    grpc::ClientContext context;
    Auth(context, b);
    ASSERT_TRUE(client->ListBookmarks(&context, page, &bookmarks).ok());
    EXPECT_EQ(bookmarks.total(), 0);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->RemoveBookmark(&context, conference, &none).ok());
  }
  wire::ListHistoryResponse history;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->ListHistory(&context, page, &history).ok());
    EXPECT_EQ(history.total(), 1);
    EXPECT_GT(history.history(0).viewed_at().seconds(), 0);
  }
  {
    grpc::ClientContext context;
    Auth(context, b);
    ASSERT_TRUE(client->ListHistory(&context, page, &history).ok());
    EXPECT_EQ(history.total(), 0);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->ClearHistory(&context, empty, &none).ok());
  }
  wire::Profile profile;
  {
    grpc::ClientContext context;
    Auth(context, a);
    context.AddMetadata("x-user-id", "B");
    ASSERT_TRUE(client->GetProfile(&context, empty, &profile).ok());
    EXPECT_EQ(profile.user_id(), "A");
    EXPECT_EQ(profile.address(), "2:5015/1.1");
  }
  {
    grpc::ClientContext context;
    Auth(context, b);
    ASSERT_TRUE(client->GetProfile(&context, empty, &profile).ok());
    EXPECT_EQ(profile.user_id(), "B");
  }
}
TEST_F(GrpcTest, EveryRpcRequiresTokenBeforeValidationOrSideEffects) {
#define UNAUTH(call, request, response)                                                                    \
  {                                                                                                        \
    grpc::ClientContext context;                                                                           \
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(2));                      \
    EXPECT_EQ(client->call(&context, request, &response).error_code(), grpc::StatusCode::UNAUTHENTICATED); \
  }
  wire::ListConferencesRequest conferences;
  wire::ListConferencesResponse conferences_out;
  UNAUTH(ListConferences, conferences, conferences_out)
  wire::GetConferenceRequest conference;
  wire::Conference conference_out;
  UNAUTH(GetConference, conference, conference_out)
  wire::ListMessagesRequest list;
  wire::ListMessagesResponse list_out;
  UNAUTH(ListMessages, list, list_out)
  wire::MessageReference reference;
  wire::Message message;
  UNAUTH(GetMessage, reference, message)
  wire::MessageTechnicalData technical;
  UNAUTH(GetMessageTechnicalData, reference, technical)
  google::protobuf::Empty filter_empty;
  wire::PersonalMessageFilterSet filter_set;
  wire::ReplacePersonalMessageFiltersRequest filter_replace;
  wire::ReplacePersonalMessageFiltersResponse filter_saved;
  wire::GetMessagePresentationRequest filter_open;
  wire::MessagePresentation filter_view;
  UNAUTH(GetPersonalMessageFilters, filter_empty, filter_set)
  UNAUTH(ReplacePersonalMessageFilters, filter_replace, filter_saved)
  UNAUTH(GetMessagePresentation, filter_open, filter_view)

  auto create = Request();
  wire::CreateMessageResponse created;
  UNAUTH(CreateMessage, create, created)
  google::protobuf::Empty empty, none;
  UNAUTH(MarkRead, reference, none)
  UNAUTH(MarkUnread, reference, none)
  wire::GetThreadRequest thread;
  UNAUTH(GetThread, thread, list_out)
  wire::PageRequest page;
  wire::ListBookmarksResponse bookmarks;
  UNAUTH(ListBookmarks, page, bookmarks)
  UNAUTH(AddBookmark, conference, none) UNAUTH(RemoveBookmark, conference, none) wire::ListHistoryResponse history;
  UNAUTH(ListHistory, page, history) UNAUTH(ClearHistory, empty, none) wire::Profile profile;
  UNAUTH(GetProfile, empty, profile)
  wire::UueLimits uue_limits;
  UNAUTH(GetUueLimits, empty, uue_limits)
  wire::SearchUuePartsRequest uue_search;
  wire::SearchUuePartsResponse uue_parts;
  UNAUTH(SearchUueParts, uue_search, uue_parts)
  wire::AssembleUueRequest uue_assemble;
  wire::UueAttachment uue_attachment;
  UNAUTH(AssembleUue, uue_assemble, uue_attachment)
  wire::GetUueChunkRequest uue_get;
  wire::UueChunk uue_bytes;
  UNAUTH(GetUueChunk, uue_get, uue_bytes)
  wire::UploadUueChunkRequest uue_upload;
  wire::UueUploadStatus uue_uploaded;
  UNAUTH(UploadUueChunk, uue_upload, uue_uploaded)
  wire::CommitUueRequest uue_commit;
  wire::UueSendStatus uue_status;
  UNAUTH(CommitUue, uue_commit, uue_status)
  wire::UueOperationReference uue_operation;
  UNAUTH(GetUueSendStatus, uue_operation, uue_status)
#undef UNAUTH
  auto access =
      storage::JamAccess::Open(*catalog, "RU.TEST", false, std::chrono::steady_clock::now() + std::chrono::seconds(1));
  ASSERT_TRUE(access);
  EXPECT_EQ((*access)->messages().message_count(), 0);
  EXPECT_TRUE(metadata->GetBookmarks("A")->empty());
  EXPECT_TRUE(metadata->GetHistory("A")->empty());
}
TEST_F(GrpcTest, BulkReadAllPagesNewArrivalsAndUserIsolation) {
  wire::CreateMessageResponse created;
  for (int i = 0; i < 25; ++i) {
    grpc::ClientContext context;
    Auth(context, b);
    ASSERT_TRUE(client->CreateMessage(&context, Request("bulk-message-" + std::to_string(i)), &created).ok());
  }
  wire::MarkConferenceReadRequest request;
  request.set_conference_id("RU.TEST");
  request.set_operation_id("bulk");
  wire::MarkConferenceReadResponse result;
  {
    grpc::ClientContext c;
    EXPECT_EQ(client->MarkConferenceRead(&c, request, &result).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  }
  {
    grpc::ClientContext c;
    Auth(c, a);
    ASSERT_TRUE(client->MarkConferenceRead(&c, request, &result).ok());
  }
  EXPECT_EQ(result.snapshot_count(), 25);
  EXPECT_EQ(result.marked_count(), 25);
  EXPECT_TRUE(metadata->GetHistory("A")->empty());
  EXPECT_EQ(metadata->LastOpened("A", "RU.TEST")->revision, 0);
  const auto receipt = result.SerializeAsString();
  {
    grpc::ClientContext c;
    Auth(c, b);
    ASSERT_TRUE(client->CreateMessage(&c, Request("after-bulk"), &created).ok());
  }
  {
    grpc::ClientContext c;
    Auth(c, a);
    ASSERT_TRUE(client->MarkConferenceRead(&c, request, &result).ok());
  }
  EXPECT_EQ(result.SerializeAsString(), receipt);
  wire::GetConferenceRequest ref;
  ref.set_conference_id("RU.TEST");
  wire::Conference conference;
  {
    grpc::ClientContext c;
    Auth(c, a);
    ASSERT_TRUE(client->GetConference(&c, ref, &conference).ok());
  }
  EXPECT_EQ(conference.unread_count(), 1);
  {
    grpc::ClientContext c;
    Auth(c, b);
    ASSERT_TRUE(client->GetConference(&c, ref, &conference).ok());
  }
  EXPECT_EQ(conference.unread_count(), 26);
}
TEST_F(GrpcTest, FieldDetailsNotFoundConflictAndInvalidTokens) {
  wire::ListConferencesRequest request;
  request.mutable_page()->set_offset(-1);
  request.mutable_page()->set_limit(0);
  request.set_sort(wire::CONFERENCE_SORT_NAME);
  wire::ListConferencesResponse response;
  grpc::ClientContext invalid;
  Auth(invalid, a);
  auto status = client->ListConferences(&invalid, request, &response);
  EXPECT_EQ(status.error_code(), grpc::StatusCode::INVALID_ARGUMENT);
  auto trailers = invalid.GetServerTrailingMetadata();
  auto found = trailers.find("ffido-error-details-bin");
  ASSERT_NE(found, trailers.end());
  wire::ErrorDetails details;
  ASSERT_TRUE(details.ParseFromArray(found->second.data(), found->second.size()));
  EXPECT_EQ(details.violations_size(), 2);
  wire::GetConferenceRequest missing;
  missing.set_conference_id("../file");
  wire::Conference conference;
  {
    grpc::ClientContext context;
    Auth(context, a);
    EXPECT_EQ(client->GetConference(&context, missing, &conference).error_code(), grpc::StatusCode::PERMISSION_DENIED);
  }
  auto create = Request();
  wire::CreateMessageResponse created;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->CreateMessage(&context, create, &created).ok());
  }
  create.set_body("different");
  {
    grpc::ClientContext context;
    Auth(context, a);
    EXPECT_EQ(client->CreateMessage(&context, create, &created).error_code(), grpc::StatusCode::ALREADY_EXISTS);
  }
  google::protobuf::Empty empty;
  wire::Profile profile;
  {
    grpc::ClientContext context;
    Auth(context, std::string(64, '0'));
    EXPECT_EQ(client->GetProfile(&context, empty, &profile).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  }
  service::AuthService auth(metadata);
  ASSERT_TRUE(auth.Revoke(a));
  {
    grpc::ClientContext context;
    Auth(context, a);
    EXPECT_EQ(client->GetProfile(&context, empty, &profile).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  }
}
TEST_F(GrpcTest, DeadlineWhileWaitingForJamMakesNoIntentOrMutation) {
  auto held = storage::JamLease::Acquire(catalog->Resolve("RU.TEST").value()->files, true,
                                         std::chrono::steady_clock::now() + std::chrono::seconds(1));
  ASSERT_TRUE(held);
  grpc::ClientContext context;
  Auth(context, a);
  context.set_deadline(std::chrono::system_clock::now() + std::chrono::milliseconds(50));
  wire::CreateMessageResponse response;
  EXPECT_EQ(client->CreateMessage(&context, Request(), &response).error_code(), grpc::StatusCode::DEADLINE_EXCEEDED);
  held->reset();
  auto journal = metadata->FindOperation("A", "operation");
  ASSERT_TRUE(journal);
  EXPECT_FALSE(*journal);
  auto access =
      storage::JamAccess::Open(*catalog, "RU.TEST", false, std::chrono::steady_clock::now() + std::chrono::seconds(1));
  ASSERT_TRUE(access);
  EXPECT_EQ((*access)->messages().message_count(), 0);
}
TEST_F(GrpcTest, TlsTrustAndResourceLimitsAreEnforced) {
  auto untrusted = wire::Ffido::NewStub(grpc::CreateChannel(address, grpc::SslCredentials({})));
  google::protobuf::Empty empty;
  wire::Profile profile;
  {
    grpc::ClientContext context;
    Auth(context, a);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(1));
    EXPECT_FALSE(untrusted->GetProfile(&context, empty, &profile).ok());
  }
  auto request = Request();
  request.set_body(std::string(2 * 1024 * 1024, 'x'));
  wire::CreateMessageResponse response;
  {
    grpc::ClientContext context;
    Auth(context, a);
    EXPECT_EQ(client->CreateMessage(&context, request, &response).error_code(), grpc::StatusCode::RESOURCE_EXHAUSTED);
  }
  auto operation = metadata->FindOperation("A", "operation");
  ASSERT_TRUE(operation);
  EXPECT_FALSE(*operation);
}

TEST_F(GrpcTest, CancelledExpiredAndDuplicateAuthorizationDoNotWrite) {
  google::protobuf::Empty empty;
  wire::Profile profile;
  {
    grpc::ClientContext context;
    Auth(context, a);
    context.AddMetadata("authorization", "Bearer " + b);
    EXPECT_EQ(client->GetProfile(&context, empty, &profile).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  }
  sqlite3* db = nullptr;
  ASSERT_EQ(sqlite3_open((temp.path() / "metadata.db").c_str(), &db), SQLITE_OK);
  ASSERT_EQ(sqlite3_exec(db, "UPDATE tokens SET expires_at=0 WHERE user_id='B'", nullptr, nullptr, nullptr), SQLITE_OK);
  sqlite3_close(db);
  {
    grpc::ClientContext context;
    Auth(context, b);
    EXPECT_EQ(client->GetProfile(&context, empty, &profile).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  }
  grpc::ClientContext cancelled;
  Auth(cancelled, a);
  cancelled.TryCancel();
  wire::CreateMessageResponse response;
  EXPECT_EQ(client->CreateMessage(&cancelled, Request(), &response).error_code(), grpc::StatusCode::CANCELLED);
  auto operation = metadata->FindOperation("A", "operation");
  ASSERT_TRUE(operation);
  EXPECT_FALSE(*operation);
}

TEST_F(GrpcTest, HptLoginTwoDevicesShareServerDataAndLogoutIsIndependent) {
  std::ofstream(temp.path() / "own.cfg") << "Name Fixture\nSysop Test\nLocation Test\nAddress 2:5015/1.1\n"
                                            "Link Boss\nAKA 2:5015/1\nOurAKA 2:5015/1.1\nSessionPwd fixture-a\n"
                                            "Link B\nAKA 2:5015/1.2\nOurAKA 2:5015/1.1\nSessionPwd fixture-b\n";
  auto snapshot = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, temp.path() / "own.cfg");
  ASSERT_TRUE(snapshot);
  ASSERT_TRUE(service->ConfigureAuth(snapshot->credentials, std::string(32, 'k')));
  auto login = [&](std::string password, wire::LoginResponse& result) {
    grpc::ClientContext context;
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(3));
    wire::LoginRequest request;
    request.set_name("Phone name");
    request.set_address("2:5015/1.1");
    request.set_password(password);
    return client->Login(&context, request, &result);
  };
  wire::LoginResponse phone, laptop, denied;
  EXPECT_EQ(login("wrong", denied).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  ASSERT_TRUE(login("fixture-a", phone).ok());
  ASSERT_TRUE(login("fixture-a", laptop).ok());
  EXPECT_TRUE(phone.session().supports_message_footer());
  EXPECT_EQ(phone.session().profile().user_id(), "A");
  EXPECT_EQ(phone.session().profile().name(), "Алексей");
  EXPECT_NE(phone.session_secret(), laptop.session_secret());
  const auto invoke = [&](const std::string& secret, auto operation) {
    grpc::ClientContext context;
    Auth(context, secret);
    return operation(context);
  };
  wire::CreateMessageResponse created;
  auto request = Request("phone-send");
  ASSERT_TRUE(
      invoke(phone.session_secret(), [&](auto& c) { return client->CreateMessage(&c, request, &created); }).ok());
  google::protobuf::Empty empty;
  wire::GetConferenceRequest conference;
  conference.set_conference_id("RU.TEST");
  ASSERT_TRUE(
      invoke(phone.session_secret(), [&](auto& c) { return client->AddBookmark(&c, conference, &empty); }).ok());
  wire::Message message;
  ASSERT_TRUE(invoke(phone.session_secret(), [&](auto& c) {
                return client->GetMessage(&c, created.message(), &message);
              }).ok());
  ASSERT_TRUE(invoke(laptop.session_secret(), [&](auto& c) {
                return client->GetMessage(&c, created.message(), &message);
              }).ok());
  EXPECT_TRUE(message.is_read());
  EXPECT_EQ(message.from_address(), "2:5015/1.1");
  EXPECT_EQ(message.body(), "Привет, мир!\n--- FFIDO\n * Origin: FFIDO (2:5015/1.1)\n");
  wire::PageRequest page;
  page.set_limit(20);
  wire::ListHistoryResponse history;
  ASSERT_TRUE(invoke(laptop.session_secret(), [&](auto& c) { return client->ListHistory(&c, page, &history); }).ok());
  EXPECT_EQ(history.total(), 1);
  wire::ListBookmarksResponse bookmarks;
  ASSERT_TRUE(
      invoke(laptop.session_secret(), [&](auto& c) { return client->ListBookmarks(&c, page, &bookmarks); }).ok());
  EXPECT_EQ(bookmarks.total(), 1);
  ASSERT_TRUE(invoke(phone.session_secret(), [&](auto& c) { return client->Logout(&c, empty, &empty); }).ok());
  wire::SessionInfo restored;
  EXPECT_EQ(invoke(phone.session_secret(), [&](auto& c) { return client->RestoreSession(&c, empty, &restored); })
                .error_code(),
            grpc::StatusCode::UNAUTHENTICATED);
  EXPECT_TRUE(
      invoke(laptop.session_secret(), [&](auto& c) { return client->RestoreSession(&c, empty, &restored); }).ok());
  EXPECT_TRUE(restored.supports_message_footer());
}
TEST_F(GrpcTest, LoginLimitsAndFieldValidationAreAppliedBeforeSessionCreation) {
  ASSERT_TRUE(service->ConfigureAuth({{"2:1/3", "fixture"}}, std::string(32, 'k')));
  wire::LoginRequest request;
  request.set_name("Name");
  request.set_address("2:1/3");
  request.set_password("wrong");
  wire::LoginResponse response;
  for (int i = 0; i < 10; ++i) {
    grpc::ClientContext context;
    EXPECT_EQ(client->Login(&context, request, &response).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  }
  grpc::ClientContext limited;
  EXPECT_EQ(client->Login(&limited, request, &response).error_code(), grpc::StatusCode::RESOURCE_EXHAUSTED);
  grpc::ClientContext oversized;
  request.set_password(std::string(9000, 'x'));
  EXPECT_EQ(client->Login(&oversized, request, &response).error_code(), grpc::StatusCode::RESOURCE_EXHAUSTED);
}

TEST_F(GrpcTest, LoginRejectsExpiredDeadlineAndInvalidFields) {
  ASSERT_TRUE(service->ConfigureAuth({{"2:1/3", "fixture"}}, std::string(32, 'k')));
  wire::LoginRequest request;
  request.set_name("Name");
  request.set_address("2:1/3");
  request.set_password("fixture");
  wire::LoginResponse response;
  grpc::ClientContext expired;
  expired.set_deadline(std::chrono::system_clock::now() - std::chrono::seconds(1));
  EXPECT_EQ(client->Login(&expired, request, &response).error_code(), grpc::StatusCode::DEADLINE_EXCEEDED);
  request.set_name("");
  grpc::ClientContext invalid;
  EXPECT_EQ(client->Login(&invalid, request, &response).error_code(), grpc::StatusCode::INVALID_ARGUMENT);
  EXPECT_EQ(invalid.GetServerTrailingMetadata().count("ffido-error-details-bin"), 1);
  wire::Profile profile;
  grpc::ClientContext unauthenticated;
  google::protobuf::Empty empty;
  EXPECT_EQ(client->GetProfile(&unauthenticated, empty, &profile).error_code(), grpc::StatusCode::UNAUTHENTICATED);
}

TEST_F(GrpcTest, UnsubscribedPointCannotBypassPolicyThroughAnyRpcOrPersonalList) {
  service::AuthService auth(metadata);
  const auto expiry =
      std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count() +
      3600;
  auto token = auth.Provision("C", domain::Profile{"Unsubscribed", "2:5015/1.3", "", ""}, expiry);
  ASSERT_TRUE(token);
  ASSERT_TRUE(metadata->AddBookmark("C", "RU.TEST"));
  ASSERT_TRUE(metadata->AddToHistory("C", "RU.TEST"));
  wire::GetConferenceRequest conference;
  conference.set_conference_id("RU.TEST");
  wire::MessageReference reference;
  reference.set_conference_id("RU.TEST");
  reference.set_message_id("known#42");
  auto check = [&](auto invoke) {
    grpc::ClientContext context;
    Auth(context, *token);
    EXPECT_EQ(invoke(context).error_code(), grpc::StatusCode::PERMISSION_DENIED);
  };
  check([&](auto& c) {
    wire::Conference r;
    return client->GetConference(&c, conference, &r);
  });
  check([&](auto& c) {
    wire::Message r;
    return client->GetMessage(&c, reference, &r);
  });
  check([&](auto& c) {
    google::protobuf::Empty r;
    return client->MarkRead(&c, reference, &r);
  });
  check([&](auto& c) {
    google::protobuf::Empty r;
    return client->AddBookmark(&c, conference, &r);
  });
  check([&](auto& c) {
    wire::ListMessagesRequest request;
    request.set_conference_id("RU.TEST");
    request.mutable_page()->set_limit(20);
    request.set_sort(wire::MESSAGE_SORT_DATE_DESCENDING);
    wire::ListMessagesResponse r;
    return client->ListMessages(&c, request, &r);
  });
  check([&](auto& c) {
    wire::GetThreadRequest request;
    request.set_conference_id("RU.TEST");
    request.set_thread_id("known#42");
    request.mutable_page()->set_limit(20);
    wire::ListMessagesResponse r;
    return client->GetThread(&c, request, &r);
  });
  check([&](auto& c) {
    wire::CreateMessageResponse r;
    return client->CreateMessage(&c, Request(), &r);
  });
  wire::PageRequest page;
  page.set_limit(20);
  {
    grpc::ClientContext c;
    Auth(c, *token);
    wire::ListBookmarksResponse response;
    ASSERT_TRUE(client->ListBookmarks(&c, page, &response).ok());
    EXPECT_EQ(response.total(), 0);
    EXPECT_FALSE(response.has_more());
  }
  {
    grpc::ClientContext c;
    Auth(c, *token);
    wire::ListHistoryResponse response;
    ASSERT_TRUE(client->ListHistory(&c, page, &response).ok());
    EXPECT_EQ(response.total(), 0);
  }
  EXPECT_EQ(metadata->GetHistory("C", 20)->size(), 1);
  {
    grpc::ClientContext c;
    Auth(c, *token);
    google::protobuf::Empty response;
    ASSERT_TRUE(client->RemoveBookmark(&c, conference, &response).ok());
  }
  EXPECT_TRUE(metadata->GetBookmarks("C")->empty());
  EXPECT_EQ(metadata->GetHistory("C", 20)->size(), 1);
  EXPECT_EQ(catalog->Resolve("RU.TEST").value()->files->identities[1].st_size, 0);
}

TEST_F(GrpcTest, Cp866PostingHasIndependentRawBodyAndTextSubfieldBytes) {
  ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"Автор Ёё", "2:5015/1.1", "", "2026-01-01T00:00:00Z"}));
  auto request = Request("cp866-raw");
  request.set_subject("Тема Ёё");
  request.set_to_name("Читатель Ёё");
  request.set_body("Привет, Ёжик ёжик!\n");
  wire::CreateMessageResponse created;
  grpc::ClientContext context;
  Auth(context, a);
  ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
  ASSERT_EQ(created.status(), wire::SAVE_STATUS_SAVED_LOCALLY);
  const auto record = test::ReadJamWireRecord(temp.path() / "file", 0);
  const std::string encoded = "\x8f\xe0\xa8\xa2\xa5\xe2, \xf0\xa6\xa8\xaa \xf1\xa6\xa8\xaa!";
  EXPECT_EQ(record.body, encoded + "\r--- FFIDO\r * Origin: FFIDO (2:5015/1.1)\r");
  EXPECT_EQ(record.Field(2), "\x80\xa2\xe2\xae\xe0 \xf0\xf1");
  EXPECT_EQ(record.Field(3), "\x97\xa8\xe2\xa0\xe2\xa5\xab\xec \xf0\xf1");
  EXPECT_EQ(record.Field(6), "\x92\xa5\xac\xa0 \xf0\xf1");
  EXPECT_TRUE(record.HasField(2000, "CHRS: CP866 2"));
  EXPECT_FALSE(record.HasField(2000, "CHRS: UTF-8 4"));
  wire::Message decoded;
  grpc::ClientContext read;
  Auth(read, a);
  ASSERT_TRUE(client->GetMessage(&read, created.message(), &decoded).ok());
  EXPECT_EQ(decoded.from_name(), "Автор Ёё");
  EXPECT_EQ(decoded.to_name(), "Читатель Ёё");
  EXPECT_EQ(decoded.subject(), "Тема Ёё");
  EXPECT_EQ(decoded.body(), "Привет, Ёжик ёжик!\n--- FFIDO\n * Origin: FFIDO (2:5015/1.1)\n");
}

TEST_F(GrpcTest, Cp866ReplyDoesNotInheritUtf8ParentAndRetryDoesNotAppend) {
  ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"НАвтор Ёё", "2:5015/1.1", "", "2026-01-01T00:00:00Z"}));
  std::string parent_id;
  {
    auto access = storage::JamAccess::Open(*catalog, "RU.TEST", true,
                                           std::chrono::steady_clock::now() + std::chrono::seconds(3), {}, "UTF-8");
    ASSERT_TRUE(access);
    msgapi::JamMessage parent;
    parent.SetSenderName("НЧитатель Ёё");
    parent.SetOriginAddress("2:5015/1.2");
    parent.SetReceiverName("All");
    parent.SetSubject("Тема Ёё");
    parent.SetText("НРодитель UTF-8\r");
    parent.SetMsgId("2:5015/1.2 parent-utf8");
    ASSERT_EQ((*access)->messages().AddMessage(parent), msgapi::JamError::kSuccess);
    parent_id = (*access)->generation() + "#42";
  }
  const auto parent_before = test::ReadJamWireRecord(temp.path() / "file", 0);
  EXPECT_TRUE(parent_before.HasField(2000, "CHRS: UTF-8 4"));
  EXPECT_EQ(parent_before.body, "НРодитель UTF-8\r");
  auto request = Request("cp866-reply");
  request.set_in_reply_to(parent_id);
  request.set_subject("Тема Ёё");
  request.set_body("Привет, Ёжик ёжик!");
  wire::CreateMessageResponse created;
  grpc::ClientContext context;
  Auth(context, a);
  ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
  const auto response = test::ReadJamWireRecord(temp.path() / "file", 1);
  EXPECT_EQ(response.number, 43);
  EXPECT_EQ(response.reply_to, 42);
  EXPECT_EQ(response.Field(5), "2:5015/1.2 parent-utf8");
  EXPECT_EQ(response.Field(2), "H\x80\xa2\xe2\xae\xe0 \xf0\xf1");
  EXPECT_EQ(response.Field(3), "H\x97\xa8\xe2\xa0\xe2\xa5\xab\xec \xf0\xf1");
  EXPECT_EQ(response.Field(6), "\x92\xa5\xac\xa0 \xf0\xf1");
  const std::string encoded = "\x8f\xe0\xa8\xa2\xa5\xe2, \xf0\xa6\xa8\xaa \xf1\xa6\xa8\xaa!";
  EXPECT_EQ(response.body, encoded + "\r--- FFIDO\r * Origin: FFIDO (2:5015/1.1)\r");
  EXPECT_TRUE(response.HasField(2000, "CHRS: CP866 2"));
  EXPECT_FALSE(response.HasField(2000, "CHRS: UTF-8 4"));
  const auto parent_after = test::ReadJamWireRecord(temp.path() / "file", 0);
  EXPECT_EQ(parent_after.header, parent_before.header);
  EXPECT_EQ(parent_after.body, parent_before.body);
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto body = test::ReadFile(temp.path() / "file.jdt");
  const auto index = test::ReadFile(temp.path() / "file.jdx");
  wire::CreateMessageResponse repeated;
  grpc::ClientContext retry;
  Auth(retry, a);
  ASSERT_TRUE(client->CreateMessage(&retry, request, &repeated).ok());
  EXPECT_EQ(repeated.message().message_id(), created.message().message_id());
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), body);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
}

TEST_F(GrpcTest, Cp866UnrepresentableBodySubjectAndNamesRejectWithoutJamOrIntent) {
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto body = test::ReadFile(temp.path() / "file.jdt");
  const auto index = test::ReadFile(temp.path() / "file.jdx");
  for (const std::string field : {"body", "subject", "recipient", "sender"}) {
    SCOPED_TRACE(field);
    ASSERT_TRUE(metadata->SaveProfile(
        "A", domain::Profile{field == "sender" ? "НАвтор 🙂" : "Автор Ёё", "2:5015/1.1", "", "2026-01-01T00:00:00Z"}));
    auto request = Request("cp866-bad-" + field);
    if (field == "body")
      request.set_body("НТекст 🙂");
    if (field == "subject")
      request.set_subject("НТема 漢");
    if (field == "recipient")
      request.set_to_name("НПолучатель 🙂");
    for (int attempt = 0; attempt < 2; ++attempt) {
      grpc::ClientContext context;
      Auth(context, a);
      wire::CreateMessageResponse response;
      EXPECT_EQ(client->CreateMessage(&context, request, &response).error_code(), grpc::StatusCode::INVALID_ARGUMENT);
      EXPECT_EQ(response.status(), wire::SAVE_STATUS_UNSPECIFIED);
      EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
      EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), body);
      EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
      auto operation = metadata->FindOperation("A", request.operation_id());
      ASSERT_TRUE(operation);
      EXPECT_FALSE(operation->has_value());
    }
  }
}

TEST_F(GrpcTest, Cp866CyrillicNUsesAsciiHInAllFieldsAndOriginalRequestForIdempotency) {
  ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"НН H нН", "2:5015/1.1", "", ""}));
  auto request = Request("normalize-n");
  request.set_subject("НН H нН");
  request.set_to_name("НН H нН");
  request.set_body("НН H нН");
  wire::CreateMessageResponse created;
  grpc::ClientContext context;
  Auth(context, a);
  ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
  const auto record = test::ReadJamWireRecord(temp.path() / "file", 0);
  const std::string expected = "HH H \xadH";
  EXPECT_EQ(record.Field(2), expected);
  EXPECT_EQ(record.Field(3), expected);
  EXPECT_EQ(record.Field(6), expected);
  EXPECT_EQ(record.body, expected + "\r--- FFIDO\r * Origin: FFIDO (2:5015/1.1)\r");
  EXPECT_TRUE(record.HasField(2000, "CHRS: CP866 2"));
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto body = test::ReadFile(temp.path() / "file.jdt");
  const auto index = test::ReadFile(temp.path() / "file.jdx");
  for (bool changed : {false, true}) {
    if (changed)
      request.set_body("HH H нH");
    grpc::ClientContext retry;
    Auth(retry, a);
    wire::CreateMessageResponse repeated;
    const auto status = client->CreateMessage(&retry, request, &repeated);
    if (changed)
      EXPECT_EQ(status.error_code(), grpc::StatusCode::ALREADY_EXISTS);
    else {
      ASSERT_TRUE(status.ok());
      EXPECT_EQ(repeated.message().message_id(), created.message().message_id());
    }
    EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
    EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), body);
    EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
  }
}

namespace {
class Koi8GrpcTest : public GrpcTest {
protected:
  std::string Encoding() const override {
    return "KOI8-R";
  }
};
}  // namespace

TEST_F(Koi8GrpcTest, Koi8PostingHasIndependentRawBodyAndTextSubfieldBytes) {
  ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"Автор Ёё", "2:5015/1.1", "", "2026-01-01T00:00:00Z"}));
  auto request = Request("koi8-raw");
  request.set_subject("Тема Ёё");
  request.set_to_name("Читатель Ёё");
  request.set_body("Привет, Ёжик ёжик!\n");
  wire::CreateMessageResponse created;
  grpc::ClientContext context;
  Auth(context, a);
  ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
  ASSERT_EQ(created.status(), wire::SAVE_STATUS_SAVED_LOCALLY);
  const auto record = test::ReadJamWireRecord(temp.path() / "file", 0);
  const std::string encoded = "\xf0\xd2\xc9\xd7\xc5\xd4, \xb3\xd6\xc9\xcb \xa3\xd6\xc9\xcb!";
  EXPECT_EQ(record.body, encoded + "\r--- FFIDO\r * Origin: FFIDO (2:5015/1.1)\r");
  EXPECT_EQ(record.Field(2), "\xe1\xd7\xd4\xcf\xd2 \xb3\xa3");
  EXPECT_EQ(record.Field(3), "\xfe\xc9\xd4\xc1\xd4\xc5\xcc\xd8 \xb3\xa3");
  EXPECT_EQ(record.Field(6), "\xf4\xc5\xcd\xc1 \xb3\xa3");
  EXPECT_TRUE(record.HasField(2000, "CHRS: KOI8-R 2"));
  EXPECT_FALSE(record.HasField(2000, "CHRS: UTF-8 4"));
  wire::Message decoded;
  grpc::ClientContext read;
  Auth(read, a);
  ASSERT_TRUE(client->GetMessage(&read, created.message(), &decoded).ok());
  EXPECT_EQ(decoded.from_name(), "Автор Ёё");
  EXPECT_EQ(decoded.to_name(), "Читатель Ёё");
  EXPECT_EQ(decoded.subject(), "Тема Ёё");
  EXPECT_EQ(decoded.body(), "Привет, Ёжик ёжик!\n--- FFIDO\n * Origin: FFIDO (2:5015/1.1)\n");
}

TEST_F(Koi8GrpcTest, Koi8ReplyDoesNotInheritUtf8ParentAndRetryDoesNotAppend) {
  ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"НАвтор Ёё", "2:5015/1.1", "", "2026-01-01T00:00:00Z"}));
  std::string parent_id;
  {
    auto access = storage::JamAccess::Open(*catalog, "RU.TEST", true,
                                           std::chrono::steady_clock::now() + std::chrono::seconds(3), {}, "UTF-8");
    ASSERT_TRUE(access);
    msgapi::JamMessage parent;
    parent.SetSenderName("НЧитатель Ёё");
    parent.SetOriginAddress("2:5015/1.2");
    parent.SetReceiverName("All");
    parent.SetSubject("Тема Ёё");
    parent.SetText("НРодитель UTF-8\r");
    parent.SetMsgId("2:5015/1.2 parent-utf8");
    ASSERT_EQ((*access)->messages().AddMessage(parent), msgapi::JamError::kSuccess);
    parent_id = (*access)->generation() + "#42";
  }
  const auto parent_before = test::ReadJamWireRecord(temp.path() / "file", 0);
  EXPECT_TRUE(parent_before.HasField(2000, "CHRS: UTF-8 4"));
  EXPECT_EQ(parent_before.body, "НРодитель UTF-8\r");
  auto request = Request("koi8-reply");
  request.set_in_reply_to(parent_id);
  request.set_subject("Тема Ёё");
  request.set_body("Привет, Ёжик ёжик!");
  wire::CreateMessageResponse created;
  grpc::ClientContext context;
  Auth(context, a);
  ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
  const auto response = test::ReadJamWireRecord(temp.path() / "file", 1);
  EXPECT_EQ(response.number, 43);
  EXPECT_EQ(response.reply_to, 42);
  EXPECT_EQ(response.Field(5), "2:5015/1.2 parent-utf8");
  EXPECT_EQ(response.Field(2), "H\xe1\xd7\xd4\xcf\xd2 \xb3\xa3");
  EXPECT_EQ(response.Field(3), "H\xfe\xc9\xd4\xc1\xd4\xc5\xcc\xd8 \xb3\xa3");
  EXPECT_EQ(response.Field(6), "\xf4\xc5\xcd\xc1 \xb3\xa3");
  const std::string encoded = "\xf0\xd2\xc9\xd7\xc5\xd4, \xb3\xd6\xc9\xcb \xa3\xd6\xc9\xcb!";
  EXPECT_EQ(response.body, encoded + "\r--- FFIDO\r * Origin: FFIDO (2:5015/1.1)\r");
  EXPECT_TRUE(response.HasField(2000, "CHRS: KOI8-R 2"));
  EXPECT_FALSE(response.HasField(2000, "CHRS: UTF-8 4"));
  const auto parent_after = test::ReadJamWireRecord(temp.path() / "file", 0);
  EXPECT_EQ(parent_after.header, parent_before.header);
  EXPECT_EQ(parent_after.body, parent_before.body);
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto body = test::ReadFile(temp.path() / "file.jdt");
  const auto index = test::ReadFile(temp.path() / "file.jdx");
  wire::CreateMessageResponse repeated;
  grpc::ClientContext retry;
  Auth(retry, a);
  ASSERT_TRUE(client->CreateMessage(&retry, request, &repeated).ok());
  EXPECT_EQ(repeated.message().message_id(), created.message().message_id());
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), body);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
}

TEST_F(Koi8GrpcTest, Koi8UnrepresentableBodySubjectAndNamesRejectWithoutJamOrIntent) {
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto body = test::ReadFile(temp.path() / "file.jdt");
  const auto index = test::ReadFile(temp.path() / "file.jdx");
  for (const std::string field : {"body", "subject", "recipient", "sender"}) {
    SCOPED_TRACE(field);
    ASSERT_TRUE(metadata->SaveProfile(
        "A", domain::Profile{field == "sender" ? "НАвтор 🙂" : "Автор Ёё", "2:5015/1.1", "", "2026-01-01T00:00:00Z"}));
    auto request = Request("koi8-bad-" + field);
    if (field == "body")
      request.set_body("НТекст 🙂");
    if (field == "subject")
      request.set_subject("НТема 漢");
    if (field == "recipient")
      request.set_to_name("НПолучатель 🙂");
    for (int attempt = 0; attempt < 2; ++attempt) {
      grpc::ClientContext context;
      Auth(context, a);
      wire::CreateMessageResponse response;
      EXPECT_EQ(client->CreateMessage(&context, request, &response).error_code(), grpc::StatusCode::INVALID_ARGUMENT);
      EXPECT_EQ(response.status(), wire::SAVE_STATUS_UNSPECIFIED);
      EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
      EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), body);
      EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
      auto operation = metadata->FindOperation("A", request.operation_id());
      ASSERT_TRUE(operation);
      EXPECT_FALSE(operation->has_value());
    }
  }
}

TEST_F(Koi8GrpcTest, UueRoundTripKeepsPayloadAndHash) {
  const std::string hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
  wire::UploadUueChunkRequest upload;
  upload.set_operation_id("koi8-uue");
  upload.set_filename("a.bin");
  upload.set_file_size(3);
  upload.set_sha256(hash);
  upload.set_data("abc");
  wire::UueUploadStatus uploaded;
  grpc::ClientContext upload_context;
  Auth(upload_context, a);
  ASSERT_TRUE(client->UploadUueChunk(&upload_context, upload, &uploaded).ok());
  ASSERT_TRUE(uploaded.complete());
  wire::CommitUueRequest commit;
  *commit.mutable_message() = Request("koi8-uue");
  commit.mutable_message()->set_subject("Тема Ёё");
  wire::UueSendStatus sent;
  grpc::ClientContext commit_context;
  Auth(commit_context, a);
  ASSERT_TRUE(client->CommitUue(&commit_context, commit, &sent).ok());
  ASSERT_EQ(sent.saved_parts(), 1);
  EXPECT_EQ(sent.sha256(), hash);
  const auto raw = test::ReadJamWireRecord(temp.path() / "file", 0);
  EXPECT_TRUE(raw.HasField(2000, "CHRS: KOI8-R 2"));
  EXPECT_TRUE(raw.Field(6).starts_with("\xf4\xc5\xcd\xc1 \xb3\xa3"));
  wire::SearchUuePartsRequest search;
  search.set_conference_id("RU.TEST");
  search.set_limit(100);
  wire::SearchUuePartsResponse parts;
  grpc::ClientContext search_context;
  Auth(search_context, a);
  ASSERT_TRUE(client->SearchUueParts(&search_context, search, &parts).ok());
  ASSERT_EQ(parts.parts_size(), 1);
  wire::AssembleUueRequest assemble;
  *assemble.add_sources() = parts.parts(0).source();
  wire::UueAttachment file;
  grpc::ClientContext assemble_context;
  Auth(assemble_context, a);
  ASSERT_TRUE(client->AssembleUue(&assemble_context, assemble, &file).ok());
  ASSERT_EQ(file.state(), wire::UUE_STATE_READY);
  EXPECT_TRUE(file.checksum_verified());
  EXPECT_EQ(file.sha256(), hash);
  wire::GetUueChunkRequest get;
  get.set_attachment_id(file.id());
  get.set_max_bytes(65536);
  wire::UueChunk bytes;
  grpc::ClientContext get_context;
  Auth(get_context, a);
  ASSERT_TRUE(client->GetUueChunk(&get_context, get, &bytes).ok());
  EXPECT_EQ(bytes.data(), "abc");
}

namespace {
class ForcedKoi8GrpcTest : public GrpcTest {
protected:
  std::map<std::string, std::string> EncodingOverrides() const override {
    return {{"file", "KOI8-R"}};
  }
};
class ForcedUtf8GrpcTest : public GrpcTest {
protected:
  std::string Encoding() const override {
    return "KOI8-R";
  }
  std::map<std::string, std::string> EncodingOverrides() const override {
    return {{"file", "UTF-8"}};
  }
};
}  // namespace
TEST_F(ForcedKoi8GrpcTest, RpcReadsStaleChrsAndPublishesInAreaEncoding) {
  auto request = Request("area-override");
  request.set_subject("Тема Ёё");
  request.set_body("Привет Ёё");
  wire::CreateMessageResponse created;
  grpc::ClientContext create;
  Auth(create, a);
  ASSERT_TRUE(client->CreateMessage(&create, request, &created).ok());
  auto raw = test::ReadJamWireRecord(temp.path() / "file", 0);
  EXPECT_TRUE(raw.HasField(2000, "CHRS: KOI8-R 2"));
  EXPECT_EQ(raw.Field(6), "\xf4\xc5\xcd\xc1 \xb3\xa3");
  auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto at = header.find("CHRS: KOI8-R 2");
  ASSERT_NE(at, std::string::npos);
  header.replace(at, 14, "CHRS: CP866 2 ");
  std::ofstream(temp.path() / "file.jhr", std::ios::binary | std::ios::trunc) << header;
  const auto body = test::ReadFile(temp.path() / "file.jdt");
  const auto index = test::ReadFile(temp.path() / "file.jdx");
  wire::Message decoded;
  grpc::ClientContext read;
  Auth(read, a);
  ASSERT_TRUE(client->GetMessage(&read, created.message(), &decoded).ok());
  EXPECT_EQ(decoded.subject(), request.subject());
  EXPECT_EQ(decoded.from_name(), "Алексей");
  EXPECT_TRUE(decoded.body().starts_with("Привет Ёё"));
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), body);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
}
TEST_F(ForcedUtf8GrpcTest, RpcAreaUtf8OverridesGlobalKoi8ForNewMessages) {
  auto request = Request("utf8-override");
  request.set_body("Привет 😀");
  wire::CreateMessageResponse created;
  grpc::ClientContext create;
  Auth(create, a);
  ASSERT_TRUE(client->CreateMessage(&create, request, &created).ok());
  auto raw = test::ReadJamWireRecord(temp.path() / "file", 0);
  EXPECT_TRUE(raw.HasField(2000, "CHRS: UTF-8 4"));
  EXPECT_TRUE(raw.body.starts_with("Привет 😀"));
  wire::Message decoded;
  grpc::ClientContext read;
  Auth(read, a);
  ASSERT_TRUE(client->GetMessage(&read, created.message(), &decoded).ok());
  EXPECT_TRUE(decoded.body().starts_with("Привет 😀"));
}

namespace {
class OwnerEchoGrpcTest : public GrpcTest {
protected:
  std::string owner;
  std::shared_ptr<const service::EchoAccess> AccessPolicy() const override {
    service::HptConfiguration config;
    config.credentials.emplace("2:5015/1", "fixture-owner-password");
    config.echoes = {{"RU.TEST", temp.path() / "file", {{"2:5015/1.1", {true, false}}}}};
    return service::EchoAccess::Build(config, *catalog, {"2:5015/1"}).value();
  }
  void SetUp() override {
    GrpcTest::SetUp();
    if (::testing::Test::HasFatalFailure())
      return;
    service::AuthService auth(metadata);
    const auto expiry =
        std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count() +
        3600;
    auto issued = auth.Provision("owner", domain::Profile{"Owner", "2:5015/1", "", ""}, expiry);
    ASSERT_TRUE(issued);
    owner = *issued;
  }
};
}  // namespace
TEST_F(OwnerEchoGrpcTest, OwnerWithoutHptSubscriptionCanReadPostAndReplyWhilePointsStayRestricted) {
  wire::ListConferencesRequest list;
  list.mutable_page()->set_limit(20);
  list.set_sort(wire::CONFERENCE_SORT_NAME);
  wire::ListConferencesResponse result;
  grpc::ClientContext owner_list;
  Auth(owner_list, owner);
  ASSERT_TRUE(client->ListConferences(&owner_list, list, &result).ok());
  ASSERT_EQ(result.conferences_size(), 1);
  EXPECT_TRUE(result.conferences(0).can_read());
  EXPECT_TRUE(result.conferences(0).can_post());
  auto request = Request("owner-unsubscribed");
  wire::CreateMessageResponse created;
  grpc::ClientContext write;
  Auth(write, owner);
  ASSERT_TRUE(client->CreateMessage(&write, request, &created).ok());
  wire::Message decoded;
  grpc::ClientContext read;
  Auth(read, owner);
  ASSERT_TRUE(client->GetMessage(&read, created.message(), &decoded).ok());
  EXPECT_EQ(decoded.from_address(), "2:5015/1");
  request.set_operation_id("owner-reply");
  request.set_in_reply_to(created.message().message_id());
  grpc::ClientContext reply;
  Auth(reply, owner);
  wire::CreateMessageResponse replied;
  ASSERT_TRUE(client->CreateMessage(&reply, request, &replied).ok());
  for (const auto& point : {a, b}) {
    grpc::ClientContext write_point;
    Auth(write_point, point);
    wire::CreateMessageResponse denied;
    EXPECT_EQ(client->CreateMessage(&write_point, Request("point-denied"), &denied).error_code(),
              grpc::StatusCode::PERMISSION_DENIED);
  }
  grpc::ClientContext readonly_point;
  Auth(readonly_point, a);
  ASSERT_TRUE(client->GetMessage(&readonly_point, created.message(), &decoded).ok());
  grpc::ClientContext unsubscribed;
  Auth(unsubscribed, b);
  EXPECT_EQ(client->GetMessage(&unsubscribed, created.message(), &decoded).error_code(),
            grpc::StatusCode::PERMISSION_DENIED);
  grpc::ClientContext point_list;
  Auth(point_list, b);
  ASSERT_TRUE(client->ListConferences(&point_list, list, &result).ok());
  EXPECT_EQ(result.conferences_size(), 0);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx").size(), 16);
}

namespace {
class CrosspostGrpcTest : public GrpcTest {
  int AreaCount() const override {
    return 3;
  }
};
}  // namespace
TEST_F(CrosspostGrpcTest, GroupRpcMapsAllCopiesAndRetriesAcrossServiceRestart) {
  wire::CreateCrosspostRequest request;
  *request.mutable_message() = Request("crosspost-rpc");
  request.add_additional_conference_ids("RU.EXTRA2");
  request.add_additional_conference_ids("RU.EXTRA1");
  wire::CreateCrosspostResponse first;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->CreateCrosspost(&context, request, &first).ok());
    ASSERT_TRUE(first.complete());
    ASSERT_EQ(first.total(), 3);
    ASSERT_EQ(first.saved_size(), 3);
    EXPECT_NE(first.saved(0).ftn_message_id(), first.saved(1).ftn_message_id());
  }
  server->Shutdown();
  server->Wait();
  client.reset();
  server.reset();
  service.reset();
  service = std::make_unique<service::GrpcService>(catalog, metadata, AccessPolicy(), Encoding());
  grpc::SslServerCredentialsOptions tls;
  tls.pem_key_cert_pairs.push_back(
      {test::ReadFile(temp.path() / "key.pem"), test::ReadFile(temp.path() / "certificate.pem")});
  grpc::ServerBuilder builder;
  builder.AddListeningPort(address, grpc::SslServerCredentials(tls));
  builder.RegisterService(service.get());
  server = builder.BuildAndStart();
  ASSERT_TRUE(server);
  grpc::SslCredentialsOptions roots;
  roots.pem_root_certs = test::ReadFile(temp.path() / "certificate.pem");
  client = wire::Ffido::NewStub(grpc::CreateChannel(address, grpc::SslCredentials(roots)));
  wire::CreateCrosspostResponse repeated;
  grpc::ClientContext context;
  Auth(context, a);
  ASSERT_TRUE(client->CreateCrosspost(&context, request, &repeated).ok());
  EXPECT_EQ(first.SerializeAsString(), repeated.SerializeAsString());
  for (const auto& saved : repeated.saved()) {
    wire::Message detail;
    grpc::ClientContext read;
    Auth(read, a);
    ASSERT_TRUE(client->GetMessage(&read, saved.message(), &detail).ok());
    EXPECT_TRUE(detail.body().starts_with(
        "* Originally in RU.TEST\n* Crossposted in RU.EXTRA1\n* Crossposted in RU.EXTRA2\n\n"));
    wire::GetConferenceRequest get;
    get.set_conference_id(saved.message().conference_id());
    wire::Conference count;
    grpc::ClientContext counter;
    Auth(counter, a);
    ASSERT_TRUE(client->GetConference(&counter, get, &count).ok());
    EXPECT_EQ(count.total_count(), 1);
  }
}
TEST_F(CrosspostGrpcTest, GroupRpcRequiresAuthenticationAndRejectsInvalidGroupBeforeWrite) {
  wire::CreateCrosspostRequest request;
  *request.mutable_message() = Request();
  request.add_additional_conference_ids("RU.EXTRA1");
  wire::CreateCrosspostResponse response;
  grpc::ClientContext missing;
  EXPECT_EQ(client->CreateCrosspost(&missing, request, &response).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  request.add_additional_conference_ids("RU.EXTRA1");
  grpc::ClientContext invalid;
  Auth(invalid, a);
  EXPECT_EQ(client->CreateCrosspost(&invalid, request, &response).error_code(), grpc::StatusCode::INVALID_ARGUMENT);
}

namespace {
class DeniedCrosspostGrpcTest : public CrosspostGrpcTest {
  std::shared_ptr<const service::EchoAccess> AccessPolicy() const override {
    service::HptConfiguration config;
    for (const auto& [id, area] : catalog->areas())
      config.echoes.push_back({id, temp.path() / area.relative_filename, {{"2:5015/1.1", {true, id == "RU.TEST"}}}});
    return service::EchoAccess::Build(config, *catalog).value();
  }
};
}  // namespace
TEST_F(DeniedCrosspostGrpcTest, ForbiddenGroupReturnsNoPrivateCopyReferences) {
  wire::CreateCrosspostRequest request;
  *request.mutable_message() = Request();
  request.add_additional_conference_ids("RU.EXTRA1");
  wire::CreateCrosspostResponse response;
  grpc::ClientContext context;
  Auth(context, a);
  EXPECT_EQ(client->CreateCrosspost(&context, request, &response).error_code(), grpc::StatusCode::PERMISSION_DENIED);
  EXPECT_EQ(response.saved_size(), 0);
}

TEST_F(GrpcTest, MsgidOriginAddressIsNarrowCanonicalAndHonorsExplicitAddress) {
  struct Case {
    std::string msgid, origin, expected;
  };
  const std::vector<Case> cases{
      {"2:5001/100@fidonet 6ae67e72", "", "2:5001/100"},
      {"2:5001/100.7@other-net.example serial", "", "2:5001/100.7"},
      {"2:5001/100.0@FiDoNeT serial", "", "2:5001/100"},
      {"2:5001/100.7 serial", "", "2:5001/100.7"},
      {"2:5001/100.0 serial", "", "2:5001/100"},
      {"2:5001/100@fidonet serial", "2:1/2", "2:1/2"},
      {"2:5001/100@ serial", "", ""},
      {"2:5001/100@@fidonet serial", "", ""},
      {"2:5001/100@fido/net serial", "", ""},
      {"2:5001/100@-fidonet serial", "", ""},
      {"2:5001/100@fidonet. serial", "", ""},
      {"2:5001/100@" + std::string(256, 'a') + " serial", "", ""},
      {"2:5001/65536@fidonet serial", "", ""},
      {"2:5001/100@fidonet", "", ""},
      {"2:5001/100@fidonet \t", "", ""},
  };
  for (size_t i = 0; i < cases.size(); ++i) {
    SCOPED_TRACE(cases[i].msgid);
    wire::MessageReference ref;
    ref.set_conference_id("RU.TEST");
    {
      auto access = storage::JamAccess::Open(*catalog, "RU.TEST", true,
                                             std::chrono::steady_clock::now() + std::chrono::seconds(3));
      ASSERT_TRUE(access);
      msgapi::JamMessage parent;
      parent.SetSenderName("Author");
      parent.SetSubject("Subject");
      parent.SetText("Body");
      parent.SetMsgId(cases[i].msgid);
      if (!cases[i].origin.empty())
        parent.SetOriginAddress(cases[i].origin);
      ASSERT_EQ((*access)->messages().AddMessage(parent), msgapi::JamError::kSuccess);
      ref.set_message_id((*access)->generation() + "#" + std::to_string(42 + i));
    }
    wire::Message message;
    grpc::ClientContext read;
    Auth(read, a);
    ASSERT_TRUE(client->GetMessage(&read, ref, &message).ok());
    EXPECT_EQ(message.from_address(), cases[i].expected);
    if (cases[i].expected.empty()) {
      auto request = Request("broken-parent-" + std::to_string(i));
      request.set_in_reply_to(ref.message_id());
      wire::CreateMessageResponse response;
      grpc::ClientContext reply;
      Auth(reply, a);
      EXPECT_EQ(client->CreateMessage(&reply, request, &response).error_code(), grpc::StatusCode::INVALID_ARGUMENT);
      EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx").size(), (i + 1) * 8);
    }
  }
  EXPECT_FALSE(service::ValidFtnAddress("2:5001/100@fidonet"));
}

TEST_F(GrpcTest, DomainMsgidReplyPreservesOriginalPayloadAndFullReplyId) {
  const std::string msgid = "2:5001/100@fidonet 6ae67e72";
  wire::MessageReference ref;
  ref.set_conference_id("RU.TEST");
  {
    auto access =
        storage::JamAccess::Open(*catalog, "RU.TEST", true, std::chrono::steady_clock::now() + std::chrono::seconds(3));
    ASSERT_TRUE(access);
    msgapi::JamMessage parent;
    parent.SetSenderName("Dmitry Protasoff");
    parent.SetReceiverName("Nil A");
    parent.SetSubject("Subject");
    parent.SetText("Original body\r");
    parent.SetMsgId(msgid);
    ASSERT_EQ((*access)->messages().AddMessage(parent), msgapi::JamError::kSuccess);
    ref.set_message_id((*access)->generation() + "#42");
  }
  const auto header_before = test::ReadFile(temp.path() / "file.jhr");
  const auto text_before = test::ReadFile(temp.path() / "file.jdt");
  const auto index_before = test::ReadFile(temp.path() / "file.jdx");
  wire::Message decoded;
  grpc::ClientContext read;
  Auth(read, a);
  ASSERT_TRUE(client->GetMessage(&read, ref, &decoded).ok());
  EXPECT_EQ(decoded.from_address(), "2:5001/100");
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header_before);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), text_before);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index_before);
  const auto original = test::ReadJamWireRecord(temp.path() / "file", 0);
  auto request = Request("domain-reply");
  request.set_in_reply_to(ref.message_id());
  request.set_to_name("");
  request.set_to_address("");
  wire::CreateMessageResponse created;
  grpc::ClientContext reply;
  Auth(reply, a);
  ASSERT_TRUE(client->CreateMessage(&reply, request, &created).ok());
  const auto result = test::ReadJamWireRecord(temp.path() / "file", 1);
  EXPECT_EQ(result.Field(5), msgid);
  EXPECT_EQ(result.Field(3), "Dmitry Protasoff");
  EXPECT_EQ(result.Field(1), "2:5001/100");
  const auto after = test::ReadJamWireRecord(temp.path() / "file", 0);
  EXPECT_EQ(after.body, original.body);
  for (auto field : {2, 3, 4, 6})
    EXPECT_EQ(after.Field(field), original.Field(field));

  request.set_operation_id("invalid-parent-address");
  request.set_to_address("2:5001/100@fidonet");
  grpc::ClientContext invalid;
  Auth(invalid, a);
  EXPECT_EQ(client->CreateMessage(&invalid, request, &created).error_code(), grpc::StatusCode::INVALID_ARGUMENT);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx").size(), 16u);
}

TEST_F(GrpcTest, MarkUnreadRpcPreservesJamAndOtherUserAndRejectsStaleOrDeletedReferences) {
  auto request = Request("unread");
  wire::CreateMessageResponse created;
  grpc::ClientContext create;
  Auth(create, a);
  ASSERT_TRUE(client->CreateMessage(&create, request, &created).ok());
  wire::Message body;
  for (const auto& token : {a, b}) {
    grpc::ClientContext read;
    Auth(read, token);
    ASSERT_TRUE(client->GetMessage(&read, created.message(), &body).ok());
  }
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto text = test::ReadFile(temp.path() / "file.jdt");
  const auto index = test::ReadFile(temp.path() / "file.jdx");
  const auto position = *metadata->LastOpened("A", "RU.TEST");
  google::protobuf::Empty empty;
  for (int i = 0; i < 2; ++i) {
    grpc::ClientContext unread;
    Auth(unread, a);
    ASSERT_TRUE(client->MarkUnread(&unread, created.message(), &empty).ok());
  }
  wire::ListMessagesRequest list;
  list.set_conference_id("RU.TEST");
  list.mutable_page()->set_limit(20);
  list.set_sort(wire::MESSAGE_SORT_DATE_DESCENDING);
  wire::ListMessagesResponse response;
  grpc::ClientContext mine;
  Auth(mine, a);
  ASSERT_TRUE(client->ListMessages(&mine, list, &response).ok());
  ASSERT_EQ(response.messages_size(), 1);
  EXPECT_FALSE(response.messages(0).is_read());
  grpc::ClientContext other;
  Auth(other, b);
  ASSERT_TRUE(client->ListMessages(&other, list, &response).ok());
  EXPECT_TRUE(response.messages(0).is_read());
  wire::GetConferenceRequest area;
  area.set_conference_id("RU.TEST");
  wire::Conference statistics;
  grpc::ClientContext counts;
  Auth(counts, a);
  ASSERT_TRUE(client->GetConference(&counts, area, &statistics).ok());
  EXPECT_EQ(statistics.unread_count(), 1);
  EXPECT_EQ(metadata->LastOpened("A", "RU.TEST")->revision, position.revision);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), text);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
  auto invalid = created.message();
  invalid.set_message_id("stale#42");
  grpc::ClientContext stale;
  Auth(stale, a);
  EXPECT_EQ(client->MarkUnread(&stale, invalid, &empty).error_code(), grpc::StatusCode::NOT_FOUND);
  {
    std::fstream output(temp.path() / "file.jdx", std::ios::binary | std::ios::in | std::ios::out);
    output.seekp(4);
    const char deleted[4] = {'\xff', '\xff', '\xff', '\xff'};
    output.write(deleted, sizeof(deleted));
  }
  grpc::ClientContext deleted;
  Auth(deleted, a);
  EXPECT_EQ(client->MarkUnread(&deleted, created.message(), &empty).error_code(), grpc::StatusCode::NOT_FOUND);
}

TEST_F(GrpcTest, FindMessageWalksBothOrdersWithoutReadingSkippedMessages) {
  std::vector<std::string> ids;
  for (int i = 0; i < 24; ++i) {
    auto request = Request("search-" + std::to_string(i));
    request.set_subject(i == 0 || i == 23 ? "Совпадение" : "Другое");
    request.set_body("Hовый Привет");
    wire::CreateMessageResponse created;
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
    ids.push_back(created.message().message_id());
  }
  wire::FindMessageRequest request;
  request.set_conference_id("RU.TEST");
  request.set_query("  СОВПАДЕНИЕ  ");
  request.set_scope(wire::MESSAGE_SEARCH_HEADER_ONLY);
  request.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  request.set_start_message_id(ids.front());
  request.set_include_start(true);
  const auto find = [&]() {
    wire::FindMessageResponse response;
    grpc::ClientContext context;
    Auth(context, b);
    EXPECT_TRUE(client->FindMessage(&context, request, &response).ok());
    return response;
  };
  auto first = find();
  ASSERT_TRUE(first.has_message());
  EXPECT_EQ(first.message().id(), ids.front());
  EXPECT_TRUE(first.message().is_read());
  ASSERT_EQ(first.matches_size(), 1);
  EXPECT_EQ(first.matches(0).field(), wire::MESSAGE_SEARCH_SUBJECT);
  EXPECT_EQ(first.matches(0).length_utf16(), 10);
  request.set_include_start(false);
  auto last = find();
  ASSERT_TRUE(last.has_message());
  EXPECT_EQ(last.message().id(), ids.back());
  request.set_start_message_id(last.message().id());
  EXPECT_FALSE(find().has_message());
  request.set_sort(wire::MESSAGE_SORT_DATE_DESCENDING);
  auto backward = find();
  ASSERT_TRUE(backward.has_message());
  EXPECT_EQ(backward.message().id(), ids.front());
  request.clear_start_message_id();
  request.set_query("НОВЫЙ");
  EXPECT_FALSE(find().has_message());  // body excluded
  request.set_scope(wire::MESSAGE_SEARCH_HEADER_AND_BODY);
  auto cp866 = find();
  ASSERT_TRUE(cp866.has_message());
  EXPECT_EQ(cp866.matches(0).field(), wire::MESSAGE_SEARCH_BODY);
  EXPECT_EQ(cp866.matches(0).start_utf16(), 0);
  EXPECT_EQ(cp866.matches(0).length_utf16(), 5);
  wire::ListMessagesRequest list;
  list.set_conference_id("RU.TEST");
  list.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  list.mutable_page()->set_limit(100);
  for (const auto& token : {a, b}) {
    grpc::ClientContext context;
    Auth(context, token);
    wire::ListMessagesResponse rows;
    ASSERT_TRUE(client->ListMessages(&context, list, &rows).ok());
    ASSERT_EQ(rows.messages_size(), 24);
    for (int i = 0; i < rows.messages_size(); ++i)
      EXPECT_EQ(rows.messages(i).is_read(), token == b && (i == 0 || i == 23));
  }
}
TEST_F(GrpcTest, FindMessageChecksParametersAccessAndAnchors) {
  wire::FindMessageRequest request;
  request.set_conference_id("RU.TEST");
  request.set_scope(wire::MESSAGE_SEARCH_HEADER_AND_BODY);
  request.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  request.set_query(std::string(256, 'a'));
  auto status = [&]() {
    grpc::ClientContext context;
    Auth(context, a);
    wire::FindMessageResponse response;
    return client->FindMessage(&context, request, &response);
  };
  EXPECT_TRUE(status().ok());
  request.set_query(std::string(257, 'a'));
  EXPECT_EQ(status().error_code(), grpc::StatusCode::INVALID_ARGUMENT);
  request.set_query("   ");
  EXPECT_EQ(status().error_code(), grpc::StatusCode::INVALID_ARGUMENT);
  request.set_query("x");
  request.GetReflection()->SetEnumValue(&request, request.GetDescriptor()->FindFieldByName("scope"), 99);
  EXPECT_EQ(status().error_code(), grpc::StatusCode::INVALID_ARGUMENT);
  request.set_scope(wire::MESSAGE_SEARCH_HEADER_ONLY);
  request.set_sort(wire::MESSAGE_SORT_UNSPECIFIED);
  EXPECT_EQ(status().error_code(), grpc::StatusCode::INVALID_ARGUMENT);
  request.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  request.set_start_message_id("old-generation#42");
  EXPECT_EQ(status().error_code(), grpc::StatusCode::NOT_FOUND);
  request.clear_start_message_id();
  request.set_conference_id("PRIVATE.UNKNOWN");
  EXPECT_FALSE(status().ok());
}

TEST_F(ForcedUtf8GrpcTest, FindMessageDoesNotApplyCp866PairsToUtf8Override) {
  auto create = Request("search-utf8");
  create.set_subject("😀 Привет");
  create.set_body("Hовый рУ");
  wire::CreateMessageResponse saved;
  grpc::ClientContext posting;
  Auth(posting, a);
  ASSERT_TRUE(client->CreateMessage(&posting, create, &saved).ok());
  wire::FindMessageRequest request;
  request.set_conference_id("RU.TEST");
  request.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  request.set_scope(wire::MESSAGE_SEARCH_HEADER_AND_BODY);
  request.set_query("Новый");
  wire::FindMessageResponse response;
  grpc::ClientContext searching;
  Auth(searching, b);
  ASSERT_TRUE(client->FindMessage(&searching, request, &response).ok());
  EXPECT_FALSE(response.has_message());
  request.set_query("ПРИВЕТ");
  grpc::ClientContext second;
  Auth(second, b);
  ASSERT_TRUE(client->FindMessage(&second, request, &response).ok());
  ASSERT_TRUE(response.has_message());
  ASSERT_EQ(response.matches_size(), 1);
  EXPECT_EQ(response.matches(0).start_utf16(), 3);
  EXPECT_EQ(response.matches(0).length_utf16(), 6);
}
TEST_F(ForcedKoi8GrpcTest, FindMessageHonorsOverrideDespiteStaleCp866Chrs) {
  auto create = Request("search-koi8");
  create.set_subject("Привет");
  create.set_body("Hовый");
  wire::CreateMessageResponse saved;
  grpc::ClientContext posting;
  Auth(posting, a);
  ASSERT_TRUE(client->CreateMessage(&posting, create, &saved).ok());
  auto header = test::ReadFile(temp.path() / "file.jhr");
  const auto at = header.find("CHRS: KOI8-R 2");
  ASSERT_NE(at, std::string::npos);
  header.replace(at, 14, "CHRS: CP866 2 ");
  std::ofstream(temp.path() / "file.jhr", std::ios::binary | std::ios::trunc) << header;
  wire::FindMessageRequest request;
  request.set_conference_id("RU.TEST");
  request.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  request.set_scope(wire::MESSAGE_SEARCH_HEADER_AND_BODY);
  request.set_query("Новый");
  wire::FindMessageResponse response;
  grpc::ClientContext first;
  Auth(first, b);
  ASSERT_TRUE(client->FindMessage(&first, request, &response).ok());
  EXPECT_FALSE(response.has_message());
  request.set_query("ПРИВЕТ");
  grpc::ClientContext second;
  Auth(second, b);
  ASSERT_TRUE(client->FindMessage(&second, request, &response).ok());
  ASSERT_TRUE(response.has_message());
  EXPECT_EQ(response.message().subject(), "Привет");
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
}

TEST_F(GrpcTest, TechnicalDataKeepsUnknownConflictingAndUndecodableMetadata) {
  std::vector<std::string> references;
  {
    auto lease =
        storage::JamAccess::Open(*catalog, "RU.TEST", true, std::chrono::steady_clock::now() + std::chrono::seconds(2));
    ASSERT_TRUE(lease);
    for (int i = 0; i < 4; ++i) {
      msgapi::JamMessage raw;
      raw.SetText("x");
      raw.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "CHRS: CP866 2");
      if (i == 2)
        raw.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, "XHRS: UTF-8 4");
      ASSERT_EQ((*lease)->messages().AddMessage(raw), msgapi::JamError::kSuccess);
      references.push_back((*lease)->generation() + "#" + std::to_string(42 + i));
    }
  }
  // Mutate only this fixture on disk: emulate legacy/foreign malformed encodings.
  auto bytes = test::ReadFile(temp.path() / "file.jhr");
  size_t position = 0;
  const std::vector<std::string> replacements = {"CHRS: XXXXX 2", "CHRS: UTF-8 4", "CHRS: CP866 2", "XHRS: CP866 2"};
  for (const auto& replacement : replacements) {
    position = bytes.find("CHRS: CP866 2", position);
    ASSERT_NE(position, std::string::npos);
    bytes.replace(position, 13, replacement);
    position += 13;
  }
  position = bytes.find("XHRS: UTF-8 4");
  ASSERT_NE(position, std::string::npos);
  bytes[position] = 'C';
  {
    std::ofstream output(temp.path() / "file.jhr", std::ios::binary);
    output.write(bytes.data(), bytes.size());
    std::ofstream body(temp.path() / "file.jdt", std::ios::binary);
    body.write("x\xffxx", 4);
  }
  for (int i = 0; i < 4; ++i) {
    wire::MessageReference reference;
    reference.set_conference_id("RU.TEST");
    reference.set_message_id(references[i]);
    grpc::ClientContext context;
    Auth(context, a);
    wire::MessageTechnicalData result;
    ASSERT_TRUE(client->GetMessageTechnicalData(&context, reference, &result).ok());
    EXPECT_GT(result.subfields_size(), 0);
    EXPECT_EQ(result.encoding_status(),
              i == 0 || i == 2 ? wire::TECHNICAL_ENCODING_STATUS_UNDETERMINED : wire::TECHNICAL_ENCODING_STATUS_KNOWN);
    if (i == 1)
      EXPECT_EQ(result.effective_encoding(), "UTF-8");
    if (i == 3)
      EXPECT_EQ(result.effective_encoding(), "cp866");
  }
}

TEST_F(ForcedKoi8GrpcTest, TechnicalDataOverrideRetainsDeclaredChrs) {
  wire::MessageReference reference;
  {
    auto lease =
        storage::JamAccess::Open(*catalog, "RU.TEST", true, std::chrono::steady_clock::now() + std::chrono::seconds(2));
    ASSERT_TRUE(lease);
    msgapi::JamMessage raw;
    raw.SetText("body");
    ASSERT_EQ((*lease)->messages().AddMessage(raw), msgapi::JamError::kSuccess);
    reference.set_conference_id("RU.TEST");
    reference.set_message_id((*lease)->generation() + "#42");
  }
  auto bytes = test::ReadFile(temp.path() / "file.jhr");
  const auto chrs = bytes.find("CHRS: KOI8-R 2");
  ASSERT_NE(chrs, std::string::npos);
  bytes.replace(chrs, 14, "CHRS: CP866 2 ");
  {
    std::ofstream output(temp.path() / "file.jhr", std::ios::binary);
    output.write(bytes.data(), bytes.size());
  }
  grpc::ClientContext context;
  Auth(context, a);
  wire::MessageTechnicalData result;
  ASSERT_TRUE(client->GetMessageTechnicalData(&context, reference, &result).ok());
  EXPECT_EQ(result.effective_encoding(), "KOI8-R");
  EXPECT_TRUE(std::ranges::any_of(result.subfields(), [](const auto& f) { return f.value() == "CHRS: CP866 2 "; }));
}

TEST_F(GrpcTest, PersonalFiltersCollapseRevealSearchAndLegacyIsolation) {
  auto request = Request("filter-source");
  wire::CreateMessageResponse created;
  grpc::ClientContext create;
  Auth(create, a);
  ASSERT_TRUE(client->CreateMessage(&create, request, &created).ok());
  const auto reference = created.message();
  auto child = Request("filter-child");
  child.set_subject("Normal");
  child.set_in_reply_to(reference.message_id());
  grpc::ClientContext reply;
  Auth(reply, a);
  wire::CreateMessageResponse replied;
  ASSERT_TRUE(client->CreateMessage(&reply, child, &replied).ok());

  wire::ReplacePersonalMessageFiltersRequest settings;
  settings.set_operation_id("filter-save");
  auto* rule = settings.add_rules();
  rule->set_rule_id("00000000-0000-4000-8000-000000000001");
  rule->set_enabled(true);
  rule->set_scope(wire::PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS);
  rule->set_subject_contains("РУССКАЯ");
  wire::ReplacePersonalMessageFiltersResponse saved;
  grpc::ClientContext save;
  Auth(save, b);
  ASSERT_TRUE(client->ReplacePersonalMessageFilters(&save, settings, &saved).ok());
  EXPECT_EQ(saved.revision(), 1);
  grpc::ClientContext retry;
  Auth(retry, b);
  ASSERT_TRUE(client->ReplacePersonalMessageFilters(&retry, settings, &saved).ok());
  settings.set_operation_id("stale");
  grpc::ClientContext stale;
  Auth(stale, b);
  EXPECT_EQ(client->ReplacePersonalMessageFilters(&stale, settings, &saved).error_code(), grpc::StatusCode::ABORTED);
  const auto header = test::ReadFile(temp.path() / "file.jhr"), body = test::ReadFile(temp.path() / "file.jdt"),
             index = test::ReadFile(temp.path() / "file.jdx");
  wire::GetMessagePresentationRequest open;
  *open.mutable_message() = reference;
  wire::MessagePresentation presentation;
  grpc::ClientContext view;
  Auth(view, b);
  ASSERT_TRUE(client->GetMessagePresentation(&view, open, &presentation).ok());
  ASSERT_TRUE(presentation.has_collapsed());
  EXPECT_FALSE(presentation.collapsed().is_read());
  EXPECT_EQ(presentation.matched_rule_ids_size(), 1);
  EXPECT_EQ(metadata->LastOpened("B", "RU.TEST")->revision, 0);
  EXPECT_TRUE(metadata->GetHistory("B")->empty());
  wire::ListMessagesRequest list;
  list.set_conference_id("RU.TEST");
  list.mutable_page()->set_limit(10);
  list.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  list.set_respect_personal_filters(true);
  wire::ListMessagesResponse listed;
  grpc::ClientContext listing;
  Auth(listing, b);
  ASSERT_TRUE(client->ListMessages(&listing, list, &listed).ok());
  ASSERT_EQ(listed.messages_size(), 2);
  EXPECT_TRUE(listed.messages(0).body_preview().empty());
  EXPECT_EQ(listed.messages(0).personal_collapse().matched_rule_ids_size(), 1);
  wire::GetThreadRequest thread;
  thread.set_conference_id("RU.TEST");
  thread.set_thread_id(reference.message_id());
  thread.mutable_page()->set_limit(10);
  thread.set_respect_personal_filters(true);
  grpc::ClientContext chain;
  Auth(chain, b);
  wire::ListMessagesResponse threaded;
  ASSERT_TRUE(client->GetThread(&chain, thread, &threaded).ok());
  ASSERT_EQ(threaded.messages_size(), 2);
  EXPECT_TRUE(threaded.messages(0).body().empty());
  EXPECT_FALSE(threaded.messages(1).body().empty());
  EXPECT_FALSE(threaded.messages(0).is_read());
  EXPECT_FALSE(threaded.messages(1).is_read());
  wire::FindMessageRequest find;
  find.set_conference_id("RU.TEST");
  find.set_query("мир");
  find.set_scope(wire::MESSAGE_SEARCH_HEADER_AND_BODY);
  find.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  find.set_include_start(true);
  find.set_respect_personal_filters(true);
  wire::FindMessageResponse found;
  grpc::ClientContext search;
  Auth(search, b);
  ASSERT_TRUE(client->FindMessage(&search, find, &found).ok());
  ASSERT_TRUE(found.has_message());
  EXPECT_TRUE(found.message().body().empty());
  EXPECT_EQ(found.matches_size(), 0);
  EXPECT_FALSE(found.message().is_read());
  EXPECT_TRUE(metadata->GetHistory("B")->empty());
  open.set_reveal(true);
  open.set_search_query("мир");
  open.set_search_scope(wire::MESSAGE_SEARCH_HEADER_AND_BODY);
  grpc::ClientContext reveal;
  Auth(reveal, b);
  ASSERT_TRUE(client->GetMessagePresentation(&reveal, open, &presentation).ok());
  ASSERT_TRUE(presentation.has_visible());
  EXPECT_TRUE(presentation.visible().is_read());
  EXPECT_GT(presentation.matches_size(), 0);
  EXPECT_FALSE(presentation.visible().body().empty());
  EXPECT_EQ(metadata->GetHistory("B")->size(), 1);
  grpc::ClientContext other;
  Auth(other, a);
  open.set_reveal(false);
  open.clear_search_query();
  open.clear_search_scope();
  ASSERT_TRUE(client->GetMessagePresentation(&other, open, &presentation).ok());
  EXPECT_TRUE(presentation.has_visible());
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdt"), body);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jdx"), index);
  find.set_respect_personal_filters(false);
  grpc::ClientContext legacy;
  Auth(legacy, b);
  ASSERT_TRUE(client->FindMessage(&legacy, find, &found).ok());
  EXPECT_FALSE(found.message().body().empty());
  EXPECT_GT(found.matches_size(), 0);
}

TEST_F(GrpcTest, PersonalFiltersValidationAndBoundsAreAtomic) {
  wire::ReplacePersonalMessageFiltersRequest request;
  request.set_operation_id("validation");
  auto* rule = request.add_rules();
  rule->set_rule_id("00000000-0000-4000-8000-000000000001");
  rule->set_enabled(true);
  rule->set_scope(wire::PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS);
  auto invalid = [&] {
    grpc::ClientContext context;
    Auth(context, b);
    wire::ReplacePersonalMessageFiltersResponse ignored;
    return client->ReplacePersonalMessageFilters(&context, request, &ignored).error_code();
  };
  EXPECT_EQ(invalid(), grpc::StatusCode::INVALID_ARGUMENT);
  rule->set_author_contains(std::string(257, 'x'));
  EXPECT_EQ(invalid(), grpc::StatusCode::INVALID_ARGUMENT);
  rule->set_author_contains("x");
  rule->set_address_equals("2:1/20*");
  EXPECT_EQ(invalid(), grpc::StatusCode::INVALID_ARGUMENT);
  rule->clear_address_equals();
  // Exercise an unknown enum exactly as it arrives on the protobuf wire.
  auto unknown_scope = rule->SerializeAsString();
  unknown_scope.append("\x18\xe7\x07", 3);  // field 3, varint 999
  ASSERT_TRUE(rule->ParseFromString(unknown_scope));
  EXPECT_EQ(invalid(), grpc::StatusCode::INVALID_ARGUMENT);
  rule->set_scope(wire::PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE);
  rule->set_conference_id("missing");
  EXPECT_EQ(invalid(), grpc::StatusCode::PERMISSION_DENIED);
  rule->set_scope(wire::PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS);
  rule->clear_conference_id();
  const auto copy = *rule;
  *request.add_rules() = copy;
  EXPECT_EQ(invalid(), grpc::StatusCode::INVALID_ARGUMENT);
  request.clear_rules();
  for (int i = 0; i < 201; ++i)
    *request.add_rules() = copy;
  EXPECT_EQ(invalid(), grpc::StatusCode::INVALID_ARGUMENT);
  EXPECT_TRUE(metadata->GetPersonalFilters("B")->rules.empty());
  EXPECT_EQ(metadata->GetPersonalFilters("B")->revision, 0);
}

TEST_F(GrpcTest, PersonalFiltersKeepPaginationAtMaximumRuleCount) {
  std::string generation;
  {
    auto lease =
        storage::JamAccess::Open(*catalog, "RU.TEST", true, std::chrono::steady_clock::now() + std::chrono::seconds(5));
    ASSERT_TRUE(lease);
    generation = (*lease)->generation();
    for (int i = 0; i < 120; ++i) {
      msgapi::JamMessage raw;
      raw.SetSubject(i % 2 == 0 ? "Noise" : "Normal");
      raw.SetText("body preview");
      ASSERT_EQ((*lease)->messages().AddMessage(raw), msgapi::JamError::kSuccess);
    }
  }
  std::vector<domain::PersonalMessageFilter> rules;
  for (int i = 0; i < 200; ++i)
    rules.push_back({"00000000-0000-4000-8000-" + std::to_string(100000000000LL + i), true, 1, "", "", "",
                     i == 199 ? "Noise" : "absent-" + std::to_string(i)});
  ASSERT_TRUE(metadata->ReplacePersonalFilters("B", 0, "max", rules));
  wire::ListMessagesRequest request;
  request.set_conference_id("RU.TEST");
  request.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
  request.mutable_page()->set_offset(20);
  request.mutable_page()->set_limit(20);
  request.set_respect_personal_filters(true);
  const auto start = std::chrono::steady_clock::now();
  grpc::ClientContext context;
  Auth(context, b);
  wire::ListMessagesResponse page;
  ASSERT_TRUE(client->ListMessages(&context, request, &page).ok());
  const auto milliseconds =
      std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
  std::cout << "personal filters: 120 messages / 200 rules / page 20: " << milliseconds << " ms\n";
  EXPECT_EQ(page.total(), 120);
  EXPECT_TRUE(page.has_more());
  EXPECT_EQ(page.actual_offset(), 20);
  ASSERT_EQ(page.messages_size(), 20);
  for (int i = 0; i < 20; ++i) {
    EXPECT_EQ(page.messages(i).id(), generation + "#" + std::to_string(62 + i));
    EXPECT_EQ(page.messages(i).personal_collapse().matched_rule_ids_size(), i % 2 == 0 ? 1 : 0);
    EXPECT_EQ(page.messages(i).body_preview().empty(), i % 2 == 0);
    EXPECT_FALSE(page.messages(i).is_read());
  }
  EXPECT_TRUE(metadata->GetHistory("B")->empty());
  request.set_anchor_message_id(generation + "#142");
  grpc::ClientContext anchor;
  Auth(anchor, b);
  ASSERT_TRUE(client->ListMessages(&anchor, request, &page).ok());
  EXPECT_EQ(page.actual_offset(), 100);
  EXPECT_FALSE(page.has_more());
  wire::MarkConferenceReadRequest bulk;
  bulk.set_conference_id("RU.TEST");
  bulk.set_operation_id("all-including-collapsed");
  wire::MarkConferenceReadResponse marked;
  grpc::ClientContext mark;
  Auth(mark, b);
  ASSERT_TRUE(client->MarkConferenceRead(&mark, bulk, &marked).ok());
  EXPECT_EQ(marked.marked_count(), 120);
}

TEST_F(GrpcTest, PersonalFiltersPresentationRejectsBadEncodingAndExpiredRequestsWithoutRead) {
  auto request = Request("encoding-filter");
  wire::CreateMessageResponse created;
  grpc::ClientContext create;
  Auth(create, a);
  ASSERT_TRUE(client->CreateMessage(&create, request, &created).ok());
  auto bytes = test::ReadFile(temp.path() / "file.jhr");
  const auto at = bytes.find("CHRS: CP866 2");
  ASSERT_NE(at, std::string::npos);
  bytes.replace(at, 13, "CHRS: XXXXX 2");
  {
    std::ofstream output(temp.path() / "file.jhr", std::ios::binary);
    output.write(bytes.data(), bytes.size());
  }
  wire::GetMessagePresentationRequest open;
  *open.mutable_message() = created.message();
  wire::MessagePresentation result;
  grpc::ClientContext view;
  Auth(view, b);
  EXPECT_FALSE(client->GetMessagePresentation(&view, open, &result).ok());
  EXPECT_FALSE(result.has_visible());
  EXPECT_FALSE(result.has_collapsed());
  grpc::ClientContext expired;
  Auth(expired, b);
  expired.set_deadline(std::chrono::system_clock::now() - std::chrono::seconds(1));
  EXPECT_EQ(client->GetMessagePresentation(&expired, open, &result).error_code(), grpc::StatusCode::DEADLINE_EXCEEDED);
  grpc::ClientContext cancelled;
  Auth(cancelled, b);
  cancelled.TryCancel();
  EXPECT_EQ(client->GetMessagePresentation(&cancelled, open, &result).error_code(), grpc::StatusCode::CANCELLED);
  EXPECT_TRUE(metadata->GetHistory("B")->empty());
  EXPECT_EQ(metadata->LastOpened("B", "RU.TEST")->revision, 0);
}

TEST_F(GrpcTest, ArchiveReadAndThreadAreAuthorizedAndLeaveReadingStateUntouched) {
  wire::CreateMessageResponse created;
  {
    grpc::ClientContext context;
    Auth(context, a);
    const auto request = Request();
    ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
  }
  wire::ReadArchiveMessageRequest request;
  *request.mutable_message() = created.message();
  request.set_body_limit(65536);
  wire::ReadArchiveMessageResponse read;
  {
    grpc::ClientContext context;
    EXPECT_EQ(client->ReadArchiveMessage(&context, request, &read).error_code(), grpc::StatusCode::UNAUTHENTICATED);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->ReadArchiveMessage(&context, request, &read).ok());
    EXPECT_FALSE(read.message().is_read());
    EXPECT_FALSE(read.message().body().empty());
    EXPECT_TRUE(read.complete());
  }
  {
    wire::GetArchiveThreadRequest thread;
    *thread.mutable_message() = created.message();
    thread.mutable_page()->set_limit(20);
    wire::ListMessagesResponse result;
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->GetArchiveThread(&context, thread, &result).ok());
    ASSERT_EQ(result.messages_size(), 1);
    EXPECT_TRUE(result.messages(0).body().empty());
    EXPECT_TRUE(result.messages(0).body_preview().empty());
    EXPECT_FALSE(result.messages(0).is_read());
  }
  auto history = metadata->GetHistory("A");
  auto position = metadata->LastOpened("A", "RU.TEST");
  ASSERT_TRUE(history);
  ASSERT_TRUE(position);
  EXPECT_TRUE(history->empty());
  EXPECT_EQ(position->revision, 0u);
  {
    grpc::ClientContext context;
    Auth(context, a);
    context.set_deadline(std::chrono::system_clock::now() - std::chrono::seconds(1));
    EXPECT_EQ(client->ReadArchiveMessage(&context, request, &read).error_code(), grpc::StatusCode::DEADLINE_EXCEEDED);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    context.TryCancel();
    EXPECT_EQ(client->ReadArchiveMessage(&context, request, &read).error_code(), grpc::StatusCode::CANCELLED);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    request.mutable_message()->set_conference_id("mailbox.of.someone.else");
    EXPECT_EQ(client->ReadArchiveMessage(&context, request, &read).error_code(), grpc::StatusCode::PERMISSION_DENIED);
  }
}

TEST_F(GrpcTest, PreviewAndDigestProtectTheFirstPublicationAndPreserveLegacySend) {
  auto request = Request();
  request.set_body("Новый ответ");
  wire::MessagePreview preview;
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->PreviewMessage(&context, request, &preview).ok());
    EXPECT_TRUE(preview.public_message());
    EXPECT_EQ(preview.from_address(), "2:5015/1.1");
    EXPECT_EQ(preview.preview_digest().size(), 64u);
  }
  request.set_expected_preview_digest(preview.preview_digest());
  wire::CreateMessageResponse sent;
  {
    auto changed = request;
    changed.set_subject("Changed");
    grpc::ClientContext context;
    Auth(context, a);
    EXPECT_EQ(client->CreateMessage(&context, changed, &sent).error_code(), grpc::StatusCode::FAILED_PRECONDITION);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    ASSERT_TRUE(client->CreateMessage(&context, request, &sent).ok());
    EXPECT_EQ(sent.status(), wire::SAVE_STATUS_SAVED_LOCALLY);
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    wire::Message read;
    ASSERT_TRUE(client->GetMessage(&context, sent.message(), &read).ok());
    EXPECT_EQ(read.body(), preview.body());
  }
  {
    grpc::ClientContext context;
    Auth(context, a);
    const auto old_request = Request("legacy");
    ASSERT_TRUE(client->CreateMessage(&context, old_request, &sent).ok());
  }
}

namespace {
class McpGrpcTest : public GrpcTest {
protected:
  std::filesystem::path ConfigureMcp() {
    const auto state = temp.path() / "mcp-state";
    std::filesystem::create_directory(state);
    chmod(state.c_str(), 0700);
    const auto session = state / "session.json";
    {
      std::ofstream output(session);
      output << nlohmann::json{{"token", a}};
    }
    chmod(session.c_str(), 0600);
    const auto config = temp.path() / "mcp.json";
    std::ofstream output(config);
    output << nlohmann::json{
        {"endpoint", address},          {"session_file", session.string()},
        {"state_dir", state.string()},  {"tls_ca_file", (temp.path() / "certificate.pem").string()},
        {"read_area_ids", {"RU.TEST"}}, {"post_area_ids", {"RU.TEST"}}};
    return config;
  }
};
}  // namespace
TEST_F(McpGrpcTest, StdioResearchPrepareSendAndRestartPreserveSourcesAndIdempotency) {
  const auto config = ConfigureMcp();
  std::string draft_id, saved_id;
  {
    test::McpProcess mcp(config.string());
    mcp.Initialize();
    auto prepare = mcp.Call(2, "ffido_prepare_message",
                            {{"area_id", "RU.TEST"}, {"subject", "Тема"}, {"body", "Новый TLS ответ"}});
    ASSERT_FALSE(prepare.at("isError").get<bool>()) << prepare.dump();
    const auto preview = prepare.at("structuredContent").at("data");
    EXPECT_TRUE(preview.at("preview").at("public_message"));
    EXPECT_EQ(preview.at("preview").at("from_address"), "2:5015/1.1");
    draft_id = preview.at("draft_id");
    auto unconfirmed = mcp.Call(3, "ffido_send_message", {{"draft_id", draft_id}, {"confirm", false}});
    EXPECT_TRUE(unconfirmed.at("isError"));
    auto sent = mcp.Call(4, "ffido_send_message", {{"draft_id", draft_id}, {"confirm", true}});
    ASSERT_FALSE(sent.at("isError").get<bool>()) << sent.dump();
    EXPECT_EQ(sent.at("structuredContent").at("data").at("status"), "saved_locally");
    saved_id = sent.at("structuredContent").at("data").at("message").at("message_id");
    auto search = mcp.Call(5, "ffido_search_messages", {{"area_ids", {"RU.TEST"}}, {"query", "TLS"}});
    ASSERT_FALSE(search.at("isError").get<bool>()) << search.dump();
    auto found = search.at("structuredContent").at("data");
    EXPECT_TRUE(found.at("complete"));
    ASSERT_EQ(found.at("results").size(), 1u);
    const auto reference = found.at("results")[0].at("message").at("reference");
    EXPECT_EQ(reference.at("message_id"), saved_id);
    EXPECT_NE(found.dump().find("ffido://message/"), std::string::npos);
    auto read = mcp.Call(6, "ffido_get_message", {{"reference", reference}});
    ASSERT_FALSE(read.at("isError").get<bool>()) << read.dump();
    EXPECT_EQ(read.at("structuredContent").at("data").at("message").at("body"), preview.at("preview").at("body"));
    auto thread = mcp.Call(7, "ffido_get_thread", {{"reference", reference}});
    EXPECT_FALSE(thread.at("isError").get<bool>());
    auto technical = mcp.Call(8, "ffido_get_message_technical_data", {{"reference", reference}});
    EXPECT_FALSE(technical.at("isError").get<bool>());
    auto forbidden =
        mcp.Call(9, "ffido_get_message", {{"reference", {{"conference_id", "SECRET"}, {"message_id", saved_id}}}});
    EXPECT_TRUE(forbidden.at("isError"));
  }
  {
    test::McpProcess restarted(config.string());
    restarted.Initialize();
    auto repeat = restarted.Call(2, "ffido_send_message", {{"draft_id", draft_id}, {"confirm", true}});
    ASSERT_FALSE(repeat.at("isError").get<bool>()) << repeat.dump();
    EXPECT_EQ(repeat.at("structuredContent").at("data").at("message").at("message_id"), saved_id);
  }
  service::ConferenceService areas(catalog, metadata, AccessPolicy());
  auto count = areas.GetConference("RU.TEST", "A");
  ASSERT_TRUE(count);
  EXPECT_EQ(count->total_count, 1);
  EXPECT_EQ(count->unread_count, 1);
  auto history = metadata->GetHistory("A");
  ASSERT_TRUE(history);
  EXPECT_TRUE(history->empty());
}
TEST_F(McpGrpcTest, StdioLifecycleSchemasPromptsAndLimitsAreControlled) {
  const auto config = ConfigureMcp();
  test::McpProcess mcp(config.string());
  mcp.Raw("not json\n");
  EXPECT_EQ(mcp.Read().at("error").at("code"), -32700);
  mcp.Send({{"jsonrpc", "2.0"}, {"id", 0}, {"method", "tools/list"}});
  EXPECT_TRUE(mcp.Read().contains("error"));
  mcp.Initialize();
  mcp.Send({{"jsonrpc", "2.0"}, {"id", 2}, {"method", "tools/list"}});
  const auto tools = mcp.Read().at("result").at("tools");
  EXPECT_EQ(tools.size(), 7u);
  for (const auto& tool : tools) {
    EXPECT_TRUE(tool.contains("inputSchema"));
    EXPECT_TRUE(tool.contains("outputSchema"));
  }
  mcp.Send({{"jsonrpc", "2.0"}, {"id", 3}, {"method", "prompts/list"}});
  EXPECT_EQ(mcp.Read().at("result").at("prompts").size(), 3u);
  mcp.Send(
      {{"jsonrpc", "2.0"},
       {"id", 4},
       {"method", "prompts/get"},
       {"params",
        {{"name", "digest_period"},
         {"arguments", {{"area_ids", "RU.TEST"}, {"from", "2026-01-01T00:00:00Z"}, {"to", "2026-02-01T00:00:00Z"}}}}}});
  const auto prompt = mcp.Read();
  EXPECT_NE(prompt.dump().find("неполноту"), std::string::npos);
  mcp.Raw(std::string(1024 * 1024 + 1, 'x') + "\n");
  EXPECT_EQ(mcp.Read().at("error").at("code"), -32700);
  auto invalid = mcp.Call(5, "ffido_get_message",
                          {{"reference", {{"conference_id", "RU.TEST"}, {"message_id", "x"}}}, {"token", "forbidden"}});
  EXPECT_TRUE(invalid.at("isError"));
  mcp.Send({{"jsonrpc", "2.0"}, {"id", 6}, {"method", "ping"}});
  EXPECT_TRUE(mcp.Read().at("result").empty());
}

namespace {
class LossyMcpService : public wire::Ffido::Service {
public:
  explicit LossyMcpService(service::GrpcService& backend) : backend_(backend) {
  }
  grpc::Status RestoreSession(grpc::ServerContext* context, const google::protobuf::Empty* input,
                              wire::SessionInfo* output) override {
    return backend_.RestoreSession(context, input, output);
  }
  grpc::Status PreviewMessage(grpc::ServerContext* context, const wire::CreateMessageRequest* input,
                              wire::MessagePreview* output) override {
    const auto status = backend_.PreviewMessage(context, input, output);
    std::unique_lock lock(mutex_);
    if (pause_preview_) {
      preview_ready_ = true;
      wake_.notify_all();
      while (!context->IsCancelled())
        wake_.wait_for(lock, std::chrono::milliseconds(5));
      return {grpc::StatusCode::CANCELLED, "cancelled"};
    }
    return status;
  }
  grpc::Status CreateMessage(grpc::ServerContext* context, const wire::CreateMessageRequest* input,
                             wire::CreateMessageResponse* output) override {
    const auto status = backend_.CreateMessage(context, input, output);
    if (status.ok() && !lost_.exchange(true))
      return {grpc::StatusCode::UNAVAILABLE, "simulated response loss after durable append"};
    return status;
  }
  grpc::Status ReadArchiveMessage(grpc::ServerContext* context, const wire::ReadArchiveMessageRequest*,
                                  wire::ReadArchiveMessageResponse*) override {
    {
      std::lock_guard lock(mutex_);
      reading_ = true;
    }
    wake_.notify_all();
    std::unique_lock lock(mutex_);
    while (!context->IsCancelled())
      wake_.wait_for(lock, std::chrono::milliseconds(5));
    return {grpc::StatusCode::CANCELLED, "cancelled"};
  }
  void PausePreview() {
    std::lock_guard lock(mutex_);
    pause_preview_ = true;
  }
  bool WaitForPreview() {
    std::unique_lock lock(mutex_);
    return wake_.wait_for(lock, std::chrono::seconds(5), [&] { return preview_ready_; });
  }
  bool WaitForReading() {
    std::unique_lock lock(mutex_);
    return wake_.wait_for(lock, std::chrono::seconds(5), [&] { return reading_; });
  }

private:
  service::GrpcService& backend_;
  std::atomic<bool> lost_ = false;
  std::mutex mutex_;
  std::condition_variable wake_;
  bool reading_ = false, pause_preview_ = false, preview_ready_ = false;
};
class LossyMcpGrpcTest : public McpGrpcTest {
protected:
  std::unique_ptr<LossyMcpService> proxy;
  grpc::Service* RegisteredService() override {
    proxy = std::make_unique<LossyMcpService>(*service);
    return proxy.get();
  }
};
}  // namespace
TEST_F(LossyMcpGrpcTest, LostSendResponseThenRestartRepeatsTheSameDurableOperation) {
  const auto config = ConfigureMcp();
  std::string draft;
  {
    test::McpProcess mcp(config.string());
    mcp.Initialize();
    auto prepared =
        mcp.Call(2, "ffido_prepare_message", {{"area_id", "RU.TEST"}, {"subject", "Тема"}, {"body", "Reply"}});
    ASSERT_FALSE(prepared.at("isError").get<bool>());
    draft = prepared.at("structuredContent").at("data").at("draft_id");
    auto lost = mcp.Call(3, "ffido_send_message", {{"draft_id", draft}, {"confirm", true}});
    ASSERT_TRUE(lost.at("isError").get<bool>());
    EXPECT_NE(lost.dump().find("OUTCOME_UNKNOWN"), std::string::npos);
  }
  std::string first_id;
  {
    service::MessageService messages(catalog, metadata, AccessPolicy());
    auto before = messages.GetMessages("RU.TEST", {}, "oldest", "A");
    ASSERT_TRUE(before);
    ASSERT_EQ(before->messages.size(), 1u);
    first_id = before->messages[0].ftn_message_id;
  }
  {
    test::McpProcess restarted(config.string());
    restarted.Initialize();
    auto repeated = restarted.Call(2, "ffido_send_message", {{"draft_id", draft}, {"confirm", true}});
    ASSERT_FALSE(repeated.at("isError").get<bool>()) << repeated.dump();
    EXPECT_EQ(repeated.at("structuredContent").at("data").at("ftn_message_id"), first_id);
  }
  service::MessageService messages(catalog, metadata, AccessPolicy());
  auto after = messages.GetMessages("RU.TEST", {}, "oldest", "A");
  ASSERT_TRUE(after);
  EXPECT_EQ(after->total, 1);
}
TEST_F(LossyMcpGrpcTest, PingAndCancellationWorkDuringAnActiveGrpcCall) {
  const auto config = ConfigureMcp();
  test::McpProcess mcp(config.string());
  mcp.Initialize();
  mcp.Send({{"jsonrpc", "2.0"},
            {"id", 2},
            {"method", "tools/call"},
            {"params",
             {{"name", "ffido_get_message"},
              {"arguments", {{"reference", {{"conference_id", "RU.TEST"}, {"message_id", "g#42"}}}}}}}});
  ASSERT_TRUE(proxy->WaitForReading());
  mcp.Send({{"jsonrpc", "2.0"}, {"id", 3}, {"method", "ping"}});
  EXPECT_EQ(mcp.Read().at("id"), 3);
  mcp.Send({{"jsonrpc", "2.0"}, {"method", "notifications/cancelled"}, {"params", {{"requestId", 2}}}});
  const auto cancelled = mcp.Read();
  EXPECT_EQ(cancelled.at("id"), 2);
  EXPECT_TRUE(cancelled.at("result").at("isError"));
}
TEST_F(McpGrpcTest, PrivateStateAndDraftExpiryAndProfileBindingAreEnforced) {
  const auto config = ConfigureMcp();
  std::string id;
  {
    test::McpProcess mcp(config.string());
    mcp.Initialize();
    auto prepared =
        mcp.Call(2, "ffido_prepare_message", {{"area_id", "RU.TEST"}, {"subject", "Тема"}, {"body", "Text"}});
    ASSERT_FALSE(prepared.at("isError").get<bool>());
    id = prepared.at("structuredContent").at("data").at("draft_id");
  }
  const auto path = temp.path() / "mcp-state" / (id + ".json");
  struct stat info{};
  ASSERT_EQ(stat(path.c_str(), &info), 0);
  EXPECT_EQ(info.st_mode & 0777, 0600);
  auto draft = nlohmann::json::parse(test::ReadFile(path));
  const auto original = draft;
  draft["expires_at"] = 0;
  {
    std::ofstream file(path);
    file << draft;
  }
  {
    test::McpProcess mcp(config.string());
    mcp.Initialize();
    auto expired = mcp.Call(2, "ffido_send_message", {{"draft_id", id}, {"confirm", true}});
    EXPECT_TRUE(expired.at("isError"));
    EXPECT_NE(expired.dump().find("expired"), std::string::npos);
  }
  draft = original;
  draft["profile"] = "different";
  {
    std::ofstream file(path);
    file << draft;
  }
  {
    test::McpProcess mcp(config.string());
    mcp.Initialize();
    auto foreign = mcp.Call(2, "ffido_send_message", {{"draft_id", id}, {"confirm", true}});
    EXPECT_TRUE(foreign.at("isError"));
    EXPECT_NE(foreign.dump().find("PERMISSION_DENIED"), std::string::npos);
  }
  chmod((temp.path() / "mcp-state" / "session.json").c_str(), 0644);
  test::McpProcess unsafe(config.string());
  EXPECT_THROW(unsafe.Initialize(), std::runtime_error);
}

TEST_F(McpGrpcTest, LocalInteractiveLoginSavesAnIndependentSessionWithoutEchoingPassword) {
  ASSERT_TRUE(service->ConfigureAuth({{"2:5015/1.1", "mcp-fixture-password"}}, std::string(32, 'k')));
  wire::LoginRequest login;
  login.set_name("Fixture");
  login.set_address("2:5015/1.1");
  login.set_password("mcp-fixture-password");
  wire::LoginResponse previous;
  {
    grpc::ClientContext context;
    ASSERT_TRUE(client->Login(&context, login, &previous).ok());
  }
  const auto config = ConfigureMcp();
  pid_t pid = -1;
  const auto file = config.string();
  char* argv[]{const_cast<char*>(FFIDO_PYTHON), const_cast<char*>(FFIDO_MCP_LOGIN_TEST),
               const_cast<char*>(FFIDO_MCP_BINARY), const_cast<char*>(file.c_str()), nullptr};
  ASSERT_EQ(posix_spawn(&pid, argv[0], nullptr, nullptr, argv, environ), 0);
  int status = 0;
  ASSERT_EQ(waitpid(pid, &status, 0), pid);
  ASSERT_TRUE(WIFEXITED(status));
  ASSERT_EQ(WEXITSTATUS(status), 0);
  const auto stored = nlohmann::json::parse(test::ReadFile(temp.path() / "mcp-state" / "session.json"));
  EXPECT_NE(stored.at("token"), previous.session_secret());
  {
    grpc::ClientContext context;
    Auth(context, previous.session_secret());
    google::protobuf::Empty input;
    wire::SessionInfo result;
    EXPECT_TRUE(client->RestoreSession(&context, input, &result).ok());
  }
  test::McpProcess mcp(file);
  mcp.Initialize();
  auto areas = mcp.Call(2, "ffido_list_areas", nlohmann::json::object());
  EXPECT_FALSE(areas.at("isError").get<bool>()) << areas.dump();
  mcp.Finish();
}
TEST_F(McpGrpcTest, EmptyAllowlistsAndUntrustedTlsNeverExposeData) {
  const auto config = ConfigureMcp();
  auto value = nlohmann::json::parse(test::ReadFile(config));
  value["read_area_ids"] = nlohmann::json::array();
  value["post_area_ids"] = nlohmann::json::array();
  {
    std::ofstream output(config);
    output << value;
  }
  {
    test::McpProcess mcp(config.string());
    mcp.Initialize();
    auto list = mcp.Call(2, "ffido_list_areas", nlohmann::json::object());
    ASSERT_FALSE(list.at("isError").get<bool>());
    EXPECT_EQ(list.at("structuredContent").at("data").at("total"), 0);
    auto denied =
        mcp.Call(3, "ffido_prepare_message", {{"area_id", "RU.TEST"}, {"subject", "Subject"}, {"body", "Body"}});
    EXPECT_TRUE(denied.at("isError"));
    mcp.Finish();
  }
  std::filesystem::create_directory(temp.path() / "other-ca");
  test::GenerateTlsCertificate(temp.path() / "other-ca");
  value["tls_ca_file"] = (temp.path() / "other-ca" / "certificate.pem").string();
  {
    std::ofstream output(config);
    output << value;
  }
  test::McpProcess mcp(config.string());
  mcp.Initialize();
  auto rejected = mcp.Call(2, "ffido_list_areas", nlohmann::json::object());
  EXPECT_TRUE(rejected.at("isError"));
}
TEST_F(LossyMcpGrpcTest, FifthConcurrentCallIsRejectedAndUnsupportedRpcRequiresUpgrade) {
  const auto config = ConfigureMcp();
  test::McpProcess mcp(config.string());
  mcp.Initialize();
  auto unsupported =
      mcp.Call(2, "ffido_get_thread", {{"reference", {{"conference_id", "RU.TEST"}, {"message_id", "g#42"}}}});
  EXPECT_TRUE(unsupported.at("isError"));
  EXPECT_NE(unsupported.dump().find("GRPC_12"), std::string::npos);
  for (int id = 3; id < 7; ++id)
    mcp.Send({{"jsonrpc", "2.0"},
              {"id", id},
              {"method", "tools/call"},
              {"params",
               {{"name", "ffido_get_message"},
                {"arguments", {{"reference", {{"conference_id", "RU.TEST"}, {"message_id", "g#42"}}}}}}}});
  ASSERT_TRUE(proxy->WaitForReading());
  mcp.Send({{"jsonrpc", "2.0"}, {"id", 7}, {"method", "tools/call"}, {"params", {{"name", "ffido_list_areas"}}}});
  const auto limited = mcp.Read();
  EXPECT_EQ(limited.at("id"), 7);
  EXPECT_TRUE(limited.at("result").at("isError"));
  for (int id = 3; id < 7; ++id)
    mcp.Send({{"jsonrpc", "2.0"}, {"method", "notifications/cancelled"}, {"params", {{"requestId", id}}}});
  for (int i = 0; i < 4; ++i)
    EXPECT_TRUE(mcp.Read().at("result").at("isError"));
}

TEST_F(McpGrpcTest, RawTechnicalBytesAndLargeBodiesHaveExplicitRepresentationsAndLimits) {
  std::string id;
  {
    auto lease =
        storage::JamAccess::Open(*catalog, "RU.TEST", true, std::chrono::steady_clock::now() + std::chrono::seconds(2));
    ASSERT_TRUE(lease);
    msgapi::JamMessage raw;
    raw.SetSenderName("Source");
    raw.SetSubject("Large");
    raw.SetText(std::string(100000, '\2'));
    raw.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, std::string("\0\xff", 2), 7);
    ASSERT_EQ((*lease)->messages().AddMessage(raw), msgapi::JamError::kSuccess);
    id = (*lease)->generation() + "#42";
  }
  const auto config = ConfigureMcp();
  test::McpProcess mcp(config.string());
  mcp.Initialize();
  nlohmann::json reference{{"conference_id", "RU.TEST"}, {"message_id", id}};
  auto technical = mcp.Call(2, "ffido_get_message_technical_data", {{"reference", reference}});
  ASSERT_FALSE(technical.at("isError").get<bool>());
  bool found = false;
  for (const auto& field : technical.at("structuredContent").at("data").at("subfields"))
    if (field.at("high_id") == 7) {
      found = true;
      EXPECT_EQ(field.at("value"), "AP8=");
    }
  EXPECT_TRUE(found);
  auto large = mcp.Call(3, "ffido_get_message", {{"reference", reference}});
  EXPECT_TRUE(large.at("isError"));
  EXPECT_NE(large.dump().find("RESOURCE_EXHAUSTED"), std::string::npos);
  auto block = mcp.Call(4, "ffido_get_message", {{"reference", reference}, {"body_limit", 1024}});
  ASSERT_FALSE(block.at("isError").get<bool>());
  const auto data = block.at("structuredContent").at("data");
  EXPECT_FALSE(data.at("complete").get<bool>());
  EXPECT_EQ(data.at("next_offset"), "1024");
  EXPECT_NE(data.at("message").at("source_uri").get<std::string>().find("%23"), std::string::npos);
  mcp.Finish();
}

TEST_F(McpGrpcTest, ConcurrentSendUsesOneOperationAndRevokedLocalPostPermissionBlocksReplay) {
  const auto config = ConfigureMcp();
  std::string draft;
  {
    test::McpProcess mcp(config.string());
    mcp.Initialize();
    auto prepared =
        mcp.Call(2, "ffido_prepare_message", {{"area_id", "RU.TEST"}, {"subject", "Тема"}, {"body", "Text"}});
    ASSERT_FALSE(prepared.at("isError").get<bool>());
    draft = prepared.at("structuredContent").at("data").at("draft_id");
    for (int id : {3, 4})
      mcp.Send({{"jsonrpc", "2.0"},
                {"id", id},
                {"method", "tools/call"},
                {"params", {{"name", "ffido_send_message"}, {"arguments", {{"draft_id", draft}, {"confirm", true}}}}}});
    const auto first = mcp.Read().at("result"), second = mcp.Read().at("result");
    ASSERT_FALSE(first.at("isError").get<bool>());
    ASSERT_FALSE(second.at("isError").get<bool>());
    EXPECT_EQ(first.at("structuredContent").at("data").at("message"),
              second.at("structuredContent").at("data").at("message"));
    mcp.Finish();
  }
  auto value = nlohmann::json::parse(test::ReadFile(config));
  value["post_area_ids"] = nlohmann::json::array();
  {
    std::ofstream output(config);
    output << value;
  }
  test::McpProcess restarted(config.string());
  restarted.Initialize();
  auto denied = restarted.Call(2, "ffido_send_message", {{"draft_id", draft}, {"confirm", true}});
  EXPECT_TRUE(denied.at("isError"));
  service::ConferenceService areas(catalog, metadata, AccessPolicy());
  auto count = areas.GetConference("RU.TEST", "A");
  ASSERT_TRUE(count);
  EXPECT_EQ(count->total_count, 1);
}

TEST_F(LossyMcpGrpcTest, ProcessTerminationBeforeDraftIdDoesNotCreateAWriteIntent) {
  const auto config = ConfigureMcp();
  proxy->PausePreview();
  {
    test::McpProcess mcp(config.string());
    mcp.Initialize();
    mcp.Send({{"jsonrpc", "2.0"},
              {"id", 2},
              {"method", "tools/call"},
              {"params",
               {{"name", "ffido_prepare_message"},
                {"arguments", {{"area_id", "RU.TEST"}, {"subject", "Subject"}, {"body", "Body"}}}}}});
    ASSERT_TRUE(proxy->WaitForPreview());
  }
  for (const auto& entry : std::filesystem::directory_iterator(temp.path() / "mcp-state"))
    EXPECT_EQ(entry.path().filename(), "session.json");
  service::ConferenceService areas(catalog, metadata, AccessPolicy());
  auto count = areas.GetConference("RU.TEST", "A");
  ASSERT_TRUE(count);
  EXPECT_EQ(count->total_count, 0);
}
TEST_F(McpGrpcTest, RevokedSessionCannotUseAnyBusinessTool) {
  const auto config = ConfigureMcp();
  test::McpProcess mcp(config.string());
  mcp.Initialize();
  service::AuthService auth(metadata);
  ASSERT_TRUE(auth.Revoke(a));
  auto denied = mcp.Call(2, "ffido_list_areas", nlohmann::json::object());
  EXPECT_TRUE(denied.at("isError"));
  EXPECT_NE(denied.dump().find("GRPC_16"), std::string::npos);
}

namespace {
void ExistingBody(const std::filesystem::path& base, uint32_t size, char byte) {
  const auto index = test::ReadFile(base.string() + ".jdx");
  const auto headers = test::ReadFile(base.string() + ".jhr");
  const auto offset = test::Wire32(index, 4);
  const auto body_offset = test::Wire32(headers, offset + 60);
  std::array<uint8_t, 4> length{};
  msgapi::jam_wire::Put32(length.data(), size);
  std::fstream output(base.string() + ".jhr", std::ios::in | std::ios::out | std::ios::binary);
  output.seekp(offset + 64);
  output.write(reinterpret_cast<const char*>(length.data()), 4);
  std::ofstream text(base.string() + ".jdt", std::ios::binary);
  text << std::string(body_offset, 'x') << std::string(size, byte);
}
class GrpcKoiLargeTest : public GrpcTest {
  std::string Encoding() const override {
    return "KOI8-R";
  }
};
}  // namespace

TEST_F(GrpcKoiLargeTest, LargeExistingBodySurvivesUtf8ExpansionAndTransport) {
  wire::CreateMessageResponse created;
  grpc::ClientContext create;
  Auth(create, a);
  ASSERT_TRUE(client->CreateMessage(&create, Request(), &created).ok());
  grpc::SslCredentialsOptions roots;
  roots.pem_root_certs = test::ReadFile(temp.path() / "certificate.pem");
  grpc::ChannelArguments args;
  args.SetMaxReceiveMessageSize(32 * 1024 * 1024);
  auto large = wire::Ffido::NewStub(grpc::CreateCustomChannel(address, grpc::SslCredentials(roots), args));
  for (const auto [size, byte] :
       {std::pair{7150806u, 'a'}, {10485760u, 'a'}, {10485760u, char(0x80)}, {10485761u, 'a'}}) {
    ExistingBody(temp.path() / "file", size, byte);
    grpc::ClientContext context;
    Auth(context, b);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(30));
    wire::Message message;
    const auto status = large->GetMessage(&context, created.message(), &message);
    if (size > 10485760u) {
      EXPECT_EQ(status.error_code(), grpc::StatusCode::RESOURCE_EXHAUSTED);
    } else {
      ASSERT_TRUE(status.ok()) << status.error_message();
      EXPECT_EQ(message.body().size(), uint64_t(size) * (byte == 'a' ? 1 : 3));
      EXPECT_EQ(message.body().substr(0, byte == 'a' ? 1 : 3), byte == 'a' ? "a" : "─");
    }
  }
}

TEST_F(McpGrpcTest, TenMiBExistingBodyStillUsesSmallArchiveBlocks) {
  wire::CreateMessageResponse created;
  grpc::ClientContext create;
  Auth(create, a);
  ASSERT_TRUE(client->CreateMessage(&create, Request(), &created).ok());
  ExistingBody(temp.path() / "file", 10 * 1024 * 1024, 'a');
  const auto config = ConfigureMcp();
  test::McpProcess mcp(config.string());
  mcp.Initialize();
  auto block = mcp.Call(2, "ffido_get_message",
                        {{"reference", {{"conference_id", "RU.TEST"}, {"message_id", created.message().message_id()}}},
                         {"body_limit", 1024}});
  ASSERT_FALSE(block.at("isError").get<bool>()) << block.dump();
  EXPECT_EQ(block.at("structuredContent").at("data").at("next_offset"), "1024");
  EXPECT_FALSE(block.at("structuredContent").at("data").at("complete").get<bool>());
  mcp.Finish();
}

namespace {
class GrpcParallelLargeTest : public GrpcTest {
  int AreaCount() const override {
    return 16;
  }
};
}  // namespace
TEST_F(GrpcParallelLargeTest, SixteenConcurrentLargeReadsReleaseTheirLeases) {
  std::vector<wire::MessageReference> references;
  for (int i = 0; i < 16; ++i) {
    auto request = Request("large" + std::to_string(i));
    request.set_conference_id(i == 0 ? "RU.TEST" : "RU.EXTRA" + std::to_string(i));
    grpc::ClientContext context;
    Auth(context, a);
    wire::CreateMessageResponse created;
    ASSERT_TRUE(client->CreateMessage(&context, request, &created).ok());
    references.push_back(created.message());
    ExistingBody(temp.path() / (i == 0 ? "file" : "extra" + std::to_string(i)), 10 * 1024 * 1024, char(0xb0));
  }
  grpc::SslCredentialsOptions roots;
  roots.pem_root_certs = test::ReadFile(temp.path() / "certificate.pem");
  grpc::ChannelArguments args;
  args.SetMaxReceiveMessageSize(32 * 1024 * 1024);
  auto large = wire::Ffido::NewStub(grpc::CreateCustomChannel(address, grpc::SslCredentials(roots), args));
  for (int repetition = 0; repetition < 2; ++repetition) {
    std::vector<std::future<void>> readers;
    for (const auto& reference : references)
      readers.push_back(std::async(std::launch::async, [&, reference] {
        grpc::ClientContext context;
        Auth(context, b);
        context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(60));
        wire::Message result;
        const auto status = large->GetMessage(&context, reference, &result);
        EXPECT_TRUE(status.ok()) << status.error_message();
        if (status.ok())
          EXPECT_EQ(result.body().size(), 30u * 1024 * 1024);
      }));
    for (auto& reader : readers)
      reader.get();
    for (const auto& [id, area] : catalog->areas())
      EXPECT_EQ(area.files->descriptors[0], -1);
  }
}

TEST_F(CrosspostGrpcTest, BrokenAreaStatisticsDoNotAbortTheRpcCatalog) {
  std::ofstream(temp.path() / "file.jdx", std::ios::binary).put('x');
  wire::ListConferencesRequest request;
  request.mutable_page()->set_limit(100);
  request.set_sort(wire::CONFERENCE_SORT_NAME);
  grpc::ClientContext context;
  Auth(context, a);
  wire::ListConferencesResponse result;
  ASSERT_TRUE(client->ListConferences(&context, request, &result).ok());
  ASSERT_GT(result.conferences_size(), 1);
  for (const auto& area : result.conferences()) {
    if (area.id() == "RU.TEST") {
      EXPECT_FALSE(area.statistics_known());
      EXPECT_EQ(area.availability(), wire::AREA_AVAILABILITY_AVAILABLE);
    } else
      EXPECT_TRUE(area.statistics_known());
  }
}

namespace {
class GrpcThousandAreaTest : public GrpcTest {
  struct rlimit saved{};
  int AreaCount() const override {
    return 1000;
  }
  void SetUp() override {
    ASSERT_EQ(getrlimit(RLIMIT_NOFILE, &saved), 0);
    auto limit = saved;
    limit.rlim_cur = std::min<rlim_t>(1024, saved.rlim_cur);
    ASSERT_EQ(setrlimit(RLIMIT_NOFILE, &limit), 0);
    GrpcTest::SetUp();
  }
  void TearDown() override {
    GrpcTest::TearDown();
    EXPECT_EQ(setrlimit(RLIMIT_NOFILE, &saved), 0);
  }
};
}  // namespace
TEST_F(GrpcThousandAreaTest, ServerListsAllPagesWithUnchangedLowNofile) {
  std::set<std::string> seen;
  for (int offset = 0; offset < 1000; offset += 100) {
    wire::ListConferencesRequest request;
    request.mutable_page()->set_offset(offset);
    request.mutable_page()->set_limit(100);
    request.set_sort(wire::CONFERENCE_SORT_NAME);
    grpc::ClientContext context;
    Auth(context, a);
    wire::ListConferencesResponse result;
    ASSERT_TRUE(client->ListConferences(&context, request, &result).ok());
    EXPECT_EQ(result.total(), 1000);
    for (const auto& area : result.conferences())
      EXPECT_TRUE(seen.insert(area.id()).second);
  }
  EXPECT_EQ(seen.size(), 1000u);
  for (const auto& [id, area] : catalog->areas())
    EXPECT_EQ(area.files->descriptors[0], -1);
}

TEST_F(GrpcKoiLargeTest, CancellationDuringLargeReadReleasesTheFileLease) {
  wire::CreateMessageResponse created;
  grpc::ClientContext create;
  Auth(create, a);
  ASSERT_TRUE(client->CreateMessage(&create, Request(), &created).ok());
  ExistingBody(temp.path() / "file", 10 * 1024 * 1024, char(0x80));
  auto owner = catalog->areas().at("RU.TEST").files;
  for (int attempt = 0; attempt < 2; ++attempt) {
    grpc::ClientContext context;
    Auth(context, b);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(30));
    auto reading = std::async(std::launch::async, [&] {
      wire::Message result;
      return client->GetMessage(&context, created.message(), &result);
    });
    const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    bool active = false;
    while (std::chrono::steady_clock::now() < until) {
      if (!owner->mutex.try_lock()) {
        active = true;
        break;
      }
      owner->mutex.unlock();
      std::this_thread::yield();
    }
    context.TryCancel();
    EXPECT_TRUE(active);
    EXPECT_EQ(reading.get().error_code(), grpc::StatusCode::CANCELLED);
    {
      auto lease =
          storage::JamLease::Acquire(owner, false, std::chrono::steady_clock::now() + std::chrono::seconds(10));
      ASSERT_TRUE(lease);
    }
    EXPECT_EQ(owner->descriptors[0], -1);
  }
}
