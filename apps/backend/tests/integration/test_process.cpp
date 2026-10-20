#include <fcntl.h>
#include <grpcpp/grpcpp.h>
#include <gtest/gtest.h>
#include <netinet/in.h>
#include <signal.h>
#include <spawn.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/wait.h>

#include <future>
#include <nlohmann/json.hpp>
#include <thread>

#include "../support/jam_wire_record.hpp"
#include "../support/temp_directory.hpp"
#include "../support/tls_certificate.hpp"
#include "ffido/v1/ffido.grpc.pb.h"
#include "service/auth_service.hpp"
#include "service/grpc_runtime.hpp"
#include "storage/jam_access.hpp"
extern char** environ;
namespace {
namespace wire = ffido::v1;
using namespace fidoback;
class ServerProcess {
public:
  pid_t pid = -1;
  explicit ServerProcess(const std::filesystem::path& config, const std::filesystem::path& log) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    std::string binary = FFIDO_SERVER_BINARY, argument = config.string();
    char* argv[] = {binary.data(), argument.data(), nullptr};
    const int error = posix_spawn(&pid, binary.c_str(), &actions, nullptr, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (error != 0) {
      pid = -1;
      throw std::runtime_error("Cannot spawn test server");
    }
  }
  ~ServerProcess() {
    if (pid > 0) {
      kill(pid, SIGKILL);
      int status;
      waitpid(pid, &status, 0);
    }
  }
  int Wait(std::chrono::seconds timeout = std::chrono::seconds(8)) {
    const auto until = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < until) {
      int status = 0;
      const auto result = waitpid(pid, &status, WNOHANG);
      if (result == pid) {
        pid = -1;
        return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
      }
      if (result < 0)
        return -2;
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    return -1;
  }
};
class ProcessTest : public ::testing::Test {
protected:
  service::GrpcRuntime runtime;
  test::TempDirectory temp;
  std::filesystem::path config;
  std::shared_ptr<storage::IMetadataStore> metadata;
  std::shared_ptr<storage::JamCatalog> catalog;
  std::shared_ptr<grpc::Channel> channel;
  std::string token;
  void SetUp() override {
    test::GenerateTlsCertificate(temp.path());
    msgapi::JamBaseHeader header{};
    header.signature = msgapi::kJamSignature;
    header.base_msg_num = 42;
    header.date_created = 123;
    header.password_crc = UINT32_MAX;
    const auto bytes = msgapi::jam_wire::Encode(header);
    {
      std::ofstream output(temp.path() / "file.jhr", std::ios::binary);
      output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    }
    for (auto ext : {".jdt", ".jdx"}) {
      std::ofstream output(temp.path() / std::string("file" + std::string(ext)), std::ios::binary);
    }
    {
      std::ofstream output(temp.path() / "areas.cfg");
      output << "EchoArea RU.TEST file -b JAM\n";
    }
    EchoAreaConfig area;
    area.name = "RU.TEST";
    area.filename = "file";
    area.msgbase_type = "JAM";
    auto coord = storage::CoordinationLock::Open(temp.path() / "hpt.lock");
    ASSERT_TRUE(coord);
    auto opened = storage::JamCatalog::Build(temp.path(), {area}, *coord);
    ASSERT_TRUE(opened);
    catalog = std::shared_ptr<storage::JamCatalog>(std::move(*opened));
    metadata = storage::CreateSQLiteStore(temp.path() / "metadata.db");
    ASSERT_TRUE(metadata->Init());
    service::AuthService auth(metadata);
    ASSERT_TRUE(metadata->SaveProfile("test", domain::Profile{"Юрий", "2:1/2", "", ""}));
    auto key = service::LoadSessionKey(temp.path() / "session.key");
    ASSERT_TRUE(key);
    ASSERT_TRUE(auth.Configure({{"2:1/2", "fixture-password"}}, *key));
    auto issued = auth.Login("Юрий", "2:1/2", "fixture-password");
    ASSERT_TRUE(issued);
    token = issued->token;
    std::ofstream(temp.path() / "hpt-auth.cfg")
        << "Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\nLink "
           "Client\nAKA 2:1/2\nOurAKA 2:1/1\nPassword fixture-password\nEchoArea RU.TEST "
        << (temp.path() / "file").string() << " -b JAM 2:1/2\n";
    const int socket_fd = socket(AF_INET, SOCK_STREAM, 0);
    ASSERT_GE(socket_fd, 0);
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    ASSERT_EQ(bind(socket_fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)), 0);
    socklen_t size = sizeof(address);
    ASSERT_EQ(getsockname(socket_fd, reinterpret_cast<sockaddr*>(&address), &size), 0);
    const int port = ntohs(address.sin_port);
    close(socket_fd);
    config = temp.path() / "config.json";
    nlohmann::json value = {{"auth", {{"hpt_config_path", "hpt-auth.cfg"}, {"session_key_path", "session.key"}}},
                            {"server",
                             {{"ip", "127.0.0.1"},
                              {"port", port},
                              {"thread_num", 4},
                              {"rpc_timeout_ms", 5000},
                              {"shutdown_timeout_ms", 500},
                              {"tls_certificate", "certificate.pem"},
                              {"tls_private_key", "key.pem"}}},
                            {"ftn",
                             {{"areacfg_path", "areas.cfg"},
                              {"jam_base_path", "."},
                              {"coordination_lock", "hpt.lock"},
                              {"default_encoding", "UTF-8"}}},
                            {"database", {{"metadata_path", "metadata.db"}}}};
    {
      std::ofstream output(config);
      output << value;
    }
    grpc::SslCredentialsOptions roots;
    roots.pem_root_certs = test::ReadFile(temp.path() / "certificate.pem");
    channel = grpc::CreateChannel("127.0.0.1:" + std::to_string(port), grpc::SslCredentials(roots));
  }
  void Ready() {
    ASSERT_TRUE(channel->WaitForConnected(std::chrono::system_clock::now() + std::chrono::seconds(8)))
        << test::ReadFile(temp.path() / "server.log");
  }
  void TearDown() override {
    channel.reset();
    EXPECT_TRUE(runtime.Shutdown(std::chrono::steady_clock::now() + std::chrono::seconds(5)));
  }
  grpc::Status Send(std::string id, std::string body = "Текст") {
    auto stub = wire::Ffido::NewStub(channel);
    grpc::ClientContext context;
    context.AddMetadata("authorization", "Bearer " + token);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(6));
    wire::CreateMessageRequest request;
    request.set_conference_id("RU.TEST");
    request.set_operation_id(id);
    request.set_to_name("All");
    request.set_subject("Тема");
    request.set_body(body);
    wire::CreateMessageResponse response;
    return stub->CreateMessage(&context, request, &response);
  }
};
}  // namespace
TEST_F(ProcessTest, SignalsAtIdleAndInstanceLockIsReleased) {
  for (int signal : {SIGINT, SIGTERM}) {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    ServerProcess duplicate(config, temp.path() / "duplicate.log");
    EXPECT_GT(duplicate.Wait(), 0);
    ASSERT_EQ(kill(process.pid, signal), 0);
    EXPECT_EQ(process.Wait(), 0);
  }
}
TEST_F(ProcessTest, BindFailureReturnsNonzero) {
  ServerProcess first(config, temp.path() / "server.log");
  Ready();
  auto value = nlohmann::json::parse(test::ReadFile(config));
  value["database"]["metadata_path"] = "other.db";
  const auto other = temp.path() / "other.json";
  {
    std::ofstream output(other);
    output << value;
  }
  ServerProcess duplicate(other, temp.path() / "duplicate.log");
  EXPECT_GT(duplicate.Wait(), 0);
  ASSERT_EQ(kill(first.pid, SIGTERM), 0);
  EXPECT_EQ(first.Wait(), 0);
}
TEST_F(ProcessTest, SignalsDuringExternalLockWaitHaveNoIntent) {
  for (int signal : {SIGINT, SIGTERM}) {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    const int fd = open((temp.path() / "hpt.lock").c_str(), O_RDWR);
    ASSERT_GE(fd, 0);
    ASSERT_EQ(flock(fd, LOCK_EX), 0);
    auto request = std::async(std::launch::async, [this, signal] { return Send("waiting" + std::to_string(signal)); });
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    ASSERT_EQ(kill(process.pid, signal), 0);
    EXPECT_EQ(process.Wait(), 0);
    EXPECT_FALSE(request.get().ok());
    flock(fd, LOCK_UN);
    close(fd);
    auto operation = metadata->FindOperation("test", "waiting" + std::to_string(signal));
    ASSERT_TRUE(operation);
    EXPECT_FALSE(*operation);
  }
}
TEST_F(ProcessTest, SignalsDrainStartedWritesAndRestartKeepsCommittedMessages) {
  for (int signal : {SIGINT, SIGTERM}) {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    std::vector<std::future<grpc::Status>> requests;
    for (int i = 0; i < 8; i++)
      requests.push_back(std::async(std::launch::async, [this, signal, i] {
        return Send("write-" + std::to_string(signal) + "-" + std::to_string(i), std::string(512 * 1024, 'x'));
      }));
    bool observed = false;
    const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (!observed && std::chrono::steady_clock::now() < until) {
      for (int i = 0; i < 8; i++) {
        auto operation = metadata->FindOperation("test", "write-" + std::to_string(signal) + "-" + std::to_string(i));
        if (operation && *operation) {
          observed = true;
          break;
        }
      }
      std::this_thread::yield();
    }
    ASSERT_TRUE(observed);
    ASSERT_EQ(kill(process.pid, signal), 0);
    EXPECT_EQ(process.Wait(), 0);
    for (auto& request : requests)
      request.get();
    auto pending = metadata->PendingOperations();
    ASSERT_TRUE(pending);
    EXPECT_TRUE(pending->empty());
    std::size_t committed = 0;
    for (int sig : {SIGINT, SIGTERM})
      for (int i = 0; i < 8; i++) {
        auto operation = metadata->FindOperation("test", "write-" + std::to_string(sig) + "-" + std::to_string(i));
        ASSERT_TRUE(operation);
        if (*operation) {
          EXPECT_EQ((**operation).state, storage::OperationState::kCommitted);
          committed++;
        }
      }
    auto access = storage::JamAccess::Open(*catalog, "RU.TEST", false,
                                           std::chrono::steady_clock::now() + std::chrono::seconds(1));
    ASSERT_TRUE(access);
    EXPECT_EQ((*access)->messages().message_count(), committed);
    access->reset();
  }
}

