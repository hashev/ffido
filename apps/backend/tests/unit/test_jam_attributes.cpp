#include <gtest/gtest.h>

#include "../support/smapi_oracle.hpp"
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
