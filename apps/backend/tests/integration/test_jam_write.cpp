#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>

#include "../support/temp_directory.hpp"
#include "JamMessageBase.h"

namespace fs = std::filesystem;
using namespace msgapi;

/// @brief Создаёт минимальную JAM-базу для тестов.
static void CreateTestJamBase(const fs::path& dir) {
  fs::create_directories(dir.parent_path());

  // .jhr — base header
  JamBaseHeader base_hdr{};
  base_hdr.signature = kJamSignature;
  base_hdr.date_created = static_cast<uint32_t>(std::time(nullptr));
  base_hdr.mod_counter = 0;
  base_hdr.active_msgs = 0;
  base_hdr.base_msg_num = 1;
  base_hdr.highwater = 0;

  {
    std::ofstream ofs(dir.string() + ".jhr", std::ios::binary);
    ofs.write(reinterpret_cast<const char*>(&base_hdr), sizeof(base_hdr));
  }

  // .jdt — пустой
  {
    std::ofstream ofs(dir.string() + ".jdt", std::ios::binary);
  }

  // .jdx — пустой
  {
    std::ofstream ofs(dir.string() + ".jdx", std::ios::binary);
  }

  // .jlr — пустой
  {
    std::ofstream ofs(dir.string() + ".jlr", std::ios::binary);
  }
}

class JamWriteIntegrationTest : public ::testing::Test {
protected:
  fidoback::test::TempDirectory temp_;
  fs::path test_dir_;

  void SetUp() override {
    test_dir_ = temp_.path() / "messages";
    CreateTestJamBase(test_dir_);
  }

  void TearDown() override {
    fs::remove_all(temp_.path());
    EXPECT_FALSE(fs::exists(temp_.path()));
  }
};

TEST_F(JamWriteIntegrationTest, WriteAndReadSingleMessage) {
  JamMessageBase jam_base(test_dir_.string());
  ASSERT_EQ(jam_base.Open(), JamError::kSuccess);

  JamMessage msg;
  msg.SetSubject("Test Subject");
  msg.SetSenderName("TestUser");
  msg.SetReceiverName("All");
  msg.SetText("Hello, this is a test message!");
  msg.SetOriginAddress("2:5015/0.0");
  msg.SetDestAddress("2:5015/1.0");
  msg.SetMsgId("<test123@fidoback>");
  msg.SetPid("FidoBack/1.0");
  msg.SetAttribute(JamMessageAttribute::kTypeEcho, true);
  msg.SetAttribute(JamMessageAttribute::kTypeLocal, true);

  auto err = jam_base.AddMessage(msg);
  ASSERT_EQ(err, JamError::kSuccess);

  // Перезапустить и прочитать
  jam_base.Close();

  JamMessageBase jam_base2(test_dir_.string());
  ASSERT_EQ(jam_base2.Open(), JamError::kSuccess);

  auto msg_nums = jam_base2.GetMessageNumbers();
  ASSERT_TRUE(msg_nums);
  ASSERT_EQ(msg_nums->size(), 1);

  auto read_msg = jam_base2.ReadMessage((*msg_nums)[0]);
  ASSERT_TRUE(read_msg);

  EXPECT_EQ(read_msg->subject(), "Test Subject");
  EXPECT_EQ(read_msg->sender_name(), "TestUser");
  EXPECT_EQ(read_msg->receiver_name(), "All");
  EXPECT_EQ(read_msg->text(), "Hello, this is a test message!");
  EXPECT_EQ(read_msg->GetSubFieldData(JamSubFieldType::kOAddress), "2:5015/0.0");
  EXPECT_EQ(read_msg->GetSubFieldData(JamSubFieldType::kDAddress), "2:5015/1.0");
  EXPECT_EQ(read_msg->GetSubFieldData(JamSubFieldType::kMsgId), "<test123@fidoback>");
  EXPECT_EQ(read_msg->GetSubFieldData(JamSubFieldType::kPid), "FidoBack/1.0");
  // NOTE: Attributes are written but not restored by ReadMessage()
  // (would need to parse JamMessageHeader.attribute during read)
}

TEST_F(JamWriteIntegrationTest, WriteMultipleMessages) {
  JamMessageBase jam_base(test_dir_.string());
  ASSERT_EQ(jam_base.Open(), JamError::kSuccess);

  for (int i = 0; i < 5; ++i) {
    JamMessage msg;
    msg.SetSubject("Message " + std::to_string(i));
    msg.SetSenderName("User" + std::to_string(i));
    msg.SetText("Body " + std::to_string(i));
    msg.SetOriginAddress("2:5015/0.0");

    auto err = jam_base.AddMessage(msg);
    ASSERT_EQ(err, JamError::kSuccess) << "Failed on message " << i;
  }

  jam_base.Close();

  // Перечитать
  JamMessageBase jam_base2(test_dir_.string());
  ASSERT_EQ(jam_base2.Open(), JamError::kSuccess);

  auto msg_nums = jam_base2.GetMessageNumbers();
  ASSERT_TRUE(msg_nums);
  ASSERT_EQ(msg_nums->size(), 5);

  for (int i = 0; i < 5; ++i) {
    auto msg = jam_base2.ReadMessage((*msg_nums)[i]);
    ASSERT_TRUE(msg);
    EXPECT_EQ(msg->subject(), "Message " + std::to_string(i));
    EXPECT_EQ(msg->text(), "Body " + std::to_string(i));
  }
}

TEST_F(JamWriteIntegrationTest, MessageCountAfterWrite) {
  JamMessageBase jam_base(test_dir_.string());
  ASSERT_EQ(jam_base.Open(), JamError::kSuccess);

  EXPECT_EQ(jam_base.message_count(), 0);

  JamMessage msg;
  msg.SetText("Test");
  msg.SetSenderName("Test");

  auto err = jam_base.AddMessage(msg);
  ASSERT_EQ(err, JamError::kSuccess);

  // In-memory кэш обновлён (баг #3 fix)
  EXPECT_EQ(jam_base.message_count(), 1);

  auto msg_nums = jam_base.GetMessageNumbers();
  ASSERT_TRUE(msg_nums);
  EXPECT_EQ(msg_nums->size(), 1);
}

