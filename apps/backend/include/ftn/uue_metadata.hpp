#pragma once

#include <cstdint>
#include <expected>
#include <string>
#include <string_view>

#include "ftn/uue.hpp"

namespace fidoback::ftn::uue {
struct Metadata {
  std::string transfer_id;
  uint32_t part = 0, total = 0;
  uint64_t size = 0;
  std::string sha256;
  std::string filename;
  bool operator==(const Metadata&) const = default;
};
// One ASCII FTN kludge, without SOH or newline. Filename is UTF-8 percent-encoded.
std::expected<std::string, Error> FormatMetadata(const Metadata& metadata, const Limits& limits = {});
std::expected<Metadata, Error> ParseMetadata(std::string_view line, const Limits& limits = {});
std::string SafeFilename(std::string_view filename, bool ascii = false);
std::expected<void, Error> Verify(std::string_view bytes, const Metadata& metadata);
}  // namespace fidoback::ftn::uue
