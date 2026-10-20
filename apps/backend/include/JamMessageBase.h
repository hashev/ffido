#pragma once
#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <expected>
#include <fstream>
#include <functional>
#include <limits>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "storage/text_codec.hpp"
#include "storage/jam_file.hpp"

namespace msgapi {

// Константы JAM
constexpr uint32_t kJamSignature = 0x004D414A;  // 'JAM\0'
constexpr uint16_t kJamRevision = 1;
constexpr size_t kJamBaseHeaderSize = 1024;
constexpr uint32_t kInvalidOffset = 0xFFFFFFFF;

// Атрибуты сообщений
enum class JamMessageAttribute : uint32_t {
  kLocal = 0x00000001,
  kInTransit = 0x00000002,
  kPrivate = 0x00000004,
  kRead = 0x00000008,
  kSent = 0x00000010,
  kKillSent = 0x00000020,
  kArchiveSent = 0x00000040,
  kHold = 0x00000080,
  kCrash = 0x00000100,
  kImmediate = 0x00000200,
  kDirect = 0x00000400,
  kGate = 0x00000800,
  kFileRequest = 0x00001000,
  kFileAttached = 0x00002000,
  kTruncFile = 0x00004000,
  kKillFile = 0x00008000,
  kReceiptRequest = 0x00010000,
  kConfirmRequest = 0x00020000,
  kOrphan = 0x00040000,
  kEncrypted = 0x00080000,
  kCompressed = 0x00100000,
  kEscaped = 0x00200000,
  kFpu = 0x00400000,
  kTypeLocal = 0x00800000,
  kTypeEcho = 0x01000000,
  kTypeNet = 0x02000000,
  kNoDisplay = 0x20000000,
  kLocked = 0x40000000,
  kDeleted = 0x80000000
};

// Идентификаторы подполей
enum class JamSubFieldType : uint16_t {
  kOAddress = 0,
  kDAddress = 1,
  kSenderName = 2,
  kReceiverName = 3,
  kMsgId = 4,
  kReplyId = 5,
  kSubject = 6,
  kPid = 7,
  kTrace = 8,
  kEnclosedFile = 9,
  kEnclosedFileWithAlias = 10,
  kEnclosedFreq = 11,
  kEnclosedFileWithCard = 12,
  kEnclosedIndirectFile = 13,
  kEmbIndat = 1000,
  kFtsKludge = 2000,
  kSeenBy2d = 2001,
  kPath2d = 2002,
  kFlags = 2003,
  kTzUtcInfo = 2004,
  kUnknown = 0xFFFF
};

#pragma pack(push, 1)
// Структуры данных JAM
struct JamBaseHeader {
  uint32_t signature;
  uint32_t date_created;
  uint32_t mod_counter;
  uint32_t active_msgs;
  uint32_t password_crc;
  uint32_t base_msg_num;
  uint32_t highwater;
  std::array<uint8_t, 996> reserved;
};

struct JamMessageHeader {
  uint32_t signature;
  uint16_t revision;
  uint16_t reserved_word;
  uint32_t subfield_len;
  uint32_t times_read;
  uint32_t msgid_crc;
  uint32_t reply_crc;
  uint32_t reply_to;
  uint32_t reply_1st;
  uint32_t reply_next;
  uint32_t date_written;
  uint32_t date_received;
  uint32_t date_processed;
  uint32_t message_number;
  uint32_t attribute;
  uint32_t attribute2;
  uint32_t offset;
  uint32_t txt_len;
  uint32_t password_crc;
  uint32_t cost;
};

struct JamSubFieldHeader {
  uint16_t lo_id;
  uint16_t hi_id;
  uint32_t data_len;
};

struct JamIndexRecord {
  uint32_t user_crc;
  uint32_t header_offset;
};

struct JamLastRead {
  uint32_t user_crc;
  uint32_t user_id;
  uint32_t last_read_msg;
  uint32_t high_read_msg;
};
#pragma pack(pop)
// Размер структур может зависеть от платформы — проверяем на этапе компиляции
static_assert(sizeof(JamBaseHeader) == 1024, "JamBaseHeader size mismatch");
static_assert(sizeof(JamMessageHeader) == 76, "JamMessageHeader size mismatch");
static_assert(sizeof(JamSubFieldHeader) == 8, "JamSubFieldHeader size mismatch");

// Типы ошибок
enum class JamError {
  kSuccess,
  kFileNotFound,
  kInvalidSignature,
  kInvalidMessageNumber,
  kReadError,
  kWriteError,
  kCorruptedData,
  kMessageDeleted
};

// Вспомогательные функции
constexpr std::array<uint32_t, 256> GenerateCrc32Table() {
  std::array<uint32_t, 256> table{};
  constexpr uint32_t polynomial = 0xEDB88320;

  for (uint32_t i = 0; i < 256; ++i) {
    uint32_t crc = i;
    for (int j = 0; j < 8; ++j) {
      crc = (crc >> 1) ^ ((crc & 1) ? polynomial : 0);
    }
    table[i] = crc;
  }
  return table;
}

constexpr auto kCrc32Table = GenerateCrc32Table();

inline uint32_t Crc32(std::string_view data) {
  uint32_t crc = 0xFFFFFFFF;
  for (char c : data) {
    crc = (crc >> 8) ^ kCrc32Table[(crc ^ static_cast<uint8_t>(c)) & 0xFF];
  }
  return ~crc;
}

/// @brief Вычисляет CRC32 без учёта регистра (без доп. аллокаций).
inline uint32_t Crc32IgnoreCase(std::string_view data) {
  uint32_t crc = 0xFFFFFFFF;
  for (unsigned char c : data) {
    uint8_t lower = static_cast<uint8_t>(std::tolower(c));
    crc = (crc >> 8) ^ kCrc32Table[(crc ^ lower) & 0xFF];
  }
  return ~crc;
}

namespace jam_wire {
inline uint16_t Get16(const uint8_t* b) {
  return uint16_t{b[0]} | (uint16_t{b[1]} << 8);
}
inline uint32_t Get32(const uint8_t* b) {
  return uint32_t{b[0]} | (uint32_t{b[1]} << 8) | (uint32_t{b[2]} << 16) | (uint32_t{b[3]} << 24);
}
inline void Put16(uint8_t* b, uint16_t v) {
  b[0] = static_cast<uint8_t>(v);
  b[1] = static_cast<uint8_t>(v >> 8);
}
inline void Put32(uint8_t* b, uint32_t v) {
  for (unsigned i = 0; i < 4; ++i)
    b[i] = static_cast<uint8_t>(v >> (8 * i));
}
inline std::array<uint8_t, 1024> Encode(const JamBaseHeader& h) {
  std::array<uint8_t, 1024> b{};
  Put32(b.data() + 0, h.signature);
  Put32(b.data() + 4, h.date_created);
  Put32(b.data() + 8, h.mod_counter);
  Put32(b.data() + 12, h.active_msgs);
  Put32(b.data() + 16, h.password_crc);
  Put32(b.data() + 20, h.base_msg_num);
  Put32(b.data() + 24, h.highwater);
  std::copy(h.reserved.begin(), h.reserved.end(), b.begin() + 28);
  return b;
}
inline JamBaseHeader Decode(const std::array<uint8_t, 1024>& b) {
  JamBaseHeader h{};
  h.signature = Get32(b.data() + 0);
  h.date_created = Get32(b.data() + 4);
  h.mod_counter = Get32(b.data() + 8);
  h.active_msgs = Get32(b.data() + 12);
  h.password_crc = Get32(b.data() + 16);
  h.base_msg_num = Get32(b.data() + 20);
  h.highwater = Get32(b.data() + 24);
  std::copy(b.begin() + 28, b.end(), h.reserved.begin());
  return h;
}
inline std::array<uint8_t, 76> Encode(const JamMessageHeader& h) {
  std::array<uint8_t, 76> b{};
  Put32(b.data(), h.signature);
  Put16(b.data() + 4, h.revision);
  Put16(b.data() + 6, h.reserved_word);
  Put32(b.data() + 8, h.subfield_len);
  Put32(b.data() + 12, h.times_read);
  Put32(b.data() + 16, h.msgid_crc);
  Put32(b.data() + 20, h.reply_crc);
  Put32(b.data() + 24, h.reply_to);
  Put32(b.data() + 28, h.reply_1st);
  Put32(b.data() + 32, h.reply_next);
  Put32(b.data() + 36, h.date_written);
  Put32(b.data() + 40, h.date_received);
  Put32(b.data() + 44, h.date_processed);
  Put32(b.data() + 48, h.message_number);
  Put32(b.data() + 52, h.attribute);
  Put32(b.data() + 56, h.attribute2);
  Put32(b.data() + 60, h.offset);
  Put32(b.data() + 64, h.txt_len);
  Put32(b.data() + 68, h.password_crc);
  Put32(b.data() + 72, h.cost);
  return b;
}
inline JamMessageHeader Decode(const std::array<uint8_t, 76>& b) {
  JamMessageHeader h{};
  h.signature = Get32(b.data());
  h.revision = Get16(b.data() + 4);
  h.reserved_word = Get16(b.data() + 6);
  h.subfield_len = Get32(b.data() + 8);
  h.times_read = Get32(b.data() + 12);
  h.msgid_crc = Get32(b.data() + 16);
  h.reply_crc = Get32(b.data() + 20);
  h.reply_to = Get32(b.data() + 24);
  h.reply_1st = Get32(b.data() + 28);
  h.reply_next = Get32(b.data() + 32);
  h.date_written = Get32(b.data() + 36);
  h.date_received = Get32(b.data() + 40);
  h.date_processed = Get32(b.data() + 44);
  h.message_number = Get32(b.data() + 48);
  h.attribute = Get32(b.data() + 52);
  h.attribute2 = Get32(b.data() + 56);
  h.offset = Get32(b.data() + 60);
  h.txt_len = Get32(b.data() + 64);
  h.password_crc = Get32(b.data() + 68);
  h.cost = Get32(b.data() + 72);
  return h;
}
inline std::array<uint8_t, 8> Encode(const JamIndexRecord& h) {
  std::array<uint8_t, 8> b{};
  Put32(b.data(), h.user_crc);
  Put32(b.data() + 4, h.header_offset);
  return b;
}
inline std::expected<uint64_t, JamError> Size(JamFile& file) {
  file.clear();
  file.seekg(0, std::ios::end);
  auto position = file.tellg();
  if (position < 0)
    return std::unexpected(JamError::kReadError);
  return static_cast<uint64_t>(position);
}
inline bool Fits(uint64_t offset, uint64_t length, uint64_t size) {
  return offset <= size && length <= size - offset;
}
constexpr uint32_t kMaxBody = 1024 * 1024;
constexpr uint32_t kMaxSubfields = 64 * 1024;
}  // namespace jam_wire

// JAM CRC as used by SMAPI Jam_Crc32: case-insensitive, no final XOR.
inline uint32_t JamCrc32(std::string_view data) {
  return ~Crc32IgnoreCase(data);
}

// Класс для представления подполя
class JamSubField {
public:
  JamSubField(JamSubFieldType type, std::vector<uint8_t> data, uint16_t high_id = 0)
      : type_(type), data_(std::move(data)), high_id_(high_id) {
  }