TEST_F(ProcessTest, HptRoundTripAndConcurrentExportWithSharedWrapper) {
  const char* hpt = std::getenv("FFIDO_TEST_HPT");
  if (!hpt || !*hpt)
    GTEST_SKIP() << "Set FFIDO_TEST_HPT to the deployment HPT executable";
  const auto root = temp.path();
  for (auto directory : {"inbound", "protinbound", "outbound", "tmpin", "tmpout", "logs", "dupes", "nodelist"})
    std::filesystem::create_directory(root / directory);
  const auto hpt_config = root / "hpt.cfg";
  {
    std::ofstream out(hpt_config);
    out << "Name FFIDO isolated test\nSysop Test\nLocation Test\nAddress 2:1/2\n";
    for (auto [keyword, directory] : {std::pair{"Inbound", "inbound"},
                                      {"ProtInbound", "protinbound"},
                                      {"Outbound", "outbound"},
                                      {"TempInbound", "tmpin"},
                                      {"TempOutbound", "tmpout"},
                                      {"LogFileDir", "logs"},
                                      {"DupeHistoryDir", "dupes"},
                                      {"NodelistDir", "nodelist"}})
      out << keyword << " " << (root / directory).string() << "\n";
    out << "MsgBaseDir " << root.string() << "\nEchoTossLog " << (root / "logs/toss.log").string() << "\nImportLog "
        << (root / "logs/import.log").string() << "\n";
    out << "Link Downlink\nAKA 2:1/3\nOurAKA 2:1/2\nAllowEmptyPktPwd on\nEchoMailFlavour direct\n";
    out << "NetmailArea NETMAIL " << (root / "netmail").string() << " -b JAM\nBadArea BAD " << (root / "bad").string()
        << " -b JAM\nDupeArea DUPE " << (root / "dupe").string() << " -b JAM\n";
    out << "EchoArea RU.TEST " << (root / "file").string() << " -b JAM -a 2:1/2 2:1/3\n";
  }
  auto run_hpt = [&](std::string suffix) {
    std::vector<std::string> arguments = {FFIDO_PYTHON, FFIDO_HPT_WRAPPER,
                                          "--config",   config.string(),
                                          "--timeout",  "10",
                                          "--",         hpt,
                                          "-c",         hpt_config.string(),
                                          "scan",       "-w",
                                          "-a",         "RU.TEST"};
    std::vector<char*> pointers;
    for (auto& argument : arguments)
      pointers.push_back(argument.data());
    pointers.push_back(nullptr);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    auto log = root / ("hpt-" + suffix + ".log");
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    pid_t pid = -1;
    const int error = posix_spawn(&pid, arguments[0].c_str(), &actions, nullptr, pointers.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    if (error)
      return error;
    int status = 0;
    if (waitpid(pid, &status, 0) != pid)
      return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
  };
  ServerProcess process(config, root / "server.log");
  Ready();
  auto client = wire::Ffido::NewStub(channel);
  wire::CreateMessageRequest request;
  request.set_conference_id("RU.TEST");
  request.set_to_name("All");
  request.set_to_address("2:1/7.8");
  request.set_subject("Русская тема");
  request.set_body("Привет, мир!");
  request.set_operation_id("utf8");
  auto create = [&](const wire::CreateMessageRequest& input, wire::CreateMessageResponse& output) {
    grpc::ClientContext context;
    context.AddMetadata("authorization", "Bearer " + token);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(15));
    return client->CreateMessage(&context, input, &output);
  };
  wire::CreateMessageResponse first, reply;
  ASSERT_TRUE(create(request, first).ok());
  request.set_operation_id("reply");
  request.set_in_reply_to(first.message().message_id());
  ASSERT_TRUE(create(request, reply).ok());
  ASSERT_EQ(run_hpt("utf8"), 0) << test::ReadFile(root / "hpt-utf8.log");
  ASSERT_EQ(kill(process.pid, SIGTERM), 0);
  ASSERT_EQ(process.Wait(), 0);
  auto value = nlohmann::json::parse(test::ReadFile(config));
  value["ftn"]["default_encoding"] = "cp866";
  {
    std::ofstream out(config);
    out << value;
  }
  ASSERT_TRUE(metadata->SaveProfile("test", domain::Profile{"НЮрий", "2:1/2", "", ""}));
  ServerProcess cp866(config, root / "server.log");
  Ready();
  for (const auto& saved : {first, reply}) {
    grpc::ClientContext context;
    context.AddMetadata("authorization", "Bearer " + token);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(5));
    wire::Message detail;
    ASSERT_TRUE(client->GetMessage(&context, saved.message(), &detail).ok());
    EXPECT_EQ(detail.to_address(), saved.ftn_message_id() == first.ftn_message_id() ? "2:1/7.8" : "2:1/2");
  }
  request.set_to_name("НAllН");
  request.set_subject("НРусская темаН");
  request.set_body("НПривет, мир!Н");
  auto exporting = std::async(std::launch::async, [&] {
    for (int i = 0; i < 10; i++) {
      const int code = run_hpt(std::to_string(i));
      if (code)
        return code;
    }
    return 0;
  });
  for (int i = 0; i < 20; i++) {
    request.clear_in_reply_to();
    request.set_operation_id("cp866-" + std::to_string(i));
    wire::CreateMessageResponse saved;
    ASSERT_TRUE(create(request, saved).ok());
    wire::CreateMessageResponse repeated;
    ASSERT_TRUE(create(request, repeated).ok());
    EXPECT_EQ(saved.message().message_id(), repeated.message().message_id());
    wire::ListMessagesRequest list;
    list.set_conference_id("RU.TEST");
    list.mutable_page()->set_limit(100);
    list.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
    wire::ListMessagesResponse rows;
    grpc::ClientContext context;
    context.AddMetadata("authorization", "Bearer " + token);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(15));
    ASSERT_TRUE(client->ListMessages(&context, list, &rows).ok());
    EXPECT_EQ(rows.total(), i + 3);
  }
  EXPECT_EQ(exporting.get(), 0);
  ASSERT_EQ(run_hpt("final"), 0) << test::ReadFile(root / "hpt-final.log");
  auto access =
      storage::JamAccess::Open(*catalog, "RU.TEST", false, std::chrono::steady_clock::now() + std::chrono::seconds(3));
  ASSERT_TRUE(access);
  auto numbers = (*access)->messages().GetMessageNumbers();
  ASSERT_TRUE(numbers);
  ASSERT_EQ(numbers->size(), 22);
  for (auto number : *numbers) {
    auto message = (*access)->messages().ReadMessage(number);
    ASSERT_TRUE(message);
    EXPECT_EQ(message->subject(), number < (*numbers)[2] ? "Русская тема" : "HРусская темаH");
    EXPECT_NE(message->text().find("Привет, мир!"), std::string::npos);
  }
  access->reset();
  // HPT has finished all exports. Inspect wire bytes without holding a JAM
  // byte lock: closing another descriptor would release that process's locks.
  for (size_t slot = 0; slot < 22; ++slot) {
    const auto raw = test::ReadJamWireRecord(root / "file", slot);
    if (slot < 2) {
      EXPECT_TRUE(raw.HasField(2000, "CHRS: UTF-8 4"));
      EXPECT_EQ(raw.Field(6), "Русская тема");
    } else {
      EXPECT_TRUE(raw.HasField(2000, "CHRS: CP866 2"));
      EXPECT_FALSE(raw.HasField(2000, "CHRS: UTF-8 4"));
      EXPECT_EQ(raw.Field(6), "H\x90\xe3\xe1\xe1\xaa\xa0\xef \xe2\xa5\xac\xa0H");
      EXPECT_EQ(raw.Field(2), "H\x9e\xe0\xa8\xa9");
      EXPECT_EQ(raw.Field(3), "HAllH");
      EXPECT_TRUE(raw.body.starts_with("H\x8f\xe0\xa8\xa2\xa5\xe2, \xac\xa8\xe0!H\r"));
    }
  }
  std::string packets;
  for (auto& entry : std::filesystem::recursive_directory_iterator(root / "outbound"))
    if (entry.is_regular_file())
      packets += test::ReadFile(entry.path());
  if (packets.empty()) {
    for (auto& entry : std::filesystem::recursive_directory_iterator(root)) {
      if (entry.is_regular_file() && entry.path().extension() == ".log")
        std::cerr << entry.path() << "\n" << test::ReadFile(entry.path());
    }
  }
  EXPECT_NE(packets.find(first.ftn_message_id()), std::string::npos);
  EXPECT_NE(packets.find(reply.ftn_message_id()), std::string::npos);
  EXPECT_NE(packets.find("MSGID: " + first.ftn_message_id()), std::string::npos);
  EXPECT_NE(packets.find("REPLY: " + first.ftn_message_id()), std::string::npos);
  EXPECT_NE(packets.find("Привет, мир!"), std::string::npos);
  const std::string cp866_text = "H\x8f\xe0\xa8\xa2\xa5\xe2, \xac\xa8\xe0!H";
  EXPECT_NE(packets.find(cp866_text), std::string::npos);
  EXPECT_NE(packets.find("CHRS: CP866 2"), std::string::npos);
  EXPECT_NE(packets.find("H\x90\xe3\xe1\xe1\xaa\xa0\xef \xe2\xa5\xac\xa0H"), std::string::npos);
  EXPECT_NE(packets.find(std::string("H\x9e\xe0\xa8\xa9") + '\0'), std::string::npos);
  EXPECT_NE(packets.find(std::string("HAllH") + '\0'), std::string::npos);
  ASSERT_EQ(kill(cp866.pid, SIGTERM), 0);
  EXPECT_EQ(cp866.Wait(), 0);
  value["ftn"]["default_encoding"] = "KOI8-R";
  std::ofstream(config) << value;
  ServerProcess koi8(config, root / "server-koi8.log");
  Ready();
  request.set_operation_id("koi8-process");
  request.set_in_reply_to(first.message().message_id());
  request.set_subject("Тема Ёё");
  request.set_body("Привет Ёё");
  wire::CreateMessageResponse koi8_saved;
  ASSERT_TRUE(create(request, koi8_saved).ok());
  const auto before = test::ReadJamWireRecord(root / "file", 22);
  EXPECT_TRUE(before.HasField(2000, "CHRS: KOI8-R 2"));
  EXPECT_EQ(before.Field(6), "\xf4\xc5\xcd\xc1 \xb3\xa3");
  EXPECT_TRUE(before.body.starts_with("\xf0\xd2\xc9\xd7\xc5\xd4 \xb3\xa3\r"));
  ASSERT_EQ(run_hpt("koi8"), 0) << test::ReadFile(root / "hpt-koi8.log");
  const auto after = test::ReadJamWireRecord(root / "file", 22);
  EXPECT_EQ(after.body, before.body);
  EXPECT_EQ(after.Field(6), before.Field(6));
  EXPECT_TRUE(after.HasField(2000, "CHRS: KOI8-R 2"));
  wire::Message koi8_read;
  grpc::ClientContext koi8_context;
  koi8_context.AddMetadata("authorization", "Bearer " + token);
  koi8_context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(5));
  ASSERT_TRUE(client->GetMessage(&koi8_context, koi8_saved.message(), &koi8_read).ok());
  EXPECT_EQ(koi8_read.subject(), "Тема Ёё");
  EXPECT_TRUE(koi8_read.body().starts_with("Привет Ёё"));
  std::string koi8_packets;
  for (auto& entry : std::filesystem::recursive_directory_iterator(root / "outbound"))
    if (entry.is_regular_file())
      koi8_packets += test::ReadFile(entry.path());
  EXPECT_NE(koi8_packets.find("CHRS: KOI8-R 2"), std::string::npos);
  EXPECT_NE(koi8_packets.find("\xf0\xd2\xc9\xd7\xc5\xd4 \xb3\xa3"), std::string::npos);
  ASSERT_EQ(kill(koi8.pid, SIGTERM), 0);
  EXPECT_EQ(koi8.Wait(), 0);
}

