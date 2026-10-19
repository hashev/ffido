#include <gtest/gtest.h>
#include <sys/stat.h>

#include <fstream>

#include "../support/temp_directory.hpp"
#include "service/echo_access.hpp"
#include "service/hpt_auth.hpp"

using namespace fidoback;
namespace {
void Write(const std::filesystem::path& path, std::string_view text) {
  std::ofstream(path) << text;
}
std::string Header() {
  return "Name FFIDO fixture\nSysop Test\nLocation Test\nAddress 2:1/2\n";
}
}  // namespace
TEST(HptAuth, CanonicalAddresses) {
  EXPECT_EQ(*domain::CanonicalFtnAddress("02:001/003.0"), "2:1/3");
  EXPECT_EQ(*domain::CanonicalFtnAddress("2:1/3.4"), "2:1/3.4");
  for (auto value : {"", "2:1", "2:1/3.", "0:1/3", "2:1/65536", "2:1/3.0.1", "2:1/3@domain"})
    EXPECT_FALSE(domain::CanonicalFtnAddress(value)) << value;
}
TEST(HptAuth, IncludesPasswordsAndExcludesVirtualOwnLinks) {
  test::TempDirectory temp;
  Write(temp.path() / "links.cfg",
        "Link Fixture\nAKA 2:1/3\nOurAKA 2:1/2\nPassword default-secret\nSessionPwd session-secret\n");
  Write(temp.path() / "hpt.cfg",
        Header() +
            "ifdef ffido_never_defined_fixture\nInvalidKeyword secret\nendif\nif \"[module]\" == \"hpt\"\nInclude " +
            (temp.path() / "links.cfg").string() + "\nendif\n");
  const auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, temp.path() / "hpt.cfg");
  ASSERT_TRUE(result);
  ASSERT_EQ(result->credentials.size(), 1);
  EXPECT_EQ(result->credentials.at("2:1/3"), "session-secret");
  EXPECT_FALSE(result->credentials.contains("2:1/2"));
}
TEST(HptAuth, AbsentSessionInheritsButEmptySessionDoesNot) {
  test::TempDirectory temp;
  const auto path = temp.path() / "hpt.cfg";
  const auto text = Header() + "Link Fixture\nAKA 2:1/3\nOurAKA 2:1/2\nPassword default-secret\n";
  Write(path, text);
  auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->credentials.at("2:1/3"), "default-secret");
  Write(path, text + "SessionPwd\n");
  result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  EXPECT_TRUE(result->credentials.at("2:1/3").empty());
  Write(path, Header() + "Link Fixture\nAKA 2:1/3\nOurAKA 2:1/2\n");
  result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  EXPECT_TRUE(result->credentials.at("2:1/3").empty());
}
TEST(HptAuth, ParserFailureDoesNotExitCallerOrExposeDiagnostics) {
  test::TempDirectory temp;
  const auto path = temp.path() / "hpt.cfg";
  Write(path, Header() + "Link\nfixture-private-value\n");
  testing::internal::CaptureStdout();
  testing::internal::CaptureStderr();
  auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  const auto out = testing::internal::GetCapturedStdout();
  const auto err = testing::internal::GetCapturedStderr();
  ASSERT_FALSE(result);
  EXPECT_TRUE(out.empty());
  EXPECT_TRUE(err.empty());
  EXPECT_EQ(result.error().message.find("fixture-private-value"), std::string::npos);
  EXPECT_FALSE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, temp.path() / "missing"));
}
TEST(HptAuth, RejectsMalformedDuplicateResultsAndBoundsChildLifetime) {
  test::TempDirectory temp;
  const auto helper = temp.path() / "helper";
  for (const auto& script :
       {"#!/bin/sh\nprintf 'invalid'\n",
        "#!/bin/sh\nprintf "
        "'[{\"address\":\"2:1/3\",\"password\":\"a\"},{\"address\":\"2:1/3.0\",\"password\":\"b\"}]'\n",
        "#!/bin/sh\nexec sleep 2\n", "#!/bin/sh\nexec 1>&-\nexec sleep 2\n"}) {
    Write(helper, script);
    chmod(helper.c_str(), 0700);
    const auto start = std::chrono::steady_clock::now();
    EXPECT_FALSE(service::ReadHptConfiguration(helper, temp.path(), std::chrono::milliseconds(50)));
    EXPECT_LT(std::chrono::steady_clock::now() - start, std::chrono::seconds(1));
  }
  EXPECT_FALSE(service::ReadHptConfiguration(temp.path() / "missing", temp.path()));
}

