#pragma once

#include <sys/resource.h>
#include <unistd.h>

#include <cstdint>
#include <fstream>
#ifdef __APPLE__
#include <mach/mach.h>
#endif

namespace fidoback::test {
inline uint64_t ResidentBytes() {
#ifdef __APPLE__
  mach_task_basic_info_data_t info{};
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  return task_info(mach_task_self(), MACH_TASK_BASIC_INFO, reinterpret_cast<task_info_t>(&info), &count) == KERN_SUCCESS
             ? info.resident_size
             : 0;
#else
  uint64_t total = 0, resident = 0;
  std::ifstream input("/proc/self/statm");
  return input >> total >> resident ? resident * static_cast<uint64_t>(sysconf(_SC_PAGESIZE)) : 0;
#endif
}
inline uint64_t PeakResidentBytes() {
  rusage usage{};
  if (getrusage(RUSAGE_SELF, &usage) != 0)
    return 0;
#ifdef __APPLE__
  return static_cast<uint64_t>(usage.ru_maxrss);
#else
  return static_cast<uint64_t>(usage.ru_maxrss) * 1024;
#endif
}
}  // namespace fidoback::test
