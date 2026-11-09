#include "storage/jam_encoding_corrections.hpp"

#include <spdlog/spdlog.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <bit>
#include <filesystem>
#include <nlohmann/json.hpp>
#include <set>
#include <string_view>

#include "storage/text_codec.hpp"

namespace fidoback::storage {
namespace {
constexpr size_t kMaxLine = 8192;
constexpr uint64_t kMaxEntries = 500000;
constexpr uint64_t kMaxBytes = 128 * 1024 * 1024;

bool IsSha256(std::string_view value) {
  return value.size() == 64 &&
         std::ranges::all_of(value, [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); });
}

bool IsBase(const std::string& name) {
  const std::filesystem::path path(name);
  return !name.empty() && name.size() <= 4096 && name.find('\0') == std::string::npos &&
         name.find("//") == std::string::npos && !path.is_absolute() && !path.filename().empty() &&
         path.generic_string() == name &&
         std::ranges::none_of(path, [](const auto& part) { return part == "." || part == ".." || part.empty(); });
}

nlohmann::json ParseLine(const char* data, size_t size) {
  bool duplicate = false;
  std::set<std::string> keys;
  auto parsed = nlohmann::json::parse(
      data, data + size,
      [&](int depth, nlohmann::json::parse_event_t event, const nlohmann::json& value) {
        if (event == nlohmann::json::parse_event_t::key && depth == 1)
          duplicate |= !keys.insert(value.get<std::string>()).second;
        return depth <= 1;
      },
      false);
  return duplicate ? nlohmann::json{} : std::move(parsed);
}

bool ValidEncoding(const std::string& encoding, std::set<std::string>& validated) {
  if (validated.contains(encoding))
    return true;
  if (validated.size() >= 128 || !ConvertText("", encoding, "UTF-8") || !ConvertText("", "UTF-8", encoding))
    return false;
  validated.insert(encoding);
  return true;
}
}  // namespace

void NoteSkippedEncodingCorrection() {
  static std::atomic<uint64_t> skips{0};
  const auto count = skips.fetch_add(1, std::memory_order_relaxed) + 1;
  if (std::has_single_bit(count))
    spdlog::warn(
        "Skipped {} JAM encoding correction attempts because the source did not match or could not be verified", count);
}

std::string CanonicalCorrectionEncoding(std::string encoding) {
  for (auto& c : encoding)
    if (c >= 'a' && c <= 'z')
      c -= 'a' - 'A';
  if (encoding == "IBM866" || encoding == "866")
    return "CP866";
  if (encoding == "LATIN-1" || encoding == "LATIN1" || encoding == "ISO8859-1")
    return "ISO-8859-1";
  return encoding;
}

std::expected<JamEncodingCorrections, std::string> LoadJamEncodingCorrections(std::istream& input) {
  JamEncodingCorrections result;
  std::set<std::string> encodings;
  std::array<char, kMaxLine + 1> buffer{};
  uint64_t bytes = 0;
  size_t line = 0;
  const auto invalid = [&](std::string_view reason) {
    return std::unexpected("manifest line " + std::to_string(line) + ": " + std::string(reason));
  };
  while (input.getline(buffer.data(), buffer.size())) {
    ++line;
    const auto read = static_cast<size_t>(input.gcount());
    bytes += read;
    if (bytes > kMaxBytes)
      return invalid("size limit exceeded");
    const auto value = ParseLine(buffer.data(), read - (input.eof() ? 0 : 1));
    if (!value.is_object())
      return invalid("expected a JSON object with unique keys");
    try {
      if (line == 1) {
        if (value.size() != 4 || value.at("kind") != "manifest" || !value.at("version").is_number_unsigned() ||
            value.at("version") != 1 || !value.at("count").is_number_unsigned())
          return invalid("invalid manifest header");
        result.source_sha256 = value.at("source_sha256").get<std::string>();
        result.count = value.at("count").get<uint64_t>();
        if (!IsSha256(result.source_sha256) || result.count > kMaxEntries)
          return invalid("invalid source digest or entry count");
        continue;
      }
      if (line - 1 > result.count || value.size() != 5 || !value.at("number").is_number_unsigned())
        return invalid("invalid entry or count");
      const auto base = value.at("base").get<std::string>();
      const auto number = value.at("number").get<uint64_t>();
      JamEncodingCorrection correction{value.at("raw_sha256").get<std::string>(),
                                       CanonicalCorrectionEncoding(value.at("expected_encoding").get<std::string>()),
                                       CanonicalCorrectionEncoding(value.at("encoding").get<std::string>())};
      if (!IsBase(base) || number == 0 || number > UINT32_MAX || !IsSha256(correction.raw_sha256) ||
          correction.expected_encoding == correction.encoding ||
          !ValidEncoding(correction.expected_encoding, encodings) || !ValidEncoding(correction.encoding, encodings))
        return invalid("invalid path, number, digest or encoding");
      if (!result.bases[base].try_emplace(static_cast<uint32_t>(number), std::move(correction)).second)
        return invalid("duplicate base and message number");
    } catch (const nlohmann::json::exception&) {
      return invalid("missing field or invalid field type");
    }
  }
  if (input.bad() || !input.eof() || line == 0 || line - 1 != result.count)
    return invalid("incomplete input, count mismatch or line too long");
  return result;
}
}  // namespace fidoback::storage
