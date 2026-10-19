# FidoBack — План реализации v1.0

## Обзор

Проект: HTTP API-сервер для работы с FTN (FidoNet) месседж-базами (JAM/Squish).
Стек: C++23, cpp-httplib, nlohmann/json, spdlog, SQLite3, libiconv.
Архитектура: Layered (API → Service → Repository → Storage).

---

## Phase 0: Hotfix — Критические исправления (1-2 дня)

> **Цель:** Устранить data races, утечки ресурсов, уязвимости безопасности.

### 0.1 Data race на глобальных переменных
**Файл:** `src/main.cpp`

**Проблема:** `config_manager` и `jam_base_path` — глобальные `shared_ptr`/`string`, читаются из ThreadPool без синхронизации.

**Решение:** Убрать глобальные переменные. Передать зависимости через лямбда-захват в обработчики:

```cpp
// БЫЛО (main.cpp:22-23):
std::shared_ptr<ConfigManager> config_manager = nullptr;
std::string jam_base_path = JAM_BASE_PATH;

// СТАЛО:
struct ServerDeps {
  std::shared_ptr<ConfigManager> config_manager;
  std::filesystem::path jam_base_path;
  std::shared_ptr<MetadataStore> metadata;  // из Phase 4
  std::shared_ptr<AuthService> auth;         // из Phase 6
};

// Передаём через capture:
auto deps = std::make_shared<ServerDeps>(...);
srv.Get("/conferences", [deps](const auto& req, auto& res) {
  handleConferences(*deps, req, res);
});
```

### 0.2 Path traversal
**Файл:** `src/main.cpp:179`

**Проблема:** `echo_area` из URL конкатенируется напрямую → чтение произвольных файлов.

**Решение:**
```cpp
// Санитизация:
std::filesystem::path full = jam_base_path / echo_area;
if (!std::filesystem::lexically_relative(full, jam_base_path).has_value()) {
  return error_response(res, 400, "Invalid conference_id");
}
// Дополнительно: проверка что файл существует и имеет .jhr/.sqd расширение
```

### 0.3 RAII для файловых дескрипторов
**Файл:** `include/JamMessageBase.h`, `include/SquishMessageBase.h`

**Проблема:** Нет деструктора → при исключении файловые дескрипторы утекают.

**Решение:**
```cpp
~JamMessageBase() { Close(); }  // в класс
~SquishMessageBase() { Close(); }  // в класс
```

### 0.4 std::localtime → localtime_r
**Файл:** `include/SquishMessageBase.h:167`

**Проблема:** `std::localtime()` возвращает указатель на статический буфер — data race.

**Решение:**
```cpp
// БЫЛО:
std::tm* tm = std::localtime(&t);

// СТАЛО (POSIX):
std::tm tm{};
localtime_r(&t, &tm);
```

### 0.5 CRC mismatch без предупреждения
**Файл:** `include/SquishMessageBase.h:482-484`

**Проблема:** Повреждённые сообщения возвращаются молча.

**Решение:**
```cpp
if (index_record.crc != to_hash) {
  spdlog::warn("CRC mismatch for message {} in Squish base", msg_num);
  // Не блокируем, но логируем — для совместимости
}
```

### 0.6 const_cast<char*> для iconv
**Файл:** `src/main.cpp:38`

**Проблема:** Формальное UB.

**Решение:** Копировать входной буфер:
```cpp
std::string in_buf = text;  // копия для модификации
char* in_ptr = in_buf.data();
```

---

## Phase 1: Рефакторинг архитектуры (2-3 дня)

> **Цель:** Разделить interface/implementation, исправить антипаттерны контейнеров.

### 1.1 Разделить .h и .cpp для JamMessageBase

**Новая структура:**
```
include/msgapi/JamMessageBase.h     — только объявления + docs
include/msgapi/JamMessageBase_fwd.h — forward declarations
src/msgapi/JamMessageBase.cpp       — реализация
include/msgapi/JamMessage.h         — класс JamMessage
include/msgapi/JamTypes.h           — enums, structs, constants
src/msgapi/JamMessage.cpp           — реализация JamMessage
```

