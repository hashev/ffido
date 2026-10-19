#include <gtest/gtest.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <spawn.h>
#include <sys/wait.h>

#include <chrono>
#include <fstream>
#include <thread>

#include "../support/temp_directory.hpp"
#include "service/auth_service.hpp"
#include "service/crypto.hpp"
using namespace fidoback;
using service::AuthService;
class AuthServiceTest : public ::testing::Test {
protected:
  test::TempDirectory temp;
  std::shared_ptr<storage::IMetadataStore> metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  AuthService auth{metadata};
  domain::Profile profile{"Пользователь", "2:5015/1.2", "", "2026-01-01T00:00:00Z"};
  int64_t expiry =
      std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count() +
      3600;
  void SetUp() override {
    ASSERT_TRUE(metadata->Init());
  }
};
TEST_F(AuthServiceTest, ProvisionAuthenticateAndRevoke) {
  auto token = auth.Provision("A", profile, expiry);
  ASSERT_TRUE(token);
  EXPECT_EQ(token->size(), 64);
  auto identity = auth.ValidateToken(*token);
  ASSERT_TRUE(identity);
  EXPECT_EQ(identity->id, "A");
  EXPECT_EQ(identity->profile.address, profile.address);
  auto header = AuthService::ExtractBearerToken("Bearer " + *token);
  ASSERT_TRUE(header);
  EXPECT_EQ(*header, *token);
  ASSERT_TRUE(auth.Revoke(*token));
  EXPECT_FALSE(auth.ValidateToken(*token));
  ASSERT_TRUE(auth.Revoke(*token));
}
TEST_F(AuthServiceTest, InvalidMissingUnknownAndTamperedTokens) {
  for (auto token : {std::string{}, std::string("invalid.token"), std::string(64, '0'), std::string(65, 'a'),
                     std::string(64, 'A')}) {
    auto result = auth.ValidateToken(token);
    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, domain::ErrorCode::kUnauthorized);
  }
  auto token = auth.Provision("A", profile, expiry);
  ASSERT_TRUE(token);
  (*token)[0] = (*token)[0] == 'a' ? 'b' : 'a';
  EXPECT_FALSE(auth.ValidateToken(*token));
  for (auto header : {"", "Bearer ", "Basic abc", "bearer abc", "Bearer abc"})
    EXPECT_FALSE(AuthService::ExtractBearerToken(header));
}
TEST_F(AuthServiceTest, TokensNeverAppearInDatabaseFiles) {
  auto token = auth.Provision("A", profile, expiry);
  ASSERT_TRUE(token);
  for (const auto& file : std::filesystem::directory_iterator(temp.path())) {
    std::ifstream input(file.path(), std::ios::binary);
    std::string contents(std::istreambuf_iterator<char>(input), {});
    EXPECT_EQ(contents.find(*token), std::string::npos);
  }
}
TEST_F(AuthServiceTest, ExpiredRevokedAndInactiveProfilesRejectAccess) {
  auto token = auth.Provision("A", profile, expiry);
  ASSERT_TRUE(token);
  sqlite3* db = nullptr;
  ASSERT_EQ(sqlite3_open((temp.path() / "metadata.db").c_str(), &db), SQLITE_OK);
  ASSERT_EQ(sqlite3_exec(db, "UPDATE tokens SET expires_at=0", nullptr, nullptr, nullptr), SQLITE_OK);
  EXPECT_FALSE(auth.ValidateToken(*token));
  ASSERT_EQ(sqlite3_exec(db, "UPDATE tokens SET expires_at=9223372036854775807; UPDATE users SET active=0", nullptr,
                         nullptr, nullptr),
            SQLITE_OK);
  EXPECT_FALSE(auth.ValidateToken(*token));
  sqlite3_close(db);
}
TEST_F(AuthServiceTest, ProfilesAndExpiryAreValidatedBeforeMutation) {
  EXPECT_FALSE(auth.Provision("A", profile, 0));
  EXPECT_FALSE(auth.Provision("", profile, expiry));
  for (const char* address : {"", "2:1", "0:1/1", "2:0/1", "2:1/65536", "2:1/1.-1", "2:1/1/2", "2:1/1\n"}) {
    auto invalid = profile;
    invalid.address = address;
    EXPECT_FALSE(auth.Provision("A", invalid, expiry));
  }
  EXPECT_FALSE(metadata->GetProfile("A"));
  auto invalid = profile;
  invalid.name = std::string("a\0b", 3);
  EXPECT_FALSE(auth.Provision("A", invalid, expiry));
  for (const char* address : {"2:5015/1", "2:5015/1.0", "2:1/0.65535"})
    EXPECT_TRUE(service::ValidFtnAddress(address));
}
TEST_F(AuthServiceTest, TokenRemainsValidAfterStoreRestartAndOtherStoreRejectsIt) {
  auto token = auth.Provision("A", profile, expiry);
  ASSERT_TRUE(token);
  auto reopened = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(reopened->Init());
  AuthService restored(reopened);
  EXPECT_TRUE(restored.ValidateToken(*token));
  auto other = storage::CreateSQLiteStore(temp.path() / "other.db");
  ASSERT_TRUE(other->Init());
  AuthService unrelated(other);
  EXPECT_FALSE(unrelated.ValidateToken(*token));
}