TEST_F(JamWriteIntegrationTest, ReplyChainFields) {
  JamMessageBase jam_base(test_dir_.string());
  ASSERT_EQ(jam_base.Open(), JamError::kSuccess);

  // Первое сообщение (root)
  JamMessage root;
  root.SetSubject("Root");
  root.SetText("Root message");
  root.SetSenderName("User1");
  root.SetMsgId("<root@fidoback>");
  root.SetOriginAddress("2:5015/0.0");

  auto err1 = jam_base.AddMessage(root);
  ASSERT_EQ(err1, JamError::kSuccess);

  auto msg_nums = jam_base.GetMessageNumbers();
  ASSERT_TRUE(msg_nums);
  uint32_t root_num = (*msg_nums)[0];

  // Ответ (с reply_to)
  JamMessage reply;
  reply.SetSubject("Re: Root");
  reply.SetText("This is a reply");
  reply.SetSenderName("User2");
  reply.SetOriginAddress("2:5015/0.0");
  reply.SetReplyId("<root@fidoback>");
  reply.SetReplyTo(root_num);
  reply.SetPid("FidoBack/1.0");

  auto err2 = jam_base.AddMessage(reply);
  ASSERT_EQ(err2, JamError::kSuccess);

  // Перечитать и проверить
  jam_base.Close();
  JamMessageBase jam_base2(test_dir_.string());
  ASSERT_EQ(jam_base2.Open(), JamError::kSuccess);

  msg_nums = jam_base2.GetMessageNumbers();
  ASSERT_EQ(msg_nums->size(), 2);

  auto reply_msg = jam_base2.ReadMessage((*msg_nums)[1]);
  ASSERT_TRUE(reply_msg);
  EXPECT_EQ(reply_msg->GetSubFieldData(JamSubFieldType::kReplyId), "<root@fidoback>");
  // reply_to хранится в message header, не в subfields — проверяем что message создан
  EXPECT_EQ(reply_msg->subject(), "Re: Root");
}

TEST_F(JamWriteIntegrationTest, EmptyTextMessage) {
  JamMessageBase jam_base(test_dir_.string());
  ASSERT_EQ(jam_base.Open(), JamError::kSuccess);

  JamMessage msg;
  msg.SetSubject("No body");
  msg.SetSenderName("User");
  // text() пустой — баг #1 fix

  auto err = jam_base.AddMessage(msg);
  ASSERT_EQ(err, JamError::kSuccess);

  jam_base.Close();
  JamMessageBase jam_base2(test_dir_.string());
  ASSERT_EQ(jam_base2.Open(), JamError::kSuccess);

  auto msg_nums = jam_base2.GetMessageNumbers();
  ASSERT_EQ(msg_nums->size(), 1);

  auto read = jam_base2.ReadMessage((*msg_nums)[0]);
  ASSERT_TRUE(read);
  EXPECT_EQ(read->subject(), "No body");
  EXPECT_TRUE(read->text().empty());
}

TEST_F(JamWriteIntegrationTest, DeletedPhysicalSlotsKeepNumbersWithNonunitBase) {
  {
    std::fstream file(test_dir_.string() + ".jhr", std::ios::in | std::ios::out | std::ios::binary);
    uint32_t first = 42;
    file.seekp(20);
    file.write(reinterpret_cast<char*>(&first), sizeof(first));
  }
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  for (unsigned i = 0; i < 5; ++i) {
    JamMessage message;
    message.SetSubject(std::to_string(42 + i));
    ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
  }
  for (auto number : {42u, 44u, 46u})
    ASSERT_EQ(base.DeleteMessage(number), JamError::kSuccess);
  EXPECT_EQ(base.DeleteMessage(42), JamError::kMessageDeleted);
  EXPECT_EQ(base.message_count(), 2);
  base.Close();
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  auto numbers = base.GetMessageNumbers();
  ASSERT_TRUE(numbers);
  EXPECT_EQ(*numbers, (std::vector<uint32_t>{43, 45}));
  for (auto number : {43u, 45u}) {
    auto message = base.ReadMessage(number);
    ASSERT_TRUE(message);
    EXPECT_EQ(message->subject(), std::to_string(number));
  }
  EXPECT_EQ(base.ReadMessage(44).error(), JamError::kMessageDeleted);
  JamMessage last;
  last.SetSubject("47");
  ASSERT_EQ(base.AddMessage(last), JamError::kSuccess);
  base.Close();
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  numbers = base.GetMessageNumbers();
  ASSERT_TRUE(numbers);
  EXPECT_EQ(*numbers, (std::vector<uint32_t>{43, 45, 47}));
  EXPECT_EQ(base.ReadMessage(47)->subject(), "47");
  EXPECT_EQ(base.message_count(), 3);
}

TEST_F(JamWriteIntegrationTest, RejectsTruncatedIndexWithoutRepair) {
  {
    std::ofstream file(test_dir_.string() + ".jdx", std::ios::binary);
    file << "partial";
  }
  const auto before = fs::file_size(test_dir_.string() + ".jdx");
  JamMessageBase base(test_dir_.string());
  EXPECT_EQ(base.Open(), JamError::kCorruptedData);
  EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdx"), before);
  EXPECT_FALSE(base.is_open());
}

namespace {
void Patch32(const std::string& path, uint64_t offset, uint32_t value) {
  std::fstream file(path, std::ios::in | std::ios::out | std::ios::binary);
  std::array<uint8_t, 4> bytes{};
  jam_wire::Put32(bytes.data(), value);
  file.seekp(static_cast<std::streamoff>(offset));
  file.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
}
std::string Contents(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}
}  // namespace

TEST_F(JamWriteIntegrationTest, BoundedParserRejectsCorruptedHeadersAndOffsets) {
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetSubject("subject");
  message.SetText("body");
  ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
  base.Close();
  const auto original = Contents(test_dir_.string() + ".jhr");
  for (auto [offset, value] : std::vector<std::pair<uint64_t, uint32_t>>{{1024, 0},
                                                                         {1028, 2},
                                                                         {1032, UINT32_MAX},
                                                                         {1072, 99},
                                                                         {1084, UINT32_MAX},
                                                                         {1088, UINT32_MAX},
                                                                         {1024 + 76 + 4, UINT32_MAX}}) {
    SCOPED_TRACE(offset);
    {
      std::ofstream file(test_dir_.string() + ".jhr", std::ios::binary);
      file << original;
    }
    Patch32(test_dir_.string() + ".jhr", offset, value);
    const auto damaged = Contents(test_dir_.string() + ".jhr");
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    auto result = base.ReadMessage(1);
    EXPECT_FALSE(result);
    base.Close();
    EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), damaged);
  }
}

TEST_F(JamWriteIntegrationTest, TruncatedBaseAndMessageAndTextFailWithoutAllocation) {
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetText("body");
  ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
  base.Close();
  fs::resize_file(test_dir_.string() + ".jdt", 0);
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  EXPECT_FALSE(base.ReadMessage(1));
  base.Close();
  fs::resize_file(test_dir_.string() + ".jhr", 1040);
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  EXPECT_FALSE(base.ReadMessage(1));
  base.Close();
  fs::resize_file(test_dir_.string() + ".jhr", 1000);
  EXPECT_EQ(base.Open(), JamError::kCorruptedData);
}

