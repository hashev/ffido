cmake_minimum_required(VERSION 3.11)

project(
  fidoback
  VERSION 0.1.0
  LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT TARGET ffido_backend_checks)
  include(${CMAKE_CURRENT_SOURCE_DIR}/../../cmake/BackendChecks.cmake)
endif()

find_package(Iconv REQUIRED)
find_package(OpenSSL REQUIRED)

set(FFIDO_HUSKY_ROOT "" CACHE PATH "Prefix of the HPT-compatible Husky installation")
find_path(FFIDO_FIDOCONFIG_INCLUDE fidoconf/fidoconf.h HINTS "${FFIDO_HUSKY_ROOT}/include")
find_library(FFIDO_FIDOCONFIG_LIBRARY NAMES fidoconfig HINTS "${FFIDO_HUSKY_ROOT}/lib")
find_library(FFIDO_HUSKY_LIBRARY NAMES husky HINTS "${FFIDO_HUSKY_ROOT}/lib")
if(NOT FFIDO_FIDOCONFIG_INCLUDE OR NOT FFIDO_FIDOCONFIG_LIBRARY OR NOT FFIDO_HUSKY_LIBRARY)
  message(FATAL_ERROR "HPT-compatible libfidoconfig and libhusky are required. Set FFIDO_HUSKY_ROOT to their installation prefix.")
endif()
add_executable(ffido-hpt-auth src/hpt_auth_main.cpp)
target_include_directories(ffido-hpt-auth SYSTEM PRIVATE ${FFIDO_FIDOCONFIG_INCLUDE})
target_link_libraries(ffido-hpt-auth PRIVATE ${FFIDO_FIDOCONFIG_LIBRARY} ${FFIDO_HUSKY_LIBRARY} nlohmann_json::nlohmann_json ffido_backend_checks)

include(${CMAKE_CURRENT_SOURCE_DIR}/../../cmake/FidoConfigAdapter.cmake)

include(${CMAKE_CURRENT_SOURCE_DIR}/../../cmake/deps.cmake)

set(FIDOBACK_LIB_SOURCES
  src/AppConfig.cpp
  src/EchoAreaConfig.cpp
  src/ftn/path_mapping.cpp
  src/ftn/uue.cpp
  src/ftn/uue_metadata.cpp
  src/domain/error.cpp
  src/domain/ftn_address.cpp
  src/storage/sqlite_store.cpp
  src/storage/coordination_lock.cpp
  src/storage/jam_catalog.cpp
  src/storage/jam_lock.cpp
  src/storage/jam_access.cpp
  src/storage/jam_writer.cpp
  src/storage/jam_audit.cpp
  src/storage/point_mailbox.cpp
  src/storage/text_codec.cpp
  src/service/conference_service.cpp
  src/service/message_service.cpp
  src/service/uue_service.cpp
  src/service/auth_service.cpp
  src/service/echo_access.cpp
  src/service/hpt_catalog.cpp
  src/service/hpt_auth.cpp
  src/service/point_mail.cpp
  src/service/mail_addressing.cpp
  src/service/mail_bridge.cpp
  src/service/point_mail_admin.cpp
  src/service/crypto.cpp
  src/service/grpc_service.cpp
  src/service/grpc_runtime.cpp
)

