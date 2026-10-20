#include <gtest/gtest.h>

#include <algorithm>
#include <fstream>
#include <nlohmann/json.hpp>

#include "ftn/uue.hpp"
#include "ftn/uue_metadata.hpp"
#include "storage/text_codec.hpp"

using namespace fidoback::ftn;
namespace {
std::string Bytes(size_t count) {
  std::string out;
  for (size_t i = 0; i < count; ++i)
    out += static_cast<char>(i);
  return out;
}
}  // namespace
TEST(Uue, BinaryBoundariesRoundTrip) {
  for (size_t size : {0, 1, 2, 3, 44, 45, 46, 256, 1024 * 1024}) {
    const auto bytes = Bytes(size);
    auto encoded = uue::Encode(bytes, "payload.bin");
    ASSERT_TRUE(encoded) << size;
    auto decoded = uue::Decode(*encoded);
    ASSERT_TRUE(decoded) << size;
    EXPECT_EQ(*decoded, bytes);
    EXPECT_TRUE(encoded->starts_with("begin 644 payload.bin\n"));
    EXPECT_TRUE(encoded->ends_with("`\nend\n"));
  }
}
TEST(Uue, ZeroAlphabetsAndLineEndings) {
  auto encoded = uue::Encode(Bytes(256), "payload.bin");
  ASSERT_TRUE(encoded);
  for (const auto& newline : {"\n", "\r", "\r\n"}) {
    for (bool spaces : {false, true}) {
      std::string text;
      for (char c : *encoded) {
        if (c == '\n')
          text += newline;
        else
          text += spaces && c == '`' ? ' ' : c;
      }
      EXPECT_EQ(uue::Decode(text), (std::expected<std::string, uue::Error>(Bytes(256))));
    }
  }
}
TEST(Uue, ScanKeepsOffsetsAndDoesNotActivateQuotedBlocks) {
  auto first = uue::Encode(Bytes(30), "first.bin");
  auto second = uue::Encode("two", "second.bin");
  ASSERT_TRUE(first);
  ASSERT_TRUE(second);
  std::string text = "before\r\n> begin 644 quoted\r\n" + *first + "between\n" + *second + "after";
  auto found = uue::Scan(text);
  ASSERT_TRUE(found);
  ASSERT_EQ(found->size(), 2);
  EXPECT_EQ(found->at(0).filename, "first.bin");
  EXPECT_EQ(found->at(0).bytes, (std::expected<std::string, uue::Error>(Bytes(30))));
  EXPECT_EQ(text.substr(found->at(0).begin, found->at(0).end - found->at(0).begin), *first);
  EXPECT_EQ(text.substr(found->at(1).begin, found->at(1).end - found->at(1).begin), *second);
  // A 30-byte data line starts with '>', but is UUE, not a quote.
  EXPECT_EQ(first->at(first->find('\n') + 1), '>');
}
TEST(Uue, RejectsCorruptionInsteadOfRepairing) {
  for (auto text : {"begin 644 a\n!00``\nend\n", "begin 644 a\n!01``\n`\nend\n", "begin 644 a\n!00`\n`\nend\n",
                    "begin 644 a\n!~0``\n`\nend\n", "begin 644 a\nN0000\n`\nend\n", "begin 644 a\n`\nend\nextra\n",
                    "begin-base64 644 a\nQQ==\n====\n", "=ybegin name=a\n"}) {
    EXPECT_FALSE(uue::Decode(text)) << text;
  }
  EXPECT_EQ(uue::Decode("begin 644 a\n`\n").error(), uue::Error::kIncomplete);
  auto found = uue::Scan("begin 644 a\n!00\nend\nbegin 644 b\n`\nend\n");
  ASSERT_TRUE(found);
  ASSERT_EQ(found->size(), 2);
  EXPECT_FALSE(found->at(0).bytes);
  EXPECT_EQ(found->at(1).bytes.value(), "");
  EXPECT_TRUE(uue::Scan("begin-base64 644 a\nQQ==\n====\n")->empty());
}
TEST(Uue, BoundsInputOutputAndNumberOfBlocks) {
  const auto encoded = uue::Encode("abc", "a").value();
  EXPECT_EQ(uue::Encode("abc", "a", {.decoded_bytes = 2}).error(), uue::Error::kLimit);
  EXPECT_EQ(uue::Decode(encoded, {.decoded_bytes = 2}).error(), uue::Error::kLimit);
  EXPECT_EQ(uue::Scan(encoded + encoded, {.decoded_bytes = 5}).error(), uue::Error::kLimit);
  EXPECT_EQ(uue::Scan(encoded, {.decoded_bytes = 3, .input_bytes = 2}).error(), uue::Error::kLimit);
  EXPECT_EQ(uue::Scan(encoded + encoded, {.decoded_bytes = 6, .input_bytes = 100, .blocks = 1}).error(),
            uue::Error::kLimit);
  EXPECT_EQ(uue::Encode("abc", "a", {.decoded_bytes = 3, .input_bytes = encoded.size()})->size(), encoded.size());
  EXPECT_EQ(uue::Encode("abc", "a", {.decoded_bytes = 3, .input_bytes = encoded.size() - 1}).error(),
            uue::Error::kLimit);
  for (auto name : {"", "../a", "a/b", "a\\b", "a\nb", "a b"})
    EXPECT_FALSE(uue::Encode("", name));
}

