#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for ci-preflight-steps.sh (issue #162).
# Each fixture is a repo-root under tests/fixtures/ci-preflight/<case>/ with a
# .github/workflows/*.yml tree; the expected emitted output lives in
# tests/fixtures/ci-preflight/_expected/<case>.txt. The .sh and .ps1 runners
# assert against the SAME golden files (cross-impl parity).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/ci-preflight-steps.sh"
FIX="tests/fixtures/ci-preflight"
GOLD="$ROOT/$FIX/_expected"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

# case <name> [ciWorkflow] [goldenBasename]
declare -a CASES=(
  "clean-run"
  "skip-rules"
  "working-dir"
  "silent-under-run"
  "not-gating"
  "block-scalar"
  "inline-comment"
  "multi-workflow"
  "services"
  "no-workflows-dir"
  "multi-workflow|zeta.yml|multi-workflow__zeta"
)

pass=0; fail=0
# Paths are passed RELATIVE to the repo root (and we cd there) so the WARN path
# text is checkout-independent and matches the committed golden exactly.
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
  # CR-normalize the golden so a CRLF checkout (Windows core.autocrlf) still
  # compares clean — the script's own stdout is already LF. Mirrors the .ps1 runner.
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
