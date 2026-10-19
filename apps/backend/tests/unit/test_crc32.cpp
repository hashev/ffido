#include <gtest/gtest.h>

#include "JamMessageBase.h"

using namespace msgapi;

TEST(Crc32, BasicCalculation) {
  // CRC32("") = 0 (initial 0xFFFFFFFF, inverted at end → ~0xFFFFFFFF = 0)
  EXPECT_EQ(Crc32(""), 0u);
  uint32_t crc = Crc32("hello");
  EXPECT_NE(crc, 0);
}

TEST(Crc32, SameInputSameOutput) {
  auto crc1 = Crc32("test");
  auto crc2 = Crc32("test");
  EXPECT_EQ(crc1, crc2);
}

TEST(Crc32, DifferentInputDifferentOutput) {
  auto crc1 = Crc32("hello");
  auto crc2 = Crc32("world");
  EXPECT_NE(crc1, crc2);
}

TEST(Crc32IgnoreCase, CaseInsensitive) {
  auto crc1 = Crc32IgnoreCase("Hello");
  auto crc2 = Crc32IgnoreCase("HELLO");
  EXPECT_EQ(crc1, crc2);
}

TEST(Crc32IgnoreCase, MixedCase) {
  auto crc1 = Crc32IgnoreCase("HeLLo WoRLd");
  auto crc2 = Crc32IgnoreCase("hello world");
  EXPECT_EQ(crc1, crc2);
}

TEST(Crc32IgnoreCase, EmptyString) {
  auto crc = Crc32IgnoreCase("");
  EXPECT_EQ(crc, ~0xFFFFFFFFu);  // ~0xFFFFFFFF = 0
}
