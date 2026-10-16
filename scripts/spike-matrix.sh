#!/bin/bash
# spike-matrix.sh — run the Phase 0 spike tests across the simulator matrix in
# docs/BRIEF.md section 6, then print one parameter table per simulator from the
# variant reports.
#
# Usage: scripts/spike-matrix.sh [OUT_DIR]
# Runs sequentially (the runs share one DerivedData). Fails if any run fails.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/spike-matrix}"
mkdir -p "$OUT"

MATRIX=(
  "iPhone 17|26.5"
  "iPhone 17 Pro Max|26.5"
  "iPhone SE (3rd generation)|26.5"
  "iPad Pro 13-inch (M5)|26.5"
  "iPhone Xs|17.5"
  "iPhone SE (3rd generation)|17.5"
  "iPad Pro 13-inch (M4)|17.5"
)

failed=()
for entry in "${MATRIX[@]}"; do
  device="${entry%%|*}"
  os="${entry##*|}"
  dir="$OUT/$(echo "$device-$os" | tr ' ()' '_--')"
  echo "=== $device, iOS $os"
  if "$ROOT/scripts/spike-test.sh" --device "$device" --os "$os" --out "$dir" > "$dir.log" 2>&1; then
    grep -E "^== (result|PASS)" "$dir.log"
  else
    grep -E "^== |FAILED" "$dir.log" | tail -8
    failed+=("$device ($os)")
  fi
done

echo
python3 "$ROOT/scripts/variant-report-table.py" "$OUT"/*/variant-reports

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "ALL ${#MATRIX[@]} SIMULATORS PASSED"
