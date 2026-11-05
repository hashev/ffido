#include <fcntl.h>
#include <google/protobuf/util/json_util.h>
#include <openssl/rand.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>

#include <fstream>
#include <iostream>
#include <utility>

#include "mcp.hpp"
namespace ffido_mcp {
namespace {
struct Fd {
  int value;
  explicit Fd(int fd) : value(fd) {
  }
  ~Fd() {
    if (value >= 0)
      close(value);
  }
  Fd(const Fd&) = delete;
  Fd& operator=(const Fd&) = delete;
};
[[noreturn]] void Unsafe() {
  throw Error("LOCAL_CONFIG", "Invalid or unsafe local configuration/state file");
}
int Directory(const std::filesystem::path& path) {
  Fd dir(open(path.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
  struct stat info{};
  if (dir.value < 0 || fstat(dir.value, &info) != 0 || info.st_uid != geteuid() || (info.st_mode & 0777) != 0700)
    Unsafe();
  return std::exchange(dir.value, -1);
}
std::string Read(const std::filesystem::path& path, bool secret) {
  if (!secret) {
    std::ifstream input(path, std::ios::binary);
    if (!input)
      Unsafe();
    std::string text;
    char bytes[4096];
    while (input.read(bytes, sizeof(bytes)) || input.gcount()) {
      text.append(bytes, input.gcount());
      if (text.size() > 1024 * 1024)
        Unsafe();
    }
    if (!input.eof())
      Unsafe();
    return text;
  }
  Fd directory(Directory(path.parent_path()));
  Fd file(openat(directory.value, path.filename().c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC));
  struct stat info{};
  if (file.value < 0 || fstat(file.value, &info) != 0 || !S_ISREG(info.st_mode) || info.st_nlink != 1 ||
      info.st_uid != geteuid() || (info.st_mode & 0777) != 0600 || info.st_size < 0 || info.st_size > 4 * 1024 * 1024)
    Unsafe();
  std::string text(static_cast<size_t>(info.st_size), '\0');
  size_t offset = 0;
  while (offset < text.size()) {
    const auto count = read(file.value, text.data() + offset, text.size() - offset);
    if (count <= 0)
      Unsafe();
    offset += static_cast<size_t>(count);
  }
  return text;
}
}  // namespace
void EnsureState(const std::filesystem::path& path) {
  if (mkdir(path.c_str(), 0700) != 0 && errno != EEXIST)
    Unsafe();
  Fd directory(Directory(path));
}
std::string ReadSecret(const std::filesystem::path& path) {
  return Read(path, true);
}
void SaveSecret(const std::filesystem::path& path, std::string_view text) {
  Fd directory(Directory(path.parent_path()));
  const auto name = ".tmp-" + RandomId();
  Fd file(openat(directory.value, name.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
  if (file.value < 0)
    Unsafe();
  try {
    size_t offset = 0;
    while (offset < text.size()) {
      const auto count = write(file.value, text.data() + offset, text.size() - offset);
      if (count <= 0)
        Unsafe();
      offset += static_cast<size_t>(count);
    }
    if (fsync(file.value) != 0 ||
        renameat(directory.value, name.c_str(), directory.value, path.filename().c_str()) != 0 ||
        fsync(directory.value) != 0)
      Unsafe();
  } catch (...) {
    unlinkat(directory.value, name.c_str(), 0);
    throw;
  }
}
std::string RandomId() {
  std::array<unsigned char, 24> bytes{};
  if (RAND_bytes(bytes.data(), bytes.size()) != 1)
    throw Error("INTERNAL", "Identity generation failed");
  constexpr char hex[] = "0123456789abcdef";
  std::string result;
  for (auto byte : bytes) {
    result += hex[byte >> 4];
    result += hex[byte & 15];
  }
  return result;
}
Config LoadConfig(const std::filesystem::path& path) {
  const auto value = Json::parse(Read(path, false));
  Config result;
  result.endpoint = value.at("endpoint").get<std::string>();
  if (result.endpoint.empty() || result.endpoint.find('/') != std::string::npos)
    Unsafe();
  const auto parent = std::filesystem::absolute(path).parent_path();
  const auto resolve = [&](const char* name) {
    return (parent / value.at(name).get<std::string>()).lexically_normal();
  };
  result.session_file = resolve("session_file");
  result.state_dir = resolve("state_dir");
  for (auto pair : {std::pair{"read_area_ids", &result.read_areas}, std::pair{"post_area_ids", &result.post_areas}}) {
    if (!value.contains(pair.first))
      continue;
    for (const auto& id : value.at(pair.first)) {
      const auto text = id.get<std::string>();
      if (text.empty() || text.size() > 1024 || text.find('*') != std::string::npos)
        Unsafe();
      pair.second->insert(text);
    }
  }
  if (value.contains("tls_ca_file"))
    result.certificate = Read(resolve("tls_ca_file"), false);
  EnsureState(result.state_dir);
  return result;
}
Json Encode(const google::protobuf::Message& message) {
  google::protobuf::util::JsonPrintOptions options;
  options.preserve_proto_field_names = true;
  options.always_print_fields_with_no_presence = true;
  std::string text;
  if (!google::protobuf::util::MessageToJsonString(message, &text, options).ok())
    throw Error("INTERNAL", "Cannot encode response");
  return Json::parse(text);
}
void Decode(const Json& value, google::protobuf::Message& message) {
  if (!google::protobuf::util::JsonStringToMessage(value.dump(), &message).ok())
    throw Error("INVALID_ARGUMENT", "Invalid request fields");
}
void Check(const grpc::Status& status) {
  if (status.ok())
    return;
  const auto code = static_cast<int>(status.error_code());
  throw Error("GRPC_" + std::to_string(code),
              code == 12 ? "Backend requires an update for this operation" : "FFIDO operation failed",
              code == 14 || code == 8);
}
Client::Client(Config config, bool login) : config_(std::move(config)) {
  grpc::SslCredentialsOptions tls;
  tls.pem_root_certs = config_.certificate;
  grpc::ChannelArguments arguments;
  arguments.SetMaxReceiveMessageSize(32 * 1024 * 1024);
  stub_ = wire::Ffido::NewStub(grpc::CreateCustomChannel(config_.endpoint, grpc::SslCredentials(tls), arguments));
  if (!login) {
    token_ = Json::parse(ReadSecret(config_.session_file)).at("token").get<std::string>();
    if (token_.empty() || token_.size() > 8192 || token_.find_first_of("\r\n") != std::string::npos)
      Unsafe();
  }
}
void Client::Area(std::string_view id, bool post) const {
  const auto& allowed = post ? config_.post_areas : config_.read_areas;
  if (!allowed.contains(std::string(id)))
    throw Error("PERMISSION_DENIED", "Area is outside the configured MCP permissions");
}
void Client::Authorize(grpc::ClientContext& context) const {
  context.AddMetadata("authorization", "Bearer " + token_);
}
std::shared_ptr<grpc::ClientContext> CallContext::Next() {
  std::lock_guard lock(mutex);
  current = std::make_shared<grpc::ClientContext>();
  current->set_deadline(deadline);
  if (cancelled)
    current->TryCancel();
  return current;
}
void CallContext::Cancel() {
  std::lock_guard lock(mutex);
  cancelled = true;
  wake.notify_all();
  if (current)
    current->TryCancel();
}
void CallContext::Acquire(std::unique_lock<std::timed_mutex>& lock) {
  std::unique_lock guard(mutex);
  while (!cancelled && std::chrono::system_clock::now() < deadline) {
    if (lock.try_lock())
      return;
    wake.wait_until(guard, std::min(deadline, std::chrono::system_clock::now() + std::chrono::milliseconds(10)));
  }
  throw Error(cancelled ? "GRPC_1" : "GRPC_4", "MCP operation no longer active");
}
void Client::Login() {
  if (!isatty(STDIN_FILENO))
    throw Error("LOCAL_CONFIG", "Login requires an interactive terminal");
  wire::LoginRequest request;
  std::string value;
  std::cerr << "Name: ";
  std::getline(std::cin, value);
  request.set_name(value);
  std::cerr << "FTN address: ";
  std::getline(std::cin, value);
  request.set_address(value);
  termios original{};
  if (tcgetattr(STDIN_FILENO, &original) != 0)
    Unsafe();
  struct Restore {
    termios value;
    ~Restore() {
      tcsetattr(STDIN_FILENO, TCSAFLUSH, &value);
    }
  } restore{original};
  auto hidden = original;
  hidden.c_lflag &= ~ECHO;
  if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &hidden) != 0)
    Unsafe();
  std::cerr << "Password: ";
  std::getline(std::cin, value);
  std::cerr << '\n';
  request.set_password(value);
  grpc::ClientContext context;
  context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(5));
  wire::LoginResponse response;
  Check(stub_->Login(&context, request, &response));
  SaveSecret(config_.session_file, Json{{"token", response.session_secret()}}.dump());
  std::cerr << "Session saved. Restart the MCP process.\n";
}
}  // namespace ffido_mcp
