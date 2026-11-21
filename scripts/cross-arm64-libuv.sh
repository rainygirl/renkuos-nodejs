#!/bin/sh
# Cross-build libuv for Haiku arm64, from Node.js's own bundled source tree,
# to replace a stale pre-staged libuv under /boot/home/deps/node.
#
# Why from Node's bundled source rather than upstream libuv directly: Node
# is built with node_shared_libuv=true against a pre-staged libuv.so, and an
# earlier staging pass installed libuv 1.49.2 while node-v24.21.0 (and its
# deps/uv/include/uv/version.h) expects 1.52.1. Two concrete breaks from
# that gap: uv_statfs_s was missing the f_frsize field (old layout used
# f_spare[4], same total size, just a renamed slot -- not a real ABI
# change), and uv_thread_setname did not exist in 1.49.2 at all -- a real
# missing symbol, not just a stale header. Building from Node's own
# deps/uv guarantees an exact version match by construction, since that is
# literally the source node.cc was compiled against.
#
# Node's bundled libuv already carries its own Haiku port
# (src/unix/haiku.c, CMakeLists.txt's `if(CMAKE_SYSTEM_NAME STREQUAL
# "Haiku")` block) -- no patching needed, just the same cross CMake
# toolchain this project already uses for fastfetch (see
# cross-arm64-fastfetch.sh).
#
# Usage, from a Haiku arm64 node source checkout (adjust NODE_SRC):
#   docker cp $NODE_SRC/deps/uv haiku-builder:/root/uvbuild-src
#   docker cp scripts/cross-arm64-libuv.sh haiku-builder:/root/
#   docker exec haiku-builder sh /root/cross-arm64-libuv.sh
#   -> /root/uvbuild/build/libuv.so.1.0.0 (soname libuv.so.1, matches the
#      stale one being replaced -- a drop-in binary swap)
#
# After building, this has to replace BOTH copies on the target Haiku
# system, not just the one under ~/deps/node/lib used at compile time:
# Haiku's runtime_loader also needs it findable at RUN time, and whatever
# earlier staging pass installed the deps also dropped a second copy into
# /boot/system/non-packaged/lib (a real loader search path, unlike
# ~/deps/node/lib) -- missing that second copy is why node_mksnapshot kept
# failing with "Troubles relocating: Symbol not found" even after the
# first copy was fixed. Replace both:
#   scp libuv.so.1.0.0 host:/tmp/libuv.so.1.0.0.new
#   ssh host 'cp /tmp/libuv.so.1.0.0.new ~/deps/node/lib/libuv.so.1.0.0 && \
#              cp /tmp/libuv.so.1.0.0.new /boot/system/non-packaged/lib/libuv.so.1.0.0'
# and copy deps/uv/include/uv.h + deps/uv/include/uv/ over
# ~/deps/node/include/uv.h + .../uv/ the same way (headers are compile-time
# only, so they don't need a non-packaged/ copy).
set -e
SRC=${1:-/root/uvbuild-src}
W=/root/uvbuild
rm -rf $W
mkdir -p $W
cp -r $SRC $W/uv
cd $W
mkdir build && cd build
HAIKU_CROSS_BIN=/root/wk/xbin HAIKU_SYSROOT=/root/wk/sysroot cmake ../uv \
	-DCMAKE_TOOLCHAIN_FILE=/root/wk/scripts/haiku-arm64.toolchain.cmake \
	-DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DLIBUV_BUILD_SHARED=ON \
	-DCMAKE_INSTALL_PREFIX=/boot/system
make -j"$(nproc)" uv
/root/wk/xbin/aarch64-unknown-haiku-strip --strip-unneeded libuv.so.1.0.0
/root/wk/xbin/aarch64-unknown-haiku-nm -D libuv.so.1.0.0 | grep -q uv_thread_setname \
	|| { echo "uv_thread_setname still missing -- build is not the expected version" >&2; exit 1; }
ls -la libuv.so.1.0.0
echo "-> $W/build/libuv.so.1.0.0"
