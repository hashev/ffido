set(FFIDO_PROTO_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
set(FFIDO_PROTO ${FFIDO_PROTO_ROOT}/ffido/v1/ffido.proto)
set(FFIDO_GENERATED_ROOT ${CMAKE_CURRENT_BINARY_DIR}/generated)
set(FFIDO_GENERATED
  ${FFIDO_GENERATED_ROOT}/ffido/v1/ffido.pb.cc
  ${FFIDO_GENERATED_ROOT}/ffido/v1/ffido.pb.h
  ${FFIDO_GENERATED_ROOT}/ffido/v1/ffido.grpc.pb.cc
  ${FFIDO_GENERATED_ROOT}/ffido/v1/ffido.grpc.pb.h)

add_custom_command(
  OUTPUT ${FFIDO_GENERATED} ${FFIDO_GENERATED_ROOT}/ffido.descriptor.pb
  COMMAND ${CMAKE_COMMAND} -E make_directory ${FFIDO_GENERATED_ROOT}
  COMMAND protobuf::protoc
    --proto_path=${FFIDO_PROTO_ROOT}
    --cpp_out=${FFIDO_GENERATED_ROOT}
    --grpc_out=${FFIDO_GENERATED_ROOT}
    --plugin=protoc-gen-grpc=$<TARGET_FILE:gRPC::grpc_cpp_plugin>
    --descriptor_set_out=${FFIDO_GENERATED_ROOT}/ffido.descriptor.pb
    --include_imports ${FFIDO_PROTO}
  DEPENDS ${FFIDO_PROTO} protobuf::protoc gRPC::grpc_cpp_plugin
  VERBATIM)

add_library(ffido_contracts STATIC ${FFIDO_GENERATED})
target_include_directories(ffido_contracts PUBLIC ${FFIDO_GENERATED_ROOT})
target_link_libraries(ffido_contracts PUBLIC protobuf::libprotobuf gRPC::grpc++
  PRIVATE ffido_backend_instrumentation)
target_compile_features(ffido_contracts PUBLIC cxx_std_23)

add_executable(ffido_contract_tests tests/test_contract.cpp)
target_link_libraries(ffido_contract_tests PRIVATE
  GTest::gtest_main ffido_contracts ffido_backend_checks)
include(GoogleTest)
gtest_discover_tests(ffido_contract_tests DISCOVERY_TIMEOUT 30)
