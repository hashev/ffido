#pragma once

#include <sys/resource.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <nlohmann/json.hpp>
#include <string>
#include <thread>
#include <vector>

#include "resource_usage.hpp"
#include "storage/measurements.hpp"

namespace fidoback::test {
inline nlohmann::json MeasurementValues() {
  constexpr const char* names[]{"sql_executions",
                                "metadata_wait_ns",
                                "jam_opens",
                                "jam_read_bytes",
                                "jam_mutex_wait_ns",
                                "jam_file_wait_ns",
                                "coordination_wait_ns",
                                "cache_wait_ns",
                                "cache_hold_ns",
                                "hash_calls",
                                "hashed_bytes",
                                "cache_snapshots",
                                "payload_copied_bytes",
                                "slice_copied_bytes",
                                "reserved_bytes",
                                "reserved_peak_bytes",
                                "assembly_bytes",
                                "assembly_peak_bytes",
                                "chunk_bytes",
                                "chunk_peak_bytes",
                                "protobuf_bytes",
                                "protobuf_peak_bytes",
                                "json_models",
                                "json_peak_models",
                                "serialized_models",
                                "serialized_peak_models",
                                "json_bytes",
                                "json_peak_bytes",
                                "serialized_bytes",
                                "serialized_peak_bytes",
                                "queued_bytes",
                                "queued_peak_bytes",
                                "queued_capacity_bytes",
                                "queued_capacity_peak_bytes"};
  static_assert(std::size(names) == measurements::metric_count);
  nlohmann::json result;
  for (size_t i = 0; i < std::size(names); ++i)
    result[names[i]] = measurements::counters[i].load();
  return result;
}
class RssSampler {
public:
  RssSampler()
      : baseline_(ResidentBytes()), peak_(baseline_), worker_([this] {
          while (!done_.load()) {
            peak_.store(std::max(peak_.load(), ResidentBytes()));
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
          }
        }) {
  }
  ~RssSampler() {
    Stop();
  }
  nlohmann::json Stop() {
    done_ = true;
    if (worker_.joinable())
      worker_.join();
    const auto retained = ResidentBytes();
    rusage usage{};
    getrusage(RUSAGE_SELF, &usage);
    return {{"baseline_rss_bytes", baseline_},
            {"sampled_peak_rss_bytes", std::max(peak_.load(), retained)},
            {"retained_rss_bytes", retained},
            {"process_maxrss_native_units", usage.ru_maxrss}};
  }

private:
  uint64_t baseline_;
  std::atomic<uint64_t> peak_;
  std::atomic<bool> done_{false};
  std::thread worker_;
};
inline nlohmann::json Latencies(std::vector<double> samples) {
  std::sort(samples.begin(), samples.end());
  if (samples.empty())
    return {{"samples", 0}};
  return {{"samples", samples.size()},
          {"p50_ms", samples[(samples.size() - 1) / 2]},
          {"p95_ms", samples[static_cast<size_t>(std::ceil(0.95 * samples.size())) - 1]}};
}
inline int BenchmarkOption(const char* name, int fallback) {
  const auto* value = std::getenv(name);
  return value ? std::stoi(value) : fallback;
}
}  // namespace fidoback::test
