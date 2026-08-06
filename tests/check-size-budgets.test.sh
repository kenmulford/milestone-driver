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
# and exited 0; the byte count moved 4500 -> 4606 against a 4500 ceiling, so
# the byte column fails it. That is the real growth shape this ratchet missed
# (PR #398 grew a governed file 1052 bytes at a flat line count).
#
# Fixture-prose caveat: the line-flat-byte-over tree is a BYTE-FOR-BYTE COPY of
# the at-ceiling tree with one sentence appended to an existing line. Its
# inherited prose therefore describes the at-ceiling copy, not itself: that
# file says it "stands at exactly 4500 bytes", that "both report 4500 here",
# and that its padding line is "sized so this fixture lands on exactly 4500
# bytes", while the file it sits in is 4606 bytes and is the deliberately-over
# case; it also names line-flat-byte-over/ as the sibling from inside
# line-flat-byte-over/. Do not "fix" that prose. The byte-for-byte-copy
# property is what the case rests on, and rewording a byte-pinned fixture moves
# its totals and forces a golden regeneration for no test value.
#
# parity-guard, positional-desync and the three malformed-row cases have no
# fixture tree: the governed set is a table in the checker's OWN source, so no
# fixture can reach it. Each of those cases builds an edited COPY of the
# checker instead (garble a column, swap two rows, drop a column, add a surplus
# column, widen a ceiling past int32 max) and asserts what the copy does. See
# the three blocks below the loop.
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

GUARD_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_guard.$$")"
GUARD_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_guard_err.$$")"
SWAP_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_swap.$$")"
MAL_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_mal.$$")"
MAL_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_mal_err.$$")"
trap 'rm -f "$GUARD_SCRIPT" "$GUARD_ERR" "$SWAP_SCRIPT" "$MAL_SCRIPT" "$MAL_ERR"' EXIT

# --- parity-guard: the length-parity refusal (issue #399) ------------------
# The checker parses its governed-set table into three index-aligned arrays,
# appending a ceiling only when that column is present AND all digits, so a row
# with a dropped or garbled column leaves the three counts unequal — and the
# checker refuses to run rather than measure a file against a neighbour's
# ceiling. No fixture tree can reach that path (a fixture is input, the table
# is the script's own source), so this case garbles ONE column in a COPY of the
# script (awk blanks the first row's LINE ceiling to "-", leaving 15/14/15) and
# asserts all three halves of the refusal: EMPTY stdout, exit 1, and the
# exact stderr line. The stderr golden is shared with the .ps1 runner, which
# runs the same case against the same file, so the two twins' refusal messages
# are held byte-identical the way the OK/FAIL goldens hold their record streams.
GUARD_GOLD="$GOLD/parity-guard.stderr.txt"
if [ ! -f "$GUARD_GOLD" ]; then
  echo "FAIL parity-guard: missing golden $GUARD_GOLD" >&2; fail=$((fail+1))
else
  # Table rows are the only lines starting at column 0 with skills/ or agents/,
  # so the first three-field one is the first governed row. If a table rewrite
  # ever makes this a no-op the case still fails loud: the unmodified copy
  # prints its OK records and stdout is then not empty.
  awk '!hit && /^(skills|agents)\// && NF == 3 { $2 = "-"; hit = 1 }
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

# --- positional-desync: a moved row carries its own ceilings (issue #428) ---
# Before #428 the governed set was three free-standing parallel arrays, so
# swapping agents/design-reviewer.md and agents/triage-reviewer.md inside FILES
# ALONE kept all three lengths equal, sailed past the parity guard, measured
# each file against the other's ceilings and still exited 0. One row per file
# removes that edit: the smallest unit of the table that names a file carries
# both of its ceilings. This case is the issue's reproduction expressed in the
# new table — swap two ROWS in a COPY of the script — and asserts the stream is
# the same records in a different ORDER, never the same order with reattributed
# ceilings:
#   sorted == at-ceiling golden  the two rows carry DIFFERENT ceilings, so a
#                                reattribution changes a record's text and
#                                survives the sort; a pure reorder does not
#   raw    != at-ceiling golden  the swap actually landed. Without this half a
#                                table rewrite that made the surgery a no-op
#                                would pass vacuously, the same fail-loud
#                                property the parity-guard case relies on.
# THE PAIR MUST DIFFER ON AT LEAST ONE CEILING, or the sorted half asserts
# nothing: two rows carrying identical ceilings produce identical record text,
# so a reattribution would be invisible to it. #428's own pair was
# design-reviewer/triage-reviewer, and it still satisfies that. #464 collapsed
# their LINE column to 120/120 but left them apart on BYTES (16500 vs 17000),
# and the mutation is still caught there. Re-keying the swap to design-reviewer
# (120/16500) against implementer.md (130/15000) is HARDENING, not a repair:
# that pair differs on BOTH axes, so it survives a future ratchet that collapses
# either axis alone. Re-key again only if a pair goes identical on both.
SWAP_GOLD="$GOLD/at-ceiling.txt"
if [ ! -f "$SWAP_GOLD" ]; then
  echo "FAIL positional-desync: missing golden $SWAP_GOLD" >&2; fail=$((fail+1))
