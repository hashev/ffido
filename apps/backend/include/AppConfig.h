#pragma once

#include <chrono>
#include <cstdint>
#include <expected>
#include <filesystem>
#include <nlohmann/json.hpp>
#include <string>
#include <string_view>
#include <vector>

#include "ftn/path_mapping.hpp"

// ─────────────────────────────────────────────────────────────────────────────
// Структуры конфигурации
// ─────────────────────────────────────────────────────────────────────────────

/// @brief Настройки gRPC-сервера.
struct ServerConfig {
  std::string ip = "0.0.0.0";
  uint16_t port = 8080;
  size_t thread_num = 8;
  int rpc_timeout_ms = 5000;
  int shutdown_timeout_ms = 10000;
  std::string tls_certificate;
  std::string tls_private_key;
};

/// @brief Настройки FTN (FidoNet) — пути к месседж-базам.
struct FtnConfig {
  std::vector<fidoback::ftn::PathMapping> path_mappings;
  std::string areacfg_path;
  std::string jam_base_path;
  std::string default_encoding = "cp866";
  std::filesystem::path coordination_lock;
};

/// @brief Настройки базы данных метаданных.
struct DatabaseConfig {
  std::filesystem::path metadata_path;
};

/// @brief Настройки логирования.
struct LoggingConfig {
  std::string level = "info";
};

struct AuthConfig {
  std::vector<std::string> owner_addresses;
  std::filesystem::path hpt_config_path;
  std::filesystem::path session_key_path;
};

struct PointMailboxConfig {
  std::string address;
  std::filesystem::path jam_base;
};
struct PointMailConfig {
  bool enabled = false;
  std::vector<std::string> ingress_areas;
  std::string egress_area;
  std::vector<PointMailboxConfig> points;
};

struct UueConfig {
  uint64_t max_file_bytes = 1024 * 1024;
  uint32_t part_body_bytes = 32768, max_parts = 128, chunk_bytes = 65536;
  uint64_t user_quota_bytes = 8 * 1024 * 1024, global_quota_bytes = 64 * 1024 * 1024;
  uint32_t upload_ttl_seconds = 86400;
  uint64_t preview_pixels = 16000000;
  uint32_t preview_dimension = 8192;
};

/// @brief Полная конфигурация приложения.
struct AppConfig {
  ServerConfig server;
  FtnConfig ftn;
  DatabaseConfig database;
  LoggingConfig logging;
  AuthConfig auth;
  PointMailConfig point_mail;
  UueConfig uue;
};

// ─────────────────────────────────────────────────────────────────────────────
// Парсинг конфигурации
// ─────────────────────────────────────────────────────────────────────────────

/// @brief Коды ошибок парсинга конфигурации.
enum class ConfigError {
  kSuccess = 0,
  kFileNotFound,
  kParseError,
  kInvalidValue,
};

/// @brief Загрузить конфигурацию из JSON-файла.
/// @param config_path Путь к config.json.
/// @return Загруженная конфигурация или ошибка.
/// @note Если config_path пустой, используются значения по умолчанию.
[[nodiscard]] std::expected<AppConfig, ConfigError> LoadAppConfig(std::string_view config_path);

/// @brief Загрузить конфигурацию из JSON-объекта.
[[nodiscard]] std::expected<AppConfig, ConfigError> ParseAppConfig(const nlohmann::json& j);

/// @brief Конфигурация по умолчанию (для backward compatibility).
[[nodiscard]] AppConfig DefaultConfig();