TEST_F(ProcessTest, InvalidStartupInputsFailBeforeListeningWithoutJamMutation) {
  const auto original = nlohmann::json::parse(test::ReadFile(config));
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  auto reject = [&](const nlohmann::json& value) {
    {
      std::ofstream output(config);
      output << value;
    }
    ServerProcess server(config, temp.path() / "invalid-startup.log");
    EXPECT_GT(server.Wait(), 0);
    EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
  };
  auto value = original;
  value["server"]["tls_certificate"] = "";
  reject(value);
  value = original;
  value["server"]["tls_private_key"] = "";
  reject(value);
  value = original;
  value["server"]["tls_certificate"] = "missing.pem";
  reject(value);
  {
    std::ofstream output(temp.path() / "empty.pem");
  }
  value = original;
  value["server"]["tls_certificate"] = "empty.pem";
  reject(value);
  {
    std::ofstream output(temp.path() / "huge.pem");
    output << std::string(65537, 'x');
  }
  value = original;
  value["server"]["tls_private_key"] = "huge.pem";
  reject(value);
  value = original;
  value["server"]["port"] = 0;
  reject(value);
  value = original;
  value["ftn"]["areacfg_path"] = "missing.cfg";
  reject(value);
  value = original;
  value["ftn"]["coordination_lock"] = "";
  reject(value);
  value = original;
  value["ftn"]["jam_base_path"] = "missing";
  reject(value);
  {
    std::ofstream output(temp.path() / "corrupt.db");
    output << "not SQLite";
  }
  value = original;
  value["database"]["metadata_path"] = "corrupt.db";
  reject(value);
  value = original;
  value["database"]["metadata_path"] = "missing/metadata.db";
  reject(value);
  {
    std::ofstream output(config);
    output << "{broken";
  }
  ServerProcess malformed(config, temp.path() / "malformed-startup.log");
  EXPECT_GT(malformed.Wait(), 0);
}