TEST(Uue, LegacyMultipartAssemblyIsStrictAndOrdered) {
  const auto encoded = uue::Encode(Bytes(256), "all-bytes.bin").value();
  const size_t split = encoded.find('\n', encoded.find('\n') + 1) + 1;
  const auto a = encoded.substr(0, split);
  const auto b = encoded.substr(split);
  EXPECT_EQ(uue::Assemble({a, b}).value(), Bytes(256));
  EXPECT_EQ(uue::Assemble({a + "section 1 end\nignored tail\n", b}).value(), Bytes(256));
  EXPECT_EQ(uue::Assemble({a + "sum -r/size 123/45 section 1\nignored tail\n", b}).value(), Bytes(256));
  EXPECT_FALSE(uue::Assemble({a + "UNKNOWN SECTION\n", b}));
  EXPECT_FALSE(uue::Assemble({b, a}));
  EXPECT_FALSE(uue::Assemble({a}));
  EXPECT_FALSE(uue::Assemble({encoded, encoded}));
  EXPECT_EQ(uue::Assemble({a, b}, {.decoded_bytes = 255}).error(), uue::Error::kLimit);
}

TEST(Uue, IndependentGoldedCompatibleFixtures) {
  std::ifstream single(std::string(FFIDO_UUE_FIXTURES) + "/golded-single.uue", std::ios::binary);
  ASSERT_TRUE(single);
  std::string stream{std::istreambuf_iterator<char>(single), std::istreambuf_iterator<char>()};
  EXPECT_EQ(uue::Decode(stream).value(), Bytes(256));
  std::ifstream multipart(std::string(FFIDO_UUE_FIXTURES) + "/golded-multipart.json");
  ASSERT_TRUE(multipart);
  auto fixture = nlohmann::json::parse(multipart);
  std::vector<std::string> bodies;
  for (const auto& part : fixture.at("parts"))
    bodies.push_back(part.at("body").get<std::string>());
  std::vector<std::string_view> views;
  for (const auto& body : bodies)
    views.push_back(body);
  EXPECT_EQ(uue::Assemble(views).value(), Bytes(256));
}

