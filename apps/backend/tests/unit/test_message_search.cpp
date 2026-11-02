#include <gtest/gtest.h>

#include "JamMessageBase.h"
#include "service/message_search.hpp"
using namespace fidoback;
TEST(MessageSearch, LiteralUnicodeOffsetsAndNonOverlappingRanges) {
  auto result = service::SearchRanges("😀 ПрИвЕт привет Ёж ёж .*[a]", "ПРИВЕТ", false, 6);
  ASSERT_TRUE(result);
  ASSERT_EQ(result->size(), 2);
  EXPECT_EQ(result->at(0).start_utf16, 3);
  EXPECT_EQ(result->at(0).length_utf16, 6);
  EXPECT_EQ(result->at(1).start_utf16, 10);
  EXPECT_EQ(service::SearchRanges("Ёж ёж", "ЁЖ", false, 5)->size(), 2);
  EXPECT_EQ(service::SearchRanges(".*[a]", ".*[a]", false, 6)->size(), 1);
  EXPECT_EQ(service::SearchRanges("aaaaa", "aa", false, 6)->size(), 2);
  EXPECT_TRUE(service::SearchRanges("É", "é", false, 6)->empty());
}
TEST(MessageSearch, Cp866PairsOnlyInEffectiveCp866) {
  for (const auto* alias : {"CP866", "866", "IBM866", "+7_FIDO"})
    EXPECT_TRUE(service::SearchCp866(alias));
  for (const auto* encoding : {"UTF-8", "KOI8-R"})
    EXPECT_FALSE(service::SearchCp866(encoding));
  EXPECT_EQ(service::SearchRanges("Hовый pУ HОВЫЙ Рy", "Новый", true, 6)->size(), 2);
  EXPECT_EQ(service::SearchRanges("рУ", "Py", true, 6)->size(), 1);
  EXPECT_TRUE(service::SearchRanges("Hовый", "Новый", false, 6)->empty());
  EXPECT_TRUE(service::SearchRanges("Привет", "", true, 6)->empty());
  EXPECT_FALSE(service::SearchRanges(std::string("\xff", 1), "x", false, 6));
}
TEST(MessageSearch, CancellationAndDeadlineInsideText) {
  std::stop_source stop;
  service::RequestBudget budget{std::chrono::steady_clock::now() + std::chrono::seconds(1), stop.get_token()};
  service::RequestScope scope(budget);
  stop.request_stop();
  auto cancelled = service::SearchRanges(std::string(10000, 'a'), "x", false, 6);
  ASSERT_FALSE(cancelled);
  EXPECT_EQ(cancelled.error().code, domain::ErrorCode::kCancelled);
  budget.cancellation = {};
  budget.deadline = std::chrono::steady_clock::now();
  auto expired = service::SearchRanges("x", "x", false, 6);
  ASSERT_FALSE(expired);
  EXPECT_EQ(expired.error().code, domain::ErrorCode::kDeadline);
}

TEST(MessageSearch, EffectiveEncodingUsesFallbackAliasesChrsAndOverride) {
  msgapi::JamMessage message;
  msgapi::JamMessageBase fallback("unused", "IBM866");
  EXPECT_TRUE(service::SearchCp866(*fallback.EffectiveEncoding(message)));
  message.SetRawSubField(msgapi::JamSubFieldType::kFtsKludge, "CHRS: UTF-8 4");
  EXPECT_EQ(*fallback.EffectiveEncoding(message), "UTF-8");
  msgapi::JamMessageBase forced("unused", "KOI8-R", true);
  EXPECT_EQ(*forced.EffectiveEncoding(message), "KOI8-R");
  message.SetRawSubField(msgapi::JamSubFieldType::kFtsKludge, "CHRS: CP866 2");
  EXPECT_FALSE(service::SearchCp866(*forced.EffectiveEncoding(message)));
  msgapi::JamMessageBase utf8("unused", "UTF-8", true);
  EXPECT_EQ(*utf8.EffectiveEncoding(message), "UTF-8");
}
