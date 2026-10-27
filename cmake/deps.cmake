include_guard(GLOBAL)

include(FetchContent)
file(READ "${CMAKE_CURRENT_LIST_DIR}/../scripts/release/dependencies.lock.json" FFIDO_DEPENDENCY_LOCK)
function(ffido_locked output name field)
  string(JSON value GET "${FFIDO_DEPENDENCY_LOCK}" cmake "${name}" "${field}")
  set(${output} "${value}" PARENT_SCOPE)
endfunction()
ffido_locked(FFIDO_SQLITE_URL sqlite3 url)
ffido_locked(FFIDO_PROTOBUF_VERSION protobuf version)
ffido_locked(FFIDO_GRPC_VERSION grpc version)

ffido_locked(FFIDO_SPDLOG_URL spdlog url)
ffido_locked(FFIDO_SPDLOG_SHA256 spdlog sha256)
FetchContent_Declare(
  spdlog
  URL ${FFIDO_SPDLOG_URL}
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  URL_HASH SHA256=${FFIDO_SPDLOG_SHA256})

FetchContent_MakeAvailable(spdlog)

ffido_locked(FFIDO_JSON_URL nlohmann_json url)
ffido_locked(FFIDO_JSON_SHA256 nlohmann_json sha256)
FetchContent_Declare(
  nlohmann_json
  URL ${FFIDO_JSON_URL}
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  URL_HASH SHA256=${FFIDO_JSON_SHA256})

FetchContent_MakeAvailable(nlohmann_json)

ffido_locked(FFIDO_SQLITE_SHA256 sqlite3 sha256)
FetchContent_Declare(
  sqlite3
  URL ${FFIDO_SQLITE_URL}
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  URL_HASH SHA256=${FFIDO_SQLITE_SHA256})

FetchContent_MakeAvailable(sqlite3)
add_library(SQLite3 STATIC ${sqlite3_SOURCE_DIR}/sqlite3.c)
# Отдельная директория для заголовков — избегаем конфликта с файлом "version"
target_include_directories(SQLite3 PUBLIC ${CMAKE_CURRENT_LIST_DIR}/../apps/backend/third_party/sqlite3/include)

ffido_locked(FFIDO_GTEST_URL googletest url)
ffido_locked(FFIDO_GTEST_SHA256 googletest sha256)
FetchContent_Declare(
  googletest
  URL ${FFIDO_GTEST_URL}
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  URL_HASH SHA256=${FFIDO_GTEST_SHA256})

FetchContent_MakeAvailable(googletest)

# gRPC/protobuf code generators and runtimes are pinned as a compatible set.
find_package(Protobuf ${FFIDO_PROTOBUF_VERSION} EXACT CONFIG REQUIRED)
find_package(gRPC ${FFIDO_GRPC_VERSION} EXACT CONFIG REQUIRED)
foreach(required_target protobuf::libprotobuf protobuf::protoc gRPC::grpc++ gRPC::grpc_cpp_plugin)
  if(NOT TARGET ${required_target})
    message(FATAL_ERROR "Missing dependency target: ${required_target}")
  endif()
endforeach()
