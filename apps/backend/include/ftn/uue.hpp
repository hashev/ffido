#pragma once

#include <cstddef>
#include <expected>
#include <string>
#include <string_view>
#include <vector>

namespace fidoback::ftn::uue {
enum class Error { kInvalid, kIncomplete, kLimit };
struct Limits {
  size_t decoded_bytes = 1024 * 1024;
  size_t input_bytes = 2 * 1024 * 1024;
  size_t blocks = 128;
};
struct Block {
  size_t begin = 0;
  size_t end = 0;  // Exclusive byte offset in the unchanged source text.
  std::string filename;
  std::expected<std::string, Error> bytes;
};
// The caller chooses a safe ASCII transfer name; this function rejects unsafe headers.
std::expected<std::string, Error> Encode(std::string_view bytes, std::string_view filename, const Limits& limits = {});
std::expected<std::string, Error> Decode(std::string_view block, const Limits& limits = {});
std::expected<std::vector<Block>, Error> Scan(std::string_view text, const Limits& limits = {});
// Ordered, already authorized message bodies. This does not infer membership or order.
std::expected<std::string, Error> Assemble(const std::vector<std::string_view>& parts, const Limits& limits = {});
}  // namespace fidoback::ftn::uue
