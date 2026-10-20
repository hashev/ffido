#include "EchoAreaConfig.h"

#include <spdlog/spdlog.h>

#include <charconv>
#include <fstream>
#include <set>

namespace {
std::string Lower(std::string_view value) {
  std::string result(value);
  for (auto& c : result) {
    if (c >= 'A' && c <= 'Z')
      c = static_cast<char>(c + ('a' - 'A'));
  }
  return result;
}

std::expected<std::vector<std::string_view>, ParseError> Tokens(std::string_view line) {
  std::vector<std::string_view> result;
  while (!line.empty()) {
    const auto start = line.find_first_not_of(" \t\r");
    if (start == std::string_view::npos || line[start] == '#')
      break;
    line.remove_prefix(start);
    size_t end;
    if (line.front() == '"') {
      line.remove_prefix(1);
      end = line.find('"');
      if (end == std::string_view::npos)
        return std::unexpected(ParseError::kInvalidFormat);
      result.push_back(line.substr(0, end));
      line.remove_prefix(end + 1);
      if (!line.empty() && line.front() != ' ' && line.front() != '\t' && line.front() != '\r' && line.front() != '#')
        return std::unexpected(ParseError::kInvalidFormat);
    } else {
      end = line.find_first_of(" \t\r#");
      result.push_back(line.substr(0, end));
      if (end == std::string_view::npos)
        break;
      line.remove_prefix(end);
    }
  }
  return result;
}
}  // namespace

ConfigManager::ConfigManager(std::string config_path) : config_path_(std::move(config_path)) {
}

std::expected<std::vector<EchoAreaConfig>, ParseError> ConfigManager::GetConfig() const {
  std::shared_lock lock(config_mutex_);
  return ParseConfig();
}

void ConfigManager::UpdateConfigPath(std::string new_path) {
  std::unique_lock lock(config_mutex_);
  config_path_ = std::move(new_path);
  spdlog::info("Config path updated to: {}", config_path_);
}

std::string ConfigManager::GetConfigPath() const {
  std::shared_lock lock(config_mutex_);
  return config_path_;
}

std::expected<std::vector<EchoAreaConfig>, ParseError> ConfigManager::ParseConfig() const {
  std::ifstream file(config_path_);
  if (!file.is_open()) {
    spdlog::error("Failed to open config file: {}", config_path_);
    return std::unexpected(ParseError::kFileOpenError);
  }

  std::vector<EchoAreaConfig> configs;
  EchoAreaConfig defaults;
  // FidoConfig uses Squish when no -b/default is given. Never infer JAM from a name.
  defaults.msgbase_type = "Squish";
  std::set<std::string> names;
  std::string line;
  size_t conditional_depth = 0;
  auto options = [](const std::vector<std::string_view>& tokens, size_t first,
                    EchoAreaConfig& area) -> std::expected<void, ParseError> {
    std::set<std::string> seen;
    for (size_t i = first; i < tokens.size(); ++i) {
      const auto option = Lower(tokens[i]);
      if (option == "-pass") {
        area.is_passthrough = true;
        continue;
      }
      if (option != "-b" && option != "-lr" && option != "-lw" && option != "-d" && option != "-g" && option != "-a" &&
          option != "-dupecheck" && option != "-dupehistory" && option != "-$m" && option != "-scan") {
        if (option.starts_with('-'))
          return std::unexpected(ParseError::kUnknownOption);
        continue;  // FTN uplink addresses do not grant application identity.
      }
      if (!seen.insert(option).second)
        return std::unexpected(ParseError::kDuplicateOption);
      if (++i == tokens.size() || tokens[i].empty() || tokens[i].starts_with('-'))
        return std::unexpected(ParseError::kInvalidFormat);
      if (option == "-b") {
        const auto type = Lower(tokens[i]);
        if (type == "jam")
          area.msgbase_type = "JAM";
        else if (type == "squish")
          area.msgbase_type = "Squish";
        else if (type == "msg")
          area.msgbase_type = "MSG";
        else
          return std::unexpected(ParseError::kInvalidValue);
      } else if (option == "-dupecheck") {
        const auto mode = Lower(tokens[i]);
        if (mode != "off" && mode != "move" && mode != "del")
          return std::unexpected(ParseError::kInvalidValue);
      } else if (option == "-scan") {
        const auto mode = Lower(tokens[i]);
        if (mode != "listed" && mode != "manual" && mode != "never")
          return std::unexpected(ParseError::kInvalidValue);
      } else if (option == "-lr" || option == "-lw" || option == "-dupehistory" || option == "-$m") {
        auto value = ParseUint32(tokens[i]);
        if (!value)
          return std::unexpected(ParseError::kInvalidValue);
        if (option == "-lr")
          area.access_levels.read = *value;
        else if (option == "-lw")
          area.access_levels.write = *value;
        else if (option == "-$m")
          area.purge_settings.max_messages = *value;
      } else if (option == "-d")
        area.description = tokens[i];
      else if (option == "-g")
        area.group = tokens[i];
      else
        area.aka = tokens[i];
    }
    return {};
  };
  while (std::getline(file, line)) {
    if (line.size() > 65536 || line.find('\0') != std::string::npos)
      return std::unexpected(ParseError::kInvalidFormat);
    const auto trimmed = TrimWhitespace(line);
    const auto keyword = Lower(trimmed.substr(0, trimmed.find_first_of(" \t\r")));
    if (keyword.empty() || keyword.starts_with('#'))
      continue;
    if (keyword == "if" || keyword == "ifdef" || keyword == "ifndef") {
      ++conditional_depth;
      continue;
    }
    if (keyword == "endif") {
      if (conditional_depth == 0)
        return std::unexpected(ParseError::kInvalidFormat);
      --conditional_depth;
      continue;
    }
    // Resolving HPT include/conditional/macro semantics is not safe by guessing.
    if (keyword == "include")
      return std::unexpected(ParseError::kUnknownOption);
    if (keyword != "echoarea" && keyword != "echoareadefaults")
      continue;
    if (conditional_depth != 0)
      return std::unexpected(ParseError::kUnknownOption);
    auto parsed = Tokens(line);
    if (!parsed)
      return std::unexpected(parsed.error());
    const auto& tokens = *parsed;
    if (keyword == "echoareadefaults") {
      if (auto result = options(tokens, 1, defaults); !result)
        return std::unexpected(result.error());
      continue;
    }
    if (tokens.size() < 3 || tokens[1].empty() || tokens[2].empty() || tokens[1].starts_with('-') ||
        tokens[2].starts_with('-') || tokens[2].find_first_of("$%[]") != std::string_view::npos)
      return std::unexpected(ParseError::kInvalidFormat);
    if (!names.insert(Lower(tokens[1])).second)
      return std::unexpected(ParseError::kDuplicateOption);
    auto area = defaults;
    area.name = tokens[1];
    area.filename = tokens[2];
    area.is_passthrough = defaults.is_passthrough || Lower(area.filename) == "passthrough";
    if (auto result = options(tokens, 3, area); !result)
      return std::unexpected(result.error());
    configs.push_back(std::move(area));
  }
  if (file.bad())
    return std::unexpected(ParseError::kFileOpenError);
  if (conditional_depth != 0)
    return std::unexpected(ParseError::kInvalidFormat);
  return configs;
}

