#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>

#include "../support/temp_directory.hpp"
#include "AppConfig.h"

namespace fs = std::filesystem;

TEST(AppConfig, DefaultConfigHasReasonableValues) {
  auto cfg = DefaultConfig();
  EXPECT_EQ(cfg.server.ip, "0.0.0.0");
  EXPECT_EQ(cfg.server.port, 8080);
  EXPECT_EQ(cfg.server.thread_num, 8);
  EXPECT_TRUE(cfg.server.tls_private_key.empty());
  EXPECT_EQ(cfg.ftn.default_encoding, "cp866");
}

TEST(AppConfig, LoadEmptyPathReturnsDefaults) {
  auto result = LoadAppConfig("");
  ASSERT_TRUE(result);
  auto cfg = *result;
  EXPECT_EQ(cfg.server.port, 8080);
  EXPECT_TRUE(cfg.server.tls_private_key.empty());
}

TEST(AppConfig, LoadNonexistentFileReturnsError) {
  auto result = LoadAppConfig("/nonexistent/path/config.json");
  ASSERT_FALSE(result);
  EXPECT_EQ(result.error(), ConfigError::kFileNotFound);
}

TEST(AppConfig, ParseValidJsonOverrides) {
  nlohmann::json j = {
      {"server", {{"port", 9090}, {"thread_num", 16}}},
      {"ftn", {{"areacfg_path", "/tmp/test.cfg"}, {"jam_base_path", "/tmp/msg/"}}},
  };

  auto result = ParseAppConfig(j);
  ASSERT_TRUE(result);

  EXPECT_EQ(result->server.port, 9090);
  EXPECT_EQ(result->server.thread_num, 16);
  EXPECT_EQ(result->ftn.areacfg_path, "/tmp/test.cfg");
  EXPECT_EQ(result->ftn.jam_base_path, "/tmp/msg/");
}

TEST(AppConfig, ParseMinimalJson) {
  nlohmann::json j = {
      {"server", {{"port", 3000}}},
  };

  auto result = ParseAppConfig(j);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->server.port, 3000);
  // Defaults for everything else
  EXPECT_EQ(result->server.ip, "0.0.0.0");
  EXPECT_EQ(result->server.thread_num, 8);
}

TEST(AppConfig, LoadFromFile) {
  fidoback::test::TempDirectory temp;
  fs::path tmp = temp.path() / "fidoback_test_config.json";
  {
    std::ofstream ofs(tmp);
    ofs << R"({
      "server": {"port": 7777, "ip": "127.0.0.1"}
    })";
  }

  auto result = LoadAppConfig(tmp.string());
  ASSERT_TRUE(result);
  EXPECT_EQ(result->server.port, 7777);
  EXPECT_EQ(result->server.ip, "127.0.0.1");
}

TEST(AppConfig, InvalidPortReturnsError) {
  nlohmann::json j = {
      {"server", {{"port", 0}}},
  };

  auto result = ParseAppConfig(j);
  ASSERT_FALSE(result);
  EXPECT_EQ(result.error(), ConfigError::kInvalidValue);
}

TEST(AppConfig, ZeroThreadCountReturnsError) {
  nlohmann::json j = {
      {"server", {{"thread_num", 0}}},
  };

  auto result = ParseAppConfig(j);
  ASSERT_FALSE(result);
  EXPECT_EQ(result.error(), ConfigError::kInvalidValue);
}

TEST(AppConfig, RejectsPortBeforeNarrowing) {
  for (auto value : {nlohmann::json(-1), nlohmann::json(65536), nlohmann::json(131073), nlohmann::json(1.5),
                     nlohmann::json("8080")}) {
    auto result = ParseAppConfig({{"server", {{"port", value}}}});
    ASSERT_FALSE(result);
    EXPECT_EQ(result.error(), ConfigError::kInvalidValue);
  }
  for (auto port : {1, 65535}) {
    auto result = ParseAppConfig({{"server", {{"port", port}}}});
    ASSERT_TRUE(result);
    EXPECT_EQ(result->server.port, port);
  }
}

TEST(AppConfig, ValidatesDefaultEncodingAndTypes) {
  for (auto encoding : {std::string(""), std::string("not-an-encoding"), std::string("UTF-8\0hidden", 12)}) {
    EXPECT_FALSE(ParseAppConfig({{"ftn", {{"default_encoding", encoding}}}}));
  }
  for (auto encoding : {"cp866", "KOI8-R", "UTF-8"}) {
    EXPECT_TRUE(ParseAppConfig({{"ftn", {{"default_encoding", encoding}}}}));
  }
  EXPECT_FALSE(ParseAppConfig(nlohmann::json::array()));
  EXPECT_FALSE(ParseAppConfig({{"server", "invalid"}}));
  EXPECT_FALSE(ParseAppConfig({{"ftn", {{"default_encoding", 123}}}}));
}

