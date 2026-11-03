#pragma once

#include <cstdint>
#include <expected>
#include <optional>
#include <string>
#include <vector>

#include "domain/personal_filters.hpp"

namespace fidoback::domain {

/// @brief Краткое представление сообщения (для списка).
struct MessageSummary {
  std::string id;
  std::string from_name;
  std::string from_address;
  std::string to_name;
  std::string to_address;
  std::string subject;
  std::string date;
  std::string body_preview;  ///< Первые 200 символов
  bool is_read = false;
  std::string thread_id;
  std::string ftn_message_id;
  uint32_t attributes = 0;
  int direction = 0;
  uint64_t position_revision = 0;
  std::optional<PersonalMessageCollapse> personal_collapse;
};

/// @brief Полное представление сообщения.
struct MessageDetail {
  std::string id;
  std::string from_name;
  std::string from_address;
  std::string to_name;
  std::string to_address;
  std::string subject;
  std::string date;
  std::string body;
  std::string thread_id;
  std::string ftn_message_id;
  uint32_t attributes = 0;
  int direction = 0;
  uint64_t position_revision = 0;
  std::optional<PersonalMessageCollapse> personal_collapse;
  std::string in_reply_to;
  bool is_read = false;
  std::vector<std::string> attachments;
  std::vector<std::string> ftn_kludges;
};

struct ArchiveMessage {
  MessageDetail message;
  uint64_t body_offset = 0, next_offset = 0;
  bool complete = false, collapsed = false;
};

struct MessageTechnicalSubfield {
  uint32_t low_id = 0, high_id = 0;
  std::string value;
};
struct MessageTechnicalData {
  std::string conference, id;
  uint32_t attributes = 0, attributes2 = 0;
  std::vector<MessageTechnicalSubfield> subfields;
  std::string effective_encoding;
};

struct SearchMatch {
  int field = 0;
  uint32_t start_utf16 = 0, length_utf16 = 0;
};
struct FindMessageResponse {
  std::optional<MessageDetail> message;
  std::vector<SearchMatch> matches;
};

struct MessagePresentation {
  MessageDetail message;
  uint64_t revision = 0;
  std::vector<std::string> rules;
  bool collapsed = false;
  std::vector<SearchMatch> matches;
};

struct MessageFooter {
  std::string tagline, origin;
};

/// @brief Запрос на создание сообщения.
struct CreateMessageRequest {
  std::string operation_id;
  std::string to_name;
  std::string to_address;
  std::string subject;
  std::string body;
  std::string in_reply_to;
  std::optional<MessageFooter> footer = std::nullopt;
  std::string expected_preview_digest = {};
};

struct MessagePreview {
  std::string conference, from_name, from_address, to_name, to_address, subject, body, encoding, digest, in_reply_to;
  uint64_t wire_body_bytes = 0;
  int kind = 0;
  bool public_message = false;
};

/// @brief Ответ на создание.
struct CreateMessageResponse {
  std::string id;
  std::string status = "saved_locally";
  std::string resolved_to_name, resolved_to_address;
  uint64_t wire_body_bytes = 0;
  std::string ftn_message_id;
  std::optional<MessagePreview> preview;
};

struct CrosspostCopy {
  std::string conference, id, ftn_message_id;
};
struct CreateCrosspostResponse {
  bool complete = false;
  std::vector<CrosspostCopy> saved;
  int total = 0;
  int pending_code = 0;
};

/// @brief Список сообщений с пагинацией.
struct MessageListResponse {
  int64_t actual_offset = 0;
  std::vector<MessageSummary> messages;
  int64_t total = 0;
  bool has_more = false;
};

struct ThreadListResponse {
  std::vector<MessageDetail> messages;
  int64_t total = 0;
  bool has_more = false;
};

}  // namespace fidoback::domain