TEST_F(JamWriteIntegrationTest, RejectsSparseOversizeAndNumberOverflowBeforeWrite) {
  Patch32(test_dir_.string() + ".jhr", 20, UINT32_MAX);
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetText("body");
  ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
  auto numbers = base.GetMessageNumbers();
  ASSERT_TRUE(numbers);
  EXPECT_EQ(*numbers, (std::vector<uint32_t>{UINT32_MAX}));
  const auto before = Contents(test_dir_.string() + ".jdt");
  EXPECT_EQ(base.AddMessage(message), JamError::kCorruptedData);
  EXPECT_EQ(Contents(test_dir_.string() + ".jdt"), before);
  base.Close();
  fs::resize_file(test_dir_.string() + ".jhr", uint64_t{UINT32_MAX} + 1);
  EXPECT_EQ(base.Open(), JamError::kCorruptedData);
  EXPECT_EQ(fs::file_size(test_dir_.string() + ".jhr"), uint64_t{UINT32_MAX} + 1);
}

TEST_F(JamWriteIntegrationTest, OversizedAppendLeavesAllFilesUntouched) {
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  const auto header = Contents(test_dir_.string() + ".jhr");
  JamMessage huge;
  huge.SetText(std::string(jam_wire::kMaxBody + 1, 'x'));
  EXPECT_EQ(base.AddMessage(huge), JamError::kCorruptedData);
  EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), header);
  EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdt"), 0);
  EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdx"), 0);
  JamMessage fields;
  fields.SetSubject(std::string(jam_wire::kMaxSubfields, 'x'));
  EXPECT_EQ(base.AddMessage(fields), JamError::kCorruptedData);
  EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), header);
}

TEST(JamWire, ExplicitLittleEndianAndJamCrcMatchSmapi) {
  JamMessageHeader header{};
  header.signature = kJamSignature;
  header.revision = 1;
  header.message_number = 0x01020304;
  header.attribute2 = 0xfedcba98;
  const auto bytes = jam_wire::Encode(header);
  EXPECT_EQ(bytes[48], 4);
  EXPECT_EQ(bytes[49], 3);
  EXPECT_EQ(bytes[50], 2);
  EXPECT_EQ(bytes[51], 1);
  EXPECT_EQ(jam_wire::Decode(bytes).attribute2, 0xfedcba98);
  EXPECT_EQ(JamCrc32("123456789"), 0x340bc6d9);
  EXPECT_EQ(JamCrc32(""), UINT32_MAX);
  EXPECT_EQ(JamCrc32("2:5020/1 ABcd"), JamCrc32("2:5020/1 abCD"));
}

TEST_F(JamWriteIntegrationTest, UnicodeCodecsAndHeaderMetadataRoundTrip) {
  for (auto encoding : {"UTF-8", "CP866"}) {
    CreateTestJamBase(test_dir_);
    JamMessageBase base(test_dir_.string(), encoding);
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    JamMessage message;
    message.SetSubject("Русское ё");
    message.SetSenderName("Автор");
    message.SetReceiverName("Читатель");
    message.SetText("Привет, мир!\r\nЁжик");
    message.SetDates(0, 123, 456);
    message.SetReplyLinks(7, 8, 9);
    message.SetAttribute(JamMessageAttribute::kTypeEcho, true);
    message.set_attributes2(0x12345678);
    message.AddRawSubField(JamSubFieldType::kFtsKludge, "FLAGS: DIR");
    message.AddRawSubField(JamSubFieldType::kUnknown, "future", 42);
    ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
    base.Close();
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    auto result = base.ReadMessage(1);
    ASSERT_TRUE(result);
    EXPECT_EQ(result->text(), message.text());
    EXPECT_EQ(result->subject(), message.subject());
    EXPECT_EQ(result->sender_name(), message.sender_name());
    EXPECT_EQ(result->receiver_name(), message.receiver_name());
    EXPECT_EQ(result->date_written(), 0);
    EXPECT_EQ(result->date_received(), 123);
    EXPECT_EQ(result->date_processed(), 456);
    EXPECT_EQ(result->reply_to(), 7);
    EXPECT_EQ(result->reply_first(), 8);
    EXPECT_EQ(result->reply_next(), 9);
    EXPECT_TRUE(result->GetAttribute(JamMessageAttribute::kTypeEcho));
    EXPECT_EQ(result->attributes2(), 0x12345678);
    EXPECT_EQ(result->GetSubFieldData(JamSubFieldType::kFtsKludge), "FLAGS: DIR");
    EXPECT_EQ(result->subfields()[4].high_id(), 42);
  }
}

TEST_F(JamWriteIntegrationTest, ExplicitChrsOverridesFallbackAndAbsentChrsUsesFallback) {
  JamMessageBase writer(test_dir_.string(), "UTF-8");
  ASSERT_EQ(writer.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetText("Русский текст");
  ASSERT_EQ(writer.AddMessage(message), JamError::kSuccess);
  writer.Close();
  JamMessageBase reader(test_dir_.string(), "CP866");
  ASSERT_EQ(reader.Open(), JamError::kSuccess);
  auto result = reader.ReadMessage(1);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->text(), message.text());
  reader.Close();
  auto cp866 = fidoback::storage::ConvertText(message.text(), "UTF-8", "CP866");
  ASSERT_TRUE(cp866);
  {
    std::ofstream text(test_dir_.string() + ".jdt", std::ios::binary);
    text << *cp866;
  }
  Patch32(test_dir_.string() + ".jhr", 1024 + 64, static_cast<uint32_t>(cp866->size()));
  Patch32(test_dir_.string() + ".jhr", 1024 + 8, 0);
  fs::resize_file(test_dir_.string() + ".jhr", 1024 + 76);
  ASSERT_EQ(reader.Open(), JamError::kSuccess);
  result = reader.ReadMessage(1);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->text(), message.text());
}

TEST_F(JamWriteIntegrationTest, InvalidOrConflictingEncodingDoesNotMutate) {
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  const auto before = Contents(test_dir_.string() + ".jhr");
  JamMessage invalid;
  invalid.SetText(std::string("\xff", 1));
  EXPECT_EQ(base.AddMessage(invalid), JamError::kCorruptedData);
  JamMessage conflicting;
  conflicting.AddRawSubField(JamSubFieldType::kFtsKludge, "CHRS: UTF-8 4");
  conflicting.AddRawSubField(JamSubFieldType::kFtsKludge, "CHRS: CP866 2");
  EXPECT_EQ(base.AddMessage(conflicting), JamError::kCorruptedData);
  JamMessage unknown;
  unknown.AddRawSubField(JamSubFieldType::kFtsKludge, "CHRS: not-an-encoding 2");
  EXPECT_EQ(base.AddMessage(unknown), JamError::kCorruptedData);
  EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), before);
  EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdt"), 0);
  EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdx"), 0);
}

