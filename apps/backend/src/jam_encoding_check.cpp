#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <string_view>

#include "AppConfig.h"
#include "service/crypto.hpp"
#include "service/hpt_auth.hpp"
#include "storage/jam_access.hpp"
#include "storage/jam_encoding_corrections.hpp"

namespace {
using namespace fidoback;
using namespace fidoback::storage;
using nlohmann::json;

int Fail(std::string_view message) {
  std::cerr << message << '\n';
  return 1;
}

bool ReadAt(int fd, char* data, size_t size, uint64_t offset) {
  while (size > 0) {
    const auto read = pread(fd, data, size, static_cast<off_t>(offset));
    if (read < 0 && errno == EINTR)
      continue;
    if (read <= 0)
      return false;
    data += read;
    size -= static_cast<size_t>(read);
    offset += static_cast<size_t>(read);
  }
  return true;
}

std::string_view Check(const JamAccess& access, msgapi::JamMessageBase& messages, uint32_t number,
                       const JamEncodingCorrection& correction) {
  const auto header = messages.GetHeader(number);
  if (!header) {
    if (header.error() == msgapi::JamError::kInvalidMessageNumber ||
        header.error() == msgapi::JamError::kMessageDeleted)
      return "missing_record";
    return "read_error";
  }
  if (header->subfield_len > msgapi::jam_wire::kMaxSubfields || header->txt_len > msgapi::jam_wire::kMaxReadBody)
    return "record_limit";
  const auto raw = messages.ReadRawMetadata(number);
  if (!raw)
    return "read_error";
  const auto previous = messages.EffectiveEncoding(*raw);
  if (!previous || CanonicalCorrectionEncoding(*previous) != correction.expected_encoding)
    return "decoder_changed";

  const auto& files = access.files().descriptors;
  const auto slot = uint64_t(number - messages.base_header().base_msg_num);
  std::array<uint8_t, 8> index{};
  if (!ReadAt(files[2], reinterpret_cast<char*>(index.data()), index.size(), slot * index.size()))
    return "read_error";
  const auto position = uint64_t(msgapi::jam_wire::Get32(index.data() + 4)) + 76;
  std::string bytes(static_cast<size_t>(header->subfield_len) + header->txt_len, '\0');
  if (!ReadAt(files[0], bytes.data(), header->subfield_len, position) ||
      !ReadAt(files[1], bytes.data() + header->subfield_len, header->txt_len, header->offset))
    return "read_error";
  const auto digest = service::Sha256(bytes);
  if (!digest)
    return "hash_error";
  constexpr std::string_view hex = "0123456789abcdef";
  for (size_t i = 0; i < digest->size(); ++i) {
    const auto byte = (*digest)[i];
    if (correction.raw_sha256[i * 2] != hex[byte >> 4] || correction.raw_sha256[i * 2 + 1] != hex[byte & 15])
      return "fingerprint_changed";
  }
  if (!ConvertText(std::string_view(bytes).substr(header->subfield_len), correction.encoding, "UTF-8",
                   32 * 1024 * 1024))
    return "invalid_target_text";
  for (const auto& field : raw->subfields())
    if (field.high_id() == 0 &&
        (field.type() == msgapi::JamSubFieldType::kSenderName ||
         field.type() == msgapi::JamSubFieldType::kReceiverName || field.type() == msgapi::JamSubFieldType::kSubject) &&
        !ConvertText(field.ToString(), correction.encoding, "UTF-8"))
      return "invalid_target_text";
  return "eligible";
}

int DryRun(const AppConfig& config, const JamEncodingCorrections& manifest, const char* hpt_helper) {
  service::HptConfiguration hpt;
  if (!config.ftn.path_mappings.empty()) {
    const auto loaded = service::LoadHptConfiguration(hpt_helper, config);
    if (!loaded)
      return Fail("Cannot load the active HPT area configuration");
    hpt = *loaded;
  }
  auto areas = service::CatalogAreas(config, hpt);
  if (!areas)
    return Fail("Invalid conference configuration");
  const auto coordination = CoordinationLock::Open(config.ftn.coordination_lock, false);
  if (!coordination)
    return Fail("Existing HPT coordination lock is required");
  std::error_code error;
  const auto root = std::filesystem::canonical(config.ftn.jam_base_path, error);
  if (error)
    return Fail("JAM root unavailable");
  const auto logical_root = std::filesystem::absolute(config.ftn.jam_base_path, error).lexically_normal();
  if (error)
    return Fail("JAM root unavailable");
  std::map<std::string, std::string> overrides;
  for (const auto& area : *areas) {
    std::filesystem::path path(area.filename);
    if (path.is_absolute()) {
      auto relative = path.lexically_relative(logical_root);
      if (relative.empty() || *relative.begin() == "..")
        relative = path.lexically_relative(root);
      path = std::move(relative);
    }
    if (const auto rule = config.ftn.jam_encoding_overrides.find(path.generic_string());
        rule != config.ftn.jam_encoding_overrides.end())
      overrides.insert(*rule);
  }
  CatalogDiagnostic diagnostic;
  const auto catalog = JamCatalog::Build(config.ftn.jam_base_path, *areas, *coordination, overrides, &diagnostic);
  if (!catalog)
    return Fail("JAM catalog unavailable near area " + diagnostic.area);

  std::map<std::string, std::string> echo_ids;
  for (const auto& [id, area] : (*catalog)->areas())
    if (area.config.kind == AreaKind::kEcho && area.files)
      echo_ids.emplace(area.relative_filename.generic_string(), id);
  std::set<std::pair<JamFiles*, uint32_t>> keys;
  for (const auto& [base, entries] : manifest.bases) {
    const auto id = echo_ids.find(base);
    if (id == echo_ids.end())
      return Fail("Manifest base is not a configured JAM echo: " + base);
    const auto owner = (*catalog)->areas().at(id->second).files.get();
    for (const auto& [number, correction] : entries)
      if (!keys.emplace(owner, number).second)
        return Fail("Duplicate physical JAM record through an alias: " + base + "#" + std::to_string(number));
  }

  std::map<std::string, uint64_t> counts;
  for (const auto& [base, entries] : manifest.bases) {
    const auto access =
        JamAccess::Open(**catalog, echo_ids.at(base), false, std::chrono::steady_clock::now() + std::chrono::seconds(5),
                        {}, config.ftn.default_encoding);
    if (!access)
      return Fail("Read lease unavailable for JAM echo: " + base);
    for (const auto& [number, correction] : entries) {
      const auto status = Check(**access, (*access)->messages(), number, correction);
      ++counts[std::string(status)];
      if (status != "eligible")
        std::cout << json{{"kind", "rejected"}, {"base", base}, {"number", number}, {"reason", status}}.dump() << '\n';
    }
  }
  std::cout << json{{"kind", "summary"},
                    {"source_sha256", manifest.source_sha256},
                    {"entries", manifest.count},
                    {"bases", manifest.bases.size()},
                    {"counts", counts}}
                   .dump()
            << '\n';
  if (!std::cout)
    return 1;
  return counts["eligible"] == manifest.count ? 0 : 3;
}
}  // namespace

