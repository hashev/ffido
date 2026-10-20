#include <fcntl.h>
#include <gtest/gtest.h>
#include <sys/file.h>

#include <fstream>
#include <future>

#include "../support/echo_access.hpp"
#include "../support/temp_directory.hpp"
#include "../support/tls_certificate.hpp"
#include "ftn/uue.hpp"
#include "ftn/uue_metadata.hpp"
#include "service/conference_service.hpp"
#include "service/crypto.hpp"
#include "service/jam_mapping.hpp"
#include "service/message_service.hpp"
#include "service/request_context.hpp"
#include "service/uue_service.hpp"
using namespace fidoback;
namespace {
class ServicesTest : public ::testing::Test {
protected:
  test::TempDirectory temp;
  std::shared_ptr<storage::IMetadataStore> metadata;
  std::shared_ptr<storage::JamCatalog> catalog;
  std::unique_ptr<service::MessageService> messages;
  std::unique_ptr<service::ConferenceService> conferences;
  void SetUp() override {
    std::vector<EchoAreaConfig> areas;
    for (auto [id, filename] : {std::pair{"echo.one", "different-file"}, std::pair{"echo.two", "second"}}) {
      auto base = temp.path() / filename;
      msgapi::JamBaseHeader header{};
      header.signature = msgapi::kJamSignature;
      header.base_msg_num = 42;
      header.date_created = 123;
      header.password_crc = UINT32_MAX;
      const auto bytes = msgapi::jam_wire::Encode(header);
      {
        std::ofstream output(base.string() + ".jhr", std::ios::binary);
        output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
      }
      for (auto extension : {".jdt", ".jdx"}) {
        std::ofstream output(base.string() + extension, std::ios::binary);
      }
      EchoAreaConfig area;
      area.name = id;
      area.filename = filename;
      area.msgbase_type = "JAM";
      areas.push_back(area);
    }
    auto opened = storage::JamCatalog::Build(temp.path(), areas);
    ASSERT_TRUE(opened);
    catalog = std::shared_ptr<storage::JamCatalog>(std::move(*opened));
    metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
    ASSERT_TRUE(metadata->Init());
    ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"Алексей", "2:5015/1.1", "", "2026-01-01T00:00:00Z"}));
    ASSERT_TRUE(metadata->SaveProfile("B", domain::Profile{"Борис", "2:5015/1.2", "", "2026-01-01T00:00:00Z"}));
    messages = std::make_unique<service::MessageService>(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
    conferences =
        std::make_unique<service::ConferenceService>(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  }
  void RewriteField(msgapi::JamSubFieldType type, bool remove, char replacement = '9') {
    // Emulate SMAPI's removal/rewrite without changing other fields or numbering.
    const auto path = temp.path() / "different-file.jhr";
    std::ifstream input(path, std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
    ASSERT_GE(bytes.size(), 1100u);
    const auto end = 1100u + msgapi::jam_wire::Get32(bytes.data() + 1032);
    ASSERT_LE(end, bytes.size());
    bool found = false;
    for (size_t offset = 1100; offset < end;) {
      const auto length = msgapi::jam_wire::Get32(bytes.data() + offset + 4);
      ASSERT_LE(offset + 8 + length, end);
      if (msgapi::jam_wire::Get16(bytes.data() + offset) == uint16_t(type)) {
        if (remove)
          msgapi::jam_wire::Put16(bytes.data() + offset, 0x7fff);
        else {
          ASSERT_GT(length, 0u);
          bytes[offset + 8 + length - 1] = replacement;
        }
        found = true;
        break;
      }
      offset += 8 + length;
    }
    ASSERT_TRUE(found);
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    ASSERT_TRUE(output);
  }
  domain::CreateMessageRequest Request(std::string id = "operation") {
    domain::CreateMessageRequest result;
    result.operation_id = std::move(id);
    result.subject = "Тема";
    result.body = "Привет\nМир";
    result.to_name = "All";
    return result;
  }
};
}  // namespace
TEST_F(ServicesTest, EmptyFilterAndPaginationTotals) {
  auto empty = messages->GetMessages("echo.one", {}, "newest", "A");
  ASSERT_TRUE(empty);
  EXPECT_EQ(empty->total, 0);
  EXPECT_FALSE(empty->has_more);
  auto filtered = conferences->GetConferences({}, "two", "A");
  ASSERT_TRUE(filtered);
  EXPECT_EQ(filtered->total, 1);
  ASSERT_EQ(filtered->conferences.size(), 1);
  EXPECT_EQ(filtered->conferences.front().id, "echo.two");
  EXPECT_EQ(filtered->conferences.front().total_count, 0);
  auto beyond = conferences->GetConferences({INT64_MAX, 100}, {}, "A");
  ASSERT_TRUE(beyond);
  EXPECT_TRUE(beyond->conferences.empty());
  EXPECT_EQ(beyond->total, 2);
  EXPECT_FALSE(messages->GetMessages("../different-file", {}, "newest", "A"));
  EXPECT_FALSE(messages->GetMessages("different-file", {}, "newest", "A"));
  EXPECT_FALSE(messages->GetMessages("echo.one", {-1, 20}, "newest", "A"));
  EXPECT_FALSE(messages->GetMessages("echo.one", {}, "invalid", "A"));
  EXPECT_FALSE(conferences->GetConferences({0, 101}, {}, "A"));
  auto missing = conferences->GetConference("missing", "A");
  ASSERT_FALSE(missing);
  EXPECT_EQ(missing.error().code, domain::ErrorCode::kForbidden);
}
TEST_F(ServicesTest, ReadHistoryCountersAndBookmarksArePersonal) {
  auto created = messages->CreateMessage("echo.one", Request(), "A");
  ASSERT_TRUE(created);
  EXPECT_EQ(created->status, "saved_locally");
  auto a = conferences->GetConference("echo.one", "A"), b = conferences->GetConference("echo.one", "B");
  ASSERT_TRUE(a);
  ASSERT_TRUE(b);
  EXPECT_EQ(a->unread_count, 1);
  EXPECT_EQ(b->unread_count, 1);
  EXPECT_EQ(a->total_count, 1);
  EXPECT_FALSE(a->last_message_date.empty());
  auto read = messages->GetMessage("echo.one", created->id, "A");
  ASSERT_TRUE(read);
  EXPECT_TRUE(read->is_read);
  EXPECT_EQ(read->from_name, "Алексей");
  EXPECT_EQ(read->from_address, "2:5015/1.1");
  EXPECT_EQ(read->body.find("Привет\nМир"), 0);
  ASSERT_TRUE(messages->GetMessage("echo.one", created->id, "A"));
  ASSERT_TRUE(metadata->AddBookmark("A", "echo.one"));
  a = conferences->GetConference("echo.one", "A");
  b = conferences->GetConference("echo.one", "B");
  ASSERT_TRUE(a);
  ASSERT_TRUE(b);
  EXPECT_EQ(a->unread_count, 0);
  EXPECT_EQ(b->unread_count, 1);
  EXPECT_TRUE(a->is_bookmarked);
  EXPECT_FALSE(b->is_bookmarked);
  auto history = metadata->GetHistory("A");
  ASSERT_TRUE(history);
  EXPECT_EQ(history->size(), 1);
  history = metadata->GetHistory("B");
  ASSERT_TRUE(history);
  EXPECT_TRUE(history->empty());
  auto listed = messages->GetMessages("echo.one", {}, "newest", "A");
  ASSERT_TRUE(listed);
  EXPECT_TRUE(listed->messages.front().is_read);
  EXPECT_FALSE(messages->GetMessage("echo.one", "42", "A"));
  EXPECT_FALSE(messages->MarkAsRead("echo.two", created->id, "A"));
}
TEST_F(ServicesTest, IdempotencyHandlesConcurrentRepeatLostResponseAndDifferentUser) {
  std::vector<std::future<std::expected<domain::CreateMessageResponse, domain::ApiError>>> calls;
  for (int i = 0; i < 8; ++i)
    calls.push_back(
        std::async(std::launch::async, [&] { return messages->CreateMessage("echo.one", Request(), "A"); }));
  std::string id, msgid;
  for (auto& call : calls) {
    auto result = call.get();
    ASSERT_TRUE(result);
    if (id.empty()) {
      id = result->id;
      msgid = result->ftn_message_id;
    }
    EXPECT_EQ(result->id, id);
    EXPECT_EQ(result->ftn_message_id, msgid);
  }
  auto count = conferences->GetConference("echo.one", "A");
  ASSERT_TRUE(count);
  EXPECT_EQ(count->total_count, 1);
  service::MessageService restarted(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  auto retry = restarted.CreateMessage("echo.one", Request(), "A");
  ASSERT_TRUE(retry);
  EXPECT_EQ(retry->id, id);
  auto changed = Request();
  changed.body = "other";
  auto conflict = messages->CreateMessage("echo.one", changed, "A");
  ASSERT_FALSE(conflict);
  EXPECT_EQ(conflict.error().code, domain::ErrorCode::kConflict);
  auto other = messages->CreateMessage("echo.one", Request(), "B");
  ASSERT_TRUE(other);
  EXPECT_NE(other->id, id);
  EXPECT_NE(other->ftn_message_id, msgid);
}
TEST_F(ServicesTest, ReplyUsesParentSenderAndRejectsMissingParent) {
  auto parent = messages->CreateMessage("echo.one", Request("parent"), "A");
  ASSERT_TRUE(parent);
  auto request = Request("reply");
  request.in_reply_to = parent->id;
  request.to_name = "wrong";
  request.to_address = "2:999/999";
  auto reply = messages->CreateMessage("echo.one", request, "B");
  ASSERT_TRUE(reply);
  auto read = messages->GetMessage("echo.one", reply->id, "B");
  ASSERT_TRUE(read);
  EXPECT_EQ(read->to_name, "Алексей");
  EXPECT_EQ(read->to_address, "2:5015/1.1");
  EXPECT_EQ(read->in_reply_to, parent->id);
  auto thread = messages->GetThread("echo.one", parent->id, "A");
  ASSERT_TRUE(thread);
  EXPECT_EQ(thread->messages.size(), 2);
  request.operation_id = "missing";
  request.in_reply_to = "invalid";
  EXPECT_FALSE(messages->CreateMessage("echo.one", request, "B"));
  auto count = conferences->GetConference("echo.one", "A");
  ASSERT_TRUE(count);
  EXPECT_EQ(count->total_count, 2);
}
TEST_F(ServicesTest, InvalidPayloadAndMetadataErrorsHaveNoFalseSuccess) {
  for (auto field : {"operation", "subject", "body", "address"}) {
    auto request = Request();
    if (std::string_view(field) == "operation")
      request.operation_id = "bad/id";
    if (std::string_view(field) == "subject")
      request.subject = "";
    if (std::string_view(field) == "body")
      request.body = std::string(1, '\1');
    if (std::string_view(field) == "address")
      request.to_address = "invalid";
    EXPECT_FALSE(messages->CreateMessage("echo.one", request, "A"));
  }
  auto count = conferences->GetConference("echo.one", "A");
  ASSERT_TRUE(count);
  EXPECT_EQ(count->total_count, 0);
  auto created = messages->CreateMessage("echo.one", Request(), "A");
  ASSERT_TRUE(created);
  sqlite3* db = nullptr;
  ASSERT_EQ(sqlite3_open((temp.path() / "metadata.db").c_str(), &db), SQLITE_OK);
  ASSERT_EQ(sqlite3_exec(db, "DROP TABLE read_status", nullptr, nullptr, nullptr), SQLITE_OK);
  sqlite3_close(db);
  EXPECT_FALSE(messages->GetMessages("echo.one", {}, "newest", "A"));
  EXPECT_FALSE(messages->GetMessage("echo.one", created->id, "A"));
  EXPECT_FALSE(conferences->GetConference("echo.one", "A"));
}

TEST_F(ServicesTest, DeletedSlotsAndExtremePageBoundsKeepRealCounters) {
  std::vector<std::string> ids;
  for (int i = 0; i < 3; ++i) {
    auto response = messages->CreateMessage("echo.one", Request("msg-" + std::to_string(i)), "A");
    ASSERT_TRUE(response);
    ids.push_back(response->id);
  }
  {
    auto access = storage::JamAccess::Open(*catalog, "echo.one", true,
                                           std::chrono::steady_clock::now() + std::chrono::seconds(1));
    ASSERT_TRUE(access);
    ASSERT_EQ((*access)->messages().DeleteMessage(43), msgapi::JamError::kSuccess);
  }
  auto newest = messages->GetMessages("echo.one", {0, 1}, "newest", "A");
  ASSERT_TRUE(newest);
  EXPECT_EQ(newest->total, 2);
  EXPECT_TRUE(newest->has_more);
  EXPECT_EQ(newest->messages.front().id, ids[2]);
  auto oldest = messages->GetMessages("echo.one", {1, 1}, "oldest", "A");
  ASSERT_TRUE(oldest);
  EXPECT_EQ(oldest->messages.front().id, ids[2]);
  EXPECT_FALSE(oldest->has_more);
  auto beyond = messages->GetMessages("echo.one", {INT64_MAX, 100}, "newest", "A");
  ASSERT_TRUE(beyond);
  EXPECT_EQ(beyond->total, 2);
  EXPECT_TRUE(beyond->messages.empty());
  EXPECT_FALSE(beyond->has_more);
  EXPECT_FALSE(messages->MarkAsRead("echo.one", ids[1], "A"));
  EXPECT_FALSE(messages->GetMessage("echo.one", ids[1], "A"));
  auto conference = conferences->GetConference("echo.one", "A");
  ASSERT_TRUE(conference);
  EXPECT_EQ(conference->total_count, 2);
  EXPECT_EQ(conference->unread_count, 2);
  const auto lastread = temp.path() / "different-file.jlr";
  {
    std::ofstream output(lastread, std::ios::binary);
    output << "external HPT read state";
  }
  ASSERT_TRUE(messages->GetMessage("echo.one", ids[0], "A"));
  std::ifstream input(lastread, std::ios::binary);
  EXPECT_EQ(std::string(std::istreambuf_iterator<char>(input), {}), "external HPT read state");
}

namespace {
class FailFirstWrite : public storage::JamIo {
public:
  ssize_t Write(int, const void*, size_t, off_t) override {
    errno = ENOSPC;
    return -1;
  }
};
class FailIndexSync : public storage::JamIo {
public:
  int count = 0;
  int Sync(int fd) override {
    if (++count == 3) {
      errno = EIO;
      return -1;
    }
    return storage::JamIo::Sync(fd);
  }
};
}  // namespace
TEST_F(ServicesTest, SameOperationRetriesRollbackAndUncertainCommit) {
  service::MessageService failing(catalog, metadata, test::EchoAccess(*catalog, temp.path()), "cp866",
                                  std::make_shared<FailFirstWrite>());
  auto request = Request("rollback");
  EXPECT_FALSE(failing.CreateMessage("echo.one", request, "A"));
  auto retry = messages->CreateMessage("echo.one", request, "A");
  ASSERT_TRUE(retry);
  auto count = conferences->GetConference("echo.one", "A");
  ASSERT_TRUE(count);
  EXPECT_EQ(count->total_count, 1);
  service::MessageService uncertain(catalog, metadata, test::EchoAccess(*catalog, temp.path()), "cp866",
                                    std::make_shared<FailIndexSync>());
  request = Request("uncertain");
  EXPECT_FALSE(uncertain.CreateMessage("echo.one", request, "A"));
  auto recovered = messages->CreateMessage("echo.one", request, "A");
  ASSERT_TRUE(recovered);
  auto repeated = messages->CreateMessage("echo.one", request, "A");
  ASSERT_TRUE(repeated);
  EXPECT_EQ(repeated->id, recovered->id);
  count = conferences->GetConference("echo.one", "A");
  ASSERT_TRUE(count);
  EXPECT_EQ(count->total_count, 2);
}

TEST_F(ServicesTest, SearchCountsDatesAndConferenceSortsAreConsistent) {
  auto first = Request("first");
  first.subject = "needle";
  auto a = messages->CreateMessage("echo.one", first, "A");
  ASSERT_TRUE(a);
  auto b = messages->CreateMessage("echo.one", Request("second"), "A");
  ASSERT_TRUE(b);
  auto filtered = messages->GetMessages("echo.one", {0, 1}, "oldest", "A", "needle");
  ASSERT_TRUE(filtered);
  EXPECT_EQ(filtered->total, 1);
  EXPECT_FALSE(filtered->has_more);
  EXPECT_EQ(filtered->messages.front().id, a->id);
  auto none = messages->GetMessages("echo.one", {}, "newest", "A", "absent");
  ASSERT_TRUE(none);
  EXPECT_EQ(none->total, 0);
  auto sorted = conferences->GetConferences({}, {}, "A", "unread");
  ASSERT_TRUE(sorted);
  EXPECT_EQ(sorted->conferences.front().id, "echo.one");
  sorted = conferences->GetConferences({}, {}, "A", "date");
  ASSERT_TRUE(sorted);
  EXPECT_EQ(sorted->conferences.front().id, "echo.one");
  EXPECT_FALSE(conferences->GetConferences({}, {}, "A", "invalid"));
}
TEST_F(ServicesTest, ThreadBranchPaginationMissingParentCyclesAndDeletedNodes) {
  auto root = messages->CreateMessage("echo.one", Request("root"), "A");
  ASSERT_TRUE(root);
  auto request = Request("child-one");
  request.in_reply_to = root->id;
  auto one = messages->CreateMessage("echo.one", request, "B");
  ASSERT_TRUE(one);
  request.operation_id = "child-two";
  auto two = messages->CreateMessage("echo.one", request, "B");
  ASSERT_TRUE(two);
  auto page = messages->GetThread("echo.one", two->id, "A", {1, 1});
  ASSERT_TRUE(page);
  EXPECT_EQ(page->total, 3);
  EXPECT_TRUE(page->has_more);
  ASSERT_EQ(page->messages.size(), 1);
  EXPECT_EQ(page->messages.front().id, one->id);
  page = messages->GetThread("echo.one", root->id, "A", {INT64_MAX, 20});
  ASSERT_TRUE(page);
  EXPECT_TRUE(page->messages.empty());
  EXPECT_FALSE(page->has_more);
  {
    auto access = storage::JamAccess::Open(*catalog, "echo.one", true,
                                           std::chrono::steady_clock::now() + std::chrono::seconds(1));
    ASSERT_TRUE(access);
    const auto index = test::ReadFile(temp.path() / "different-file.jdx");
    const auto root_offset = msgapi::jam_wire::Get32(reinterpret_cast<const uint8_t*>(index.data()) + 4);
    std::array<uint8_t, 4> bytes{};
    msgapi::jam_wire::Put32(bytes.data(), 43);
    ASSERT_EQ(pwrite((*access)->files().descriptors[0], bytes.data(), bytes.size(), root_offset + 24),
              4);  // cycle 42 -> 43 -> 42
  }
  page = messages->GetThread("echo.one", one->id, "A");
  ASSERT_TRUE(page);
  EXPECT_EQ(page->total, 3);
  {
    auto access = storage::JamAccess::Open(*catalog, "echo.one", true,
                                           std::chrono::steady_clock::now() + std::chrono::seconds(1));
    ASSERT_TRUE(access);
    ASSERT_EQ((*access)->messages().DeleteMessage(42), msgapi::JamError::kSuccess);
  }
  EXPECT_FALSE(messages->GetThread("echo.one", root->id, "A"));
  page = messages->GetThread("echo.one", one->id, "A");
  ASSERT_TRUE(page);
  EXPECT_EQ(page->total, 1);  // absent/deleted parent leaves a readable subtree
  EXPECT_FALSE(messages->GetThread("echo.one", one->id, "A", {-1, 20}));
}
TEST_F(ServicesTest, IdempotencySurvivesActualMetadataReopen) {
  auto created = messages->CreateMessage("echo.one", Request(), "A");
  ASSERT_TRUE(created);
  messages.reset();
  conferences.reset();
  metadata.reset();
  metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(metadata->Init());
  messages = std::make_unique<service::MessageService>(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  auto retry = messages->CreateMessage("echo.one", Request(), "A");
  ASSERT_TRUE(retry);
  EXPECT_EQ(retry->id, created->id);
  EXPECT_EQ(retry->ftn_message_id, created->ftn_message_id);
}

TEST_F(ServicesTest, ThreadUsesExactFtnReplyWhenNumericLinksAreMissing) {
  auto root = messages->CreateMessage("echo.one", Request("root"), "A");
  ASSERT_TRUE(root);
  auto request = Request("child");
  request.in_reply_to = root->id;
  auto reply = messages->CreateMessage("echo.one", request, "B");
  ASSERT_TRUE(reply);
  {
    auto access = storage::JamAccess::Open(*catalog, "echo.one", true,
                                           std::chrono::steady_clock::now() + std::chrono::seconds(1));
    ASSERT_TRUE(access);
    const auto index = test::ReadFile(temp.path() / "different-file.jdx");
    const auto offset = msgapi::jam_wire::Get32(reinterpret_cast<const uint8_t*>(index.data()) + 8 + 4);
    std::array<uint8_t, 4> bytes{};
    ASSERT_EQ(pwrite((*access)->files().descriptors[0], bytes.data(), bytes.size(), offset + 24), 4);
  }
  auto thread = messages->GetThread("echo.one", root->id, "A");
  ASSERT_TRUE(thread);
  EXPECT_EQ(thread->total, 2);
}

TEST(StorageErrorMapping, LockReasonsRemainDistinctWithoutInternalDiagnostics) {
  using domain::ErrorCode;
  using storage::CoordinationError;
  using storage::JamLockError;
  for (const auto& [reason, code] :
       std::vector<std::pair<CoordinationError, ErrorCode>>{{CoordinationError::kTimeout, ErrorCode::kDeadline},
                                                            {CoordinationError::kCancelled, ErrorCode::kCancelled},
                                                            {CoordinationError::kIo, ErrorCode::kPrecondition},
                                                            {CoordinationError::kChanged, ErrorCode::kPrecondition}}) {
    EXPECT_EQ(service::JamError(storage::JamAccessError(reason)).code, code);
  }
  for (const auto& [reason, code] :
       std::vector<std::pair<JamLockError, ErrorCode>>{{JamLockError::kTimeout, ErrorCode::kDeadline},
                                                       {JamLockError::kCancelled, ErrorCode::kCancelled},
                                                       {JamLockError::kIo, ErrorCode::kServer},
                                                       {JamLockError::kReadOnly, ErrorCode::kPrecondition}}) {
    EXPECT_EQ(service::JamError(storage::JamAccessError(reason)).code, code);
  }
  EXPECT_EQ(service::JamError(storage::JamAccessError(storage::CatalogError::kNotFound)).code, ErrorCode::kNotFound);
  EXPECT_EQ(service::JamError(storage::JamAccessError(msgapi::JamError::kCorruptedData)).code, ErrorCode::kServer);
}

TEST_F(ServicesTest, OpaqueMessageNumbersRejectAllMalformedSuffixes) {
  auto created = messages->CreateMessage("echo.one", Request("root"), "A");
  ASSERT_TRUE(created);
  auto access =
      storage::JamAccess::Open(*catalog, "echo.one", false, std::chrono::steady_clock::now() + std::chrono::seconds(1));
  ASSERT_TRUE(access);
  const auto prefix = (*access)->generation() + "#";
  for (const auto* suffix : {"", "0", "-1", "+1", "4294967296", "1x", " 1", "1#extra"}) {
    EXPECT_FALSE(service::MessageNumber(**access, prefix + suffix)) << suffix;
  }
  EXPECT_FALSE(service::MessageNumber(**access, "other-generation#1"));
  auto valid = service::MessageNumber(**access, created->id);
  ASSERT_TRUE(valid);
  EXPECT_EQ(*valid, 42);
}

TEST_F(ServicesTest, LegacyEchomailPreservesLayoutAndResolvesOnlyKnownAddresses) {
  msgapi::JamMessageBase base((temp.path() / "different-file").string());
  ASSERT_EQ(base.Open(), msgapi::JamError::kSuccess);
  msgapi::JamMessage original;
  original.SetSenderName("Автор");
  original.SetReceiverName("All");
  original.SetSubject("Legacy");
  original.SetMsgId("2:5001/100.1 abc123");
  original.SetReplyId("2:5030/49 parent123");
  original.SetText("Привет\r\r DP> Цитата\r\n  отступ\tтекст\nПодпись\r");
  ASSERT_EQ(base.AddMessage(original), msgapi::JamError::kSuccess);
  base.Close();
  auto listed = messages->GetMessages("echo.one", {}, "oldest", "A");
  ASSERT_TRUE(listed);
  ASSERT_EQ(listed->messages.size(), 1);
  const auto id = listed->messages.front().id;
  auto detail = messages->GetMessage("echo.one", id, "A");
  ASSERT_TRUE(detail);
  EXPECT_EQ(detail->from_address, "2:5001/100.1");
  EXPECT_TRUE(detail->to_address.empty());  // REPLY is not a destination address.
  EXPECT_EQ(detail->body, "Привет\n\n DP> Цитата\n  отступ\tтекст\nПодпись\n");
  EXPECT_EQ(listed->messages.front().body_preview, detail->body);
  ASSERT_EQ(base.Open(), msgapi::JamError::kSuccess);
  auto stored = base.ReadMessage(42);
  ASSERT_TRUE(stored);
  EXPECT_EQ(stored->text(), original.text());  // Display normalization never rewrites JAM.
  base.Close();
  auto reply = Request("legacy-reply");
  reply.in_reply_to = id;
  auto created = messages->CreateMessage("echo.one", reply, "B");
  ASSERT_TRUE(created);
  auto sent = messages->GetMessage("echo.one", created->id, "B");
  ASSERT_TRUE(sent);
  EXPECT_EQ(sent->to_address, "2:5001/100.1");
  EXPECT_EQ(sent->from_address, "2:5015/1.2");
}

TEST_F(ServicesTest, AddressFallbackRejectsNonFtnIdsAndPreservesExplicitFields) {
  for (const auto* id : {"mail@example.org abc", "2:5001/100.1", "2:5001/100.1   ", "2:70000/1 abc"}) {
    msgapi::JamMessageBase base((temp.path() / "different-file").string());
    ASSERT_EQ(base.Open(), msgapi::JamError::kSuccess);
    msgapi::JamMessage message;
    message.SetMsgId(id);
    message.SetText("body");
    ASSERT_EQ(base.AddMessage(message), msgapi::JamError::kSuccess);
  }
  {
    msgapi::JamMessageBase base((temp.path() / "different-file").string());
    ASSERT_EQ(base.Open(), msgapi::JamError::kSuccess);
    msgapi::JamMessage message;
    message.SetMsgId("2:5001/100.1 abc");
    message.SetOriginAddress("2:1/2.3");
    message.SetDestAddress("2:4/5.6");
    ASSERT_EQ(base.AddMessage(message), msgapi::JamError::kSuccess);
  }
  auto listed = messages->GetMessages("echo.one", {}, "oldest", "A");
  ASSERT_TRUE(listed);
  ASSERT_EQ(listed->messages.size(), 5);
  for (size_t i = 0; i < 4; ++i)
    EXPECT_TRUE(listed->messages[i].from_address.empty());
  EXPECT_EQ(listed->messages.back().from_address, "2:1/2.3");
  EXPECT_EQ(listed->messages.back().to_address, "2:4/5.6");
}

TEST_F(ServicesTest, RecipientSurvivesEchoHeaderRewriteAndMetadataRestart) {
  auto request = Request();
  request.to_address = "2:5015/8.8";
  auto created = messages->CreateMessage("echo.one", request, "A");
  ASSERT_TRUE(created);
  RewriteField(msgapi::JamSubFieldType::kDAddress, true);
  // Includes recovery of sends journalled before this fix, with no schema migration.
  metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(metadata->Init());
  messages = std::make_unique<service::MessageService>(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  auto detail = messages->GetMessage("echo.one", created->id, "B");
  ASSERT_TRUE(detail);
  EXPECT_EQ(detail->to_address, request.to_address);
  auto listed = messages->GetMessages("echo.one", {}, "newest", "B");
  ASSERT_TRUE(listed);
  ASSERT_EQ(listed->messages.size(), 1);
  EXPECT_EQ(listed->messages.front().to_address, request.to_address);
  auto operation = metadata->FindOperation("A", request.operation_id);
  ASSERT_TRUE(operation && *operation);
  const auto& op = **operation;
  for (auto key :
       {storage::ReadKey{"echo.two", op.generation, "42"}, storage::ReadKey{"echo.one", "other-generation", "42"},
        storage::ReadKey{"echo.one", op.generation, "43"}}) {
    auto missing = metadata->GetCommittedRecipient(key, op.ftn_msgid);
    ASSERT_TRUE(missing);
    EXPECT_TRUE(missing->empty());
  }
  auto changed_id = metadata->GetCommittedRecipient({"echo.one", op.generation, "42"}, "2:5015/1.1 other");
  ASSERT_TRUE(changed_id);
  EXPECT_TRUE(changed_id->empty());
  for (auto state : {storage::OperationState::kPending, storage::OperationState::kRolledBack,
                     storage::OperationState::kQuarantine}) {
    ASSERT_TRUE(metadata->SetOperationState("A", request.operation_id, state));
    auto uncommitted = metadata->GetCommittedRecipient({"echo.one", op.generation, "42"}, op.ftn_msgid);
    ASSERT_TRUE(uncommitted);
    EXPECT_TRUE(uncommitted->empty());
  }
}

TEST_F(ServicesTest, ExplicitJamRecipientWinsAndChangedMessageIdCannotBorrowAddress) {
  auto request = Request();
  request.to_address = "2:5015/8.8";
  auto created = messages->CreateMessage("echo.one", request, "A");
  ASSERT_TRUE(created);
  RewriteField(msgapi::JamSubFieldType::kDAddress, false);
  auto current = messages->GetMessage("echo.one", created->id, "A");
  ASSERT_TRUE(current);
  EXPECT_EQ(current->to_address, "2:5015/8.9");
  RewriteField(msgapi::JamSubFieldType::kDAddress, true);
  RewriteField(msgapi::JamSubFieldType::kMsgId, false, 'z');
  current = messages->GetMessage("echo.one", created->id, "A");
  ASSERT_TRUE(current);
  EXPECT_TRUE(current->to_address.empty());
}

TEST_F(ServicesTest, CorruptRecipientJournalFailsSafely) {
  auto request = Request();
  request.to_address = "2:5015/8.8";
  auto created = messages->CreateMessage("echo.one", request, "A");
  ASSERT_TRUE(created);
  RewriteField(msgapi::JamSubFieldType::kDAddress, true);
  auto op = metadata->FindOperation("A", request.operation_id);
  ASSERT_TRUE(op && *op);
  const auto header = (**op).plan.header;
  for (int fault = 0; fault < 4; ++fault) {
    auto bytes = header;
    if (fault == 0)
      bytes[0] = 0;
    if (fault == 1)
      msgapi::jam_wire::Put32(bytes.data() + 8, UINT32_MAX);
    if (fault == 2)
      msgapi::jam_wire::Put32(bytes.data() + 80, UINT32_MAX);
    if (fault == 3) {
      // Valid bounds, but a bad FTN address must never reach the API.
      for (size_t at = 76; at < bytes.size();) {
        const auto length = msgapi::jam_wire::Get32(bytes.data() + at + 4);
        if (msgapi::jam_wire::Get16(bytes.data() + at) == uint16_t(msgapi::JamSubFieldType::kDAddress))
          bytes[at + 8] = 'x';
        at += 8 + length;
      }
    }
    sqlite3* db = nullptr;
    ASSERT_EQ(sqlite3_open((temp.path() / "metadata.db").c_str(), &db), SQLITE_OK);
    sqlite3_stmt* update = nullptr;
    ASSERT_EQ(sqlite3_prepare_v2(db, "UPDATE operations SET header_append=?", -1, &update, nullptr), SQLITE_OK);
    ASSERT_EQ(sqlite3_bind_blob(update, 1, bytes.data(), int(bytes.size()), SQLITE_TRANSIENT), SQLITE_OK);
    ASSERT_EQ(sqlite3_step(update), SQLITE_DONE);
    sqlite3_finalize(update);
    sqlite3_close(db);
    auto result = messages->GetMessage("echo.one", created->id, "A");
    ASSERT_FALSE(result) << fault;
    EXPECT_EQ(result.error().code, domain::ErrorCode::kServer);
  }
}

TEST_F(ServicesTest, EchoPolicySeparatesReadPostAndHidesBeforePagination) {
  service::HptConfiguration config;
  config.echoes = {
      {"ECHO.ONE", temp.path() / "different-file", {{"2:5015/1.1", {true, false}}, {"2:5015/1.2", {false, true}}}},
      {"echo.two", temp.path() / "second", {{"2:5015/1.1", {false, false}}}}};
  auto built = service::EchoAccess::Build(config, *catalog);
  ASSERT_TRUE(built);
  service::ConferenceService restricted_conferences(catalog, metadata, *built);
  service::MessageService restricted_messages(catalog, metadata, *built);
  auto list = restricted_conferences.GetConferences({0, 1}, {}, "A");
  ASSERT_TRUE(list);
  EXPECT_EQ(list->total, 1);
  EXPECT_FALSE(list->has_more);
  EXPECT_TRUE(list->conferences[0].can_read);
  EXPECT_FALSE(list->conferences[0].can_post);
  auto post = restricted_messages.CreateMessage("echo.one", Request("post-only"), "B");
  ASSERT_TRUE(post);
  auto meta = restricted_conferences.GetConference("echo.one", "B");
  ASSERT_TRUE(meta);
  EXPECT_FALSE(meta->can_read);
  EXPECT_TRUE(meta->can_post);
  EXPECT_EQ(meta->total_count, 0);
  EXPECT_TRUE(meta->last_message_date.empty());
  auto denied_post = restricted_messages.CreateMessage("echo.one", Request("readonly"), "A");
  ASSERT_FALSE(denied_post);
  EXPECT_EQ(denied_post.error().code, domain::ErrorCode::kForbidden);
  EXPECT_FALSE(metadata->FindOperation("A", "readonly")->has_value());
  auto denied = restricted_messages.GetMessage("echo.one", post->id, "B");
  ASSERT_FALSE(denied);
  EXPECT_EQ(denied.error().code, domain::ErrorCode::kForbidden);
  EXPECT_FALSE(restricted_messages.GetMessages("echo.one", {}, "newest", "B"));
  EXPECT_FALSE(restricted_messages.MarkAsRead("echo.one", post->id, "B"));
  EXPECT_FALSE(restricted_messages.GetThread("echo.one", post->id, "B"));
  EXPECT_TRUE(metadata->GetHistory("B", 100)->empty());
  auto reply = Request("post-only-reply");
  reply.in_reply_to = post->id;
  EXPECT_FALSE(restricted_messages.CreateMessage("echo.one", reply, "B"));
  auto read = restricted_messages.GetMessage("echo.one", post->id, "A");
  ASSERT_TRUE(read);
  EXPECT_EQ(read->from_address, "2:5015/1.2");
  EXPECT_EQ(conferences->GetConference("echo.one", "A")->total_count, 1);
  EXPECT_FALSE(restricted_conferences.GetConference("echo.two", "A"));
  EXPECT_EQ(restricted_conferences.GetConferences({}, "two", "A")->total, 0);
  // A successful idempotent operation must not bypass a newly revoked permission.
  config.echoes[0].links["2:5015/1.2"] = {false, false};
  auto revoked = service::EchoAccess::Build(config, *catalog);
  ASSERT_TRUE(revoked);
  service::MessageService after_revoke(catalog, metadata, *revoked);
  EXPECT_FALSE(after_revoke.CreateMessage("echo.one", Request("post-only"), "B"));
}

TEST_F(ServicesTest, EchoPolicyRejectsPathMismatchAndCaseCollisionAndDefaultsToDenied) {
  service::HptConfiguration config;
  auto empty = service::EchoAccess::Build(config, *catalog);
  ASSERT_TRUE(empty);
  EXPECT_FALSE((*empty)->Permissions(*metadata, "A", "echo.one")->read);
  config.echoes = {{"ECHO.ONE", temp.path() / "second", {{"2:5015/1.1", {true, true}}}}};
  EXPECT_FALSE(service::EchoAccess::Build(config, *catalog));
  config.echoes[0].filename = temp.path() / "different-file";
  EXPECT_TRUE(service::EchoAccess::Build(config, *catalog));
  config.echoes.push_back(config.echoes[0]);
  config.echoes[1].name = "echo.one";
  EXPECT_FALSE(service::EchoAccess::Build(config, *catalog));
}

TEST_F(ServicesTest, EchoPolicyRequiresAllJamCompanionsToMatch) {
  std::filesystem::create_hard_link(temp.path() / "different-file.jhr", temp.path() / "alias.jhr");
  std::filesystem::copy_file(temp.path() / "different-file.jdt", temp.path() / "alias.jdt");
  std::filesystem::copy_file(temp.path() / "different-file.jdx", temp.path() / "alias.jdx");
  service::HptConfiguration config;
  config.echoes = {{"echo.one", temp.path() / "alias", {{"2:5015/1.1", {true, true}}}}};
  EXPECT_FALSE(service::EchoAccess::Build(config, *catalog));
}

TEST_F(ServicesTest, ConferenceCountersDoNotDecodeMessageBodies) {
  auto sent = messages->CreateMessage("echo.one", Request("bad-charset"), "A");
  ASSERT_TRUE(sent);
  const auto path = temp.path() / "different-file.jhr";
  auto bytes = test::ReadFile(path);
  const auto offset = bytes.find("CHRS: CP866 2");
  ASSERT_NE(offset, std::string::npos);
  bytes.replace(offset, 13, "CHRS: XFAIL 2");
  std::ofstream(path, std::ios::binary | std::ios::trunc) << bytes;
  auto conference = conferences->GetConference("echo.one", "A");
  ASSERT_TRUE(conference);
  EXPECT_EQ(conference->total_count, 1);
  EXPECT_EQ(conference->unread_count, 1);
  EXPECT_FALSE(messages->GetMessage("echo.one", sent->id, "A"));
  EXPECT_EQ(test::ReadFile(path), bytes);
}

TEST_F(ServicesTest, OutgoingCyrillicNNormalizesEveryFieldAndPreservesOtherCharacters) {
  ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"НН H нН", "2:5015/1.1", "", ""}));
  auto request = Request("normalize-n");
  request.to_name = "НН H нН";
  request.subject = "НН H нН";
  request.body = "НН H нН\n> Н цитата Н\nFrom: Н\nSubject: Н\nН";
  auto created = messages->CreateMessage("echo.one", request, "A");
  ASSERT_TRUE(created);
  auto read = messages->GetMessage("echo.one", created->id, "A");
  ASSERT_TRUE(read);
  EXPECT_EQ(read->from_name, "HH H нH");
  EXPECT_EQ(read->to_name, "HH H нH");
  EXPECT_EQ(read->subject, "HH H нH");
  EXPECT_EQ(read->body, "HH H нH\n> H цитата H\nFrom: H\nSubject: H\nH\n--- FFIDO\n * Origin: FFIDO (2:5015/1.1)\n");
  auto profile = metadata->GetProfile("A");
  ASSERT_TRUE(profile);
  EXPECT_EQ(profile->name, "НН H нН");
  EXPECT_EQ(request.body, "НН H нН\n> Н цитата Н\nFrom: Н\nSubject: Н\nН");
}

