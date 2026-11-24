# RenkuOS/arm64용 Node.js

[English](README.md) | [한국어](README.ko.md)

RenkuOS ARM64에서 네이티브로 빌드한 Node.js 24.21.0에 대한 패키징 노트와
스크립트입니다. 같은 이미지의 `golang_bin`이나 `fastfetch`와 달리, Node
자신의 빌드(gyp/ninja, 그리고 V8 시작 스냅샷을 만들기 위해 방금 빌드한
`node_mksnapshot`을 타깃 자체에서 실행하는 과정)는 교차 컴파일이 아니라
RenkuOS 위에서 네이티브로 돌아가야 합니다 — 이 저장소는 그 빌드에 실제로
필요했던 유일한 의존성 수정, 그 결과물의 패키징, 그리고 실제 Next.js
앱을 SSH로 스트레스 테스트하며 찾아서 고친 두 가지 실제 버그를 담고
있습니다. 대부분의 사용자가 패키징된 바이너리에 실제로 닿는 경로가 바로
이거라서 택한 테스트 방식입니다.

libuv, libbrotlicommon/dec/enc, libcares/libnghttp2는 이 Node 릴리스가
필요로 하는 정확한 버전으로 함께 패키징했습니다. openssl3와 zlib은
베이스 시스템이 이미 제공하므로 그대로 둡니다. revision 3부터는 베이스
시스템의 `icu74` 대신 완전한 ICU를 직접 빌드해서 정적으로 링크합니다
(`--with-intl=full-icu`) — 아래 참고.

## 미리 빌드된 패키지 설치

RenkuOS arm64 이미지에서는 대부분 직접 빌드할 필요가 없습니다 — 패키징된
바이너리는 이 프로젝트 자체의 pkgman 저장소에 배포되어 있습니다:

```sh
pkgman add-repo https://pkgman.rainygirl.com/arm64   # 시스템당 한 번만
pkgman install nodejs_bin
```

`scripts/smoke-test-nodejs.sh`는 같은 머신에서 돌리는 간단한 설치 후
점검입니다 — 기본 eval, 데스크탑 세션이 아닌 곳에서의 `Intl`, 그리고
`npm`/`npx`가 실제로 동작하는지까지, 이 패키지의 revision 2가 고친 바로
그 경로들입니다.

```sh
sh scripts/smoke-test-nodejs.sh
```

## 빌드하고 패키징하기

Node 자신의 빌드(gyp/ninja, 그리고 방금 빌드한 `node_mksnapshot`을 타깃
자체에서 실행하는 과정)는 RenkuOS arm64 머신 위에서 네이티브로 돌리는
보통의 업스트림 빌드입니다 — 이 부분은 스크립트화되어 있지 않습니다:

```sh
./configure
make -j$(nproc)
```

이 릴리스가 필요로 하는 런타임 라이브러리를 만드는 교차 빌드 스크립트가
네 개 있고, 각각 Node 자신이 번들한 `deps/` 소스로부터 빌드해서 구조적으로
정확한 버전 일치를 보장합니다: `scripts/cross-arm64-libuv.sh`(실제로 고쳐야
했던 것, 아래 설명), 그리고 새로 추가된 `scripts/cross-arm64-brotli.sh`,
`scripts/cross-arm64-cares.sh`, `scripts/cross-arm64-nghttp2.sh` — 넷 다
`golang_bin`이 쓰는 것과 같은 교차 빌드 컨테이너 `haiku-builder` 안에서
실행합니다. 그다음 `scripts/stage-nodejs-package.sh`가 빌드된 체크아웃 —
`bin/node-real`, `bin/node`/`bin/npm`/`bin/npx` 래퍼, 번들된 npm CLI, 네 개의
런타임 라이브러리 — 을 설치 가능한 `.hpkg`로 패키징합니다. 네이티브 빌드
머신에서 실행합니다:

```sh
NODE_SRC=/path/to/node-v24.21.0 LIBDIR=/path/to/the/four/.so/files \
  sh scripts/stage-nodejs-package.sh
```

