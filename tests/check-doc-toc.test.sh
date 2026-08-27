#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for check-doc-toc.sh (issue #490).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/check-doc-toc.sh"
FIX="tests/fixtures/check-doc-toc"
GOLD="$ROOT/$FIX/_expected"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

declare -a CASES=(
  "compliant|0"
  "fenced-pseudo-heading|0"
  "missing-heading|1"
  "heading-not-first|1"
  "missing-file|1"
)

pass=0; fail=0
cd "$ROOT"
for spec in "${CASES[@]}"; do
  IFS='|' read -r name wantExit <<< "$spec"
  exp="$GOLD/$name.txt"
  [ -f "$exp" ] || { echo "FAIL $name: missing golden $exp" >&2; fail=$((fail+1)); continue; }
  got="$(bash "$SCRIPT" "$FIX/$name" 2>&1)"; rc=$?
  want="$(tr -d '\r' < "$exp")"
  if [ "$got" = "$want" ] && [ "$rc" -eq "$wantExit" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: rc=$rc (want $wantExit)" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2 || true
  fi
done

echo "check-doc-toc.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
