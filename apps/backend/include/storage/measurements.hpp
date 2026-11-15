#pragma once

#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>

namespace fidoback::measurements {
// Opt-in, numeric-only observation for isolated fixtures. No paths or message data.
// Reset/enable only while the observed process is quiescent; join workers before disabling.
enum Metric {
  sql_executions,
  metadata_wait_ns,
  jam_opens,
  jam_read_bytes,
  jam_mutex_wait_ns,
  jam_file_wait_ns,
  coordination_wait_ns,
  cache_wait_ns,
  cache_hold_ns,
  hash_calls,
  hashed_bytes,
  cache_snapshots,
  payload_copied_bytes,
  slice_copied_bytes,
  reserved_bytes,
  reserved_peak_bytes,
  assembly_bytes,
  assembly_peak_bytes,
  chunk_bytes,
  chunk_peak_bytes,
  protobuf_bytes,
  protobuf_peak_bytes,
  json_models,
  json_peak_models,
  serialized_models,
  serialized_peak_models,
  json_bytes,
  json_peak_bytes,
  serialized_bytes,
  serialized_peak_bytes,
  queued_bytes,
  queued_peak_bytes,
  queued_capacity_bytes,
  queued_capacity_peak_bytes,
  metric_count
};
inline std::array<std::atomic<uint64_t>, metric_count> counters{};
inline std::atomic<bool> enabled{false};
inline void Add(Metric metric, uint64_t value) {
  if (enabled.load(std::memory_order_relaxed))
    counters[metric].fetch_add(value, std::memory_order_relaxed);
}
inline void Gauge(Metric current, Metric peak_metric, uint64_t value) {
  if (!enabled.load(std::memory_order_relaxed))
    return;
  counters[current].store(value, std::memory_order_relaxed);
  auto peak = counters[peak_metric].load(std::memory_order_relaxed);
  while (peak < value && !counters[peak_metric].compare_exchange_weak(peak, value, std::memory_order_relaxed)) {
  }
}
inline void Enable() {
  for (auto& counter : counters)
    counter.store(0, std::memory_order_relaxed);
  enabled.store(true);
}
inline void Disable() {
  enabled.store(false);
}
class Timer {
public:
  explicit Timer(Metric metric) : metric_(metric), active_(enabled.load(std::memory_order_relaxed)) {
    if (active_)
      started_ = std::chrono::steady_clock::now();
  }
  ~Timer() {
    Finish();
  }
  void Finish() {
    if (active_) {
      counters[metric_].fetch_add(static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
                                                            std::chrono::steady_clock::now() - started_)
                                                            .count()),
                                  std::memory_order_relaxed);
      active_ = false;
    }
  }

private:
  Metric metric_;
  bool active_;
  std::chrono::steady_clock::time_point started_;
};
class Bytes {
public:
  Bytes(Metric current, Metric peak, uint64_t bytes = 0)
      : current_(current), peak_(peak), active_(enabled.load(std::memory_order_relaxed)) {
    Grow(bytes);
  }
  ~Bytes() {
    if (active_)
      counters[current_].fetch_sub(bytes_, std::memory_order_relaxed);
  }
  void Grow(uint64_t bytes) {
    if (!active_)
      return;
    bytes_ += bytes;
    const auto live = counters[current_].fetch_add(bytes, std::memory_order_relaxed) + bytes;
    auto peak = counters[peak_].load(std::memory_order_relaxed);
    while (peak < live && !counters[peak_].compare_exchange_weak(peak, live, std::memory_order_relaxed)) {
    }
  }
  Bytes(const Bytes&) = delete;
  Bytes& operator=(const Bytes&) = delete;

private:
  Metric current_, peak_;
  bool active_;
  uint64_t bytes_ = 0;
};
}  // namespace fidoback::measurements