**JamMessageBase.h (интерфейс):**
```cpp
namespace msgapi {

/// @brief RAII-обёртка для работы с JAM message base.
/// @thread_safety Не потокобезопасен. Один экземпляр — один поток.
class JamMessageBase {
 public:
  explicit JamMessageBase(std::filesystem::path base_path);
  ~JamMessageBase();

  JamMessageBase(const JamMessageBase&) = delete;
  JamMessageBase& operator=(const JamMessageBase&) = delete;
  JamMessageBase(JamMessageBase&&) noexcept;
  JamMessageBase& operator=(JamMessageBase&&) noexcept;

  [[nodiscard]] JamError Open();
  void Close();
  [[nodiscard]] bool is_open() const;

  [[nodiscard]] std::expected<std::vector<uint32_t>, JamError> GetMessageNumbers() const;
  [[nodiscard]] std::expected<JamMessage, JamError> ReadMessage(uint32_t msg_num) const;
  [[nodiscard]] JamError AddMessage(const JamMessage& message);
  [[nodiscard]] JamError DeleteMessage(uint32_t msg_num);

  [[nodiscard]] uint32_t message_count() const;

 private:
  // ... private методы
};

}  // namespace msgapi
```

### 1.2 Разделить .h и .cpp для SquishMessageBase

Аналогично Phase 1.1:
```
include/msgapi/SquishMessageBase.h
include/msgapi/SquishMessage.h
include/msgapi/SquishTypes.h
src/msgapi/SquishMessageBase.cpp
src/msgapi/SquishMessage.cpp
```

### 1.3 Исправить контейнеры в JamMessage

**Проблема:** `std::map<JamSubFieldType, std::unique_ptr<JamSubField>>`

**Решение:** `std::vector<JamSubField>` или `absl::flat_hash_map` / `std::unordered_map`:

```cpp
// БЫЛО:
std::map<JamSubFieldType, std::unique_ptr<JamSubField>> subfields_;

// СТАЛО:
std::vector<JamSubField> subfields_;  // для малого кол-ва подполей (обычно < 20)
// или:
std::unordered_map<JamSubFieldType, JamSubField> subfields_;  // если > 50
```

**Обоснование:** `std::vector` для < 20 элементов быстрее `std::map` за счёт locality. Нет heap-аллокаций на элемент.

### 1.4 Crc32IgnoreCase без аллокации

**Файл:** `include/JamMessageBase.h`

```cpp
// БЫЛО:
inline uint32_t Crc32IgnoreCase(std::string_view data) {
  std::string lower_data;
  lower_data.reserve(data.size());
  std::transform(data.begin(), data.end(), std::back_inserter(lower_data),
                 [](unsigned char c) { return std::tolower(c); });
  return Crc32(lower_data);
}

// СТАЛО:
inline uint32_t Crc32IgnoreCase(std::string_view data) {
  uint32_t crc = 0xFFFFFFFF;
  for (unsigned char c : data) {
    uint8_t lower = static_cast<uint8_t>(std::tolower(c));
    crc = (crc >> 8) ^ kCrc32Table[(crc ^ lower) & 0xFF];
  }
  return ~crc;
}
```

### 1.5 Параметры функций — string_view вместо const string&

**Файлы:** `include/Config.h`, `src/Config.cpp`

```cpp
// БЫЛО:
std::shared_ptr<Config> createConfig(const std::string ip, const uint16_t port, ...);

// СТАЛО:
[[nodiscard]] std::shared_ptr<Config> createConfig(
    std::string_view ip,
    uint16_t port,
    size_t thread_num,
    std::string_view areacfg,
    std::string_view jam_base_path);
```

### 1.6 Убрать using namespace std;

**Файл:** `src/EchoAreaConfig.cpp:8`

Заменить все `string` → `std::string`, `vector` → `std::vector`, etc.

### 1.7 static_assert для packed-структур

```cpp
static_assert(sizeof(JamBaseHeader) == 1024, "JamBaseHeader size mismatch");
static_assert(sizeof(JamMessageHeader) == 76, "JamMessageHeader size mismatch");
static_assert(sizeof(JamSubFieldHeader) == 8, "JamSubFieldHeader size mismatch");
static_assert(sizeof(SquishBaseHeader) == 256, "SquishBaseHeader size mismatch");
static_assert(sizeof(SquishFrameHeader) == 164, "SquishFrameHeader size mismatch");
```

### 1.8 Добавить [[nodiscard]]

На все методы, возвращающие `JamError`, `SquishError`, `std::expected`.

---

## Phase 2: CMake modernization (0.5 дня)

### 2.1 target-based include directories

```cmake
# БЫЛО:
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

# СТАЛО:
target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
```

### 2.2 Явный список исходников (убрать GLOB)

