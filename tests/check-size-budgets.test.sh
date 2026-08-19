#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for check-size-budgets.sh (issue #295).
# Each fixture is a repo-root under tests/fixtures/check-size-budgets/<case>/
# mirroring the governed files' real relative paths; the fixture files'
# CONTENT is throwaway filler: only their LINE COUNT, BYTE COUNT and WORD
# COUNT are asserted. The expected emitted output lives in
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
# byte-flat-word-over covers the word ceiling added by issue #489, and is the
# case NEITHER of the other two axes can catch: its async-mode.md is the
# at-ceiling tree's file with the padding line's single 1806-character `x` run
# re-cut into 258 six-character tokens of the same total length. Line count is
# unchanged at 40/40 and byte count is unchanged at 4500/4500 — both still
# exactly AT their ceilings and both still passing — while the word count moves
# 469 -> 726 against a 700 ceiling, so only the word column fails it. That is
# the growth shape #399 argued a word count would miss and #489 reversed: token
# density moving under a flat byte total.
#
# Fixture-prose caveat: line-flat-byte-over and byte-flat-word-over are both
# BYTE-FOR-BYTE-SIZED COPIES of the at-ceiling tree, each with one surgical
# edit. Their inherited prose therefore describes the at-ceiling copy, not
# itself: line-flat-byte-over's file says it "stands at exactly 4500 bytes",
# that "both report 4500 here", and that its padding line is "sized so this
# fixture lands on exactly 4500 bytes", while the file it sits in is 4606 bytes
# and is the deliberately-over case; it also names line-flat-byte-over/ as the
# sibling from inside line-flat-byte-over/. The at-ceiling original in turn
# says "only this file's line count and byte count are asserted", which the
# word axis made stale. Do not "fix" any of that prose. The
# byte-for-byte-sized-copy property is what these cases rest on, and rewording
# a byte-pinned fixture moves its totals and forces a golden regeneration for
# no test value.
#
# missing-closure-member covers the CLOSURE records added by issue #491, whose
# ceilings are PRINTED AND NEVER GATED. Its tree is the governed set with
# skills/notices.md deleted — a file that is a closure MEMBER of solve-issue and
# solve-milestone and of neither other closure. So the one deletion asserts both
# halves of the missing-member rule at once: those two records print MISSING
# while setup's and triage's still print a number (the record is per-closure,
# never a global refusal), and the exit code still comes from notices.md's own
# `FAIL ... MISSING` row, not from the CLOSURE lines. Its files are all
# throwaway 1-line/7-byte/1-word filler, including async-mode.md — the
# byte-pinned 40/4500 copy only matters to the three cases above.
#
# parity-guard, positional-desync, empty-closure-table and the three
# malformed-row cases have no fixture tree: the governed set and the closure set
# are tables in the checker's OWN source, so no fixture can reach them. Each of
# those cases builds an edited COPY of the checker instead (garble a column,
# swap two rows, empty the closure table, drop a column, add a surplus column,
# widen a ceiling past int32 max) and asserts what the copy does. See the blocks
# below the loop.
#
# excluded-untouched is the remaining case, and it needs neither: it perturbs a
# COPY of the at-ceiling TREE (a fixture is input, so a committed fixture cannot
# hold both the perturbed and unperturbed state) and asserts the CLOSURE lines
# did not move.
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
  "byte-flat-word-over|1"
  "missing-file|1"
  "missing-closure-member|1"
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
EMPTY_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_empty.$$")"
EMPTY_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_empty_err.$$")"
EXC_TREE="$(mktemp -d 2>/dev/null || { d="${TMPDIR:-/tmp}/csb_exc.$$"; mkdir -p "$d"; echo "$d"; })"
trap 'rm -f "$GUARD_SCRIPT" "$GUARD_ERR" "$SWAP_SCRIPT" "$MAL_SCRIPT" "$MAL_ERR" "$EMPTY_SCRIPT" "$EMPTY_ERR"; rm -rf "$EXC_TREE"' EXIT

# --- parity-guard: the length-parity refusal (issue #399) ------------------
# The checker parses its governed-set table into four index-aligned arrays,
# appending a ceiling only when that column is present AND all digits, so a row
# with a dropped or garbled column leaves the four counts unequal — and the
# checker refuses to run rather than measure a file against a neighbour's
# ceiling. No fixture tree can reach that path (a fixture is input, the table
# is the script's own source), so this case garbles ONE column in a COPY of the
# script (awk blanks the first row's LINE ceiling to "-", leaving 15/14/15/15)
# and asserts all three halves of the refusal: EMPTY stdout, exit 1, and the
# exact stderr line. The stderr golden is shared with the .ps1 runner, which
# runs the same case against the same file, so the two twins' refusal messages
# are held byte-identical the way the OK/FAIL goldens hold their record streams.
GUARD_GOLD="$GOLD/parity-guard.stderr.txt"
if [ ! -f "$GUARD_GOLD" ]; then
  echo "FAIL parity-guard: missing golden $GUARD_GOLD" >&2; fail=$((fail+1))