TEST(TextCodec, PreviewKeepsWholeUnicodeCodepoints) {
  auto preview = fidoback::storage::Utf8Preview("АБ🌍В", 3);
  ASSERT_TRUE(preview);
  EXPECT_EQ(*preview, "АБ🌍");
  EXPECT_EQ(*fidoback::storage::Utf8Preview("Привет", 0), "");
  EXPECT_EQ(*fidoback::storage::Utf8Preview("Привет", 100), "Привет");
  EXPECT_FALSE(fidoback::storage::Utf8Preview(std::string("\xc0\x80", 2), 1));
  EXPECT_FALSE(fidoback::storage::ConvertText("x", "unknown", "UTF-8"));
}

TEST(TextCodec, ExpandedCp866PreviewAndNoLossyConversion) {
  const std::string cp866(600000, static_cast<char>(0x80));
  auto decoded = fidoback::storage::ConvertText(cp866, "CP866", "UTF-8");
  ASSERT_TRUE(decoded);
  EXPECT_EQ(decoded->size(), 1200000);
  auto preview = fidoback::storage::Utf8Preview(*decoded, 2);
  ASSERT_TRUE(preview);
  EXPECT_EQ(*preview, "АА");
  EXPECT_FALSE(fidoback::storage::ConvertText("🌍", "UTF-8", "CP866"));
  EXPECT_FALSE(fidoback::storage::ConvertText("🌍", "UTF-8", "CP866//TRANSLIT"));
}

TEST_F(JamWriteIntegrationTest, SmapiDeletedMarkersAndHeaderFlagsDoNotReuseSlots) {
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  for (uint32_t i = 1; i <= 5; ++i) {
    JamMessage message;
    message.SetSubject(std::to_string(i));
    message.SetText("preserved body");
    ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
  }
  base.Close();
  auto index = Contents(test_dir_.string() + ".jdx");
  for (uint32_t slot : {0u, 2u, 4u}) {
    const auto offset = jam_wire::Get32(reinterpret_cast<const uint8_t*>(index.data()) + slot * 8 + 4);
    Patch32(test_dir_.string() + ".jhr", offset + 52, 0x80000000);
    Patch32(test_dir_.string() + ".jhr", offset + 64, 0);
    Patch32(test_dir_.string() + ".jdx", slot * 8, UINT32_MAX);
    Patch32(test_dir_.string() + ".jdx", slot * 8 + 4, UINT32_MAX);
  }
  Patch32(test_dir_.string() + ".jhr", 12, 2);
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  auto numbers = base.GetMessageNumbers();
  ASSERT_TRUE(numbers);
  EXPECT_EQ(*numbers, (std::vector<uint32_t>{2, 4}));
  JamMessage appended;
  appended.SetSubject("six");
  ASSERT_EQ(base.AddMessage(appended), JamError::kSuccess);
  base.Close();
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  EXPECT_EQ(base.message_count(), 3);
  EXPECT_EQ(base.ReadMessage(2)->text(), "preserved body");
  EXPECT_EQ(base.ReadMessage(4)->subject(), "4");
  EXPECT_EQ(base.ReadMessage(6)->subject(), "six");
  ASSERT_EQ(base.DeleteMessage(6), JamError::kSuccess);
  base.Close();
  auto new_index = Contents(test_dir_.string() + ".jdx");
  auto headers = Contents(test_dir_.string() + ".jhr");
  EXPECT_EQ(jam_wire::Get32(reinterpret_cast<const uint8_t*>(new_index.data()) + 5 * 8), UINT32_MAX);
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  EXPECT_EQ(base.message_count(), 2);
  EXPECT_EQ(*base.GetMessageNumbers(), (std::vector<uint32_t>{2, 4}));
}