int main(int argc, char** argv) {
  if (argc != 3 && argc != 5) {
    std::cerr << "Usage: ffido-jam-encoding-check --validate-only MANIFEST\n"
                 "       ffido-jam-encoding-check --dry-run CONFIG MANIFEST HPT_HELPER\n";
    return 2;
  }
  const bool validate = std::string_view(argv[1]) == "--validate-only";
  if ((validate && argc != 3) || (!validate && (argc != 5 || std::string_view(argv[1]) != "--dry-run")))
    return 2;
  const auto config = validate ? std::expected<AppConfig, ConfigError>(AppConfig{}) : LoadAppConfig(argv[2]);
  if (!config)
    return Fail("Cannot read FFIDO configuration");
  const auto path = validate || std::string_view(argv[3]) != "-" ? std::filesystem::path(argv[validate ? 2 : 3])
                                                                 : config->ftn.jam_message_encoding_corrections_path;
  std::ifstream input(path, std::ios::binary);
  if (!input)
    return Fail("Cannot open the correction manifest");
  const auto manifest = LoadJamEncodingCorrections(input);
  if (!manifest)
    return Fail(manifest.error());
  if (!validate)
    return DryRun(*config, *manifest, argv[4]);
  std::cout << json{{"source_sha256", manifest->source_sha256},
                    {"entries", manifest->count},
                    {"bases", manifest->bases.size()}}
                   .dump()
            << '\n';
  return std::cout ? 0 : 1;
}