TEST(AppConfig, RelativePathsUseConfigurationDirectory) {
  fidoback::test::TempDirectory temporary;
  const auto path = temporary.path() / "config.json";
  {
    std::ofstream output(path);
    output
        << R"({"ftn":{"coordination_lock":"data/hpt.lock"},"server":{"tls_certificate":"cert.pem","tls_private_key":"key.pem"}})";
  }
  auto result = LoadAppConfig(path.string());
  ASSERT_TRUE(result);
  EXPECT_EQ(result->ftn.coordination_lock, temporary.path() / "data/hpt.lock");
  EXPECT_EQ(result->server.tls_certificate, (temporary.path() / "cert.pem").string());
  EXPECT_EQ(result->database.metadata_path, temporary.path() / "data/metadata.db");
  EXPECT_EQ(result->ftn.jam_base_path, (temporary.path() / "ftn/jam").string());
}
TEST(AppConfig, RejectsLegacyJwtAndOutOfRangeResourceSettings) {
  EXPECT_FALSE(ParseAppConfig({{"jwt", {{"secret", "unused"}}}}));
  for (auto value : {-1, 0, 257})
    EXPECT_FALSE(ParseAppConfig({{"server", {{"thread_num", value}}}}));
  for (auto value : {-1, 0, 60001})
    EXPECT_FALSE(ParseAppConfig({{"server", {{"rpc_timeout_ms", value}}}}));
  for (auto value : {nlohmann::json(1.5), nlohmann::json("8"), nlohmann::json(UINT64_MAX)})
    EXPECT_FALSE(ParseAppConfig({{"server", {{"thread_num", value}}}}));
}

TEST(AppConfig, EverySectionAndStringBoundaryFailsClosed) {
  for (const auto* section : {"server", "ftn", "database", "logging"}) {
    for (const auto& wrong : {nlohmann::json::array(), nlohmann::json(12), nlohmann::json(nullptr)}) {
      EXPECT_FALSE(ParseAppConfig({{section, wrong}}));
    }
  }
  for (const auto* key : {"ip", "tls_certificate", "tls_private_key"}) {
    EXPECT_FALSE(ParseAppConfig({{"server", {{key, std::string("a\0b", 3)}}}}));
  }
  EXPECT_FALSE(ParseAppConfig({{"server", {{"ip", ""}}}}));
  for (const auto* key : {"areacfg_path", "jam_base_path"}) {
    EXPECT_FALSE(ParseAppConfig({{"ftn", {{key, ""}}}}));
    EXPECT_FALSE(ParseAppConfig({{"ftn", {{key, std::string("a\0b", 3)}}}}));
  }
  EXPECT_FALSE(ParseAppConfig({{"ftn", {{"coordination_lock", std::string("a\0b", 3)}}}}));
  EXPECT_FALSE(ParseAppConfig({{"ftn", {{"default_encoding", std::string(65, 'a')}}}}));
  EXPECT_FALSE(ParseAppConfig({{"ftn", {{"default_encoding", "UTF-8//IGNORE"}}}}));
  EXPECT_FALSE(ParseAppConfig({{"database", {{"metadata_path", std::string("a\0b", 3)}}}}));
  EXPECT_TRUE(ParseAppConfig({{"database", {{"metadata_path", ""}}}}));
  EXPECT_TRUE(ParseAppConfig({{"logging", {{"level", "debug"}}}}));
  for (const auto value : {-1, 0, 60001})
    EXPECT_FALSE(ParseAppConfig({{"server", {{"shutdown_timeout_ms", value}}}}));
  EXPECT_FALSE(ParseAppConfig({{"server", {{"thread_num", INT64_MAX}}}}));
  EXPECT_FALSE(ParseAppConfig({{"server", {{"thread_num", INT64_MIN}}}}));
  EXPECT_FALSE(ParseAppConfig({{"server", {{"port", UINT64_MAX}}}}));
}

TEST(AppConfig, InvalidJsonAndInvalidParsedConfigurationHaveDifferentErrors) {
  fidoback::test::TempDirectory temporary;
  auto path = temporary.path() / "config.json";
  {
    std::ofstream output(path);
    output << "{not-json";
  }
  auto malformed = LoadAppConfig(path.string());
  ASSERT_FALSE(malformed);
  EXPECT_EQ(malformed.error(), ConfigError::kParseError);
  {
    std::ofstream output(path);
    output << R"({"server":{"port":0}})";
  }
  auto invalid = LoadAppConfig(path.string());
  ASSERT_FALSE(invalid);
  EXPECT_EQ(invalid.error(), ConfigError::kInvalidValue);
}

