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

TEST(Contract, TechnicalDataPreservesRawFieldsAndHasNoIdentityOverride) {
  using namespace ffido::v1;
  MessageTechnicalData value;
  value.mutable_message()->set_conference_id("ECHO");
  value.mutable_message()->set_message_id("generation#1");
  value.set_attributes(0x80000008u);
  value.set_attributes2(0xffffffffu);
  for (const auto& bytes : {std::string{}, std::string("A\0\xff", 3), std::string("A\0\xff", 3)}) {
    auto* field = value.add_subfields();
    field->set_low_id(2000);
    field->set_high_id(3);
    field->set_value(bytes);
  }
  MessageTechnicalData decoded;
  ASSERT_TRUE(decoded.ParseFromString(value.SerializeAsString()));
  EXPECT_EQ(decoded.SerializeAsString(), value.SerializeAsString());
  EXPECT_EQ(decoded.attributes(), 0x80000008u);
  EXPECT_EQ(decoded.attributes2(), 0xffffffffu);
  ASSERT_EQ(decoded.subfields_size(), 3);
  EXPECT_TRUE(decoded.subfields(0).value().empty());
  EXPECT_EQ(decoded.subfields(1).value(), std::string("A\0\xff", 3));
  const auto* service =
      google::protobuf::DescriptorPool::generated_pool()->FindServiceByName("ffido.v1.Ffido");
  ASSERT_NE(service->FindMethodByName("GetMessageTechnicalData"), nullptr);
  EXPECT_EQ(service->FindMethodByName("GetMessageTechnicalData")->input_type(),
            MessageReference::descriptor());
  EXPECT_EQ(MessageReference::descriptor()->field_count(), 2);
  EXPECT_EQ(Message::descriptor()->FindFieldByName("attributes")->number(), 15);
  EXPECT_EQ(Message::descriptor()->FindFieldByName("ftn_message_id")->number(), 14);
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
  EXPECT_EQ(service->method_count(), 35);
  ASSERT_NE(service->FindMethodByName("FindMessage"), nullptr);
  EXPECT_EQ(service->FindMethodByName("FindMessage")->input_type(),
            ffido::v1::FindMessageRequest::descriptor());
  EXPECT_EQ(service->FindMethodByName("FindMessage")->output_type(),
            ffido::v1::FindMessageResponse::descriptor());
  EXPECT_EQ(ffido::v1::FindMessageRequest::descriptor()->FindFieldByName("user_id"), nullptr);
  EXPECT_EQ(service->FindMethodByName("MarkRead")->output_type()->full_name(),
            "google.protobuf.Empty");
  ASSERT_NE(service->FindMethodByName("MarkUnread"), nullptr);
  EXPECT_EQ(service->FindMethodByName("MarkUnread")->input_type(),
            ffido::v1::MessageReference::descriptor());
  EXPECT_EQ(service->FindMethodByName("MarkUnread")->output_type()->full_name(),
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

TEST(Contract, PersonalFiltersAreAdditiveAndPresentationIsExplicit) {
  using namespace ffido::v1;
  EXPECT_FALSE(ListMessagesRequest{}.respect_personal_filters());
  EXPECT_FALSE(GetThreadRequest{}.respect_personal_filters());
  EXPECT_FALSE(FindMessageRequest{}.respect_personal_filters());
  EXPECT_FALSE(GetMessagePresentationRequest{}.reveal());
  ReplacePersonalMessageFiltersRequest request;
  request.set_expected_revision(UINT64_MAX);
  request.set_operation_id("operation");
  request.add_rules()->set_rule_id("rule");
  ReplacePersonalMessageFiltersRequest decoded;
  ASSERT_TRUE(decoded.ParseFromString(request.SerializeAsString()));
  EXPECT_EQ(decoded.expected_revision(), UINT64_MAX);
  EXPECT_EQ(MessageReference::descriptor()->field_count(), 2);
  EXPECT_EQ(Message::descriptor()->FindFieldByName("position_revision")->number(), 17);
  MessagePresentation presentation;
  EXPECT_EQ(presentation.content_case(), MessagePresentation::CONTENT_NOT_SET);
  presentation.mutable_visible()->set_body("text");
  presentation.mutable_collapsed()->mutable_message()->set_message_id("g#1");
  EXPECT_FALSE(presentation.has_visible());
  EXPECT_TRUE(presentation.has_collapsed());
  for (const auto* descriptor : {ReplacePersonalMessageFiltersRequest::descriptor(),
                                 GetMessagePresentationRequest::descriptor()}) {
    EXPECT_EQ(descriptor->FindFieldByName("user_id"), nullptr);
    EXPECT_EQ(descriptor->FindFieldByName("profile"), nullptr);
  }
}

TEST(Contract, ArchiveMessagesPreserveUnicodeOffsetsAndReferences) {
  using namespace ffido::v1;
  ReadArchiveMessageResponse value;
  value.mutable_message()->set_id("generation#42");
  value.mutable_message()->set_conference_id("RU.TEST");
  value.mutable_message()->set_body("Архив 🌍");
  value.set_body_offset(4);
  value.set_next_offset(18);
  value.set_complete(false);
  ReadArchiveMessageResponse decoded;
  ASSERT_TRUE(decoded.ParseFromString(value.SerializeAsString()));
  EXPECT_EQ(decoded.SerializeAsString(), value.SerializeAsString());
  EXPECT_EQ(decoded.message().body(), "Архив 🌍");
  EXPECT_EQ(decoded.next_offset(), 18u);
  EXPECT_FALSE(ReadArchiveMessageRequest{}.reveal());
  SearchArchiveMessagesRequest search;
  search.add_conference_ids("RU.TEST");
  search.set_query("ёжик");
  search.mutable_from()->set_seconds(-1);
  search.mutable_to()->set_seconds(42);
  search.set_cursor("opaque-cursor");
  SearchArchiveMessagesRequest restored;
  ASSERT_TRUE(restored.ParseFromString(search.SerializeAsString()));
  EXPECT_EQ(restored.SerializeAsString(), search.SerializeAsString());
  EXPECT_TRUE(restored.has_from());
  EXPECT_EQ(restored.from().seconds(), -1);
  const auto* service = google::protobuf::DescriptorPool::generated_pool()->FindServiceByName("ffido.v1.Ffido");
  for (const auto* name : {"SearchArchiveMessages", "ReadArchiveMessage", "GetArchiveThread"}) {
    const auto* method = service->FindMethodByName(name);
    ASSERT_NE(method, nullptr);
    EXPECT_EQ(method->input_type()->FindFieldByName("user_id"), nullptr);
    EXPECT_EQ(method->input_type()->FindFieldByName("record_view"), nullptr);
  }
  EXPECT_EQ(Message::descriptor()->FindFieldByName("body")->number(), 9);
  EXPECT_EQ(MessageReference::descriptor()->field_count(), 2);
}

TEST(Contract, PublicationPreviewIsAdditiveAndOldRequestsRemainValid) {
  using namespace ffido::v1;
  CreateMessageRequest old;
  old.set_conference_id("RU.TEST"); old.set_operation_id("old"); old.set_body("Текст");
  CreateMessageRequest restored;
  ASSERT_TRUE(restored.ParseFromString(old.SerializeAsString()));
  EXPECT_FALSE(restored.has_expected_preview_digest());
  EXPECT_EQ(CreateMessageRequest::descriptor()->FindFieldByName("footer")->number(), 8);
  EXPECT_EQ(CreateMessageRequest::descriptor()->FindFieldByName("expected_preview_digest")->number(), 9);
  MessagePreview preview;
  preview.set_body("Итоговый текст"); preview.set_preview_digest("digest"); preview.set_public_message(true);
  MessagePreview decoded;
  ASSERT_TRUE(decoded.ParseFromString(preview.SerializeAsString()));
  EXPECT_EQ(decoded.SerializeAsString(), preview.SerializeAsString());
}

TEST(Contract, OfflineReadFieldsAreAdditiveAndPreserveDefaultsAndBytes) {
  using namespace ffido::v1;
  using F = google::protobuf::FieldDescriptor;
  const auto check = [](const google::protobuf::Descriptor* descriptor, const char* name,
                        int number, F::Type type, bool repeated = false) {
    const auto* field = descriptor->FindFieldByName(name);
    ASSERT_NE(field, nullptr);
    EXPECT_EQ(field->number(), number);
    EXPECT_EQ(field->type(), type);
    EXPECT_EQ(field->is_repeated(), repeated);
  };
  check(SessionInfo::descriptor(), "supports_offline_sync", 5, F::TYPE_BOOL);
  check(Conference::descriptor(), "generation", 17, F::TYPE_STRING);
  check(ListMessagesResponse::descriptor(), "generation", 5, F::TYPE_STRING);
  check(ListMessagesRequest::descriptor(), "after_message_id", 7, F::TYPE_STRING);
  check(ReadArchiveMessageRequest::descriptor(), "include_subfields", 5, F::TYPE_BOOL);
  check(ReadArchiveMessageResponse::descriptor(), "subfields", 6, F::TYPE_MESSAGE, true);
  check(ReadArchiveMessageResponse::descriptor(), "attributes2", 7, F::TYPE_UINT32);
  EXPECT_EQ(MESSAGE_SORT_NUMBER_ASCENDING, 3);
  EXPECT_FALSE(SessionInfo{}.supports_offline_sync());
  EXPECT_TRUE(Conference{}.generation().empty());
  EXPECT_TRUE(ListMessagesResponse{}.generation().empty());
  EXPECT_TRUE(ListMessagesRequest{}.after_message_id().empty());
  EXPECT_FALSE(ReadArchiveMessageRequest{}.include_subfields());
  EXPECT_EQ(ReadArchiveMessageResponse{}.attributes2(), 0u);
  EXPECT_EQ(ReadArchiveMessageResponse{}.subfields_size(), 0);
  SessionInfo session;
  session.set_supports_offline_sync(true);
  SessionInfo restored;
  ASSERT_TRUE(restored.ParseFromString(session.SerializeAsString()));
  EXPECT_TRUE(restored.supports_offline_sync());
  Conference conference;
  conference.set_generation("opaque");
  Conference conference_copy;
  ASSERT_TRUE(conference_copy.ParseFromString(conference.SerializeAsString()));
  EXPECT_EQ(conference_copy.generation(), "opaque");
  ListMessagesResponse list;
  list.set_generation("opaque");
  ListMessagesResponse list_copy;
  ASSERT_TRUE(list_copy.ParseFromString(list.SerializeAsString()));
  EXPECT_EQ(list_copy.generation(), "opaque");
  ListMessagesRequest request;
  request.set_sort(MESSAGE_SORT_NUMBER_ASCENDING);
  request.set_after_message_id("opaque#4294967295");
  ListMessagesRequest request_copy;
  ASSERT_TRUE(request_copy.ParseFromString(request.SerializeAsString()));
  EXPECT_EQ(request_copy.after_message_id(), request.after_message_id());
  EXPECT_EQ(request_copy.sort(), MESSAGE_SORT_NUMBER_ASCENDING);
  ReadArchiveMessageRequest read;
  read.set_include_subfields(true);
  ReadArchiveMessageRequest read_copy;
  ASSERT_TRUE(read_copy.ParseFromString(read.SerializeAsString()));
  EXPECT_TRUE(read_copy.include_subfields());
  ReadArchiveMessageResponse response;
  response.set_attributes2(0x80000001u);
  auto* field = response.add_subfields();
  field->set_low_id(65000);
  field->set_high_id(65535);
  field->set_value(std::string("A\0\xff", 3));
  ReadArchiveMessageResponse response_copy;
  ASSERT_TRUE(response_copy.ParseFromString(response.SerializeAsString()));
  EXPECT_EQ(response_copy.SerializeAsString(), response.SerializeAsString());
}
