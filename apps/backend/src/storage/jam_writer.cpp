#include "storage/jam_writer.hpp"

#include <algorithm>
#include <cerrno>

namespace fidoback::storage {
ssize_t JamIo::Write(int fd, const void* data, size_t size, off_t offset) {
  return pwrite(fd, data, size, offset);
}
ssize_t JamIo::Read(int fd, void* data, size_t size, off_t offset) {
  return pread(fd, data, size, offset);
}
int JamIo::Stat(int fd, struct stat* info) {
  return fstat(fd, info);
}
int JamIo::Sync(int fd) {
  return fsync(fd);
}
int JamIo::Truncate(int fd, off_t size) {
  return ftruncate(fd, size);
}
namespace {
domain::ApiError Failure() {
  return domain::ApiError::Server("Message commit requires recovery");
}
std::span<const uint8_t> Text(const std::string& text) {
  return {reinterpret_cast<const uint8_t*>(text.data()), text.size()};
}
bool ReadAll(JamIo& io, int fd, std::span<uint8_t> bytes, uint64_t offset) {
  while (!bytes.empty()) {
    auto count = io.Read(fd, bytes.data(), bytes.size(), static_cast<off_t>(offset));
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return false;
    bytes = bytes.subspan(count);
    offset += count;
  }
  return true;
}
bool KnownBase(const std::array<uint8_t, 1024>& actual, const msgapi::JamAppendPlan& plan) {
  // A partial positional write can contain a prefix of the new base header.
  for (size_t split = 0; split <= actual.size(); ++split)
    if (std::equal(actual.begin(), actual.begin() + split, plan.published_base.begin()) &&
        std::equal(actual.begin() + split, actual.end(), plan.original_base.begin() + split))
      return true;
  return false;
}
}  // namespace
bool JamWriter::WriteAll(int fd, std::span<const uint8_t> bytes, uint64_t offset) {
  while (!bytes.empty()) {
    auto count = io_->Write(fd, bytes.data(), bytes.size(), static_cast<off_t>(offset));
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0 || static_cast<size_t>(count) > bytes.size())
      return false;
    bytes = bytes.subspan(count);
    offset += count;
  }
  return true;
}
bool JamWriter::Sync(int fd) {
  int rc;
  do {
    rc = io_->Sync(fd);
  } while (rc < 0 && errno == EINTR);
  return rc == 0;
}
std::expected<void, domain::ApiError> JamWriter::Append(JamAccess& access, const Operation& operation) {
  auto& owner = access.files();
  if (owner.needs_recovery || !owner.writable || operation.generation != access.generation())
    return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "Message base requires recovery", {}});
  auto intent = metadata_->PrepareOperation(operation);
  if (!intent)
    return intent;
  owner.needs_recovery = true;
  const auto& plan = operation.plan;
  const auto& fd = owner.descriptors;
  // Once intent is durable, finish the bounded commit even if the caller disconnects.
  if (!WriteAll(fd[1], Text(plan.text), plan.original_sizes[1]) || !Sync(fd[1]) ||
      !WriteAll(fd[0], plan.header, plan.original_sizes[0]) || !Sync(fd[0]) ||
      !WriteAll(fd[2], plan.index, plan.original_sizes[2]) || !Sync(fd[2]) ||
      !WriteAll(fd[0], plan.published_base, 0) || !Sync(fd[0]))
    return std::unexpected(Failure());
  auto committed = metadata_->SetOperationState(operation.user, operation.id, OperationState::kCommitted);
  if (!committed)
    return committed;
  owner.needs_recovery = false;
  return {};
}
std::expected<void, domain::ApiError> JamWriter::Quarantine(JamFiles& owner, const Operation& operation) {
  owner.needs_recovery = true;
  owner.writable = false;
  auto saved = metadata_->SetOperationState(operation.user, operation.id, OperationState::kQuarantine);
  if (!saved)
    return saved;
  return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "Message base is quarantined", {}});
}
std::expected<void, domain::ApiError> JamWriter::Recover(const JamCatalog& catalog, const Operation& snapshot,
                                                         JamDeadline deadline) {
  std::unique_ptr<CoordinationLease> coordination;
  if (catalog.coordination()) {
    auto acquired = catalog.coordination()->Shared(deadline);
    if (!acquired)
      return std::unexpected(Failure());
    coordination = std::move(*acquired);
  }
  auto area = catalog.Resolve(snapshot.conference);
  if (!area) {
    auto entry = catalog.areas().find(snapshot.conference);
    if (entry != catalog.areas().end())
      return Quarantine(*entry->second.files, snapshot);
    auto saved = metadata_->SetOperationState(snapshot.user, snapshot.id, OperationState::kQuarantine);
    if (!saved)
      return saved;
    return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "Message base identity changed", {}});
  }
  auto& owner = *(*area)->files;
  if (snapshot.state != OperationState::kPending && snapshot.state != OperationState::kQuarantine)
    return {};
  if (snapshot.state == OperationState::kQuarantine) {
    owner.needs_recovery = true;
    owner.writable = false;
    return std::unexpected(domain::ApiError{domain::ErrorCode::kPrecondition, "Message base is quarantined", {}});
  }
  auto lease = JamLease::Acquire((*area)->files, true, deadline);
  if (!lease)
    return std::unexpected(Failure());
  area = catalog.Resolve(snapshot.conference);
  if (!area)
    return Quarantine(owner, snapshot);
  auto latest = metadata_->FindOperation(snapshot.user, snapshot.id);
  if (!latest || !*latest)
    return std::unexpected(Failure());
  if ((*latest)->state == OperationState::kCommitted || (*latest)->state == OperationState::kRolledBack)
    return {};
  const auto& operation = **latest;
  owner.needs_recovery = true;
  if (operation.state == OperationState::kQuarantine)
    return Quarantine(owner, operation);
  const auto& fd = owner.descriptors;
  const auto& plan = operation.plan;
  std::array<uint8_t, 1024> base{};
  if (!ReadAll(*io_, fd[0], base, 0))
    return std::unexpected(Failure());
  const auto& identity = owner.identities[0];
  const auto before = msgapi::jam_wire::Decode(plan.original_base);
  const auto generation = std::to_string(identity.st_dev) + ":" + std::to_string(identity.st_ino) + ":" +
                          std::to_string(before.date_created) + ":" + std::to_string(before.base_msg_num);
  if (generation != operation.generation || !KnownBase(base, plan))
    return Quarantine(owner, operation);
  const std::array<std::span<const uint8_t>, 3> tails{plan.header, Text(plan.text), plan.index};
  bool complete = true;
  for (size_t i = 0; i < fd.size(); ++i) {
    struct stat info{};
    if (io_->Stat(fd[i], &info) != 0 || info.st_size < 0)
      return std::unexpected(Failure());
    const auto size = static_cast<uint64_t>(info.st_size), original = plan.original_sizes[i],
               target = original + tails[i].size();
    if (size < original || size > target || target > UINT32_MAX)
      return Quarantine(owner, operation);
    std::vector<uint8_t> actual(static_cast<size_t>(size - original));
    if (!ReadAll(*io_, fd[i], actual, original))
      return std::unexpected(Failure());
    if (!std::equal(actual.begin(), actual.end(), tails[i].begin()))
      return Quarantine(owner, operation);
    complete = complete && size == target;
  }
  if (complete) {
    // Re-sync all append files before publishing or confirming a prior uncertain fsync.
    if (!Sync(fd[1]) || !Sync(fd[0]) || !Sync(fd[2]) || !WriteAll(fd[0], plan.published_base, 0) || !Sync(fd[0]))
      return std::unexpected(Failure());
  } else {
    // Every surviving suffix was proved to be our own exact prefix; foreign data is never truncated.
    if (!WriteAll(fd[0], plan.original_base, 0) || !Sync(fd[0]))
      return std::unexpected(Failure());
    for (size_t i : {size_t(2), size_t(0), size_t(1)}) {
      int rc;
      do {
        rc = io_->Truncate(fd[i], static_cast<off_t>(plan.original_sizes[i]));
      } while (rc < 0 && errno == EINTR);
      if (rc < 0 || !Sync(fd[i]))
        return std::unexpected(Failure());
    }
  }
  auto finished = metadata_->SetOperationState(operation.user, operation.id,
                                               complete ? OperationState::kCommitted : OperationState::kRolledBack);
  if (!finished)
    return finished;
  owner.needs_recovery = false;
  return {};
}
std::expected<void, domain::ApiError> JamWriter::RecoverAll(const JamCatalog& catalog, JamDeadline deadline) {
  auto pending = metadata_->PendingOperations();
  if (!pending)
    return std::unexpected(pending.error());
  std::optional<domain::ApiError> failure;
  for (const auto& operation : *pending) {
    auto result = Recover(catalog, operation, deadline);
    if (!result && !failure)
      failure = result.error();
  }
  if (failure)
    return std::unexpected(*failure);
  return {};
}
}  // namespace fidoback::storage