TEST_F(ProcessTest, QuarantinedIntentStopsStartupAndPreservesAllCompanions) {
  auto access =
      storage::JamAccess::Open(*catalog, "RU.TEST", true, std::chrono::steady_clock::now() + std::chrono::seconds(1));
  ASSERT_TRUE(access);
  msgapi::JamMessage message;
  message.SetText("unconfirmed");
  auto plan = (*access)->messages().PrepareAppend(message);
  ASSERT_TRUE(plan);
  storage::Operation operation;
  operation.user = "test";
  operation.id = "pending";
  operation.conference = "RU.TEST";
  operation.generation = "foreign";
  operation.ftn_msgid = "2:1/2 pending";
  operation.plan = *plan;
  ASSERT_TRUE(metadata->PrepareOperation(operation));
  access->reset();
  const auto header = test::ReadFile(temp.path() / "file.jhr");
  ServerProcess server(config, temp.path() / "recovery-startup.log");
  EXPECT_GT(server.Wait(), 0);
  EXPECT_EQ(test::ReadFile(temp.path() / "file.jhr"), header);
  EXPECT_EQ(std::filesystem::file_size(temp.path() / "file.jdt"), 0);
  EXPECT_EQ(std::filesystem::file_size(temp.path() / "file.jdx"), 0);
  auto record = metadata->FindOperation("test", "pending");
  ASSERT_TRUE(record);
  ASSERT_TRUE(*record);
  EXPECT_EQ((*record)->state, storage::OperationState::kQuarantine);
}

