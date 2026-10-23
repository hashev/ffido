#include "AppConfig.h"

#include <iconv.h>
#include <spdlog/spdlog.h>

#include <fstream>
#include <limits>
#include <set>

#include "domain/ftn_address.hpp"

namespace {

/// @brief Безопасное чтение строки из JSON.
std::string ReadString(const nlohmann::json& j, std::string_view key, std::string_view default_val) {
  if (j.contains(key.data()))
    return j[key.data()].get<std::string>();
  return std::string(default_val);
}

/// @brief Безопасное чтение числа из JSON.
template <typename T>
T ReadNumber(const nlohmann::json& j, std::string_view key, T default_val) {
  if (j.contains(key.data())) {
    const auto& value = j[key.data()];
    if (!value.is_number_integer() || (value.is_number_unsigned() && value.get<uint64_t>() > INT64_MAX))
      throw std::invalid_argument("Invalid integer configuration");
    const auto number = value.get<int64_t>();
    if constexpr (std::is_unsigned_v<T>) {
      if (number < 0 || uint64_t(number) > std::numeric_limits<T>::max())
        throw std::invalid_argument("Integer range");
    } else if (number < std::numeric_limits<T>::min() || number > std::numeric_limits<T>::max())
      throw std::invalid_argument("Integer range");
    return static_cast<T>(number);
  }
  return default_val;
}

}  // namespace

AppConfig DefaultConfig() {
  AppConfig cfg;
  cfg.server.ip = "0.0.0.0";
  cfg.server.port = 8080;
  cfg.server.thread_num = 8;
  cfg.ftn.areacfg_path = "./ftn/areas.cfg";
  cfg.ftn.jam_base_path = "./ftn/jam";
  cfg.ftn.default_encoding = "cp866";
  cfg.database.metadata_path = "./data/metadata.db";

  cfg.logging.level = "info";

  return cfg;
}

