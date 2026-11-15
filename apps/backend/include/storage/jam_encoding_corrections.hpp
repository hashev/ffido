#pragma once

#include <cstdint>
#include <expected>
#include <istream>
#include <map>
#include <string>

namespace fidoback::storage {
struct JamEncodingCorrection {
  std::string raw_sha256;
  std::string expected_encoding;
  std::string encoding;
};

using JamEncodingCorrectionIndex = std::map<uint32_t, JamEncodingCorrection>;

struct JamEncodingCorrections {
  std::string source_sha256;
  uint64_t count = 0;
  std::map<std::string, JamEncodingCorrectionIndex, std::less<>> bases;
};

void NoteSkippedEncodingCorrection();
std::string CanonicalCorrectionEncoding(std::string encoding);
std::expected<JamEncodingCorrections, std::string> LoadJamEncodingCorrections(std::istream& input);
}  // namespace fidoback::storage