TEST(HptAuth, RealParserRejectsDuplicateAndUnrepresentableAddresses) {
  test::TempDirectory temp;
  const auto path = temp.path() / "hpt.cfg";
  Write(path, Header() + "Link A\nAKA 2:1/3\nOurAKA 2:1/2\nPassword a\nLink B\nAKA 2:1/3\nOurAKA 2:1/2\nPassword b\n");
  EXPECT_FALSE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path));
  Write(path, Header() + "Link A\nAKA 2:1/65535.65535\nOurAKA 2:1/2\nPassword fixture\n");
  // This Husky build represents fields as signed 16-bit values and rejects
  // values above 32767. Respect the parser rather than reinterpret wildcards.
  EXPECT_FALSE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path));
  Write(path, Header() + "Link A\nAKA 2:1/32767.32767\nOurAKA 2:1/2\nPassword fixture\n");
  const auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->credentials.at("2:1/32767.32767"), "fixture");
}

TEST(HptAuth, EffectiveEchoSubscriptionsAndMasks) {
  test::TempDirectory temp;
  const auto path = temp.path() / "hpt.cfg";
  Write(temp.path() / "areas.cfg", "EchoArea RU.FULL ./full -b JAM 2:1/3 2:1/4\n"
                                   "EchoArea RU.READ ./read -b JAM 2:1/3 2:1/4\n"
                                   "EchoArea RU.WRITE ./write -b JAM 2:1/3\n"
                                   "EchoArea RU.EMPTY ./empty -b JAM\n"
                                   "EchoAreaDefaults -b JAM\nEchoArea RU.DEFAULT ./default 2:1/3\n");
  Write(path, Header() +
                  "Link A\nAKA 2:1/3\nOurAKA 2:1/2\nPassword fixture\n"
                  "Link B\nAKA 2:1/4\nOurAKA 2:1/2\nPassword fixture\nInclude " +
                  (temp.path() / "areas.cfg").string() +
                  "\nReadOnly 2:1/* RU.*\nReadOnly 2:1/3 !RU.FULL\nReadOnly 2:1/3 !RU.WRITE\n"
                  "ReadOnly 2:1/3 !RU.DEFAULT\nWriteOnly 2:1/3 RU.WRITE\n");
  auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  ASSERT_EQ(result->echoes.size(), 5);
  auto find = [&](std::string_view name) -> const service::HptEcho& {
    return *std::find_if(result->echoes.begin(), result->echoes.end(),
                         [&](const auto& echo) { return echo.name == name; });
  };
  EXPECT_TRUE(find("RU.FULL").links.at("2:1/3").read);
  EXPECT_TRUE(find("RU.FULL").links.at("2:1/3").post);
  EXPECT_FALSE(find("RU.READ").links.at("2:1/3").post);
  EXPECT_TRUE(find("RU.READ").links.at("2:1/3").read);
  EXPECT_FALSE(find("RU.WRITE").links.at("2:1/3").read);
  EXPECT_TRUE(find("RU.WRITE").links.at("2:1/3").post);
  EXPECT_FALSE(find("RU.EMPTY").links.contains("2:1/3"));
  EXPECT_TRUE(find("RU.DEFAULT").links.at("2:1/3").post);
  EXPECT_EQ(find("RU.FULL").filename, (std::filesystem::current_path() / "full").lexically_normal());
}

TEST(HptAuth, RejectsMalformedExpandedPolicyAndOversizedHelperOutput) {
  test::TempDirectory temp;
  const auto helper = temp.path() / "helper";
  for (
      const auto& json :
      {R"({"credentials":[],"echoes":[{"name":"RU.TEST","filename":"relative","links":[]}]})",
       R"({"credentials":[],"echoes":[],"private_areas":[{"name":"X","filename":"/tmp/x","kind":"echo","format":"JAM","aka":""}]})",
       R"({"credentials":[],"echoes":[],"private_areas":[{"name":"X","filename":"/tmp/x","kind":"local","format":"JAM","aka":"bad"}]})",
       R"({"credentials":[],"echoes":[{"name":"RU.TEST","filename":"/tmp/file","links":[{"address":"2:1/3","read":1,"post":true}]}]})",
       R"({"credentials":[],"echoes":[{"name":"RU.TEST","filename":"/tmp/file","links":[]},{"name":"ru.test","filename":"/tmp/file","links":[]}]})",
       R"({"credentials":[],"echoes":[{"name":"RU.TEST","filename":"/tmp/file","links":[{"address":"2:1/3","read":true,"post":true},{"address":"2:1/3.0","read":false,"post":false}]}]})"}) {
    Write(helper, "#!/bin/sh\nprintf '%s' '" + std::string(json) + "'\n");
    chmod(helper.c_str(), 0700);
    EXPECT_FALSE(service::ReadHptConfiguration(helper, temp.path()));
  }
  Write(helper, "#!/bin/sh\nexec head -c 16777217 /dev/zero\n");
  chmod(helper.c_str(), 0700);
  EXPECT_FALSE(service::ReadHptConfiguration(helper, temp.path()));
}

