#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for check-citations.sh (issue #432).
# Each row of check-citations.cases.tsv is: name<TAB>golden<TAB>want_exit.
# <name> is a fixture REPO ROOT under tests/fixtures/check-citations/<name>/ and
# <golden> is its expected stdout under .../_expected/. The runner cd's to the
# repo root and passes the fixture root as a RELATIVE path, so every path in the
# emitted stream is checkout-independent and the golden can be asserted
# literally (same rationale as tests/check-size-budgets.test.sh's per-case
# relative root and tests/resolve-citation.test.sh's per-case cd).
#
# What the nine cases prove, one property each:
#   resolves-once       an anchor matching exactly one line is OK, exit 0
#   zero-matches        a stale anchor is FAIL 0 matches, exit 1
#   two-matches         an anchor matching twice is FAIL 2 matches, exit 1 —
#                       the uniqueness property. Exit status alone would never
#                       catch it: issue #431 landed two anchors that resolved at
#                       exit 0 onto the WRONG line.
#   same-file           a same-file anchor citation reproduces its own anchor,
#                       so the citing line is itself a match and the count is 2.
#                       This is the DOCUMENTED behavior, asserted: the checker
#                       carries no syntactic same-file rule (a basename
#                       comparison flagged 3 cross-file citations as same-file,
#                       because every skill file in this repo is SKILL.md).
#   line-citation       `path:line` and `path:start-end` are UNVERIFIED and do
#                       NOT move the exit code
#   heading-forms       `path#Heading` and `path § Heading` are UNVERIFIED, with
#                       the heading text bounded correctly in all four live
#                       shapes: backtick-terminated, ending in a balanced
#                       parenthetical, a markdown link cut at its `)`, and a
#                       bare prose reference cut at its comma
#   nested-and-missing  paren balance recovers an anchor holding `()` and one
#                       holding a nested parenthetical; a citation whose TARGET
#                       FILE does not exist is FAIL 0 matches
#   prose-not-citation  one line per measured prose lookalike, and the whole
#                       fixture emits NOTHING — a false positive here is the
#                       failure mode that made a naive matcher unusable
#   frozen-excluded     docs/superpowers/**, docs/briefs/**, CHANGELOG.md and
#                       tests/fixtures/** are skipped as SOURCES, each with a
#                       visible EXCLUDED count, while a live file in the same
#                       tree still resolves
#
# Two bespoke cases follow the table: a missing REPO_ROOT (fail-loud on stderr,
# empty stdout, exit 1) and a DEFAULT root (no argument at all, run from inside
# the fixture), which is the one path the table cannot drive and the one where
# `${1:-$PWD}` and the pwsh twin's `(Get-Location).Path` could diverge.
#
# RAW vs NORMALIZED — same rule as tests/resolve-citation.test.sh (RAW vs NORMALIZED — the distinction):
#   * ACTUAL stdout/stderr is captured RAW and compared byte-for-byte, never
#     rebuilt from a line array — otherwise the runner is blind to CRLF creep
#     and to a missing trailing newline, the twin-parity bugs this matrix
#     exists to catch.
#   * The GOLDEN gets ONE normalization, CRLF -> LF, because a CRLF working
#     tree (Windows core.autocrlf) rewrites the committed goldens.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/check-citations.sh"
CASES="$HERE/check-citations.cases.tsv"
FIX="tests/fixtures/check-citations"
GOLD="$ROOT/$FIX/_expected"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
[ -f "$CASES" ] || { echo "FATAL: missing $CASES" >&2; exit 3; }
[ -d "$ROOT/$FIX" ] || { echo "FATAL: missing $ROOT/$FIX" >&2; exit 3; }
BASH_BIN="$(command -v bash)"

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/cct.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
OUTFILE="$TMP/out"
ERRFILE="$TMP/err"

TAB=$'\t'
EXPECT_COLS=3
# split_tab <row> — bash-3.2-safe TAB split preserving empty fields. Copied from
# tests/resolve-citation.test.sh (split_tab <row>).
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}

# slurp_x <path> — a file's contents with a literal 'X' sentinel appended, so
# the caller's $(...) cannot strip the trailing newline off the capture.
slurp_x() { cat "$1"; printf X; }