```cmake
# БЫЛО:
file(GLOB CORE_SOURCES CONFIGURE_DEPENDS "src/*.cpp")

# СТАЛО:
set(FIDOBACK_SOURCES
  src/main.cpp
  src/Config.cpp
  src/EchoAreaConfig.cpp
  src/msgapi/JamMessageBase.cpp
  src/msgapi/JamMessage.cpp
  src/msgapi/SquishMessageBase.cpp
  src/msgapi/SquishMessage.cpp
  src/service/ConferenceService.cpp
  src/service/MessageService.cpp
  src/service/MetadataService.cpp
  src/service/AuthService.cpp
  src/storage/SQLiteMetadataStore.cpp
  src/http/handlers.cpp
  src/http/middleware.cpp
  src/http/router.cpp
  src/http/json_serialization.cpp
)

add_executable(${PROJECT_NAME} ${FIDOBACK_SOURCES})
```

### 2.3 Sanitizer configuration

```cmake
option(FIDOBACK_ENABLE_ASAN "Enable AddressSanitizer" OFF)
option(FIDOBACK_ENABLE_TSAN "Enable ThreadSanitizer" OFF)

if(FIDOBACK_ENABLE_ASAN)
  target_compile_options(${PROJECT_NAME} PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(${PROJECT_NAME} PRIVATE -fsanitize=address)
endif()

if(FIDOBACK_ENABLE_TSAN)
  target_compile_options(${PROJECT_NAME} PRIVATE -fsanitize=thread)
  target_link_options(${PROJECT_NAME} PRIVATE -fsanitize=thread)
endif()
```

### 2.4 Добавить SQLite3

```cmake
find_package(SQLite3 REQUIRED)
# или FetchContent если системной нет:
FetchContent_Declare(
  sqlite3
  URL https://www.sqlite.org/2025/sqlite-autoconf-3490100.tar.gz
)
FetchContent_MakeAvailable(sqlite3)

target_link_libraries(${PROJECT_NAME} PRIVATE SQLite::SQLite3)
```

### 2.5 FetchContent shallow clone

```cmake
FetchContent_Declare(spdlog
  GIT_REPOSITORY https://github.com/gabime/spdlog.git
  GIT_TAG v1.15.3
  GIT_SHALLOW TRUE  # экономим трафик
)
```

---

## Phase 3: Domain models и DTO (2-3 дня)

> **Цель:** Строго типизированные DTO для API контрактов, валидация, сериализация.

### 3.1 Структура файлов

```
include/domain/
  conference.hpp       — Conference DTO
  message.hpp          — Message DTO (list + detail)
  profile.hpp          — Profile DTO
  bookmark.hpp         — Bookmark DTO
  thread.hpp           — Thread DTO
  pagination.hpp       — PaginationRequest / PaginatedResponse<T>
  error.hpp            — ApiError, ValidationException

include/domain/impl/   — inline-реализация мелких методов (если нужно)

src/domain/
  conference.cpp       — сериализация Conference
  message.cpp          — сериализация Message
  pagination.cpp       — валидация offset/limit
  error.cpp            — формирование JSON ошибок
```

### 3.2 Conference DTO

```cpp
namespace fidoback::domain {

/// @brief Представление FTN-эхоконференции в API.
struct Conference {
  std::string id;              ///< Имя эхоконференции (напр. "comp.lang.dart")
  std::string name;            ///< Отображаемое имя
  std::string description;     ///< Описание (из config или kludge)
  int64_t unread_count;        ///< Кол-во непрочитанных (из metadata store)
  int64_t total_count;         ///< Всего сообщений (из JAM/Squish)
  std::string last_message_date; ///< ISO 8601, напр. "2026-04-02T18:30:00Z"
  int icon_code;               ///< Код иконки для клиента
  std::string icon_font_family;///< "MaterialIcons"
  bool is_bookmarked;          ///<true если в закладках пользователя

  /// Сериализация в JSON.
  [[nodiscard]] nlohmann::json ToJson() const;
  /// Десериализация из JSON.
  [[nodiscard]] static std::expected<Conference, ApiError> FromJson(
      const nlohmann::json& j);
};

/// @brief Список конференций с пагинацией.
struct ConferenceListResponse {
  std::vector<Conference> conferences;
  int64_t total;
  bool has_more;

  [[nodiscard]] nlohmann::json ToJson() const;
};

}  // namespace fidoback::domain
```

### 3.3 Message DTO