  JamSubFieldType type() const {
    return type_;
  }
  uint16_t high_id() const {
    return high_id_;
  }
  const std::vector<uint8_t>& data() const {
    return data_;
  }
  std::string ToString() const {
    return std::string(data_.begin(), data_.end());
  }

private:
  JamSubFieldType type_;
  std::vector<uint8_t> data_;
  uint16_t high_id_ = 0;
};

// Класс для представления сообщения
class JamMessage {
public:
  JamMessage() = default;

  // Установка основных полей
  void SetSubject(std::string_view subject) {
    SetSubField(JamSubFieldType::kSubject, subject);
  }

  void SetSenderName(std::string_view name) {
    SetSubField(JamSubFieldType::kSenderName, name);
  }

  void SetReceiverName(std::string_view name) {
    SetSubField(JamSubFieldType::kReceiverName, name);
  }

  void SetText(std::string_view text) {
    text_ = text;
  }

  // Получение данных
  std::string subject() const {
    return GetSubFieldData(JamSubFieldType::kSubject);
  }
  std::string sender_name() const {
    return GetSubFieldData(JamSubFieldType::kSenderName);
  }
  std::string receiver_name() const {
    return GetSubFieldData(JamSubFieldType::kReceiverName);
  }
  std::string text() const {
    return text_;
  }

