#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for resolve-citation.sh (issue #417).
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
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/rc.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
OUTFILE="$TMP/out"
ERRFILE="$TMP/err"

TAB=$'\t'
EXPECT_COLS=7
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}

unescape() { printf '%b' "$1"; }

slurp_x() { cat "$1"; printf X; }

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
  name="${cols[0]}"; file="${cols[1]}"; nargs="${cols[2]}"; anchor_raw="${cols[3]}"
  stdout_file="${cols[4]}"; want_exit="${cols[5]}"; want_stderr_raw="${cols[6]}"

  anchor="$(unescape "$anchor_raw")"
  want_err="$(unescape "${want_stderr_raw//__SCRIPT__/$SCRIPT_NAME}")"
  if [ -n "$want_err" ]; then want_err="$want_err
"; fi
  if [ -n "$stdout_file" ]; then
    [ -f "$GOLD/$stdout_file" ] || { echo "FATAL: case $name names a missing golden: $GOLD/$stdout_file" >&2; exit 3; }
    exp_out="$(slurp_x "$GOLD/$stdout_file")"; exp_out="${exp_out%X}"
    exp_out="${exp_out//$'\r\n'/$'\n'}"
  else
    exp_out=""
  fi

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
    diff <(printf '%s' "$exp_out" | od -c) <(printf '%s' "$out" | od -c) >&2 || true
    printf '  stderr got[%s] want[%s]\n' "$err" "$want_err" >&2
  fi
done < "$CASES"

if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES - this run tested nothing" >&2
  exit 1
fi

# ---- bespoke case: a CRLF input file. This is the one input a committed
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
