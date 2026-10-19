#pragma once
#include "storage/jam_access.hpp"
#include "storage/metadata_store.hpp"
namespace fidoback::storage {
// Low-level boundary for meaningful short-write/ENOSPC/fsync fault injection.
class JamIo {
public:
  virtual ~JamIo() = default;
  virtual ssize_t Write(int fd, const void* data, size_t size, off_t offset);
  virtual ssize_t Read(int fd, void* data, size_t size, off_t offset);
  virtual int Stat(int fd, struct stat* info);
  virtual int Sync(int fd);
  virtual int Truncate(int fd, off_t size);
};
class JamWriter {
public:
  explicit JamWriter(std::shared_ptr<IMetadataStore> metadata, std::shared_ptr<JamIo> io = std::make_shared<JamIo>())
      : metadata_(std::move(metadata)), io_(std::move(io)) {
  }
  std::expected<void, domain::ApiError> Append(JamAccess& access, const Operation& operation);
  std::expected<void, domain::ApiError> Recover(const JamCatalog& catalog, const Operation& operation,
                                                JamDeadline deadline);
  std::expected<void, domain::ApiError> RecoverAll(const JamCatalog& catalog, JamDeadline deadline);

private:
  bool WriteAll(int fd, std::span<const uint8_t> bytes, uint64_t offset);
  bool Sync(int fd);
  std::expected<void, domain::ApiError> Quarantine(JamFiles& owner, const Operation& operation);
  std::shared_ptr<IMetadataStore> metadata_;
  std::shared_ptr<JamIo> io_;
};
}  // namespace fidoback::storage