  // ─── FTN-адреса (баг #7) ───
  /// @brief Установить FTN-адрес отправителя (Origin Address).
  void SetOriginAddress(std::string_view addr) {
    SetSubField(JamSubFieldType::kOAddress, addr);
  }

  /// @brief Установить FTN-адрес получателя (Destination Address).
  void SetDestAddress(std::string_view addr) {
    SetSubField(JamSubFieldType::kDAddress, addr);
  }

  /// @brief Получить FTN-адрес отправителя.
  [[nodiscard]] std::string origin_address() const {
    return GetSubFieldData(JamSubFieldType::kOAddress);
  }

  /// @brief Получить FTN-адрес получателя.
  [[nodiscard]] std::string dest_address() const {
    return GetSubFieldData(JamSubFieldType::kDAddress);
  }

  /// @brief Получить MsgID.
  [[nodiscard]] std::string msg_id() const {
    return GetSubFieldData(JamSubFieldType::kMsgId);
  }

  /// @brief Получить ReplyId.
  [[nodiscard]] std::string reply_id() const {
    return GetSubFieldData(JamSubFieldType::kReplyId);
  }

  // ─── MsgID / ReplyID / PID (баг #2, #4) ───
  /// @brief Установить MsgID (уникальный идентификатор, напр. <hash@fidoback>).
  void SetMsgId(std::string_view msgid) {
    SetSubField(JamSubFieldType::kMsgId, msgid);
  }

  /// @brief Установить ReplyID (для цепочки ответов).
  void SetReplyId(std::string_view replyid) {
    SetSubField(JamSubFieldType::kReplyId, replyid);
  }

  /// @brief Установить PID (Program Identifier, напр. "FidoBack/1.0").
  void SetPid(std::string_view pid) {
    SetSubField(JamSubFieldType::kPid, pid);
  }

  // ─── Reply chain (баг #2) ───
  /// @brief Номер родительского сообщения (для reply_to в заголовке).
  void SetReplyTo(uint32_t msg_num) {
    reply_to_ = msg_num;
  }
  [[nodiscard]] uint32_t reply_to() const {
    return reply_to_;
  }

  // ─── Атрибуты — getter (баг #5) ───
  void SetAttribute(JamMessageAttribute attr, bool value) {
    if (value) {
      attributes_ |= static_cast<uint32_t>(attr);
    } else {
      attributes_ &= ~static_cast<uint32_t>(attr);
    }
  }

  [[nodiscard]] bool GetAttribute(JamMessageAttribute attr) const {
    return (attributes_ & static_cast<uint32_t>(attr)) != 0;
  }

  /// @brief Получить битовую маску атрибутов (для сериализации в заголовок).
  [[nodiscard]] uint32_t attributes() const {
    return attributes_;
  }

  /// @brief Установить вторую битовую маску атрибутов.
  void set_attributes2(uint32_t attr2) {
    attributes2_ = attr2;
  }
  [[nodiscard]] uint32_t attributes2() const {
    return attributes2_;
  }

  /// @brief Получить все подполя (для сериализации).
  [[nodiscard]] const std::vector<JamSubField>& subfields() const {
    return subfields_;
  }

  /// @brief Установить произвольное подполе (для kludge и расширений).
  void SetRawSubField(JamSubFieldType type, std::string_view data) {
    std::vector<uint8_t> data_vec(data.begin(), data.end());
    subfields_.erase(std::remove_if(subfields_.begin(), subfields_.end(),
                                    [type](const JamSubField& sf) { return sf.type() == type; }),
                     subfields_.end());
    subfields_.emplace_back(type, std::move(data_vec));
  }

  /// @brief Получить данные конкретного подполя (публичный API для тестов и сервисов).
  [[nodiscard]] std::string GetSubFieldData(JamSubFieldType type) const {
    auto it = std::find_if(subfields_.begin(), subfields_.end(),
                           [type](const JamSubField& sf) { return sf.type() == type && sf.high_id() == 0; });
    return it != subfields_.end() ? it->ToString() : "";
  }

  void SetDates(uint32_t written, uint32_t received, uint32_t processed) {
    date_written_ = written;
    date_received_ = received;
    date_processed_ = processed;
    dates_set_ = true;
  }
  uint32_t date_written() const {
    return date_written_;
  }
  uint32_t date_received() const {
    return date_received_;
  }
  uint32_t date_processed() const {
    return date_processed_;
  }
  void SetReplyLinks(uint32_t to, uint32_t first, uint32_t next) {
    reply_to_ = to;
    reply_first_ = first;
    reply_next_ = next;
  }
  uint32_t reply_first() const {
    return reply_first_;
  }
  uint32_t reply_next() const {
    return reply_next_;
  }
  void AddRawSubField(JamSubFieldType type, std::string_view data, uint16_t high_id = 0) {
    subfields_.emplace_back(type, std::vector<uint8_t>(data.begin(), data.end()), high_id);
  }

private:
  // JamMessageBase имеет доступ к private-методам для сериализации
  friend class JamMessageBase;

  // ─── Работа с подполями ───
  void SetSubField(JamSubFieldType type, std::string_view data) {
    std::vector<uint8_t> data_vec(data.begin(), data.end());
    subfields_.erase(std::remove_if(subfields_.begin(), subfields_.end(),
                                    [type](const JamSubField& sf) { return sf.type() == type; }),
                     subfields_.end());
    subfields_.emplace_back(type, std::move(data_vec));
  }

