#include <gtest/gtest.h>

#include "../support/smapi_oracle.hpp"
#include "../support/temp_directory.hpp"
#include "JamMessageBase.h"

TEST(JamAttributes, EveryWireBitMatchesIndependentSmapiHeaders) {
  const auto reference = fidoback::test::SmapiOracle({"constants"});
  using A = msgapi::JamMessageAttribute;
  const std::pair<const char*, A> attributes[] = {{"Local", A::kLocal},
                                                  {"InTransit", A::kInTransit},
                                                  {"Private", A::kPrivate},
                                                  {"Read", A::kRead},
                                                  {"Sent", A::kSent},
                                                  {"KillSent", A::kKillSent},
                                                  {"ArchiveSent", A::kArchiveSent},
                                                  {"Hold", A::kHold},
                                                  {"Crash", A::kCrash},
                                                  {"Immediate", A::kImmediate},
                                                  {"Direct", A::kDirect},
                                                  {"Gate", A::kGate},
                                                  {"FileRequest", A::kFileRequest},
                                                  {"FileAttached", A::kFileAttached},
                                                  {"TruncFile", A::kTruncFile},
                                                  {"KillFile", A::kKillFile},
                                                  {"ReceiptRequest", A::kReceiptRequest},
                                                  {"ConfirmRequest", A::kConfirmRequest},
                                                  {"Orphan", A::kOrphan},
                                                  {"Encrypted", A::kEncrypted},
                                                  {"Compressed", A::kCompressed},
                                                  {"Escaped", A::kEscaped},
                                                  {"Fpu", A::kFpu},
                                                  {"TypeLocal", A::kTypeLocal},
                                                  {"TypeEcho", A::kTypeEcho},
                                                  {"TypeNet", A::kTypeNet},
                                                  {"NoDisplay", A::kNoDisplay},
                                                  {"Locked", A::kLocked},
                                                  {"Deleted", A::kDeleted}};
  ASSERT_EQ(reference.size(), std::size(attributes));
  for (const auto& [name, attribute] : attributes)
    EXPECT_EQ(static_cast<uint32_t>(attribute), reference.at(name).get<uint32_t>()) << name;
}

TEST(JamNumberRange, EmptyDeletedNonzeroBaseAndCorruptPrefix) {
  fidoback::test::TempDirectory temp;
  auto path = temp.path() / "range";
  msgapi::JamBaseHeader header{};
  header.signature = msgapi::kJamSignature;
  header.base_msg_num = 42;
  auto bytes = msgapi::jam_wire::Encode(header);
  {
    std::ofstream out(path.string() + ".jhr", std::ios::binary);
    out.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    std::ofstream(path.string() + ".jdx", std::ios::binary);
    std::ofstream(path.string() + ".jdt", std::ios::binary);
  }
  msgapi::JamMessageBase base(path.string());
  ASSERT_EQ(base.Open(), msgapi::JamError::kSuccess);
  EXPECT_EQ(base.MessageNumberRange(), (std::pair<uint64_t, uint64_t>{42, 42}));
  auto empty = base.NextMessageNumber(0);
  ASSERT_TRUE(empty);
  EXPECT_FALSE(*empty);
  for (int i = 0; i < 3; ++i) {
    msgapi::JamMessage message;
    message.SetText("x");
    ASSERT_EQ(base.AddMessage(message), msgapi::JamError::kSuccess);
  }
  ASSERT_EQ(base.DeleteMessage(43), msgapi::JamError::kSuccess);
  base.Close();
  // Any read at/below cursor 43 will fail; continuation must never touch it.
  {
    std::fstream out(path.string() + ".jhr", std::ios::in | std::ios::out | std::ios::binary);
    out.seekp(1024);
    out.write("BAD!", 4);
  }
  ASSERT_EQ(base.Open(), msgapi::JamError::kSuccess);
  auto next = base.NextMessageNumber(44);
  ASSERT_TRUE(next);
  ASSERT_TRUE(*next);
  EXPECT_EQ(**next, 44u);
  EXPECT_FALSE(base.NextMessageNumber(42));
  EXPECT_FALSE(*base.NextMessageNumber(45));
  EXPECT_FALSE(*base.NextMessageNumber(UINT64_MAX));
  EXPECT_EQ(base.message_count(), 2u);
  ASSERT_EQ(base.DeleteMessage(44), msgapi::JamError::kSuccess);
  EXPECT_FALSE(*base.NextMessageNumber(44));
  EXPECT_EQ(base.MessageNumberRange().second, 45u);  // Deleted last slot remains a valid cursor boundary.
  base.Close();
  // Boundary after UINT32_MAX is represented without wrapping.
  header.base_msg_num = UINT32_MAX;
  header.active_msgs = 1;
  bytes = msgapi::jam_wire::Encode(header);
  {
    std::ofstream out(path.string() + ".jhr", std::ios::binary);
    out.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    msgapi::JamMessageHeader record{};
    record.signature = msgapi::kJamSignature;
    record.revision = 1;
    record.message_number = UINT32_MAX;
    auto encoded = msgapi::jam_wire::Encode(record);
    out.write(reinterpret_cast<const char*>(encoded.data()), encoded.size());
    std::array<uint8_t, 8> index{};
    msgapi::jam_wire::Put32(index.data() + 4, 1024);
    std::ofstream idx(path.string() + ".jdx", std::ios::binary);
    idx.write(reinterpret_cast<const char*>(index.data()), index.size());
  }
  ASSERT_EQ(base.Open(), msgapi::JamError::kSuccess);
  EXPECT_EQ(base.MessageNumberRange().second, uint64_t{UINT32_MAX} + 1);
  EXPECT_EQ(**base.NextMessageNumber(UINT32_MAX), UINT32_MAX);
  EXPECT_FALSE(*base.NextMessageNumber(uint64_t{UINT32_MAX} + 1));
  base.Close();
  {
    std::ofstream idx(path.string() + ".jdx", std::ios::binary | std::ios::app);
    std::array<char, 8> extra{};
    idx.write(extra.data(), extra.size());
  }
  EXPECT_EQ(base.Open(), msgapi::JamError::kCorruptedData);
}