TEST_F(JamWriteIntegrationTest, MoveTransfersOwnershipAndReopenRefreshesSnapshot) {
  JamMessageBase original(test_dir_.string());
  ASSERT_EQ(original.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetText("one");
  ASSERT_EQ(original.AddMessage(message), JamError::kSuccess);
  JamMessageBase moved(std::move(original));
  EXPECT_TRUE(moved.ReadMessage(1));
  JamMessageBase assigned((temp_.path() / "missing").string());
  assigned = std::move(moved);
  EXPECT_TRUE(assigned.ReadMessage(1));
  auto* same = &assigned;
  assigned = std::move(*same);
  EXPECT_EQ(assigned.Open(), JamError::kSuccess);
  EXPECT_EQ(assigned.message_count(), 1);
  assigned.Close();
  EXPECT_FALSE(assigned.GetMessageNumbers());
  EXPECT_FALSE(assigned.ReadMessage(1));
  EXPECT_FALSE(assigned.PrepareAppend(message));
  EXPECT_EQ(assigned.DeleteMessage(1), JamError::kFileNotFound);
}

TEST_F(JamWriteIntegrationTest, LastReadRoundTripKeepsHighWaterAndCaseInsensitiveIdentity) {
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  auto missing = base.GetLastRead("Alice");
  ASSERT_TRUE(missing);
  EXPECT_EQ(*missing, 0);
  ASSERT_EQ(base.SetLastRead("Alice", 42), JamError::kSuccess);
  ASSERT_EQ(base.SetLastRead("Bob", 43), JamError::kSuccess);
  ASSERT_EQ(base.SetLastRead("ALICE", 21), JamError::kSuccess);
  auto alice = base.GetLastRead("alice");
  ASSERT_TRUE(alice);
  EXPECT_EQ(*alice, 21);
  base.Close();
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  EXPECT_EQ(*base.GetLastRead("Bob"), 43);
  std::ifstream input(test_dir_.string() + ".jlr", std::ios::binary);
  const std::string contents(std::istreambuf_iterator<char>(input), {});
  ASSERT_EQ(contents.size(), 32);
  EXPECT_EQ(jam_wire::Get32(reinterpret_cast<const uint8_t*>(contents.data()) + 12), 42);
  base.Close();
  fs::resize_file(test_dir_.string() + ".jlr", 17);
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  EXPECT_FALSE(base.GetLastRead("Alice"));
  EXPECT_EQ(base.SetLastRead("Alice", 99), JamError::kCorruptedData);
  base.Close();
  fs::remove(test_dir_.string() + ".jlr");
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  auto absent = base.GetLastRead("Alice");
  ASSERT_TRUE(absent);
  EXPECT_EQ(*absent, 0);
  EXPECT_NE(base.SetLastRead("Alice", 99), JamError::kSuccess);
}

TEST(TextCodec, LimitsAndEncodingNamesRejectBeforeConversion) {
  using fidoback::storage::ConvertText;
  using fidoback::storage::TextError;
  auto oversized = ConvertText(std::string(4 * 1024 * 1024 + 1, 'a'), "UTF-8", "UTF-8");
  ASSERT_FALSE(oversized);
  EXPECT_EQ(oversized.error(), TextError::kLimit);
  for (const auto& encoding : {std::string{}, std::string("UTF\0-8", 6), std::string(65, 'a'),
                               std::string("UTF-8//IGNORE"), std::string("absent-encoding")}) {
    EXPECT_FALSE(ConvertText("text", encoding, "UTF-8"));
    EXPECT_FALSE(ConvertText("text", "UTF-8", encoding));
  }
  const std::string large(8193, 'x');
  auto exact = ConvertText(large, "UTF-8", "UTF-8");
  ASSERT_TRUE(exact);
  EXPECT_EQ(*exact, large);
  auto expanded = ConvertText(std::string(3 * 1024 * 1024, '\x80'), "CP866", "UTF-8");
  ASSERT_FALSE(expanded);
  EXPECT_EQ(expanded.error(), TextError::kLimit);
}

namespace {
struct JamDescriptors {
  std::array<int, 3> values{};
  JamDescriptors(const fs::path& base, int readonly = -1) {
    for (size_t i = 0; i < values.size(); ++i) {
      values[i] = open((base.string() + std::array<const char*, 3>{".jhr", ".jdt", ".jdx"}[i]).c_str(),
                       static_cast<int>(i) == readonly ? O_RDONLY : O_RDWR);
      EXPECT_GE(values[i], 0);
    }
  }
  ~JamDescriptors() {
    for (int fd : values)
      close(fd);
  }
};
}  // namespace

TEST_F(JamWriteIntegrationTest, BorrowedReadOnlyCompanionsReportEveryAppendStageFailure) {
  for (int readonly : {1, 0, 2}) {
    CreateTestJamBase(test_dir_);
    JamDescriptors files(test_dir_, readonly);
    JamMessageBase base(files.values, "UTF-8");
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    JamMessage message;
    message.SetSubject("message");
    message.SetText("body");
    EXPECT_EQ(base.AddMessage(message), JamError::kWriteError);
  }
}

TEST_F(JamWriteIntegrationTest, ParserCancellationAndInvalidDescriptorsFailClosed) {
  JamMessageBase seed(test_dir_.string());
  ASSERT_EQ(seed.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetText("body");
  ASSERT_EQ(seed.AddMessage(message), JamError::kSuccess);
  seed.Close();
  JamDescriptors files(test_dir_);
  bool active = false;
  JamMessageBase cancelled(files.values, "UTF-8", [&] { return active; });
  EXPECT_EQ(cancelled.Open(), JamError::kReadError);
  EXPECT_GE(fcntl(files.values[0], F_GETFD), 0);
  active = true;
  JamMessageBase reader(files.values, "UTF-8", [&] { return active; });
  ASSERT_EQ(reader.Open(), JamError::kSuccess);
  active = false;
  EXPECT_FALSE(reader.ReadMessage(1));
  EXPECT_FALSE(reader.GetMessageNumbers());
  active = true;
  ASSERT_TRUE(reader.ReadMessage(1));
  JamMessageBase invalid(std::array<int, 3>{-1, files.values[1], files.values[2]}, "UTF-8");
  EXPECT_EQ(invalid.Open(), JamError::kFileNotFound);
}

TEST_F(JamWriteIntegrationTest, DeleteReportsReadOnlyHeaderAndIndexAndKeepsOldBody) {
  for (int readonly : {0, 2}) {
    CreateTestJamBase(test_dir_);
    JamMessageBase seed(test_dir_.string());
    ASSERT_EQ(seed.Open(), JamError::kSuccess);
    JamMessage message;
    message.SetText("old body");
    ASSERT_EQ(seed.AddMessage(message), JamError::kSuccess);
    seed.Close();
    JamDescriptors files(test_dir_, readonly);
    JamMessageBase base(files.values);
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    EXPECT_EQ(base.DeleteMessage(0), JamError::kInvalidMessageNumber);
    EXPECT_EQ(base.DeleteMessage(2), JamError::kInvalidMessageNumber);
    EXPECT_EQ(base.DeleteMessage(1), JamError::kWriteError);
    std::ifstream input(test_dir_.string() + ".jdt");
    EXPECT_EQ(std::string(std::istreambuf_iterator<char>(input), {}), "old body");
  }
}

namespace {
class ParserFaultIo : public JamFileIo {
public:
  int fail_read = 0, fail_write = 0, fail_stat = 0;
  int reads = 0, writes = 0, stats = 0;
  int changed_stat = 0;
  off_t changed_size = 0;
  bool interrupt_read = false, interrupt_write = false, short_io = false;
  ssize_t Read(int fd, void* bytes, size_t size, off_t offset) override {
    if (std::exchange(interrupt_read, false)) {
      errno = EINTR;
      return -1;
    }
    if (++reads == fail_read) {
      errno = EIO;
      return -1;
    }
    return JamFileIo::Read(fd, bytes, short_io ? std::min<size_t>(size, 7) : size, offset);
  }
  ssize_t Write(int fd, const void* bytes, size_t size, off_t offset) override {
    if (std::exchange(interrupt_write, false)) {
      errno = EINTR;
      return -1;
    }
    if (++writes == fail_write) {
      errno = ENOSPC;
      return -1;
    }
    return JamFileIo::Write(fd, bytes, short_io ? std::min<size_t>(size, 7) : size, offset);
  }
  int Stat(int fd, struct stat* info) override {
    if (++stats == fail_stat) {
      errno = EIO;
      return -1;
    }
    const int result = JamFileIo::Stat(fd, info);
    if (result == 0 && stats == changed_stat)
      info->st_size = changed_size;
    return result;
  }
};
}  // namespace

TEST_F(JamWriteIntegrationTest, ParserReadAndStatFailuresNeverReturnSuccessfulSnapshots) {
  JamMessageBase seed(test_dir_.string());
  ASSERT_EQ(seed.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetSubject("subject");
  message.SetText("body");
  ASSERT_EQ(seed.AddMessage(message), JamError::kSuccess);
  seed.Close();
  const auto header = Contents(test_dir_.string() + ".jhr");
  for (int read = 1; read <= 5; ++read) {
    SCOPED_TRACE(read);
    JamDescriptors files(test_dir_);
    ParserFaultIo io;
    io.fail_read = read;
    JamMessageBase base(files.values, "UTF-8", {}, &io);
    if (read <= 2)
      EXPECT_NE(base.Open(), JamError::kSuccess);
    else {
      ASSERT_EQ(base.Open(), JamError::kSuccess);
      EXPECT_FALSE(base.ReadMessage(1));
    }
    EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), header);
  }
  for (int stat = 1; stat <= 5; ++stat) {
    SCOPED_TRACE(stat);
    JamDescriptors files(test_dir_);
    ParserFaultIo io;
    io.fail_stat = stat;
    JamMessageBase base(files.values, "UTF-8", {}, &io);
    if (stat <= 2)
      EXPECT_NE(base.Open(), JamError::kSuccess);
    else {
      ASSERT_EQ(base.Open(), JamError::kSuccess);
      EXPECT_FALSE(base.ReadMessage(1));
    }
    EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), header);
  }
}

