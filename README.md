# Node.js for Haiku/arm64 (RenkuOS)

[English](README.md) | [한국어](README.ko.md)

Packaging notes and scripts for a native Node.js 24.21.0 build on Haiku
ARM64. Unlike `golang_bin` or `fastfetch` on this same image, Node's own
build (gyp/ninja, plus running the freshly built `node_mksnapshot` on the
target itself to generate the V8 startup snapshot) has to run natively on
Haiku, not cross-compiled -- this repo is the one real dependency fix that
build needed, the resulting packaging, and the two real bugs found (and
fixed) stress-testing a real Next.js app over SSH, the only way most users
actually reach a packaged binary like this.

Bundles libuv, libbrotlicommon/dec/enc and libcares/libnghttp2 at the
exact versions this Node release needs; openssl3, icu74 and zlib are left
to the base system, which already provides them.

## The one build-time fix: `scripts/cross-arm64-libuv.sh`

A pre-staged libuv on the build image was a version behind what
node-v24.21.0 requires (1.49.2 vs. the 1.52.1 its bundled `deps/uv`
expects): `uv_statfs_s` was missing the renamed `f_frsize` field, and
`uv_thread_setname` didn't exist at all. Fixed by cross-building libuv
straight from Node's own bundled `deps/uv` source (which already carries
its own Haiku port -- `src/unix/haiku.c`, a `CMakeLists.txt` branch for
`CMAKE_SYSTEM_NAME STREQUAL "Haiku"` -- no patching needed), guaranteeing
an exact version match by construction.

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
