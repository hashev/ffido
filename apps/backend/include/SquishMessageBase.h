#pragma once

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <expected>
#include <fstream>
#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace msgapi {

// Константы Squish
constexpr uint32_t kSquishSignature = 0xAFB74453;       // 'S\x44\xB7\xAF'
constexpr uint32_t kSquishFrameSignature = 0xAFB74453;  // 'S\x44\xB7\xAF'
constexpr uint16_t kSquishHeaderSize = 256;

// Атрибуты сообщений Squish
enum class SquishMessageAttribute : uint32_t {
  kPrivate = 0x0001,
  kCrash = 0x0002,
  kRead = 0x0004,
  kSent = 0x0008,
  kFile = 0x0010,
  kForwarded = 0x0020,
  kOrphan = 0x0040,
  kKill = 0x0080,
  kLocal = 0x0100,
  kHold = 0x0200,
  kXx2 = 0x0400,
  kFrq = 0x0800,
  kRrq = 0x1000,
  kCpt = 0x2000,
  kArq = 0x4000,
  kUrq = 0x8000,
  kScanned = 0x00010000,
  kUid = 0x00020000,
  kSeen = 0x00080000
};

// Структуры данных Squish
#pragma pack(push, 1)
struct SquishBaseHeader {
  uint16_t len;
  uint16_t rsvd1;
  uint32_t num_msgs;
  uint32_t high_msg;
  uint32_t skip_msg;
  uint32_t high_water;
  uint32_t uid;
  std::array<uint8_t, 80> base;
  uint32_t begin_frame;
  uint32_t last_frame;
  uint32_t free_frame;
  uint32_t last_free_frame;
  uint32_t end_frame;
  uint32_t max_msg;
  uint16_t keep_days;
  uint16_t sz_sq_hdr;
  std::array<uint8_t, 124> rsvd2;
};

struct SquishFrameHeader {
  uint32_t id;
  uint32_t next_frame;
  uint32_t prev_frame;
  uint32_t frame_length;
  uint32_t msg_length;
  uint32_t c_len;
  uint16_t frame_type;
  uint16_t rsvd;
  uint32_t attr;
  std::array<uint8_t, 36> from;
  std::array<uint8_t, 36> to;
  std::array<uint8_t, 72> subject;
  uint16_t from_zone;
  uint16_t from_net;
  uint16_t from_node;
  uint16_t from_point;
  uint16_t to_zone;
  uint16_t to_net;
  uint16_t to_node;
  uint16_t to_point;
  uint32_t date_written;
  uint32_t date_arrived;
  uint16_t utc;
  uint32_t reply_to;
  std::array<uint32_t, 9> replies;
  uint32_t u_msg_id;
  std::array<uint8_t, 20> date;
};

struct SquishIndexRecord {
  uint32_t offset;
  uint32_t message_num;
  uint32_t crc;
};
#pragma pack(pop)

// Размер заголовка фрейма (определён после #pragma pack(pop) для корректного sizeof)
constexpr uint16_t kSquishFrameHeaderSize = sizeof(SquishFrameHeader);  // 266 bytes packed