std::string_view ConfigManager::TrimWhitespace(std::string_view str) {
  constexpr std::string_view kWhitespace = " \t\r";
  const auto start = str.find_first_not_of(kWhitespace);
  if (start == std::string_view::npos)
    return "";
  const auto end = str.find_last_not_of(kWhitespace);
  return str.substr(start, end - start + 1);
}

std::optional<uint32_t> ConfigManager::ParseUint32(std::string_view str) {
  uint32_t value = 0;
  auto [ptr, ec] = std::from_chars(str.data(), str.data() + str.size(), value);
  if (ec != std::errc{} || ptr != str.data() + str.size()) {
    return std::nullopt;
  }
  return value;
}

// JSON conversion methods
nlohmann::json EchoAreaConfig::LinkOptions::ToJson() const {
  nlohmann::json j;
  j["is_default"] = is_default;
  j["read_only"] = read_only;
  j["write_only"] = write_only;
  j["mandatory"] = mandatory;
  return j;
}

nlohmann::json EchoAreaConfig::AccessLevels::ToJson() const {
  nlohmann::json j;
  if (read)
    j["read"] = *read;
  if (write)
    j["write"] = *write;
  return j;
}

nlohmann::json EchoAreaConfig::PurgeSettings::ToJson() const {
  nlohmann::json j;
  if (after_days)
    j["after_days"] = *after_days;
  if (max_messages)
    j["max_messages"] = *max_messages;
  j["enabled"] = enabled;
  j["kill_read"] = kill_read;
  j["keep_unread"] = keep_unread;
  return j;
}

nlohmann::json EchoAreaConfig::MsgBaseSettings::ToJson() const {
  // Json::Value json;
  nlohmann::json j;
  j["keep_seen_by"] = keep_seen_by;
  j["tiny_seen_by"] = tiny_seen_by;
  j["kill_seen_by"] = kill_seen_by;
  j["dos_filename"] = dos_filename;
  return j;
}

#include <nlohmann/json.hpp>

nlohmann::json EchoAreaConfig::ToJson() const {
  nlohmann::json json;
  json["name"] = name;
  json["filename"] = filename;
  json["is_passthrough"] = is_passthrough;

  if (msgbase_type)
    json["msgbase_type"] = *msgbase_type;
  if (group)
    json["group"] = *group;
  if (description)
    json["description"] = *description;
  if (aka)
    json["aka"] = *aka;

  json["access_levels"] = access_levels.ToJson();
  json["purge_settings"] = purge_settings.ToJson();
  json["msgbase_settings"] = msgbase_settings.ToJson();

  json["mandatory"] = mandatory;
  json["manual_subscribe"] = manual_subscribe;
  json["hidden"] = hidden;
  json["pauseable"] = pauseable;
  json["carbon_copy"] = carbon_copy;
  json["reply_linking"] = reply_linking;
  json["debug"] = debug;

  // Convert link_akas array
  json["link_akas"] = nlohmann::json::array();
  for (const auto& aka : link_akas) {
    json["link_akas"].push_back(aka);
  }

  // Convert link_options array
  json["link_options"] = nlohmann::json::array();
  for (const auto& option : link_options) {
    json["link_options"].push_back(option.ToJson());
  }

  return json;
}