TEST(HptAuth, OwnPointUsesOnlyItsBossAndEffectivePassword) {
  test::TempDirectory temp;
  const auto path = temp.path() / "hpt.cfg";
  const auto header = "Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/2.1\n";
  const std::string boss = "Link Boss\nAKA 2:1/2\nOurAKA 2:1/2.1\nPassword fallback\n";
  Write(path, header + boss);
  auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->credentials.at("2:1/2.1"), "fallback");
  Write(path, header + boss + "SessionPwd session\n");
  result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->credentials.at("2:1/2.1"), "session");
  for (const auto& suffix : {std::string("SessionPwd\n"), std::string("Password\n")}) {
    Write(path, header + (suffix == "Password\n" ? "Link Boss\nAKA 2:1/2\nOurAKA 2:1/2.1\n" : boss) + suffix);
    result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
    ASSERT_TRUE(result);
    EXPECT_FALSE(result->credentials.contains("2:1/2.1"));
  }
  for (const auto& links : {"", "Link Other\nAKA 2:1/3\nOurAKA 2:1/2.1\nPassword fixture\n",
                            "Link Boss\nAKA 2:1/2\nOurAKA 2:1/2.2\nPassword fixture\n"}) {
    Write(path, std::string(header) + "Address 2:1/2.2\n" + links);
    result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
    ASSERT_TRUE(result);
    EXPECT_FALSE(result->credentials.contains("2:1/2.1"));
  }
  Write(path, header + boss + "Link Duplicate\nAKA 2:1/2\nOurAKA 2:1/2.1\nPassword different\n");
  EXPECT_FALSE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path));
}

TEST(HptAuth, OwnAkaEchoRightsAreLocalAndExplicitLinksTakePriority) {
  test::TempDirectory temp;
  const auto path = temp.path() / "hpt.cfg";
  const std::string text = "Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/2.1\nAddress 2:1/3.1\n"
                           "Link Boss1\nAKA 2:1/2\nOurAKA 2:1/2.1\nPassword boss1\n"
                           "Link Boss2\nAKA 2:1/3\nOurAKA 2:1/3.1\nPassword boss2\n"
                           "EchoArea ONE ./one -b JAM -a 2:1/2.1 2:1/2\n"
                           "EchoArea TWO ./two -b JAM -a 2:1/3.1 2:1/3\n";
  Write(path, text);
  auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->credentials.at("2:1/2.1"), "boss1");
  EXPECT_EQ(result->credentials.at("2:1/3.1"), "boss2");
  ASSERT_EQ(result->echoes.size(), 2);
  EXPECT_TRUE(result->echoes[0].links.at("2:1/2.1").read);
  EXPECT_TRUE(result->echoes[0].links.at("2:1/2.1").post);
  EXPECT_FALSE(result->echoes[0].links.contains("2:1/3.1"));
  EXPECT_FALSE(result->echoes[1].links.contains("2:1/2.1"));
  Write(path, text + "Link Local\nAKA 2:1/2.1\nOurAKA 2:1/2.1\nSessionPwd explicit\n");
  result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->credentials.at("2:1/2.1"), "explicit");
  EXPECT_FALSE(result->echoes[0].links.contains("2:1/2.1"));
}

