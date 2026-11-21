#!/bin/sh
# Orchestrates the whole nodejs_bin build, end to end, from a plain
# node-v$VER source checkout to a ready-to-install .hpkg. Ties together
# the pieces that previously only existed as separate, manually-run
# commands (or, for three of the four runtime libraries, were never
# scripted at all -- see cross-arm64-brotli.sh/cross-arm64-cares.sh/
# cross-arm64-nghttp2.sh's own headers).
#
# Two different machines are involved, same as every other script here:
#
#   1. The four runtime library cross-builds (cross-arm64-libuv.sh,
#      cross-arm64-brotli.sh, cross-arm64-cares.sh,
#      cross-arm64-nghttp2.sh) run inside haiku-builder, the same Docker
#      cross-build container golang_bin and fastfetch use -- fast, and
#      the only place the cross toolchain + CMake toolchain file live.
#   2. Node's own build (gyp/ninja, and running the freshly built
#      node_mksnapshot on the target itself to generate the V8 startup
#      snapshot) and the final packaging step MUST run natively, on a
#      real RenkuOS arm64 machine -- that is the whole reason this
#      package isn't cross-built like golang_bin. This script's own
#      `./configure && make` call is accordingly the ordinary upstream
#      build, not scripted further here; it is a long step (V8 alone is
#      a lot of C++) and needs the actual target CPU, not emulation.
#
# Usage, on a real (or QEMU, same architecture) RenkuOS arm64 machine,
# from a node-v$VER source checkout:
#
#   NODE_SRC=/path/to/node-v24.21.0 sh build-nodejs-native.sh
#
# Expects the four cross-built libraries already staged under
# $NODE_SRC/../renku-libs (or wherever LIBDIR for
# stage-nodejs-package.sh points) -- run the four cross-arm64-*.sh
# scripts above inside haiku-builder first and copy their output there;
# this script does not reach into Docker itself, since it has to run on
# the native target machine, not wherever the container lives.
#
# Not yet verified end to end as one single run: the four library
# cross-builds above are each individually confirmed (cross-compiled and
# checked against the already-shipped package's own staged libraries --
# see each script's own header for the exact version each produces, and
# where that does or doesn't match what's already staged). The
# `./configure && make` step and the final `stage-nodejs-package.sh` call
# were each separately verified in earlier work on this package (the
# former by the original native build that produced the currently
# published nodejs_bin-24.21.0-2; the latter by re-running
# stage-nodejs-package.sh against that package's own already-built
# files and confirming an identical file tree). What this script adds is
# just the missing glue between those already-proven pieces -- running
# all of it back to back, on a from-scratch checkout, with nothing
# pre-staged, has not itself been done.
set -e
VER=${VER:-24.21.0}
NODE_SRC=${NODE_SRC:?set NODE_SRC to a node-v$VER source checkout}
LIBDIR=${LIBDIR:-$NODE_SRC/../renku-libs}

if [ ! -f "$NODE_SRC/configure" ]; then
	echo "NODE_SRC ($NODE_SRC) doesn't look like a node source checkout" >&2
	exit 1
fi

mkdir -p "$LIBDIR"
missing=""
for lib in libuv.so.1.0.0 libbrotlicommon.so.1.2.0 libbrotlidec.so.1.2.0 \
           libbrotlienc.so.1.2.0 libcares.so.2.19.7 libnghttp2.so.14.29.5; do
	[ -e "$LIBDIR/$lib" ] || missing="$missing $lib"
done
if [ -n "$missing" ]; then
	echo "missing from $LIBDIR, build with the matching cross-arm64-*.sh" \
	     "script in haiku-builder and copy the output here first:$missing" >&2
	exit 1
fi

cd "$NODE_SRC"
./configure
make -j"$(nproc)"

NODE_SRC="$NODE_SRC" LIBDIR="$LIBDIR" \
	sh "$(dirname "$0")/stage-nodejs-package.sh"