// Типы ошибок
enum class SquishError {
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
inline char tolower_safe(char c) {
  return static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
}

inline uint32_t buf_hash32(std::string_view str) {
  uint32_t h = 0;
  for (char c : str) {
    if (c == '\0')
      continue;
    char lower_c = tolower_safe(c);
    h = (h << 4) + static_cast<uint32_t>(lower_c);
    uint32_t g = h & 0xF0000000;
    if (g != 0) {
      h ^= g >> 24;
      h ^= g;
    }
  }
  return h & 0x7FFFFFFF;
}

inline std::string trim_null(std::string_view str) {
  auto end = std::find(str.begin(), str.end(), '\0');
  return std::string(str.begin(), end);
}

inline std::chrono::system_clock::time_point squish_time_to_chrono(uint32_t t) {
  int year = ((t >> 9) & 127) + 1980;
  int month = (t >> 5) & 15;
  int day = t & 31;
  int hour = (t >> 27) & 31;
  int minute = (t >> 21) & 63;
  int second = ((t >> 16) & 31) * 2;

  std::tm tm{};
  tm.tm_year = year - 1900;
  tm.tm_mon = month - 1;
  tm.tm_mday = day;
  tm.tm_hour = hour;
  tm.tm_min = minute;
  tm.tm_sec = second;

  return std::chrono::system_clock::from_time_t(std::mktime(&tm));
}

inline uint32_t chrono_to_squish_time(std::chrono::system_clock::time_point tp) {
  std::time_t t = std::chrono::system_clock::to_time_t(tp);
  std::tm tm{};
  localtime_r(&t, &tm);  // POSIX: thread-safe, нет data race

  uint32_t result = 0;
  result |= (tm.tm_mday & 31);
  result |= ((tm.tm_mon + 1) & 15) << 5;
  result |= ((tm.tm_year + 1900 - 1980) & 127) << 9;
  result |= ((tm.tm_sec / 2) & 31) << 16;
  result |= (tm.tm_min & 63) << 21;
  result |= (tm.tm_hour & 31) << 27;

  return result;
}

// Класс для представления адреса
class NetworkAddress {
public:
  NetworkAddress(uint16_t zone = 0, uint16_t net = 0, uint16_t node = 0, uint16_t point = 0)
      : zone_(zone), net_(net), node_(node), point_(point) {
  }

  uint16_t zone() const {
    return zone_;
  }
  uint16_t net() const {
    return net_;
  }
  uint16_t node() const {
    return node_;
  }
  uint16_t point() const {
    return point_;
  }

  void set_zone(uint16_t zone) {
    zone_ = zone;
  }
  void set_net(uint16_t net) {
    net_ = net;
  }
  void set_node(uint16_t node) {
    node_ = node;
  }
  void set_point(uint16_t point) {
    point_ = point;
  }

  static NetworkAddress FromNumbers(uint16_t zone, uint16_t net, uint16_t node, uint16_t point) {
    return NetworkAddress(zone, net, node, point);
  }

private:
  uint16_t zone_;
  uint16_t net_;
  uint16_t node_;
  uint16_t point_;
};

// Класс для представления сообщения
class SquishMessage {
public:
  SquishMessage() = default;

  // Основные поля
  void set_from(std::string_view from) {
    from_ = from;
  }
  void set_to(std::string_view to) {
    to_ = to;
  }
  void set_subject(std::string_view subject) {
    subject_ = subject;
  }
  void set_body(std::string_view body) {
    body_ = body;
  }
  void set_date_written(std::chrono::system_clock::time_point time) {
    date_written_ = time;
  }
  void set_date_arrived(std::chrono::system_clock::time_point time) {
    date_arrived_ = time;
  }
  void set_from_address(const NetworkAddress& addr) {
    from_addr_ = addr;
  }
  void set_to_address(const NetworkAddress& addr) {
    to_addr_ = addr;
  }
  void set_reply_to(uint32_t reply_to) {
    reply_to_ = reply_to;
  }

  const std::string& from() const {
    return from_;
  }
  const std::string& to() const {
    return to_;
  }
  const std::string& subject() const {
    return subject_;
  }
  const std::string& body() const {
    return body_;
  }
  std::chrono::system_clock::time_point date_written() const {
    return date_written_;
  }
  std::chrono::system_clock::time_point date_arrived() const {
    return date_arrived_;
  }
  const NetworkAddress& from_address() const {
    return from_addr_;
  }
  const NetworkAddress& to_address() const {
    return to_addr_;
  }
  uint32_t reply_to() const {
    return reply_to_;
  }

  // Атрибуты
  void SetAttribute(SquishMessageAttribute attr, bool value) {
    if (value) {
      attributes_ |= static_cast<uint32_t>(attr);
    } else {
      attributes_ &= ~static_cast<uint32_t>(attr);
    }
  }

  bool GetAttribute(SquishMessageAttribute attr) const {
    return (attributes_ & static_cast<uint32_t>(attr)) != 0;
  }

  // Клуджи
  void AddKludge(std::string_view key, std::string_view value) {
    kludges_[std::string(key)] = std::string(value);
  }

