#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>

#include "../support/temp_directory.hpp"
#include "EchoAreaConfig.h"

namespace fs = std::filesystem;

TEST(ConfigManager, ParseEmptyFile) {
  fidoback::test::TempDirectory temp;
  fs::path tmp = temp.path() / "fidoback_test_empty.cfg";
  {
    std::ofstream ofs(tmp);
    ofs << "# Empty config\n";
    ofs << "\n";
  }

  ConfigManager mgr(tmp.string());
  auto result = mgr.GetConfig();
  ASSERT_TRUE(result);
  EXPECT_TRUE(result->empty());
}

TEST(ConfigManager, ParseBasicEchoArea) {
  fidoback::test::TempDirectory temp;
  fs::path tmp = temp.path() / "fidoback_test_basic.cfg";
  {
    std::ofstream ofs(tmp);
    ofs << "EchoArea comp.lang.dart Passthrough\n";
  }

  ConfigManager mgr(tmp.string());
  auto result = mgr.GetConfig();
  ASSERT_TRUE(result);
  ASSERT_EQ(result->size(), 1);
  EXPECT_EQ((*result)[0].name, "comp.lang.dart");
  EXPECT_EQ((*result)[0].is_passthrough, true);
}

TEST(ConfigManager, ParseWithMsgBaseType) {
  fidoback::test::TempDirectory temp;
  fs::path tmp = temp.path() / "fidoback_test_msgbase.cfg";
  {
    std::ofstream ofs(tmp);
    ofs << "EchoArea ru.fido JAM -b JAM\n";
  }

  ConfigManager mgr(tmp.string());
  auto result = mgr.GetConfig();
  ASSERT_TRUE(result);
  ASSERT_EQ(result->size(), 1);
  EXPECT_EQ((*result)[0].name, "ru.fido");
  ASSERT_TRUE((*result)[0].msgbase_type.has_value());
  EXPECT_EQ((*result)[0].msgbase_type.value(), "JAM");
}

TEST(ConfigManager, SkipCommentsAndBlankLines) {
  fidoback::test::TempDirectory temp;
  fs::path tmp = temp.path() / "fidoback_test_comments.cfg";
  {
    std::ofstream ofs(tmp);
    ofs << "# Comment line\n";
    ofs << "\n";
    ofs << "   \n";
    ofs << "EchoArea test.echo Passthrough\n";
    ofs << "# Another comment\n";
  }

  ConfigManager mgr(tmp.string());
  auto result = mgr.GetConfig();
  ASSERT_TRUE(result);
  EXPECT_EQ(result->size(), 1);
}

TEST(EchoAreaConfig, ToJson) {
  EchoAreaConfig config;
  config.name = "test.area";
  config.filename = "test";
  config.is_passthrough = false;
  config.description = "Test area";

  auto json = config.ToJson();
  EXPECT_EQ(json["name"], "test.area");
  EXPECT_EQ(json["description"], "Test area");
  EXPECT_EQ(json["is_passthrough"], false);
}

namespace {
auto ParseFixture(std::string_view text) {
  fidoback::test::TempDirectory temp;
  const auto path = temp.path() / "areas.cfg";
  {
    std::ofstream file(path);
    file << text;
  }
  return ConfigManager(path.string()).GetConfig();
}
}  // namespace

TEST(ConfigManager, TabsCaseFilenameAndQuotedDescription) {
  auto result =
      ParseFixture("echoarea\tRU.TEST\tstorage/test\t-b\tjam\t-lr\t12\t-lw\t7\t-d \"Русское описание\" # comment\r\n");
  ASSERT_TRUE(result);
  ASSERT_EQ(result->size(), 1);
  const auto& area = result->front();
  EXPECT_EQ(area.name, "RU.TEST");
  EXPECT_EQ(area.filename, "storage/test");
  EXPECT_EQ(area.msgbase_type, "JAM");
  EXPECT_EQ(area.access_levels.read, 12);
  EXPECT_EQ(area.access_levels.write, 7);
  EXPECT_EQ(area.description, "Русское описание");
}

TEST(ConfigManager, DefaultsAreNotAreasAndDoNotInferJam) {
  auto result = ParseFixture("EchoArea A file\nEchoAreaDefaults -b JAM -lr 4\nEchoArea B second\nEchoArea C third -b "
                             "Squish\nEchoAreaDefaults -pass\nEchoArea D fourth\n");
  ASSERT_TRUE(result);
  ASSERT_EQ(result->size(), 4);
  EXPECT_EQ((*result)[0].msgbase_type, "Squish");
  EXPECT_EQ((*result)[1].msgbase_type, "JAM");
  EXPECT_EQ((*result)[1].access_levels.read, 4);
  EXPECT_EQ((*result)[2].msgbase_type, "Squish");
  EXPECT_TRUE((*result)[3].is_passthrough);
}

TEST(ConfigManager, MalformedAreaFailsWholeConfiguration) {
  for (auto invalid :
       {"EchoArea", "EchoArea name", "EchoArea name -b JAM", "EchoArea name file -b", "EchoArea name file -b unknown",
        "EchoArea name file -lr abc", "EchoArea name file -lw 4294967296", "EchoArea name file -lr",
        "EchoArea name file -unknown", "EchoArea name file -dupeCheck invalid", "EchoArea name file -dupeHistory abc",
        "EchoArea name file -b JAM -b Squish", "EchoArea name \"unterminated", "EchoArea name file -d \"text\"suffix",
        "EchoArea name $BASE/file", "EchoArea \"\" file"}) {
    SCOPED_TRACE(invalid);
    auto result = ParseFixture(std::string("EchoArea valid safe -b JAM\n") + invalid + "\n");
    EXPECT_FALSE(result);
  }
}

TEST(ConfigManager, DuplicateNamesAndUnsupportedPreprocessingFailClosed) {
  for (auto text : {"EchoArea a file -b JAM\nEchoArea A other -b JAM\n", "Include areas.cfg\n",
                    "if condition\nEchoArea a file -b JAM\nendif\n", "if condition\nEchoAreaDefaults -b JAM\nendif\n",
                    "endif\n", "if condition\n"}) {
    SCOPED_TRACE(text);
    EXPECT_FALSE(ParseFixture(text));
  }
  auto result = ParseFixture("if arbitrary \"HPT\"==\"syntax\"\nSysop name\nendif\nEchoArea a file -b JAM\n");
  ASSERT_TRUE(result);
  ASSERT_EQ(result->size(), 1);
}

TEST(ConfigManager, PassthroughAndOtherHptOptions) {
  auto result = ParseFixture("EchoArea A passthrough -b JAM\nEchoArea B file -b MSG -g group -a 2:5020/1 -dupeHistory "
                             "30 -dupeCheck move -$m 1000 -scan listed\nEchoArea C third -b JAM -pass\n");
  ASSERT_TRUE(result);
  ASSERT_EQ(result->size(), 3);
  EXPECT_TRUE((*result)[0].is_passthrough);
  EXPECT_EQ((*result)[1].msgbase_type, "MSG");
  EXPECT_EQ((*result)[1].group, "group");
  EXPECT_EQ((*result)[1].aka, "2:5020/1");
  EXPECT_EQ((*result)[1].purge_settings.max_messages, 1000);
  EXPECT_TRUE((*result)[2].is_passthrough);
}

TEST(ConfigManager, OversizedAndNulConfigFailClosed) {
  EXPECT_FALSE(ParseFixture(std::string(65537, 'x')));
  EXPECT_FALSE(ParseFixture(std::string("EchoArea a file\0 -b JAM", 23)));
}
