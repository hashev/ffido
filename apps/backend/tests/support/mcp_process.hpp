#pragma once
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>
#include <utility>
extern char** environ;
namespace fidoback::test {
class McpProcess {
public:
  explicit McpProcess(const std::string& config) {
    int input[2], output[2];
    if (pipe(input) != 0 || pipe(output) != 0)
      throw std::runtime_error("MCP pipe");
    for (int fd : {input[0], input[1], output[0], output[1]})
      fcntl(fd, F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO);
    char* argv[]{const_cast<char*>(FFIDO_MCP_BINARY), const_cast<char*>(config.c_str()), nullptr};
    const int error = posix_spawn(&pid_, argv[0], &actions, nullptr, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(input[0]);
    close(output[1]);
    if (error) {
      close(input[1]);
      close(output[0]);
      throw std::runtime_error("MCP spawn");
    }
    input_ = input[1];
    output_ = output[0];
  }
  ~McpProcess() {
    if (input_ >= 0)
      close(input_);
    if (pid_ > 0) {
      kill(pid_, SIGTERM);
      waitpid(pid_, nullptr, 0);
    }
    if (output_ >= 0)
      close(output_);
  }
  void Send(const nlohmann::json& value) {
    Raw(value.dump() + "\n");
  }
  void Finish() {
    close(input_);
    input_ = -1;
    int status = 0;
    if (waitpid(pid_, &status, 0) != pid_ || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
      throw std::runtime_error("MCP did not exit cleanly on EOF");
    pid_ = -1;
  }
  void Raw(std::string_view bytes) {
    struct BlockPipeSignal {
      sigset_t blocked{}, original{};
      bool pending = false;
      BlockPipeSignal() {
        sigemptyset(&blocked);
        sigaddset(&blocked, SIGPIPE);
        pthread_sigmask(SIG_BLOCK, &blocked, &original);
        sigset_t signals{};
        sigpending(&signals);
        pending = sigismember(&signals, SIGPIPE) == 1;
      }
      ~BlockPipeSignal() {
        sigset_t signals{};
        sigpending(&signals);
        if (!pending && sigismember(&signals, SIGPIPE) == 1) {
          int received = 0;
          sigwait(&blocked, &received);
        }
        pthread_sigmask(SIG_SETMASK, &original, nullptr);
      }
    } block_signal;

    while (!bytes.empty()) {
      const auto count = write(input_, bytes.data(), bytes.size());
      if (count <= 0)
        throw std::runtime_error("MCP input");
      bytes.remove_prefix(static_cast<size_t>(count));
    }
  }
  nlohmann::json Read() {
    std::string line;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    for (;;) {
      const auto remaining =
          std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
      pollfd descriptor{output_, POLLIN, 0};
      if (remaining <= 0 || poll(&descriptor, 1, static_cast<int>(remaining)) <= 0)
        throw std::runtime_error("MCP response timeout");
      char c;
      if (read(output_, &c, 1) != 1)
        throw std::runtime_error("MCP process closed stdout");
      if (c == '\n')
        break;
      line += c;
      if (line.size() > 512 * 1024)
        throw std::runtime_error("MCP response oversized");
    }
    return nlohmann::json::parse(line);
  }
  void Initialize() {
    Send({{"jsonrpc", "2.0"},
          {"id", 1},
          {"method", "initialize"},
          {"params",
           {{"protocolVersion", "2025-11-25"},
            {"capabilities", nlohmann::json::object()},
            {"clientInfo", {{"name", "test"}, {"version", "1"}}}}}});
    const auto response = Read();
    if (!response.contains("result"))
      throw std::runtime_error("MCP initialization failed");
    Send({{"jsonrpc", "2.0"}, {"method", "notifications/initialized"}});
  }
  nlohmann::json Call(int id, std::string name, nlohmann::json arguments) {
    Send({{"jsonrpc", "2.0"},
          {"id", id},
          {"method", "tools/call"},
          {"params", {{"name", std::move(name)}, {"arguments", std::move(arguments)}}}});
    return Read().at("result");
  }

private:
  pid_t pid_ = -1;
  int input_ = -1, output_ = -1;
};
}  // namespace fidoback::test
