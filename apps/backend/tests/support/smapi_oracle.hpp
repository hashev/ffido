#pragma once

#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>

#include <nlohmann/json.hpp>
#include <stdexcept>
#include <vector>

#include "temp_directory.hpp"
#include "tls_certificate.hpp"

namespace fidoback::test {
inline nlohmann::json SmapiOracle(std::vector<std::string> arguments) {
  TempDirectory capture;
  arguments.insert(arguments.begin(), FFIDO_SMAPI_ORACLE_BINARY);
  std::vector<char*> pointers;
  for (auto& argument : arguments)
    pointers.push_back(argument.data());
  pointers.push_back(nullptr);
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  const auto output = capture.path() / "output.json";
  posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, output.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
  pid_t child = -1;
  const int error = posix_spawn(&child, arguments.front().c_str(), &actions, nullptr, pointers.data(), environ);
  posix_spawn_file_actions_destroy(&actions);
  if (error != 0)
    throw std::runtime_error("Cannot launch independent SMAPI oracle");
  int status = 0;
  if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
    throw std::runtime_error("Independent SMAPI oracle failed: " + std::to_string(status));
  const auto text = ReadFile(output);
  return text.empty() ? nlohmann::json::object() : nlohmann::json::parse(text);
}
}  // namespace fidoback::test
