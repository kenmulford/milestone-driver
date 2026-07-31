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
#
# Fixture-prose caveat: the line-flat-byte-over tree is a BYTE-FOR-BYTE COPY of
# the at-ceiling tree with one sentence appended to an existing line. Its
# inherited prose therefore describes the at-ceiling copy, not itself: that
# file says it "stands at exactly 5000 bytes", that "both report 5000 here",
# and that its padding line is "sized so this fixture lands on exactly 5000
# bytes", while the file it sits in is 5106 bytes and is the deliberately-over
# case; it also names line-flat-byte-over/ as the sibling from inside
# line-flat-byte-over/. Do not "fix" that prose. The byte-for-byte-copy
# property is what the case rests on, and rewording a byte-pinned fixture moves
# its totals and forces a golden regeneration for no test value.
#
# parity-guard is the fifth case and the only one with no fixture tree: the
# script's FILES/CEILINGS/BYTE_CEILINGS tables are hand-edited parallel arrays
# and no fixture can desync them, so that case builds a desynced COPY of the
# script instead and asserts the refusal. See the block below the loop.
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

# --- parity-guard: the length-parity refusal (issue #399) ------------------
# The checker's three tables are hand-edited parallel arrays with no structural
# link, so it refuses to run when their lengths disagree rather than
# misattributing ceilings. No fixture tree can reach that path (a fixture is
# input, the tables are the script's own source), so this case desyncs a COPY
# of the script (awk drops the first entry of CEILINGS, leaving 14/13/14) and
# asserts all three halves of the refusal: EMPTY stdout, exit 1, and the
# exact stderr line. The stderr golden is shared with the .ps1 runner, which
# runs the same case against the same file, so the two twins' refusal messages
# are held byte-identical the way the OK/FAIL goldens hold their record streams.
GUARD_GOLD="$GOLD/parity-guard.stderr.txt"
GUARD_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_guard.$$")"
GUARD_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_guard_err.$$")"
trap 'rm -f "$GUARD_SCRIPT" "$GUARD_ERR"' EXIT
if [ ! -f "$GUARD_GOLD" ]; then
  echo "FAIL parity-guard: missing golden $GUARD_GOLD" >&2; fail=$((fail+1))
else
  # Drop the first entry line following the CEILINGS=( opener. Anchored at line
  # start, so BYTE_CEILINGS=( (which also ends in "CEILINGS=(") never matches.
  # If a table rewrite ever makes this a no-op the case still fails loud: the
  # unmodified copy prints its OK records and stdout is then not empty.
  awk '/^CEILINGS=\(/ { print; drop = 1; next }
       drop && /^  [0-9][0-9]*$/ { drop = 0; next }
       { print }' "$SCRIPT" > "$GUARD_SCRIPT"
  guard_out="$(bash "$GUARD_SCRIPT" "$FIX/at-ceiling" 2>"$GUARD_ERR")"; grc=$?
  guard_err="$(tr -d '\r' < "$GUARD_ERR")"
  guard_want="$(tr -d '\r' < "$GUARD_GOLD")"
  if [ -z "$guard_out" ] && [ "$grc" -eq 1 ] && [ "$guard_err" = "$guard_want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL parity-guard: rc=$grc (want 1), stdout=[$guard_out] (want empty)" >&2
    diff <(printf '%s\n' "$guard_want") <(printf '%s\n' "$guard_err") >&2 || true
  fi
fi

echo "check-size-budgets.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
