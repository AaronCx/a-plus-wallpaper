#!/bin/bash
# spike-matrix.sh — run the Phase 0 spike tests across the simulator matrix in
# docs/BRIEF.md section 6, then print the variant parameter tables.
#
# Usage: scripts/spike-matrix.sh [OUT_DIR]
# Runs sequentially (the runs share one DerivedData). Fails if any simulator
# fails, if a passing simulator lacks its 12 variant reports, or if the tables
# can't be built.
#
# The body is a function called on the last line, so bash parses the whole
# file before running it: editing this script mid-run can't break a run.
set -uo pipefail

main() {
  local ROOT OUT
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  OUT="${1:-$ROOT/build/spike-matrix}"
  rm -rf "$OUT"
  mkdir -p "$OUT"

  local MATRIX=(
    "iPhone 17|26.5"
    "iPhone 17 Pro Max|26.5"
    "iPhone SE (3rd generation)|26.5"
    "iPad Pro 13-inch (M5)|26.5"
    "iPhone Xs|17.5"
    "iPhone SE (3rd generation)|17.5"
    "iPad Pro 13-inch (M4)|17.5"
  )

  local failed=() reports=() entry device os dir
  for entry in "${MATRIX[@]}"; do
    device="${entry%%|*}"
    os="${entry##*|}"
    dir="$OUT/$(echo "$device-$os" | tr ' ()' '_--')"
    echo "=== $device, iOS $os"
    if "$ROOT/scripts/spike-test.sh" --device "$device" --os "$os" --out "$dir" > "$dir.log" 2>&1; then
      grep -E "^== (result|PASS)" "$dir.log"
      reports+=("$dir/variant-reports")
    else
      grep -E "^== |FAILED" "$dir.log" | tail -8
      failed+=("$device ($os)")
    fi
  done

  echo
  if [[ ${#reports[@]} -gt 0 ]]; then
    python3 "$ROOT/scripts/variant-report-table.py" "${reports[@]}" || failed+=("variant report tables")
  fi

  if [[ ${#failed[@]} -gt 0 ]]; then
    echo "FAILED: ${failed[*]}"
    exit 1
  fi
  echo "ALL ${#MATRIX[@]} SIMULATORS PASSED"
}

main "$@"
