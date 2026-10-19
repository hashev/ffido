#pragma once

#include <cstdint>
#include <filesystem>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>

#include "tls_certificate.hpp"

namespace fidoback::test {
// Deliberately independent of JamMessageBase and its decoder/codec. Offsets are
// JAM's on-disk wire layout; tests compare against fixed CP866 reference bytes.
inline uint32_t Wire32(const std::string& data, size_t offset) {
  uint32_t value = 0;
  for (unsigned i = 0; i < 4; ++i)
    value |= uint32_t{static_cast<unsigned char>(data.at(offset + i))} << (8 * i);
  return value;
}
struct JamWireRecord {
  std::string header;
  std::string body;
  std::multimap<uint16_t, std::string> fields;
  uint32_t number = 0;
  uint32_t reply_to = 0;
  std::string Field(uint16_t id) const {
    return fields.find(id) == fields.end() ? std::string{} : fields.find(id)->second;
  }
  bool HasField(uint16_t id, std::string_view value) const {
    auto [begin, end] = fields.equal_range(id);
    for (; begin != end; ++begin)
      if (begin->second == value)
        return true;
    return false;
  }
};
inline JamWireRecord ReadJamWireRecord(const std::filesystem::path& base, size_t slot) {
  const auto index = ReadFile(base.string() + ".jdx");
  const auto headers = ReadFile(base.string() + ".jhr");
  const auto text = ReadFile(base.string() + ".jdt");
  const size_t offset = Wire32(index, slot * 8 + 4);
  const size_t length = Wire32(headers, offset + 8);
  if (offset > headers.size() || headers.size() - offset < 76 || length > headers.size() - offset - 76)
    throw std::runtime_error("Invalid JAM header range in fixture");
  JamWireRecord record;
  record.header = headers.substr(offset, 76 + length);
  record.number = Wire32(record.header, 48);
  record.reply_to = Wire32(record.header, 24);
  const size_t body_offset = Wire32(record.header, 60), body_length = Wire32(record.header, 64);
  if (body_offset > text.size() || body_length > text.size() - body_offset)
    throw std::runtime_error("Invalid JAM text range in fixture");
  record.body = text.substr(body_offset, body_length);
  for (size_t position = 76; position < record.header.size();) {
    const auto identifiers = Wire32(record.header, position);
    const size_t count = Wire32(record.header, position + 4);
    position += 8;
    if (count > record.header.size() - position)
      throw std::runtime_error("Invalid JAM subfield range in fixture");
    if ((identifiers >> 16) == 0)
      record.fields.emplace(static_cast<uint16_t>(identifiers), record.header.substr(position, count));
    position += count;
  }
  return record;
}
}  // namespace fidoback::test
