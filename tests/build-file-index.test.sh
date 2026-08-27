#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for build-file-index.sh (issue #318).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/build-file-index.sh"
CASES="$HERE/build-file-index.cases.tsv"
FIX="$HERE/fixtures/build-file-index"
GOLD="$FIX/_expected"
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
[ -f "$CASES" ] || { echo "FATAL: missing $CASES" >&2; exit 3; }

pass=0; fail=0
ERRFILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bfi_err.$$")"
trap 'rm -f "$ERRFILE"' EXIT
TAB=$'\t'
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}
while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in ''|\#*) continue;; esac
  row="${row%$'\r'}"
  split_tab "$row"
  name="${cols[0]:-}"; fixture="${cols[1]:-}"; input="${cols[2]:-}"
  stdout_file="${cols[3]:-}"; exp_err="${cols[4]:-}"
  if [ -n "$stdout_file" ]; then exp_out="$(tr -d '\r' < "$GOLD/$stdout_file")"; else exp_out=""; fi
  out="$( cd "$FIX/$fixture" && printf '%s' "$input" | bash "$SCRIPT" 2>"$ERRFILE" )"
  err="$(cat "$ERRFILE")"
  if [ "$out" = "$exp_out" ] && [ "$err" = "$exp_err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name" >&2
    diff <(printf '%s\n' "$exp_out") <(printf '%s\n' "$out") >&2 || true
    printf '  stderr got[%s] want[%s]\n' "$err" "$exp_err" >&2
  fi
done < "$CASES"
echo "build-file-index.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
