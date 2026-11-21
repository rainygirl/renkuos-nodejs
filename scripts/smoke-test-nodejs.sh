#!/bin/sh
# Quick post-install smoke test for nodejs_bin. Run on the target RenkuOS
# arm64 machine itself (over SSH or locally), after `pkgman install
# nodejs_bin`:
#
#   sh smoke-test-nodejs.sh
#
# Exercises exactly the paths this package's own revision 2 had to fix --
# ICU_DATA under a non-desktop (SSH) session, and npm/npx actually being
# wired up -- plus a basic sanity check that node itself runs. Does not
# attempt a real `npm install` (slow, needs network); that path is
# covered separately by the Next.js build/run verification described in
# README.md. Exits non-zero on the first failure.
set -e

echo "== node --version =="
node --version

echo "== basic eval =="
[ "$(node -e 'console.log(1 + 1)')" = "2" ] || { echo "FAIL: basic eval"; exit 1; }
echo "basic eval ok"

echo "== Intl under this session (the ICU_DATA bug's path) =="
node -e '
const d = new Intl.DateTimeFormat("en-US", {month: "long"}).format(new Date(2026, 0, 1));
if (d !== "January") { console.log("FAIL: got", d); process.exit(1); }
console.log("Intl ok:", d);
'

echo "== npm --version (npm wiring) =="
npm --version

echo "== npx --version (npx wiring) =="
npx --version

echo "== ALL NODEJS SMOKE TESTS PASSED =="