TEST_F(ServicesTest, UueSearchAndAutomaticLegacyAssemblyNeverChangeReadState) {
  service::UueService uue(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  const std::string file(100, 'A');
  const auto encoded = ftn::uue::Encode(file, "file.bin").value();
  const auto split = encoded.find('\n', encoded.find('\n') + 1) + 1;
  auto first = Request("uue-one");
  first.subject = "file [1/2]";
  first.body = encoded.substr(0, split);
  auto a = messages->CreateMessage("echo.one", first, "A");
  ASSERT_TRUE(a);
  auto before = uue.Search("echo.one", "", 0, 1, "A");
  ASSERT_TRUE(before);
  ASSERT_EQ(before->parts.size(), 1);
  EXPECT_FALSE(before->more);
  EXPECT_TRUE(metadata->GetHistory("A")->empty());
  EXPECT_EQ(metadata->GetReadCount("A", "echo.one", before->generation).value(), 0);
  EXPECT_TRUE(metadata->LastOpened("A", "echo.one")->message.empty());
  auto second = Request("uue-two");
  second.subject = "file [2/2]";
  second.body = encoded.substr(split);
  auto b = messages->CreateMessage("echo.one", second, "A");
  ASSERT_TRUE(b);
  auto late = uue.Search("echo.one", before->generation, before->next, 1, "A");
  ASSERT_TRUE(late);
  ASSERT_EQ(late->parts.size(), 1);
  std::vector<service::UueReference> sources{before->parts[0].source, late->parts[0].source};
  auto missing = uue.Assemble({sources[0]}, false, "A");
  ASSERT_TRUE(missing);
  EXPECT_EQ(missing->missing, std::vector<uint32_t>{2});
  auto assembled = uue.Assemble({sources[1], sources[0], sources[1]}, false, "A");
  ASSERT_TRUE(assembled);
  EXPECT_EQ(assembled->state, service::UueState::kReady);
  EXPECT_FALSE(assembled->verified);
  EXPECT_EQ(assembled->filename, "file.bin");
  EXPECT_FALSE(assembled->diagnostic.empty());
  auto chunk = uue.Chunk(assembled->id, 0, 65536, "A");
  ASSERT_TRUE(chunk);
  EXPECT_EQ(chunk->bytes, file);
  EXPECT_TRUE(chunk->eof);
  EXPECT_TRUE(metadata->GetHistory("A")->empty());
  EXPECT_EQ(metadata->GetReadCount("A", "echo.one", before->generation).value(), 0);
  EXPECT_FALSE(uue.Search("echo.one", "wrong-generation", before->next, 1, "A"));
  EXPECT_FALSE(uue.Chunk(assembled->id, 0, 65536, "B"));
  EXPECT_FALSE(uue.Chunk(assembled->id, 0, 65537, "A"));
  EXPECT_FALSE(uue.Chunk(assembled->id, 101, 1, "A"));
  EXPECT_NE(uue.Assemble({sources[1], sources[0]}, true, "A")->state, service::UueState::kReady);
}
TEST_F(ServicesTest, UueLegacyAutomaticGroupingRejectsConflictsButCannotDetectStructuralMixing) {
  service::UueService uue(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  auto append = [&](std::string subject, std::string body, std::string from = "2:5015/1.1", std::string to = "") {
    auto access = storage::JamAccess::Open(*catalog, "echo.one", true, service::RequestDeadline()).value();
    msgapi::JamMessage message;
    message.SetSenderName("A");
    message.SetReceiverName("All");
    message.SetOriginAddress(from);
    message.SetDestAddress(to);
    message.SetSubject(subject);
    message.SetText(body);
    const auto number = access->messages().base_header().base_msg_num + access->messages().message_count();
    message.SetMsgId(from + " legacy" + std::to_string(number));
    EXPECT_EQ(access->messages().AddMessage(message), msgapi::JamError::kSuccess);
    return service::UueReference{"echo.one", service::MessageId(*access, number), 0};
  };
  const auto first = ftn::uue::Encode(std::string(90, 'A'), "same.bin").value();
  const auto second = ftn::uue::Encode(std::string(90, 'B'), "same.bin").value();
  const auto split = first.find('\n', first.find('\n') + 1) + 1;
  auto a = append("file [1/2]", first.substr(0, split));
  auto b = append("file [2/2]", second.substr(split));
  auto mixed = uue.Assemble({b, a}, false, "A");
  ASSERT_TRUE(mixed);
  ASSERT_EQ(mixed->state, service::UueState::kReady);
  EXPECT_FALSE(mixed->verified);
  EXPECT_FALSE(mixed->diagnostic.empty());
  EXPECT_EQ(uue.Chunk(mixed->id, 0, 65536, "A")->bytes, std::string(45, 'A') + std::string(45, 'B'));
  auto conflicting = append("file [2/2]", first.substr(split));
  EXPECT_EQ(uue.Assemble({a, b, conflicting}, false, "A")->state, service::UueState::kConflict);
  auto other_subject = append("other [2/2]", second.substr(split));
  EXPECT_EQ(uue.Assemble({a, other_subject}, false, "A")->state, service::UueState::kConflict);
  EXPECT_EQ(uue.Assemble({a, other_subject}, true, "A")->state, service::UueState::kReady);
  auto other_total = append("file [2/3]", second.substr(split));
  EXPECT_EQ(uue.Assemble({a, other_total}, false, "A")->state, service::UueState::kConflict);
  auto other_from = append("file [2/2]", second.substr(split), "2:5015/1.2");
  EXPECT_FALSE(uue.Assemble({a, other_from}, false, "A"));
  auto other_to = append("file [2/2]", second.substr(split), "2:5015/1.1", "2:5015/1.9");
  EXPECT_FALSE(uue.Assemble({a, other_to}, false, "A"));
  auto unnumbered_a = append("unnumbered", first.substr(0, split));
  auto unnumbered_b = append("unnumbered", first.substr(split));
  EXPECT_FALSE(uue.Assemble({unnumbered_a, unnumbered_b}, false, "A"));
  EXPECT_EQ(uue.Assemble({unnumbered_a, unnumbered_b}, true, "A")->state, service::UueState::kReady);
}
TEST_F(ServicesTest, UueCacheRevalidatesAccessAndSourceDeletion) {
  auto policy = test::EchoAccess(*catalog, temp.path());
  service::UueService uue(catalog, metadata, policy);
  auto request = Request("uue-cache");
  request.body = ftn::uue::Encode("payload", "a.bin").value();
  auto sent = messages->CreateMessage("echo.one", request, "A");
  ASSERT_TRUE(sent);
  auto found = uue.Search("echo.one", "", 0, 100, "A");
  ASSERT_TRUE(found);
  ASSERT_EQ(found->parts.size(), 1);
  auto file = uue.Assemble({found->parts[0].source}, false, "A");
  ASSERT_TRUE(file);
  ASSERT_EQ(file->state, service::UueState::kReady);
  ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"A", "2:9/9.9", "", ""}));
  EXPECT_FALSE(uue.Chunk(file->id, 0, 10, "A"));
  ASSERT_TRUE(metadata->SaveProfile("A", domain::Profile{"A", "2:5015/1.1", "", ""}));
  file = uue.Assemble({found->parts[0].source}, false, "A");
  ASSERT_TRUE(file);
  {
    auto access = storage::JamAccess::Open(*catalog, "echo.one", true, service::RequestDeadline());
    ASSERT_TRUE(access);
    auto number = service::MessageNumber(**access, sent->id);
    ASSERT_TRUE(number);
    ASSERT_EQ((*access)->messages().DeleteMessage(*number), msgapi::JamError::kSuccess);
  }
  EXPECT_FALSE(uue.Chunk(file->id, 0, 10, "A"));
}

