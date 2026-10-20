#pragma once
#include <cstdint>
#include <string>
namespace fidoback::storage {
struct UueUpload {
  std::string user, id, filename, sha256, data, manifest;
  uint64_t size = 0;
  int64_t revision = 0, updated_at = 0;
  std::string state = "uploading";
};
}  // namespace fidoback::storage