```cpp
namespace fidoback::domain {

/// @brief Краткое представление сообщения (для списка).
struct MessageSummary {
  std::string id;              ///< UUID или "msg_{hash}"
  std::string from_name;
  std::string from_address;    ///< FTN-адрес, напр. "2:5015/120.25"
  std::string to_name;
  std::string to_address;
  std::string subject;
  std::string date;            ///< ISO 8601
  std::string body_preview;    ///< Первые 200 символов
  bool is_read;
  std::string thread_id;       ///< ID цепочки (reply chain)

  [[nodiscard]] nlohmann::json ToJson() const;
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
  std::string body;            ///< Полный текст
  std::string thread_id;
  std::string in_reply_to;     ///< ID родительского сообщения (пусто если root)
  bool is_read;
  std::vector<std::string> attachments;  ///< Пока пусто — placeholder

  [[nodiscard]] nlohmann::json ToJson() const;
};

/// @brief Запрос на создание сообщения.
struct CreateMessageRequest {
  std::string to_name;
  std::string to_address;
  std::string subject;
  std::string body;
  std::string in_reply_to;  ///< пустой = новое сообщение

  [[nodiscard]] static std::expected<CreateMessageRequest, ApiError> FromJson(
      const nlohmann::json& j);
};

/// @brief Ответ на создание.
struct CreateMessageResponse {
  std::string id;
  std::string status;  // "sent"

  [[nodiscard]] nlohmann::json ToJson() const;
};

/// @brief Список сообщений с пагинацией.
struct MessageListResponse {
  std::vector<MessageSummary> messages;
  int64_t total;
  bool has_more;

  [[nodiscard]] nlohmann::json ToJson() const;
};

}  // namespace fidoback::domain
```

### 3.4 Pagination DTO

```cpp
namespace fidoback::domain {

/// @brief Параметры пагинации.
struct PaginationRequest {
  int64_t offset = 0;
  int64_t limit = 20;

  /// Валидация: offset >= 0, 1 <= limit <= 100.
  [[nodiscard]] static std::expected<PaginationRequest, ApiError> FromQuery(
      const httplib::Request& req);
};

/// @brief Пагинированный ответ.
template <typename T>
struct PaginatedResponse {
  std::vector<T> items;
  int64_t total;
  bool has_more;

  [[nodiscard]] nlohmann::json ToJson() const
    requires std::is_same_v<T, Conference> ||
             std::is_same_v<T, MessageSummary>;
};

}  // namespace fidoback::domain
```

### 3.5 Profile DTO

```cpp
namespace fidoback::domain {

struct Profile {
  std::string name;
  std::string address;       ///< FTN-адрес
  std::string email;
  std::string registered_at; ///< ISO 8601

  [[nodiscard]] nlohmann::json ToJson() const;
  [[nodiscard]] static std::expected<Profile, ApiError> FromJson(
      const nlohmann::json& j);
};

}  // namespace fidoback::domain
```

### 3.6 Error DTO

```cpp
namespace fidoback::domain {

enum class ErrorCode {
  kUnauthorized = 401,
  kNotFound = 404,
  kValidation = 422,
  kServer = 500,
  kNetwork = 503,
};

struct ErrorDetail {
  std::string field;
  std::string message;
};

struct ApiError {
  ErrorCode code;
  std::string message;
  std::vector<ErrorDetail> details;  ///< Для ValidationException

  [[nodiscard]] nlohmann::json ToJson() const;
  [[nodiscard]] int HttpStatus() const;
};

}  // namespace fidoback::domain
```

### 3.7 Конвертация FTN → API DTO

Ключевой маппинг. Определяем в `src/service/DtoMapper.cpp`:

```cpp
namespace fidoback::service {

/// @brief Конвертирует JamMessage → domain::MessageDetail.
domain::MessageDetail ToMessageDetail(
    const msgapi::JamMessage& msg,
    uint32_t msg_num,
    std::string_view conference_id,
    bool is_read);

/// @brief Конвертирует EchoAreaConfig → domain::Conference.
domain::Conference ToConference(
    const EchoAreaConfig& config,
    int64_t total_count,
    std::string_view last_message_date,
    bool is_bookmarked,
    int64_t unread_count);

// Аналогично для SquishMessage.

}  // namespace fidoback::service
```

---

## Phase 4: SQLite Metadata Store (2-3 дня)

> **Цель:** Хранение закладок, истории, read-статусов, профиля.

### 4.1 Структура файлов

```
include/storage/
  metadata_store.hpp    — абстрактный интерфейс
  sqlite_store.hpp      — SQLite реализзация

src/storage/
  sqlite_store.cpp      — реализация + schema init
```

### 4.2 Интерфейс