TEST_F(ServicesTest, UueVerifiedPartsSortDeduplicateAndRejectMixingAndHashMismatch) {
  service::UueService uue(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  const std::string bytes = "abc";
  const auto encoded = ftn::uue::Encode(bytes, "a.bin").value();
  const auto split = encoded.find('\n') + 1;
  ftn::uue::Metadata meta{
      std::string(32, 'a'), 1, 2, 3, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "a.bin"};
  auto append = [&](std::string body, ftn::uue::Metadata m, std::string from = "2:5015/1.1", std::string to = "") {
    auto access = storage::JamAccess::Open(*catalog, "echo.one", true, service::RequestDeadline()).value();
    msgapi::JamMessage message;
    message.SetSenderName("A");
    message.SetReceiverName("All");
    message.SetOriginAddress(from);
    message.SetDestAddress(to);
    message.SetSubject("file");
    message.SetMsgId(from + " serial" + std::to_string(access->messages().message_count()));
    message.SetText(body);
    message.AddRawSubField(msgapi::JamSubFieldType::kFtsKludge, ftn::uue::FormatMetadata(m).value());
    const auto number = access->messages().base_header().base_msg_num + access->messages().message_count();
    EXPECT_EQ(access->messages().AddMessage(message), msgapi::JamError::kSuccess);
    return service::UueReference{"echo.one", service::MessageId(*access, number), 0};
  };
  auto a = append(encoded.substr(0, split), meta);
  auto incomplete = uue.Assemble({a}, false, "A");
  ASSERT_TRUE(incomplete);
  EXPECT_EQ(incomplete->missing, (std::vector<uint32_t>{2}));
  meta.part = 2;
  auto b = append(encoded.substr(split), meta);
  auto full = uue.Assemble({b, a, b}, false, "A");
  ASSERT_TRUE(full);
  ASSERT_EQ(full->state, service::UueState::kReady);
  EXPECT_TRUE(full->verified);
  EXPECT_EQ(uue.Chunk(full->id, 0, 2, "A")->bytes, "ab");
  EXPECT_EQ(uue.Chunk(full->id, 2, 2, "A")->bytes, "c");
  auto corrupt = append(ftn::uue::Encode("xyz", "a.bin")->substr(split), meta);
  EXPECT_EQ(uue.Assemble({a, corrupt}, false, "A")->state, service::UueState::kCorrupt);
  EXPECT_EQ(uue.Assemble({a, b, corrupt}, false, "A")->state, service::UueState::kConflict);
  auto other_origin = append(encoded.substr(split), meta, "2:5015/1.2");
  EXPECT_FALSE(uue.Assemble({a, other_origin}, false, "A"));
  auto other_recipient = append(encoded.substr(split), meta, "2:5015/1.1", "2:9/9.1");
  EXPECT_FALSE(uue.Assemble({a, other_recipient}, false, "A"));
  meta.transfer_id = std::string(32, 'b');
  auto other_id = append(encoded.substr(split), meta);
  EXPECT_EQ(uue.Assemble({a, other_id}, false, "A")->state, service::UueState::kConflict);
}

TEST_F(ServicesTest, UueCacheExpiresAndCanBeRebuiltByAnotherClient) {
  auto now = std::chrono::steady_clock::now();
  auto policy = test::EchoAccess(*catalog, temp.path());
  service::UueService uue(catalog, metadata, policy, "cp866", [&] { return now; });
  auto request = Request("uue-expire");
  request.body = ftn::uue::Encode("payload", "a.bin").value();
  ASSERT_TRUE(messages->CreateMessage("echo.one", request, "A"));
  auto found = uue.Search("echo.one", "", 0, 100, "A");
  ASSERT_TRUE(found);
  auto file = uue.Assemble({found->parts[0].source}, false, "A");
  ASSERT_TRUE(file);
  now += std::chrono::minutes(6);
  EXPECT_FALSE(uue.Chunk(file->id, 0, 10, "A"));
  service::UueService laptop(catalog, metadata, policy);
  auto fresh = laptop.Search("echo.one", "", 0, 100, "A");
  ASSERT_TRUE(fresh);
  auto rebuilt = laptop.Assemble({fresh->parts[0].source}, false, "A");
  ASSERT_TRUE(rebuilt);
  EXPECT_EQ(laptop.Chunk(rebuilt->id, 0, 10, "A")->bytes, "payload");
}

TEST_F(ServicesTest, UueCacheHasPerUserQuota) {
  auto policy = test::EchoAccess(*catalog, temp.path());
  service::UueService uue(catalog, metadata, policy);
  for (int i = 0; i < 9; ++i) {
    auto request = Request("quota-" + std::to_string(i));
    // The FTN body limit is smaller than a 1 MiB decoded file. Use a single
    // 700 KiB decoded block so the real existing writer accepts this fixture.
    request.body = ftn::uue::Encode(std::string(700000, static_cast<char>('a' + i)), "file.bin").value();
    auto sent = messages->CreateMessage("echo.one", request, "A");
    ASSERT_TRUE(sent);
    auto file = uue.Assemble({{"echo.one", sent->id, 0}}, false, "A");
    ASSERT_TRUE(file);
    ASSERT_EQ(file->state, service::UueState::kReady);
  }
  for (int i = 9; i < 12; ++i) {
    auto request = Request("quota-" + std::to_string(i));
    request.body = ftn::uue::Encode(std::string(700000, static_cast<char>('a' + i)), "file.bin").value();
    auto sent = messages->CreateMessage("echo.one", request, "A");
    ASSERT_TRUE(sent);
    auto file = uue.Assemble({{"echo.one", sent->id, 0}}, false, "A");
    if (i == 11) {
      ASSERT_FALSE(file);
      EXPECT_EQ(file.error().code, domain::ErrorCode::kResource);
    } else {
      ASSERT_TRUE(file);
      EXPECT_EQ(file->state, service::UueState::kReady);
    }
  }
}

namespace {
std::string UueHash(const std::string& bytes) {
  auto hash = fidoback::service::Sha256(bytes).value();
  const char* hex = "0123456789abcdef";
  std::string value;
  for (auto byte : hash) {
    value += hex[byte >> 4];
    value += hex[byte & 15];
  }
  return value;
}
}  // namespace
TEST_F(ServicesTest, UueUploadBoundaryRepeatGapAndChecksumFailBeforeJamMutation) {
  service::UueService uue(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  std::string bytes(1048576, 'x');
  const auto hash = UueHash(bytes);
  for (size_t offset = 0; offset < bytes.size(); offset += 65536) {
    auto received = uue.Upload("upload", "file.bin", bytes.size(), hash, offset,
                               std::string_view(bytes).substr(offset, 65536), "A");
    ASSERT_TRUE(received);
    EXPECT_EQ(*received, offset + 65536);
  }
  EXPECT_EQ(
      uue.Upload("upload", "file.bin", bytes.size(), hash, 0, std::string_view(bytes).substr(0, 65536), "A").value(),
      bytes.size());
  EXPECT_FALSE(uue.Upload("upload", "file.bin", bytes.size(), hash, 0, "different", "A"));
  EXPECT_FALSE(uue.Upload("large", "file.bin", bytes.size() + 1, hash, 0, "", "A"));
  EXPECT_FALSE(uue.Upload("gap", "file.bin", 3, UueHash("abc"), 1, "a", "A"));
  EXPECT_FALSE(uue.Upload("hash", "file.bin", 3, UueHash("abc"), 0, "xyz", "A"));
  EXPECT_FALSE(uue.SendStatus("upload", "B"));
  EXPECT_EQ(messages->GetMessages("echo.one", {}, "oldest", "A")->total, 0);
}
TEST_F(ServicesTest, UueCommitPublishesRecoverableMultipartWithExactBytesAndIdempotency) {
  auto policy = test::EchoAccess(*catalog, temp.path());
  service::UueService uue(catalog, metadata, policy);
  std::string bytes;
  for (int i = 0; i < 50000; ++i)
    bytes += static_cast<char>(i);
  ASSERT_TRUE(uue.Upload("send-uue", "Н.bin", bytes.size(), UueHash(bytes), 0, bytes, "A"));
  auto request = Request("send-uue");
  request.body = "Н текст";
  auto sent = uue.Commit("echo.one", request, "A");
  ASSERT_TRUE(sent);
  ASSERT_EQ(sent->state, "completed");
  EXPECT_GT(sent->total, 1);
  EXPECT_EQ(sent->saved, sent->total);
  auto again = uue.Commit("echo.one", request, "A");
  ASSERT_TRUE(again);
  EXPECT_EQ(again->messages, sent->messages);
  request.body = "H текст";
  EXPECT_FALSE(uue.Commit("echo.one", request, "A"));
  auto found = uue.Search("echo.one", "", 0, 100, "A");
  ASSERT_TRUE(found);
  std::vector<service::UueReference> sources;
  for (const auto& part : found->parts)
    sources.push_back(part.source);
  auto file = uue.Assemble(sources, false, "A");
  ASSERT_TRUE(file);
  ASSERT_EQ(file->state, service::UueState::kReady);
  EXPECT_TRUE(file->verified);
  EXPECT_EQ(uue.Chunk(file->id, 0, 65536, "A")->bytes, bytes);
  auto first = messages->PeekMessage("echo.one", sent->messages[0], "A");
  ASSERT_TRUE(first);
  EXPECT_TRUE(first->body.starts_with("H текст\n"));
  EXPECT_TRUE(metadata->GetHistory("A")->empty());
}

namespace {
class UueFaultIo : public storage::JamIo {
public:
  int fail_write = 0, fail_sync = 0, writes = 0, syncs = 0;
  std::function<void()> after_first;
  ssize_t Write(int fd, const void* data, size_t size, off_t offset) override {
    if (++writes == fail_write) {
      errno = ENOSPC;
      return -1;
    }
    return JamIo::Write(fd, data, size, offset);
  }
  int Sync(int fd) override {
    if (++syncs == fail_sync) {
      errno = EIO;
      return -1;
    }
    auto result = JamIo::Sync(fd);
    if (syncs == 4 && after_first)
      after_first();
    return result;
  }
};
}  // namespace
TEST_F(ServicesTest, UueRestartAfterEachAppendStageAndLostReplyDoesNotDuplicate) {
  auto policy = test::EchoAccess(*catalog, temp.path());
  UueConfig config;
  config.part_body_bytes = 4096;
  config.max_file_bytes = 50000;
  for (bool sync_fault : {false, true}) {
    for (int stage = 1; stage <= 8; ++stage) {
      auto io = std::make_shared<UueFaultIo>();
      if (sync_fault)
        io->fail_sync = stage;
      else
        io->fail_write = stage;
      service::UueService interrupted(catalog, metadata, policy, "cp866", std::chrono::steady_clock::now, config, io);
      std::string bytes(10000, 'a');
      auto request = Request("fault-" + std::to_string(sync_fault) + "-" + std::to_string(stage));
      ASSERT_TRUE(interrupted.Upload(request.operation_id, "a.bin", bytes.size(), UueHash(bytes), 0, bytes, "A"));
      auto partial = interrupted.Commit("echo.one", request, "A");
      ASSERT_TRUE(partial);
      EXPECT_EQ(partial->state, "partial");
      EXPECT_LT(partial->saved, partial->total);
      service::UueService restarted(catalog, metadata, policy, "cp866", std::chrono::steady_clock::now, config);
      auto resumed = restarted.Commit("echo.one", request, "A");
      ASSERT_TRUE(resumed);
      ASSERT_EQ(resumed->state, "completed");
      ASSERT_EQ(resumed->saved, resumed->total);
      const auto total = messages->GetMessages("echo.one", {}, "oldest", "A")->total;
      // Treat the successful response as lost and repeat after another service restart.
      service::UueService laptop(catalog, metadata, policy, "cp866", std::chrono::steady_clock::now, config);
      auto repeated = laptop.Commit("echo.one", request, "A");
      ASSERT_TRUE(repeated);
      EXPECT_EQ(repeated->messages, resumed->messages);
      EXPECT_EQ(messages->GetMessages("echo.one", {}, "oldest", "A")->total, total);
    }
  }
}
TEST_F(ServicesTest, UueRevokedAccessStopsRemainingPartsAndKeepsConfirmedPart) {
  auto policy = test::EchoAccess(*catalog, temp.path());
  UueConfig config;
  config.part_body_bytes = 4096;
  config.max_file_bytes = 50000;
  auto io = std::make_shared<UueFaultIo>();
  io->after_first = [&] { EXPECT_TRUE(metadata->SaveProfile("A", {"A", "2:9/9.9", "", ""})); };
  service::UueService uue(catalog, metadata, policy, "cp866", std::chrono::steady_clock::now, config, io);
  const std::string bytes(10000, 'a');
  auto request = Request("revoked-uue");
  ASSERT_TRUE(uue.Upload(request.operation_id, "a.bin", bytes.size(), UueHash(bytes), 0, bytes, "A"));
  auto partial = uue.Commit("echo.one", request, "A");
  ASSERT_TRUE(partial);
  EXPECT_EQ(partial->state, "partial");
  EXPECT_EQ(partial->saved, 1);
  EXPECT_EQ(messages->GetMessages("echo.one", {}, "oldest", "B")->total, 1);
  EXPECT_EQ(uue.SendStatus(request.operation_id, "A")->saved, 1);
  EXPECT_EQ(uue.Commit("echo.one", request, "A")->state, "partial");
}

TEST_F(ServicesTest, UueBaseGenerationChangeStopsRemainingParts) {
  auto policy = test::EchoAccess(*catalog, temp.path());
  UueConfig config;
  config.part_body_bytes = 4096;
  config.max_file_bytes = 50000;
  auto io = std::make_shared<UueFaultIo>();
  io->after_first = [&] {
    const int fd = catalog->areas().at("echo.one").files->descriptors[0];
    std::array<uint8_t, 4> changed{};
    msgapi::jam_wire::Put32(changed.data(), 124);
    ASSERT_EQ(pwrite(fd, changed.data(), changed.size(), 4), 4);
  };
  service::UueService uue(catalog, metadata, policy, "cp866", std::chrono::steady_clock::now, config, io);
  const std::string bytes(10000, 'a');
  auto request = Request("generation-uue");
  ASSERT_TRUE(uue.Upload(request.operation_id, "a.bin", bytes.size(), UueHash(bytes), 0, bytes, "A"));
  auto partial = uue.Commit("echo.one", request, "A");
  ASSERT_TRUE(partial);
  EXPECT_EQ(partial->state, "partial");
  EXPECT_EQ(partial->saved, 1);
  EXPECT_EQ(messages->GetMessages("echo.one", {}, "oldest", "B")->total, 1);
  EXPECT_EQ(uue.Commit("echo.one", request, "A")->state, "partial");
}
TEST_F(ServicesTest, UueUsesHptCoordinationLockBeforePublishing) {
  const auto path = temp.path() / "hpt.lock";
  auto coordinator = storage::CoordinationLock::Open(path);
  ASSERT_TRUE(coordinator);
  std::vector<EchoAreaConfig> areas;
  for (const auto& [id, entry] : catalog->areas())
    areas.push_back(entry.config);
  messages.reset();
  conferences.reset();
  catalog.reset();
  auto opened = storage::JamCatalog::Build(temp.path(), areas, *coordinator);
  ASSERT_TRUE(opened);
  catalog = std::shared_ptr<storage::JamCatalog>(std::move(*opened));
  service::UueService uue(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  const std::string bytes(10000, 'a');
  auto request = Request("locked-uue");
  ASSERT_TRUE(uue.Upload(request.operation_id, "a.bin", bytes.size(), UueHash(bytes), 0, bytes, "A"));
  const int hpt = open(path.c_str(), O_RDWR);
  ASSERT_GE(hpt, 0);
  ASSERT_EQ(flock(hpt, LOCK_EX), 0);
  {
    service::RequestBudget budget{std::chrono::steady_clock::now() + std::chrono::milliseconds(20), {}};
    service::RequestScope scope(budget);
    EXPECT_FALSE(uue.Commit("echo.one", request, "A"));
  }
  close(hpt);
  EXPECT_EQ(uue.SendStatus(request.operation_id, "A")->state, "uploading");
  auto sent = uue.Commit("echo.one", request, "A");
  ASSERT_TRUE(sent);
  EXPECT_EQ(sent->state, "completed");
}

TEST_F(ServicesTest, UueDoesNotTurnEmptySubjectIntoOnlyPartNumbering) {
  service::UueService uue(catalog, metadata, test::EchoAccess(*catalog, temp.path()));
  ASSERT_TRUE(uue.Upload("empty-title", "a.bin", 3, UueHash("abc"), 0, "abc", "A"));
  auto request = Request("empty-title");
  request.subject.clear();
  EXPECT_FALSE(uue.Commit("echo.one", request, "A"));
  EXPECT_EQ(messages->GetMessages("echo.one", {}, "oldest", "A")->total, 0);
}