std::expected<AppConfig, ConfigError> ParseAppConfig(const nlohmann::json& j) {
  if (!j.is_object())
    return std::unexpected(ConfigError::kInvalidValue);
  try {
    AppConfig cfg = DefaultConfig();

    if (j.contains("jwt"))
      return std::unexpected(ConfigError::kInvalidValue);

    // ── Server ──
    if (j.contains("server")) {
      const auto& srv = j["server"];
      cfg.server.ip = ReadString(srv, "ip", cfg.server.ip);
      if (!srv.is_object())
        return std::unexpected(ConfigError::kInvalidValue);
      if (srv.contains("port") && !srv["port"].is_number_integer())
        return std::unexpected(ConfigError::kInvalidValue);
      const auto port = ReadNumber<int64_t>(srv, "port", cfg.server.port);
      if (port < 1 || port > 65535)
        return std::unexpected(ConfigError::kInvalidValue);
      cfg.server.port = static_cast<uint16_t>(port);
      cfg.server.thread_num = ReadNumber(srv, "thread_num", cfg.server.thread_num);
      cfg.server.rpc_timeout_ms = ReadNumber(srv, "rpc_timeout_ms", cfg.server.rpc_timeout_ms);
      cfg.server.shutdown_timeout_ms = ReadNumber(srv, "shutdown_timeout_ms", cfg.server.shutdown_timeout_ms);
      cfg.server.tls_certificate = ReadString(srv, "tls_certificate", cfg.server.tls_certificate);
      cfg.server.tls_private_key = ReadString(srv, "tls_private_key", cfg.server.tls_private_key);
      if (cfg.server.thread_num < 1 || cfg.server.thread_num > 256 || cfg.server.rpc_timeout_ms < 1 ||
          cfg.server.rpc_timeout_ms > 60000 || cfg.server.shutdown_timeout_ms < 1 ||
          cfg.server.shutdown_timeout_ms > 60000 || cfg.server.ip.empty() ||
          cfg.server.ip.find('\0') != std::string::npos || cfg.server.tls_certificate.find('\0') != std::string::npos ||
          cfg.server.tls_private_key.find('\0') != std::string::npos)
        return std::unexpected(ConfigError::kInvalidValue);
    }

    // ── FTN ──
    if (j.contains("ftn")) {
      const auto& ftn = j["ftn"];
      if (!ftn.is_object())
        return std::unexpected(ConfigError::kInvalidValue);
      if (ftn.contains("path_mappings")) {
        const auto& rules = ftn.at("path_mappings");
        if (!rules.is_array() || rules.size() > 128)
          return std::unexpected(ConfigError::kInvalidValue);
        std::vector<fidoback::ftn::PathMapping> mappings;
        for (const auto& rule : rules) {
          if (!rule.is_object())
            return std::unexpected(ConfigError::kInvalidValue);
          mappings.push_back({rule.at("from").get<std::string>(), rule.at("to").get<std::string>()});
        }
        auto validated = fidoback::ftn::ValidateMappings(mappings);
        if (!validated)
          return std::unexpected(ConfigError::kInvalidValue);
        cfg.ftn.path_mappings = std::move(*validated);
      }
      cfg.ftn.areacfg_path = ReadString(ftn, "areacfg_path", cfg.ftn.areacfg_path);
      cfg.ftn.jam_base_path = ReadString(ftn, "jam_base_path", cfg.ftn.jam_base_path);
      cfg.ftn.default_encoding = ReadString(ftn, "default_encoding", cfg.ftn.default_encoding);
      cfg.ftn.coordination_lock = ReadString(ftn, "coordination_lock", cfg.ftn.coordination_lock.string());
      if (cfg.ftn.coordination_lock.string().find('\0') != std::string::npos)
        return std::unexpected(ConfigError::kInvalidValue);
      if (cfg.ftn.default_encoding.empty() || cfg.ftn.default_encoding.find('\0') != std::string::npos)
        return std::unexpected(ConfigError::kInvalidValue);
      if (cfg.ftn.areacfg_path.empty() || cfg.ftn.jam_base_path.empty() ||
          cfg.ftn.areacfg_path.find('\0') != std::string::npos ||
          cfg.ftn.jam_base_path.find('\0') != std::string::npos || cfg.ftn.default_encoding.size() > 64 ||
          cfg.ftn.default_encoding.find("//") != std::string::npos)
        return std::unexpected(ConfigError::kInvalidValue);
      const auto valid_encoding = [](const std::string& encoding) {
        if (encoding.empty() || encoding.size() > 64 || encoding.find('\0') != std::string::npos ||
            encoding.find("//") != std::string::npos)
          return false;
        for (const auto& direction : {std::pair{"UTF-8", encoding.c_str()}, std::pair{encoding.c_str(), "UTF-8"}}) {
          auto converter = iconv_open(direction.first, direction.second);
          if (converter == reinterpret_cast<iconv_t>(-1))
            return false;
          iconv_close(converter);
        }
        return true;
      };
      if (!valid_encoding(cfg.ftn.default_encoding))
        return std::unexpected(ConfigError::kInvalidValue);
      if (ftn.contains("jam_encoding_overrides")) {
        const auto& rules = ftn.at("jam_encoding_overrides");
        if (!rules.is_object() || rules.size() > 10000)
          return std::unexpected(ConfigError::kInvalidValue);
        for (const auto& [name, value] : rules.items()) {
          const std::filesystem::path path(name);
          if (name.empty() || name.size() > 4096 || name.find('\0') != std::string::npos ||
              name.find("//") != std::string::npos || path.is_absolute() || path.filename().empty() ||
              path.generic_string() != name)
            return std::unexpected(ConfigError::kInvalidValue);
          for (const auto& part : path)
            if (part == "." || part == ".." || part.empty())
              return std::unexpected(ConfigError::kInvalidValue);
          auto encoding = value.get<std::string>();
          if (!valid_encoding(encoding))
            return std::unexpected(ConfigError::kInvalidValue);
          for (auto& c : encoding)
            if (c >= 'a' && c <= 'z')
              c -= 'a' - 'A';
          cfg.ftn.jam_encoding_overrides.emplace(name, std::move(encoding));
        }
      }
    }

    if (j.contains("auth")) {
      const auto& auth = j["auth"];
      if (!auth.is_object())
        return std::unexpected(ConfigError::kInvalidValue);
      if (auth.contains("owner_addresses")) {
        const auto& owners = auth.at("owner_addresses");
        if (!owners.is_array() || owners.size() > 10000)
          return std::unexpected(ConfigError::kInvalidValue);
        std::set<std::string> unique;
        for (const auto& value : owners) {
          auto address = fidoback::domain::CanonicalFtnAddress(value.get<std::string>());
          if (!address || !unique.insert(*address).second)
            return std::unexpected(ConfigError::kInvalidValue);
          cfg.auth.owner_addresses.push_back(*address);
        }
      }
      cfg.auth.hpt_config_path = ReadString(auth, "hpt_config_path", "");
      cfg.auth.session_key_path = ReadString(auth, "session_key_path", "");
      for (const auto& path : {cfg.auth.hpt_config_path, cfg.auth.session_key_path})
        if (path.empty() || path.string().find('\0') != std::string::npos)
          return std::unexpected(ConfigError::kInvalidValue);
    }

    if (j.contains("point_mail")) {
      const auto& mail = j.at("point_mail");
      if (!mail.is_object())
        return std::unexpected(ConfigError::kInvalidValue);
      cfg.point_mail.enabled = mail.value("enabled", false);
      cfg.point_mail.ingress_areas = mail.value("ingress_areas", std::vector<std::string>{});
      cfg.point_mail.egress_area = mail.value("egress_area", std::string{});
      const auto points = mail.value("points", nlohmann::json::array());
      if (!points.is_array() || points.size() > 10000)
        return std::unexpected(ConfigError::kInvalidValue);
      std::set<std::string> addresses, paths, ingress;
      auto valid_tag = [](const std::string& tag) {
        return !tag.empty() && tag.size() <= 256 && tag.find_first_of(" \t\r\n") == std::string::npos &&
               tag.find('\0') == std::string::npos;
      };
      for (const auto& point : points) {
        auto address = fidoback::domain::CanonicalFtnAddress(point.at("address").get<std::string>());
        std::filesystem::path path = point.at("jam_base").get<std::string>();
        if (!address || address->find('.') == std::string::npos || !addresses.insert(*address).second || path.empty() ||
            path.is_absolute() || path.string().find('\0') != std::string::npos)
          return std::unexpected(ConfigError::kInvalidValue);
        for (const auto& part : path)
          if (part == ".." || part == "." || part.empty())
            return std::unexpected(ConfigError::kInvalidValue);
        if (!paths.insert(path.generic_string()).second)
          return std::unexpected(ConfigError::kInvalidValue);
        cfg.point_mail.points.push_back({*address, path});
      }
      for (auto tag : cfg.point_mail.ingress_areas) {
        for (auto& c : tag)
          if (c >= 'A' && c <= 'Z')
            c += 'a' - 'A';
        if (!valid_tag(tag) || !ingress.insert(tag).second)
          return std::unexpected(ConfigError::kInvalidValue);
      }
      auto egress = cfg.point_mail.egress_area;
      for (auto& c : egress)
        if (c >= 'A' && c <= 'Z')
          c += 'a' - 'A';
      if (cfg.point_mail.enabled && (cfg.point_mail.points.empty() || ingress.empty() || !valid_tag(egress) ||
                                     ingress.contains(egress) || cfg.ftn.coordination_lock.empty()))
        return std::unexpected(ConfigError::kInvalidValue);
    }

    if (j.contains("uue")) {
      const auto& value = j["uue"];
      if (!value.is_object())
        return std::unexpected(ConfigError::kInvalidValue);
      cfg.uue.max_file_bytes = ReadNumber(value, "max_file_bytes", cfg.uue.max_file_bytes);
      cfg.uue.part_body_bytes = ReadNumber(value, "part_body_bytes", cfg.uue.part_body_bytes);
      cfg.uue.max_parts = ReadNumber(value, "max_parts", cfg.uue.max_parts);
      cfg.uue.chunk_bytes = ReadNumber(value, "chunk_bytes", cfg.uue.chunk_bytes);
      cfg.uue.user_quota_bytes = ReadNumber(value, "user_quota_bytes", cfg.uue.user_quota_bytes);
      cfg.uue.global_quota_bytes = ReadNumber(value, "global_quota_bytes", cfg.uue.global_quota_bytes);
      cfg.uue.upload_ttl_seconds = ReadNumber(value, "upload_ttl_seconds", cfg.uue.upload_ttl_seconds);
      cfg.uue.preview_pixels = ReadNumber(value, "preview_pixels", cfg.uue.preview_pixels);
      cfg.uue.preview_dimension = ReadNumber(value, "preview_dimension", cfg.uue.preview_dimension);
      const auto& u = cfg.uue;
      if (!u.max_file_bytes || u.max_file_bytes > 16 * 1024 * 1024 || u.part_body_bytes < 1024 ||
          u.part_body_bytes > 256 * 1024 || !u.max_parts || u.max_parts > 1024 || !u.chunk_bytes ||
          u.chunk_bytes > 65536 || u.user_quota_bytes < 3 * u.max_file_bytes ||
          u.global_quota_bytes < u.user_quota_bytes || u.global_quota_bytes > 1024ull * 1024 * 1024 ||
          !u.upload_ttl_seconds || u.upload_ttl_seconds > 604800 || !u.preview_pixels || u.preview_pixels > 64000000 ||
          !u.preview_dimension || u.preview_dimension > 16384 ||
          (u.max_file_bytes * 62 / 45 + 1024) > uint64_t(u.max_parts) * (u.part_body_bytes - 512))
        return std::unexpected(ConfigError::kInvalidValue);
    }

    // ── Database ──
    if (j.contains("database")) {
      const auto& db = j["database"];
      if (!db.is_object())
        return std::unexpected(ConfigError::kInvalidValue);
      std::string path_str = ReadString(db, "metadata_path", "");
      if (path_str.find('\0') != std::string::npos)
        return std::unexpected(ConfigError::kInvalidValue);
      if (!path_str.empty()) {
        cfg.database.metadata_path = path_str;
      }
    }

    // ── Logging ──
    if (j.contains("logging")) {
      const auto& log = j["logging"];
      if (!log.is_object())
        return std::unexpected(ConfigError::kInvalidValue);
      cfg.logging.level = ReadString(log, "level", cfg.logging.level);
    }

    return cfg;
  } catch (const std::exception&) {
    return std::unexpected(ConfigError::kInvalidValue);
  }
}