TEST_F(AuthServiceTest, AssignedIdentityRejectsInvalidBoundariesAndDamagedStoredAddress) {
  for (const auto& user : {std::string(129, 'a'), std::string("a\0b", 3), std::string("a\nb"), std::string("a\rb")}) {
    EXPECT_FALSE(auth.Provision(user, profile, expiry));
  }
  for (const auto& name :
       {std::string{}, std::string(257, 'a'), std::string("a\nb"), std::string("a\rb"), std::string("\xff", 1)}) {
    auto invalid = profile;
    invalid.name = name;
    EXPECT_FALSE(auth.Provision("A", invalid, expiry));
  }
  for (const auto* address : {"2/1:1", "2:1/", "2:1/1.", "2:1/1.65536", "65536:1/1", "2:65536/1", "2:1/1.2.3",
                              "2:1/1:2", "-2:1/1", "2:1./1"}) {
    EXPECT_FALSE(service::ValidFtnAddress(address)) << address;
  }
  EXPECT_FALSE(auth.Revoke("invalid"));
  auto token = auth.Provision("A", profile, expiry);
  ASSERT_TRUE(token);
  auto invalid = profile;
  invalid.address = "invalid";
  ASSERT_TRUE(metadata->SaveProfile("A", invalid));
  auto rejected = auth.ValidateToken(*token);
  ASSERT_FALSE(rejected);
  EXPECT_EQ(rejected.error().code, domain::ErrorCode::kUnauthorized);
}

TEST_F(AuthServiceTest, ProvisionPropagatesStorageFailureWithoutIssuingToken) {
  auto unopened = storage::CreateSQLiteStore(temp.path() / "unopened.db");
  AuthService uninitialized(unopened);
  EXPECT_FALSE(uninitialized.Provision("A", profile, expiry));
  EXPECT_FALSE(std::filesystem::exists(temp.path() / "unopened.db"));
}