`scripts/build-nodejs-native.sh`가 전체 과정을 엮습니다 — 네 라이브러리가
스테이징됐는지 확인하고, Node 자신의 네이티브 `./configure && make`를
돌린 뒤, `stage-nodejs-package.sh`를 호출합니다 — 다만 아무것도 미리
준비되지 않은 처음부터의 체크아웃으로 전체를 한 번에 끝까지 돌려본 적은
아직 없습니다. 각 조각은 따로따로 검증돼 있습니다(정확히 무엇을
확인했는지는 각 스크립트 자신의 헤더 참고).

실제 배포된 `nodejs_bin-24.21.0-2` 패키지와 구조적으로 대조해
검증했습니다: 이미 빌드되고 스테이징된 파일들로
`stage-nodejs-package.sh`를 다시 돌려보면 동일한 파일 트리가 그대로
재현됩니다.

## 빌드 시점의 유일한 수정: `scripts/cross-arm64-libuv.sh`

빌드 이미지에 미리 올려져 있던 libuv가 node-v24.21.0이 요구하는 버전보다
한 단계 낮았습니다(번들된 `deps/uv`가 요구하는 1.52.1 대신 1.49.2) —
`uv_statfs_s`에는 이름이 바뀐 `f_frsize` 필드가 없었고, `uv_thread_setname`은
아예 존재하지 않았습니다. Node 자신이 번들한 `deps/uv` 소스(이미 자체
RenkuOS 포트를 갖고 있음 — `src/unix/haiku.c`, `CMakeLists.txt`의
`CMAKE_SYSTEM_NAME STREQUAL "Haiku"` 분기 — 패치 불필요)로 직접 교차
빌드해서, 구조적으로 정확한 버전 일치를 보장하도록 고쳤습니다.

## 나머지 세 라이브러리에서 발견한 버전 드리프트

Node v24.21.0이 실제로 번들한 소스로 `brotli`와 `c-ares`를 빌드하면
(`scripts/cross-arm64-brotli.sh`, `scripts/cross-arm64-cares.sh`)
`libbrotli{common,dec,enc}.so.1.2.0`과 `libcares.so.2.19.7`이 나오는데,
이는 이 패키지에 이미 스테이징된 라이브러리(각각 `1.1.0`, `2.19.3`)보다
패치 버전이 하나 앞선 것입니다. 둘 다 SONAME은 호환됩니다(메이저 버전이
각각 1과 2로 동일) — 스테이징된 버전이 이 패키지가 실제로 빌드되고
테스트된 대상이므로 당장 고장난 건 없지만, 이 두 라이브러리는 libuv의
수정이 고집한 것과 같은 정확한 버전 일치로 빌드된 게 아니었다는 뜻입니다.
다음에 다시 빌드할 때는 스크립트의 결과물을 쓰는 게 낫습니다.
`libnghttp2`(`scripts/cross-arm64-nghttp2.sh`)는 정확히 일치합니다
(`14.29.5`).

## 실제 Next.js 앱을 스트레스 테스트하며 찾은 두 가지 실제 버그

**1. 데스크톱 실행 타깃 밖에서는 `ICU_DATA`가 전혀 설정되지 않았습니다.**
이 이미지의 `icu74`는 부트스트랩용 스텁일 뿐이고, 실제 ICU 데이터 파일은
`/boot/system/data/icu/74.1`에 있는데, 데스크톱 실행 타깃의
`SetupEnvironment`만 이 경로로 `ICU_DATA`를 지정했습니다. SSH를 통한 어떤
`Intl` 사용(`new Intl.DateTimeFormat`, npm 자체의 문자열 로케일 비교)도
크래시하거나 예외를 던졌습니다. `golang_bin`의 `bin/go` 래퍼가 자신의
빈 `GOPROXY`/`GOSUMDB`를 고친 것과 같은 방식으로 수정했습니다 —
`bin/node`를 래퍼 스크립트로 바꾸고(`export
ICU_DATA=/boot/system/data/icu/74.1; exec bin/node-real "$@"`), 진짜
바이너리는 `bin/node-real`로 옮겼습니다.

**2. npm/npx가 아예 연결되어 있지 않았습니다**(빌드에서
`node_install_npm`이 false였음). `bin/npm`/`bin/npx`는 이제 Node 자신이
번들한 npm CLI를 패키징한 복사본(`deps/npm`, test/docs/man 트리는 제외)을
`lib/node/npm`에 올려두고 그걸 감싸는 래퍼 스크립트입니다.