```cpp
namespace fidoback::storage {

/// @brief Абстрактный интерфейс для хранения метаданных.
/// @thread_safety Потокобезопасен (internal mutex).
class IMetadataStore {
 public:
  virtual ~IMetadataStore() = default;

  // Bookmarks
  [[nodiscard]] virtual std::expected<std::vector<std::string>, ApiError>
  GetBookmarks(std::string_view user_id) = 0;
  [[nodiscard]] virtual std::expected<void, ApiError>
  AddBookmark(std::string_view user_id, std::string_view conference_id) = 0;
  [[nodiscard]] virtual std::expected<void, ApiError>
  RemoveBookmark(std::string_view user_id, std::string_view conference_id) = 0;

  // History
  [[nodiscard]] virtual std::expected<std::vector<std::string>, ApiError>
  GetHistory(std::string_view user_id, int64_t limit) = 0;
  [[nodiscard]] virtual std::expected<void, ApiError>
  ClearHistory(std::string_view user_id) = 0;
  [[nodiscard]] virtual std::expected<void, ApiError>
  AddToHistory(std::string_view user_id, std::string_view conference_id) = 0;

  // Read status
  [[nodiscard]] virtual std::expected<bool, ApiError>
  IsMessageRead(std::string_view user_id, std::string_view msg_id) = 0;
  [[nodiscard]] virtual std::expected<void, ApiError>
  MarkMessageRead(std::string_view user_id, std::string_view msg_id) = 0;
  [[nodiscard]] virtual std::expected<int64_t, ApiError>
  GetUnreadCount(std::string_view user_id, std::string_view conference_id) = 0;

  // Profile
  [[nodiscard]] virtual std::expected<domain::Profile, ApiError>
  GetProfile(std::string_view user_id) = 0;
  [[nodiscard]] virtual std::expected<void, ApiError>
  SaveProfile(std::string_view user_id, const domain::Profile& profile) = 0;
};

}  // namespace fidoback::storage
```

### 4.3 SQLite Schema

```sql
-- Таблица пользователей (пока один, потом auth)
CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    ftn_address TEXT NOT NULL,
    email TEXT,
    registered_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Закладки
CREATE TABLE IF NOT EXISTS bookmarks (
    user_id TEXT NOT NULL,
    conference_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, conference_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- История просмотров
CREATE TABLE IF NOT EXISTS history (
    user_id TEXT NOT NULL,
    conference_id TEXT NOT NULL,
    viewed_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, conference_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Read status
CREATE TABLE IF NOT EXISTS read_status (
    user_id TEXT NOT NULL,
    message_id TEXT NOT NULL,
    conference_id TEXT NOT NULL,
    read_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, message_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_history_user_time ON history(user_id, viewed_at DESC);
CREATE INDEX IF NOT EXISTS idx_read_status_user_conf ON read_status(user_id, conference_id);
```

### 4.4 SQLite реализация (ключевые моменты)

```cpp
namespace fidoback::storage {

/// @brief SQLite-реализация IMetadataStore.
/// @thread_safety Потокобезопасна через WAL mode + mutex.
class SQLiteMetadataStore final : public IMetadataStore {
 public:
  /// @param db_path Путь к SQLite файлу.
  /// @throws ApiError если не удалось открыть БД.
  explicit SQLiteMetadataStore(std::filesystem::path db_path);
  ~SQLiteMetadataStore() override;

  SQLiteMetadataStore(const SQLiteMetadataStore&) = delete;
  SQLiteMetadataStore& operator=(const SQLiteMetadataStore&) = delete;

  // ... реализация IMetadataStore

 private:
  void InitSchema();  // CREATE TABLE IF NOT EXISTS ...

  sqlite3* db_;
  mutable std::mutex mutex_;
  std::filesystem::path db_path_;
};

}  // namespace fidoback::storage
```

**Ключевые SQLite-запросы:**

```sql
-- GetBookmarks
SELECT conference_id FROM bookmarks WHERE user_id = ? ORDER BY created_at DESC;

-- AddBookmark (INSERT OR IGNORE)
INSERT OR IGNORE INTO bookmarks (user_id, conference_id) VALUES (?, ?);

-- RemoveBookmark
DELETE FROM bookmarks WHERE user_id = ? AND conference_id = ?;

-- GetHistory (LIMIT)
SELECT conference_id FROM history WHERE user_id = ? ORDER BY viewed_at DESC LIMIT ?;

-- AddToHistory (UPSERT)
INSERT INTO history (user_id, conference_id) VALUES (?, ?)
ON CONFLICT(user_id, conference_id) DO UPDATE SET viewed_at = datetime('now');

-- IsMessageRead
SELECT COUNT(1) > 0 FROM read_status WHERE user_id = ? AND message_id = ?;

-- MarkMessageRead (UPSERT)
INSERT INTO read_status (user_id, message_id, conference_id) VALUES (?, ?, ?)
ON CONFLICT(user_id, message_id) DO UPDATE SET read_at = datetime('now');

-- GetUnreadCount
SELECT total_count - COUNT(rs.message_id)
FROM (SELECT COUNT(1) as total_count FROM messages WHERE conference_id = ?) m
LEFT JOIN read_status rs ON rs.conference_id = ? AND rs.user_id = ?;

-- GetProfile
SELECT name, ftn_address, email, registered_at FROM users WHERE user_id = ?;
```