extern char** environ;
TEST(AuthCryptoFaults, UnavailableProviderCannotIssueOrValidateTokens) {
  const auto* mode = std::getenv("FFIDO_CRYPTO_FAULT_MODE");
  if (mode) {
    test::TempDirectory temporary;
    auto metadata = storage::CreateSQLiteStore(temporary.path() / "metadata.db");
    ASSERT_TRUE(metadata->Init());
    AuthService auth(metadata);
    if (std::string_view(mode) == "digest") {
      std::array<unsigned char, 32> warmup{};
      ASSERT_EQ(RAND_bytes(warmup.data(), warmup.size()), 1);
    }
    ASSERT_EQ(EVP_set_default_properties(nullptr, "provider=ffido-unavailable"), 1);
    auto issued = auth.Provision("A", {"Name", "2:1/1", "", "date"}, INT64_MAX);
    EXPECT_FALSE(issued);
    auto digest = service::Sha256("payload");
    EXPECT_FALSE(digest);
    auto identity = auth.ValidateToken(std::string(64, 'a'));
    EXPECT_FALSE(identity);
    EXPECT_FALSE(metadata->GetProfile("A"));
    return;
  }
  // Separate exec isolates OpenSSL's process-wide provider configuration/cache.
  for (const auto* scenario : {"random", "digest"}) {
    std::vector<std::string> environment;
    for (auto entry = environ; *entry; ++entry)
      environment.emplace_back(*entry);
    environment.emplace_back(std::string("FFIDO_CRYPTO_FAULT_MODE=") + scenario);
    std::vector<char*> env;
    for (auto& entry : environment)
      env.push_back(entry.data());
    env.push_back(nullptr);
    std::string executable = FFIDO_TEST_BINARY;
    std::string filter = "--gtest_filter=AuthCryptoFaults.UnavailableProviderCannotIssueOrValidateTokens";
    char* arguments[] = {executable.data(), filter.data(), nullptr};
    pid_t child = -1;
    ASSERT_EQ(posix_spawn(&child, executable.c_str(), nullptr, nullptr, arguments, env.data()), 0);
    int status = 0;
    ASSERT_EQ(waitpid(child, &status, 0), child);
    ASSERT_TRUE(WIFEXITED(status));
    EXPECT_EQ(WEXITSTATUS(status), 0) << scenario;
  }
}