TEST_F(JamWriteIntegrationTest, AppendFaultsAtEveryWriteAndSizeReadNeverReportSuccess) {
  for (int write = 1; write <= 4; ++write) {
    CreateTestJamBase(test_dir_);
    JamDescriptors files(test_dir_);
    ParserFaultIo io;
    io.fail_write = write;
    JamMessageBase base(files.values, "UTF-8", {}, &io);
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    JamMessage message;
    message.SetText("body");
    EXPECT_EQ(base.AddMessage(message), JamError::kWriteError);
  }
  for (int stat = 1; stat <= 3; ++stat) {
    CreateTestJamBase(test_dir_);
    JamDescriptors files(test_dir_);
    ParserFaultIo io;
    JamMessageBase base(files.values, "UTF-8", {}, &io);
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    io.fail_stat = io.stats + stat;
    JamMessage message;
    message.SetText("body");
    EXPECT_FALSE(base.PrepareAppend(message));
    EXPECT_EQ(fs::file_size(test_dir_.string() + ".jhr"), 1024);
    EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdt"), 0);
    EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdx"), 0);
  }
}

TEST_F(JamWriteIntegrationTest, InterruptedAndShortParserIoCompletesExactRoundTrip) {
  JamDescriptors files(test_dir_);
  ParserFaultIo io;
  io.short_io = true;
  io.interrupt_read = io.interrupt_write = true;
  JamMessageBase base(files.values, "UTF-8", {}, &io);
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetSubject("Русское сообщение");
  message.SetText("Привет, мир!");
  ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
  auto read = base.ReadMessage(1);
  ASSERT_TRUE(read);
  EXPECT_EQ(read->text(), message.text());
  EXPECT_EQ(read->subject(), message.subject());
  EXPECT_GT(io.reads, 5);
  EXPECT_GT(io.writes, 4);
}

TEST(JamEncoding, KludgeLinesValidateChrsAndPreserveUnknownExtensions) {
  for (const auto& name : {std::string{}, std::string(65, 'x'), std::string("UTF\0-8", 6)}) {
    JamMessage message;
    message.AddRawSubField(JamSubFieldType::kFtsKludge, "CHRS: " + name + " 4");
    EXPECT_FALSE(MessageEncoding(message, "cp866"));
  }
  JamMessage valid;
  valid.SetAttribute(JamMessageAttribute::kTypeEcho, true);
  valid.SetAttribute(JamMessageAttribute::kTypeEcho, false);
  EXPECT_FALSE(valid.GetAttribute(JamMessageAttribute::kTypeEcho));
  valid.SetRawSubField(JamSubFieldType::kFtsKludge, "\1CHRS: UTF-8 4\r\n\1CHRS: UTF-8 4\nPID: test");
  valid.AddRawSubField(JamSubFieldType::kFtsKludge, "ignored", 1);
  auto encoding = MessageEncoding(valid, "cp866");
  ASSERT_TRUE(encoding);
  EXPECT_EQ(*encoding, "UTF-8");
  valid.SetRawSubField(JamSubFieldType::kFtsKludge, "");
  EXPECT_EQ(*MessageEncoding(valid, "cp866"), "cp866");
}

TEST_F(JamWriteIntegrationTest, MalformedSubfieldsAndInvalidUtf8AreRejectedWithoutMutation) {
  JamMessageBase base(test_dir_.string(), "UTF-8");
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetSubject("subject");
  message.SetText("body");
  ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
  base.Close();
  const auto original = Contents(test_dir_.string() + ".jhr");
  const auto body = Contents(test_dir_.string() + ".jdt");
  for (int damage = 0; damage < 3; ++damage) {
    {
      std::ofstream output(test_dir_.string() + ".jhr", std::ios::binary);
      output << original;
    }
    {
      std::ofstream output(test_dir_.string() + ".jdt", std::ios::binary);
      output << body;
    }
    if (damage == 0)
      Patch32(test_dir_.string() + ".jhr", 1032, 7);
    else if (damage == 1) {
      std::fstream output(test_dir_.string() + ".jhr", std::ios::in | std::ios::out | std::ios::binary);
      output.seekp(1024 + 76 + 8);
      output.put('\xff');
    } else {
      std::fstream output(test_dir_.string() + ".jdt", std::ios::in | std::ios::out | std::ios::binary);
      output.put('\xff');
    }
    const auto damaged = Contents(test_dir_.string() + ".jhr");
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    EXPECT_FALSE(base.ReadMessage(1));
    base.Close();
    EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), damaged);
  }
  {
    std::ofstream output(test_dir_.string() + ".jhr", std::ios::binary);
    output << original;
  }
  {
    std::ofstream output(test_dir_.string() + ".jdt", std::ios::binary);
    output << body;
  }
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  for (const auto type : {JamSubFieldType::kSubject, JamSubFieldType::kSenderName, JamSubFieldType::kReceiverName}) {
    JamMessage invalid;
    invalid.AddRawSubField(type, std::string(1, '\xff'));
    EXPECT_FALSE(base.PrepareAppend(invalid));
  }
  JamMessage huge_field;
  huge_field.AddRawSubField(JamSubFieldType::kPid, std::string(jam_wire::kMaxSubfields + 1, 'x'));
  EXPECT_FALSE(base.PrepareAppend(huge_field));
}

TEST_F(JamWriteIntegrationTest, IndexAndBaseInconsistencyNeverGetsRepairedByAppend) {
  JamMessageBase base(test_dir_.string());
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetText("body");
  ASSERT_EQ(base.AddMessage(message), JamError::kSuccess);
  base.Close();
  Patch32(test_dir_.string() + ".jhr", 12, 0);
  const auto before = Contents(test_dir_.string() + ".jhr");
  ASSERT_EQ(base.Open(), JamError::kSuccess);
  EXPECT_FALSE(base.GetMessageNumbers());
  EXPECT_FALSE(base.PrepareAppend(message));
  EXPECT_EQ(base.DeleteMessage(1), JamError::kCorruptedData);
  EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), before);
  base.Close();
  Patch32(test_dir_.string() + ".jhr", 12, 2);
  EXPECT_EQ(base.Open(), JamError::kCorruptedData);
  Patch32(test_dir_.string() + ".jhr", 12, 1);
  Patch32(test_dir_.string() + ".jhr", 20, 0);
  EXPECT_EQ(base.Open(), JamError::kCorruptedData);
  Patch32(test_dir_.string() + ".jhr", 20, UINT32_MAX);
  {
    std::ofstream output(test_dir_.string() + ".jdx", std::ios::app | std::ios::binary);
    output << std::string(8, '\0');
  }
  EXPECT_EQ(base.Open(), JamError::kCorruptedData);
}