---

## Phase 5: HTTP handlers — полный API (3-4 дня)

> **Цель:** Реализовать все 10 эндпоинтов из README.md.

### 5.1 Структура файлов

```
include/http/
  router.hpp          — регистрация маршрутов
  handlers.hpp        — объявления handler-функций
  middleware.hpp      — auth, logging, cors
  json_serialization.hpp — общие утилиты сериализации
  response_helpers.hpp — helpers для JSON-ответов

src/http/
  router.cpp
  handlers/
    conference_handler.cpp
    message_handler.cpp
    bookmark_handler.cpp
    history_handler.cpp
    profile_handler.cpp
  middleware.cpp
  json_serialization.cpp
  response_helpers.cpp
```

### 5.2 Router

```cpp
namespace fidoback::http {

struct RouterDeps {
  std::shared_ptr<ConfigManager> config_manager;
  std::shared_ptr<service::ConferenceService> conference_service;
  std::shared_ptr<service::MessageService> message_service;
  std::shared_ptr<storage::IMetadataStore> metadata;
  std::shared_ptr<service::AuthService> auth;
};

/// @brief Регистрирует все маршруты на сервере.
void RegisterRoutes(httplib::Server& srv, const RouterDeps& deps);

}  // namespace fidoback::http
```

### 5.3 Маршруты

| Метод | Путь | Handler | Status |
|-------|------|---------|--------|
| GET | `/conferences` | `handleGetConferences` | 200 |
| GET | `/conferences/{id}/messages` | `handleGetMessages` | 200 |
| GET | `/conferences/{id}/messages/{msg_id}` | `handleGetMessage` | 200 |
| POST | `/conferences/{id}/messages` | `handleCreateMessage` | 201 |
| POST | `/conferences/{id}/messages/{msg_id}/read` | `handleMarkRead` | 200 |
| GET | `/conferences/{id}/threads/{thread_id}` | `handleGetThread` | 200 |
| GET | `/bookmarks` | `handleGetBookmarks` | 200 |
| POST | `/bookmarks` | `handleAddBookmark` | 201 |
| DELETE | `/bookmarks/{conference_id}` | `handleRemoveBookmark` | 200 |
| GET | `/history` | `handleGetHistory` | 200 |
| DELETE | `/history` | `handleClearHistory` | 200 |
| GET | `/profile` | `handleGetProfile` | 200 |

### 5.4 Service layer

```
include/service/
  conference_service.hpp
  message_service.hpp
  metadata_service.hpp     — фасад над IMetadataStore
  auth_service.hpp

src/service/
  conference_service.cpp
  message_service.cpp
  metadata_service.cpp
  auth_service.cpp
```

#### ConferenceService

```cpp
namespace fidoback::service {

class ConferenceService {
 public:
  ConferenceService(
      std::shared_ptr<ConfigManager> config_manager,
      std::shared_ptr<storage::IMetadataStore> metadata,
      std::filesystem::path msg_base_path);

  /// @brief Получить список конференций с пагинацией и поиском.
  [[nodiscard]] std::expected<domain::ConferenceListResponse, domain::ApiError>
  GetConferences(
      const domain::PaginationRequest& pagination,
      std::optional<std::string_view> search,
      std::string_view user_id);

  /// @brief Получить конфигурацию конкретной конференции.
  [[nodiscard]] std::expected<domain::Conference, domain::ApiError>
  GetConference(std::string_view conference_id, std::string_view user_id);

 private:
  std::shared_ptr<ConfigManager> config_manager_;
  std::shared_ptr<storage::IMetadataStore> metadata_;
  std::filesystem::path msg_base_path_;
};

}  // namespace fidoback::service
```

#### MessageService

```cpp
namespace fidoback::service {

class MessageService {
 public:
  MessageService(
      std::filesystem::path msg_base_path,
      std::shared_ptr<storage::IMetadataStore> metadata);

  /// @brief Список сообщений конференции.
  [[nodiscard]] std::expected<domain::MessageListResponse, domain::ApiError>
  GetMessages(
      std::string_view conference_id,
      const domain::PaginationRequest& pagination,
      std::string_view sort,  // "newest" | "oldest"
      std::string_view user_id);

  /// @brief Одно сообщение полностью.
  [[nodiscard]] std::expected<domain::MessageDetail, domain::ApiError>
  GetMessage(
      std::string_view conference_id,
      std::string_view message_id,
      std::string_view user_id);

  /// @brief Создать сообщение (новое или ответ).
  [[nodiscard]] std::expected<domain::CreateMessageResponse, domain::ApiError>
  CreateMessage(
      std::string_view conference_id,
      const domain::CreateMessageRequest& request,
      std::string_view user_id);

  /// @brief Отметить сообщение как прочитанное.
  [[nodiscard]] std::expected<void, domain::ApiError>
  MarkAsRead(std::string_view conference_id, std::string_view message_id,
             std::string_view user_id);

  /// @brief Получить thread (цепочку ответов).
  [[nodiscard]] std::expected<std::vector<domain::MessageDetail>, domain::ApiError>
  GetThread(std::string_view conference_id, std::string_view thread_id,
            std::string_view user_id);

 private:
  std::filesystem::path msg_base_path_;
  std::shared_ptr<storage::IMetadataStore> metadata_;
};

}  // namespace fidoback::service
```

