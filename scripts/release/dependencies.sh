#!/usr/bin/env bash
# Native release dependencies; never install into a system prefix.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${FFIDO_DEPS_WORK:-$ROOT/build/release-deps}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
PREFIX="$WORK/prefix"
JOBS="${JOBS:-4}"
if [[ "$(uname -s)" == Darwin ]]; then
  export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || exit 2
clone() {
  local name="$1" url="$2" ref="$3"
  if [[ ! -d "$WORK/$name/.git" ]]; then
    git init -q "$WORK/$name"
    git -C "$WORK/$name" remote add origin "$url"
    git -C "$WORK/$name" fetch --depth 1 origin "$ref"
    git -C "$WORK/$name" checkout --detach FETCH_HEAD
    printf '%s\n' "$ref" > "$WORK/$name/.git/ffido-pinned-ref"
  fi
  [[ "$(git -C "$WORK/$name" rev-parse HEAD)" == "$ref" ]] || { echo "Wrong dependency revision: $name" >&2; exit 1; }
  git -C "$WORK/$name" diff --exit-code --quiet
}
clone abseil https://github.com/abseil/abseil-cpp.git 2065f4ded0558c6f89fee67c8e5228feb4eb960e
clone protobuf https://github.com/protocolbuffers/protobuf.git 2c74169b34066ceb8ddb6b882fcb3fb32d737a55
clone grpc https://github.com/grpc/grpc.git 3252a89f10d8e92997862167ca7d095ecda85973
git -C "$WORK/grpc" submodule update --init --depth 1 third_party/grpc-proto
export CMAKE_PREFIX_PATH="$PREFIX:${CMAKE_PREFIX_PATH:-}"
common=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_PREFIX="$PREFIX")
build_install() {
  local name="$1"; shift
  (cd "$WORK/$name"; cmake -S . -B "$WORK/$name-build" "${common[@]}" "$@")
  cmake --build "$WORK/$name-build" --parallel "$JOBS"
  cmake --install "$WORK/$name-build"
}
build_install abseil -DABSL_ENABLE_INSTALL=ON -DABSL_BUILD_TESTING=OFF
build_install protobuf -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_PROTOC_BINARIES=ON -Dprotobuf_LOCAL_DEPENDENCIES_ONLY=ON
build_install grpc -DgRPC_BUILD_TESTS=OFF -DgRPC_ABSL_PROVIDER=package -DgRPC_PROTOBUF_PROVIDER=package -DgRPC_CARES_PROVIDER=package -DgRPC_RE2_PROVIDER=package -DgRPC_SSL_PROVIDER=package -DgRPC_ZLIB_PROVIDER=package -DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF
clone huskylib https://github.com/huskyproject/huskylib.git d3c0c1c3b643d7fce45f82d6c8378802e85d9205
clone smapi https://github.com/huskyproject/smapi.git c2fc9ecb0dd1ec8909e9e9709bfdd0031d5b9bf2
clone fidoconf https://github.com/huskyproject/fidoconf.git 62c963a6f078905660f2c0b3a6929383823190c5
clone areafix https://github.com/huskyproject/areafix.git cd178f92e01d73b39bfc00b4d6359efd543dd990
clone hpt https://github.com/huskyproject/hpt.git c2a91d64cee0e6cd357376d30c9285ee3f9c624f
for name in huskylib smapi fidoconf areafix hpt; do
  build_install "$name" -DCMAKE_C_FLAGS="-I$PREFIX/include" -Dhusky_LIB="$PREFIX/lib/libhusky.a" -Dsmapi_LIB="$PREFIX/lib/libsmapi.a" -Dfidoconfig_LIB="$PREFIX/lib/libfidoconfig.a" -Dareafix_LIB="$PREFIX/lib/libareafix.a" -DMAKEINFO=MAKEINFO-NOTFOUND
done
python3 "$ROOT/scripts/release/dependency_record.py" "$WORK"
