#!/bin/sh
# Cross-build brotlicommon/brotlidec/brotlienc for Haiku arm64, from Node's
# own vendored deps/brotli/c source tree, the same division of labor
# cross-arm64-libuv.sh uses for libuv.
#
# Upstream brotli (github.com/google/brotli) ships a real top-level
# CMakeLists.txt, but Node does not vendor it -- only the c/ source tree
# plus its own brotli.gyp. Node's vendored c/ source has also drifted from
# any tagged upstream brotli release (confirmed: diffing node v24.21.0's
# deps/brotli/c against upstream's own v1.1.0 tag shows real content
# differences in nearly every file, not just the version string -- brotli
# tags releases rarely relative to its own development). So this script
# takes upstream's CMakeLists.txt (unmodified -- it is a plain glob over
# c/common, c/dec, c/enc and reads its own version macros out of
# c/common/version.h, nothing upstream-source-specific) and points it at
# Node's actual vendored c/ tree instead of upstream's, which is the only
# way to get an exact match to what node.cc was really compiled against:
#
#   git clone --depth 1 https://github.com/google/brotli.git brotli-cmake
#   rm -rf brotli-cmake/c
#   cp -r $NODE_SRC/deps/brotli/c brotli-cmake/c
#   docker cp brotli-cmake haiku-builder:/root/brotli-exact
#   docker cp scripts/cross-arm64-brotli.sh haiku-builder:/root/
#   docker exec haiku-builder sh /root/cross-arm64-brotli.sh
#   -> /root/brotlibuild/libbrotli{common,dec,enc}.so.1.*.*
#
# Confirmed building cleanly this way against node v24.21.0's actual
# vendored source, producing libbrotlicommon.so.1.2.0,
# libbrotlidec.so.1.2.0, and libbrotlienc.so.1.2.0 (SONAME libbrotli*.so.1
# for all three, matching the major version the already-shipped
# nodejs_bin-24.21.0-2 package's bundled libs use -- but NOT the same
# patch version: that package's libs are stamped 1.1.0, one version behind
# this exact build. Both are SONAME-compatible (major version 1 either
# way), and 1.1.0 clearly works in practice (it is what node_mksnapshot
# and node itself were actually linked against and run against when that
# package was built and tested) -- but if rebuilding this package from
# scratch rather than reusing its existing staged libs, prefer this
# script's 1.2.0 output: it is what node v24.21.0 actually vendors today,
# by construction, the same "exact version match" reasoning
# cross-arm64-libuv.sh uses for libuv.
set -e
NODE_BROTLI_SRC=${1:-/root/brotli-exact}
W=/root/brotlibuild
rm -rf "$W"
mkdir -p "$W"
cd "$W"
HAIKU_CROSS_BIN=/root/wk/xbin HAIKU_SYSROOT=/root/wk/sysroot cmake "$NODE_BROTLI_SRC" \
	-DCMAKE_TOOLCHAIN_FILE=/root/wk/scripts/haiku-arm64.toolchain.cmake \
	-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
	-DCMAKE_INSTALL_PREFIX=/boot/system
make -j"$(nproc)" brotlicommon brotlidec brotlienc
find . -maxdepth 1 -type f -name 'libbrotli*.so.*' -exec \
	/root/wk/xbin/aarch64-unknown-haiku-strip --strip-unneeded {} \;
ls -la "$W"/libbrotli*.so*
echo "-> $W/libbrotli{common,dec,enc}.so.*"