TEST(HptAuth, EffectivePrivateTypesDefaultsAndRobotsReference) {
  test::TempDirectory temp;
  Write(temp.path() / "private.cfg", "NetmailArea MAIL ./mail -b JAM -a 2:1/2\n"
                                     "NetArea ROBOT ./robot -b JAM -a 2:1/2\n"
                                     "RobotsArea robot\n"
                                     "NetmailArea SQUISH ./squish -b Squish\n"
                                     "LocalArea CARBON ./carbon -b JAM\n"
                                     "LocalArea SDM ./sdm -b MSG\n"
                                     "BadArea BAD ./bad -b JAM\nDupeArea DUPE ./dupe -b JAM\n");
  Write(temp.path() / "hpt.cfg", Header() + "Include " + (temp.path() / "private.cfg").string() + "\n");
  auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, temp.path() / "hpt.cfg");
  ASSERT_TRUE(result);
  EXPECT_TRUE(result->echoes.empty());
  ASSERT_EQ(result->private_areas.size(), 7);
  const auto& areas = result->private_areas;
  EXPECT_EQ(areas[0].kind, AreaKind::kNetmail);
  EXPECT_EQ(areas[0].aka, "2:1/2");
  EXPECT_EQ(areas[1].kind, AreaKind::kRobots);
  EXPECT_EQ(areas[2].msgbase_type, "Squish");
  EXPECT_EQ(areas[3].kind, AreaKind::kLocal);
  EXPECT_EQ(areas[3].msgbase_type, "JAM");
  EXPECT_EQ(areas[4].msgbase_type, "MSG");
  EXPECT_EQ(areas[5].kind, AreaKind::kBad);
  EXPECT_EQ(areas[6].kind, AreaKind::kDupe);
  for (const auto& area : areas)
    EXPECT_TRUE(std::filesystem::path(area.filename).is_absolute());
}

TEST(HptAuth, ExposesEffectiveMailTransportWithoutInventingOwnPointAka) {
  test::TempDirectory temp;
  auto text = Header() + "Link Point\nAKA 2:1/2.1\nOurAKA 2:1/2\nPassword fixture\nKeepTrsMail on\nPackNetMailOnScan "
                         "off\nRoute nopack 2:1/2.1\nRoute normal noroute *\n";
  text += "NetmailArea IN " + (temp.path() / "in").string() + " -b JAM -dupeCheck off\n";
  Write(temp.path() / "hpt.cfg", text);
  auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, temp.path() / "hpt.cfg");
  ASSERT_TRUE(result);
  ASSERT_TRUE(result->transport.available);
  EXPECT_EQ(result->transport.own_addresses, std::vector<std::string>{"2:1/2"});
  EXPECT_EQ(result->transport.link_akas.at("2:1/2.1"), "2:1/2");
  EXPECT_TRUE(result->transport.keep_transit);
  EXPECT_FALSE(result->transport.pack_on_scan);
  ASSERT_EQ(result->transport.netmail.size(), 1u);
  EXPECT_TRUE(result->transport.netmail.front().dupe_check_off);
  ASSERT_EQ(result->transport.routes.size(), 2u);
  EXPECT_EQ(result->transport.routes.front().pattern, "2:1/2.1");
  EXPECT_TRUE(result->transport.routes.front().nopack);
}

TEST(HptAuth, MappedIncludesKeepHptSemanticsAndCatalog) {
#ifndef FFIDO_CONFIG_OPEN_ADAPTER
  GTEST_SKIP() << "Configure FFIDO_FIDOCONFIG_SOURCE to test mapped includes";
#endif
  test::TempDirectory temp;
  const std::string logical = "/ffido-container-fixture";
  Write(temp.path() / "links.cfg", "Link Fixture\nAKA 2:1/3\nOurAKA 2:1/2\nPassword /ffido-container-fixture/secret\n");
  Write(temp.path() / "areas.cfg", "EchoAreaDefaults -b JAM\nEchoArea RU.MAPPED " + logical +
                                       "/jam/ru.test -p 3650 -d \"Mapped description\" 2:1/3\n" + "LocalArea LOCAL " +
                                       logical + "/jam/local -b JAM\n");
  Write(temp.path() / "nested.cfg", "Include [basedir]/links.cfg\nInclude [basedir]/areas.cfg\n");
  Write(temp.path() / "hpt.cfg", Header() + "set basedir=\"" + logical +
                                     "\"\nif \"[module]\" == \"hpt\"\nInclude [basedir]/nested.cfg\nendif\n"
                                     "ifdef ffido_never_defined_fixture\nInclude /missing-secret\nendif\n");
  AppConfig config = DefaultConfig();
  config.auth.hpt_config_path = temp.path() / "hpt.cfg";
  config.ftn.areacfg_path = (temp.path() / "areas.cfg").string();
  config.ftn.path_mappings = {{logical, temp.path()}};
  auto hpt = service::LoadHptConfiguration(FFIDO_HPT_AUTH_BINARY, config);
  ASSERT_TRUE(hpt) << (hpt ? "" : hpt.error().message);
  EXPECT_EQ(hpt->credentials.at("2:1/3"), logical + "/secret");
  ASSERT_EQ(hpt->echoes.size(), 1);
  EXPECT_EQ(hpt->echoes[0].filename, temp.path() / "jam/ru.test");
  EXPECT_EQ(hpt->echoes[0].description, "Mapped description");
  EXPECT_TRUE(hpt->echoes[0].links.at("2:1/3").read);
  auto areas = service::CatalogAreas(config, *hpt);
  ASSERT_TRUE(areas);
  ASSERT_EQ(areas->size(), 2);
  EXPECT_EQ(areas->at(0).filename, (temp.path() / "jam/ru.test").string());
  EXPECT_EQ(areas->at(1).filename, (temp.path() / "jam/local").string());
  EXPECT_EQ(areas->at(1).kind, AreaKind::kLocal);
  EXPECT_EQ(areas->at(1).description.value_or(areas->at(1).name), "LOCAL");
  config.ftn.areacfg_path = (temp.path() / "links.cfg").string();
  EXPECT_TRUE(service::LoadHptConfiguration(FFIDO_HPT_AUTH_BINARY, config));
  Write(temp.path() / "other.cfg", "");
  config.ftn.areacfg_path = (temp.path() / "other.cfg").string();
  EXPECT_FALSE(service::LoadHptConfiguration(FFIDO_HPT_AUTH_BINARY, config));
}