## Next.js의 진짜 원인 (앞서 두 번 틀렸던 진단을 바로잡음)

`next-swc`는 `haiku`/`arm64` 네이티브 빌드가 없고 앞으로도 없을
것입니다 — 하지만 Next.js의 WASM 폴백(`@next/swc-wasm-nodejs`, `npm`/`npx`가
PATH에 있으면 첫 `next build` 때 자동으로 내려받힘)은 정상 동작하며
수동으로 파일을 놓아줄 필요가 전혀 없습니다. 이건 당연히 알 수 있는
사실이 아니었습니다 — 앞선 두 차례의 테스트 모두 같은 증상(`next build`가
모든 `app/*.js` 파일에서 `'import' and 'export' may appear only with
sourceType: module` 에러로 실패)을 보고 WASM 폴백 자체가 고장났다고
결론 내렸습니다. `node_modules/next/dist/build/swc/index.js`를 직접
계측해서 확인한 결과: 실제 빌드 중 SWC 변환 호출은 100개 넘는 모듈에
걸쳐 전부 성공합니다(`isWasm=true`, 정상 출력) — 실패는 SWC보다 훨씬
뒤쪽에서 일어납니다.

실제 트리거: `npm init -y`(이 npm CLI의 기본 동작)가 `package.json`에
명시적으로 `"type": "commonjs"`를 써 넣습니다. Next.js 15의 webpack
설정은 `"type"` 필드가 전혀 없는 `package.json`(`create-next-app`으로
스캐폴딩한 것을 포함해 실제 Next.js 프로젝트 대부분에 해당하는 흔한
경우)과 이 필드가 있는 경우를 다르게 처리합니다 — 필드가 있으면 webpack이
이미 정상적으로 SWC 변환된 app-router 출력을 잘못된 `sourceType`으로
해석해서 빌드가 실패합니다. 이 필드를 지우면(또는 애초에 안 쓰면) 똑같은
WASM 기반 빌드가 성공합니다. `npm init -y`부터 `next start`에 대한 실제
`curl` HTTP 200까지, 빌드 전에 `"type"` 필드만 지우는 걸로 두 번 끝까지
확인했습니다 — SWC/WASM 파일을 손으로 놓거나, postinstall hook을 쓰거나,
패키지를 바꿀 필요는 전혀 없었습니다.

## Revision 3: 처음으로 제대로 처음부터 빌드, 그리고 완전한 `Intl`

위의 revision 1-2는 V8 포트가 이미 동작하는, 앞선 세션에서 넘겨받은
Node 체크아웃에서 빌드·패키징한 것입니다. Revision 3은 V8 자체의
처음부터 하는 Haiku 포트까지 포함해서 전체 파이프라인을 깨끗한
`node-v24.21.0` 체크아웃부터 끝까지 처음으로 돌린 것이고, 그 과정에서
이미 패치된 체크아웃이 전혀 건드리지 않았던 실제 `gyp`/빌드 시스템 틈이
여러 개 드러났습니다:

- **GYP 자체의 OS 플레이버 감지**(`tools/gyp/pylib/gyp/common.py`의
  `GetFlavorByPlatform()`)에 `haiku` 분기가 전혀 없어서 조용히
  `"linux"`로 떨어졌습니다 — 그 결과 V8의 `platform-linux.cc`가 정작
  맞는 `platform-haiku.cc`와 함께 컴파일됐습니다. 빠진 분기 하나
  (`sys.platform.startswith("haiku") -> "haiku"`)를 추가해서 고쳤습니다.
