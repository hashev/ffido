#include <algorithm>
#include <fstream>
#include <span>

#include "../support/temp_directory.hpp"
#include "JamMessageBase.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 8 || size > 2 * 1024 * 1024)
    return 0;
  fidoback::test::TempDirectory temporary;
  const auto base = temporary.path() / "messages";
  auto rest = std::span(data + 8, size - 8);
  const auto header_size = std::min<size_t>(msgapi::jam_wire::Get32(data), rest.size());
  auto write = [&](std::string_view extension, std::span<const uint8_t> bytes) {
    std::ofstream file(base.string() + std::string(extension), std::ios::binary);
    file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  };
  write(".jhr", rest.first(header_size));
  rest = rest.subspan(header_size);
  const auto index_size = std::min<size_t>(msgapi::jam_wire::Get32(data + 4), rest.size());
  write(".jdx", rest.first(index_size));
  write(".jdt", rest.subspan(index_size));
  msgapi::JamMessageBase messages(base.string());
  if (messages.Open() == msgapi::JamError::kSuccess) {
    auto numbers = messages.GetMessageNumbers();
    if (numbers) {
      for (size_t i = 0; i < std::min<size_t>(numbers->size(), 4); ++i)
        (void)messages.ReadMessage((*numbers)[i]);
    }
    (void)messages.ReadMessage(0);
    (void)messages.ReadMessage(UINT32_MAX);
  }
  return 0;
}
