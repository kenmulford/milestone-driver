#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for extract-version.sh (issue #158).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/extract-version.sh"
CASES="$HERE/extract-version.cases.tsv"
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

pass=0; fail=0
# Per-run temp file for captured stderr — mktemp avoids the fixed-path collision
# under concurrent runs and is portable across hosts; trap removes it on exit.
ERRFILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/ev_err.$$")"
trap 'rm -f "$ERRFILE"' EXIT
# Split on TAB preserving empty fields ("IFS=$'\t' read" collapses adjacent tabs,
# silently dropping empty description / expected columns — parity-critical to avoid).
TAB=$'\t'
split_tab() {
  local rest="$1$TAB"; local -n _arr="$2"; _arr=()
  while [ -n "$rest" ]; do _arr+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}
while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in ''|\#*) continue;; esac
  row="${row%$'\r'}"
  split_tab "$row" cols
  name="${cols[0]:-}"; title="${cols[1]:-}"; desc="${cols[2]:-}"
  exp_out="${cols[3]:-}"; exp_err="${cols[4]:-}"
  json="$(jq -n --arg t "$title" --arg d "$desc" '{title:$t, description:$d}')"
  out="$(printf '%s' "$json" | bash "$SCRIPT" 2>"$ERRFILE")"; err="$(cat "$ERRFILE")"
  if [ "$out" = "$exp_out" ] && [ "$err" = "$exp_err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %-22s in[%s|%s] got[out=%s err=%s] want[out=%s err=%s]\n' \
      "$name" "$title" "$desc" "$out" "$err" "$exp_out" "$exp_err" >&2
  fi
done < "$CASES"
echo "extract-version.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
