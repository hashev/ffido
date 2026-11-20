#include <gtest/gtest.h>
#include <openssl/evp.h>

#include <future>
#include <memory>
#include <nlohmann/json.hpp>

#include "../support/temp_directory.hpp"
#include "service/auth_service.hpp"
#include "service/telegram_auth.hpp"
#include "storage/metadata_store.hpp"

using namespace fidoback;
namespace {
class TelegramProofTest : public ::testing::Test {
protected:
  service::TelegramConfig config{123, false, 300, 30};
  std::array<unsigned char, 32> seed{1, 2, 3};
  std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> key{
      EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, nullptr, seed.data(), seed.size()), EVP_PKEY_free};
  service::TelegramPublicKey public_key{};
  void SetUp() override {
    ASSERT_TRUE(key);
    size_t size = public_key.size();
    ASSERT_EQ(EVP_PKEY_get_raw_public_key(key.get(), public_key.data(), &size), 1);
  }
  std::string Proof(std::string user = "{\"id\":456}", std::string date = "1000", int64_t bot = 123) {
    const std::string check = std::to_string(bot) + ":WebAppData\nauth_date=" + date + "\nuser=" + user;
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);
    EXPECT_EQ(EVP_DigestSignInit(context.get(), nullptr, nullptr, nullptr, key.get()), 1);
    std::array<unsigned char, 64> signature{};
    size_t size = signature.size();
    EXPECT_EQ(EVP_DigestSign(context.get(), signature.data(), &size,
                             reinterpret_cast<const unsigned char*>(check.data()), check.size()),
              1);
    std::array<unsigned char, 89> encoded{};
    EXPECT_EQ(EVP_EncodeBlock(encoded.data(), signature.data(), static_cast<int>(size)), 88);
    std::string result(reinterpret_cast<const char*>(encoded.data()), 86);
    for (char& c : result) {
      if (c == '+')
        c = '-';
      else if (c == '/')
        c = '_';
    }
    return "user=" + user + "&signature=" + result + "&auth_date=" + date + "&hash=ignored";
  }
};
TEST_F(TelegramProofTest, SignatureCanonicalOrderAndNumericIdentity) {
  auto proof = Proof();
  auto user = service::VerifyTelegramProof(proof, config, 1000, public_key);
  ASSERT_TRUE(user);
  EXPECT_EQ(*user, 456);
  EXPECT_TRUE(service::VerifyTelegramProof(proof, config, 1300, public_key));
  EXPECT_TRUE(service::VerifyTelegramProof(proof, config, 970, public_key));
  EXPECT_FALSE(service::VerifyTelegramProof(proof, config, 1301, public_key));
  EXPECT_FALSE(service::VerifyTelegramProof(proof, config, 969, public_key));
  EXPECT_FALSE(service::VerifyTelegramProof(proof, config, 1000, service::TelegramKey(false)));
  EXPECT_NE(service::TelegramKey(false), service::TelegramKey(true));
}
TEST_F(TelegramProofTest, RejectsTamperingDuplicateKeysAndMalformedData) {
  auto proof = Proof();
  for (const auto& value :
       {proof + "&user={}", proof + "&%75ser={}", proof + "&x=%ZZ", proof + "&x=%0A", proof + "&",
        std::string("user={}"), Proof("{}"), Proof("{\"id\":\"456\"}"), Proof("{\"id\":0}"), Proof("{\"id\":-1}"),
        Proof("{\"id\":18446744073709551615}"), Proof("{\"id\":1}", "1000x"), Proof("{\"id\":1}", "1000", 124)})
    EXPECT_FALSE(service::VerifyTelegramProof(value, config, 1000, public_key));
  proof.replace(proof.find("456"), 3, "457");
  EXPECT_FALSE(service::VerifyTelegramProof(proof, config, 1000, public_key));
  auto disabled = config;
  disabled.bot_id = 0;
  EXPECT_FALSE(service::VerifyTelegramProof(Proof(), disabled, 1000, public_key));
  auto oversized = service::VerifyTelegramProof(std::string(8193, 'a'), config, 1000, public_key);
  ASSERT_FALSE(oversized);
  EXPECT_EQ(oversized.error().code, domain::ErrorCode::kResource);
}
TEST_F(TelegramProofTest, PercentEncodingIsDecodedOnceAndHashIsNotSigned) {
  auto proof = Proof();
  const auto position = proof.find("user={\"id\":456}");
  ASSERT_NE(position, std::string::npos);
  proof.replace(position, 15, "user=%7B%22id%22%3A456%7D");
  proof.erase(proof.find("&hash="));
  auto result = service::VerifyTelegramProof(proof, config, 1000, public_key);
  ASSERT_TRUE(result);
  EXPECT_EQ(*result, 456);
}
TEST_F(TelegramProofTest, AuthServiceBindsOnlyWithCurrentPasswordAndPreservesFtnIdentity) {
  test::TempDirectory temp;
  auto store = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(store->Init());
  service::AuthService auth(store);
  auth.SetClockForTesting([] { return 1000; });
  auth.SetTelegramKeyForTesting(public_key);
  auth.ConfigureTelegram(config);
  ASSERT_TRUE(auth.Configure({{"2:1/1.1", "fixture"}, {"2:1/1.2", "second"}}, std::string(32, 'k')));
  auto hpt = auth.Login("FTN Name", "2:1/1.1", "fixture");
  ASSERT_TRUE(hpt);
  EXPECT_FALSE(auth.BindTelegram(hpt->user, Proof(), "wrong", false));
  ASSERT_TRUE(auth.BindTelegram(hpt->user, Proof(), "fixture", false));
  auto list = auth.TelegramProfiles(Proof());
  ASSERT_TRUE(list);
  ASSERT_EQ(list->size(), 1);
  EXPECT_EQ(list->front().profile.name, "FTN Name");
  auto login = auth.TelegramLogin(Proof(), "2:1/1.1");
  ASSERT_TRUE(login);
  EXPECT_EQ(login->user.id, hpt->user.id);
  EXPECT_EQ(login->user.profile.name, "FTN Name");
  EXPECT_EQ(login->user.expires_at, 1000 + 30 * 24 * 3600);
  EXPECT_FALSE(auth.TelegramLogin(Proof(), "2:1/1.2"));
  EXPECT_FALSE(auth.TelegramLogin(Proof("{\"id\":789}"), "2:1/1.1"));
  EXPECT_FALSE(auth.BindTelegram(hpt->user, Proof("{\"id\":789}"), "fixture", false));
  ASSERT_TRUE(auth.BindTelegram(hpt->user, Proof("{\"id\":789}"), "fixture", true));
  EXPECT_FALSE(auth.ValidateToken(login->token));
  EXPECT_TRUE(auth.ValidateToken(hpt->token));
  auto replacement = auth.TelegramLogin(Proof("{\"id\":789}"), "2:1/1.1");
  ASSERT_TRUE(replacement);
  ASSERT_TRUE(store->UnbindTelegram(hpt->user.id));
  EXPECT_FALSE(auth.ValidateToken(replacement->token));
  EXPECT_TRUE(auth.ValidateToken(hpt->token));
}
class TelegramStoreTest : public ::testing::Test {
protected:
  test::TempDirectory temp;
  std::shared_ptr<storage::IMetadataStore> store = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  storage::TokenDigest fingerprint{1}, hpt_token{2}, telegram_token{3};
  std::string user;
  void SetUp() override {
    ASSERT_TRUE(store->Init());
    ASSERT_TRUE(store->SyncCredentials({{"2:1/1.1", fingerprint}, {"2:1/1.2", fingerprint}}));
    auto session = store->CreateSession("2:1/1.1", "Point", "2026-01-01T00:00:00Z", hpt_token, fingerprint, 2000);
    ASSERT_TRUE(session);
    user = session->id;
  }
};
TEST_F(TelegramStoreTest, MultipleProfilesReplacementAndSelectiveRevocation) {
  auto second =
      store->CreateSession("2:1/1.2", "Second", "2026-01-01T00:00:00Z", storage::TokenDigest{4}, fingerprint, 2000);
  ASSERT_TRUE(second);
  ASSERT_TRUE(store->BindTelegram(user, 123, 456, fingerprint, false));
  ASSERT_TRUE(store->BindTelegram(second->id, 123, 456, fingerprint, false));
  ASSERT_TRUE(store->TelegramProfiles(123, 456));
  EXPECT_EQ(store->TelegramProfiles(123, 456)->size(), 2);
  EXPECT_TRUE(store->TelegramProfiles(123, 999)->empty());
  EXPECT_TRUE(store->TelegramProfiles(124, 456)->empty());
  ASSERT_TRUE(store->CreateTelegramSession(123, 456, "2:1/1.1", telegram_token, 2000));
  ASSERT_TRUE(store->AuthenticateToken(telegram_token, 1000));
  ASSERT_TRUE(store->BindTelegram(user, 123, 456, fingerprint, false));
  EXPECT_TRUE(store->AuthenticateToken(telegram_token, 1000));
  auto conflict = store->BindTelegram(user, 123, 789, fingerprint, false);
  ASSERT_FALSE(conflict);
  EXPECT_EQ(conflict.error().code, domain::ErrorCode::kConflict);
  ASSERT_TRUE(store->BindTelegram(user, 123, 789, fingerprint, true));
  EXPECT_FALSE(store->AuthenticateToken(telegram_token, 1000));
  EXPECT_TRUE(store->AuthenticateToken(hpt_token, 1000));
  EXPECT_FALSE(store->CreateTelegramSession(123, 456, "2:1/1.1", storage::TokenDigest{5}, 2000));
  ASSERT_TRUE(store->UnbindTelegram(user));
  EXPECT_FALSE(*store->TelegramBinding(user));
  EXPECT_EQ(store->TelegramProfiles(123, 456)->size(), 1);
}
TEST_F(TelegramStoreTest, CredentialChangePersistsRevocationAcrossRestartAndPasswordRollback) {
  ASSERT_TRUE(store->BindTelegram(user, 123, 456, fingerprint, false));
  ASSERT_TRUE(store->CreateTelegramSession(123, 456, "2:1/1.1", telegram_token, 2000));
  ASSERT_TRUE(store->SyncCredentials({{"2:1/1.1", storage::TokenDigest{9}}}));
  EXPECT_FALSE(store->AuthenticateToken(telegram_token, 1000));
  EXPECT_FALSE(store->AuthenticateToken(hpt_token, 1000));
  EXPECT_FALSE(*store->TelegramBinding(user));
  ASSERT_TRUE(store->SyncCredentials({{"2:1/1.1", fingerprint}}));
  auto reopened = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(reopened->Init());
  EXPECT_FALSE(*reopened->TelegramBinding(user));
  EXPECT_FALSE(reopened->BindTelegram(user, 123, 456, storage::TokenDigest{9}, false));
  EXPECT_FALSE(reopened->BindTelegram("unknown", 123, 456, fingerprint, false));
}
TEST_F(TelegramStoreTest, ConcurrentLoginAndUnbindCannotLeaveAnAuthorizedSession) {
  ASSERT_TRUE(store->BindTelegram(user, 123, 456, fingerprint, false));
  auto other = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(other->Init());
  auto login = std::async(std::launch::async,
                          [&] { return other->CreateTelegramSession(123, 456, "2:1/1.1", telegram_token, 2000); });
  ASSERT_TRUE(store->UnbindTelegram(user));
  const auto outcome = login.get();
  EXPECT_TRUE(outcome || outcome.error().code == domain::ErrorCode::kUnauthorized);
  EXPECT_FALSE(store->AuthenticateToken(telegram_token, 1000));
  EXPECT_FALSE(other->AuthenticateToken(telegram_token, 1000));
}
TEST_F(TelegramStoreTest, MigrationFromElevenPreservesHptAndRollsBackOnFailure) {
  store.reset();
  sqlite3* raw = nullptr;
  ASSERT_EQ(sqlite3_open((temp.path() / "metadata.db").c_str(), &raw), SQLITE_OK);
  ASSERT_EQ(sqlite3_exec(raw,
                         "DROP TABLE telegram_bindings; ALTER TABLE tokens DROP COLUMN telegram_revision; "
                         "PRAGMA user_version=11; CREATE TABLE telegram_bindings(conflict TEXT)",
                         nullptr, nullptr, nullptr),
            SQLITE_OK);
  store = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  EXPECT_FALSE(store->Init());
  ASSERT_EQ(sqlite3_exec(raw, "DROP TABLE telegram_bindings", nullptr, nullptr, nullptr), SQLITE_OK);
  sqlite3_close(raw);
  ASSERT_TRUE(store->Init());
  ASSERT_TRUE(store->Init());
  auto session = store->AuthenticateToken(hpt_token, 1000);
  ASSERT_TRUE(session);
  EXPECT_EQ(session->id, user);
  EXPECT_EQ(session->profile.name, "Point");
  EXPECT_FALSE(*store->TelegramBinding(user));
}
TEST_F(TelegramStoreTest, ConcurrentReplacementLeavesOneOwnerAndSessionsExpire) {
  ASSERT_TRUE(store->BindTelegram(user, 123, 456, fingerprint, false));
  auto other = storage::CreateSQLiteStore(temp.path() / "metadata.db");
  ASSERT_TRUE(other->Init());
  auto first = std::async(std::launch::async, [&] { return store->BindTelegram(user, 123, 789, fingerprint, true); });
  auto second = std::async(std::launch::async, [&] { return other->BindTelegram(user, 123, 999, fingerprint, true); });
  ASSERT_TRUE(first.get());
  ASSERT_TRUE(second.get());
  const auto a = store->TelegramProfiles(123, 789), b = store->TelegramProfiles(123, 999);
  ASSERT_TRUE(a);
  ASSERT_TRUE(b);
  EXPECT_EQ(a->size() + b->size(), 1);
  const int64_t owner = a->empty() ? 999 : 789;
  ASSERT_TRUE(store->CreateTelegramSession(123, owner, "2:1/1.1", telegram_token, 2000));
  EXPECT_TRUE(store->AuthenticateToken(telegram_token, 1999));
  EXPECT_FALSE(store->AuthenticateToken(telegram_token, 2000));
  EXPECT_FALSE(store->CreateTelegramSession(124, owner, "2:1/1.1", storage::TokenDigest{5}, 2000));
  ASSERT_TRUE(store->UnbindTelegram(user));
  ASSERT_TRUE(store->UnbindTelegram(user));
  EXPECT_TRUE(store->AuthenticateToken(hpt_token, 1000));
}
}  // namespace