TEST_F(ProcessTest, RestartAppliesEchoRevocationToExistingSessionAndPreservesReadState) {
  auto stub = wire::Ffido::NewStub(channel);
  auto auth = [&](grpc::ClientContext& context) {
    context.AddMetadata("authorization", "Bearer " + token);
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(5));
  };
  wire::CreateMessageResponse created;
  wire::MessageReference reference;
  reference.set_conference_id("RU.TEST");
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    wire::CreateMessageRequest request;
    request.set_conference_id("RU.TEST");
    request.set_operation_id("before-revoke");
    request.set_subject("Subject");
    request.set_body("Body");
    grpc::ClientContext context;
    auth(context);
    ASSERT_TRUE(stub->CreateMessage(&context, request, &created).ok());
    reference.set_message_id(created.message().message_id());
    grpc::ClientContext read;
    auth(read);
    wire::Message message;
    ASSERT_TRUE(stub->GetMessage(&read, reference, &message).ok());
    kill(process.pid, SIGTERM);
    ASSERT_EQ(process.Wait(), 0);
  }
  const auto original = test::ReadFile(temp.path() / "hpt-auth.cfg");
  auto revoked = original.substr(0, original.find("EchoArea"));
  std::ofstream(temp.path() / "hpt-auth.cfg") << revoked;
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    grpc::ClientContext context;
    auth(context);
    wire::Message message;
    EXPECT_EQ(stub->GetMessage(&context, reference, &message).error_code(), grpc::StatusCode::PERMISSION_DENIED);
    grpc::ClientContext list;
    auth(list);
    wire::ListConferencesRequest request;
    request.set_sort(wire::CONFERENCE_SORT_NAME);
    request.mutable_page()->set_limit(20);
    wire::ListConferencesResponse response;
    const auto status = stub->ListConferences(&list, request, &response);
    ASSERT_TRUE(status.ok()) << status.error_code() << ": " << status.error_message();
    EXPECT_EQ(response.total(), 0);
    EXPECT_EQ(Send("before-revoke").error_code(), grpc::StatusCode::PERMISSION_DENIED);
    kill(process.pid, SIGTERM);
    ASSERT_EQ(process.Wait(), 0);
  }
  std::ofstream(temp.path() / "hpt-auth.cfg") << original;
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    grpc::ClientContext context;
    auth(context);
    wire::GetConferenceRequest request;
    request.set_conference_id("RU.TEST");
    wire::Conference response;
    ASSERT_TRUE(stub->GetConference(&context, request, &response).ok());
    EXPECT_EQ(response.total_count(), 1);
    EXPECT_EQ(response.unread_count(), 0);
    kill(process.pid, SIGTERM);
    ASSERT_EQ(process.Wait(), 0);
  }
}

