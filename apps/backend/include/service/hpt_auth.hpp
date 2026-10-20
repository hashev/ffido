#pragma once

#include <chrono>
#include <expected>
#include <filesystem>
#include <map>
#include <string>
#include <vector>

#include "AppConfig.h"
#include "EchoAreaConfig.h"
#include "domain/error.hpp"
#include "domain/ftn_address.hpp"

namespace fidoback::service {
using HptCredentials = std::map<std::string, std::string>;
struct EchoPermissions {
  bool read = false;
  bool post = false;
  bool visible = false;
};
struct HptEcho {
  std::string name;
  std::filesystem::path filename;
  std::map<std::string, EchoPermissions> links;
  std::string description{};
};
struct HptNetmailPolicy {
  std::string name;
  bool dupe_check_off = false;
};
struct HptRoute {
  std::string pattern;
  bool nopack = false;
  bool mail = false;
};
struct HptTransport {
  bool available = false, keep_transit = false, pack_on_scan = false;
  std::vector<std::string> own_addresses;
  std::map<std::string, std::string> link_akas;
  std::vector<HptNetmailPolicy> netmail;
  std::vector<HptRoute> routes;
};
struct HptConfiguration {
  HptCredentials credentials;
  HptTransport transport;
  std::vector<HptEcho> echoes;
  std::vector<EchoAreaConfig> private_areas;
  std::vector<std::pair<uint64_t, uint64_t>> included_files;
};
std::expected<HptConfiguration, domain::ApiError> ReadHptConfiguration(
    const std::filesystem::path& helper, const std::filesystem::path& config,
    std::chrono::milliseconds timeout = std::chrono::seconds(5), std::span<const ftn::PathMapping> mappings = {});
std::expected<HptConfiguration, domain::ApiError> LoadHptConfiguration(const std::filesystem::path& helper,
                                                                       const AppConfig& config);
std::expected<std::vector<EchoAreaConfig>, domain::ApiError> CatalogAreas(const AppConfig& config,
                                                                          const HptConfiguration& hpt);
}  // namespace fidoback::service
