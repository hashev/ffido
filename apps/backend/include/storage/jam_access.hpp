#pragma once
#include <variant>

#include "JamMessageBase.h"
#include "storage/coordination_lock.hpp"
#include "storage/jam_lock.hpp"

namespace fidoback::storage {
using JamAccessError = std::variant<CatalogError, JamLockError, CoordinationError, msgapi::JamError>;

// The lease owns open descriptors and the byte lock; borrowed views die first.
// All reads are refreshed only after obtaining the lock.
class JamAccess {
public:
  static std::expected<std::unique_ptr<JamAccess>, JamAccessError> Open(const JamCatalog& catalog,
                                                                        std::string_view conference, bool write,
                                                                        JamDeadline deadline,
                                                                        std::stop_token cancellation = {},
                                                                        std::string encoding = "cp866");
  msgapi::JamMessageBase& messages() {
    return messages_;
  }
  const std::string& generation() const {
    return generation_;
  }
  JamFiles& files() const {
    return lease_->files();
  }

private:
  JamAccess(std::unique_ptr<CoordinationLease> coordination, std::unique_ptr<JamLease> lease, std::string encoding,
            JamDeadline deadline, std::stop_token cancellation, bool force_encoding,
            std::shared_ptr<const JamEncodingCorrectionIndex> encoding_corrections)
      : coordination_(std::move(coordination)),
        lease_(std::move(lease)),
        messages_(
            lease_->files().descriptors, std::move(encoding),
            [deadline, cancellation] {
              return !cancellation.stop_requested() && std::chrono::steady_clock::now() < deadline;
            },
            nullptr, force_encoding, std::move(encoding_corrections)) {
  }
  std::unique_ptr<CoordinationLease> coordination_;
  std::unique_ptr<JamLease> lease_;
  msgapi::JamMessageBase messages_;
  std::string generation_;
};
}  // namespace fidoback::storage