  std::vector<JamSubField> subfields_;
  std::string text_;
  uint32_t attributes_ = 0;
  uint32_t attributes2_ = 0;
  uint32_t date_written_ = 0, date_received_ = 0, date_processed_ = 0;
  uint32_t reply_first_ = 0, reply_next_ = 0;
  bool dates_set_ = false;
  uint32_t reply_to_ = 0;  ///< Номер сообщения-родителя (для reply chain)
};

inline std::expected<std::string, JamError> MessageEncoding(const JamMessage& message, std::string_view fallback) {
  std::string encoding(fallback);
  bool found = false;
  for (const auto& field : message.subfields()) {
    if (field.type() != JamSubFieldType::kFtsKludge || field.high_id() != 0)
      continue;
    const auto data = field.ToString();
    std::string_view rest(data);
    while (!rest.empty()) {
      const auto end = rest.find_first_of("\r\n");
      auto line = rest.substr(0, end);
      if (!line.empty() && line.front() == '\1')
        line.remove_prefix(1);
      if (line.starts_with("CHRS: ")) {
        line.remove_prefix(6);
        const auto length = line.find_first_of(" \t");
        auto name = line.substr(0, length);
        if (name.empty() || name.size() > 64 || name.find('\0') != std::string_view::npos)
          return std::unexpected(JamError::kCorruptedData);
        const auto fold = [](std::string value) {
          for (auto& c : value)
            if (c >= 'A' && c <= 'Z')
              c += 'a' - 'A';
          return value;
        };
        // IBMPC never identified a unique code page. Use the configured local
        // default, while preserving errors for unknown explicit charsets.
        const std::string selected = fold(std::string(name)) == "ibmpc" ? std::string(fallback) : std::string(name);
        if (found && fold(selected) != fold(encoding))
          return std::unexpected(JamError::kCorruptedData);
        encoding = selected;
        found = true;
      }
      if (end == std::string_view::npos)
        break;
      rest.remove_prefix(end + 1);
    }
  }
  return encoding;
}

struct JamAppendPlan {
  std::array<uint64_t,3> original_sizes{};
  std::array<uint8_t,1024> original_base{}, published_base{};
  std::vector<uint8_t> header;
  std::string text;
  std::array<uint8_t,8> index{};
  uint32_t number = 0;
};

// Основной класс для работы с JAM базой
class JamMessageBase {
public:
  // Caller holds a lease on the physical owner for the entire view lifetime.
  explicit JamMessageBase(const std::array<int, 3>& descriptors, std::string encoding = "cp866", std::function<bool()> active = {}, JamFileIo* io = nullptr)
      : default_encoding_(std::move(encoding)), jhr_file_(descriptors[0], io),
        jdt_file_(descriptors[1], io), jdx_file_(descriptors[2], io), active_(std::move(active)) {}

  explicit JamMessageBase(std::string_view base_path, std::string_view default_encoding = "cp866");
  ~JamMessageBase();  // RAII — автоматически закрывает файлы

  JamMessageBase(const JamMessageBase&) = delete;
  JamMessageBase& operator=(const JamMessageBase&) = delete;
  JamMessageBase(JamMessageBase&&) noexcept;
  JamMessageBase& operator=(JamMessageBase&&) noexcept;

  // Основные операции
  [[nodiscard]] JamError Open();
  void Close();
  [[nodiscard]] bool is_open() const {
    return is_open_;
  }

  [[nodiscard]] std::expected<std::vector<uint32_t>, JamError> GetMessageNumbers() const;
  [[nodiscard]] std::expected<JamMessage, JamError> ReadMessage(uint32_t msg_num, bool include_body = true) const;
  std::expected<uint32_t, JamError> GetLastRead(std::string_view username);
  [[nodiscard]] JamError SetLastRead(std::string_view username, uint32_t msg_num);

  // Запись сообщений
  [[nodiscard]] JamError AddMessage(const JamMessage& message);
  [[nodiscard]] std::expected<JamAppendPlan, JamError> PrepareAppend(const JamMessage& input);
  [[nodiscard]] JamError DeleteMessage(uint32_t msg_num);
  const JamBaseHeader& base_header() const { return base_header_; }
  std::expected<JamMessageHeader, JamError> GetHeader(uint32_t number) const { return ReadHeader(number); }

  // Информация
  uint32_t message_count() const {
    return base_header_.active_msgs;
  }

private:
  // Вспомогательные методы
  std::expected<JamMessageHeader, JamError> ReadHeader(uint32_t msg_num) const;
  JamError ReadBaseHeader();
  JamError WriteBaseHeader();
  std::expected<JamIndexRecord, JamError> ReadIndexRecord(uint32_t index);
  JamError WriteIndexRecord(uint32_t index, const JamIndexRecord& record);
  std::expected<std::vector<JamLastRead>, JamError> ReadLastReads();
  JamError WriteLastReads(const std::vector<JamLastRead>& last_reads);
  std::expected<std::vector<JamSubField>, JamError> ReadSubFields(uint32_t offset, uint32_t length) const;

  std::string base_path_;
  std::string default_encoding_;
  bool is_open_ = false;
  JamBaseHeader base_header_{};
  std::vector<JamIndexRecord> index_structure_;

