#pragma once

#include <chrono>
#include <cstdint>
#include <utility>

namespace fidoback::storage {
// Opt-in, thread-local observations for isolated workloads. Counters do not
// estimate RSS or physical disk traffic; read_bytes counts successful pread bytes.
struct WorkMetrics {
  uint64_t jam_opens = 0, read_calls = 0, read_bytes = 0;
  uint64_t jam_mutex_wait_ns = 0, jam_byte_lock_wait_ns = 0;
  uint64_t hash_calls = 0, hash_bytes = 0, payload_copy_bytes = 0, cache_hold_ns = 0;
};
inline thread_local WorkMetrics* work_metrics = nullptr;
class WorkScope {
public:
  explicit WorkScope(WorkMetrics& metrics) : previous_(std::exchange(work_metrics, &metrics)) {
  }
  ~WorkScope() {
    work_metrics = previous_;
  }
  WorkScope(const WorkScope&) = delete;
  WorkScope& operator=(const WorkScope&) = delete;

private:
  WorkMetrics* previous_;
};
class WorkTimer {
public:
  explicit WorkTimer(uint64_t WorkMetrics::* field) : metrics_(work_metrics), field_(field) {
    if (metrics_)
      start_ = std::chrono::steady_clock::now();
  }
  ~WorkTimer() {
    Stop();
  }
  void Stop() {
    if (metrics_) {
      metrics_->*field_ += static_cast<uint64_t>(
          std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - start_).count());
      metrics_ = nullptr;
    }
  }
  WorkTimer(const WorkTimer&) = delete;
  WorkTimer& operator=(const WorkTimer&) = delete;

private:
  WorkMetrics* metrics_;
  uint64_t WorkMetrics::* field_;
  std::chrono::steady_clock::time_point start_;
};
}  // namespace fidoback::storage
