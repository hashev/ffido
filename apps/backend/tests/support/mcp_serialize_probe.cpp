#include <cstdlib>
#include <fstream>
#include <thread>

#include "mcp.hpp"
#include "measurements.hpp"
#include "service/grpc_runtime.hpp"

int main(int argc, char** argv) {
  if (argc != 2)
    return 2;
  const auto* ready = std::getenv("FFIDO_TEST_SERIALIZE_READY");
  const auto* release = std::getenv("FFIDO_TEST_SERIALIZE_RELEASE");
  const auto* report = std::getenv("FFIDO_TEST_MEASUREMENTS");
  if ((!ready || !release) && !report)
    return 2;
  struct Report {
    const char* path;
    fidoback::test::RssSampler rss{};
    ~Report() {
      if (path) {
        auto values = fidoback::test::MeasurementValues();
        values["rss"] = rss.Stop();
        std::ofstream output(path);
        output << values.dump() << '\n';
        fidoback::measurements::Disable();
      }
    }
  } observations{report};
  if (report)
    fidoback::measurements::Enable();
  fidoback::service::GrpcRuntime runtime;
  const auto result = [&] {
    ffido_mcp::Client client(ffido_mcp::LoadConfig(argv[1]));
    return ffido_mcp::Serve(client, [&](const ffido_mcp::Json& response) {
      if (!ready || !release || !response.contains("id") || response.at("id") != 3)
        return;
      {
        std::ofstream output(ready);
        output << "ready";
      }
      const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(5);
      while (!std::filesystem::exists(release)) {
        if (std::chrono::steady_clock::now() >= until)
          throw std::runtime_error("Serialization probe watchdog");
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
      }
    });
  }();
  if (!runtime.Shutdown(std::chrono::steady_clock::now() + std::chrono::seconds(5)))
    return 1;
  return result;
}
