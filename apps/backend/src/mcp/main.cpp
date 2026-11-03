#include <iostream>

#include "mcp.hpp"
#include "service/grpc_runtime.hpp"
namespace {
int Run(int argc, char** argv) {
  try {
    const bool login = argc == 3 && std::string_view(argv[1]) == "login";
    if ((!login && argc != 2) || (argc == 3 && !login)) {
      std::cerr << "Usage: ffido-mcp CONFIG | ffido-mcp login CONFIG\n";
      return 2;
    }
    ffido_mcp::Client client(ffido_mcp::LoadConfig(argv[login ? 2 : 1]), login);
    if (login) {
      client.Login();
      return 0;
    }
    return ffido_mcp::Serve(client);
  } catch (const ffido_mcp::Error& error) {
    std::cerr << error.code << ": " << error.what() << '\n';
    return 1;
  } catch (const std::exception&) {
    std::cerr << "MCP operation failed: invalid local configuration or state\n";
    return 1;
  }
}
}  // namespace
int main(int argc, char** argv) {
  try {
    fidoback::service::GrpcRuntime runtime;
    const auto result = Run(argc, argv);
    if (!runtime.Shutdown(std::chrono::steady_clock::now() + std::chrono::seconds(5))) {
      std::cerr << "gRPC cleanup deadline exceeded\n";
      return 1;
    }
    return result;
  } catch (const std::exception&) {
    std::cerr << "MCP runtime unavailable\n";
    return 1;
  }
}
