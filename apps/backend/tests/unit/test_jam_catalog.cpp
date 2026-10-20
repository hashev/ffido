#include <fcntl.h>
#include <gtest/gtest.h>
#include <unistd.h>

#include <fstream>

#include "../support/temp_directory.hpp"
#include "storage/jam_catalog.hpp"

using namespace fidoback::storage;
namespace fs = std::filesystem;
namespace {
EchoAreaConfig Area(std::string id, std::string filename, std::string type = "JAM") {
  EchoAreaConfig result;
  result.name = std::move(id);
  result.filename = std::move(filename);
  result.msgbase_type = std::move(type);
  return result;
}
void Files(const fs::path& base) {
  fs::create_directories(base.parent_path());
  for (auto extension : {".jhr", ".jdt", ".jdx"}) {
    std::ofstream file(base.string() + extension);
    file << "fixture";
  }
}
}  // namespace

TEST(JamCatalog, MapsIdToFilenameAndOpenedInode) {
  fidoback::test::TempDirectory temporary;
  Files(temporary.path() / "nested/file");
  auto result = JamCatalog::Build(temporary.path(), {Area("RU.TEST", "nested/file")});
  ASSERT_TRUE(result);
  auto area = (*result)->Resolve("RU.TEST");
  ASSERT_TRUE(area);
  struct stat actual{};
  ASSERT_EQ(stat((temporary.path() / "nested/file.jhr").c_str(), &actual), 0);
  EXPECT_EQ((*area)->files->identities[0].st_ino, actual.st_ino);
  char bytes[7];
  EXPECT_EQ(pread((*area)->files->descriptors[0], bytes, sizeof(bytes), 0), 7);
  EXPECT_EQ(std::string(bytes, sizeof(bytes)), "fixture");
  EXPECT_FALSE((*result)->Resolve("nested/file"));
  EXPECT_FALSE((*result)->Resolve("../outside"));
  EXPECT_FALSE((*result)->Resolve(std::string_view("RU.TEST\0extra", 13)));
}

TEST(JamCatalog, RejectsTraversalMissingAndSymlinkFiles) {
  fidoback::test::TempDirectory temporary;
  const auto root = temporary.path() / "root";
  fs::create_directory(root);
  Files(temporary.path() / "outside");
  for (auto filename : {"../outside", "a/../../outside", "missing", "./missing"}) {
    EXPECT_FALSE(JamCatalog::Build(root, {Area("A", filename)}));
  }
  EXPECT_FALSE(JamCatalog::Build(root, {Area("A", (temporary.path() / "outside").string())}));
  for (auto extension : {".jhr", ".jdt", ".jdx"})
    fs::create_symlink(temporary.path() / (std::string("outside") + extension),
                       root / (std::string("link") + extension));
  EXPECT_FALSE(JamCatalog::Build(root, {Area("A", "link")}));
  fs::create_directory_symlink(temporary.path(), root / "escape");
  EXPECT_FALSE(JamCatalog::Build(root, {Area("A", "escape/outside")}));
  EXPECT_FALSE(JamCatalog::Build(root / "missing", {}));
}

TEST(JamCatalog, IgnoresUnsupportedTypesAndPassthrough) {
  fidoback::test::TempDirectory temporary;
  auto pass = Area("P", "anything");
  pass.is_passthrough = true;
  auto result =
      JamCatalog::Build(temporary.path(), {pass, Area("S", "anything", "Squish"), Area("M", "anything", "MSG")});
  ASSERT_TRUE(result);
  EXPECT_TRUE((*result)->areas().empty());
}

TEST(JamCatalog, DetectsReplacementAndDirectorySymlinkRace) {
  fidoback::test::TempDirectory temporary;
  Files(temporary.path() / "nested/base");
  Files(temporary.path() / "foreign/base");
  auto result = JamCatalog::Build(temporary.path(), {Area("A", "nested/base")});
  ASSERT_TRUE(result);
  auto initial = (*result)->Resolve("A");
  ASSERT_TRUE(initial);
  fs::rename(temporary.path() / "nested", temporary.path() / "saved");
  fs::create_directory_symlink(temporary.path() / "foreign", temporary.path() / "nested");
  auto replaced = (*result)->Resolve("A");
  ASSERT_FALSE(replaced);
  EXPECT_EQ(replaced.error(), CatalogError::kChangedBase);
  // The held fd still identifies the original authorized inode, never the symlink target.
  struct stat original{};
  ASSERT_EQ(stat((temporary.path() / "saved/base.jhr").c_str(), &original), 0);
  EXPECT_EQ((*initial)->files->identities[0].st_ino, original.st_ino);
}