TEST(AppConfig, ResourceIntegersRejectNarrowingBeforeValidation) {
  for (const auto* key : {"rpc_timeout_ms", "shutdown_timeout_ms"}) {
    for (const auto value : {INT64_MIN, INT64_MAX})
      EXPECT_FALSE(ParseAppConfig({{"server", {{key, value}}}}));
  }
}

TEST(AppConfig, AuthPathsAreValidatedAndResolvedWithoutReadingSecrets) {
  for (const auto& wrong : {nlohmann::json(nullptr), nlohmann::json::array(), nlohmann::json(1)})
    EXPECT_FALSE(ParseAppConfig({{"auth", wrong}}));
  EXPECT_FALSE(ParseAppConfig({{"auth", {{"hpt_config_path", ""}, {"session_key_path", "key"}}}}));
  EXPECT_FALSE(ParseAppConfig({{"auth", {{"hpt_config_path", "config"}}}}));
  EXPECT_FALSE(ParseAppConfig({{"auth", {{"hpt_config_path", std::string("a\0b", 3)}, {"session_key_path", "key"}}}}));
  fidoback::test::TempDirectory temp;
  std::ofstream(temp.path() / "config.json")
      << R"({"auth":{"hpt_config_path":"hpt/config","session_key_path":"data/key"}})";
  const auto config = LoadAppConfig((temp.path() / "config.json").string());
  ASSERT_TRUE(config);
  EXPECT_EQ(config->auth.hpt_config_path, temp.path() / "hpt/config");
  EXPECT_EQ(config->auth.session_key_path, temp.path() / "data/key");
}

TEST(AppConfig, ExplicitOwnersAreCanonicalAndUnique) {
  nlohmann::json j = {{"auth", {{"hpt_config_path", "/tmp/hpt"}, {"session_key_path", "/tmp/key"}}}};
  ASSERT_TRUE(ParseAppConfig(j));
  EXPECT_TRUE(ParseAppConfig(j)->auth.owner_addresses.empty());
  j["auth"]["owner_addresses"] = {"02:001/002.1", "2:1/3"};
  ASSERT_TRUE(ParseAppConfig(j));
  EXPECT_EQ(ParseAppConfig(j)->auth.owner_addresses[0], "2:1/2.1");
  for (const auto& owners : {nlohmann::json{"2:1/2", "02:001/002.0"}, nlohmann::json{"invalid"},
                             nlohmann::json("2:1/2"), nlohmann::json{42}}) {
    j["auth"]["owner_addresses"] = owners;
    EXPECT_FALSE(ParseAppConfig(j));
  }
}

TEST(AppConfig, PointMailIsDisabledAndRejectsAmbiguousOrEscapingBindings) {
  EXPECT_FALSE(DefaultConfig().point_mail.enabled);
  nlohmann::json document = {
      {"ftn", {{"coordination_lock", "lock"}}},
      {"point_mail",
       {{"enabled", true},
        {"ingress_areas", {"IN"}},
        {"egress_area", "OUT"},
        {"points", nlohmann::json::array({{{"address", "02:001/002.1"}, {"jam_base", "points/p1"}}})}}}};
  auto parsed = ParseAppConfig(document);
  ASSERT_TRUE(parsed);
  EXPECT_EQ(parsed->point_mail.points.front().address, "2:1/2.1");
  const auto original = document;
  for (auto path : {"../mail", "/tmp/mail", "points/../mail", "./mail", ""}) {
    document = original;
    document["point_mail"]["points"][0]["jam_base"] = path;
    EXPECT_FALSE(ParseAppConfig(document)) << path;
  }
  document = original;
  document["point_mail"]["points"].push_back(document["point_mail"]["points"][0]);
  EXPECT_FALSE(ParseAppConfig(document));
  document = original;
  document["point_mail"]["egress_area"] = "in";
  EXPECT_FALSE(ParseAppConfig(document));
  document = original;
  document["point_mail"]["points"][0]["address"] = "2:1/2";
  EXPECT_FALSE(ParseAppConfig(document));
}

TEST(AppConfig, UueLimitsAreBoundedAndConsistent) {
  auto defaults = ParseAppConfig(nlohmann::json::object());
  ASSERT_TRUE(defaults);
  EXPECT_EQ(defaults->uue.max_file_bytes, 1048576);
  for (auto field : {"max_file_bytes", "part_body_bytes", "max_parts", "chunk_bytes", "user_quota_bytes",
                     "global_quota_bytes", "upload_ttl_seconds", "preview_pixels", "preview_dimension"}) {
    EXPECT_FALSE(ParseAppConfig({{"uue", {{field, -1}}}}));
    EXPECT_FALSE(ParseAppConfig({{"uue", {{field, 0}}}}));
  }
  EXPECT_FALSE(ParseAppConfig({{"uue", {{"chunk_bytes", 65537}}}}));
  EXPECT_FALSE(ParseAppConfig({{"uue", {{"max_parts", 1}}}}));
  EXPECT_TRUE(ParseAppConfig({{"uue", {{"part_body_bytes", 16384}}}}));
}

