#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for parse-md-epic-order.sh (issue #266).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/parse-md-epic-order.sh"
CASES="$HERE/parse-md-epic-order.cases.tsv"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

pass=0; fail=0
ERRFILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/pmeo_err.$$")"
trap 'rm -f "$ERRFILE"' EXIT
TAB=$'\t'
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}
decode() { printf '%b' "$1"; }

while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in ''|\#*) continue;; esac
  row="${row%$'\r'}"
  split_tab "$row"
  name="${cols[0]:-}"; body_enc="${cols[1]:-}"
  exp_out_enc="${cols[2]:-}"; exp_err_enc="${cols[3]:-}"; exp_exit="${cols[4]:-0}"
  body="$(decode "$body_enc")"
  exp_out="$(decode "$exp_out_enc")"
  exp_err="$(decode "$exp_err_enc")"
  out="$(printf '%s' "$body" | bash "$SCRIPT" 2>"$ERRFILE")"; got_exit=$?
  err="$(cat "$ERRFILE")"
  if [ "$out" = "$exp_out" ] && [ "$err" = "$exp_err" ] && [ "$got_exit" = "$exp_exit" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %-28s got[exit=%s out=%s err=%s] want[exit=%s out=%s err=%s]\n' \
      "$name" "$got_exit" "$out" "$err" "$exp_exit" "$exp_out" "$exp_err" >&2
  fi
done < "$CASES"
echo "parse-md-epic-order.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
