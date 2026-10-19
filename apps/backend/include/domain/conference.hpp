#pragma once

#include <optional>
#include <string>
#include <vector>

#include "EchoAreaConfig.h"

namespace fidoback::domain {

/// @brief Представление FTN-эхоконференции в API.
struct Conference {
  std::string id;                 ///< Имя эхоконференции (напр. "comp.lang.dart")
  std::string name;               ///< Отображаемое имя
  std::string description;        ///< Описание
  int64_t unread_count = 0;       ///< Кол-во непрочитанных
  int64_t total_count = 0;        ///< Всего сообщений
  std::string last_message_date;  ///< ISO 8601
  int icon_code = 1234;
  std::string icon_font_family = "MaterialIcons";
  bool can_read = false;
  bool can_post = false;
  bool is_bookmarked = false;
  AreaKind kind = AreaKind::kEcho;
  std::string storage_format = "JAM";
  bool unsupported_format = false;
  bool statistics_known = true;
  bool personal_mailbox = false;
  std::string last_opened_message;
  uint64_t position_revision = 0;
};

/// @brief Список конференций с пагинацией.
struct ConferenceListResponse {
  std::vector<Conference> conferences;
  int64_t total = 0;
  bool has_more = false;
};

}  // namespace fidoback::domain