std::expected<AppConfig, ConfigError> LoadAppConfig(std::string_view config_path) {
  // Пустой путь — используем дефолты
  if (config_path.empty()) {
    spdlog::warn("Config path is empty, using defaults");
    return DefaultConfig();
  }

  std::ifstream file{std::string(config_path)};
  if (!file.is_open()) {
    return std::unexpected(ConfigError::kFileNotFound);
  }

  try {
    nlohmann::json j = nlohmann::json::parse(file);
    auto config = ParseAppConfig(j);
    if (!config)
      return config;
    std::error_code error;
    const auto absolute = std::filesystem::absolute(std::filesystem::path(config_path), error);
    if (error)
      return std::unexpected(ConfigError::kInvalidValue);
    auto resolve = [&](std::filesystem::path path) {
      return path.empty() || path.is_absolute() ? path : (absolute.parent_path() / path).lexically_normal();
    };
    config->ftn.areacfg_path = resolve(config->ftn.areacfg_path).string();
    config->ftn.jam_base_path = resolve(config->ftn.jam_base_path).string();
    config->ftn.coordination_lock = resolve(config->ftn.coordination_lock);
    config->auth.hpt_config_path = resolve(config->auth.hpt_config_path);
    config->auth.session_key_path = resolve(config->auth.session_key_path);
    config->database.metadata_path = resolve(config->database.metadata_path);
    config->server.tls_certificate = resolve(config->server.tls_certificate).string();
    config->server.tls_private_key = resolve(config->server.tls_private_key).string();
    return config;
  } catch (const nlohmann::json::parse_error&) {
    spdlog::error("Invalid JSON configuration");
    return std::unexpected(ConfigError::kParseError);
  }
}