### 5.5 Middleware

```cpp
namespace fidoback::http {

/// @brief Middleware: проверка JWT токена.
std::function<bool(const httplib::Request&, httplib::Response&)>
AuthMiddleware(std::shared_ptr<service::AuthService> auth);

/// @brief Middleware: логирование запросов.
void LoggingMiddleware(const httplib::Request& req, const httplib::Response& res);

/// @brief Middleware: CORS headers.
void CorsMiddleware(httplib::Response& res);

/// @brief Helper: отправка JSON-ошибки.
void SendError(httplib::Response& res, const domain::ApiError& error);

/// @brief Helper: парсинг user_id из JWT claims.
std::expected<std::string, domain::ApiError>
ExtractUserId(const httplib::Request& req);

}  // namespace fidoback::http
```

---

## Phase 6: JWT Authentication (1-2 дня)

> **Цель:** Middleware для авторизации через JWT.

### 6.1 Структура

```
include/service/
  auth_service.hpp

src/service/
  auth_service.cpp
```

### 6.2 AuthService

```cpp
namespace fidoback::service {

/// @brief Сервис авторизации через JWT.
class AuthService {
 public:
  /// @param secret_key Секретный ключ для HMAC-SHA256.
  /// @param token_ttl Время жизни токена.
  explicit AuthService(std::string_view secret_key,
                       std::chrono::seconds token_ttl = std::chrono::hours(24));

  /// @brief Валидирует JWT и возвращает user_id.
  [[nodiscard]] std::expected<std::string, domain::ApiError>
  ValidateToken(std::string_view token) const;

  /// @brief Генерирует новый JWT для пользователя.
  [[nodiscard]] std::string GenerateToken(std::string_view user_id) const;

 private:
  std::string secret_key_;
  std::chrono::seconds token_ttl_;
};

}  // namespace fidoback::service
```

**Реализация JWT:** используем `openssl` или лёгкую `jwt-cpp` библиотеку:

```cmake
FetchContent_Declare(
  jwt_cpp
  GIT_REPOSITORY https://github.com/Thalhammer/jwt-cpp.git
  GIT_TAG v0.8.0
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(jwt_cpp)

target_link_libraries(${PROJECT_NAME} PRIVATE jwt-cpp)
```

**Header формат:** `Authorization: Bearer <token>`

---

## Phase 7: Тесты и документация (2-3 дня)

### 7.1 Unit-тесты

```
tests/
  unit/
    test_jam_message.cpp
    test_jam_message_base.cpp
    test_squish_message.cpp
    test_squish_message_base.cpp
    test_config_parser.cpp
    test_dto_serialization.cpp
    test_pagination.cpp
    test_crc32.cpp
    test_iconv.cpp
    test_sqlite_store.cpp
    test_auth_service.cpp
```

Фреймворк: GoogleTest (FetchContent).

```cmake
FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG v1.16.0
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(googletest)

add_executable(fidoback_tests
  tests/unit/test_jam_message.cpp
  tests/unit/test_config_parser.cpp
  # ...
)
target_link_libraries(fidoback_tests PRIVATE GTest::gtest_main fidoback_lib)
```

### 7.2 Integration-тесты

```
tests/
  integration/
    test_api_conferences.cpp
    test_api_messages.cpp
    test_api_bookmarks.cpp
    test_api_profile.cpp
```

Тестирование через `httplib::Client` к тестовому серверу.

### 7.3 Doxygen

```cmake
# В CMakeLists.txt (опционально):
find_package(Doxygen)
if(DOXYGEN_FOUND)
  set(DOXYGEN_GENERATE_HTML YES)
  set(DOXYGEN_OUTPUT_DIRECTORY docs)
  doxygen_add_docs(docs include src)
endif()
```

**Doxygen-стиль для всех публичных API:**

