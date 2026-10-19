#pragma once
#include "storage/token_record.hpp"

namespace fidoback::storage {
enum class TransferState { kIntent = 0, kClaimed = 1, kCopied = 2, kBound = 3, kDone = 4, kQuarantine = 5 };
struct MailTransfer {
  std::string source_key, delivery_key, source_conference, source_generation, target_conference, target_operation;
  uint32_t source_number = 0, original_flags = 0;
  TokenDigest payload_hash{}, source_hash{};
  TransferState state = TransferState::kIntent;
  bool duplicate = false, collision = false;
};
}  // namespace fidoback::storage