TEST_F(ProcessTest, OwnPointSessionsSurviveDevicesButNotChangedOrRemovedBossCredentials) {
  auto stub = wire::Ffido::NewStub(channel);
  auto configure = [&](std::string password, bool own = true) {
    std::ofstream(temp.path() / "hpt-auth.cfg")
        << "Name Fixture\nSysop Test\nLocation Test\nAddress " << (own ? "2:1/2.1" : "2:1/1")
        << "\nLink Boss\nAKA 2:1/2\nOurAKA " << (own ? "2:1/2.1" : "2:1/1") << "\nSessionPwd " << password
        << "\nEchoArea RU.TEST " << (temp.path() / "file").string() << " -b JAM 2:1/2\n";
  };
  auto login = [&](std::string password, wire::LoginResponse& response) {
    grpc::ClientContext c;
    c.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(5));
    wire::LoginRequest request;
    request.set_name("Own point");
    request.set_address("2:1/2.1");
    request.set_password(password);
    return stub->Login(&c, request, &response);
  };
  wire::LoginResponse phone, laptop, replacement;
  configure("first-password");
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    ASSERT_TRUE(login("first-password", phone).ok());
    ASSERT_TRUE(login("first-password", laptop).ok());
    EXPECT_EQ(phone.session().profile().user_id(), laptop.session().profile().user_id());
    EXPECT_NE(phone.session_secret(), laptop.session_secret());
    EXPECT_EQ(phone.session().profile().address(), "2:1/2.1");
    EXPECT_NE(phone.session().profile().user_id(), "test");
    token = phone.session_secret();
    ASSERT_TRUE(Send("own-post").ok());
    wire::ListMessagesRequest request;
    request.set_conference_id("RU.TEST");
    request.set_sort(wire::MESSAGE_SORT_DATE_ASCENDING);
    request.mutable_page()->set_limit(20);
    grpc::ClientContext c;
    c.AddMetadata("authorization", "Bearer " + laptop.session_secret());
    wire::ListMessagesResponse messages;
    ASSERT_TRUE(stub->ListMessages(&c, request, &messages).ok());
    ASSERT_EQ(messages.messages_size(), 1);
    EXPECT_EQ(messages.messages(0).from_address(), "2:1/2.1");
    kill(process.pid, SIGTERM);
    ASSERT_EQ(process.Wait(), 0);
  }
  configure("second-password");
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    EXPECT_EQ(Send("revoked-phone").error_code(), grpc::StatusCode::UNAUTHENTICATED);
    token = laptop.session_secret();
    EXPECT_EQ(Send("revoked-laptop").error_code(), grpc::StatusCode::UNAUTHENTICATED);
    EXPECT_EQ(login("first-password", replacement).error_code(), grpc::StatusCode::UNAUTHENTICATED);
    ASSERT_TRUE(login("second-password", replacement).ok());
    EXPECT_EQ(replacement.session().profile().user_id(), phone.session().profile().user_id());
    token = replacement.session_secret();
    kill(process.pid, SIGTERM);
    ASSERT_EQ(process.Wait(), 0);
  }
  configure("second-password", false);
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    EXPECT_EQ(Send("removed-own").error_code(), grpc::StatusCode::UNAUTHENTICATED);
    wire::LoginResponse denied;
    EXPECT_EQ(login("second-password", denied).error_code(), grpc::StatusCode::UNAUTHENTICATED);
    kill(process.pid, SIGTERM);
    ASSERT_EQ(process.Wait(), 0);
  }
}

