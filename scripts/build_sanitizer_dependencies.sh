#!/usr/bin/env bash
# Build pinned runtimes together: protobuf's sanitizer layouts differ from release.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-tsan}"
case "$MODE" in
  tsan) flags='-fsanitize=thread -fno-omit-frame-pointer' ;;
  asan-ubsan) flags='-fsanitize=address,undefined -fno-omit-frame-pointer' ;;
  *) echo 'Usage: build_sanitizer_dependencies.sh {tsan|asan-ubsan}' >&2; exit 2 ;;
esac
WORK="${SANITIZER_BUILD_DIR:-$ROOT/build/$MODE-dependencies}"
PREFIX="${SANITIZER_DEPENDENCIES_PREFIX:-$WORK/prefix}"
JOBS="${JOBS:-4}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 2; }
for tool in cmake git python3 nm; do command -v "$tool" >/dev/null || { echo "Required tool not found: $tool" >&2; exit 127; }; done
mkdir -p "$WORK" "$PREFIX"
WORK="$(cd "$WORK" && pwd)"; PREFIX="$(cd "$PREFIX" && pwd)"
if [[ -z "${SANITIZER_OPENSSL_ROOT:-}" ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    command -v brew >/dev/null || { echo 'Set SANITIZER_OPENSSL_ROOT to compatible OpenSSL 3' >&2; exit 2; }
    SANITIZER_OPENSSL_ROOT="$(brew --prefix openssl@3)"
  else SANITIZER_OPENSSL_ROOT=/usr; fi
fi
SSL=''; CRYPTO=''
for directory in lib lib64 lib/x86_64-linux-gnu lib/aarch64-linux-gnu; do
  for suffix in so dylib; do
    if [[ -f "$SANITIZER_OPENSSL_ROOT/$directory/libssl.$suffix" && -f "$SANITIZER_OPENSSL_ROOT/$directory/libcrypto.$suffix" ]]; then
      SSL="$SANITIZER_OPENSSL_ROOT/$directory/libssl.$suffix"; CRYPTO="$SANITIZER_OPENSSL_ROOT/$directory/libcrypto.$suffix"; break 2
    fi
  done
done
[[ -n "$SSL" ]] || { echo 'OpenSSL libraries missing; set SANITIZER_OPENSSL_ROOT' >&2; exit 2; }
if [[ ! -d "$WORK/abseil/.git" ]]; then git clone --depth 1 --branch 20260817.0 https://github.com/abseil/abseil-cpp.git "$WORK/abseil"; fi
if [[ ! -d "$WORK/grpc/.git" ]]; then git clone --depth 1 --branch v1.84.0 https://github.com/grpc/grpc.git "$WORK/grpc"; fi
if [[ ! -d "$WORK/protobuf/.git" ]]; then git clone --depth 1 --branch v36.2 https://github.com/protocolbuffers/protobuf.git "$WORK/protobuf"; fi
git -C "$WORK/abseil" describe --exact-match --tags HEAD | python3 -c 'import sys; assert sys.stdin.read().strip()=="20260817.0"'
git -C "$WORK/grpc" describe --exact-match --tags HEAD | python3 -c 'import sys; assert sys.stdin.read().strip()=="v1.84.0"'
git -C "$WORK/protobuf" describe --exact-match --tags HEAD | python3 -c 'import sys; assert sys.stdin.read().strip()=="v36.2"'
export CMAKE_PREFIX_PATH="$PREFIX:${CMAKE_PREFIX_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"
common=(-DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_CXX_STANDARD=23 -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_RPATH="$PREFIX/lib" -DBUILD_SHARED_LIBS=ON)
cmake -S "$WORK/abseil" -B "$WORK/abseil-build" "${common[@]}" -DABSL_ENABLE_INSTALL=ON -DABSL_BUILD_TESTING=OFF
cmake --build "$WORK/abseil-build" --parallel "$JOBS"
cmake --install "$WORK/abseil-build"
cmake -S "$WORK/protobuf" -B "$WORK/protobuf-build" "${common[@]}" -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_PROTOC_BINARIES=ON -Dprotobuf_LOCAL_DEPENDENCIES_ONLY=ON
cmake --build "$WORK/protobuf-build" --parallel "$JOBS"
cmake --install "$WORK/protobuf-build"
cmake -S "$WORK/grpc" -B "$WORK/grpc-build" "${common[@]}" -DCMAKE_PROJECT_grpc_INCLUDE="$ROOT/scripts/grpc_shared_dependencies.cmake" -DgRPC_BUILD_TESTS=OFF -DgRPC_ABSL_PROVIDER=package -DgRPC_PROTOBUF_PROVIDER=package -DgRPC_CARES_PROVIDER=package -DgRPC_RE2_PROVIDER=package -DgRPC_SSL_PROVIDER=package -DgRPC_ZLIB_PROVIDER=package -DOPENSSL_ROOT_DIR="$SANITIZER_OPENSSL_ROOT" -DOPENSSL_INCLUDE_DIR="$SANITIZER_OPENSSL_ROOT/include" -DOPENSSL_SSL_LIBRARY="$SSL" -DOPENSSL_CRYPTO_LIBRARY="$CRYPTO" -DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF
cmake --build "$WORK/grpc-build" --parallel "$JOBS"
cmake --install "$WORK/grpc-build"
python3 "$ROOT/scripts/sanitizer_cache.py" --mode "$MODE" --prefix "$PREFIX" --openssl-root "$SANITIZER_OPENSSL_ROOT" --ssl "$SSL" --crypto "$CRYPTO"
echo "SANITIZER_DEPENDENCIES_PREFIX=$PREFIX ./build.sh $MODE"
