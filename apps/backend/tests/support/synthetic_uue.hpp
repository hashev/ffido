#pragma once

#include <fstream>

#include "JamMessageBase.h"
#include "ftn/uue.hpp"
#include "service/uue_service.hpp"

namespace fidoback::test {
// Incoming synthetic JAM, including valid legacy bodies larger than the outgoing
// 1 MiB writer limit. Every source still obeys the public 10 MiB read limit.
inline std::vector<std::vector<service::UueReference>> SyntheticUue(const std::filesystem::path& base,
                                                                    const storage::JamCatalog& catalog,
                                                                    std::string_view area, const std::string& payload,
                                                                    bool single, int groups = 1) {
  const ftn::uue::Limits limits{16 * 1024 * 1024, 32 * 1024 * 1024 + 4096, 1024};
  auto encoded = ftn::uue::Encode(payload, "synthetic.bin", limits);
  if (!encoded)
    throw std::runtime_error("Synthetic encoding failed");
  std::vector<std::string_view> parts;
  for (size_t offset = 0; offset < encoded->size();) {
    const auto end = single ? encoded->size() : std::min(encoded->size(), offset + 256 * 1024);
    auto split = end == encoded->size() ? end : encoded->find('\n', end) + 1;
    parts.push_back(std::string_view(*encoded).substr(offset, split - offset));
    offset = split;
  }
  if (parts.front().size() > msgapi::jam_wire::kMaxReadBody)
    throw std::runtime_error("Single source exceeds the existing JAM read limit");
  msgapi::JamBaseHeader header{};
  header.signature = msgapi::kJamSignature;
  header.base_msg_num = 42;
  header.date_created = 123;
  header.password_crc = UINT32_MAX;
  header.active_msgs = static_cast<uint32_t>(parts.size() * groups);
  const auto bytes = msgapi::jam_wire::Encode(header);
  {
    std::ofstream jhr(base.string() + ".jhr", std::ios::binary | std::ios::trunc);
    std::ofstream jdx(base.string() + ".jdx", std::ios::binary | std::ios::trunc);
    std::ofstream jdt(base.string() + ".jdt", std::ios::binary | std::ios::trunc);
    jhr.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    uint32_t header_offset = 1024, body_offset = 0;
    for (int group = 0; group < groups; ++group)
      for (size_t part = 0; part < parts.size(); ++part) {
        const auto number = 42 + static_cast<uint32_t>(group * parts.size() + part);
        std::string fields;
        const auto field = [&](msgapi::JamSubFieldType type, std::string_view text) {
          std::array<uint8_t, 8> descriptor{};
          msgapi::jam_wire::Put16(descriptor.data(), static_cast<uint16_t>(type));
          msgapi::jam_wire::Put32(descriptor.data() + 4, static_cast<uint32_t>(text.size()));
          fields.append(reinterpret_cast<const char*>(descriptor.data()), descriptor.size());
          fields += text;
        };
        field(msgapi::JamSubFieldType::kOAddress, "2:5015/1.1");
        field(msgapi::JamSubFieldType::kSenderName, "Synthetic");
        field(msgapi::JamSubFieldType::kReceiverName, "All");
        field(msgapi::JamSubFieldType::kMsgId, "2:5015/1.1 " + std::to_string(number));
        field(msgapi::JamSubFieldType::kFtsKludge, "CHRS: UTF-8 4");
        field(msgapi::JamSubFieldType::kSubject, "Synthetic " + std::to_string(group) + " [" +
                                                     std::to_string(part + 1) + "/" + std::to_string(parts.size()) +
                                                     "]");
        msgapi::JamMessageHeader item{};
        item.signature = msgapi::kJamSignature;
        item.revision = 1;
        item.message_number = number;
        item.subfield_len = static_cast<uint32_t>(fields.size());
        item.offset = body_offset;
        item.txt_len = static_cast<uint32_t>(parts[part].size());
        item.date_written = 100 + number;
        const auto record = msgapi::jam_wire::Encode(item);
        const auto index = msgapi::jam_wire::Encode(msgapi::JamIndexRecord{0, header_offset});
        jhr.write(reinterpret_cast<const char*>(record.data()), record.size());
        jhr.write(fields.data(), fields.size());
        jdx.write(reinterpret_cast<const char*>(index.data()), index.size());
        jdt.write(parts[part].data(), parts[part].size());
        header_offset += static_cast<uint32_t>(record.size() + fields.size());
        body_offset += item.txt_len;
      }
    if (!jhr || !jdx || !jdt)
      throw std::runtime_error("Synthetic JAM write failed");
  }
  auto view =
      storage::JamAccess::Open(catalog, area, false, std::chrono::steady_clock::now() + std::chrono::seconds(5));
  if (!view)
    throw std::runtime_error("Synthetic JAM open failed");
  std::vector<std::vector<service::UueReference>> result(groups);
  for (int group = 0; group < groups; ++group)
    for (size_t part = 0; part < parts.size(); ++part)
      result[group].push_back(
          {std::string(area), (*view)->generation() + "#" + std::to_string(42 + group * parts.size() + part), 0});
  return result;
}
}  // namespace fidoback::test