  const std::map<std::string, std::string>& kludges() const {
    return kludges_;
  }

private:
  std::string from_;
  std::string to_;
  std::string subject_;
  std::string body_;
  std::chrono::system_clock::time_point date_written_ = std::chrono::system_clock::now();
  std::chrono::system_clock::time_point date_arrived_ = std::chrono::system_clock::now();
  NetworkAddress from_addr_;
  NetworkAddress to_addr_;
  uint32_t attributes_ = 0;
  uint32_t reply_to_ = 0;
  std::map<std::string, std::string> kludges_;
};

// Основной класс для работы с Squish базой
class SquishMessageBase {
public:
  explicit SquishMessageBase(std::string_view base_path);
  ~SquishMessageBase();  // RAII — автоматически закрывает файлы

  SquishMessageBase(const SquishMessageBase&) = delete;
  SquishMessageBase& operator=(const SquishMessageBase&) = delete;
  SquishMessageBase(SquishMessageBase&&) noexcept;
  SquishMessageBase& operator=(SquishMessageBase&&) noexcept;

  // Основные операции
  [[nodiscard]] SquishError Open();
  void Close();
  [[nodiscard]] bool is_open() const {
    return is_open_;
  }

  // Чтение сообщений
  std::expected<std::unique_ptr<SquishMessage>, SquishError> ReadMessage(uint32_t msg_num);
  std::expected<uint32_t, SquishError> GetLastRead();
  SquishError SetLastRead(uint32_t msg_num);

  // Запись сообщений
  SquishError AddMessage(const SquishMessage& message);
  SquishError DeleteMessage(uint32_t msg_num);

  // Информация
  uint32_t message_count() const {
    return index_structure_.size();
  }
  uint32_t last_message_number() const;

private:
  // Вспомогательные методы
  SquishError ReadBaseHeader();
  SquishError WriteBaseHeader();
  SquishError ReadIndex();
  SquishError WriteIndex();
  std::expected<SquishBaseHeader, SquishError> ReadSquishBaseHeader();
  std::expected<SquishFrameHeader, SquishError> ReadFrameHeader(uint32_t offset);
  SquishError WriteFrameHeader(uint32_t offset, const SquishFrameHeader& header);

  std::string base_path_;
  bool is_open_ = false;
  SquishBaseHeader base_header_{};
  std::vector<SquishIndexRecord> index_structure_;

