#pragma once

#include <unistd.h>

#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <system_error>
#include <vector>

namespace fidoback::test {

class TempDirectory {
public:
  TempDirectory() {
    auto pattern = (std::filesystem::temp_directory_path() / "ffido-test-XXXXXX").string();
    std::vector<char> buffer(pattern.begin(), pattern.end());
    buffer.push_back('\0');
    if (auto* directory = ::mkdtemp(buffer.data())) {
      path_ = directory;
    } else {
      throw std::runtime_error("Cannot create isolated test directory");
    }
  }

  ~TempDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path_, error);
  }

  TempDirectory(const TempDirectory&) = delete;
  TempDirectory& operator=(const TempDirectory&) = delete;

  const std::filesystem::path& path() const {
    return path_;
  }

private:
  std::filesystem::path path_;
};

}  // namespace fidoback::test
