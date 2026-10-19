#pragma once
#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <vector>
extern char** environ;
namespace fidoback::test {
inline std::string ReadFile(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(input), {}};
}
inline void GenerateTlsCertificate(const std::filesystem::path& directory) {
  std::vector<std::string> arguments{"openssl",  "req",
                                     "-x509",    "-newkey",
                                     "rsa:2048", "-nodes",
                                     "-days",    "1",
                                     "-subj",    "/CN=localhost",
                                     "-addext",  "subjectAltName=DNS:localhost,IP:127.0.0.1",
                                     "-keyout",  (directory / "key.pem").string(),
                                     "-out",     (directory / "certificate.pem").string()};
  std::vector<char*> argv;
  for (auto& argument : arguments)
    argv.push_back(argument.data());
  argv.push_back(nullptr);
  posix_spawn_file_actions_t actions;
  if (posix_spawn_file_actions_init(&actions) != 0)
    throw std::runtime_error("spawn setup");
  posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
  posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
  pid_t pid;
  const int result = posix_spawnp(&pid, "openssl", &actions, nullptr, argv.data(), environ);
  posix_spawn_file_actions_destroy(&actions);
  if (result != 0)
    throw std::runtime_error("openssl unavailable");
  int status;
  if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
    throw std::runtime_error("certificate generation failed");
}
}  // namespace fidoback::test