```cpp
/// @brief Получает список сообщений конференции с пагинацией.
/// @param conference_id Идентификатор конференции (эхоконференции).
/// @param pagination Параметры пагинации (offset, limit).
/// @param sort Порядок сортировки: "newest" или "oldest".
/// @param user_id Идентификатор пользователя (для read-status).
/// @return Пагинированный список сообщений.
/// @retval Error{404} Если конференция не найдена.
/// @retval Error{500} Если ошибка чтения JAM-базы.
/// @thread_safety Потокобезопасен.
[[nodiscard]] std::expected<domain::MessageListResponse, domain::ApiError>
GetMessages(std::string_view conference_id,
            const domain::PaginationRequest& pagination,
            std::string_view sort,
            std::string_view user_id);
```

---

## Финальная структура проекта

```
fidoback/
├── CMakeLists.txt
├── README.md
├── include/
│   ├── Config.h
│   ├── EchoAreaConfig.h
│   ├── domain/
│   │   ├── conference.hpp
│   │   ├── message.hpp
│   │   ├── profile.hpp
│   │   ├── bookmark.hpp
│   │   ├── pagination.hpp
│   │   └── error.hpp
│   ├── msgapi/
│   │   ├── JamMessageBase.h
│   │   ├── JamMessage.h
│   │   ├── JamTypes.h
│   │   ├── SquishMessageBase.h
│   │   ├── SquishMessage.h
│   │   └── SquishTypes.h
│   ├── service/
│   │   ├── conference_service.hpp
│   │   ├── message_service.hpp
│   │   ├── metadata_service.hpp
│   │   └── auth_service.hpp
│   ├── storage/
│   │   ├── metadata_store.hpp
│   │   └── sqlite_store.hpp
│   └── http/
│       ├── router.hpp
│       ├── handlers.hpp
│       ├── middleware.hpp
│       └── response_helpers.hpp
├── src/
│   ├── main.cpp
│   ├── Config.cpp
│   ├── EchoAreaConfig.cpp
│   ├── domain/
│   │   ├── conference.cpp
│   │   ├── message.cpp
│   │   ├── pagination.cpp
│   │   └── error.cpp
│   ├── msgapi/
│   │   ├── JamMessageBase.cpp
│   │   ├── JamMessage.cpp
│   │   ├── SquishMessageBase.cpp
│   │   └── SquishMessage.cpp
│   ├── service/
│   │   ├── conference_service.cpp
│   │   ├── message_service.cpp
│   │   ├── metadata_service.cpp
│   │   ├── auth_service.cpp
│   │   └── DtoMapper.cpp
│   ├── storage/
│   │   └── sqlite_store.cpp
│   └── http/
│       ├── router.cpp
│       ├── handlers/
│       │   ├── conference_handler.cpp
│       │   ├── message_handler.cpp
│       │   ├── bookmark_handler.cpp
│       │   ├── history_handler.cpp
│       │   └── profile_handler.cpp
│       ├── middleware.cpp
│       └── response_helpers.cpp
├── tests/
│   ├── unit/
│   └── integration/
└── docs/  (Doxygen output)
```

---

## Порядок выполнения (зависимости)

```
Phase 0 (hotfix) ──────────────────────────────────────┐
Phase 1 (refactor) ────────────────────────────────────┤
Phase 2 (cmake)  ──────────────────────────────────────┼──▶ Phase 3 (DTO)
                                                       ├──▶ Phase 4 (SQLite)
                                                       ┘
Phase 3 (DTO) ─────────────────────────────────────────┐
Phase 4 (SQLite) ──────────────────────────────────────┼──▶ Phase 5 (HTTP API)
                                                       ┘
Phase 5 (HTTP API) ────────────────────────────────────┐
Phase 6 (JWT Auth) ────────────────────────────────────┼──▶ Phase 7 (Tests + Docs)
                                                       ┘
```

---

## Ключевые решения

| Решение | Выбор | Обоснование |
|---------|-------|-------------|
| Хранение метаданных | SQLite + WAL mode | Лёгкий, транзакционный, без доп. процессов |
| Контейнер подполей | `std::vector<JamSubField>` | < 20 элементов → cache-friendly, без heap per item |
| JWT библиотека | jwt-cpp (header-only) | Нет runtime dependency, compile-time |
| Пагинация | offset/limit | Просто, соответствует контракту |
| ID сообщений | `{conference_id}_{msg_num}` | Детерминированный, без UUID |
| Thread ID | Reply chain через `reply_to` → root | FTN reply tracking |
| Конвертация времени | JAM Unix timestamp → ISO 8601 | Стандарт API |
| Read-status | Отдельная таблица SQLite | Не модифицируем JAM-базу |