TEST(HptAuth, MappedIncludeFailuresRemainPrivateAndBounded) {
#ifndef FFIDO_CONFIG_OPEN_ADAPTER
  GTEST_SKIP() << "Configure FFIDO_FIDOCONFIG_SOURCE to test mapped includes";
#endif
  test::TempDirectory temp;
  const auto path = temp.path() / "hpt.cfg";
  const std::vector<ftn::PathMapping> rules{{"/ffido-container-fixture", temp.path()}};
  for (const auto& include : {"/ffido-container-fixture/missing-secret", "/ffido-container-fixture/hpt.cfg",
                              "/ffido-container-fixture/../escape"}) {
    Write(path, Header() + "Include " + include + "\n");
    testing::internal::CaptureStdout();
    testing::internal::CaptureStderr();
    const auto result = service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path, std::chrono::seconds(1), rules);
    EXPECT_TRUE(testing::internal::GetCapturedStdout().empty());
    EXPECT_TRUE(testing::internal::GetCapturedStderr().empty());
    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().message.find("secret"), std::string::npos);
  }
  Write(temp.path() / "large", std::string(16 * 1024 * 1024 + 1, '#'));
  Write(path, Header() + "Include /ffido-container-fixture/large\n");
  EXPECT_FALSE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path, std::chrono::seconds(1), rules));
  for (int i = 0; i < 35; ++i)
    Write(temp.path() / ("depth" + std::to_string(i)),
          "Include /ffido-container-fixture/depth" + std::to_string(i + 1) + "\n");
  Write(path, Header() + "Include /ffido-container-fixture/depth0\n");
  EXPECT_FALSE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path, std::chrono::seconds(1), rules));
}

