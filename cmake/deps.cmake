include_guard(GLOBAL)

include(FetchContent)

FetchContent_Declare(
  spdlog
  GIT_REPOSITORY https://github.com/gabime/spdlog.git
  GIT_TAG v1.15.3
  GIT_SHALLOW TRUE)

FetchContent_MakeAvailable(spdlog)

FetchContent_Declare(
  nlohmann_json
  GIT_REPOSITORY https://github.com/nlohmann/json.git
  GIT_TAG v3.12.0
  GIT_SHALLOW TRUE)

FetchContent_MakeAvailable(nlohmann_json)

FetchContent_Declare(
  sqlite3
  URL https://www.sqlite.org/2025/sqlite-autoconf-3490100.tar.gz)

FetchContent_MakeAvailable(sqlite3)
add_library(SQLite3 STATIC ${sqlite3_SOURCE_DIR}/sqlite3.c)
# Отдельная директория для заголовков — избегаем конфликта с файлом "version"
target_include_directories(SQLite3 PUBLIC ${CMAKE_CURRENT_LIST_DIR}/../apps/backend/third_party/sqlite3/include)

FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG v1.16.0
  GIT_SHALLOW TRUE)

FetchContent_MakeAvailable(googletest)

# gRPC/protobuf code generators and runtimes are pinned as a compatible set.
find_package(Protobuf 36.2.0 EXACT CONFIG REQUIRED)
find_package(gRPC 1.84.0 EXACT CONFIG REQUIRED)
foreach(required_target protobuf::libprotobuf protobuf::protoc gRPC::grpc++ gRPC::grpc_cpp_plugin)
  if(NOT TARGET ${required_target})
    message(FATAL_ERROR "Missing dependency target: ${required_target}")
  endif()
endforeach()