# read_golden <name> — the named golden, CRLF -> LF only, with the same trailing
# 'X' sentinel slurp_x uses: this function is itself called through $(...), so
# WITHOUT the sentinel the caller's command substitution strips the golden's
# final newline and every case fails on a phantom one-byte diff. A
# named-but-missing golden is FATAL — returning '' would silently turn the case
# into "expect empty stdout", i.e. a green run that asserts nothing.
read_golden() {
  [ -f "$GOLD/$1" ] || { echo "FATAL: case names a missing golden: $GOLD/$1" >&2; exit 3; }
  local g; g="$(slurp_x "$GOLD/$1")"; g="${g%X}"
  printf '%sX' "${g//$'\r\n'/$'\n'}"
}

cd "$ROOT"

case_count=0
while IFS= read -r row || [ -n "$row" ]; do
  row="${row%$'\r'}"
  case "$row" in ''|\#*) continue;; esac
  split_tab "$row"
  if [ "${#cols[@]}" -ne "$EXPECT_COLS" ]; then
    echo "FATAL: row failed to parse (got ${#cols[@]} fields, want $EXPECT_COLS): [$row]" >&2
    exit 1
  fi
  case_count=$((case_count+1))
  name="${cols[0]}"; golden="${cols[1]}"; want_exit="${cols[2]}"

  exp_out="$(read_golden "$golden")"; exp_out="${exp_out%X}"
  "$BASH_BIN" "$SCRIPT" "$FIX/$name" >"$OUTFILE" 2>"$ERRFILE"; rc=$?
  out="$(slurp_x "$OUTFILE")"; out="${out%X}"
  err="$(slurp_x "$ERRFILE")"; err="${err%X}"

  if [ "$rc" -eq "$want_exit" ] && [ "$out" = "$exp_out" ] && [ -z "$err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %s: rc=%s (want %s)\n' "$name" "$rc" "$want_exit" >&2
    # od -c so a CR / missing-newline mismatch is visible in the diff rather
    # than rendering identically to the expected text.
    diff <(printf '%s' "$exp_out" | od -c) <(printf '%s' "$out" | od -c) >&2 || true
    printf '  stderr got[%s] (want empty)\n' "$err" >&2
  fi
done < "$CASES"

if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES — this run tested nothing" >&2
  exit 1
fi

# ---- bespoke: a REPO_ROOT that is not a directory. Fail-loud, and the stderr
# golden is SHARED with the .ps1 runner so the two twins' refusal messages are
# held byte-identical the way the record-stream goldens are.
ROOT_GOLD="$GOLD/missing-root.stderr.txt"
if [ ! -f "$ROOT_GOLD" ]; then
  echo "FATAL: missing golden $ROOT_GOLD" >&2; fail=$((fail+1))
else
  want_err="$(slurp_x "$ROOT_GOLD")"; want_err="${want_err%X}"
  want_err="${want_err//$'\r\n'/$'\n'}"
  "$BASH_BIN" "$SCRIPT" "$FIX/no-such-root" >"$OUTFILE" 2>"$ERRFILE"; rc=$?
  out="$(slurp_x "$OUTFILE")"; out="${out%X}"
  err="$(slurp_x "$ERRFILE")"; err="${err%X}"
  if [ "$rc" -eq 1 ] && [ -z "$out" ] && [ "$err" = "$want_err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL missing-root: rc=%s (want 1) stdout=[%s] (want empty)\n' "$rc" "$out" >&2
    printf '  stderr got[%s] want[%s]\n' "$err" "$want_err" >&2
  fi
fi

# ---- bespoke: NO argument at all, run from inside the fixture root. The table
# always passes a root explicitly, so this is the only exercise of the
# `${1:-$PWD}` default — and the only place it can diverge from the pwsh twin's
# `(Get-Location).Path`.
exp_out="$(read_golden "resolves-once.txt")"; exp_out="${exp_out%X}"
( cd "$ROOT/$FIX/resolves-once" && "$BASH_BIN" "$SCRIPT" >"$OUTFILE" 2>"$ERRFILE" ); rc=$?
out="$(slurp_x "$OUTFILE")"; out="${out%X}"
err="$(slurp_x "$ERRFILE")"; err="${err%X}"
if [ "$rc" -eq 0 ] && [ "$out" = "$exp_out" ] && [ -z "$err" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  printf 'FAIL default-root: rc=%s (want 0)\n' "$rc" >&2
  diff <(printf '%s' "$exp_out" | od -c) <(printf '%s' "$out" | od -c) >&2 || true
  printf '  stderr got[%s] (want empty)\n' "$err" >&2
fi

echo "check-citations.sh: $pass passed, $fail failed (parsed $case_count TSV cases + 2 bespoke)"
[ "$fail" -eq 0 ]
