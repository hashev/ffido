#pragma once
#include <algorithm>
#include <condition_variable>
#include <mutex>

#include "storage/jam_lock.hpp"
namespace fidoback::service {
struct RequestBudget {
  storage::JamDeadline deadline;
  std::stop_token cancellation;
};
inline thread_local const RequestBudget* current_budget = nullptr;
class RequestScope {
public:
  explicit RequestScope(const RequestBudget& budget) : previous_(current_budget) {
    current_budget = &budget;
  }
  ~RequestScope() {
    current_budget = previous_;
  }
  RequestScope(const RequestScope&) = delete;
  RequestScope& operator=(const RequestScope&) = delete;

private:
  const RequestBudget* previous_;
};
inline storage::JamDeadline RequestDeadline() {
  return current_budget ? current_budget->deadline : std::chrono::steady_clock::now() + std::chrono::seconds(5);
}
inline std::stop_token RequestCancellation() {
  return current_budget ? current_budget->cancellation : std::stop_token{};
}
inline bool RequestActive() {
  return !current_budget || (!current_budget->cancellation.stop_requested() &&
                             std::chrono::steady_clock::now() < current_budget->deadline);
}
inline bool AcquireRequestLock(std::unique_lock<std::timed_mutex>& lock) {
  const auto deadline = RequestDeadline();
  const auto cancellation = RequestCancellation();
  std::mutex mutex;
  std::condition_variable wake;
  std::stop_callback cancelled(cancellation, [&] { wake.notify_all(); });
  for (;;) {
    const auto now = std::chrono::steady_clock::now();
    if (cancellation.stop_requested() || now >= deadline)
      return false;
    if (lock.try_lock()) {
      if (!cancellation.stop_requested() && std::chrono::steady_clock::now() < deadline)
        return true;
      lock.unlock();
      return false;
    }
    std::unique_lock wait(mutex);
    wake.wait_until(wait, std::min(deadline, now + std::chrono::milliseconds(10)),
                    [&] { return cancellation.stop_requested(); });
  }
}
}  // namespace fidoback::service
