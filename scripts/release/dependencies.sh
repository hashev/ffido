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
clone_locked() {
  local name="$1" url ref
  url="$(python3 "$ROOT/scripts/release/dependency_lock.py" native "$name" url)"
  ref="$(python3 "$ROOT/scripts/release/dependency_lock.py" native "$name" revision)"
  clone "$name" "$url" "$ref"
}
# Profile and component keys are verified before any executable cache is used.
python3 "$ROOT/scripts/release/cache_key.py" --describe
rm -rf "$PREFIX"
COMPONENTS="${FFIDO_NATIVE_CACHE:-$WORK/components}"
mkdir -p "$PREFIX" "$COMPONENTS"
export CMAKE_PREFIX_PATH="$PREFIX:${CMAKE_PREFIX_PATH:-}"
common=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_PREFIX="$PREFIX")
if [[ "$(uname -s)" == Darwin ]]; then
  # Keep CMake's implicit system include paths aligned with the selected SDK.
  common+=(-DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)")
fi
build_install() {
  local name="$1"; shift
  local key component stage
  key="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["components"][sys.argv[2]])' "$ROOT/build/native-profile.json" "$name")"
  component="$COMPONENTS/$name"
  if python3 "$ROOT/scripts/release/native_cache.py" verify "$component" "$key"; then
    echo "Native cache hit: $name ($key)"
  else
    echo "Native cache miss: $name ($key); building pinned source"
    rm -rf "$component" "$WORK/$name" "$WORK/$name-build"
    clone_locked "$name"
    if [[ "$name" == grpc ]]; then
      git -C "$WORK/grpc" submodule update --init --depth 1 third_party/grpc-proto
    fi
    stage="$component/payload"
    mkdir -p "$stage/prefix"
    (cd "$WORK/$name"; cmake -S . -B "$WORK/$name-build" "${common[@]}" -DCMAKE_INSTALL_PREFIX="$stage/prefix" "$@")
    cmake --build "$WORK/$name-build" --parallel "$JOBS"
    cmake --install "$WORK/$name-build"
    cp -R "$WORK/$name" "$stage/source"
    python3 "$ROOT/scripts/release/native_cache.py" seal "$component" "$key"
  fi
  python3 "$ROOT/scripts/release/native_cache.py" assemble "$component" "$key" --prefix "$PREFIX" --source "$WORK/$name"
}
build_install abseil -DABSL_ENABLE_INSTALL=ON -DABSL_BUILD_TESTING=OFF
build_install protobuf -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_PROTOC_BINARIES=ON -Dprotobuf_LOCAL_DEPENDENCIES_ONLY=ON
build_install grpc -DgRPC_BUILD_TESTS=OFF -DgRPC_ABSL_PROVIDER=package -DgRPC_PROTOBUF_PROVIDER=package -DgRPC_CARES_PROVIDER=package -DgRPC_RE2_PROVIDER=package -DgRPC_SSL_PROVIDER=package -DgRPC_ZLIB_PROVIDER=package -DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF
for name in huskylib smapi fidoconf areafix hpt; do
  build_install "$name" -DCMAKE_C_FLAGS="-I$PREFIX/include" -Dhusky_LIB="$PREFIX/lib/libhusky.a" -Dsmapi_LIB="$PREFIX/lib/libsmapi.a" -Dfidoconfig_LIB="$PREFIX/lib/libfidoconfig.a" -Dareafix_LIB="$PREFIX/lib/libareafix.a" -DMAKEINFO=MAKEINFO-NOTFOUND
done
python3 "$ROOT/scripts/release/dependency_record.py" "$WORK"