TEST_F(JamWriteIntegrationTest, AppendRevalidatesFileSizesAndRejectsAllOverflowBoundaries) {
  for (const auto& [stat, size] : std::vector<std::pair<int, off_t>>{{3, -1},
                                                                     {3, UINT32_MAX},
                                                                     {3, UINT32_MAX - 1},
                                                                     {4, -1},
                                                                     {4, static_cast<off_t>(uint64_t{UINT32_MAX} + 1)},
                                                                     {4, UINT32_MAX},
                                                                     {5, -1},
                                                                     {5, 8}}) {
    SCOPED_TRACE(stat);
    SCOPED_TRACE(size);
    JamDescriptors files(test_dir_);
    ParserFaultIo io;
    JamMessageBase base(files.values, "UTF-8", {}, &io);
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    io.changed_stat = stat;
    io.changed_size = size;
    JamMessage message;
    message.SetText("body");
    EXPECT_FALSE(base.PrepareAppend(message));
    EXPECT_EQ(fs::file_size(test_dir_.string() + ".jhr"), 1024);
    EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdt"), 0);
    EXPECT_EQ(fs::file_size(test_dir_.string() + ".jdx"), 0);
  }
}

TEST_F(JamWriteIntegrationTest, ReadRejectsOversizedCompanionsAndIndexBeforeBaseHeader) {
  JamMessageBase seed(test_dir_.string());
  ASSERT_EQ(seed.Open(), JamError::kSuccess);
  JamMessage message;
  message.SetText("body");
  ASSERT_EQ(seed.AddMessage(message), JamError::kSuccess);
  seed.Close();
  for (int stat : {3, 4}) {
    JamDescriptors files(test_dir_);
    ParserFaultIo io;
    JamMessageBase base(files.values, "UTF-8", {}, &io);
    ASSERT_EQ(base.Open(), JamError::kSuccess);
    io.changed_stat = stat;
    io.changed_size = static_cast<off_t>(uint64_t{UINT32_MAX} + 1);
    EXPECT_FALSE(base.ReadMessage(1));
  }
  Patch32(test_dir_.string() + ".jdx", 4, 1023);
  ASSERT_EQ(seed.Open(), JamError::kSuccess);
  EXPECT_FALSE(seed.ReadMessage(1));
}

TEST_F(JamWriteIntegrationTest, MissingRequiredCompanionsAreRejectedIndividually) {
  for (const auto* missing : {".jhr", ".jdt", ".jdx"}) {
    CreateTestJamBase(test_dir_);
    fs::remove(test_dir_.string() + missing);
    JamMessageBase base(test_dir_.string());
    EXPECT_EQ(base.Open(), JamError::kFileNotFound);
  }
}

TEST_F(JamWriteIntegrationTest, LegacyIbmpcUsesConfiguredFallbackWithoutRewritingFiles) {
  JamMessageBase writer(test_dir_.string(), "CP866");
  ASSERT_EQ(writer.Open(), JamError::kSuccess);
  JamMessage input;
  input.SetText("Привет, мир");
  input.SetSubject("Тема");
  input.SetSenderName("Автор");
  ASSERT_EQ(writer.AddMessage(input), JamError::kSuccess);
  writer.Close();
  const auto path = test_dir_.string() + ".jhr";
  auto bytes = Contents(path);
  const auto offset = bytes.find("CHRS: CP866 2");
  ASSERT_NE(offset, std::string::npos);
  bytes.replace(offset, 13, "CHRS: IBMPC 2");
  std::ofstream(path, std::ios::binary | std::ios::trunc) << bytes;
  JamMessageBase reader(test_dir_.string(), "cp866");
  ASSERT_EQ(reader.Open(), JamError::kSuccess);
  auto message = reader.ReadMessage(1);
  ASSERT_TRUE(message);
  EXPECT_EQ(message->text(), input.text());
  EXPECT_EQ(message->subject(), input.subject());
  EXPECT_EQ(message->sender_name(), input.sender_name());
  EXPECT_EQ(Contents(path), bytes);
}
TEST(JamEncoding, LegacyIbmpcAndCharsetCaseAreResolvedBeforeConflictChecks) {
  JamMessage input;
  input.AddRawSubField(JamSubFieldType::kFtsKludge, "CHRS: ibmpc 2\rCHRS: CP866 2");
  EXPECT_EQ(*MessageEncoding(input, "cp866"), "CP866");
  input.AddRawSubField(JamSubFieldType::kFtsKludge, "CHRS: UTF-8 4");
  EXPECT_FALSE(MessageEncoding(input, "cp866"));
}

TEST_F(JamWriteIntegrationTest, Koi8BytesFallbackAndExplicitChrsDoNotRewriteHistory) {
  JamMessage input;
  input.SetText("Привет Ёё");
  input.SetSubject("Тема Ёё");
  input.SetSenderName("Автор Ёё");
  input.SetReceiverName("All");
  {
    JamMessageBase writer(test_dir_.string(), "KOI8-R");
    ASSERT_EQ(writer.Open(), JamError::kSuccess);
    ASSERT_EQ(writer.AddMessage(input), JamError::kSuccess);
  }
  EXPECT_EQ(Contents(test_dir_.string() + ".jdt"), "\xf0\xd2\xc9\xd7\xc5\xd4 \xb3\xa3");
  const auto original = Contents(test_dir_.string() + ".jhr");
  ASSERT_NE(original.find("CHRS: KOI8-R 2"), std::string::npos);
  ASSERT_NE(original.find("\xf4\xc5\xcd\xc1 \xb3\xa3"), std::string::npos);
  ASSERT_NE(original.find("\xe1\xd7\xd4\xcf\xd2 \xb3\xa3"), std::string::npos);
  for (const auto& chrs : {std::string("CHRS: KOI8-R 2"), std::string("CHRS: IBMPC 2 "), std::string(14, ' ')}) {
    auto header = original;
    header.replace(header.find("CHRS: KOI8-R 2"), 14, chrs);
    std::ofstream(test_dir_.string() + ".jhr", std::ios::binary | std::ios::trunc) << header;
    JamMessageBase reader(test_dir_.string(), "KOI8-R");
    ASSERT_EQ(reader.Open(), JamError::kSuccess);
    auto read = reader.ReadMessage(1);
    ASSERT_TRUE(read);
    EXPECT_EQ(read->text(), input.text());
    EXPECT_EQ(read->subject(), input.subject());
    EXPECT_EQ(read->sender_name(), input.sender_name());
    reader.Close();
    EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), header);
  }
}

TEST_F(JamWriteIntegrationTest, Koi8FallbackPreservesExplicitCp866AndUtf8) {
  for (const auto& encoding : {"CP866", "UTF-8"}) {
    JamMessageBase writer(test_dir_.string(), encoding);
    ASSERT_EQ(writer.Open(), JamError::kSuccess);
    JamMessage input;
    input.SetText("Привет Ёё");
    input.SetSubject("Тема Ёё");
    ASSERT_EQ(writer.AddMessage(input), JamError::kSuccess);
  }
  const auto header = Contents(test_dir_.string() + ".jhr");
  const auto body = Contents(test_dir_.string() + ".jdt");
  JamMessageBase reader(test_dir_.string(), "KOI8-R");
  ASSERT_EQ(reader.Open(), JamError::kSuccess);
  for (int number : {1, 2}) {
    auto message = reader.ReadMessage(number);
    ASSERT_TRUE(message);
    EXPECT_EQ(message->text(), "Привет Ёё");
    EXPECT_EQ(message->subject(), "Тема Ёё");
  }
  reader.Close();
  EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), header);
  EXPECT_EQ(Contents(test_dir_.string() + ".jdt"), body);
}

