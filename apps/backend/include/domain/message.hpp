#pragma once

#include <cstdint>
#include <expected>
#include <optional>
#include <string>
#include <vector>

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
  std::string in_reply_to;
  bool is_read = false;
  std::vector<std::string> attachments;
  std::vector<std::string> ftn_kludges;
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
};

/// @brief Ответ на создание.
struct CreateMessageResponse {
  std::string id;
  std::string status = "saved_locally";
  std::string resolved_to_name, resolved_to_address;
  uint64_t wire_body_bytes = 0;
  std::string ftn_message_id;
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
