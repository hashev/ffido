#include "service/grpc_runtime.hpp"

#include <grpc/event_engine/event_engine.h>
#include <grpc/grpc.h>

#include <algorithm>
#include <thread>

namespace fidoback::service {
GrpcRuntime::GrpcRuntime() {
  grpc_init();
  try {
    engine_ = grpc_event_engine::experimental::GetDefaultEventEngine();
  } catch (...) {
    grpc_shutdown();
    throw;
  }
}
GrpcRuntime::~GrpcRuntime() {
  if (initialized_)
    grpc_shutdown();
}
bool GrpcRuntime::Shutdown(std::chrono::steady_clock::time_point deadline) {
  if (initialized_) {
    grpc_shutdown();
    initialized_ = false;
  }
  while (grpc_is_initialized() || (engine_ && engine_.use_count() > 1)) {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline)
      return false;
    std::this_thread::sleep_until(std::min(deadline, now + std::chrono::milliseconds(1)));
  }
  // EventEngine destruction joins its workers, including trailing TLS cleanup.
  engine_.reset();
  return true;
}
}  // namespace fidoback::service