TEST(JamCatalog, AliasesShareOwnerAndRejectDifferentCompanions) {
  fidoback::test::TempDirectory temporary;
  Files(temporary.path() / "base");
  for (auto extension : {".jhr", ".jdt", ".jdx"})
    fs::create_hard_link(temporary.path() / (std::string("base") + extension),
                         temporary.path() / (std::string("alias") + extension));
  auto result = JamCatalog::Build(temporary.path(), {Area("A", "base"), Area("B", "alias")});
  ASSERT_TRUE(result);
  auto a = (*result)->Resolve("A");
  auto b = (*result)->Resolve("B");
  ASSERT_TRUE(a);
  ASSERT_TRUE(b);
  EXPECT_EQ((*a)->files, (*b)->files);
  fs::remove(temporary.path() / "alias.jdx");
  {
    std::ofstream file(temporary.path() / "alias.jdx");
  }
  EXPECT_FALSE((*result)->Resolve("B"));
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area("A", "base"), Area("B", "alias")}));
}

TEST(JamCatalog, RejectsDuplicateEmptyAndNonregularConfiguration) {
  fidoback::test::TempDirectory temporary;
  Files(temporary.path() / "base");
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area("A", "base"), Area("A", "base")}));
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area("", "base")}));
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area("A", "")}));
  fs::remove(temporary.path() / "base.jhr");
  fs::create_directory(temporary.path() / "base.jhr");
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area("A", "base")}));
}

TEST(JamCatalog, AbsoluteFilenameWithinRoot) {
  fidoback::test::TempDirectory temporary;
  Files(temporary.path() / "base");
  auto result = JamCatalog::Build(temporary.path(), {Area("A", (temporary.path() / "base").string())});
  ASSERT_TRUE(result);
  EXPECT_TRUE((*result)->Resolve("A"));
}

TEST(JamCatalog, ReadOnlyPermissionsNeverGrantWriteAccess) {
  if (geteuid() == 0)
    GTEST_SKIP() << "Root bypasses file permission checks";
  fidoback::test::TempDirectory temporary;
  Files(temporary.path() / "base");
  ASSERT_EQ(chmod((temporary.path() / "base.jhr").c_str(), 0400), 0);
  auto catalog = JamCatalog::Build(temporary.path(), {Area("A", "base")});
  ASSERT_TRUE(catalog);
  auto area = (*catalog)->Resolve("A");
  ASSERT_TRUE(area);
  EXPECT_FALSE((*area)->files->writable);
  ASSERT_EQ(chmod((temporary.path() / "base.jhr").c_str(), 0000), 0);
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area("A", "base")}));
  ASSERT_EQ(chmod((temporary.path() / "base.jhr").c_str(), 0600), 0);
}

TEST(JamCatalog, RejectsNulPathsNonDirectoryRootsAndRemovedCompanions) {
  fidoback::test::TempDirectory temporary;
  Files(temporary.path() / "base");
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area(std::string("A\0B", 3), "base")}));
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area("A", std::string("base\0other", 10))}));
  EXPECT_FALSE(JamCatalog::Build(temporary.path() / "base.jhr", {}));
  auto catalog = JamCatalog::Build(temporary.path(), {Area("A", "base")});
  ASSERT_TRUE(catalog);
  fs::remove(temporary.path() / "base.jdt");
  EXPECT_FALSE((*catalog)->Resolve("A"));
}

TEST(JamCatalog, PrivateMetadataIdsFormatsAndAliasBoundary) {
  fidoback::test::TempDirectory temporary;
  Files(temporary.path() / "base");
  auto net = Area("MAIL", "base");
  net.kind = AreaKind::kNetmail;
  auto robot = Area("ROBOT", "base");
  robot.kind = AreaKind::kRobots;
  auto unsupported = Area("OLD", "old", "Squish");
  unsupported.kind = AreaKind::kLocal;
  auto catalog = JamCatalog::Build(temporary.path(), {net, robot, unsupported});
  ASSERT_TRUE(catalog);
  ASSERT_EQ((*catalog)->areas().size(), 3);
  const auto& first = (*catalog)->areas().at("@ffido/1/6d61696c");
  EXPECT_EQ(first.config.name, "MAIL");
  EXPECT_TRUE(first.files->role_read_only);
  EXPECT_EQ(first.files, (*catalog)->areas().at("@ffido/5/726f626f74").files);
  EXPECT_FALSE((*catalog)->areas().at("@ffido/2/6f6c64").files);
  auto unavailable = (*catalog)->Resolve("@ffido/2/6f6c64");
  ASSERT_FALSE(unavailable);
  EXPECT_EQ(unavailable.error(), CatalogError::kUnsupportedFormat);
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {net, Area("PUBLIC", "base")}));
  for (auto extension : {".jhr", ".jdt", ".jdx"})
    fs::create_hard_link(temporary.path() / (std::string("base") + extension),
                         temporary.path() / (std::string("alias") + extension));
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {net, Area("PUBLIC", "alias")}));
  auto local = net;
  local.name = "LOCAL";
  local.kind = AreaKind::kLocal;
  auto mixed = JamCatalog::Build(temporary.path(), {net, local});
  ASSERT_TRUE(mixed);
  EXPECT_TRUE((*mixed)->areas().at("@ffido/1/6d61696c").files->role_read_only);
  auto duplicate = net;
  duplicate.name = "mail";
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {net, duplicate}));
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {Area("@ffido/1/6d61696c", "base")}));
  unsupported.filename = "../outside";
  EXPECT_FALSE(JamCatalog::Build(temporary.path(), {unsupported}));
}
