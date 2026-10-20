#include "ftn/uue.hpp"

#include <algorithm>
#include <optional>
#include <regex>

namespace fidoback::ftn::uue {
namespace {
struct Line {
  std::string_view text;
  size_t begin;
  size_t end;
};
Line Next(std::string_view source, size_t offset) {
  size_t end = source.find_first_of("\r\n", offset);
  if (end == std::string_view::npos)
    return {source.substr(offset), offset, source.size()};
  size_t after = end + 1;
  if (source[end] == '\r' && after < source.size() && source[after] == '\n')
    ++after;
  return {source.substr(offset, end - offset), offset, after};
}
std::optional<std::string_view> Header(std::string_view line) {
  if (!line.starts_with("begin "))
    return {};
  line.remove_prefix(6);
  const auto space = line.find(' ');
  if (space != 3 && space != 4)
    return {};
  for (char c : line.substr(0, space))
    if (c < '0' || c > '7')
      return {};
  line.remove_prefix(space + 1);
  if (line.empty() || line.size() > 255)
    return {};
  for (unsigned char c : line)
    if (c < 32 || c == 127)
      return {};
  return line;
}
int Six(unsigned char c) {
  if (c < 32 || c > 96)
    return -1;
  return (c - 32) & 63;
}
char Enc(unsigned n) {
  return n ? static_cast<char>(n + 32) : '`';
}
std::expected<bool, Error> Data(std::string_view line, std::string& out, size_t max) {
  if (line.empty())
    return std::unexpected(Error::kInvalid);
  const int n = Six(static_cast<unsigned char>(line[0]));
  if (n < 0 || n > 45 || line.size() != 1 + 4 * ((static_cast<size_t>(n) + 2) / 3))
    return std::unexpected(Error::kInvalid);
  if (static_cast<size_t>(n) > max - out.size())
    return std::unexpected(Error::kLimit);
  if (n == 0)
    return true;
  for (size_t i = 1, remaining = static_cast<size_t>(n); i < line.size(); i += 4) {
    int a = Six(static_cast<unsigned char>(line[i]));
    int b = Six(static_cast<unsigned char>(line[i + 1]));
    int c = Six(static_cast<unsigned char>(line[i + 2]));
    int d = Six(static_cast<unsigned char>(line[i + 3]));
    if (a < 0 || b < 0 || c < 0 || d < 0)
      return std::unexpected(Error::kInvalid);
    if ((remaining == 1 && ((b & 15) || c || d)) || (remaining == 2 && ((c & 3) || d)))
      return std::unexpected(Error::kInvalid);
    out += static_cast<char>((a << 2) | (b >> 4));
    if (remaining > 1)
      out += static_cast<char>((b << 4) | (c >> 2));
    if (remaining > 2)
      out += static_cast<char>((c << 6) | d);
    remaining -= std::min(remaining, size_t{3});
  }
  return false;
}
}  // namespace

std::expected<std::string, Error> Encode(std::string_view bytes, std::string_view filename, const Limits& limits) {
  if (bytes.size() > limits.decoded_bytes)
    return std::unexpected(Error::kLimit);
  if (filename.empty() || filename.size() > 255 || filename == "." || filename == "..")
    return std::unexpected(Error::kInvalid);
  for (unsigned char c : filename)
    if (c < 33 || c > 126 || c == '/' || c == '\\')
      return std::unexpected(Error::kInvalid);
  // Check the exact size before constructing output (including an empty-file block).
  const size_t rows = bytes.size() / 45;
  const size_t tail = bytes.size() % 45;
  if (rows > limits.input_bytes / 62)
    return std::unexpected(Error::kLimit);
  const size_t size = 17 + filename.size() + rows * 62 + (tail ? 2 + 4 * ((tail + 2) / 3) : 0);
  if (size > limits.input_bytes)
    return std::unexpected(Error::kLimit);
  std::string out = "begin 644 " + std::string(filename) + "\n";
  for (size_t offset = 0; offset < bytes.size(); offset += 45) {
    const size_t n = std::min(size_t{45}, bytes.size() - offset);
    out += Enc(static_cast<unsigned>(n));
    for (size_t i = 0; i < n; i += 3) {
      unsigned a = static_cast<unsigned char>(bytes[offset + i]);
      unsigned b = i + 1 < n ? static_cast<unsigned char>(bytes[offset + i + 1]) : 0;
      unsigned c = i + 2 < n ? static_cast<unsigned char>(bytes[offset + i + 2]) : 0;
      out += Enc(a >> 2);
      out += Enc(((a & 3) << 4) | (b >> 4));
      out += Enc(((b & 15) << 2) | (c >> 6));
      out += Enc(c & 63);
    }
    out += '\n';
  }
  out += "`\nend\n";
  return out;
}

std::expected<std::string, Error> Decode(std::string_view block, const Limits& limits) {
  if (block.size() > limits.input_bytes)
    return std::unexpected(Error::kLimit);
  if (block.empty())
    return std::unexpected(Error::kIncomplete);
  auto line = Next(block, 0);
  if (!Header(line.text))
    return std::unexpected(Error::kInvalid);
  bool zero = false;
  std::string out;
  for (size_t pos = line.end; pos < block.size();) {
    line = Next(block, pos);
    pos = line.end;
    if (zero) {
      if (line.text != "end" || pos != block.size())
        return std::unexpected(Error::kInvalid);
      return out;
    }
    auto result = Data(line.text, out, limits.decoded_bytes);
    if (!result)
      return std::unexpected(result.error());
    zero = *result;
  }
  return std::unexpected(Error::kIncomplete);
}

std::expected<std::vector<Block>, Error> Scan(std::string_view text, const Limits& limits) {
  if (text.size() > limits.input_bytes)
    return std::unexpected(Error::kLimit);
  std::vector<Block> out;
  size_t total = 0;
  for (size_t pos = 0; pos < text.size();) {
    auto line = Next(text, pos);
    auto name = Header(line.text);
    pos = line.end;
    if (!name)
      continue;
    if (out.size() == limits.blocks)
      return std::unexpected(Error::kLimit);
    const size_t begin = line.begin;
    while (pos < text.size()) {
      auto data = Next(text, pos);
      if (Header(data.text))
        break;
      pos = data.end;
      if (data.text == "end")
        break;
    }
    auto remaining = limits;
    remaining.decoded_bytes -= total;
    auto bytes = Decode(text.substr(begin, pos - begin), remaining);
    if (bytes)
      total += bytes->size();
    if (!bytes && bytes.error() == Error::kLimit)
      return std::unexpected(Error::kLimit);
    out.push_back({begin, pos, std::string(*name), std::move(bytes)});
  }
  return out;
}
std::expected<std::string, Error> Assemble(const std::vector<std::string_view>& parts, const Limits& limits) {
  if (parts.empty())
    return std::unexpected(Error::kIncomplete);
  if (parts.size() > limits.blocks)
    return std::unexpected(Error::kLimit);
  size_t total = 0;
  for (auto part : parts) {
    if (part.size() > limits.input_bytes - total)
      return std::unexpected(Error::kLimit);
    total += part.size();
  }
  // These delimiters are explicitly recognized by GoldED+'s uulib. They do not
  // imply verification of the sum printed by an external encoder.
  static const std::regex section(R"((sum -r/size [0-9]+/[0-9]+ section.*|section [0-9]+ end.*))", std::regex::icase);
  std::string stream;
  bool started = false;
  bool ended = false;
  for (size_t i = 0; i < parts.size(); ++i) {
    bool data_in_part = false;
    for (size_t pos = 0; pos < parts[i].size();) {
      const auto line = Next(parts[i], pos);
      pos = line.end;
      if (!started) {
        if (i != 0)
          return std::unexpected(Error::kInvalid);
        if (!Header(line.text))
          continue;
        started = true;
      } else {
        if (Header(line.text))
          return std::unexpected(Error::kInvalid);
        if (line.text.size() <= 299 && std::regex_match(line.text.begin(), line.text.end(), section)) {
          if (!data_in_part)
            return std::unexpected(Error::kInvalid);
          break;
        }
      }
      stream += line.text;
      stream += '\n';
      data_in_part = true;
      if (line.text == "end") {
        ended = true;
        break;
      }
    }
    if (ended && i + 1 != parts.size())
      return std::unexpected(Error::kInvalid);
    if (!data_in_part)
      return std::unexpected(Error::kIncomplete);
  }
  return Decode(stream, limits);
}
}  // namespace fidoback::ftn::uue