TEST_F(ProcessTest, PrivateOwnerRpcBoundaryAndRevocationPreserveMetadata) {
  auto settings = nlohmann::json::parse(test::ReadFile(config));
  settings["auth"]["owner_addresses"] = {"2:1/2.1"};
  settings["ftn"]["default_encoding"] = "cp866";
  std::ofstream(config) << settings;
  for (auto name : {"MAIL", "LOCAL", "BAD", "DUPE", "ROBOT"})
    for (auto ext : {".jhr", ".jdt", ".jdx"})
      std::filesystem::copy_file(temp.path() / (std::string("file") + ext), temp.path() / (std::string(name) + ext));
  {
    std::ofstream hpt(temp.path() / "hpt-auth.cfg");
    hpt << "Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/2.1\n"
           "Link Boss\nAKA 2:1/2\nOurAKA 2:1/2.1\nPassword fixture-password\n"
           "Link P1\nAKA 2:1/2.2\nOurAKA 2:1/2.1\nPassword point1\n"
           "Link P2\nAKA 2:1/2.3\nOurAKA 2:1/2.1\nPassword point2\n"
           "EchoArea RU.TEST "
        << (temp.path() / "file").string() << " -b JAM 2:1/2 2:1/2.2 2:1/2.3\n";
    for (auto [keyword, name] : {std::pair{"NetmailArea", "MAIL"},
                                 {"LocalArea", "LOCAL"},
                                 {"BadArea", "BAD"},
                                 {"DupeArea", "DUPE"},
                                 {"NetArea", "ROBOT"}})
      hpt << keyword << " " << name << " " << (temp.path() / name).string() << " -b JAM\n";
    hpt << "RobotsArea ROBOT\nLocalArea OLD " << (temp.path() / "OLD").string() << " -b Squish\n";
  }
  const std::string net = "@ffido/1/6d61696c";
  std::string owner, point1, point2, message_id;
  auto stub = wire::Ffido::NewStub(channel);
  auto authenticate = [&](std::string address, std::string password) {
    grpc::ClientContext context;
    context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(5));
    wire::LoginRequest request;
    request.set_name("Одинаковое имя");
    request.set_address(address);
    request.set_password(password);
    wire::LoginResponse response;
    EXPECT_TRUE(stub->Login(&context, request, &response).ok());
    return response.session_secret();
  };
  auto context = [](const std::string& session) {
    auto result = std::make_unique<grpc::ClientContext>();
    result->AddMetadata("authorization", "Bearer " + session);
    result->set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(5));
    return result;
  };
  auto send = [&](const std::string& session, std::string area, std::string operation) {
    auto call = context(session);
    wire::CreateMessageRequest request;
    request.set_conference_id(area);
    request.set_operation_id(operation);
    request.set_to_name("Николай");
    request.set_to_address("2:1/3.4");
    request.set_subject("Н тема");
    request.set_body("Н текст");
    wire::CreateMessageResponse response;
    auto status = stub->CreateMessage(call.get(), request, &response);
    if (status.ok())
      message_id = response.message().message_id();
    return status;
  };
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    owner = authenticate("2:1/2.1", "fixture-password");
    point1 = authenticate("2:1/2.2", "point1");
    point2 = authenticate("2:1/2.3", "point2");
    ASSERT_TRUE(send(owner, net, "netmail").ok());
    ASSERT_TRUE(send(owner, "@ffido/2/6c6f63616c", "local").ok());
    for (auto id : {"@ffido/3/626164", "@ffido/4/64757065", "@ffido/5/726f626f74"})
      EXPECT_EQ(send(owner, id, "readonly").error_code(), grpc::StatusCode::PERMISSION_DENIED);
    wire::GetConferenceRequest area;
    area.set_conference_id(net);
    wire::MessageReference ref;
    ref.set_conference_id(net);
    ref.set_message_id(message_id);
    wire::PageRequest page;
    page.set_limit(100);
    // Seed personal metadata for all identities to prove filtering, not empty fixtures.
    service::AuthService auth(metadata);
    for (auto [address, session] : {std::pair{"2:1/2.1", owner}, {"2:1/2.2", point1}, {"2:1/2.3", point2}}) {
      auto user = auth.ValidateToken(session);
      ASSERT_TRUE(user);
      ASSERT_TRUE(metadata->AddBookmark(user->id, net));
      ASSERT_TRUE(metadata->RecordMessageView(user->id, {net, "fixture", "42"}));
    }
    for (const auto& session : {point1, point2}) {
      wire::ListConferencesRequest list;
      *list.mutable_page() = page;
      list.set_sort(wire::CONFERENCE_SORT_NAME);
      wire::ListConferencesResponse found;
      auto call = context(session);
      ASSERT_TRUE(stub->ListConferences(call.get(), list, &found).ok());
      EXPECT_EQ(found.total(), 1);
      EXPECT_FALSE(found.has_more());
      EXPECT_EQ(found.conferences(0).id(), "RU.TEST");
      list.set_query("MAIL");
      call = context(session);
      ASSERT_TRUE(stub->ListConferences(call.get(), list, &found).ok());
      EXPECT_EQ(found.total(), 0);
      wire::Conference conference;
      call = context(session);
      EXPECT_EQ(stub->GetConference(call.get(), area, &conference).error_code(), grpc::StatusCode::PERMISSION_DENIED);
      wire::Message message;
      call = context(session);
      EXPECT_EQ(stub->GetMessage(call.get(), ref, &message).error_code(), grpc::StatusCode::PERMISSION_DENIED);
      google::protobuf::Empty empty;
      call = context(session);
      EXPECT_EQ(stub->MarkRead(call.get(), ref, &empty).error_code(), grpc::StatusCode::PERMISSION_DENIED);
      call = context(session);
      EXPECT_EQ(stub->AddBookmark(call.get(), area, &empty).error_code(), grpc::StatusCode::PERMISSION_DENIED);
      call = context(session);
      EXPECT_EQ(stub->RemoveBookmark(call.get(), area, &empty).error_code(), grpc::StatusCode::PERMISSION_DENIED);
      EXPECT_EQ(send(session, net, "forbidden").error_code(), grpc::StatusCode::PERMISSION_DENIED);
      wire::ListBookmarksResponse bookmarks;
      call = context(session);
      ASSERT_TRUE(stub->ListBookmarks(call.get(), page, &bookmarks).ok());
      EXPECT_EQ(bookmarks.total(), 0);
      wire::ListHistoryResponse history;
      call = context(session);
      ASSERT_TRUE(stub->ListHistory(call.get(), page, &history).ok());
      EXPECT_EQ(history.total(), 0);
    }
    auto call = context(owner);
    wire::Conference conference;
    ASSERT_TRUE(stub->GetConference(call.get(), area, &conference).ok());
    EXPECT_EQ(conference.kind(), wire::AREA_KIND_NETMAIL);
    EXPECT_TRUE(conference.statistics_known());
    EXPECT_EQ(conference.total_count(), 1);
    EXPECT_EQ(kill(process.pid, SIGTERM), 0);
    EXPECT_EQ(process.Wait(), 0);
  }
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    ASSERT_TRUE(send(owner, net, "netmail").ok());  // old session, exact retry after restart.
    EXPECT_EQ(test::ReadFile(temp.path() / "MAIL.jdx").size(), 8);
    EXPECT_EQ(kill(process.pid, SIGTERM), 0);
    EXPECT_EQ(process.Wait(), 0);
  }
  settings["auth"]["owner_addresses"] = nlohmann::json::array();
  std::ofstream(config) << settings;
  {
    ServerProcess process(config, temp.path() / "server.log");
    Ready();
    EXPECT_EQ(send(owner, net, "netmail").error_code(), grpc::StatusCode::PERMISSION_DENIED);
    auto call = context(owner);
    wire::GetConferenceRequest request;
    request.set_conference_id(net);
    wire::Conference response;
    EXPECT_EQ(stub->GetConference(call.get(), request, &response).error_code(), grpc::StatusCode::PERMISSION_DENIED);
    service::AuthService auth(metadata);
    auto user = auth.ValidateToken(owner);
    ASSERT_TRUE(user);
    EXPECT_EQ(metadata->GetBookmarks(user->id)->size(), 1);
    EXPECT_EQ(metadata->GetHistory(user->id)->size(), 1);
    EXPECT_EQ(kill(process.pid, SIGTERM), 0);
    EXPECT_EQ(process.Wait(), 0);
  }
}

