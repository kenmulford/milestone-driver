#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for resolve-citation.sh (issue #417).
# Each row of resolve-citation.cases.tsv is: name<TAB>file<TAB>nargs<TAB>anchor
# <TAB>stdout_file<TAB>want_exit<TAB>want_stderr. The runner cd's into
# tests/fixtures/resolve-citation/ and passes <file> as a RELATIVE path, so the
# path text the resolver echoes into its stderr is checkout-independent and can
# be asserted literally (mirrors tests/build-file-index.test.sh's per-case cd,
# and tests/check-skill-frontmatter.test.ps1's run-from-a-fixed-root rationale).
# It asserts the exit code, stdout, AND stderr exactly.
#   nargs        how many arguments to pass: 0, 1 (<file> only), 2 (<file>
#                <anchor> — <anchor> may be the empty string), or 3 (a trailing
#                junk argument). This is how the bad-usage exits are driven.
#   anchor       \n and \t are unescaped to a real newline / TAB (same TSV
#                escape convention as tests/code-review-gate.cases.tsv); a
#                literal backslash is therefore not expressible in this column.
#   stdout_file  names a golden under fixtures/resolve-citation/_expected/;
#                an empty column means "expect EMPTY stdout" (fail-closed).
#                A NAMED-BUT-MISSING golden is FATAL, never a silent
#                degradation to "expect empty".
#   want_stderr  __SCRIPT__ expands to this leg's script filename, so the one
#                table drives both legs while each still asserts its OWN usage
#                line (placeholder convention from code-review-gate.cases.tsv's
#                __BODYFILE_REL__). A non-empty value is compared WITH its
#                single trailing newline.
#
# RAW vs NORMALIZED — the distinction this runner turns on:
#   * The ACTUAL stdout/stderr of the script under test is captured RAW and
#     compared byte-for-byte. It is never CR-stripped and never rebuilt from a
#     line array: doing either would make the runner blind to CRLF creep and to
#     a missing trailing newline, which are precisely the twin-parity bugs the
#     golden matrix exists to catch.
#   * The GOLDEN file gets ONE normalization, CRLF -> LF, because a CRLF working
#     tree (Windows core.autocrlf) rewrites the committed goldens. That
#     replacement is deliberately \r\n-scoped rather than a blanket \r strip, so
#     a golden that legitimately contains a LONE CR (lone-cr-in-text.out) keeps
#     it.
# The .sh and .ps1 runners assert against the SAME cases table and the SAME
# golden files (cross-impl parity). A trailing, non-TSV case proves the CRLF
# parity path, which no committed fixture can express — see its comment below.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/resolve-citation.sh"
CASES="$HERE/resolve-citation.cases.tsv"
FIX="$HERE/fixtures/resolve-citation"
GOLD="$FIX/_expected"
SCRIPT_NAME="resolve-citation.sh"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
[ -f "$CASES" ] || { echo "FATAL: missing $CASES" >&2; exit 3; }
[ -d "$FIX" ] || { echo "FATAL: missing $FIX" >&2; exit 3; }
BASH_BIN="$(command -v bash)"

pass=0; fail=0
# Per-run temp dir for the captured streams + the generated CRLF fixture —
# mktemp -d avoids fixed-path collisions under concurrent runs; trap cleans up.
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/rc.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
OUTFILE="$TMP/out"
ERRFILE="$TMP/err"

TAB=$'\t'
EXPECT_COLS=7
# split_tab <row> — bash-3.2-safe TAB split preserving empty fields ("IFS=$'\t'
# read" collapses adjacent tabs, silently dropping the empty anchor / stdout_file
# / stderr columns). NO mapfile/readarray (bash-4+ builtins; macOS ships 3.2).
# Sets the GLOBAL `cols` array directly. Copied from tests/code-review-gate.test.sh (split_tab() {).
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}

# unescape <str> — turns the TSV's literal \n / \t 2-char sequences into real
# characters, mirroring tests/code-review-gate.test.sh (unescape() {).
unescape() { printf '%b' "$1"; }

# slurp_x <path> — a file's contents with a literal 'X' sentinel appended.
# Callers do out="$(slurp_x f)"; out="${out%X}" — the sentinel is what survives
# command substitution's trailing-newline stripping, so the capture stays RAW
# down to the final byte. (Appending it INSIDE the function would not work: the
# caller's own $(...) would strip the newline right back off.)
slurp_x() { cat "$1"; printf X; }

