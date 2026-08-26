#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for parse-md-epic-order.sh (issue #266).
# Each row's body/expected_stdout/expected_stderr carry real newlines/tabs
# encoded as literal "\n"/"\t" (backslashes as "\\"), decoded here with a single
# printf '%b' pass before piping to the script under test (mirrors the "\n"/"\\"
# TSV field-escaping convention in scripts/ci-preflight-steps.sh (Output (stdout): a deterministic), extended
# with "\t" since this script's own success output is TAB-separated).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/parse-md-epic-order.sh"
CASES="$HERE/parse-md-epic-order.cases.tsv"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

pass=0; fail=0
# Per-run temp file for captured stderr - mktemp avoids the fixed-path collision
# under concurrent runs and is portable across hosts; trap removes it on exit.
ERRFILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/pmeo_err.$$")"
trap 'rm -f "$ERRFILE"' EXIT
TAB=$'\t'
# split_tab <row> - bash-3.2-safe TAB split preserving empty fields ("IFS=$'\t'
# read" collapses adjacent tabs, silently dropping empty expected_stdout /
# expected_stderr columns - parity-critical to avoid). NO `local -n`: that is a
# bash-4.3 nameref, and under the /bin/bash 3.2 macOS ships it is an invalid
# option to `local`, so the array never populates and every case fails. Sets the
# GLOBAL `cols` array directly. Copied from tests/code-review-gate.test.sh (split_tab() {).
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