TEST_F(JamWriteIntegrationTest, ForcedKoi8ReadIgnoresStaleChrsWithoutRewriting) {
  JamMessage input;
  input.SetText("Привет Ёё");
  input.SetSubject("Тема Ёё");
  input.SetSenderName("Автор Ёё");
  input.SetReceiverName("Получатель");
  {
    JamMessageBase writer(test_dir_.string(), "KOI8-R");
    ASSERT_EQ(writer.Open(), JamError::kSuccess);
    ASSERT_EQ(writer.AddMessage(input), JamError::kSuccess);
  }
  auto header = Contents(test_dir_.string() + ".jhr");
  header.replace(header.find("CHRS: KOI8-R 2"), 14, "CHRS: CP866 2 ");
  std::ofstream(test_dir_.string() + ".jhr", std::ios::binary | std::ios::trunc) << header;
  const auto body = Contents(test_dir_.string() + ".jdt");
  const auto index = Contents(test_dir_.string() + ".jdx");
  {
    JamMessageBase ordinary(test_dir_.string(), "KOI8-R");
    ASSERT_EQ(ordinary.Open(), JamError::kSuccess);
    auto wrong = ordinary.ReadMessage(1);
    ASSERT_TRUE(wrong);
    EXPECT_NE(wrong->text(), input.text());
  }
  JamMessageBase forced(test_dir_.string(), "KOI8-R", true);
  ASSERT_EQ(forced.Open(), JamError::kSuccess);
  auto message = forced.ReadMessage(1);
  ASSERT_TRUE(message);
  EXPECT_EQ(message->text(), input.text());
  EXPECT_EQ(message->subject(), input.subject());
  EXPECT_EQ(message->sender_name(), input.sender_name());
  EXPECT_EQ(message->receiver_name(), input.receiver_name());
  forced.Close();
  EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), header);
  EXPECT_EQ(Contents(test_dir_.string() + ".jdt"), body);
  EXPECT_EQ(Contents(test_dir_.string() + ".jdx"), index);
}

TEST_F(JamWriteIntegrationTest, ForcedAppendReplacesOnlyChrsAndRejectsLoss) {
  JamMessage input;
  input.SetText("Привет Ёё");
  input.SetSubject("Тема Ёё");
  input.SetSenderName("Автор");
  input.SetReceiverName("Получатель");
  input.AddRawSubField(JamSubFieldType::kFtsKludge, "\1CHRS: UTF-8 4\r\nPID: Original\rCHRS: CP866 2\rTZUTC: 0300");
  input.AddRawSubField(JamSubFieldType::kFtsKludge, "CHRS: unknown 2");
  JamMessageBase forced(test_dir_.string(), "KOI8-R", true);
  ASSERT_EQ(forced.Open(), JamError::kSuccess);
  ASSERT_EQ(forced.AddMessage(input), JamError::kSuccess);
  const auto header = Contents(test_dir_.string() + ".jhr");
  EXPECT_NE(header.find("CHRS: KOI8-R 2"), std::string::npos);
  EXPECT_EQ(header.find("CHRS: CP866"), std::string::npos);
  EXPECT_EQ(header.find("CHRS: UTF-8"), std::string::npos);
  EXPECT_EQ(header.find("CHRS: unknown"), std::string::npos);
  EXPECT_NE(header.find("PID: Original"), std::string::npos);
  EXPECT_NE(header.find("TZUTC: 0300"), std::string::npos);
  const auto body = Contents(test_dir_.string() + ".jdt");
  EXPECT_EQ(body, "\xf0\xd2\xc9\xd7\xc5\xd4 \xb3\xa3");
  const auto index = Contents(test_dir_.string() + ".jdx");
  auto read = forced.ReadMessage(1);
  ASSERT_TRUE(read);
  EXPECT_EQ(read->subject(), input.subject());
  EXPECT_EQ(read->text(), input.text());
  auto moved = std::move(forced);
  input.SetText("😀");
  EXPECT_FALSE(moved.PrepareAppend(input));
  moved.Close();
  EXPECT_EQ(Contents(test_dir_.string() + ".jhr"), header);
  EXPECT_EQ(Contents(test_dir_.string() + ".jdt"), body);
  EXPECT_EQ(Contents(test_dir_.string() + ".jdx"), index);
}

TEST_F(JamWriteIntegrationTest, ForcedUtf8RemainsSeparateFromKoi8Default) {
  JamMessage input;
  input.SetText("Привет 😀");
  input.SetSubject("UTF-8 Ёё");
  input.AddRawSubField(JamSubFieldType::kFtsKludge, "CHRS: CP866 2");
  JamMessageBase forced(test_dir_.string(), "UTF-8", true);
  ASSERT_EQ(forced.Open(), JamError::kSuccess);
  ASSERT_EQ(forced.AddMessage(input), JamError::kSuccess);
  EXPECT_EQ(Contents(test_dir_.string() + ".jdt"), input.text());
  auto read = forced.ReadMessage(1);
  ASSERT_TRUE(read);
  EXPECT_EQ(read->text(), input.text());
  EXPECT_NE(Contents(test_dir_.string() + ".jhr").find("CHRS: UTF-8 4"), std::string::npos);
}

TEST_F(JamWriteIntegrationTest, ForcedAppendDoesNotMistakeOtherKludgeTextForChrs) {
  JamMessage input;
  input.SetText("Привет Ёё");
  input.SetSubject("Тема");
  input.AddRawSubField(JamSubFieldType::kFtsKludge, "PID: mentions CHRS: UTF-8 4");
  JamMessageBase forced(test_dir_.string(), "KOI8-R", true);
  ASSERT_EQ(forced.Open(), JamError::kSuccess);
  ASSERT_EQ(forced.AddMessage(input), JamError::kSuccess);
  const auto header = Contents(test_dir_.string() + ".jhr");
  EXPECT_NE(header.find("PID: mentions CHRS: UTF-8 4"), std::string::npos);
  EXPECT_NE(header.find("CHRS: KOI8-R 2"), std::string::npos);
  // An ordinary reader must decode the new record without relying on an override.
  forced.Close();
  JamMessageBase reader(test_dir_.string(), "CP866");
  ASSERT_EQ(reader.Open(), JamError::kSuccess);
  auto read = reader.ReadMessage(1);
  ASSERT_TRUE(read);
  EXPECT_EQ(read->text(), input.text());
  EXPECT_EQ(read->subject(), input.subject());
}
