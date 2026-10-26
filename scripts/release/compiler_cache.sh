#!/usr/bin/env bash
# Build the pinned compiler-cache tool; no application or system prefix changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/build/compiler-cache-tool"
REVISION="$(python3 "$ROOT/scripts/release/dependency_lock.py" compiler_cache revision)"
VERSION="$(python3 "$ROOT/scripts/release/dependency_lock.py" compiler_cache version)"
if [[ ! -x "$WORK/prefix/bin/ccache" ]] || ! "$WORK/prefix/bin/ccache" --version | head -1 | grep -Fxq "ccache version $VERSION"; then
  rm -rf "$WORK"
  mkdir -p "$WORK/source"
  git -C "$WORK/source" init -q
  git -C "$WORK/source" remote add origin https://github.com/ccache/ccache.git
  git -C "$WORK/source" fetch --depth 1 origin "$REVISION"
  git -C "$WORK/source" checkout --detach FETCH_HEAD
  [[ "$(git -C "$WORK/source" rev-parse HEAD)" == "$REVISION" ]]
  git -C "$WORK/source" tag "v$VERSION" "$REVISION"
  cmake -S "$WORK/source" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$WORK/prefix" -DCCACHE_DEV_MODE=OFF -DDEPS=DOWNLOAD -DDEP_FMT=BUNDLED -DREDIS_STORAGE_BACKEND=OFF -DENABLE_TESTING=OFF -DENABLE_DOCUMENTATION=OFF
  cmake --build "$WORK/build" --parallel 3
  cmake --install "$WORK/build"
fi
"$WORK/prefix/bin/ccache" --version
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$WORK/prefix/bin" >> "$GITHUB_PATH"
fi