TEST(AppConfig, PathMappingsValidateAndNormalize) {
  using nlohmann::json;
  EXPECT_TRUE(ParseAppConfig(json::object())->ftn.path_mappings.empty());
  EXPECT_TRUE(ParseAppConfig({{"ftn", {{"path_mappings", json::array()}}}})->ftn.path_mappings.empty());
  const auto valid = json::array({{{"from", "/container//"}, {"to", "/host/"}}});
  auto config = ParseAppConfig({{"ftn", {{"path_mappings", valid}}}});
  ASSERT_TRUE(config);
  ASSERT_EQ(config->ftn.path_mappings.size(), 1);
  EXPECT_EQ(config->ftn.path_mappings.front().from, "/container");
  for (const auto& rules :
       {json(nullptr), json(1), json::object(), json::array({1}), json::array({{{"from", "/a"}}}),
        json::array({{{"from", "relative"}, {"to", "/b"}}}), json::array({{{"from", "/a"}, {"to", "/b/../c"}}}),
        json::array({{{"from", "/a/."}, {"to", "/b"}}}), json::array({{{"from", ""}, {"to", "/b"}}}),
        json::array({{{"from", std::string("/a\0b", 4)}, {"to", "/b"}}}),
        json::array({{{"from", "/a"}, {"to", "/b"}}, {{"from", "/a/"}, {"to", "/c"}}})}) {
    EXPECT_FALSE(ParseAppConfig({{"ftn", {{"path_mappings", rules}}}})) << rules;
  }
}

TEST(PathMapping, LongestComponentPrefixAppliesOnce) {
  using namespace fidoback::ftn;
  auto rules = ValidateMappings(
      std::vector<PathMapping>{{"/container", "/host"}, {"/container/jam", "/special"}, {"/special", "/wrong"}});
  ASSERT_TRUE(rules);
  EXPECT_EQ(*MapPath("/container/jam/ru.test", *rules), "/special/ru.test");
  EXPECT_EQ(*MapPath("/container/links.cfg", *rules), "/host/links.cfg");
  EXPECT_EQ(*MapPath("/container-other/jam", *rules), "/container-other/jam");
  EXPECT_EQ(*MapPath("/container", *rules), "/host");
  EXPECT_EQ(*MapPath("/container//jam/ru.test", *rules), "/special/ru.test");
  EXPECT_EQ(*MapPath("/container/./jam/ru.test", *rules), "/special/ru.test");
  std::reverse(rules->begin(), rules->end());
  EXPECT_EQ(*MapPath("/container/jam/ru.test", *rules), "/special/ru.test");
  EXPECT_FALSE(MapPath("/container/jam/../escape", *rules));
  EXPECT_FALSE(MapPath("relative", *rules));
}

TEST(AppConfig, JamEncodingOverridesValidatePathsAndCodecs) {
  using nlohmann::json;
  ASSERT_TRUE(ParseAppConfig(json::object())->ftn.jam_encoding_overrides.empty());
  auto config =
      ParseAppConfig({{"ftn", {{"jam_encoding_overrides", {{"nested/echo", "koi8-r"}, {"utf-8", "UTF-8"}}}}}});
  ASSERT_TRUE(config);
  EXPECT_EQ(config->ftn.jam_encoding_overrides.at("nested/echo"), "KOI8-R");
  for (const auto& rules :
       {json(nullptr), json::array(), json(5), json{{"echo", 1}}, json{{"echo", "unknown-codec"}},
        json{{"echo", "UTF-8//IGNORE"}}, json{{"echo", ""}}, json{{"echo", std::string("KOI8-R\0x", 8)}}})
    EXPECT_FALSE(ParseAppConfig({{"ftn", {{"jam_encoding_overrides", rules}}}})) << rules;
  for (auto path : {"", "/echo", "../echo", "x/../echo", "./echo", "x//echo", "echo/"})
    EXPECT_FALSE(ParseAppConfig({{"ftn", {{"jam_encoding_overrides", {{path, "KOI8-R"}}}}}})) << path;
  EXPECT_FALSE(ParseAppConfig({{"ftn", {{"jam_encoding_overrides", {{std::string("a\0b", 3), "KOI8-R"}}}}}}));
}