TEST(HptAuth, MappedCatalogPreservesRootAndPhysicalIdentityChecks) {
#ifndef FFIDO_CONFIG_OPEN_ADAPTER
  GTEST_SKIP() << "Configure FFIDO_FIDOCONFIG_SOURCE to test mapped includes";
#endif
  test::TempDirectory temp;
  const auto root = temp.path() / "jam";
  std::filesystem::create_directory(root);
  auto files = [](const std::filesystem::path& base) {
    for (const auto* extension : {".jhr", ".jdt", ".jdx"})
      Write(base.string() + extension, "fixture");
  };
  files(root / "one");
  files(root / "two");
  files(temp.path() / "outside");
  AppConfig config = DefaultConfig();
  config.auth.hpt_config_path = temp.path() / "hpt.cfg";
  config.ftn.areacfg_path = (temp.path() / "areas.cfg").string();
  config.ftn.jam_base_path = root.string();
  config.ftn.path_mappings = {{"/mapped", temp.path()}};
  Write(config.auth.hpt_config_path, Header() + "Include /mapped/areas.cfg\n");
  auto load = [&](const std::string& filename) {
    Write(config.ftn.areacfg_path, "EchoArea ECHO " + filename + " -b JAM\n");
    return service::LoadHptConfiguration(FFIDO_HPT_AUTH_BINARY, config);
  };
  auto hpt = load("/mapped/jam/one");
  ASSERT_TRUE(hpt);
  auto areas = service::CatalogAreas(config, *hpt);
  ASSERT_TRUE(areas);
  auto catalog = storage::JamCatalog::Build(root, *areas);
  ASSERT_TRUE(catalog);
  EXPECT_TRUE(service::EchoAccess::Build(*hpt, **catalog));
  auto different = *hpt;
  different.echoes[0].filename = root / "two";
  EXPECT_FALSE(service::EchoAccess::Build(different, **catalog));
  for (const auto& name : {"/mapped/outside", "/mapped/jam/missing"}) {
    hpt = load(name);
    ASSERT_TRUE(hpt);
    areas = service::CatalogAreas(config, *hpt);
    ASSERT_TRUE(areas);
    EXPECT_FALSE(storage::JamCatalog::Build(root, *areas));
  }
  EXPECT_FALSE(load("/mapped/jam/../outside"));
  std::filesystem::create_directory_symlink(temp.path(), root / "escape");
  hpt = load("/mapped/jam/escape/outside");
  ASSERT_TRUE(hpt);
  areas = service::CatalogAreas(config, *hpt);
  ASSERT_TRUE(areas);
  EXPECT_FALSE(storage::JamCatalog::Build(root, *areas));
}

TEST(HptAuth, MappingWithoutAdapterFailsExplicitly) {
  test::TempDirectory temp;
  Write(temp.path() / "hpt.cfg", Header());
  const std::vector<ftn::PathMapping> rules{{"/container", temp.path()}};
  auto result = service::ReadHptConfiguration(FFIDO_UNMAPPED_HELPER_BINARY, temp.path() / "hpt.cfg",
                                              std::chrono::seconds(1), rules);
  ASSERT_FALSE(result);
  EXPECT_NE(result.error().message.find("FFIDO_FIDOCONFIG_SOURCE"), std::string::npos);
  EXPECT_TRUE(service::ReadHptConfiguration(FFIDO_UNMAPPED_HELPER_BINARY, temp.path() / "hpt.cfg"));
}

TEST(HptAuth, MappedRelativeIncludeUsesHptWorkingDirectory) {
#ifndef FFIDO_CONFIG_OPEN_ADAPTER
  GTEST_SKIP() << "Configure FFIDO_FIDOCONFIG_SOURCE to test mapped includes";
#endif
  test::TempDirectory temp;
  const auto relative = "ffido-mapped-relative-fixture.cfg";
  Write(temp.path() / "links.cfg", "Link Fixture\nAKA 2:1/3\nOurAKA 2:1/2\nPassword fixture\n");
  Write(temp.path() / "hpt.cfg", Header() + "Include ./" + relative + "\n");
  const std::vector<ftn::PathMapping> rules{{std::filesystem::current_path() / relative, temp.path() / "links.cfg"}};
  auto result =
      service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, temp.path() / "hpt.cfg", std::chrono::seconds(1), rules);
  ASSERT_TRUE(result);
  EXPECT_EQ(result->credentials.at("2:1/3"), "fixture");
}

TEST(HptAuth, MappedIncludeCountAndInvalidMetadataFailWithoutPartialPolicy) {
#ifndef FFIDO_CONFIG_OPEN_ADAPTER
  GTEST_SKIP() << "Configure FFIDO_FIDOCONFIG_SOURCE to test mapped includes";
#endif
  test::TempDirectory temp;
  const auto path = temp.path() / "hpt.cfg";
  const std::vector<ftn::PathMapping> rules{{"/mapped", temp.path()}};
  std::string text = Header();
  for (int i = 0; i < 1025; ++i) {
    const auto name = "include" + std::to_string(i);
    Write(temp.path() / name, "# fixture\n");
    text += "Include /mapped/" + name + "\n";
  }
  Write(path, text);
  EXPECT_FALSE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path, std::chrono::seconds(2), rules));
  Write(path, Header() + "Include /mapped/areas.cfg\n");
  Write(temp.path() / "areas.cfg", "EchoArea ECHO /mapped/base -b JAM -d \"invalid-\xff\"\n");
  EXPECT_FALSE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path, std::chrono::seconds(1), rules));
  Write(path, Header() + "Include " + (temp.path() / "areas.cfg").string() + "\n");
  EXPECT_TRUE(service::ReadHptConfiguration(FFIDO_HPT_AUTH_BINARY, path));
}
