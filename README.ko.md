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
필요로 하는 정확한 버전으로 함께 패키징했습니다. openssl3, icu74, zlib은
베이스 시스템이 이미 제공하므로 그대로 둡니다.

## 빌드 시점의 유일한 수정: `scripts/cross-arm64-libuv.sh`

빌드 이미지에 미리 올려져 있던 libuv가 node-v24.21.0이 요구하는 버전보다
한 단계 낮았습니다(번들된 `deps/uv`가 요구하는 1.52.1 대신 1.49.2) —
`uv_statfs_s`에는 이름이 바뀐 `f_frsize` 필드가 없었고, `uv_thread_setname`은
아예 존재하지 않았습니다. Node 자신이 번들한 `deps/uv` 소스(이미 자체
RenkuOS 포트를 갖고 있음 — `src/unix/haiku.c`, `CMakeLists.txt`의
`CMAKE_SYSTEM_NAME STREQUAL "Haiku"` 분기 — 패치 불필요)로 직접 교차
빌드해서, 구조적으로 정확한 버전 일치를 보장하도록 고쳤습니다.

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

## 라이선스

MIT.

## AI 사용 고지

이 작업은 Claude(Anthropic)가 다 했습니다. 두 버그를 찾아낸 것(Next.js
문제에 대한 자신의 앞선 두 번의 잘못된 진단을 스스로 바로잡은 것 포함),
수정, 패키징, 검증까지 전부 에이전틱 코딩 세션 안에서 Claude가 작성하고
빌드하고 실행하고 디버깅했습니다. 작성자는 세션의 방향을 정하고 각
단계를 승인했습니다.
