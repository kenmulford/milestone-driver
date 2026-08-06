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

# ---- bespoke: GENERATED byte-level trees ------------------------------------
# These inputs CANNOT live in a git-tracked fixture. .gitattributes pins
# `tests/fixtures/** text eol=lf`, so a committed CRLF file is renormalized on
# checkout and a committed UTF-16 file would be corrupted by that same
# conversion; a FIFO, a symlink target and a chmod-000 directory are not
# git-storable at all. They are built here byte for byte, and the .ps1 runner
# builds the IDENTICAL trees and asserts the SAME committed goldens — which is
# what holds the two legs' decoders and walks together. Before these cases the
# fixture set had zero CRLF files, zero BOMs, zero files missing a final
# newline, zero non-UTF-8 bytes, zero symlinks and zero non-regular files, and
# that blind spot is exactly why the golden matrix stayed green through four
# twin-splitting defects.

# build_gen_bytes <base> — <base>/gen is the repo root; <base>/outside.md sits
# OUTSIDE it, which is what the containment case reaches for.
#   crlf.md       a trailing CR must not shift a line number or a match
#   bom.md        a UTF-8 BOM is three ORDINARY BYTES; neither leg may strip it
#   nonewline.md  a final line with no terminator still counts
#   highbyte.md   a raw 0xE9 inside the anchor must reach stdout AS 0xE9 (the
#                 pwsh leg used to emit EF BF BD, a U+FFFD substitution)
#   utf16.md      a UTF-16 target. The pwsh leg used to DECODE it and report OK
#                 while this leg reported FAIL 0 matches: same tree, one leg red
#                 and one green
#   ../outside.md containment: an anchor may not read a file next to the checkout
# cite_line <n> <path> <anchor> — emits "<n> `<path> (<anchor>)`" plus a
# newline. The citation is ASSEMBLED from arguments and never spelled out
# literally anywhere in this file, because tests/ IS SCANNED by the gate under
# test: a literal would be a real citation here, resolved against a fixture path
# that does not exist in this repo, and the repo-wide run would fail on its own
# test runner. Measured: spelling them out cost 18 FAIL records.
cite_line() { printf '%s `%s (%s)`\n' "$1" "$2" "$3"; }

build_gen_bytes() {
  b="$1"
  mkdir -p "$b/gen/docs" "$b/gen/src"
  e9="$(printf '\351')"
  printf 'secret string\n' > "$b/outside.md"
  {
    printf '# Citing\n\n'
    cite_line 1 'src/crlf.md'      'crlf anchor here'
    cite_line 2 'src/bom.md'       'bom anchor'
    cite_line 3 'src/nonewline.md' 'tail anchor'
    cite_line 4 'src/highbyte.md'  "caf$e9 anchor"
    cite_line 5 'src/utf16.md'     'utf16 anchor'
    cite_line 6 '../outside.md'    'secret string'
  } > "$b/gen/docs/citing.md"
  printf '# Crlf\r\ncrlf anchor here\r\n' > "$b/gen/src/crlf.md"
  printf '\357\273\277bom anchor on line one\n' > "$b/gen/src/bom.md"
  printf '# Tail\ntail anchor' > "$b/gen/src/nonewline.md"
  printf '# High\ncaf\351 anchor lives here\n' > "$b/gen/src/highbyte.md"
  printf '\377\376u\000t\000f\0001\0006\000 \000a\000n\000c\000h\000o\000r\000\n\000' > "$b/gen/src/utf16.md"
}

# build_gen_unix <base> — non-regular entries and an unreadable directory.
# Unix-only: a FIFO and an unprivileged symlink do not exist on Windows, so the
# case reports SKIPPED there rather than failing. CI runs both legs on Linux.
#   link.md    a symlink is LISTED BY NEITHER leg, so citing it is 0 matches
#   pipe.md    a FIFO is listed but NEVER OPENED. Opening one blocks forever:
#              this leg finished while the pwsh leg hung to a CI timeout with
#              zero output
#   locked/    a chmod-000 directory must be skipped, not fatal. It holds a
#              CITATION-FREE file on purpose, so the golden is identical whether
#              or not the chmod bit takes effect (it does not when the suite
#              runs as root), while a leg that ABORTS on it still fails loudly
build_gen_unix() {
  b="$1"
  mkdir -p "$b/gen/docs" "$b/gen/src" "$b/gen/locked"
  {
    printf '# Citing\n\n'
    cite_line 1 'src/real.md' 'real anchor'
    cite_line 2 'src/link.md' 'real anchor'
    cite_line 3 'src/pipe.md' 'any anchor'
  } > "$b/gen/docs/citing.md"
  printf '# Real\nreal anchor lives here\n' > "$b/gen/src/real.md"
  printf '# Plain\nNothing worth citing.\n' > "$b/gen/locked/plain.md"
  ln -s real.md "$b/gen/src/link.md" || return 1
  mkfifo "$b/gen/src/pipe.md" || return 1
  chmod 000 "$b/gen/locked" || return 1
  return 0
}

# run_generated <name> <root> <golden> <want_exit>
run_generated() {
  gname="$1"; groot="$2"; ggold="$3"; gwant="$4"
  gexp="$(read_golden "$ggold")"; gexp="${gexp%X}"
  "$BASH_BIN" "$SCRIPT" "$groot" >"$OUTFILE" 2>"$ERRFILE"; grc=$?
  gout="$(slurp_x "$OUTFILE")"; gout="${gout%X}"
  gerr="$(slurp_x "$ERRFILE")"; gerr="${gerr%X}"
  if [ "$grc" -eq "$gwant" ] && [ "$gout" = "$gexp" ] && [ -z "$gerr" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %s: rc=%s (want %s)\n' "$gname" "$grc" "$gwant" >&2
    diff <(printf '%s' "$gexp" | od -c) <(printf '%s' "$gout" | od -c) >&2 || true
    printf '  stderr got[%s] (want empty)\n' "$gerr" >&2
  fi
}

build_gen_bytes "$TMP"
run_generated gen-bytes "$TMP/gen" gen-bytes.txt 1

UNIXTMP="$TMP/u"
mkdir -p "$UNIXTMP"
gen_unix_skipped=0
if build_gen_unix "$UNIXTMP" 2>/dev/null; then
  run_generated gen-unix "$UNIXTMP/gen" gen-unix.txt 1
  chmod 755 "$UNIXTMP/gen/locked" 2>/dev/null || true
else
  gen_unix_skipped=1
  chmod 755 "$UNIXTMP/gen/locked" 2>/dev/null || true
fi

if [ "$gen_unix_skipped" -eq 1 ]; then
  echo "check-citations.sh: $pass passed, $fail failed (parsed $case_count TSV cases + 3 bespoke, gen-unix SKIPPED on this platform)"
else
  echo "check-citations.sh: $pass passed, $fail failed (parsed $case_count TSV cases + 4 bespoke)"
fi
[ "$fail" -eq 0 ]
