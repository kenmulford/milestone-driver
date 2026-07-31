#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for check-size-budgets.sh (issue #295).
# Each fixture is a repo-root under tests/fixtures/check-size-budgets/<case>/
# mirroring the governed files' real relative paths; the fixture files'
# CONTENT is throwaway filler: only their LINE COUNT and BYTE COUNT are
# asserted. The expected emitted output lives in
# tests/fixtures/check-size-budgets/_expected/<case>.txt. The .sh and .ps1
# runners assert against the SAME golden files (cross-impl parity), mirroring
# tests/ci-preflight-steps.test.{sh,ps1}.
#
# Cases prove the per-file semantics required by issue #295: a file AT both
# ceilings passes (at-ceiling), one line OVER its line ceiling fails NAMING
# that file (one-over), and an absent governed file fails as MISSING
# (missing-file) — never a silent pass.
#
# line-flat-byte-over covers the byte ceiling added by issue #399, and is the
# case a line-only checker CANNOT catch: its async-mode.md is the at-ceiling
# tree's file with one sentence appended to the END OF AN EXISTING LINE. Line
# count is unchanged at 40/40, so the pre-#399 checker emitted an all-OK stream
# and exited 0; the byte count moved 5000 -> 5106 against a 5000 ceiling, so
# the byte column fails it. That is the real growth shape this ratchet missed
# (PR #398 grew a governed file 1052 bytes at a flat line count).
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
  "line-flat-byte-over|1"
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
