# Node.js for RenkuOS/arm64

[English](README.md) | [한국어](README.ko.md)

Packaging notes and scripts for a native Node.js 24.21.0 build on RenkuOS
ARM64. Unlike `golang_bin` or `fastfetch` on this same image, Node's own
build (gyp/ninja, plus running the freshly built `node_mksnapshot` on the
target itself to generate the V8 startup snapshot) has to run natively on
RenkuOS, not cross-compiled -- this repo is the one real dependency fix that
build needed, the resulting packaging, and the two real bugs found (and
fixed) stress-testing a real Next.js app over SSH, the only way most users
actually reach a packaged binary like this.

Bundles libuv, libbrotlicommon/dec/enc and libcares/libnghttp2 at the
exact versions this Node release needs; openssl3, icu74 and zlib are left
to the base system, which already provides them.

## Installing the prebuilt package

On a RenkuOS arm64 image, most users never build this at all -- the
packaged binary is published to this project's own pkgman repository:

```sh
pkgman add-repo https://pkgman.rainygirl.com/arm64   # once per system
pkgman install nodejs_bin
```

`scripts/smoke-test-nodejs.sh` is a quick post-install check, run on the
same machine: a basic eval, `Intl` under a non-desktop session, and
`npm`/`npx` actually running -- the exact paths this package's own
revision 2 fixed.

```sh
sh scripts/smoke-test-nodejs.sh
```

## Building and packaging it

Node's own build (gyp/ninja, plus running the freshly built
`node_mksnapshot` on the target itself) is the ordinary upstream build,
run natively on a RenkuOS arm64 machine -- that part isn't scripted here:

```sh
./configure
make -j$(nproc)
```

Four cross-build scripts produce the runtime libraries this release
needs, each from Node's own vendored `deps/` source for an exact version
match by construction: `scripts/cross-arm64-libuv.sh` (the one that
actually needed a real fix, see below), and, newly added,
`scripts/cross-arm64-brotli.sh`, `scripts/cross-arm64-cares.sh`, and
`scripts/cross-arm64-nghttp2.sh` -- all four run inside `haiku-builder`,
the same cross-build container `golang_bin` uses. `scripts/stage-nodejs-
package.sh` then stages the built checkout -- `bin/node-real`, the
`bin/node`/`bin/npm`/`bin/npx` wrappers, the bundled npm CLI, and the
four runtime libraries -- into the installable `.hpkg`, run on the
native build machine:

```sh
NODE_SRC=/path/to/node-v24.21.0 LIBDIR=/path/to/the/four/.so/files \
  sh scripts/stage-nodejs-package.sh
```

`scripts/build-nodejs-native.sh` orchestrates the whole thing -- checks
the four libraries are staged, runs Node's own native `./configure &&
make`, then calls `stage-nodejs-package.sh` -- though running all of it
back to back, on one from-scratch checkout with nothing pre-staged, has
not itself been done; each piece is verified separately (see each
script's own header for exactly what was checked).

Verified structurally against the actual published `nodejs_bin-24.21.0-2`
package: re-running `stage-nodejs-package.sh` against the already-built,
already-staged files it would have produced reproduces the identical
file tree.

## The one build-time fix: `scripts/cross-arm64-libuv.sh`

A pre-staged libuv on the build image was a version behind what
node-v24.21.0 requires (1.49.2 vs. the 1.52.1 its bundled `deps/uv`
expects): `uv_statfs_s` was missing the renamed `f_frsize` field, and
`uv_thread_setname` didn't exist at all. Fixed by cross-building libuv
straight from Node's own bundled `deps/uv` source (which already carries
its own RenkuOS port -- `src/unix/haiku.c`, a `CMakeLists.txt` branch for
`CMAKE_SYSTEM_NAME STREQUAL "Haiku"` -- no patching needed), guaranteeing
an exact version match by construction.

## A version-drift finding in the other three libraries

Building `brotli` and `c-ares` from Node v24.21.0's actual vendored
source (`scripts/cross-arm64-brotli.sh`, `scripts/cross-arm64-cares.sh`)
produces `libbrotli{common,dec,enc}.so.1.2.0` and `libcares.so.2.19.7` --
one patch version *ahead* of what this package's own already-staged
libraries actually are (`1.1.0` and `2.19.3` respectively). Both are
SONAME-compatible either way (major version 1 and 2 respectively, in
both cases), and the staged versions are what this package was actually
built and tested against, so nothing here is broken -- but it means
those two libraries weren't built from an exact version match the way
libuv's fix insists on; a future rebuild should prefer the scripts'
output. `libnghttp2` (`scripts/cross-arm64-nghttp2.sh`) matches exactly
(`14.29.5`).

## Two real bugs, found stress-testing a real Next.js app

**1. `ICU_DATA` was never set outside the desktop launch target.** This
image's `icu74` is a bootstrap-only stub; the real ICU data file lives at
`/boot/system/data/icu/74.1`, and only the desktop launch target's
`SetupEnvironment` pointed `ICU_DATA` there. Any `Intl` use over SSH (`new
Intl.DateTimeFormat`, npm's own string-locale-compare) crashed or threw.
Fixed the same way `golang_bin`'s `bin/go` wrapper fixes its own blank
`GOPROXY`/`GOSUMDB`: `bin/node` is now a wrapper script (`export
ICU_DATA=/boot/system/data/icu/74.1; exec bin/node-real "$@"`), the real
binary moved to `bin/node-real`.

**2. npm/npx were never wired up at all** (`node_install_npm` was false
in the build). `bin/npm`/`bin/npx` are now wrapper scripts over a
packaged copy of Node's own bundled npm CLI (`deps/npm`, test/docs/man
trees excluded), staged at `lib/node/npm`.

## The real Next.js root cause (two earlier, wrong diagnoses corrected)

`next-swc` has no `haiku`/`arm64` native build and never will -- but
Next.js's WASM fallback (`@next/swc-wasm-nodejs`, auto-downloaded on the
first `next build` once `npm`/`npx` are on `PATH`) works correctly and
needs no manual file placement. This was *not* obvious: two earlier
rounds of testing both concluded the WASM fallback itself was broken,
based on the same recurring symptom (`next build` failing with `'import'
and 'export' may appear only with sourceType: module` on every
`app/*.js` file). Confirmed by instrumenting
`node_modules/next/dist/build/swc/index.js` directly: every SWC transform
call during a real build succeeds (`isWasm=true`, valid output) across
100+ modules -- the failure is downstream of SWC entirely.

The actual trigger: `npm init -y` (this npm CLI's default behavior)
writes an explicit `"type": "commonjs"` into `package.json`. Next.js 15's
webpack config handles that differently from a `package.json` with no
`"type"` field at all (the common case for most real Next.js projects,
including ones scaffolded with `create-next-app`) -- with the field
present, webpack parses the SWC-transformed, already-correct app-router
output with the wrong `sourceType` and the build fails. Remove the field
(or never let it get written) and the identical WASM-backed build
succeeds. Confirmed end to end, twice, from `npm init -y` through a real
HTTP 200 from `curl` against `next start`, by deleting the `"type"`
field before building -- no SWC/WASM file placement, postinstall hook, or
package change needed, ever.

## License

MIT.

## AI disclosure

Claude (Anthropic) did this: finding both bugs (including correcting two
of its own earlier, wrong diagnoses of the Next.js issue), the fixes, the
packaging, and the verification, end to end, inside an agentic coding
session. The author steered the session and approved each step; Claude
wrote, built, ran, and debugged essentially all of the code and testing
here.
