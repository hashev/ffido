#!/bin/sh
set -eu
PREFIX=/opt/ffido-hpt
mkdir -p /opt/ffido-hpt-src
cd /opt/ffido-hpt-src
export CMAKE_PREFIX_PATH="$PREFIX"
build() {
 name="$1"; ref="$2"; shift 2
 git init -q "$name"
 git -C "$name" remote add origin "https://github.com/huskyproject/$name.git"
 git -C "$name" fetch --depth 1 origin "$ref"
 git -C "$name" checkout --detach FETCH_HEAD
 test "$(git -C "$name" rev-parse HEAD)" = "$ref"
 if [ "$name" = hpt ]; then git -C hpt apply --check /opt/ffido-local/hpt-transport.patch; git -C hpt apply /opt/ffido-local/hpt-transport.patch; fi
 (cd "$name" && cmake -S . -B "../$name-build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_C_FLAGS="-I$PREFIX/include" -DBUILD_SHARED_LIBS=OFF -Dhusky_LIB="$PREFIX/lib/libhusky.a" -Dsmapi_LIB="$PREFIX/lib/libsmapi.a" -Dfidoconfig_LIB="$PREFIX/lib/libfidoconfig.a" -Dareafix_LIB="$PREFIX/lib/libareafix.a" -DMAKEINFO=MAKEINFO-NOTFOUND "$@")
 cmake --build "$name-build" --parallel 2
 cmake --install "$name-build"
}
build huskylib d3c0c1c3b643d7fce45f82d6c8378802e85d9205
build smapi c2fc9ecb0dd1ec8909e9e9709bfdd0031d5b9bf2
build fidoconf 62c963a6f078905660f2c0b3a6929383823190c5
build areafix cd178f92e01d73b39bfc00b4d6359efd543dd990
build hpt c2a91d64cee0e6cd357376d30c9285ee3f9c624f
