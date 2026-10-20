#include <grpcpp/grpcpp.h>
#include <pthread.h>
#include <signal.h>
#include <spdlog/spdlog.h>

#include <fstream>
#include <thread>
#include <vector>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

#include "AppConfig.h"
#include "EchoAreaConfig.h"
#include "service/grpc_runtime.hpp"
#include "service/grpc_service.hpp"
#include "service/point_mail.hpp"
#include "storage/jam_writer.hpp"
#include "storage/point_mailbox.hpp"
namespace {
std::expected<std::string, int> Pem(const std::string& path) {
  if (path.empty())
    return std::unexpected(1);
  std::ifstream input(path, std::ios::binary);
  if (!input)
    return std::unexpected(1);
  std::string text;
  char buffer[4096];
  while (input.read(buffer, sizeof(buffer)) || input.gcount()) {
    text.append(buffer, input.gcount());
    if (text.size() > 65536)
      return std::unexpected(1);
  }
  if (!input.eof() || text.empty())
    return std::unexpected(1);
  return text;
}
int RunBackend(int argc, char** argv) {
  std::string path;
  if (argc == 2)
    path = argv[1];
  else if (argc != 1) {
    spdlog::error("Usage: fidoback CONFIG");
    return 2;
  }
  if (path.empty())
    if (const char* env = std::getenv("FIDOBACK_CONFIG"))
      path = env;
  if (path.empty()) {
    spdlog::error("Explicit configuration is required");
    return 2;
  }
  auto config = LoadAppConfig(path);
  if (!config) {
    spdlog::error("Invalid configuration");
    return 1;
  }
  std::filesystem::path binary;
#ifdef __APPLE__
  uint32_t size = 0;
  _NSGetExecutablePath(nullptr, &size);
  std::vector<char> buffer(size);
  if (_NSGetExecutablePath(buffer.data(), &size) == 0)
    binary = buffer.data();
#else
  std::error_code executable_error;
  binary = std::filesystem::read_symlink("/proc/self/exe", executable_error);
#endif
  if (binary.empty()) {
    spdlog::error("Cannot locate HPT authentication helper");
    return 1;
  }
  const auto executable = std::filesystem::absolute(binary).parent_path() / "ffido-hpt-auth";
  auto credentials = fidoback::service::LoadHptConfiguration(executable, *config);
  if (!credentials) {
    spdlog::error("{}", credentials.error().message);
    return 1;
  }
  if (!fidoback::service::ValidatePointMail(*config, *credentials)) {
    spdlog::error("Point mail configuration failed preflight");
    return 1;
  }
  auto session_key = fidoback::service::LoadSessionKey(config->auth.session_key_path);
  if (!session_key) {
    spdlog::error("HPT authentication configuration or session key unavailable");
    return 1;
  }
  auto certificate = Pem(config->server.tls_certificate), key = Pem(config->server.tls_private_key);
  if (!certificate || !key) {
    spdlog::error("TLS certificate and private key are required");
    return 1;
  }
  sigset_t signals;
  sigemptyset(&signals);
  sigaddset(&signals, SIGINT);
  sigaddset(&signals, SIGTERM);
  if (pthread_sigmask(SIG_BLOCK, &signals, nullptr) != 0) {
    spdlog::error("Cannot configure shutdown signals");
    return 1;
  }
  auto instance = fidoback::storage::BackendInstanceLock::Acquire(config->database.metadata_path.string() + ".lock");
  if (!instance) {
    spdlog::error("Backend instance lock unavailable");
    return 1;
  }
  auto metadata = fidoback::storage::CreateSQLiteStore(config->database.metadata_path);
  if (!metadata->Init()) {
    spdlog::error("Metadata initialization failed");
    return 1;
  }
  auto areas = fidoback::service::CatalogAreas(*config, *credentials);
  if (!areas) {
    spdlog::error("Invalid conference configuration");
    return 1;
  }
  auto mailboxes = fidoback::storage::MailboxAreas(config->point_mail, *metadata);
  if (!mailboxes) {
    spdlog::error("Point mailboxes must be explicitly provisioned");
    return 1;
  }
  areas->insert(areas->end(), mailboxes->begin(), mailboxes->end());
  auto coordination = fidoback::storage::CoordinationLock::Open(config->ftn.coordination_lock);
  if (!coordination) {
    spdlog::error("HPT coordination lock is required and must be accessible");
    return 1;
  }
  auto opened = fidoback::storage::JamCatalog::Build(config->ftn.jam_base_path, *areas, *coordination);
  if (!opened) {
    spdlog::error("JAM catalog unavailable");
    return 1;
  }
  auto catalog = std::shared_ptr<fidoback::storage::JamCatalog>(std::move(*opened));
  auto access = fidoback::service::EchoAccess::Build(*credentials, *catalog, config->auth.owner_addresses);
  if (!access) {
    spdlog::error("HPT echo access policy unavailable or inconsistent");
    return 1;
  }
  fidoback::storage::JamWriter recovery(metadata);
  if (!recovery.RecoverAll(*catalog, std::chrono::steady_clock::now() + std::chrono::seconds(5))) {
    spdlog::error("JAM recovery requires administrator attention");
    return 1;
  }
  fidoback::service::GrpcService service(catalog, metadata, *access, config->ftn.default_encoding,
                                         static_cast<int>(config->server.thread_num), config->server.rpc_timeout_ms,
                                         config->uue);
  if (!service.ConfigureAuth(std::move(credentials->credentials), *session_key)) {
    spdlog::error("Authentication initialization failed");
    return 1;
  }
  grpc::SslServerCredentialsOptions tls;
  tls.pem_key_cert_pairs.push_back({*key, *certificate});
  grpc::ServerBuilder builder;
  int port = 0;
  builder.AddListeningPort(config->server.ip + ":" + std::to_string(config->server.port),
                           grpc::SslServerCredentials(tls), &port);
  grpc::ResourceQuota quota;
  quota.Resize(64 * 1024 * 1024).SetMaxThreads(static_cast<int>(config->server.thread_num) + 2);
  builder.SetResourceQuota(quota);
  builder.AddChannelArgument(GRPC_ARG_ALLOW_REUSEPORT, 0);
  builder.SetMaxReceiveMessageSize(2 * 1024 * 1024);
  builder.SetMaxSendMessageSize(4 * 1024 * 1024);
  builder.AddChannelArgument(GRPC_ARG_MAX_METADATA_SIZE, 8192);
  builder.SetSyncServerOption(grpc::ServerBuilder::SyncServerOption::NUM_CQS, 1);
  builder.SetSyncServerOption(grpc::ServerBuilder::SyncServerOption::MAX_POLLERS,
                              static_cast<int>(config->server.thread_num));
  builder.RegisterService(&service);
  auto server = builder.BuildAndStart();
  if (!server || port == 0) {
    spdlog::error("gRPC bind failed");
    return 1;
  }
  spdlog::info("gRPC server ready on port {}", port);
  int signal = 0;
  if (sigwait(&signals, &signal) != 0) {
    server->Shutdown();
    return 1;
  }
  server->Shutdown(std::chrono::system_clock::now() + std::chrono::milliseconds(config->server.shutdown_timeout_ms));
  server->Wait();
  spdlog::info("gRPC server stopped");
  return 0;
}
}  // namespace
int main(int argc, char** argv) {
  fidoback::service::GrpcRuntime runtime;
  const int result = RunBackend(argc, argv);
  if (!runtime.Shutdown(std::chrono::steady_clock::now() + std::chrono::seconds(5))) {
    spdlog::error("gRPC runtime cleanup deadline exceeded");
    return 1;
  }
  return result;
}
