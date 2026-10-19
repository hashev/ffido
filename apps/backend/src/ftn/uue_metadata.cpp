#include "ftn/uue_metadata.hpp"

#include <algorithm>
#include <charconv>

#include "service/crypto.hpp"
#include "storage/text_codec.hpp"

namespace fidoback::ftn::uue {
namespace {
constexpr std::string_view hex = "0123456789abcdef";
bool IsHex(std::string_view text, size_t count) {
  return text.size() == count && text.find_first_not_of(hex) == std::string_view::npos;
}
bool Valid(const Metadata& m, const Limits& limits) {
  return IsHex(m.transfer_id, 32) && IsHex(m.sha256, 64) && m.part && m.total && m.part <= m.total &&
         m.total <= limits.blocks && m.size <= limits.decoded_bytes && !m.filename.empty() &&
         m.filename.size() <= 255 && m.filename == SafeFilename(m.filename) &&
         bool(storage::ConvertText(m.filename, "UTF-8", "UTF-8"));
}
bool Unreserved(unsigned char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.';
}
std::string Escape(std::string_view value) {
  std::string out;
  for (unsigned char c : value) {
    if (Unreserved(c))
      out += static_cast<char>(c);
    else {
      out += '%';
      out += hex[c >> 4];
      out += hex[c & 15];
    }
  }
  return out;
}
std::expected<std::string, Error> Unescape(std::string_view value) {
  std::string out;
  for (size_t i = 0; i < value.size(); ++i) {
    unsigned char c = value[i];
    if (c == '%') {
      if (i + 2 >= value.size())
        return std::unexpected(Error::kInvalid);
      auto a = hex.find(value[i + 1]);
      auto b = hex.find(value[i + 2]);
      if (a == hex.npos || b == hex.npos)
        return std::unexpected(Error::kInvalid);
      c = static_cast<unsigned char>(a * 16 + b);
      i += 2;
      // One canonical representation makes repeat/conflict detection unambiguous.
      if (Unreserved(c))
        return std::unexpected(Error::kInvalid);
    } else if (!Unreserved(c))
      return std::unexpected(Error::kInvalid);
    out += static_cast<char>(c);
    if (out.size() > 255)
      return std::unexpected(Error::kLimit);
  }
  return out;
}
template <class T>
bool Number(std::string_view value, T& out) {
  if (value.empty() || (value.size() > 1 && value[0] == '0'))
    return false;
  auto [end, error] = std::from_chars(value.data(), value.data() + value.size(), out);
  return error == std::errc{} && end == value.data() + value.size();
}
}  // namespace

std::string SafeFilename(std::string_view filename, bool ascii) {
  const auto slash = filename.find_last_of("/\\");
  if (slash != filename.npos)
    filename.remove_prefix(slash + 1);
  if (!storage::ConvertText(filename, "UTF-8", "UTF-8"))
    return "attachment.bin";
  std::string out;
  for (unsigned char c : filename) {
    if (c < 32 || c == 127 || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|')
      out += '_';
    else if (ascii && (c > 126 || c == ' '))
      out += '_';
    else
      out += static_cast<char>(c);
  }
  while (!out.empty() && (out.back() == '.' || out.back() == ' '))
    out.pop_back();
  while (!out.empty() && (out.front() == '.' || out.front() == ' '))
    out.erase(0, 1);
  if (out.empty())
    return "attachment.bin";
  // Preserve a UTF-8 boundary when capping a byte-based FTN filename field.
  if (out.size() > 200) {
    size_t end = 200;
    while (end && (static_cast<unsigned char>(out[end]) & 0xc0) == 0x80)
      --end;
    out.resize(end);
  }
  auto stem = out.substr(0, out.find('.'));
  std::transform(stem.begin(), stem.end(), stem.begin(), [](unsigned char c) {
    return c >= 'a' && c <= 'z' ? static_cast<char>(c - 'a' + 'A') : static_cast<char>(c);
  });
  if (stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL" ||
      (stem.size() == 4 && (stem.starts_with("COM") || stem.starts_with("LPT")) && stem[3] >= '1' && stem[3] <= '9'))
    out.insert(0, "_");
  return out;
}
std::expected<std::string, Error> FormatMetadata(const Metadata& m, const Limits& limits) {
  if (!Valid(m, limits))
    return std::unexpected(Error::kInvalid);
  return "FFIDO-UUE: 1 " + m.transfer_id + " " + std::to_string(m.part) + "/" + std::to_string(m.total) + " " +
         std::to_string(m.size) + " " + m.sha256 + " " + Escape(m.filename);
}
std::expected<Metadata, Error> ParseMetadata(std::string_view line, const Limits& limits) {
  if (line.size() > 1024)
    return std::unexpected(Error::kLimit);
  constexpr std::string_view prefix = "FFIDO-UUE: 1 ";
  if (!line.starts_with(prefix))
    return std::unexpected(Error::kInvalid);
  line.remove_prefix(prefix.size());
  std::vector<std::string_view> fields;
  while (true) {
    const auto space = line.find(' ');
    fields.push_back(line.substr(0, space));
    if (space == line.npos)
      break;
    line.remove_prefix(space + 1);
    if (fields.size() > 5)
      return std::unexpected(Error::kInvalid);
  }
  if (fields.size() != 5)
    return std::unexpected(Error::kInvalid);
  Metadata m;
  m.transfer_id = fields[0];
  m.sha256 = fields[3];
  const auto slash = fields[1].find('/');
  if (slash == fields[1].npos || !Number(fields[1].substr(0, slash), m.part) ||
      !Number(fields[1].substr(slash + 1), m.total) || !Number(fields[2], m.size))
    return std::unexpected(Error::kInvalid);
  auto name = Unescape(fields[4]);
  if (!name)
    return std::unexpected(name.error());
  m.filename = std::move(*name);
  if (!Valid(m, limits))
    return std::unexpected(Error::kInvalid);
  return m;
}
std::expected<void, Error> Verify(std::string_view bytes, const Metadata& metadata) {
  if (bytes.size() != metadata.size)
    return std::unexpected(Error::kInvalid);
  auto digest = service::Sha256(bytes);
  if (!digest)
    return std::unexpected(Error::kInvalid);
  std::string text;
  for (auto byte : *digest) {
    text += hex[byte >> 4];
    text += hex[byte & 15];
  }
  if (text != metadata.sha256)
    return std::unexpected(Error::kInvalid);
  return {};
}
}  // namespace fidoback::ftn::uue
