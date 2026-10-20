#include <google/protobuf/empty.pb.h>
#include <gtest/gtest.h>

#include "ffido/v1/ffido.pb.h"

namespace {

TEST(Contract, UnicodeAndTimestampRoundTrip) {
  ffido::v1::Message message;
  message.set_id("generation:42");
  message.set_conference_id("RU.TEST");
  message.set_subject("Проверка ёжика");
  message.set_body("Привет\nмир 🌍");
  message.set_ftn_message_id("2:5020/1 abcdef");
  message.mutable_date()->set_seconds(-1);
  message.mutable_date()->set_nanos(123456789);
  ffido::v1::Message decoded;
  ASSERT_TRUE(decoded.ParseFromString(message.SerializeAsString()));
  EXPECT_EQ(decoded.subject(), message.subject());
  EXPECT_EQ(decoded.body(), message.body());
  EXPECT_EQ(decoded.ftn_message_id(), message.ftn_message_id());
  ASSERT_TRUE(decoded.has_date());
  EXPECT_EQ(decoded.date().seconds(), -1);
  EXPECT_EQ(decoded.date().nanos(), 123456789);
}

TEST(Contract, EmptyOperationResponseHasNoPayload) {
  google::protobuf::Empty response;
  EXPECT_TRUE(response.SerializeAsString().empty());
  ASSERT_TRUE(response.ParseFromString(""));
}

TEST(Contract, UnknownSortSurvivesWireForValidation) {
  ffido::v1::ListMessagesRequest request;
  request.set_sort(static_cast<ffido::v1::MessageSort>(12345));
  request.mutable_page()->set_offset(-1);
  request.mutable_page()->set_limit(101);
  ffido::v1::ListMessagesRequest decoded;
  ASSERT_TRUE(decoded.ParseFromString(request.SerializeAsString()));
  EXPECT_EQ(static_cast<int>(decoded.sort()), 12345);
  EXPECT_FALSE(ffido::v1::MessageSort_IsValid(decoded.sort()));
  EXPECT_EQ(decoded.page().offset(), -1);
  EXPECT_EQ(decoded.page().limit(), 101);
}

TEST(Contract, FieldErrorsPreserveMultipleViolations) {
  ffido::v1::ErrorDetails details;
  auto* body = details.add_violations();
  body->set_field("body");
  body->set_message("Текст обязателен");
  auto* address = details.add_violations();
  address->set_field("to_address");
  address->set_message("Некорректный FTN-адрес");
  ffido::v1::ErrorDetails decoded;
  ASSERT_TRUE(decoded.ParseFromString(details.SerializeAsString()));
  ASSERT_EQ(decoded.violations_size(), 2);
  EXPECT_EQ(decoded.violations(0).message(), "Текст обязателен");
  EXPECT_EQ(decoded.violations(1).field(), "to_address");
  EXPECT_FALSE(decoded.ParseFromString(std::string("\x0a\xff", 2)));
}

TEST(Contract, RpcSurfaceAndTrustedIdentity) {
  const auto* service =
      google::protobuf::DescriptorPool::generated_pool()->FindServiceByName("ffido.v1.Ffido");
  ASSERT_NE(service, nullptr);
  EXPECT_EQ(service->method_count(), 24);
  EXPECT_EQ(service->FindMethodByName("MarkRead")->output_type()->full_name(),
            "google.protobuf.Empty");
  const auto* request = ffido::v1::CreateMessageRequest::descriptor();
  EXPECT_NE(request->FindFieldByName("operation_id"), nullptr);
  EXPECT_EQ(request->FindFieldByName("user_id"), nullptr);
  EXPECT_EQ(request->FindFieldByName("from_address"), nullptr);
  EXPECT_EQ(ffido::v1::SAVE_STATUS_SAVED_LOCALLY, 1);
}

TEST(Contract, BulkReadIsAdditiveAndHasNoUserOverride) {
  auto request = ffido::v1::MarkConferenceReadRequest::descriptor();
  EXPECT_EQ(request->FindFieldByName("conference_id")->number(), 1);
  EXPECT_EQ(request->FindFieldByName("operation_id")->number(), 2);
  EXPECT_EQ(request->FindFieldByName("user_id"), nullptr);
  auto response = ffido::v1::MarkConferenceReadResponse::descriptor();
  EXPECT_EQ(response->FindFieldByName("marked_count")->number(), 1);
  EXPECT_EQ(response->FindFieldByName("snapshot_count")->number(), 2);
  EXPECT_EQ(response->FindFieldByName("generation")->number(), 3);
  auto service =
      google::protobuf::DescriptorPool::generated_pool()->FindServiceByName("ffido.v1.Ffido");
  EXPECT_EQ(service->FindMethodByName("MarkConferenceRead")->input_type(), request);
}

TEST(Contract, PrivateAreaFieldsAreAdditiveAndLegacyEchoDefaultsSurvive) {
  const auto* descriptor = ffido::v1::Conference::descriptor();
  EXPECT_EQ(descriptor->FindFieldByName("id")->number(), 1);
  EXPECT_EQ(descriptor->FindFieldByName("can_post")->number(), 9);
  EXPECT_EQ(descriptor->FindFieldByName("kind")->number(), 10);
  EXPECT_EQ(descriptor->FindFieldByName("storage_format")->number(), 11);
  EXPECT_EQ(descriptor->FindFieldByName("availability")->number(), 12);
  EXPECT_EQ(descriptor->FindFieldByName("statistics_known")->number(), 13);
  EXPECT_EQ(descriptor->FindFieldByName("path"), nullptr);
  ffido::v1::Conference legacy;
  legacy.set_id("RU.TEST");
  EXPECT_EQ(legacy.kind(), ffido::v1::AREA_KIND_ECHO);
  EXPECT_FALSE(legacy.has_statistics_known());
  const auto* login = ffido::v1::LoginRequest::descriptor();
  EXPECT_EQ(login->FindFieldByName("role"), nullptr);
}

TEST(Contract, PersonalMailboxFieldsPreserveExistingNumbersAndLegacyDefaults) {
  const auto* conference = ffido::v1::Conference::descriptor();
  EXPECT_EQ(conference->FindFieldByName("personal_mailbox")->number(), 14);
  EXPECT_EQ(conference->FindFieldByName("last_opened_message_id")->number(), 15);
  EXPECT_EQ(conference->FindFieldByName("position_revision")->number(), 16);
  const auto* message = ffido::v1::Message::descriptor();
  EXPECT_EQ(message->FindFieldByName("attributes")->number(), 15);
  EXPECT_EQ(message->FindFieldByName("direction")->number(), 16);
  EXPECT_EQ(message->FindFieldByName("position_revision")->number(), 17);
  EXPECT_EQ(
      ffido::v1::ListMessagesRequest::descriptor()->FindFieldByName("anchor_message_id")->number(),
      5);
  EXPECT_FALSE(ffido::v1::Conference{}.personal_mailbox());
  EXPECT_EQ(ffido::v1::Message{}.direction(), ffido::v1::MAIL_DIRECTION_UNSPECIFIED);
  EXPECT_FALSE(ffido::v1::ListMessagesResponse{}.has_actual_offset());
}

TEST(Contract, UueExtensionHasNoIdentityOrFilesystemOverride) {
  const auto* service =
      google::protobuf::DescriptorPool::generated_pool()->FindServiceByName("ffido.v1.Ffido");
  ASSERT_NE(service, nullptr);
  for (const auto* name : {"GetUueLimits", "SearchUueParts", "AssembleUue", "GetUueChunk",
                           "UploadUueChunk", "CommitUue", "GetUueSendStatus"}) {
    const auto* method = service->FindMethodByName(name);
    ASSERT_NE(method, nullptr) << name;
    EXPECT_FALSE(method->client_streaming());
    EXPECT_FALSE(method->server_streaming());
    EXPECT_EQ(method->input_type()->FindFieldByName("user_id"), nullptr);
    EXPECT_EQ(method->input_type()->FindFieldByName("path"), nullptr);
    EXPECT_EQ(method->output_type()->FindFieldByName("url"), nullptr);
  }
  EXPECT_EQ(ffido::v1::UploadUueChunkRequest::descriptor()->FindFieldByName("data")->type(),
            google::protobuf::FieldDescriptor::TYPE_BYTES);
  EXPECT_EQ(ffido::v1::GetUueChunkRequest::descriptor()->FindFieldByName("offset")->type(),
            google::protobuf::FieldDescriptor::TYPE_UINT64);
  EXPECT_EQ(ffido::v1::CommitUueRequest::descriptor()->FindFieldByName("message")->message_type(),
            ffido::v1::CreateMessageRequest::descriptor());
}

}  // namespace
