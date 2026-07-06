#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for check-size-budgets.sh (issue #295).
# Each fixture is a repo-root under tests/fixtures/check-size-budgets/<case>/
# mirroring the governed files' real relative paths; the fixture files'
# CONTENT is throwaway filler — only their LINE COUNT is asserted. The
# expected emitted output lives in
# tests/fixtures/check-size-budgets/_expected/<case>.txt. The .sh and .ps1
# runners assert against the SAME golden files (cross-impl parity), mirroring
# tests/ci-preflight-steps.test.{sh,ps1}.
#
# Cases prove the per-file semantics required by issue #295: a file AT its
# ceiling passes (at-ceiling), one line OVER its ceiling fails NAMING that
# file (one-over), and an absent governed file fails as MISSING
# (missing-file) — never a silent pass.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/check-size-budgets.sh"
FIX="tests/fixtures/check-size-budgets"
GOLD="$ROOT/$FIX/_expected"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

# case <name>|<wantExit>
declare -a CASES=(
  "at-ceiling|0"
  "one-over|1"
  "missing-file|1"
)

pass=0; fail=0
# Paths are passed RELATIVE to the repo root (and we cd there) so any path
# text in the output is checkout-independent and matches the committed golden
# exactly. Mirrors tests/ci-preflight-steps.test.sh.
cd "$ROOT"
for spec in "${CASES[@]}"; do
  IFS='|' read -r name wantExit <<< "$spec"
  exp="$GOLD/$name.txt"
  [ -f "$exp" ] || { echo "FAIL $name: missing golden $exp" >&2; fail=$((fail+1)); continue; }
  got="$(bash "$SCRIPT" "$FIX/$name" 2>&1)"; rc=$?
  # CR-normalize the golden so a CRLF checkout (Windows core.autocrlf) still
  # compares clean — the script's own stdout is already LF. Mirrors the .ps1 runner.
  want="$(tr -d '\r' < "$exp")"
  if [ "$got" = "$want" ] && [ "$rc" -eq "$wantExit" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: rc=$rc (want $wantExit)" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2 || true
  fi
done
echo "check-size-budgets.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
