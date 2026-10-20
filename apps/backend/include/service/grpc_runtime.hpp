#pragma once

#include <chrono>
#include <memory>

namespace grpc_event_engine::experimental {
class EventEngine;
}
namespace fidoback::service {
class GrpcRuntime {
public:
  GrpcRuntime();
  ~GrpcRuntime();
  GrpcRuntime(const GrpcRuntime&) = delete;
  GrpcRuntime& operator=(const GrpcRuntime&) = delete;
  // Call after application-owned channels, servers and queues are destroyed.
  bool Shutdown(std::chrono::steady_clock::time_point deadline);

private:
  std::shared_ptr<grpc_event_engine::experimental::EventEngine> engine_;
  bool initialized_ = true;
};
}  // namespace fidoback::service