- **OpenSSL 자신의 arm64 빌드 설정 선택**, `deps/openssl/*.gypi` 9개
  파일(`openssl[-cl][-fips]_{asm,asm_avx2,no_asm}.gypi`) 전부에서:
  각 파일이 `'target_arch=="arm64" and OS in "linux openharmony"'`를
  하드코딩해두고, "다른 아키텍처는 어셈블리를 안 쓴다"고 적힌 마지막
  `else` 분기로 떨어지는데 실제로는 이 분기도 **x86_64** 리눅스 asm
  설정을 그대로 포함합니다 — `haiku`는 둘 중 아무 조건도 맞지 않아
  떨어졌고, 모든 OpenSSL 오브젝트가 arm64 타깃에서 `-m64`와 x86 SSE2
  define으로 컴파일되다가 바로 실패했습니다(`cc: error: unrecognized
  command-line option '-m64'`). 각 arm64/Linux 조건에 `haiku`를
  추가해서 고쳤고, 기존 `linux-aarch64` 설정 디렉터리는 그대로
  재사용했습니다(실제로 Linux에만 특정된 내용이 아니라 그냥 include
  경로와 전처리 define뿐입니다).
- **같은 `linux-aarch64` 설정의 `openssl_ex_libs_linux-aarch64`
  변수가 `-lm -ldl -pthread`를 하드코딩**하고 있어서 (같은 9개 파일),
  `openssl-cli`의 링크 단계가 `cannot find -ldl`로 실패했습니다 —
  Haiku는 `dlopen`/`dlsym`을 `libroot.so`에 합쳐놔서 별도 `libdl`이
  전혀 없습니다. `-ldl`을 빼고 `-lm -pthread`만 남겼습니다.
- **zlib의 `cpu_features.c`**는 명시적으로 나열된 OS 매크로
  목록(Android/Linux/macOS/Fuchsia/iOS/x86/RISC-V)에서만
  `cpu_check_features()`를 정의하는데 — 그 안에 Haiku가 없어서 심볼
  자체가 존재하지 않았고, `deflate.c`/`adler32.c`/`crc32.c`가 `undefined
  reference to 'cpu_check_features'`로 링크 실패했습니다.
  `ARMV8_OS_HAIKU`를 추가(`deps/zlib/zlib.gyp`의 `zlib_arm_crc32`
  타깃과 `deps/zlib/cpu_features.c` 자체)하고 `ARMV8_OS_MACOS`와
  똑같이 취급했습니다: 런타임에 탐지하는 대신 ARMv8.1의 `crc32`/`pmull`
  암호화 확장을 빌드 타임에 그냥 있다고 가정합니다 — macOS/arm64에서
  맞는 이유와 똑같은 이유로 여기서도 맞습니다. 이 포트는 실제 Apple
  Silicon 위에서 `-cpu host`(hvf 패스스루)로 돌아가고, 둘 다 무조건
  갖추고 있습니다.
- **c-ares 헤더가 실제로는 한 단계 더 깊은 곳**(`include/cares/ares.h`)에
  놓여 있었는데 `--shared-cares-includes`는 `include/ares.h`를
  기대합니다 — 이건 이 포트 자신의 라이브러리 스테이징 스크립트가
  배치한 방식의 문제고, Node나 c-ares의 버그는 아닙니다. 한 단계 위로도
  복사해서 고쳤습니다.
- **버전 없는 `.so` 심볼릭 링크 2개가 빠져 있었습니다**: Haiku는 정확한
  버전이 붙은 공유 객체만 제공하고(`libexecinfo.so.1.1`,
  `libicuuc.so.74.1`, ...), devel 패키지가 보통 제공하는, 링커의
  `-lfoo`가 실제로 찾는 맨 `libfoo.so` 심볼릭 링크는 전혀 없습니다.
  둘 다 다른 4개 번들 런타임이 이미 들어 있는 같은 커스텀 라이브러리
  디렉터리에 손으로 추가해야 했습니다.