  mutable JamFile jhr_file_;
  mutable JamFile jdt_file_;
  mutable JamFile jdx_file_;
  mutable JamFile jlr_file_;
  std::function<bool()> active_;
};

// Реализация методов
inline JamError JamMessageBase::Open() {
  if (is_open_) {
    // Refresh the snapshot while retaining borrowed descriptors and their lease.
    is_open_ = false;
    index_structure_.clear();
    jhr_file_.clear();
    jdt_file_.clear();
    jdx_file_.clear();
    jlr_file_.clear();
  }

  if (!base_path_.empty()) {
    jhr_file_.open(base_path_ + ".jhr", std::ios::in | std::ios::out | std::ios::binary);
    jdt_file_.open(base_path_ + ".jdt", std::ios::in | std::ios::out | std::ios::binary);
    jdx_file_.open(base_path_ + ".jdx", std::ios::in | std::ios::out | std::ios::binary);
    jlr_file_.open(base_path_ + ".jlr", std::ios::in | std::ios::out | std::ios::binary);
  }

  if (!jhr_file_.is_open() || !jdt_file_.is_open() || !jdx_file_.is_open()) {
    Close();
    return JamError::kFileNotFound;
  }

  if (auto error = ReadBaseHeader(); error != JamError::kSuccess) {
    Close();
    return error;
  }

  if (base_header_.signature != kJamSignature) {
    Close();
    return JamError::kInvalidSignature;
  }

  // Чтение индексной структуры
  jdx_file_.seekg(0, std::ios::end);
  const auto file_size_pos = jdx_file_.tellg();
  if (file_size_pos == static_cast<std::streampos>(-1)) {
    Close();
    return JamError::kReadError;
  }
  const size_t file_size = static_cast<size_t>(file_size_pos);
  if (file_size % sizeof(JamIndexRecord) != 0 || file_size / sizeof(JamIndexRecord) > 1000000) {
    Close();
    return JamError::kCorruptedData;
  }
  const size_t num_records = file_size / sizeof(JamIndexRecord);
  if (base_header_.base_msg_num == 0 || num_records > uint64_t{UINT32_MAX} - base_header_.base_msg_num + 1 ||
      base_header_.active_msgs > num_records) {
    Close();
    return JamError::kCorruptedData;
  }

  index_structure_.reserve(num_records);
  jdx_file_.seekg(0, std::ios::beg);

  for (size_t i = 0; i < num_records; ++i) {
    std::array<uint8_t, 8> bytes{};
    if (active_ && !active_()) { Close(); return JamError::kReadError; }
    jdx_file_.read(reinterpret_cast<char*>(bytes.data()), bytes.size());
    JamIndexRecord record{jam_wire::Get32(bytes.data()), jam_wire::Get32(bytes.data() + 4)};
    if (jdx_file_.fail()) {
      Close();
      return JamError::kReadError;
    }
    index_structure_.push_back(record);
  }

  is_open_ = true;
  return JamError::kSuccess;
}

inline void JamMessageBase::Close() {
  jhr_file_.close();
  jdt_file_.close();
  jdx_file_.close();
  jlr_file_.close();
  is_open_ = false;
  index_structure_.clear();
}

// ─── Special member functions (RAII) ───
inline JamMessageBase::~JamMessageBase() {
  Close();
}

inline JamMessageBase::JamMessageBase(JamMessageBase&& other) noexcept
    : base_path_(std::move(other.base_path_)),
      default_encoding_(std::move(other.default_encoding_)),
      is_open_(other.is_open_),
      base_header_(other.base_header_),
      index_structure_(std::move(other.index_structure_)),
      jhr_file_(std::move(other.jhr_file_)),
      jdt_file_(std::move(other.jdt_file_)),
      jdx_file_(std::move(other.jdx_file_)),
      jlr_file_(std::move(other.jlr_file_)), active_(std::move(other.active_)) {
  other.is_open_ = false;
}

inline JamMessageBase& JamMessageBase::operator=(JamMessageBase&& other) noexcept {
  if (this != &other) {
    Close();
    base_path_ = std::move(other.base_path_);
    default_encoding_ = std::move(other.default_encoding_);
    is_open_ = other.is_open_;
    base_header_ = other.base_header_;
    index_structure_ = std::move(other.index_structure_);
    jhr_file_ = std::move(other.jhr_file_);
    jdt_file_ = std::move(other.jdt_file_);
    jdx_file_ = std::move(other.jdx_file_);
    jlr_file_ = std::move(other.jlr_file_);
    active_ = std::move(other.active_);
    other.is_open_ = false;
  }
  return *this;
}

inline JamMessageBase::JamMessageBase(std::string_view base_path, std::string_view default_encoding)
    : base_path_(base_path), default_encoding_(default_encoding) {
}

[[nodiscard]] inline std::expected<std::vector<uint32_t>, JamError> JamMessageBase::GetMessageNumbers() const {
  if (!is_open_) {
    return std::unexpected(JamError::kFileNotFound);
  }

  std::vector<uint32_t> message_numbers;
  message_numbers.reserve(index_structure_.size());

  for (uint32_t i = 0; i < index_structure_.size(); ++i) {
    if (index_structure_[i].header_offset == kInvalidOffset)
      continue;
    auto header = ReadHeader(base_header_.base_msg_num + i);
    if (!header) {
      if (header.error() == JamError::kMessageDeleted)
        continue;
      return std::unexpected(header.error());
    }
    message_numbers.push_back(base_header_.base_msg_num + i);
  }

  if (message_numbers.size() != base_header_.active_msgs)
    return std::unexpected(JamError::kCorruptedData);
  return message_numbers;
}

inline std::expected<JamMessageHeader, JamError> JamMessageBase::ReadHeader(uint32_t msg_num) const {
  if (active_ && !active_()) return std::unexpected(JamError::kReadError);
  if (!is_open_) {
    return std::unexpected(JamError::kFileNotFound);
  }

  if (msg_num < base_header_.base_msg_num ||
      uint64_t{msg_num} >= uint64_t{base_header_.base_msg_num} + index_structure_.size()) {
    return std::unexpected(JamError::kInvalidMessageNumber);
  }

  const uint32_t index = msg_num - base_header_.base_msg_num;
  const JamIndexRecord& index_record = index_structure_[index];

  if (index_record.header_offset == kInvalidOffset) {
    return std::unexpected(JamError::kMessageDeleted);
  }

  auto header_size = jam_wire::Size(jhr_file_);
  auto text_size = jam_wire::Size(jdt_file_);
  if (!header_size || !text_size)
    return std::unexpected(JamError::kReadError);
  if (*header_size > UINT32_MAX || *text_size > UINT32_MAX)
    return std::unexpected(JamError::kCorruptedData);
  if (index_record.header_offset < kJamBaseHeaderSize || !jam_wire::Fits(index_record.header_offset, 76, *header_size))
    return std::unexpected(JamError::kCorruptedData);
  jhr_file_.seekg(index_record.header_offset, std::ios::beg);
  std::array<uint8_t, 76> bytes{};
  jhr_file_.read(reinterpret_cast<char*>(bytes.data()), bytes.size());
  const auto msg_header = jam_wire::Decode(bytes);

  if (jhr_file_.fail()) {
    return std::unexpected(JamError::kReadError);
  }

  if (msg_header.signature != kJamSignature) {
    return std::unexpected(JamError::kInvalidSignature);
  }

  if (msg_header.revision != kJamRevision || msg_header.message_number != msg_num ||
      msg_header.subfield_len > jam_wire::kMaxSubfields || msg_header.txt_len > jam_wire::kMaxBody ||
      !jam_wire::Fits(uint64_t{index_record.header_offset} + 76, msg_header.subfield_len, *header_size) ||
      !jam_wire::Fits(msg_header.offset, msg_header.txt_len, *text_size))
    return std::unexpected(JamError::kCorruptedData);
  if ((msg_header.attribute & static_cast<uint32_t>(JamMessageAttribute::kDeleted)) != 0)
    return std::unexpected(JamError::kMessageDeleted);
  return msg_header;
}

[[nodiscard]] inline std::expected<JamMessage, JamError> JamMessageBase::ReadMessage(uint32_t msg_num, bool include_body) const {
  auto header = ReadHeader(msg_num);
  if (!header)
    return std::unexpected(header.error());
  const auto& msg_header = *header;
  const auto& index_record = index_structure_[msg_num - base_header_.base_msg_num];
  JamMessage message;
  message.attributes_ = msg_header.attribute;
  message.attributes2_ = msg_header.attribute2;
  message.SetReplyLinks(msg_header.reply_to, msg_header.reply_1st, msg_header.reply_next);
  message.SetDates(msg_header.date_written, msg_header.date_received, msg_header.date_processed);

  // Чтение подполей
  if (msg_header.subfield_len > 0) {
    auto subfields = ReadSubFields(index_record.header_offset + sizeof(JamMessageHeader), msg_header.subfield_len);
    if (!subfields) {
      return std::unexpected(subfields.error());
    }

    for (const auto& subfield : *subfields) {
      message.subfields_.push_back(subfield);
    }
  }

  // Чтение текста сообщения
  if (include_body && msg_header.txt_len > 0) {
    jdt_file_.seekg(msg_header.offset, std::ios::beg);
    std::vector<char> text_data(msg_header.txt_len);
    jdt_file_.read(text_data.data(), msg_header.txt_len);

    if (jdt_file_.fail()) {
      return std::unexpected(JamError::kReadError);
    }

    message.SetText(std::string(text_data.data(), msg_header.txt_len));
  }

  auto encoding = MessageEncoding(message, default_encoding_);
  if (!encoding)
    return std::unexpected(encoding.error());
  auto decoded = fidoback::storage::ConvertText(message.text_, *encoding, "UTF-8");
  if (!decoded)
    return std::unexpected(JamError::kCorruptedData);
  message.text_ = std::move(*decoded);
  for (auto& field : message.subfields_) {
    if (field.high_id() != 0 ||
        (field.type() != JamSubFieldType::kSubject && field.type() != JamSubFieldType::kSenderName &&
         field.type() != JamSubFieldType::kReceiverName))
      continue;
    auto text = fidoback::storage::ConvertText(field.ToString(), *encoding, "UTF-8");
    if (!text)
      return std::unexpected(JamError::kCorruptedData);
    field = JamSubField(field.type(), std::vector<uint8_t>(text->begin(), text->end()));
  }
  return message;
}

inline std::expected<uint32_t, JamError> JamMessageBase::GetLastRead(std::string_view username) {
  auto last_reads = ReadLastReads();
  if (!last_reads) {
    return std::unexpected(last_reads.error());
  }

  const uint32_t user_crc = JamCrc32(username);

  for (const auto& lr : *last_reads) {
    if (lr.user_crc == user_crc) {
      return lr.last_read_msg;
    }
  }

  return 0;
}

[[nodiscard]] inline JamError JamMessageBase::SetLastRead(std::string_view username, uint32_t msg_num) {
  auto last_reads = ReadLastReads();
  if (!last_reads) {
    return last_reads.error();
  }

  const uint32_t user_crc = JamCrc32(username);
  bool found = false;

  for (auto& lr : *last_reads) {
    if (lr.user_crc == user_crc) {
      lr.last_read_msg = msg_num;
      lr.high_read_msg = std::max(lr.high_read_msg, msg_num);
      found = true;
      break;
    }
  }

  if (!found) {
    last_reads->push_back(JamLastRead{user_crc,
                                      user_crc,  // user_id same as CRC for simplicity
                                      msg_num, msg_num});
  }

  return WriteLastReads(*last_reads);
}

[[nodiscard]] inline std::expected<JamAppendPlan, JamError> JamMessageBase::PrepareAppend(const JamMessage& input) {
  if (!is_open_) {
    return std::unexpected(JamError::kFileNotFound);
  }

  auto live=GetMessageNumbers();
  if (!live) return std::unexpected(live.error());

  auto selected_encoding = MessageEncoding(input, default_encoding_);
  if (!selected_encoding)
    return std::unexpected(selected_encoding.error());
  JamMessage message = input;
  auto body = fidoback::storage::ConvertText(input.text(), "UTF-8", *selected_encoding);
  if (!body)
    return std::unexpected(JamError::kCorruptedData);
  message.text_ = std::move(*body);
  bool has_chrs = false;
  for (auto& field : message.subfields_) {
    if (field.type() == JamSubFieldType::kFtsKludge && field.ToString().find("CHRS: ") != std::string::npos)
      has_chrs = true;
    if (field.high_id() != 0 ||
        (field.type() != JamSubFieldType::kSubject && field.type() != JamSubFieldType::kSenderName &&
         field.type() != JamSubFieldType::kReceiverName))
      continue;
    auto text = fidoback::storage::ConvertText(field.ToString(), "UTF-8", *selected_encoding);
    if (!text)
      return std::unexpected(JamError::kCorruptedData);
    field = JamSubField(field.type(), std::vector<uint8_t>(text->begin(), text->end()));
  }
  if (!has_chrs) {
    std::string upper = *selected_encoding;
    for (auto& c : upper)
      if (c >= 'a' && c <= 'z')
        c = static_cast<char>(c - ('a' - 'A'));
    message.AddRawSubField(JamSubFieldType::kFtsKludge,
                           "CHRS: " + upper + ((upper == "UTF-8" || upper == "UTF8") ? " 4" : " 2"));
  }
  auto header_size = jam_wire::Size(jhr_file_);
  auto text_size = jam_wire::Size(jdt_file_);
  auto index_size = jam_wire::Size(jdx_file_);
  uint64_t subfield_size = 0;
  for (const auto& field : message.subfields()) {
    if (field.data().size() > jam_wire::kMaxSubfields)
      return std::unexpected(JamError::kCorruptedData);
    subfield_size += 8 + field.data().size();
    if (subfield_size > jam_wire::kMaxSubfields)
      return std::unexpected(JamError::kCorruptedData);
  }
  if (!header_size || !text_size || !index_size)
    return std::unexpected(JamError::kReadError);
  if (message.text().size() > jam_wire::kMaxBody || index_structure_.size() >= 1000000 ||
      *index_size != index_structure_.size() * uint64_t{8} ||
      uint64_t{base_header_.base_msg_num} + index_structure_.size() > UINT32_MAX || *header_size >= UINT32_MAX ||
      subfield_size + 76 > UINT32_MAX - *header_size || *text_size > UINT32_MAX ||
      message.text().size() > UINT32_MAX - *text_size || base_header_.active_msgs == UINT32_MAX)
    return std::unexpected(JamError::kCorruptedData);

  const auto current_time = std::time(nullptr);
  if (!message.dates_set_ && (current_time < 0 || uint64_t(current_time) > UINT32_MAX))
    return std::unexpected(JamError::kCorruptedData);

  // ── 2. Подготовка заголовка сообщения ──
  JamMessageHeader msg_header{};
  msg_header.signature = kJamSignature;
  msg_header.revision = kJamRevision;
  msg_header.reserved_word = 0;  // баг #9: явный ноль
  msg_header.offset = static_cast<uint32_t>(*text_size);
  msg_header.txt_len = static_cast<uint32_t>(message.text().size());
  msg_header.message_number = base_header_.base_msg_num + static_cast<uint32_t>(index_structure_.size());
  msg_header.times_read = 0;  // баг #8: явный ноль

  // Даты
  const uint32_t now = static_cast<uint32_t>(current_time);
  msg_header.date_written = message.dates_set_ ? message.date_written() : now;
  msg_header.date_received = message.dates_set_ ? message.date_received() : now;
  msg_header.date_processed = message.dates_set_ ? message.date_processed() : now;

  // Баг #5: Атрибуты
  msg_header.attribute = message.attributes();
  msg_header.attribute2 = message.attributes2();

  // Баг #2: Reply chain
  msg_header.reply_to = message.reply_to();
  msg_header.reply_1st = message.reply_first();
  msg_header.reply_next = message.reply_next();

  // Баг #4: CRC для MsgID/ReplyID
  auto msgid = message.GetSubFieldData(JamSubFieldType::kMsgId);
  auto replyid = message.GetSubFieldData(JamSubFieldType::kReplyId);
  msg_header.msgid_crc = JamCrc32(msgid);
  msg_header.reply_crc = JamCrc32(replyid);

  msg_header.password_crc = UINT32_MAX;

  // ── 3. Сериализация подполей ──
  std::vector<uint8_t> subfield_data;
  for (const auto& subfield : message.subfields()) {
    JamSubFieldHeader sub_header{};
    sub_header.lo_id = static_cast<uint16_t>(subfield.type());
    sub_header.hi_id = subfield.high_id();
    sub_header.data_len = static_cast<uint32_t>(subfield.data().size());

    std::array<uint8_t, 8> bytes{};
    jam_wire::Put16(bytes.data(), sub_header.lo_id);
    jam_wire::Put16(bytes.data() + 2, sub_header.hi_id);
    jam_wire::Put32(bytes.data() + 4, sub_header.data_len);
    subfield_data.insert(subfield_data.end(), bytes.begin(), bytes.end());
    subfield_data.insert(subfield_data.end(), subfield.data().begin(), subfield.data().end());
  }

  msg_header.subfield_len = static_cast<uint32_t>(subfield_data.size());

  JamAppendPlan plan;
  plan.original_sizes = {*header_size, *text_size, *index_size};
  plan.original_base = jam_wire::Encode(base_header_);
  auto published = base_header_; ++published.active_msgs; ++published.mod_counter;
  plan.published_base = jam_wire::Encode(published);
  const auto bytes = jam_wire::Encode(msg_header);
  plan.header.assign(bytes.begin(), bytes.end());
  plan.header.insert(plan.header.end(), subfield_data.begin(), subfield_data.end());
  plan.text = message.text(); plan.number = msg_header.message_number;
  plan.index = jam_wire::Encode(JamIndexRecord{JamCrc32(message.receiver_name()), static_cast<uint32_t>(*header_size)});
  return plan;
}

[[nodiscard]] inline JamError JamMessageBase::AddMessage(const JamMessage& input) {
  auto plan = PrepareAppend(input); if (!plan) return plan.error();
  jdt_file_.seekp(plan->original_sizes[1]); jdt_file_.write(plan->text.data(), plan->text.size());
  if (jdt_file_.fail()) return JamError::kWriteError;
  jhr_file_.seekp(plan->original_sizes[0]);
  jhr_file_.write(reinterpret_cast<const char*>(plan->header.data()), plan->header.size());
  if (jhr_file_.fail()) return JamError::kWriteError;
  jdx_file_.seekp(plan->original_sizes[2]);
  jdx_file_.write(reinterpret_cast<const char*>(plan->index.data()), plan->index.size());
  if (jdx_file_.fail()) return JamError::kWriteError;
  jhr_file_.seekp(0);
  jhr_file_.write(reinterpret_cast<const char*>(plan->published_base.data()), plan->published_base.size());
  if (jhr_file_.fail()) return JamError::kWriteError;
  return Open();
}

// Вспомогательные private методы
inline JamError JamMessageBase::ReadBaseHeader() {
  auto size = jam_wire::Size(jhr_file_);
  if (!size)
    return size.error();
  if (*size < 1024 || *size > UINT32_MAX)
    return JamError::kCorruptedData;
  jhr_file_.seekg(0, std::ios::beg);
  std::array<uint8_t, 1024> bytes{};
  jhr_file_.read(reinterpret_cast<char*>(bytes.data()), bytes.size());
  if (jhr_file_.fail())
    return JamError::kReadError;
  base_header_ = jam_wire::Decode(bytes);
  return JamError::kSuccess;
}

inline JamError JamMessageBase::WriteBaseHeader() {
  jhr_file_.seekp(0, std::ios::beg);
  const auto bytes = jam_wire::Encode(base_header_);
  jhr_file_.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  jhr_file_.flush();
  return jhr_file_.fail() ? JamError::kWriteError : JamError::kSuccess;
}

inline std::expected<JamIndexRecord, JamError> JamMessageBase::ReadIndexRecord(uint32_t index) {
  if (index >= index_structure_.size()) {
    return std::unexpected(JamError::kInvalidMessageNumber);
  }
  return index_structure_[index];
}

inline JamError JamMessageBase::WriteIndexRecord(uint32_t index, const JamIndexRecord& record) {
  jdx_file_.seekp(index * sizeof(JamIndexRecord), std::ios::beg);
  const auto bytes = jam_wire::Encode(record);
  jdx_file_.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  jdx_file_.flush();
  return jdx_file_.fail() ? JamError::kWriteError : JamError::kSuccess;
}

inline std::expected<std::vector<JamLastRead>, JamError> JamMessageBase::ReadLastReads() {
  std::vector<JamLastRead> last_reads;

  if (!jlr_file_.is_open()) {
    return last_reads;
  }

  auto size = jam_wire::Size(jlr_file_);
  if (!size)
    return std::unexpected(size.error());
  if (*size % 16 != 0 || *size > 16000000)
    return std::unexpected(JamError::kCorruptedData);
  jlr_file_.seekg(0, std::ios::beg);
  for (uint64_t i = 0; i < *size / 16; ++i) {
    std::array<uint8_t, 16> bytes{};
    jlr_file_.read(reinterpret_cast<char*>(bytes.data()), bytes.size());
    if (jlr_file_.fail())
      return std::unexpected(JamError::kReadError);
    JamLastRead lr{jam_wire::Get32(bytes.data()), jam_wire::Get32(bytes.data() + 4), jam_wire::Get32(bytes.data() + 8),
                   jam_wire::Get32(bytes.data() + 12)};

    if (lr.user_crc != kInvalidOffset && lr.user_id != kInvalidOffset) {
      last_reads.push_back(lr);
    }
  }

  return last_reads;
}

inline JamError JamMessageBase::WriteLastReads(const std::vector<JamLastRead>& last_reads) {
  if (!jlr_file_.is_open()) {
    return JamError::kFileNotFound;
  }

  if (last_reads.size() > 1000000)
    return JamError::kCorruptedData;
  jlr_file_.clear();
  jlr_file_.seekp(0, std::ios::beg);

  for (const auto& lr : last_reads) {
    std::array<uint8_t, 16> bytes{};
    jam_wire::Put32(bytes.data(), lr.user_crc);
    jam_wire::Put32(bytes.data() + 4, lr.user_id);
    jam_wire::Put32(bytes.data() + 8, lr.last_read_msg);
    jam_wire::Put32(bytes.data() + 12, lr.high_read_msg);
    jlr_file_.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    if (jlr_file_.fail()) {
      return JamError::kWriteError;
    }
  }

  jlr_file_.flush();
  return jlr_file_.fail() ? JamError::kWriteError : JamError::kSuccess;
}

inline std::expected<std::vector<JamSubField>, JamError> JamMessageBase::ReadSubFields(uint32_t offset,
                                                                                       uint32_t length) const {
  std::vector<JamSubField> subfields;
  auto size = jam_wire::Size(jhr_file_);
  if (!size)
    return std::unexpected(size.error());
  if (length > jam_wire::kMaxSubfields || !jam_wire::Fits(offset, length, *size))
    return std::unexpected(JamError::kCorruptedData);
  jhr_file_.seekg(offset, std::ios::beg);

  std::vector<uint8_t> subfield_data(length);
  jhr_file_.read(reinterpret_cast<char*>(subfield_data.data()), length);

  if (jhr_file_.fail()) {
    return std::unexpected(JamError::kReadError);
  }

  size_t pos = 0;
  while (pos < subfield_data.size()) {
    if (pos + sizeof(JamSubFieldHeader) > subfield_data.size()) {
      return std::unexpected(JamError::kCorruptedData);
    }

    JamSubFieldHeader sub_header;
    const auto* bytes = subfield_data.data() + pos;
    sub_header.lo_id = jam_wire::Get16(bytes);
    sub_header.hi_id = jam_wire::Get16(bytes + 2);
    sub_header.data_len = jam_wire::Get32(bytes + 4);
    pos += sizeof(JamSubFieldHeader);

    if (sub_header.data_len > subfield_data.size() - pos) {
      return std::unexpected(JamError::kCorruptedData);
    }

    std::vector<uint8_t> field_data(subfield_data.begin() + pos, subfield_data.begin() + pos + sub_header.data_len);
    pos += sub_header.data_len;

    subfields.emplace_back(static_cast<JamSubFieldType>(sub_header.lo_id), std::move(field_data), sub_header.hi_id);
  }

  return subfields;
}

[[nodiscard]] inline JamError JamMessageBase::DeleteMessage(uint32_t msg_num) {
  if (!is_open_) {
    return JamError::kFileNotFound;
  }

  if (msg_num < base_header_.base_msg_num ||
      uint64_t{msg_num} >= uint64_t{base_header_.base_msg_num} + index_structure_.size()) {
    return JamError::kInvalidMessageNumber;
  }

  const uint32_t index = msg_num - base_header_.base_msg_num;
  JamIndexRecord& index_record = index_structure_[index];
  if (index_record.header_offset == kInvalidOffset)
    return JamError::kMessageDeleted;
  if (base_header_.active_msgs == 0)
    return JamError::kCorruptedData;
  auto header = ReadHeader(msg_num);
  if (!header) return header.error();
  header->attribute |= static_cast<uint32_t>(JamMessageAttribute::kDeleted);
  header->txt_len = 0;
  const auto bytes = jam_wire::Encode(*header);
  jhr_file_.seekp(index_record.header_offset);
  jhr_file_.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  jhr_file_.flush();
  if (jhr_file_.fail()) return JamError::kWriteError;
  auto record = index_record;
  record.user_crc = UINT32_MAX;
  record.header_offset = kInvalidOffset;
  auto error = WriteIndexRecord(index, record);
  if (error != JamError::kSuccess)
    return error;
  index_record = record;
  --base_header_.active_msgs;
  ++base_header_.mod_counter;
  return WriteBaseHeader();
}

}  // namespace msgapi
