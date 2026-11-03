#pragma once
#include <grpcpp/grpcpp.h>

#include <filesystem>
#include <mutex>
#include <nlohmann/json.hpp>
#include <set>
#include <stdexcept>
#include <string>

#include "ffido/v1/ffido.grpc.pb.h"
namespace ffido_mcp {
using Json = nlohmann::json;
namespace wire = ffido::v1;
struct Error : std::runtime_error {
  std::string code;
  bool retryable;
  Error(std::string code_value, std::string message, bool retry = false)
      : std::runtime_error(std::move(message)), code(std::move(code_value)), retryable(retry) {
  }
};
struct Config {
  std::string endpoint, certificate;
  std::filesystem::path session_file, state_dir;
  std::set<std::string> read_areas, post_areas;
};
Config LoadConfig(const std::filesystem::path& path);
std::string ReadSecret(const std::filesystem::path& path);
void SaveSecret(const std::filesystem::path& path, std::string_view text);
void EnsureState(const std::filesystem::path& path);
std::string RandomId();
Json Encode(const google::protobuf::Message& message);
void Decode(const Json& value, google::protobuf::Message& message);
void Check(const grpc::Status& status);
Json Tools();
Json Prompts();
Json Prompt(const std::string& name, const Json& arguments);
struct CallContext {
  std::mutex mutex;
  std::shared_ptr<grpc::ClientContext> current;
  bool cancelled = false;
  std::chrono::system_clock::time_point deadline = std::chrono::system_clock::now() + std::chrono::seconds(5);
  std::shared_ptr<grpc::ClientContext> Next();
  void Cancel();
};
class Client {
public:
  explicit Client(Config config, bool login = false);
  Json Call(const std::string& tool, const Json& arguments, const std::shared_ptr<CallContext>& context);
  void Login();

private:
  Config config_;
  std::unique_ptr<wire::Ffido::Stub> stub_;
  std::string token_;
  std::mutex draft_mutex_;
  void Area(std::string_view id, bool post = false) const;
  void Authorize(grpc::ClientContext& context) const;
};
int Serve(Client& client);
}  // namespace ffido_mcp