TEST_F(ProcessTest, MappedHptCatalogStartsAndPublishesKoi8WithoutConfigCopies) {
#ifndef FFIDO_CONFIG_OPEN_ADAPTER
  GTEST_SKIP() << "Configure FFIDO_FIDOCONFIG_SOURCE to test mapped includes";
#endif
  const auto root = temp.path();
  std::ofstream(root / "hpt-auth.cfg") << "Name Fixture\nSysop Test\nLocation Test\nAddress 2:1/1\n"
                                          "Link Client\nAKA 2:1/2\nOurAKA 2:1/1\nPassword fixture-password\n"
                                          "set basedir=\"/ffido-mapped-process\"\nInclude [basedir]/areas.cfg\n";
  std::ofstream(root / "areas.cfg")
      << "EchoAreaDefaults -b JAM\nEchoArea RU.TEST /ffido-mapped-process/file -p 3650 2:1/2\n";
  auto value = nlohmann::json::parse(test::ReadFile(config));
  value["ftn"]["path_mappings"] = nlohmann::json::array({{{"from", "/ffido-mapped-process"}, {"to", root.string()}}});
  value["ftn"]["default_encoding"] = "KOI8-R";
  std::ofstream(config) << value;
  const auto hpt_before = test::ReadFile(root / "hpt-auth.cfg");
  const auto areas_before = test::ReadFile(root / "areas.cfg");
  ServerProcess process(config, root / "server-mapped.log");
  Ready();
  auto client = wire::Ffido::NewStub(channel);
  wire::CreateMessageRequest request;
  request.set_conference_id("RU.TEST");
  request.set_operation_id("mapped-koi8");
  request.set_to_name("All");
  request.set_subject("Тема Ёё");
  request.set_body("Привет Ёё");
  wire::CreateMessageResponse saved;
  grpc::ClientContext context;
  context.AddMetadata("authorization", "Bearer " + token);
  context.set_deadline(std::chrono::system_clock::now() + std::chrono::seconds(5));
  ASSERT_TRUE(client->CreateMessage(&context, request, &saved).ok());
  const auto raw = test::ReadJamWireRecord(root / "file", 0);
  EXPECT_TRUE(raw.HasField(2000, "CHRS: KOI8-R 2"));
  EXPECT_EQ(raw.Field(6), "\xf4\xc5\xcd\xc1 \xb3\xa3");
  EXPECT_EQ(test::ReadFile(root / "hpt-auth.cfg"), hpt_before);
  EXPECT_EQ(test::ReadFile(root / "areas.cfg"), areas_before);
  ASSERT_EQ(kill(process.pid, SIGTERM), 0);
  EXPECT_EQ(process.Wait(), 0);
}