else
  awk '{ line[NR] = $0
         if ($1 == "agents/design-reviewer.md") a = NR
         if ($1 == "agents/implementer.md") b = NR }
       END { if (a && b) { t = line[a]; line[a] = line[b]; line[b] = t }
             for (n = 1; n <= NR; n++) print line[n] }' "$SCRIPT" > "$SWAP_SCRIPT"
  swap_out="$(bash "$SWAP_SCRIPT" "$FIX/at-ceiling" 2>&1)"; swap_rc=$?
  swap_want="$(tr -d '\r' < "$SWAP_GOLD")"
  if [ "$swap_rc" -eq 0 ] && [ "$swap_out" != "$swap_want" ] &&
     [ "$(printf '%s\n' "$swap_out" | sort)" = "$(printf '%s\n' "$swap_want" | sort)" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL positional-desync: rc=$swap_rc (want 0); the two swapped rows must reorder the stream, not reattribute ceilings" >&2
    if [ "$swap_out" = "$swap_want" ]; then
      echo "  the row swap was a no-op — re-key it to the current table shape" >&2
    fi
    diff <(printf '%s\n' "$swap_want" | sort) <(printf '%s\n' "$swap_out" | sort) >&2 || true
  fi
fi

# --- malformed-row parity: the other three single-row edits (issue #428) ----
# parity-guard above garbles a LINE ceiling and leaves 15/14/15. Three further
# single-row edits are the ones where the two twins' PARSES can disagree, so
# each is asserted on both twins against the same derived expectation:
#   short   byte column deleted           -> refusal, counts 15/15/14
#   long    surplus fourth column         -> refusal, counts 15/15/14
#   wide    byte ceiling past int32 max   -> clean OK record, exit 0
# `read -r f line_ceiling byte_ceiling` fills column 2 whatever the row's width
# and folds every surplus column into column 3, so short and long both KEEP
# their line ceiling and lose only the byte one. A pwsh parse that gated both
# ceiling adds on an exact 3-column row instead dropped the line ceiling too
# and printed 15/14/14 for these same two tables, diverging from this twin on a
# malformed table. `wide` is the other half: the digit check accepts any number
# of digits and bash arithmetic is 64-bit, so 99999999999 is simply a very
# loose ceiling here, while a pwsh parse casting to [int] threw on it and
# exited 1 with empty stdout.
#
# Both expectations are DERIVED from a committed golden by rewriting only the
# numbers the surgery moves, so a reworded refusal or a retuned ceiling still
# has exactly one place to update and the two twins cannot drift apart. A
# surgery that no-ops fails loud, same as the two cases above: the unmodified
# copy's stream matches neither expectation.
mal_refusal="$(sed 's/CEILINGS(14) and BYTE_CEILINGS(15)/CEILINGS(15) and BYTE_CEILINGS(14)/' "$GUARD_GOLD" | tr -d '\r')"
wide_stream="$(sed 's#/30000#/99999999999#' "$GOLD/at-ceiling.txt" | tr -d '\r')"
for mal in short long wide; do
  case "$mal" in
    short) prog='!hit && /^(skills|agents)\// && NF == 3 { $0 = $1 " " $2; hit = 1 } { print }'
           want_rc=1; want_out=''; want_err="$mal_refusal" ;;
    long)  prog='!hit && /^(skills|agents)\// && NF == 3 { $0 = $0 " 999"; hit = 1 } { print }'
           want_rc=1; want_out=''; want_err="$mal_refusal" ;;
    wide)  prog='!hit && /^(skills|agents)\// && NF == 3 { $0 = $1 " " $2 " 99999999999"; hit = 1 } { print }'
           want_rc=0; want_out="$wide_stream"; want_err='' ;;
  esac
  awk "$prog" "$SCRIPT" > "$MAL_SCRIPT"
  mal_out="$(bash "$MAL_SCRIPT" "$FIX/at-ceiling" 2>"$MAL_ERR")"; mrc=$?
  mal_err="$(tr -d '\r' < "$MAL_ERR")"
  if [ "$mrc" -eq "$want_rc" ] && [ "$mal_out" = "$want_out" ] && [ "$mal_err" = "$want_err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL malformed-row/$mal: rc=$mrc (want $want_rc)" >&2
    diff <(printf 'STDOUT\n%s\nSTDERR\n%s\n' "$want_out" "$want_err") \
         <(printf 'STDOUT\n%s\nSTDERR\n%s\n' "$mal_out" "$mal_err") >&2 || true
  fi
done

echo "check-size-budgets.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
