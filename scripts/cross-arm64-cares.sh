#!/bin/sh
# Cross-build c-ares for Haiku arm64, from Node's own vendored deps/cares
# source tree, the same division of labor cross-arm64-libuv.sh uses for
# libuv. Unlike brotli/nghttp2, Node vendors c-ares's real CMakeLists.txt
# unmodified, so this just points it at the cross toolchain directly.
#
#   docker cp $NODE_SRC/deps/cares haiku-builder:/root/cares-src
#   docker cp scripts/cross-arm64-cares.sh haiku-builder:/root/
#   docker exec haiku-builder sh /root/cross-arm64-cares.sh
#   -> /root/caresbuild/lib/libcares.so.2.*.*
#
# Confirmed building cleanly against node v24.21.0's actual vendored
# source (a handful of -Wstringop-overflow notes from GCC about DNS
# record struct field sizes, cosmetic, not errors), producing
# libcares.so.2.19.7 (SONAME libcares.so.2, computed by CMakeLists.txt
# from CARES_LIB_VERSIONINFO "21:7:19" via the standard libtool
# current:revision:age formula). That does NOT match the already-shipped
# nodejs_bin-24.21.0-2 package's bundled libcares.so.2.19.3 -- one
# revision behind this exact build, same kind of drift
# cross-arm64-brotli.sh found and documented for brotli. SONAME-compatible
# either way (major version 2 both times) and 2.19.3 is what that package
# was actually built and tested against, but prefer this script's 2.19.7
# output when rebuilding from scratch: it is the exact version
# CARES_LIB_VERSIONINFO in node v24.21.0's own vendored CMakeLists.txt
# computes, by construction.
set -e
CARES_SRC=${1:-/root/cares-src}
W=/root/caresbuild
rm -rf "$W"
mkdir -p "$W"
cd "$W"
HAIKU_CROSS_BIN=/root/wk/xbin HAIKU_SYSROOT=/root/wk/sysroot cmake "$CARES_SRC" \
	-DCMAKE_TOOLCHAIN_FILE=/root/wk/scripts/haiku-arm64.toolchain.cmake \
	-DCMAKE_BUILD_TYPE=Release -DCARES_STATIC=OFF -DCARES_SHARED=ON \
	-DCARES_BUILD_TESTS=OFF -DCARES_BUILD_TOOLS=OFF \
	-DCMAKE_INSTALL_PREFIX=/boot/system
make -j"$(nproc)"
find lib -maxdepth 1 -type f -name 'libcares.so.*' -exec \
	/root/wk/xbin/aarch64-unknown-haiku-strip --strip-unneeded {} \;
ls -la "$W"/lib/libcares*
echo "-> $W/lib/libcares.so.*"
