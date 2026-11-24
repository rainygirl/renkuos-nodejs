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
exact versions this Node release needs; openssl3 and zlib are left to the
base system, which already provides them. Revision 3 builds and statically
links a full ICU (`--with-intl=full-icu`) instead of using the base
system's own `icu74` -- see below.

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

## Revision 3: the first real from-scratch build, and full `Intl`

Revisions 1-2 above were built and packaged from a Node checkout whose V8
port already worked, carried over from earlier sessions. Revision 3 is the
first time the whole pipeline -- V8's own from-scratch Haiku port included
-- was run end to end starting from a clean `node-v24.21.0` checkout, and
that surfaced several real `gyp`/build-system gaps the earlier, already-
patched checkout had simply never hit:

- **GYP's own OS-flavor detection** (`tools/gyp/pylib/gyp/common.py`'s
  `GetFlavorByPlatform()`) had no `haiku` case at all, silently falling
  back to `"linux"` -- which compiled V8's `platform-linux.cc` right
  alongside its own, correct `platform-haiku.cc`. Fixed by adding the one
  missing case (`sys.platform.startswith("haiku") -> "haiku"`).
- **OpenSSL's own arm64 build-config selection**, across nine
  `deps/openssl/*.gypi` files (`openssl[-cl][-fips]_{asm,asm_avx2,no_asm}.gypi`):
  each hardcodes `'target_arch=="arm64" and OS in "linux openharmony"'`
  before falling through to a last-resort `else` branch labeled "Other
  architectures don't use assembly" that actually still includes the
  **x86_64** Linux asm config -- `haiku` matched neither case, fell
  through, and every OpenSSL object compiled with `-m64` and x86 SSE2
  defines on an arm64 target, failing immediately (`cc: error:
  unrecognized command-line option '-m64'`). Fixed by adding `haiku` to
  each arm64/Linux condition, reusing the existing `linux-aarch64` config
  directory unchanged (it's just include paths and preprocessor defines,
  nothing actually Linux-specific).
- **The same `linux-aarch64` config's `openssl_ex_libs_linux-aarch64`
  variable hardcodes `-lm -ldl -pthread`**, in the same nine files --
  `openssl-cli`'s own link step failed with `cannot find -ldl`, since
  Haiku folds `dlopen`/`dlsym` into `libroot.so` and ships no separate
  `libdl` at all. Removed `-ldl`, kept `-lm -pthread`.
- **zlib's `cpu_features.c`** only defines `cpu_check_features()` under an
  explicit allow-list of OS macros (Android/Linux/macOS/Fuchsia/iOS/x86/
  RISC-V) -- none of them Haiku, so the symbol didn't exist at all and
  `deflate.c`/`adler32.c`/`crc32.c` failed to link with `undefined
  reference to 'cpu_check_features'`. Added `ARMV8_OS_HAIKU`
  (`deps/zlib/zlib.gyp`'s `zlib_arm_crc32` target, plus
  `deps/zlib/cpu_features.c` itself) and treated it exactly like
  `ARMV8_OS_MACOS` already is: statically assume the ARMv8.1 `crc32`/
  `pmull` crypto-extension baseline rather than probe for it at runtime,
  correct here for the same reason it's correct on macOS/arm64 -- this
  port runs under `-cpu host` (hvf passthrough) on real Apple Silicon,
  which genuinely has both unconditionally.
- **c-ares's headers were staged one directory level deeper**
  (`include/cares/ares.h`) than `--shared-cares-includes` expects
  (`include/ares.h`) -- a packaging detail in how this port's own library
  staging script laid them out, not a Node or c-ares bug; fixed by also
  copying them up one level.
- **Two missing *unversioned* `.so` symlinks**: Haiku ships only
  exact-versioned shared objects (`libexecinfo.so.1.1`,
  `libicuuc.so.74.1`, ...), never the bare `libfoo.so` symlink a devel
  package normally provides and the linker's `-lfoo` actually searches
  for. Both had to be added by hand into the same custom library
  directory the four bundled runtimes above already live in.
- **`Intl`/ICU, the long way round.** `--with-intl=system-icu` builds
  against this image's live `icu74` via `pkg-config` -- except no
  `pkg-config`/`pkgconf` binary exists on this image at all, needing a
  four-line shim script answering just the two queries (`icu-i18n`,
  `icu-uc`) Node's configure actually makes. With that shimmed in, the
  build succeeded, but `new Intl.DateTimeFormat(...).format(...)`
  OOM-crashed inside ICU's own `DateTimePatternGeneratorCache`: this
  image's `/boot/system/lib/libicudata.so.74.1` turned out to be a
  132 KB bootstrap-only stub, nowhere near enough locale data for actual
  date-pattern generation. Rather than chase that further, switched to
  `--with-intl=full-icu` instead: Node's own bundled `deps/icu-small`
  turns out to already *be* a full ICU snapshot despite its directory
  name (`README-FULL-ICU.txt` confirms it), so this avoids any dependency
  on the system's own ICU at all. The one remaining hurdle there:
  `configure.py` decompresses a bundled `icudt78l.dat.bz2` through
  Python's `bz2` module, and this image has no `libbz2` either (the same
  gap already hit building V8 itself, worked around there with a stub
  `bz2` module) -- this time, decompressed the file once, out of band,
  with a real `bzip2` binary (the Linux cross-build container already
  has one) and placed the plain `.dat` file exactly where `configure.py`
  looks for it, so it's never asked to decompress anything itself. (In
  passing: the base system separately keeps a full, real 30 MB
  `icudt74l.dat` at `/boot/system/data/icu/74.1` -- the same path
  revision 2's own `ICU_DATA` wrapper already points at for the system's
  *own* apps. A `system-icu` build pointed at that file via `ICU_DATA` at
  runtime might well have worked too, and cheaper than rebuilding ICU
  from source -- not tried here, since `full-icu` already got there
  first and is the more self-contained result either way: no runtime
  dependency on that path continuing to exist.)

None of this is specific to this one build -- it's this port's own
`gyp`/library-staging gaps, fixed once in the source tree and scripts
rather than worked around per-build. The in-progress build itself was
also moved, mid-build, from one Mac to a second, faster one: tarring up
the guest's `node-v$VER` build directory (ninja's own incremental state
included) and the base-OS disk image separately, and resuming the exact
same `ninja` invocation on the new host picked up exactly where it left
off.

Revision 3's `bin/node-real` is about 112 MB (up from rev 2's ~73 MB),
entirely from the statically-linked full ICU data; the external runtime
dependency set (libuv/libbrotli\*/libcares/libnghttp2) is unchanged.
Verified the same way revision 2 was -- a real package swap plus a clean
reboot, not just running the freshly built binary from the build
directory -- with `scripts/smoke-test-nodejs.sh` passing in full,
`Intl.DateTimeFormat` included.

## License

MIT.

## AI disclosure

Claude (Anthropic) did this: finding both bugs (including correcting two
of its own earlier, wrong diagnoses of the Next.js issue), the fixes, the
packaging, and the verification, end to end, inside an agentic coding
session. Revision 3's from-scratch build-system fixes (OpenSSL, zlib,
GYP's OS detection, full ICU) and the mid-build machine migration were
done the same way, in a later session. The author steered each session
and approved each step; Claude wrote, built, ran, and debugged essentially
all of the code and testing here.