namespace {
uue::Metadata Meta() {
  return {std::string(32, 'a'), 1, 2, 3, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          "Новый файл%.bin"};
}
}  // namespace
TEST(Uue, MetadataHasCanonicalAsciiAndSurvivesTextEncoding) {
  auto m = Meta();
  auto line = uue::FormatMetadata(m);
  ASSERT_TRUE(line);
  for (unsigned char c : *line) {
    EXPECT_GE(c, 32);
    EXPECT_LT(c, 127);
  }
  EXPECT_NE(line->find("%d0%9d"), std::string::npos);
  EXPECT_NE(line->find("%25"), std::string::npos);
  EXPECT_EQ(uue::ParseMetadata(*line).value(), m);
  auto cp866 = fidoback::storage::ConvertText(*line, "UTF-8", "CP866");
  ASSERT_TRUE(cp866);
  EXPECT_EQ(*cp866, *line);
  EXPECT_TRUE(uue::Verify("abc", m));
  EXPECT_FALSE(uue::Verify("abd", m));
  EXPECT_FALSE(uue::Verify("ab", m));
  // Replacing Cyrillic Н in textual fields cannot change this ASCII wire data.
  auto binary = Bytes(256);
  auto encoded = uue::Encode(binary, uue::SafeFilename(m.filename, true));
  ASSERT_TRUE(encoded);
  EXPECT_EQ(encoded->find("Н"), std::string::npos);
  EXPECT_EQ(uue::Decode(*encoded).value(), binary);
}
TEST(Uue, RejectsMalformedMetadataAndUnsafeFilenames) {
  auto m = Meta();
  for (int fault = 0; fault < 10; ++fault) {
    auto bad = m;
    switch (fault) {
      case 0:
        bad.transfer_id = "../id";
        break;
      case 1:
        bad.part = 0;
        break;
      case 2:
        bad.part = 3;
        break;
      case 3:
        bad.total = 129;
        break;
      case 4:
        bad.size = 1024 * 1024 + 1;
        break;
      case 5:
        bad.sha256[0] = 'G';
        break;
      case 6:
        bad.filename = "../private.bin";
        break;
      case 7:
        bad.filename = std::string(256, 'a');
        break;
      case 8:
        bad.filename = "a\rb";
        break;
      case 9:
        bad.filename = std::string(1, '\xff');
        break;
    }
    EXPECT_FALSE(uue::FormatMetadata(bad)) << fault;
  }
  auto line = uue::FormatMetadata(m).value();
  EXPECT_FALSE(uue::ParseMetadata(line + " extra"));
  EXPECT_FALSE(uue::ParseMetadata(line.substr(0, line.rfind(' ') + 1) + "%2fetc"));
  EXPECT_FALSE(uue::ParseMetadata(line.substr(0, line.rfind(' ') + 1) + "%61"));
  EXPECT_FALSE(uue::ParseMetadata(std::string(1025, 'a')));
  auto zero = m;
  zero.size = 0;
  zero.part = 1;
  zero.total = 1;
  EXPECT_TRUE(uue::ParseMetadata(uue::FormatMetadata(zero).value()));
  EXPECT_EQ(uue::SafeFilename("../../etc/passwd"), "passwd");
  EXPECT_EQ(uue::SafeFilename("C:\\secret\\a.bin"), "a.bin");
  EXPECT_EQ(uue::SafeFilename("CON.txt"), "_CON.txt");
  EXPECT_EQ(uue::SafeFilename(".."), "attachment.bin");
  EXPECT_EQ(uue::SafeFilename("a\nb"), "a_b");
  EXPECT_EQ(uue::SafeFilename("bad. "), "bad");
  EXPECT_LE(uue::SafeFilename(std::string(300, 'a')).size(), 200);
  std::string long_name;
  for (int i = 0; i < 120; ++i)
    long_name += "Н";
  EXPECT_TRUE(fidoback::storage::ConvertText(uue::SafeFilename(long_name), "UTF-8", "UTF-8"));
}

TEST(Uue, LegacyNumberingCannotProveTransferMembership) {
  const auto first_file = std::string(45, 'A') + std::string(45, 'B');
  const auto second_file = std::string(45, 'C') + std::string(45, 'D');
  const auto first = uue::Encode(first_file, "same.bin").value();
  const auto second = uue::Encode(second_file, "same.bin").value();
  const auto split_a = first.find('\n', first.find('\n') + 1) + 1;
  const auto split_b = second.find('\n', second.find('\n') + 1) + 1;
  // Both transmissions could have the same sender and subject [1/2], [2/2].
  // Only the first transmission's part 1 and the second one's part 2 arrived.
  auto mixed = uue::Assemble({std::string_view(first).substr(0, split_a), std::string_view(second).substr(split_b)});
  ASSERT_TRUE(mixed);
  EXPECT_NE(*mixed, first_file);
  EXPECT_NE(*mixed, second_file);
  EXPECT_EQ(*mixed, std::string(45, 'A') + std::string(45, 'D'));
}