  mutable std::fstream sqd_file_;
  mutable std::fstream sqi_file_;
  mutable std::fstream sql_file_;
};

// Реализация методов
inline SquishError SquishMessageBase::Open() {
  if (is_open_) {
    Close();
  }

  sqd_file_.open(base_path_ + ".sqd", std::ios::in | std::ios::out | std::ios::binary);
  sqi_file_.open(base_path_ + ".sqi", std::ios::in | std::ios::out | std::ios::binary);
  sql_file_.open(base_path_ + ".sql", std::ios::in | std::ios::out | std::ios::binary);

  if (!sqd_file_.is_open() || !sqi_file_.is_open()) {
    Close();
    return SquishError::kFileNotFound;
  }

  if (auto base_header = ReadSquishBaseHeader(); !base_header) {
    Close();
    return SquishError::kInvalidSignature;
  } else {
    base_header_ = *base_header;
  }

  if (auto error = ReadIndex(); error != SquishError::kSuccess) {
    Close();
    return error;
  }

  is_open_ = true;
  return SquishError::kSuccess;
}

inline void SquishMessageBase::Close() {
  sqd_file_.close();
  sqi_file_.close();
  sql_file_.close();
  is_open_ = false;
  index_structure_.clear();
}

inline std::expected<std::unique_ptr<SquishMessage>, SquishError> SquishMessageBase::ReadMessage(uint32_t msg_num) {
  if (!is_open_) {
    return std::unexpected(SquishError::kFileNotFound);
  }

  if (msg_num == 0 || msg_num > index_structure_.size()) {
    return std::unexpected(SquishError::kInvalidMessageNumber);
  }

  const SquishIndexRecord& index_record = index_structure_[msg_num - 1];

  auto frame_header = ReadFrameHeader(index_record.offset);
  if (!frame_header) {
    return std::unexpected(frame_header.error());
  }

  if (frame_header->id != kSquishFrameSignature) {
    return std::unexpected(SquishError::kInvalidSignature);
  }

  auto message = std::make_unique<SquishMessage>();

  // Чтение основных полей
  message->set_from(
      trim_null(std::string_view(reinterpret_cast<const char*>(frame_header->from.data()), frame_header->from.size())));
  message->set_to(
      trim_null(std::string_view(reinterpret_cast<const char*>(frame_header->to.data()), frame_header->to.size())));
  message->set_subject(trim_null(
      std::string_view(reinterpret_cast<const char*>(frame_header->subject.data()), frame_header->subject.size())));
  message->set_date_written(squish_time_to_chrono(frame_header->date_written));
  message->set_date_arrived(squish_time_to_chrono(frame_header->date_arrived));
  message->set_from_address(NetworkAddress::FromNumbers(frame_header->from_zone, frame_header->from_net,
                                                        frame_header->from_node, frame_header->from_point));
  message->set_to_address(NetworkAddress::FromNumbers(frame_header->to_zone, frame_header->to_net,
                                                      frame_header->to_node, frame_header->to_point));
  message->set_reply_to(frame_header->reply_to);

  // Установка атрибутов
  for (uint32_t attr = 1; attr <= static_cast<uint32_t>(SquishMessageAttribute::kSeen); attr <<= 1) {
    if (frame_header->attr & attr) {
      message->SetAttribute(static_cast<SquishMessageAttribute>(attr), true);
    }
  }

  // Чтение тела сообщения
  sqd_file_.seekg(index_record.offset + kSquishFrameHeaderSize, std::ios::beg);
  std::vector<char> body_data(frame_header->msg_length - (kSquishFrameHeaderSize - 28));
  sqd_file_.read(body_data.data(), body_data.size());

  if (sqd_file_.fail()) {
    return std::unexpected(SquishError::kReadError);
  }

  std::string body_str(body_data.data(), body_data.size());

  // Обработка клуджей
  if (frame_header->c_len > 0 && frame_header->c_len <= body_str.size()) {
    std::string kludge_data = body_str.substr(1, frame_header->c_len - 1);
    size_t pos = 0;
    while (pos < kludge_data.size()) {
      size_t end_pos = kludge_data.find('\x01', pos);
      if (end_pos == std::string::npos) {
        end_pos = kludge_data.size();
      }

      std::string kludge = kludge_data.substr(pos, end_pos - pos);
      size_t space_pos = kludge.find(' ');
      if (space_pos != std::string::npos) {
        std::string key = kludge.substr(0, space_pos);
        std::string value = kludge.substr(space_pos + 1);
        message->AddKludge(key, value);
      }

      pos = end_pos + 1;
    }

    body_str = body_str.substr(frame_header->c_len);
  }

  // Удаление нулевых символов
  auto null_pos = body_str.find('\0');
  if (null_pos != std::string::npos) {
    body_str.resize(null_pos);
  }

  message->set_body(body_str);

  // Проверка CRC
  uint32_t to_hash = buf_hash32(message->to());
  if (message->GetAttribute(SquishMessageAttribute::kRead)) {
    to_hash |= 0x80000000;
  }

  if (index_record.crc != to_hash) {
    spdlog::warn("CRC mismatch for message {} in Squish base (expected: {:#010x}, got: {:#010x})",
                 msg_num, to_hash, index_record.crc);
    // Возвращаем сообщение, но логируем предупреждение -- для совместимости
  }

  return message;
}

inline std::expected<uint32_t, SquishError> SquishMessageBase::GetLastRead() {
  if (!is_open_) {
    return std::unexpected(SquishError::kFileNotFound);
  }

  if (!sql_file_.is_open()) {
    return 0;
  }

  sql_file_.seekg(0, std::ios::beg);
  uint32_t last_read = 0;
  sql_file_.read(reinterpret_cast<char*>(&last_read), sizeof(last_read));

  if (sql_file_.fail()) {
    return 0;
  }

  // Поиск соответствующего индекса
  for (size_t i = 0; i < index_structure_.size(); ++i) {
    if (index_structure_[i].message_num == last_read) {
      return static_cast<uint32_t>(i + 1);
    }
  }

  return index_structure_.empty() ? 0 : static_cast<uint32_t>(index_structure_.size());
}

inline SquishError SquishMessageBase::SetLastRead(uint32_t msg_num) {
  if (!is_open_) {
    return SquishError::kFileNotFound;
  }

  if (msg_num == 0 || msg_num > index_structure_.size()) {
    return SquishError::kInvalidMessageNumber;
  }

  uint32_t message_num = index_structure_[msg_num - 1].message_num;

  sql_file_.seekp(0, std::ios::beg);
  sql_file_.write(reinterpret_cast<const char*>(&message_num), sizeof(message_num));
  sql_file_.flush();

  return sql_file_.fail() ? SquishError::kWriteError : SquishError::kSuccess;
}

inline SquishError SquishMessageBase::AddMessage(const SquishMessage& message) {
  if (!is_open_) {
    return SquishError::kFileNotFound;
  }

  // ── 1. Подготовка клуджей ──
  std::string kludges;
  for (const auto& [key, value] : message.kludges()) {
    kludges += "\x01" + key + " " + value;
  }
  kludges += "\x00";  // null terminator kludge section

  // body = kludges + text (без дополнительного null terminator — баг #19)
  std::string body = kludges + message.body();

  // ── 2. Подготовка заголовка фрейма ──
  SquishFrameHeader frame_header{};
  frame_header.id = kSquishFrameSignature;
  frame_header.attr = 0;

  // Даты
  frame_header.date_written = chrono_to_squish_time(message.date_written());
  frame_header.date_arrived = chrono_to_squish_time(message.date_arrived());

  // Баг #17: FROM address
  frame_header.from_zone = message.from_address().zone();
  frame_header.from_net = message.from_address().net();
  frame_header.from_node = message.from_address().node();
  frame_header.from_point = message.from_address().point();

  // Баг #17: TO address (was missing!)
  frame_header.to_zone = message.to_address().zone();
  frame_header.to_net = message.to_address().net();
  frame_header.to_node = message.to_address().node();
  frame_header.to_point = message.to_address().point();

  // Баг #20: UTC timezone
  frame_header.utc = 0;  // UTC

  // Длина kludge section
  frame_header.c_len = static_cast<uint32_t>(kludges.size());

  // msg_length = размер данных после frame header (kludges + body + null)
  frame_header.msg_length = static_cast<uint32_t>(body.size()) + 1;  // +1 for trailing null

  // frame_length = msg_length (данные) + размер заголовка
  frame_header.frame_length = frame_header.msg_length + kSquishFrameHeaderSize;

  // Баг #13, #21: Frame chain (linked list)
  if (index_structure_.empty()) {
    // Первый фрейм
    frame_header.next_frame = 0xFFFFFFFF;  // конец списка
    frame_header.prev_frame = 0xFFFFFFFF;
    base_header_.begin_frame = 0;  // будет установлен после записи
  } else {
    // Найти последний фрейм и обновить его next_frame
    uint32_t last_offset = index_structure_.back().offset;
    auto last_hdr = ReadFrameHeader(last_offset);
    if (last_hdr) {
      last_hdr->next_frame = 0;  // будет установлен после записи
      WriteFrameHeader(last_offset, *last_hdr);
    }
    frame_header.prev_frame = last_offset;
    frame_header.next_frame = 0xFFFFFFFF;
  }

  // Атрибуты
  for (uint32_t attr = 1; attr <= static_cast<uint32_t>(SquishMessageAttribute::kSeen); attr <<= 1) {
    if (message.GetAttribute(static_cast<SquishMessageAttribute>(attr))) {
      frame_header.attr |= attr;
    }
  }

  // Баг #18: Копирование строк с null-termination
  auto safe_copy = [](std::string_view src, std::array<uint8_t, 36>& dst) {
    dst.fill(0);
    std::copy_n(src.data(), std::min(src.size(), dst.size() - 1), dst.begin());
    dst.back() = '\0';
  };
  auto safe_copy_subject = [](std::string_view src, std::array<uint8_t, 72>& dst) {
    dst.fill(0);
    std::copy_n(src.data(), std::min(src.size(), dst.size() - 1), dst.begin());
    dst.back() = '\0';
  };

  safe_copy(message.from(), frame_header.from);
  safe_copy(message.to(), frame_header.to);
  safe_copy_subject(message.subject(), frame_header.subject);

  // UMsgID — уникальный ID сообщения
  if (index_structure_.empty()) {
    frame_header.u_msg_id = 1;
  } else {
    frame_header.u_msg_id = index_structure_.back().message_num + 1;
  }

  // Reply chain
  frame_header.reply_to = message.reply_to();

  // ── 3. Запись фрейма ──
  sqd_file_.seekp(0, std::ios::end);
  uint32_t frame_offset = static_cast<uint32_t>(sqd_file_.tellp());

  // Запись заголовка фрейма
  sqd_file_.write(reinterpret_cast<const char*>(&frame_header), sizeof(frame_header));

  // Запись тела (kludges + text + null)
  uint8_t null_byte = 0;
  sqd_file_.write(body.c_str(), static_cast<std::streamsize>(body.size()));
  sqd_file_.write(reinterpret_cast<const char*>(&null_byte), 1);
  sqd_file_.flush();

  if (sqd_file_.fail()) {
    return SquishError::kWriteError;
  }

  // Обновить next_frame у предыдущего фрейма (теперь мы знаем offset)
  if (!index_structure_.empty()) {
    uint32_t last_offset = index_structure_.back().offset;
    auto last_hdr = ReadFrameHeader(last_offset);
    if (last_hdr) {
      last_hdr->next_frame = frame_offset;
      WriteFrameHeader(last_offset, *last_hdr);
    }
  }

  // Обновить base header pointers (баг #21)
  if (base_header_.begin_frame == 0) {
    base_header_.begin_frame = frame_offset;
  }
  base_header_.last_frame = frame_offset;
  base_header_.end_frame = frame_offset;
  base_header_.num_msgs++;
  base_header_.high_msg++;
  base_header_.uid++;

  // ── 4. Обновление индекса ──
  SquishIndexRecord index_record{};
  index_record.offset = frame_offset;
  index_record.message_num = frame_header.u_msg_id;
  index_record.crc = buf_hash32(message.to());

  index_structure_.push_back(index_record);

  // ── 5. Запись обновленных заголовков ──
  if (auto error = WriteBaseHeader(); error != SquishError::kSuccess) {
    return error;
  }

  if (auto error = WriteIndex(); error != SquishError::kSuccess) {
    return error;
  }

  return SquishError::kSuccess;
}

inline SquishError SquishMessageBase::DeleteMessage(uint32_t msg_num) {
  if (!is_open_) {
    return SquishError::kFileNotFound;
  }

  if (msg_num == 0 || msg_num > index_structure_.size()) {
    return SquishError::kInvalidMessageNumber;
  }

  // TODO: Реализация удаления сообщения (отметка как удаленного в индексе)
  // В текущей реализации просто удаляем из индекса
  index_structure_.erase(index_structure_.begin() + (msg_num - 1));

  base_header_.num_msgs--;

  if (auto error = WriteBaseHeader(); error != SquishError::kSuccess) {
    return error;
  }

  if (auto error = WriteIndex(); error != SquishError::kSuccess) {
    return error;
  }

  return SquishError::kSuccess;
}

inline uint32_t SquishMessageBase::last_message_number() const {
  return index_structure_.empty() ? 0 : index_structure_.back().message_num;
}

// Вспомогательные private методы
inline SquishError SquishMessageBase::ReadBaseHeader() {
  sqd_file_.seekg(0, std::ios::beg);
  sqd_file_.read(reinterpret_cast<char*>(&base_header_), sizeof(SquishBaseHeader));
  return sqd_file_.fail() ? SquishError::kReadError : SquishError::kSuccess;
}

inline SquishError SquishMessageBase::WriteBaseHeader() {
  sqd_file_.seekp(0, std::ios::beg);
  sqd_file_.write(reinterpret_cast<const char*>(&base_header_), sizeof(SquishBaseHeader));
  sqd_file_.flush();
  return sqd_file_.fail() ? SquishError::kWriteError : SquishError::kSuccess;
}

inline SquishError SquishMessageBase::ReadIndex() {
  index_structure_.clear();

  sqi_file_.seekg(0, std::ios::end);
  const auto file_size_pos = sqi_file_.tellg();
  if (file_size_pos == static_cast<std::streampos>(-1)) {
    return SquishError::kReadError;
  }
  size_t file_size = static_cast<size_t>(file_size_pos);
  size_t num_records = file_size / sizeof(SquishIndexRecord);

  sqi_file_.seekg(0, std::ios::beg);

  for (size_t i = 0; i < num_records; ++i) {
    SquishIndexRecord record;
    sqi_file_.read(reinterpret_cast<char*>(&record), sizeof(SquishIndexRecord));
    if (sqi_file_.fail()) {
      return SquishError::kReadError;
    }
    if (record.offset != 0) {
      index_structure_.push_back(record);
    }
  }

  return SquishError::kSuccess;
}

inline SquishError SquishMessageBase::WriteIndex() {
  sqi_file_.seekp(0, std::ios::beg);
  for (const auto& record : index_structure_) {
    sqi_file_.write(reinterpret_cast<const char*>(&record), sizeof(SquishIndexRecord));
    if (sqi_file_.fail()) {
      return SquishError::kWriteError;
    }
  }
  // Truncate file to actual data size
  sqi_file_.flush();
  // Note: proper truncation requires platform-specific call (ftruncate on POSIX)
  return SquishError::kSuccess;
}

inline std::expected<SquishBaseHeader, SquishError> SquishMessageBase::ReadSquishBaseHeader() {
  SquishBaseHeader header;
  sqd_file_.seekg(0, std::ios::beg);
  sqd_file_.read(reinterpret_cast<char*>(&header), sizeof(SquishBaseHeader));

  if (sqd_file_.fail()) {
    return std::unexpected(SquishError::kReadError);
  }

  if (header.len != kSquishHeaderSize) {
    return std::unexpected(SquishError::kInvalidSignature);
  }

  return header;
}

inline std::expected<SquishFrameHeader, SquishError> SquishMessageBase::ReadFrameHeader(uint32_t offset) {
  SquishFrameHeader header;
  sqd_file_.seekg(offset, std::ios::beg);
  sqd_file_.read(reinterpret_cast<char*>(&header), sizeof(SquishFrameHeader));

  if (sqd_file_.fail()) {
    return std::unexpected(SquishError::kReadError);
  }

  return header;
}

inline SquishError SquishMessageBase::WriteFrameHeader(uint32_t offset, const SquishFrameHeader& header) {
  sqd_file_.seekp(offset, std::ios::beg);
  sqd_file_.write(reinterpret_cast<const char*>(&header), sizeof(SquishFrameHeader));
  sqd_file_.flush();
  return sqd_file_.fail() ? SquishError::kWriteError : SquishError::kSuccess;
}

// ─── Special member functions (RAII) ───
inline SquishMessageBase::~SquishMessageBase() {
  Close();
}

inline SquishMessageBase::SquishMessageBase(SquishMessageBase&& other) noexcept
    : base_path_(std::move(other.base_path_)),
      is_open_(other.is_open_),
      base_header_(other.base_header_),
      index_structure_(std::move(other.index_structure_)),
      sqd_file_(std::move(other.sqd_file_)),
      sqi_file_(std::move(other.sqi_file_)),
      sql_file_(std::move(other.sql_file_)) {
  other.is_open_ = false;
}

inline SquishMessageBase& SquishMessageBase::operator=(SquishMessageBase&& other) noexcept {
  if (this != &other) {
    Close();
    base_path_ = std::move(other.base_path_);
    is_open_ = other.is_open_;
    base_header_ = other.base_header_;
    index_structure_ = std::move(other.index_structure_);
    sqd_file_ = std::move(other.sqd_file_);
    sqi_file_ = std::move(other.sqi_file_);
    sql_file_ = std::move(other.sql_file_);
    other.is_open_ = false;
  }
  return *this;
}

inline SquishMessageBase::SquishMessageBase(std::string_view base_path)
    : base_path_(base_path) {
}

}  // namespace msgapi
