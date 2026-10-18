#!/bin/bash
# spike-test.sh — build and test the Phase 0 Live Photo spike on one simulator.
#
# Usage: scripts/spike-test.sh --device "iPhone 17" [--os 26.5] [--out DIR] [--only-testing ID]...
#
# - Uses (or creates) a dedicated simulator named "APW <device> (<os>)", so
#   no existing simulator is modified, and shuts it down when done.
# - Fails on any warning in our code (warnings are also errors in the project).
# - Installs the app, then grants Photos read/write access before testing (see
#   the TCC note below). The Photos tests FAIL, never skip, without it.
# - Fails unless the result bundle shows 0 failed and 0 skipped tests, and at
#   least one passed. A full run (no --only-testing) must also produce all 12
#   variant reports, which are copied out of the app container into --out.
#
# The body is a function called on the last line, so bash parses the whole
# file before running it: editing this script mid-run can't break a run.
set -euo pipefail

main() {
  local DEVICE="" OS="" OUT=""
  local ONLY=()
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

  local ROOT BUNDLE_ID="com.aaroncx.apluswallpaper.spike"
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  OUT="${OUT:-$ROOT/build/spike-test/$(echo "$DEVICE-${OS:-latest}" | tr ' ()' '_--')}"
  mkdir -p "$OUT"
  local RESULT="$OUT/LivePhotoSpike.xcresult"
  # Never let reports from an earlier run pass as this run's.
  rm -rf "$RESULT" "$OUT/variant-reports"

  echo "== $(xcodebuild -version | tr '\n' ' ')"

  # The requested iOS version, else the newest installed iOS runtime.
  local RUNTIME RUNTIME_ID RUNTIME_VERSION
  RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = sys.argv[1]
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")]
if want:
    runtimes = [r for r in runtimes if r["version"] == want or r["version"].startswith(want + ".")]
runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(runtimes[-1]["identifier"] + " " + runtimes[-1]["version"] if runtimes else "")
' "$OS")
  [[ -n "$RUNTIME" ]] || { echo "No installed iOS runtime matches '${OS:-any}'." >&2; exit 1; }
  RUNTIME_ID="${RUNTIME%% *}"
  RUNTIME_VERSION="${RUNTIME#* }"

  local NAME="APW $DEVICE ($RUNTIME_VERSION)" UDID
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
  # Don't leave simulators running between matrix entries.
  trap "xcrun simctl shutdown '$UDID' >/dev/null 2>&1 || true" EXIT

  local DERIVED="$ROOT/build/DerivedData"
  local XCODEBUILD_ARGS=(-project "$ROOT/Spike/LivePhotoSpike.xcodeproj" -scheme LivePhotoSpike -destination "id=$UDID" -derivedDataPath "$DERIVED")

  echo "== building"
  if ! xcodebuild build-for-testing "${XCODEBUILD_ARGS[@]}" > "$OUT/build.log" 2>&1; then
    grep -E "error:|warning:" "$OUT/build.log" | sort -u || true
    echo "== BUILD FAILED (see $OUT/build.log)"
    exit 1
  fi
  local WARNINGS
  WARNINGS=$(grep -E "^/.*: warning:" "$OUT/build.log" | grep -v "/build/DerivedData/" | sort -u || true)
  if [[ -n "$WARNINGS" ]]; then
    echo "$WARNINGS"
    echo "== BUILD HAS WARNINGS IN OUR CODE"
    exit 1
  fi

  xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/LivePhotoSpike.app"
  local CONTAINER
  CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
  if [[ -n "$CONTAINER" ]]; then rm -rf "$CONTAINER/Documents/variant-reports"; fi

  # `simctl privacy grant photos` writes a version-1 TCC entry, but PhotoKit's
  # read/write check (iOS 14+ full/limited model) queries version 2 and treats a
  # missing v2 entry as "not determined" (seen in tccd's log: AUTHREQ_RESULT
  # authVersion=2 -> authValue=1, authVersion=1 -> authValue=2; iOS 17.5 and 26.5).
  # Upgrade the entry we just granted, in this dedicated simulator only.
  xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID"
  local TCC_DB="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db" GRANT
  sqlite3 "$TCC_DB" "UPDATE access SET auth_version=2 WHERE service='kTCCServicePhotos' AND client='$BUNDLE_ID' AND auth_value=2;"
  GRANT=$(sqlite3 "$TCC_DB" "SELECT auth_value || '/' || auth_version FROM access WHERE service='kTCCServicePhotos' AND client='$BUNDLE_ID';")
  if [[ "$GRANT" != "2/2" ]]; then
    echo "== Photos grant not in place (TCC auth_value/version: '${GRANT:-none}')" >&2
    exit 1
  fi

  # Stream progress (CI shows it live) while keeping the full log.
  echo "== testing"
  local XCODEBUILD_STATUS
  set +e
  xcodebuild test-without-building "${XCODEBUILD_ARGS[@]}" \
    -resultBundlePath "$RESULT" \
    ${ONLY[@]+"${ONLY[@]}"} 2>&1 \
    | tee "$OUT/xcodebuild.log" \
    | grep --line-buffered -E "error:|\*\* (TEST|BUILD)|Test run with|^[✔✘] |^◇ Test case passing|^↳ (Photos|Expectation)|^􀟈|^􁁛|^􀢄"
  XCODEBUILD_STATUS=${PIPESTATUS[0]}
  set -e

  # The result bundle is the source of truth: a skipped test is not a passing one.
  xcrun xcresulttool get test-results summary --path "$RESULT" --compact > "$OUT/summary.json" 2>/dev/null || echo '{}' > "$OUT/summary.json"
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

  # Pull this run's per-variant parameter reports out of the host app's container.
  # Look the container up again: xcodebuild's own install can move it.
  local COUNT=0
  CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)
  if [[ -n "$CONTAINER" && -d "$CONTAINER/Documents/variant-reports" ]]; then
    mkdir -p "$OUT/variant-reports"
    cp "$CONTAINER"/Documents/variant-reports/*.json "$OUT/variant-reports/" 2>/dev/null || true
    COUNT=$(find "$OUT/variant-reports" -name '*.json' | wc -l | tr -d ' ')
    echo "== $COUNT variant reports in $OUT/variant-reports"
  fi
  if [[ ${#ONLY[@]} -eq 0 && "$COUNT" -ne 12 ]]; then
    echo "== FAIL: a full run must produce 12 variant reports, got $COUNT" >&2
    exit 1
  fi
  echo "== PASS on $NAME"
}

main "$@"