else
  # Table rows are the only lines starting at column 0 with skills/ or agents/,
  # so the first four-field one is the first governed row. If a table rewrite
  # ever makes this a no-op the case still fails loud: the unmodified copy
  # prints its OK records and stdout is then not empty.
  awk '!hit && /^(skills|agents)\// && NF == 4 { $2 = "-"; hit = 1 }
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
# Before #428 the governed set was free-standing parallel arrays, so swapping
# agents/design-reviewer.md and agents/triage-reviewer.md inside FILES
# ALONE kept every length equal, sailed past the parity guard, measured
# each file against the other's ceilings and still exited 0. One row per file
# removes that edit: the smallest unit of the table that names a file carries
# all of its ceilings. This case is the issue's reproduction expressed in the
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
# (120/16500/2700) against implementer.md (130/15000/2300) is HARDENING, not a
# repair: that pair differs on ALL THREE axes, so it survives a future ratchet
# that collapses any two of them. Re-key again only if a pair goes identical on
# every axis.
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
# parity-guard above garbles a LINE ceiling and leaves 15/14/15/15. Three
# further single-row edits are the ones where the two twins' PARSES can
# disagree, so each is asserted on both twins against the same derived
# expectation:
#   short   word column deleted                 -> refusal, counts 15/15/15/14
#   long    surplus fifth column                -> refusal, counts 15/15/15/14
#   wide    byte AND word ceilings past int32   -> clean OK record, exit 0
# `read -r f line_ceiling byte_ceiling word_ceiling` fills columns 2 and 3
# whatever the row's width and folds every surplus column into column 4, so
# short and long both KEEP their line and byte ceilings and lose only the word
# one. A pwsh parse that gated every ceiling add on an exact 4-column row
# instead dropped the earlier ceilings too and printed 15/14/14/14 for these
# same two tables, diverging from this twin on a malformed table. `wide` is the
# other half: the digit check accepts any number of digits and bash arithmetic
# is 64-bit, so 99999999999 is simply a very loose ceiling here, while a pwsh
# parse casting to [int] threw on it and exited 1 with empty stdout. It widens
# the byte AND word columns in one row, so BOTH [long] lists stay covered by
# the one case.
#
# Both expectations are DERIVED from a committed golden by rewriting only the
# numbers the surgery moves, so a reworded refusal or a retuned ceiling still
# has exactly one place to update and the two twins cannot drift apart. A
# surgery that no-ops fails loud, same as the two cases above: the unmodified
# copy's stream matches neither expectation.
#
# BOTH rewrites are ADDRESSED TO THE ROW THE SURGERY ACTUALLY HITS — the first
# table row, skills/setup/SKILL.md — and not applied file-wide. An unaddressed
# `s#/4300#...#` also matches the LEADING FOUR DIGITS of any other row's
# `/43000`, and milestone #39's ratchet gave skills/solve-issue/SKILL.md a byte
# ceiling of exactly 43000: the expectation then carried a phantom
# `7/999999999990` for a row the surgery never touched, and the case failed on
# a checker that was correct. Keep the address whenever these numbers are
# retuned.
mal_refusal="$(sed 's/CEILINGS(37), BYTE_CEILINGS(38) and WORD_CEILINGS(38)/CEILINGS(38), BYTE_CEILINGS(38) and WORD_CEILINGS(37)/' "$GUARD_GOLD" | tr -d '\r')"
wide_stream="$(sed -e '/skills\/setup\/SKILL.md/ s#/28000#/99999999999#' \
                   -e '/skills\/setup\/SKILL.md/ s#/4000#/99999999999#' \
                   "$GOLD/at-ceiling.txt" | tr -d '\r')"
for mal in short long wide; do
  case "$mal" in
    short) prog='!hit && /^(skills|agents)\// && NF == 4 { $0 = $1 " " $2 " " $3; hit = 1 } { print }'
           want_rc=1; want_out=''; want_err="$mal_refusal" ;;
    long)  prog='!hit && /^(skills|agents)\// && NF == 4 { $0 = $0 " 999"; hit = 1 } { print }'
           want_rc=1; want_out=''; want_err="$mal_refusal" ;;
    wide)  prog='!hit && /^(skills|agents)\// && NF == 4 { $0 = $1 " " $2 " 99999999999 99999999999"; hit = 1 } { print }'
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

