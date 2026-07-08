#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for build-file-index.sh (issue #318).
# Each row of build-file-index.cases.tsv is: name<TAB>fixture<TAB>input<TAB>
# stdout_file<TAB>expected_stderr. The runner cd's into the per-case synthetic
# fixture root (tests/fixtures/build-file-index/<fixture>/ — a mini repo root) so
# the resolver's cwd-relative path resolution is exercised, pipes <input> on
# stdin, and asserts BOTH stdout and stderr exactly. Multi-line expected stdout
# lives in tests/fixtures/build-file-index/_expected/<stdout_file> (empty column
# => expect empty stdout), mirroring tests/fixtures/check-skill-frontmatter/_expected.
# The .sh and .ps1 runners assert against the SAME golden files (cross-impl parity).
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
# Per-run temp file for captured stderr — mktemp avoids fixed-path collisions
# under concurrent runs and is portable across hosts; trap removes it on exit.
ERRFILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bfi_err.$$")"
trap 'rm -f "$ERRFILE"' EXIT
# Split on TAB preserving empty fields ("IFS=$'\t' read" collapses adjacent tabs,
# silently dropping empty stdout_file / stderr columns — parity-critical to avoid).
TAB=$'\t'
split_tab() {
  local rest="$1$TAB"; local -n _arr="$2"; _arr=()
  while [ -n "$rest" ]; do _arr+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}
while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in ''|\#*) continue;; esac
  row="${row%$'\r'}"
  split_tab "$row" cols
  name="${cols[0]:-}"; fixture="${cols[1]:-}"; input="${cols[2]:-}"
  stdout_file="${cols[3]:-}"; exp_err="${cols[4]:-}"
  # Expected stdout: from the referenced golden file (CR-stripped for a CRLF
  # checkout), or empty when no file is named. $(...) drops the golden's trailing
  # newline, matching the capture of the script's own stdout below.
  if [ -n "$stdout_file" ]; then exp_out="$(tr -d '\r' < "$GOLD/$stdout_file")"; else exp_out=""; fi
  # cd into the fixture root inside a subshell so cwd never leaks between cases;
  # ERRFILE/SCRIPT are absolute so the cd doesn't disturb them.
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