case_count=0
while IFS= read -r row || [ -n "$row" ]; do
  # Strip the CRLF checkout's CR FIRST, so the blank/comment skip below sees the
  # same row text the .ps1 leg does. Skipping before the strip made a blank row
  # look like a lone "\r" on this leg and a blank row on the other.
  row="${row%$'\r'}"
  case "$row" in ''|\#*) continue;; esac
  split_tab "$row"
  # Self-guard: a row that doesn't parse into exactly the expected column count
  # is a runner bug (or a corrupt fixture), not a silently-defaulted pass.
  if [ "${#cols[@]}" -ne "$EXPECT_COLS" ]; then
    echo "FATAL: row failed to parse (got ${#cols[@]} fields, want $EXPECT_COLS): [$row]" >&2
    exit 1
  fi
  case_count=$((case_count+1))
  name="${cols[0]}"; file="${cols[1]}"; nargs="${cols[2]}"; anchor_raw="${cols[3]}"
  stdout_file="${cols[4]}"; want_exit="${cols[5]}"; want_stderr_raw="${cols[6]}"

  anchor="$(unescape "$anchor_raw")"
  # Expected stderr carries its single trailing newline when non-empty, so a
  # host that emitted CRLF there (or dropped the newline) fails.
  want_err="$(unescape "${want_stderr_raw//__SCRIPT__/$SCRIPT_NAME}")"
  if [ -n "$want_err" ]; then want_err="$want_err
"; fi
  # Expected stdout: the named golden, CRLF->LF only (see RAW vs NORMALIZED).
  if [ -n "$stdout_file" ]; then
    [ -f "$GOLD/$stdout_file" ] || { echo "FATAL: case $name names a missing golden: $GOLD/$stdout_file" >&2; exit 3; }
    exp_out="$(slurp_x "$GOLD/$stdout_file")"; exp_out="${exp_out%X}"
    exp_out="${exp_out//$'\r\n'/$'\n'}"
  else
    exp_out=""
  fi

  # cd into the fixture root inside a subshell so cwd never leaks between cases;
  # OUTFILE/ERRFILE/SCRIPT are absolute so the cd doesn't disturb them. The four
  # arms are spelled out rather than built from an array: `"${arr[@]}"` on an
  # EMPTY array is an unbound-variable error under `set -u` on bash 3.2.
  case "$nargs" in
    0) ( cd "$FIX" && "$BASH_BIN" "$SCRIPT" >"$OUTFILE" 2>"$ERRFILE" ); rc=$? ;;
    1) ( cd "$FIX" && "$BASH_BIN" "$SCRIPT" "$file" >"$OUTFILE" 2>"$ERRFILE" ); rc=$? ;;
    2) ( cd "$FIX" && "$BASH_BIN" "$SCRIPT" "$file" "$anchor" >"$OUTFILE" 2>"$ERRFILE" ); rc=$? ;;
    3) ( cd "$FIX" && "$BASH_BIN" "$SCRIPT" "$file" "$anchor" extra >"$OUTFILE" 2>"$ERRFILE" ); rc=$? ;;
    *) echo "FATAL: unsupported nargs '$nargs' in case $name" >&2; exit 1 ;;
  esac
  out="$(slurp_x "$OUTFILE")"; out="${out%X}"
  err="$(slurp_x "$ERRFILE")"; err="${err%X}"

  if [ "$rc" -eq "$want_exit" ] && [ "$out" = "$exp_out" ] && [ "$err" = "$want_err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %s: rc=%s (want %s)\n' "$name" "$rc" "$want_exit" >&2
    # od -c so a CR / missing-newline mismatch is visible in the diff rather
    # than rendering identically to the expected text.
    diff <(printf '%s' "$exp_out" | od -c) <(printf '%s' "$out" | od -c) >&2 || true
    printf '  stderr got[%s] want[%s]\n' "$err" "$want_err" >&2
  fi
done < "$CASES"

# Self-guard: zero parsed cases means every row was skipped or the table is
# empty — the suite would otherwise report "0 passed, 0 failed" as a clean,
# misleadingly-green exit.
if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES — this run tested nothing" >&2
  exit 1
fi

# ---- bespoke case: a CRLF input file. This is the one input a committed
# fixture cannot express (git renormalizes line endings on a Windows checkout),
# and it is exactly where the two legs can silently diverge on <text>.
# Generated at run time instead.
CRLF="$TMP/crlf.md"
printf 'alpha line\r\nbeta anchor here\r\ngamma line\r\n' > "$CRLF"
"$BASH_BIN" "$SCRIPT" "$CRLF" "beta anchor" >"$OUTFILE" 2>"$ERRFILE"; rc=$?
out="$(slurp_x "$OUTFILE")"; out="${out%X}"
err="$(slurp_x "$ERRFILE")"; err="${err%X}"
want="PRIMARY${TAB}2${TAB}beta anchor here
"
if [ "$rc" -eq 0 ] && [ "$out" = "$want" ] && [ -z "$err" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  printf 'FAIL crlf_no_stray_cr: rc=%s (want 0) out=[%s] want=[%s] err=[%s]\n' \
    "$rc" "$out" "$want" "$err" >&2
fi

echo "resolve-citation.sh: $pass passed, $fail failed (parsed $case_count TSV cases + 1 bespoke)"
[ "$fail" -eq 0 ]