# --- empty-closure-table: no closures is a no-op, not an error (issue #491) --
# The CLOSURE records are driven by a second hardcoded table in the checker's
# own source, so — like the governed set — no fixture tree can reach it. Delete
# every row between the closure table's heredoc delimiters in a COPY of the
# checker and the run must degrade to exactly the pre-#491 stream: the same
# per-file records, ZERO CLOSURE records, the same trailing SUMMARY, empty
# stderr, and an exit code still decided by the per-file outcome alone. The
# expectation is DERIVED from the at-ceiling golden by dropping its CLOSURE
# lines, so a retuned per-file ceiling has one place to update.
# Fail-loud on a no-op surgery, same property parity-guard relies on: an
# unedited copy still prints its CLOSURE lines and then does not match.
empty_want="$(tr -d '\r' < "$GOLD/at-ceiling.txt" | grep -v '^CLOSURE	')"
awk '/^done <<.CLOSURE_TABLE.$/ { intbl = 1; print; next }
     /^CLOSURE_TABLE$/          { intbl = 0; print; next }
     intbl                      { next }
                                { print }' "$SCRIPT" > "$EMPTY_SCRIPT"
empty_out="$(bash "$EMPTY_SCRIPT" "$FIX/at-ceiling" 2>"$EMPTY_ERR")"; erc=$?
empty_err="$(tr -d '\r' < "$EMPTY_ERR")"
if [ "$erc" -eq 0 ] && [ "$empty_out" = "$empty_want" ] && [ -z "$empty_err" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  echo "FAIL empty-closure-table: rc=$erc (want 0), stderr=[$empty_err] (want empty)" >&2
  diff <(printf '%s\n' "$empty_want") <(printf '%s\n' "$empty_out") >&2 || true
fi

# --- excluded-untouched: the six branch-gated files are outside every closure
# (issue #491) ---------------------------------------------------------------
# A CLOSURE sum counts ONLY the files a skill read-directs on EVERY run. The
# six reference docs that sit behind an observable branch — parallel-waves.md
# (parallel mode), milestone-granularity.md (`integrationGranularity:
# "milestone"`), trello-sync.md (`integrations.trello`), async-mode.md
# (retired, inert), md-epic-fanout.md (the `md-epic` label) and
# blocker-resolver-dispatch.md (>=1 Blocker gap on a MISS-set issue) — are NOT
# part of any closure, and the executable statement of that is: perturb all six
# and every CLOSURE line is byte-identical. A committed fixture cannot hold
# both the perturbed and unperturbed state of the same tree, so this copies
# at-ceiling and edits the copy. rc is deliberately unasserted: async-mode.md
# sits at exactly 4500/4500 bytes, so appending to it fails its byte column, which
# is beside the point this case makes.
#   CLOSURE lines == at-ceiling golden's   no excluded file reached a sum
#   the rest       != at-ceiling golden's  the perturbation actually landed,
#                                          so a no-op cp/append cannot pass this
#                                          case vacuously
cp -R "$FIX/at-ceiling/." "$EXC_TREE/"
for x in skills/solve-milestone/parallel-waves.md \
         skills/solve-milestone/milestone-granularity.md \
         skills/solve-milestone/trello-sync.md \
         skills/solve-issue/async-mode.md \
         skills/solve-issue/md-epic-fanout.md \
         skills/triage/blocker-resolver-dispatch.md; do
  printf 'excluded branch gated padding words\n' >> "$EXC_TREE/$x"
done
exc_out="$(bash "$SCRIPT" "$EXC_TREE" 2>&1)"
exc_gold="$(tr -d '\r' < "$GOLD/at-ceiling.txt")"
exc_got_cl="$(printf '%s\n' "$exc_out"  | grep '^CLOSURE	' || true)"
exc_want_cl="$(printf '%s\n' "$exc_gold" | grep '^CLOSURE	' || true)"
exc_got_rest="$(printf '%s\n' "$exc_out"  | grep -v '^CLOSURE	' || true)"
exc_want_rest="$(printf '%s\n' "$exc_gold" | grep -v '^CLOSURE	' || true)"
if [ -n "$exc_want_cl" ] && [ "$exc_got_cl" = "$exc_want_cl" ] && [ "$exc_got_rest" != "$exc_want_rest" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  echo "FAIL excluded-untouched: editing a branch-gated file must leave every CLOSURE line unchanged" >&2
  if [ "$exc_got_rest" = "$exc_want_rest" ]; then
    echo "  the perturbation was a no-op — re-key it to the current fixture tree" >&2
  fi
  diff <(printf '%s\n' "$exc_want_cl") <(printf '%s\n' "$exc_got_cl") >&2 || true
fi

echo "check-size-budgets.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
