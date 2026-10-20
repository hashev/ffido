#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
MODE="${1:-build}"
JOBS="${JOBS:-4}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 2; }
DEFAULT_DIR="build/backend"
case "$MODE" in
  coverage) DEFAULT_DIR=build/backend-coverage ;;
  asan-ubsan) DEFAULT_DIR=build/backend-asan ;;
  tsan) DEFAULT_DIR=build/backend-tsan ;;
esac
BUILD_DIR="${BUILD_DIR:-$DEFAULT_DIR}"
require() { command -v "$1" >/dev/null 2>&1 || { echo "Required tool not found: $1" >&2; exit 127; }; }
configure() {
  require cmake
  cmake -S "$ROOT" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON "$@"
}
build() { cmake --build "$BUILD_DIR" --parallel "$JOBS"; }
test_backend() { require ctest; ctest --test-dir "$BUILD_DIR" --parallel "$JOBS" --output-on-failure; }
frontend() {
  require flutter
  (cd apps/frontend; flutter pub get; flutter analyze --no-pub; flutter test --no-pub)
}
case "$MODE" in
  build) configure; build ;;
  test) configure; build; test_backend; frontend ;;
  check) require python3; python3 scripts/check_cpp.py --build-dir "$BUILD_DIR"; require dart; python3 scripts/check_dart.py --check; tools/proto/generate.sh --check; frontend ;;
  format) require python3; python3 scripts/check_cpp.py --format; require dart; python3 scripts/check_dart.py ;;
  proto) tools/proto/generate.sh ;;
  coverage) require python3; configure -DFIDOBACK_ENABLE_COVERAGE=ON; build; python3 scripts/backend_coverage.py --build-dir "$BUILD_DIR"; require flutter; (cd apps/frontend; flutter pub get); python3 scripts/frontend_coverage.py; python3 scripts/check_coverage.py --backend "$BUILD_DIR/coverage/backend.json" --frontend apps/frontend/coverage/summary.json ;;
  asan-ubsan|tsan)
    [[ -n "${SANITIZER_DEPENDENCIES_PREFIX:-}" && -f "$SANITIZER_DEPENDENCIES_PREFIX/ffido-$MODE-cache.cmake" ]] || {
      echo "Sanitizers need matching protobuf/gRPC/Abseil. Run scripts/build_sanitizer_dependencies.sh $MODE and set SANITIZER_DEPENDENCIES_PREFIX." >&2; exit 2;
    }
    if [[ "$MODE" == tsan ]]; then FLAG=FIDOBACK_ENABLE_TSAN; else FLAG=FIDOBACK_ENABLE_ASAN; fi
    configure -C "$SANITIZER_DEPENDENCIES_PREFIX/ffido-$MODE-cache.cmake" "-D$FLAG=ON"; build; test_backend ;;
  install) configure; build; if [[ -n "${INSTALL_PREFIX:-}" ]]; then cmake --install "$BUILD_DIR" --component ffido --prefix "$INSTALL_PREFIX"; else cmake --install "$BUILD_DIR" --component ffido; fi ;;
  *) echo 'Usage: build.sh {build|test|check|format|proto|coverage|asan-ubsan|tsan|install}' >&2; exit 2 ;;
esac