- **`Intl`/ICU, 돌아가는 길.** `--with-intl=system-icu`는 이 이미지에
  살아있는 `icu74`를 `pkg-config`로 링크하는데 — 이 이미지에는
  `pkg-config`/`pkgconf` 바이너리가 전혀 없어서, Node의 configure가
  실제로 묻는 두 쿼리(`icu-i18n`, `icu-uc`)에만 답하는 4줄짜리 shim
  스크립트가 필요했습니다. 그걸로 빌드는 성공했지만, `new
  Intl.DateTimeFormat(...).format(...)`이 ICU 자신의
  `DateTimePatternGeneratorCache` 안에서 메모리 부족으로 크래시났습니다
  — 이 이미지의 `/boot/system/lib/libicudata.so.74.1`이 132KB짜리
  부트스트랩 전용 스텁이라서, 실제 날짜 패턴 생성에 필요한 로케일
  데이터가 턱없이 부족했던 겁니다. 더 파고들지 않고 대신
  `--with-intl=full-icu`로 바꿨습니다: Node 자신이 번들한
  `deps/icu-small`이 디렉터리 이름과 달리 실제로는 완전한 ICU
  스냅샷이라는 걸 확인했고(`README-FULL-ICU.txt`가 그걸 확인해줍니다),
  이러면 시스템 자신의 ICU에 전혀 의존하지 않습니다. 남은 장애물 하나:
  `configure.py`가 번들된 `icudt78l.dat.bz2`를 Python의 `bz2` 모듈로
  압축 해제하는데, 이 이미지에는 `libbz2`도 없습니다(V8 빌드 자체에서
  이미 한 번 마주친 틈과 같은 것이고, 거기서는 스텁 `bz2` 모듈로
  돌아갔습니다) — 이번에는 실제 `bzip2` 바이너리(리눅스 교차 빌드
  컨테이너에 이미 있습니다)로 그 파일을 한 번 따로 압축 해제해서,
  `configure.py`가 찾는 그 자리에 평범한 `.dat` 파일을 놓아뒀습니다 —
  그러면 `bz2`를 전혀 부를 일이 없습니다. (참고로: 베이스 시스템은
  별도로 `/boot/system/data/icu/74.1`에 완전한 30MB짜리
  `icudt74l.dat`도 갖고 있습니다 — revision 2의 `ICU_DATA` 래퍼가
  시스템 자신의 앱들을 위해 이미 가리키고 있는 바로 그 경로입니다.
  런타임에 `ICU_DATA`로 그 파일을 가리키는 `system-icu` 빌드도
  됐을 수 있고, 소스에서 ICU를 다시 빌드하는 것보다 더 저렴했을
  겁니다 — 여기서는 시도하지 않았습니다, `full-icu`가 먼저 도착했고
  어느 쪽이든 더 독립적인 결과물이기 때문입니다: 그 경로가 계속
  존재해야 한다는 런타임 의존이 없습니다.)

이 중 어느 것도 이번 빌드에만 해당하는 문제가 아닙니다 — 이 포트 자신의
`gyp`/라이브러리 스테이징 틈이고, 빌드마다 임시로 돌아가는 게 아니라
소스 트리와 스크립트에서 한 번 고쳤습니다. 빌드 자체도 중간에 한 맥에서
더 빠른 다른 맥으로 옮겼습니다: 게스트의 `node-v$VER` 빌드
디렉터리(ninja 자신의 증분 상태 포함)와 베이스 OS 디스크 이미지를 각각
tar로 묶어서, 새 호스트에서 똑같은 `ninja` 명령을 다시 실행하니 멈춘
지점에서 정확히 이어졌습니다.

Revision 3의 `bin/node-real`은 약 112MB입니다(rev 2의 약 73MB에서
늘어남), 전부 정적으로 링크된 완전한 ICU 데이터 때문입니다. 외부
런타임 의존성(libuv/libbrotli\*/libcares/libnghttp2)은 그대로입니다.
revision 2와 똑같은 방식으로 검증했습니다 — 빌드 디렉터리에서 방금
만든 바이너리를 그냥 실행해본 게 아니라, 실제 패키지 교체와 깨끗한
재부팅으로 — `scripts/smoke-test-nodejs.sh`가 `Intl.DateTimeFormat`을
포함해서 전부 통과했습니다.

## 라이선스

MIT.

## AI 사용 고지

이 작업은 Claude(Anthropic)가 다 했습니다. 두 버그를 찾아낸 것(Next.js
문제에 대한 자신의 앞선 두 번의 잘못된 진단을 스스로 바로잡은 것 포함),
수정, 패키징, 검증까지 전부 에이전틱 코딩 세션 안에서 Claude가 작성하고
빌드하고 실행하고 디버깅했습니다. 작성자는 세션의 방향을 정하고 각
단계를 승인했습니다. Revision 3의 처음부터-빌드 수정(OpenSSL, zlib, GYP의
OS 감지, 완전한 ICU)과 빌드 중 머신 이전은 나중 세션에서 같은 방식으로
진행했습니다.
