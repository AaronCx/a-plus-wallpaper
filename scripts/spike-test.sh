#!/bin/bash
# spike-test.sh — build and test the Phase 0 Live Photo spike on one simulator.
#
# Usage: scripts/spike-test.sh --device "iPhone 17" [--os 26.5] [--out DIR] [--only-testing ID]...
#
# - Uses (or creates) a dedicated simulator named "APW <device> (<os>)", so
#   no existing simulator is modified.
# - Installs the app, then grants Photos read/write access before testing (see
#   the TCC note below); the Photos tests FAIL (never skip) without it.
# - Fails unless the result bundle shows 0 failed and 0 skipped tests, and at
#   least one passed.
# - Copies the per-variant JSON reports out of the app container into --out.
set -euo pipefail

DEVICE=""
OS=""
OUT=""
ONLY=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --os) OS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --only-testing) ONLY+=("-only-testing:$2"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$DEVICE" ]] || { echo "usage: $0 --device NAME [--os X.Y] [--out DIR] [--only-testing ID]" >&2; exit 64; }

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.aaroncx.apluswallpaper.spike"
OUT="${OUT:-$ROOT/build/spike-test/$(echo "$DEVICE-${OS:-latest}" | tr ' ()' '_--')}"
mkdir -p "$OUT"
RESULT="$OUT/LivePhotoSpike.xcresult"
rm -rf "$RESULT"

echo "== $(xcodebuild -version | tr '\n' ' ')"

# Pick the runtime: the requested iOS version, else the newest installed iOS runtime.
RUNTIME_ID=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = sys.argv[1]
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
if want:
    runtimes = [r for r in runtimes if r["version"] == want or r["version"].startswith(want + ".")]
runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(runtimes[-1]["identifier"] + " " + runtimes[-1]["version"] if runtimes else "")
' "$OS")
[[ -n "$RUNTIME_ID" ]] || { echo "No installed iOS runtime matches '${OS:-any}'." >&2; exit 1; }
RUNTIME_VERSION="${RUNTIME_ID#* }"
RUNTIME_ID="${RUNTIME_ID%% *}"

NAME="APW $DEVICE ($RUNTIME_VERSION)"
UDID=$(xcrun simctl list devices -j | python3 -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for d in json.load(sys.stdin)["devices"].get(runtime, []):
    if d["name"] == name and d.get("isAvailable"):
        print(d["udid"]); break
' "$NAME" "$RUNTIME_ID")
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun simctl create "$NAME" "$DEVICE" "$RUNTIME_ID")
  echo "== created simulator $NAME ($UDID)"
fi
echo "== simulator $NAME ($UDID)"

xcrun simctl bootstatus "$UDID" -b >/dev/null

DERIVED="$ROOT/build/DerivedData"
XCODEBUILD_ARGS=(-project "$ROOT/Spike/LivePhotoSpike.xcodeproj" -scheme LivePhotoSpike -destination "id=$UDID" -derivedDataPath "$DERIVED")

# Build, install and grant Photos access BEFORE testing: a grant made before the
# app is installed does not survive xcodebuild's install (verified on iOS 26.5).
if ! xcodebuild build-for-testing "${XCODEBUILD_ARGS[@]}" > "$OUT/build.log" 2>&1; then
  grep -E "error:|warning:" "$OUT/build.log" | sort -u || true
  echo "== BUILD FAILED (see $OUT/build.log)"
  exit 1
fi
WARNINGS=$(grep -E "^/.*: warning:" "$OUT/build.log" | grep -v "/build/DerivedData/" | sort -u || true)
if [[ -n "$WARNINGS" ]]; then
  echo "$WARNINGS"
  echo "== BUILD HAS WARNINGS IN OUR CODE"
  exit 1
fi
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/LivePhotoSpike.app"

# `simctl privacy grant photos` writes a version-1 TCC entry, but PhotoKit's
# read/write check (iOS 14+ full/limited model) queries version 2 and treats a
# missing v2 entry as "not determined" (seen in tccd's log: AUTHREQ_RESULT
# authVersion=2 -> authValue=1, authVersion=1 -> authValue=2; iOS 17.5 and 26.5).
# Upgrade the entry we just granted, in this dedicated simulator only.
xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID"
TCC_DB="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"
sqlite3 "$TCC_DB" "UPDATE access SET auth_version=2 WHERE service='kTCCServicePhotos' AND client='$BUNDLE_ID' AND auth_value=2;"
GRANT=$(sqlite3 "$TCC_DB" "SELECT auth_value || '/' || auth_version FROM access WHERE service='kTCCServicePhotos' AND client='$BUNDLE_ID';")
[[ "$GRANT" == "2/2" ]] || { echo "== Photos grant not in place (TCC auth_value/version: '${GRANT:-none}')" >&2; exit 1; }

set +e
xcodebuild test-without-building "${XCODEBUILD_ARGS[@]}" \
  -resultBundlePath "$RESULT" \
  ${ONLY[@]+"${ONLY[@]}"} \
  > "$OUT/xcodebuild.log" 2>&1
XCODEBUILD_STATUS=$?
set -e
grep -E "error:|warning:|\*\* (TEST|BUILD)|Test run with|^[✔✘◇↳] |^􀟈|^􁁛|^􀢄" "$OUT/xcodebuild.log" | grep -v "appintentsmetadataprocessor" || true

# The result bundle is the source of truth: a skipped test is not a passing one.
SUMMARY=$(xcrun xcresulttool get test-results summary --path "$RESULT" --compact 2>/dev/null || echo '{}')
echo "$SUMMARY" > "$OUT/summary.json"
python3 - "$OUT/summary.json" "$XCODEBUILD_STATUS" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
status = int(sys.argv[2])
total = summary.get("totalTestCount", 0)
passed = summary.get("passedTests", 0)
failed = summary.get("failedTests", 0)
skipped = summary.get("skippedTests", 0)
print(f"== result: {summary.get('result', 'unknown')}  total={total} passed={passed} failed={failed} skipped={skipped} xcodebuild_exit={status}")
for failure in summary.get("testFailures", []):
    print(f"   FAILED {failure.get('testIdentifierString', '?')}: {failure.get('failureText', '')}")
ok = status == 0 and total > 0 and passed == total and failed == 0 and skipped == 0
sys.exit(0 if ok else 1)
PY

# Pull the per-variant parameter reports out of the host app's container.
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
if [[ -n "$CONTAINER" && -d "$CONTAINER/Documents/variant-reports" ]]; then
  mkdir -p "$OUT/variant-reports"
  cp "$CONTAINER"/Documents/variant-reports/*.json "$OUT/variant-reports/" 2>/dev/null || true
  echo "== $(ls "$OUT/variant-reports" | wc -l | tr -d ' ') variant reports in $OUT/variant-reports"
fi
echo "== PASS on $NAME"
