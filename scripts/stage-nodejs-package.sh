#!/bin/sh
# Package a natively-built Node.js checkout into a RenkuOS arm64 .hpkg.
#
# Node's own build (gyp/ninja, plus running the freshly built
# node_mksnapshot on the target itself) has to run natively on RenkuOS --
# that part is not scripted here, it is the ordinary upstream build:
#
#   ./configure
#   make -j$(nproc)
#
# run from a node-v$VER checkout on a RenkuOS arm64 machine, with
# scripts/cross-arm64-libuv.sh's libuv (and libbrotli{common,dec,enc},
# libcares, libnghttp2 built the same way, from this same checkout's
# deps/ sources, at the versions deps/uv etc. here require) already built
# and staged under $LIBDIR. This script only does the packaging step
# after that: run it ON RenkuOS, from the built checkout.
#
#   NODE_SRC=/path/to/node-v24.21.0 LIBDIR=/path/to/the/four/.so/files \
#     sh scripts/stage-nodejs-package.sh
#   -> /tmp/nodejs-stage/nodejs_bin-$VER-$REV-arm64.hpkg
set -e
VER=24.21.0
REV=${REV:-2}
NODE_SRC=${NODE_SRC:-.}
LIBDIR=${LIBDIR:-./renku-libs}
W=${W:-/tmp/nodejs-stage}

rm -rf "$W"
mkdir -p "$W/root/bin" "$W/root/lib/node" "$W/root/documentation/packages/nodejs_bin"
root=$W/root

cp "$NODE_SRC/out/Release/node" "$root/bin/node-real"
chmod 555 "$root/bin/node-real"

# bin/node, bin/npm and bin/npx are wrappers, not the real binaries: this
# image's icu74 is a bootstrap-only stub, and only the desktop launch
# target's SetupEnvironment points ICU_DATA at the real data file -- any
# Intl use (new Intl.DateTimeFormat, npm's own string-locale-compare)
# crashed or threw under plain SSH sessions without it.
cat > "$root/bin/node" <<'WRAP'
#!/bin/sh
export ICU_DATA=/boot/system/data/icu/74.1
exec /boot/system/bin/node-real "$@"
WRAP
chmod 755 "$root/bin/node"

cat > "$root/bin/npm" <<'WRAP'
#!/bin/sh
export ICU_DATA=/boot/system/data/icu/74.1
exec /boot/system/bin/node-real /boot/system/lib/node/npm/bin/npm-cli.js "$@"
WRAP
chmod 755 "$root/bin/npm"

cat > "$root/bin/npx" <<'WRAP'
#!/bin/sh
export ICU_DATA=/boot/system/data/icu/74.1
exec /boot/system/bin/node-real /boot/system/lib/node/npm/bin/npx-cli.js "$@"
WRAP
chmod 755 "$root/bin/npx"

# Node's own bundled npm CLI, staged as-is (this image's build never set
# node_install_npm, so npm/npx were never wired up at all) -- not rebuilt,
# just copied from this same checkout, test/docs/man trees excluded.
mkdir -p "$root/lib/node/npm"
cp -r "$NODE_SRC/deps/npm/." "$root/lib/node/npm/"
rm -rf "$root/lib/node/npm/test" "$root/lib/node/npm/docs" \
       "$root/lib/node/npm/man" "$root/lib/node/npm/.github"

# The runtime libraries this Node release needs at a version not otherwise
# on this repository: libuv (see cross-arm64-libuv.sh), libbrotli{common,
# dec,enc}, libcares, libnghttp2 -- built the same way, from this same
# checkout's deps/ sources. openssl3, icu74 and zlib are left to the base
# system, which already provides them.
cp -P "$LIBDIR"/lib*.so* "$root/lib/"

cp "$NODE_SRC/LICENSE" "$root/documentation/packages/nodejs_bin/"

cat > "$root/.PackageInfo" <<INFO
name		nodejs_bin
version		$VER-$REV
architecture	arm64
summary		"Node.js JavaScript runtime for Haiku ARM64"
description	"Native Node.js $VER runtime for Haiku ARM64, built from upstream source directly on a RenkuOS arm64 machine (not cross-built -- gyp/ninja/mksnapshot all need to run natively)."
packager	"RENKU <renku@localhost>"
vendor		"RENKU"
copyrights {
	"2009-2026 Node.js contributors"
}
licenses {
	"MIT"
}
provides {
	nodejs_bin = $VER
	cmd:node = $VER
	cmd:npm = $VER
	cmd:npx = $VER
}
requires {
	haiku
}
INFO

( cd "$root" && package create -z zlib -9 "$W/nodejs_bin-$VER-$REV-arm64.hpkg" )
package list "$W/nodejs_bin-$VER-$REV-arm64.hpkg" | head -20
echo "-> $W/nodejs_bin-$VER-$REV-arm64.hpkg"
