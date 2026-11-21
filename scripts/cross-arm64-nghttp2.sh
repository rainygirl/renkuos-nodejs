#!/bin/sh
# Cross-build nghttp2's core library for Haiku arm64, from Node's own
# vendored deps/nghttp2 source tree, the same division of labor
# cross-arm64-libuv.sh uses for libuv.
#
# Node vendors only lib/ (plus its own nghttp2.gyp), not the project's
# real top-level CMakeLists.txt (lib/CMakeLists.txt alone has no
# PROJECT_VERSION to work from and fails to configure on its own: "No
# VERSION specified for WRITE_BASIC_CONFIG_VERSION_FILE()"). nghttp2's
# own sources under lib/ are plain, portable C with no OS-specific code
# at all (unlike libuv), so -- same reasoning as cross-arm64-brotli.sh --
# this takes upstream's real top-level CMakeLists.txt (unmodified) at the
# exact matching tag and lets it build Node's actual vendored lib/
# source, which upstream's own CMakeLists.txt's add_subdirectory(lib)
# reaches the same way either source copy came from:
#
#   git clone --depth 1 --branch v1.70.0 \
#     https://github.com/nghttp2/nghttp2.git nghttp2-full
#   # optional: rm -rf nghttp2-full/lib; cp -r $NODE_SRC/deps/nghttp2/lib nghttp2-full/lib
#   # (skippable in practice -- node's lib/ and the matching upstream
#   # tag's lib/ were found to already be identical when this was tested,
#   # unlike brotli's much heavier vendoring drift)
#   docker cp nghttp2-full haiku-builder:/root/nghttp2-full
#   docker cp scripts/cross-arm64-nghttp2.sh haiku-builder:/root/
#   docker exec haiku-builder sh /root/cross-arm64-nghttp2.sh
#   -> /root/nghttp2build/lib/libnghttp2.so.14.*.*
#
# ENABLE_LIB_ONLY=ON skips nghttpx/h2load/examples and their much heavier
# dependency list (OpenSSL, libev, libxml2, jansson, ...) entirely --
# Node only needs the core nghttp2 session/HPACK library.
#
# Confirmed building cleanly against node v24.21.0's actual vendored
# lib/ source, producing libnghttp2.so.14.29.5 (SONAME libnghttp2.so.14)
# -- an exact match to one of the two libnghttp2 versions already staged
# on the target image (14.29.5; the other, 14.28.4, is unrelated leftover
# clutter from an earlier package, not something this Node build needs).
set -e
NGHTTP2_SRC=${1:-/root/nghttp2-full}
W=/root/nghttp2build
rm -rf "$W"
mkdir -p "$W"
cd "$W"
HAIKU_CROSS_BIN=/root/wk/xbin HAIKU_SYSROOT=/root/wk/sysroot cmake "$NGHTTP2_SRC" \
	-DCMAKE_TOOLCHAIN_FILE=/root/wk/scripts/haiku-arm64.toolchain.cmake \
	-DCMAKE_BUILD_TYPE=Release -DENABLE_LIB_ONLY=ON -DENABLE_STATIC_LIB=OFF \
	-DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=/boot/system
make -j"$(nproc)" nghttp2
find lib -maxdepth 1 -type f -name 'libnghttp2.so.*' -exec \
	/root/wk/xbin/aarch64-unknown-haiku-strip --strip-unneeded {} \;
ls -la "$W"/lib/libnghttp2*
echo "-> $W/lib/libnghttp2.so.*"
