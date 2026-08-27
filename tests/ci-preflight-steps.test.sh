#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for ci-preflight-steps.sh (issue #162).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/ci-preflight-steps.sh"
FIX="tests/fixtures/ci-preflight"
GOLD="$ROOT/$FIX/_expected"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

declare -a CASES=(
  "clean-run"
  "skip-rules"
  "working-dir"
  "silent-under-run"
  "not-gating"
  "block-scalar"
  "inline-comment"
  "multi-workflow"
  "sort-order"
  "services"
  "no-workflows-dir"
  "multi-workflow|zeta.yml|multi-workflow__zeta"
)

pass=0; fail=0
cd "$ROOT"
for spec in "${CASES[@]}"; do
  IFS='|' read -r name only gold <<< "$spec"
  [ -z "$gold" ] && gold="$name"
  exp="$GOLD/$gold.txt"
  [ -f "$exp" ] || { echo "FAIL $name: missing golden $exp" >&2; fail=$((fail+1)); continue; }
  if [ -n "$only" ]; then
    got="$(bash "$SCRIPT" "$FIX/$name" "$only" 2>&1)"
  else
    got="$(bash "$SCRIPT" "$FIX/$name" 2>&1)"
  fi
  want="$(tr -d '\r' < "$exp")"
  if [ "$got" = "$want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2 || true
  fi
done
echo "ci-preflight-steps.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
