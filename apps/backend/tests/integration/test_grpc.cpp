#include <gtest/gtest.h>

#include <future>

#include "../support/echo_access.hpp"
#include "../support/jam_wire_record.hpp"
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
    builder.SetMaxSendMessageSize(4 * 1024 * 1024);
    builder.RegisterService(service.get());
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
  auto create = Request();
  wire::CreateMessageResponse created;
  UNAUTH(CreateMessage, create, created)
  google::protobuf::Empty empty, none;
  UNAUTH(MarkRead, reference, none)
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