TEST_F(AuthServiceTest, HptSessionsShareIdentityAndHaveIndependentLogout) {
  ASSERT_TRUE(auth.Configure({{profile.address, "fixture"}}, std::string(32, 'k')));
  auto phone = auth.Login(profile.name, profile.address, "fixture");
  ASSERT_TRUE(phone);
  auto laptop = auth.Login("Another name", profile.address, "fixture");
  ASSERT_TRUE(laptop);
  EXPECT_EQ(phone->user.id, laptop->user.id);
  EXPECT_EQ(laptop->user.profile.name, profile.name);
  EXPECT_NE(phone->token, laptop->token);
  ASSERT_TRUE(metadata->AddBookmark(phone->user.id, "RU.TEST"));
  EXPECT_TRUE(*metadata->IsBookmarked(laptop->user.id, "RU.TEST"));
  EXPECT_FALSE(auth.Login(profile.name, profile.address, " fixture"));
  EXPECT_FALSE(auth.Login(profile.name, "2:1/999", "fixture"));
  EXPECT_FALSE(auth.Login("", profile.address, "fixture"));
  ASSERT_TRUE(auth.Revoke(phone->token));
  EXPECT_FALSE(auth.ValidateToken(phone->token));
  EXPECT_TRUE(auth.ValidateToken(laptop->token));
  ASSERT_TRUE(auth.Configure({{profile.address, "changed"}}, std::string(32, 'k')));
  EXPECT_FALSE(auth.ValidateToken(laptop->token));
  ASSERT_TRUE(auth.Configure({{profile.address, "fixture"}}, std::string(32, 'k')));
  EXPECT_FALSE(auth.ValidateToken(laptop->token));
}
TEST_F(AuthServiceTest, HptSessionClockExpiryKeyLossAndDeletedLinks) {
  auth.SetClockForTesting([] { return 1700000000; });
  ASSERT_TRUE(auth.Configure({{"2:1/3", "fixture"}}, std::string(32, 'k')));
  const auto login = auth.Login("Name", "02:01/03.0", "fixture");
  ASSERT_TRUE(login);
  EXPECT_EQ(login->user.profile.address, "2:1/3");
  EXPECT_EQ(login->user.expires_at, 1700000000 + 30 * 24 * 3600);
  AuthService restart(metadata);
  restart.SetClockForTesting([] { return 1700000001; });
  ASSERT_TRUE(restart.Configure({{"2:1/3", "fixture"}}, std::string(32, 'k')));
  EXPECT_TRUE(restart.ValidateToken(login->token));
  restart.SetClockForTesting([&] { return login->user.expires_at; });
  EXPECT_FALSE(restart.ValidateToken(login->token));
  auth.SetClockForTesting([] { return 1700000001; });
  auto second = auth.Login("Name", "2:1/3", "fixture");
  ASSERT_TRUE(second);
  ASSERT_TRUE(auth.Configure({{"2:1/3", "fixture"}}, std::string(32, 'x')));
  EXPECT_FALSE(auth.ValidateToken(second->token));
  auto third = auth.Login("Name", "2:1/3", "fixture");
  ASSERT_TRUE(third);
  ASSERT_TRUE(auth.Configure({}, std::string(32, 'x')));
  EXPECT_FALSE(auth.ValidateToken(third->token));
  EXPECT_FALSE(auth.Login("Name", "2:1/3", "fixture"));
}
TEST_F(AuthServiceTest, ExistingIdentityPreservedAndLegacyTokenRevoked) {
  auto legacy = auth.Provision("existing", profile, expiry);
  ASSERT_TRUE(legacy);
  ASSERT_TRUE(metadata->AddBookmark("existing", "RU.TEST"));
  ASSERT_TRUE(auth.Configure({{profile.address, "fixture"}}, std::string(32, 'k')));
  EXPECT_FALSE(auth.ValidateToken(*legacy));
  const auto login = auth.Login("New entered name", profile.address, "fixture");
  ASSERT_TRUE(login);
  EXPECT_EQ(login->user.id, "existing");
  EXPECT_EQ(login->user.profile.name, profile.name);
  EXPECT_TRUE(*metadata->IsBookmarked(login->user.id, "RU.TEST"));
  for (const auto& file : std::filesystem::directory_iterator(temp.path())) {
    std::ifstream input(file.path(), std::ios::binary);
    const std::string contents(std::istreambuf_iterator<char>(input), {});
    EXPECT_EQ(contents.find(login->token), std::string::npos);
    EXPECT_EQ(contents.find("fixture"), std::string::npos);
  }
}
TEST_F(AuthServiceTest, LocalSessionKeyMustBePrivateAndCannotBeSymlinked) {
  const auto path = temp.path() / "key";
  const auto created = service::LoadSessionKey(path);
  ASSERT_TRUE(created);
  EXPECT_EQ(created->size(), 32);
  EXPECT_EQ(*service::LoadSessionKey(path), *created);
  std::filesystem::permissions(path, std::filesystem::perms::others_read, std::filesystem::perm_options::add);
  EXPECT_FALSE(service::LoadSessionKey(path));
  std::filesystem::create_symlink(path, temp.path() / "link");
  EXPECT_FALSE(service::LoadSessionKey(temp.path() / "link"));
}

TEST_F(AuthServiceTest, ConcurrentFirstLoginsNeverCreateTwoAccounts) {
  ASSERT_TRUE(auth.Configure({{"2:1/3", "fixture"}}, std::string(32, 'k')));
  std::expected<service::LoginResult, domain::ApiError> first = std::unexpected(domain::ApiError::Server("pending"));
  std::expected<service::LoginResult, domain::ApiError> second = std::unexpected(domain::ApiError::Server("pending"));
  std::thread phone([&] { first = auth.Login("Phone", "2:1/3", "fixture"); });
  std::thread laptop([&] { second = auth.Login("Laptop", "2:1/3", "fixture"); });
  phone.join();
  laptop.join();
  ASSERT_TRUE(first);
  ASSERT_TRUE(second);
  EXPECT_EQ(first->user.id, second->user.id);
  EXPECT_EQ(first->user.profile.name, second->user.profile.name);
}
