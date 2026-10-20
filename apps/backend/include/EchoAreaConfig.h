#pragma once

#include <expected>
#include <nlohmann/json.hpp>
#include <optional>
#include <shared_mutex>
#include <string>
#include <vector>

enum class ParseError { kSuccess = 0, kFileOpenError, kInvalidFormat, kUnknownOption, kInvalidValue, kDuplicateOption };

enum class AreaKind { kEcho = 0, kNetmail = 1, kLocal = 2, kBad = 3, kDupe = 4, kRobots = 5 };

struct EchoAreaConfig {
  struct LinkOptions {
    bool is_default = false;
    bool read_only = false;
    bool write_only = false;
    bool mandatory = false;

    nlohmann::json ToJson() const;
  };

  struct AccessLevels {
    std::optional<uint32_t> read;
    std::optional<uint32_t> write;

    nlohmann::json ToJson() const;
  };

  struct PurgeSettings {
    std::optional<uint32_t> after_days;
    std::optional<uint32_t> max_messages;
    bool enabled = true;
    bool kill_read = false;
    bool keep_unread = false;

    nlohmann::json ToJson() const;
  };

  struct MsgBaseSettings {
    bool keep_seen_by = true;
    bool tiny_seen_by = false;
    bool kill_seen_by = false;
    bool dos_filename = false;

    nlohmann::json ToJson() const;
  };

  std::string name;
  std::string filename;
  std::optional<std::string> msgbase_type;
  AccessLevels access_levels;
  PurgeSettings purge_settings;
  MsgBaseSettings msgbase_settings;
  std::optional<std::string> group;
  std::optional<std::string> description;
  std::optional<std::string> aka;
  std::vector<std::string> link_akas;
  std::vector<LinkOptions> link_options;
  bool is_passthrough = false;
  bool mandatory = false;
  bool manual_subscribe = false;
  bool hidden = false;
  bool pauseable = true;
  bool carbon_copy = true;
  bool reply_linking = true;
  bool debug = false;

  std::string mailbox_address;
  std::string mailbox_generation;
  std::string mailbox_files;
  AreaKind kind = AreaKind::kEcho;

  nlohmann::json ToJson() const;
};

class ConfigManager {
public:
  explicit ConfigManager(std::string config_path);

  std::expected<std::vector<EchoAreaConfig>, ParseError> GetConfig() const;
  void UpdateConfigPath(std::string new_path);
  std::string GetConfigPath() const;

private:
  mutable std::shared_mutex config_mutex_;
  std::string config_path_;

  std::expected<std::vector<EchoAreaConfig>, ParseError> ParseConfig() const;
  static std::string_view TrimWhitespace(std::string_view str);
  static std::optional<uint32_t> ParseUint32(std::string_view str);
};
