#pragma once
#include "JamMessageBase.h"
#include "storage/token_record.hpp"
namespace fidoback::storage {
enum class OperationState { kPending = 0, kCommitted = 1, kRolledBack = 2, kQuarantine = 3 };
struct Operation {
  std::string user, id, conference, generation, ftn_msgid;
  TokenDigest payload_hash{};
  msgapi::JamAppendPlan plan;
  int outbox_state = 0;
  int mail_direction = 0;  // 1 incoming, 2 outgoing, 3 transport; durable provenance, not wire flags.
  std::string recipient;
  OperationState state = OperationState::kPending;
};
}  // namespace fidoback::storage