# Библиотека core-кода (без main.cpp) — для линковки с тестами
add_library(fidoback_lib STATIC ${FIDOBACK_LIB_SOURCES})
target_include_directories(fidoback_lib PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(fidoback_lib PUBLIC
  ffido_contracts gRPC::grpc++ spdlog::spdlog nlohmann_json::nlohmann_json
  Iconv::Iconv OpenSSL::Crypto SQLite3 ffido_backend_checks)
target_compile_features(fidoback_lib PUBLIC cxx_std_20)

set(FIDOBACK_SOURCES
  src/main.cpp
)

add_executable(ffido-admin src/admin.cpp)
target_link_libraries(ffido-admin PRIVATE fidoback_lib)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
add_test(NAME UueFixtureOracle COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/support/uue_oracle.py ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/uue)
add_test(NAME JamUtf8Repair COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/test_repair_jam_utf8.py)
add_test(NAME HptWrapper COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/test_hpt_wrapper.py ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/run_hpt.py)
add_test(NAME AdminCommands COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/test_admin.py $<TARGET_FILE:ffido-admin>)
add_test(NAME HptRoutingFixtures COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/support/hpt_routing_fixture.py ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/run_hpt.py)
set_tests_properties(HptRoutingFixtures PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 120)
add_test(NAME PointMailboxProvision COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/support/point_provision_fixture.py $<TARGET_FILE:ffido-admin>)
add_test(NAME PointMailboxCycle COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/support/point_cycle_fixture.py $<TARGET_FILE:ffido-admin> ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/run_hpt.py)
set_tests_properties(PointMailboxCycle PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 120)




add_executable(${PROJECT_NAME} ${FIDOBACK_SOURCES})
add_dependencies(${PROJECT_NAME} ffido-hpt-auth)
target_link_libraries(${PROJECT_NAME} PRIVATE fidoback_lib)
if(APPLE)
  find_library(COREFOUNDATION_LIBRARY CoreFoundation)
  find_library(CFNETWORK_LIBRARY CFNetwork)
  target_link_libraries(${PROJECT_NAME} PRIVATE ${COREFOUNDATION_LIBRARY}
                                                ${CFNETWORK_LIBRARY})
endif()

target_compile_features(${PROJECT_NAME} PRIVATE cxx_std_20)
# --- Tests ---
set(TEST_SOURCES
  tests/unit/test_uue.cpp
  tests/unit/test_crc32.cpp
  tests/unit/test_jam_attributes.cpp
  tests/unit/test_config_parser.cpp
  tests/unit/test_jam_catalog.cpp
  tests/unit/test_jam_lock.cpp
  tests/unit/test_coordination.cpp
  tests/unit/test_sqlite_store.cpp
  tests/unit/test_auth_service.cpp
  tests/unit/test_hpt_auth.cpp
  tests/unit/test_point_mail.cpp
  tests/unit/test_app_config.cpp
  tests/integration/test_jam_write.cpp
  tests/integration/test_jam_recovery.cpp
  tests/integration/test_services.cpp
  tests/integration/test_private_areas.cpp
  tests/integration/test_grpc.cpp
  tests/integration/test_process.cpp
)

# The oracle runs separately so SMAPI macros and its codec cannot share FFIDO's implementation.
find_path(FFIDO_SMAPI_INCLUDE smapi/msgapi.h HINTS "${FFIDO_HUSKY_ROOT}/include")
find_library(FFIDO_SMAPI_LIBRARY NAMES smapi HINTS "${FFIDO_HUSKY_ROOT}/lib")
find_path(FFIDO_SMAPI_VERSION_INCLUDE version.h HINTS "${FFIDO_SMAPI_INCLUDE}/smapi" NO_DEFAULT_PATH)
if(NOT FFIDO_SMAPI_VERSION_INCLUDE)
  message(FATAL_ERROR "SMAPI msgapi.h requires version.h. Set FFIDO_SMAPI_VERSION_INCLUDE to the matching SMAPI headers if the installation omits it.")
endif()
if(NOT FFIDO_SMAPI_INCLUDE OR NOT FFIDO_SMAPI_LIBRARY)
  message(FATAL_ERROR "HPT-compatible SMAPI is required for independent JAM compatibility tests.")
endif()
add_executable(ffido-smapi-oracle tests/support/smapi_oracle.c)
target_include_directories(ffido-smapi-oracle SYSTEM PRIVATE ${FFIDO_SMAPI_INCLUDE} ${FFIDO_SMAPI_VERSION_INCLUDE})
target_link_libraries(ffido-smapi-oracle PRIVATE ${FFIDO_SMAPI_LIBRARY} ${FFIDO_HUSKY_LIBRARY} ffido_backend_checks)

# Exercise an installed, unpatched Husky build as well as the optional adapter.
add_executable(ffido-hpt-auth-unmapped src/hpt_auth_main.cpp)
target_include_directories(ffido-hpt-auth-unmapped SYSTEM PRIVATE ${FFIDO_FIDOCONFIG_INCLUDE})
target_link_libraries(ffido-hpt-auth-unmapped PRIVATE ${FFIDO_FIDOCONFIG_LIBRARY} ${FFIDO_HUSKY_LIBRARY} nlohmann_json::nlohmann_json ffido_backend_checks)

add_executable(fidoback_tests ${TEST_SOURCES})
target_link_libraries(fidoback_tests PRIVATE
  GTest::gtest_main
  GTest::gmock_main
  fidoback_lib
)
target_include_directories(fidoback_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)

target_compile_definitions(fidoback_tests PRIVATE FFIDO_HPT_AUTH_BINARY="$<TARGET_FILE:ffido-hpt-auth>" FFIDO_TEST_BINARY="$<TARGET_FILE:fidoback_tests>" FFIDO_SERVER_BINARY="$<TARGET_FILE:fidoback>" FFIDO_HPT_WRAPPER="${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/run_hpt.py" FFIDO_PYTHON="${Python3_EXECUTABLE}")
target_compile_definitions(fidoback_tests PRIVATE FFIDO_UUE_FIXTURES="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/uue")
target_compile_definitions(fidoback_tests PRIVATE FFIDO_SMAPI_ORACLE_BINARY="$<TARGET_FILE:ffido-smapi-oracle>")
target_compile_definitions(fidoback_tests PRIVATE FFIDO_UNMAPPED_HELPER_BINARY="$<TARGET_FILE:ffido-hpt-auth-unmapped>")
add_dependencies(fidoback_tests fidoback ffido-hpt-auth ffido-hpt-auth-unmapped ffido-smapi-oracle)
if(FFIDO_FIDOCONFIG_SOURCE)
  target_compile_definitions(fidoback_tests PRIVATE FFIDO_CONFIG_OPEN_ADAPTER=1)
  add_test(NAME PointMailboxProvisionMapped COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/support/point_provision_fixture.py $<TARGET_FILE:ffido-admin> --mapped)
  add_test(NAME PointMailboxCycleMapped COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/support/point_cycle_fixture.py $<TARGET_FILE:ffido-admin> ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/run_hpt.py --mapped)
  set_tests_properties(PointMailboxCycleMapped PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 120)
endif()

# Register tests
include(GoogleTest)
gtest_discover_tests(fidoback_tests DISCOVERY_TIMEOUT 30)

option(FIDOBACK_BUILD_FUZZER "Build bounded JAM parser libFuzzer harness" OFF)
if(FIDOBACK_BUILD_FUZZER)
  if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang" OR FIDOBACK_ENABLE_TSAN)
    message(FATAL_ERROR "JAM fuzzing requires Clang and cannot use TSan")
  endif()
  add_executable(jam_parser_fuzz tests/fuzz/jam_parser_fuzz.cpp)
  target_link_libraries(jam_parser_fuzz PRIVATE fidoback_lib)
  target_compile_options(jam_parser_fuzz PRIVATE -fsanitize=fuzzer,address,undefined -fno-omit-frame-pointer)
  target_link_options(jam_parser_fuzz PRIVATE -fsanitize=fuzzer,address,undefined)
endif()

install(TARGETS fidoback ffido-admin ffido-hpt-auth RUNTIME DESTINATION bin COMPONENT ffido)
install(PROGRAMS ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/run_hpt.py DESTINATION bin RENAME ffido-run-hpt COMPONENT ffido)
install(FILES config.example.json DESTINATION share/ffido COMPONENT ffido)

install(PROGRAMS ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/update/ffido-update DESTINATION bin COMPONENT ffido)
install(FILES
  ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/update/common.py
  ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/update/discovery.py
  ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/update/server.py
  ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/update/public_keys.json
  ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/update/requirements.txt
  DESTINATION share/ffido/update COMPONENT ffido)

add_test(NAME UpdateCli COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/test_update_cli.py $<TARGET_FILE:fidoback>)
add_test(NAME ReleaseSchemaCompatibility
  COMMAND ${CMAKE_COMMAND} -E env "FFIDO_E2E_BACKEND=$<TARGET_FILE:fidoback>"
  ${Python3_EXECUTABLE} -m unittest discover
  -s ${CMAKE_CURRENT_SOURCE_DIR}/../../scripts/release -p test_schema_compatibility.py)
set_tests_properties(ReleaseSchemaCompatibility PROPERTIES TIMEOUT 60)
