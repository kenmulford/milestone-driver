#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for expand-domain-skills.sh (issue #589).
# Each row of expand-domain-skills.cases.tsv is:
#   name<TAB>root<TAB>entries<TAB>want_stdout<TAB>want_stderr
#   root      a directory name under tests/fixtures/expand-domain-skills/, or
#             the sentinel __MISSING__ for a cache root that does not exist.
#             `not-a-dir` is a FILE there - the unreadable-root case.
#             __EMPTY__ drives the EMPTY root; a `~/`-prefixed value is passed
#             VERBATIM, unexpanded, so the script's own tilde resolution is what
#             the row tests. Every child runs with HOME set to a per-run temp
#             COPY of the fixture tree, which makes `~/…` hermetic, keeps every
#             other row untouched, and keeps child writes out of tests/fixtures/.
#   entries   space-separated argv after the root; an empty column means no
#             entries at all. Split under `set -f`: an entry holds a literal
#             `*` and must never be glob-expanded by the runner itself.
#   want_*    `\n` unescapes to a real newline (the TSV escape convention of
#             tests/code-review-gate.cases.tsv). Trailing newlines are stripped
#             from BOTH the actual and the expected stream before comparing, on
#             both legs, so the two runners apply one identical rule.
# The exit code is asserted too: the script is fail-open and ALWAYS exits 0.
# The .sh and .ps1 runners drive the SAME table over the SAME fixture tree -
# that cross-leg agreement is the parity contract for the twin.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/expand-domain-skills.sh"
CASES="$HERE/expand-domain-skills.cases.tsv"
FIX="$HERE/fixtures/expand-domain-skills"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
[ -f "$CASES" ] || { echo "FATAL: missing $CASES" >&2; exit 3; }
[ -d "$FIX" ] || { echo "FATAL: missing $FIX" >&2; exit 3; }
BASH_BIN="$(command -v bash)"

pass=0; fail=0
# Per-run temp dir for the captured streams - mktemp -d avoids a fixed-path
# collision under concurrent runs; trap cleans up.
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/eds.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
OUTFILE="$TMP/out"; ERRFILE="$TMP/err"
# HOME faked to a PER-RUN TEMP COPY of the fixture, NEVER to $FIX itself. Each
# child on the .ps1 leg is a pwsh, and pwsh writes its own
# .cache/powershell/ and .local/share/powershell/ under $HOME: aimed at the
# tracked fixture tree that left the worktree dirty after every run, which
# trips the clean-tree precondition and would sweep pwsh telemetry into the
# repo at commit time. The copy keeps a `~/…` root hermetic and resolvable, and
# dies with $TMP. `"$FIX"/*` skips dot-prefixed entries, matching the .ps1
# runner's wildcard Copy-Item.
HOMEDIR="$TMP/home"; mkdir -p "$HOMEDIR"
cp -R "$FIX"/* "$HOMEDIR"/
TAB=$'\t'

# split_tab <row> - bash-3.2-safe TAB split preserving empty fields ("IFS=$'\t'
# read" collapses adjacent tabs, silently dropping an empty column). NO
# `local -n`: that is a bash-4.3 nameref and an invalid option to `local` under
# the /bin/bash 3.2 macOS ships. Sets the GLOBAL `cols` array directly. Copied
# from tests/extract-version.test.sh (bash-3.2-safe TAB split).
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}
# unesc <s> - `\n` -> newline. Deliberately narrow: a blanket `printf %b` would
# also eat a literal backslash the table may need to express.
unesc() { local s="$1"; s="${s//\\n/$'\n'}"; printf '%s' "$s"; }

while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in ''|\#*) continue;; esac
  row="${row%$'\r'}"
  split_tab "$row"
  name="${cols[0]:-}"; rootname="${cols[1]:-}"; entries="${cols[2]:-}"
  exp_out="$(unesc "${cols[3]:-}")"; exp_err="$(unesc "${cols[4]:-}")"
  case "$rootname" in
    __EMPTY__) root="";;
    '~/'*)     root="$rootname";;
    *)         root="$FIX/$rootname";;
  esac
  set -f; args=($entries); set +f
  if [ "${#args[@]}" -eq 0 ]; then
    HOME="$HOMEDIR" "$BASH_BIN" "$SCRIPT" "$root" >"$OUTFILE" 2>"$ERRFILE"; rc=$?
  else
    HOME="$HOMEDIR" "$BASH_BIN" "$SCRIPT" "$root" "${args[@]}" >"$OUTFILE" 2>"$ERRFILE"; rc=$?
  fi
  out="$(cat "$OUTFILE")"; err="$(cat "$ERRFILE")"
  if [ "$rc" -eq 0 ] && [ "$out" = "$exp_out" ] && [ "$err" = "$exp_err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %-24s root[%s] entries[%s] got[rc=%s out=%s err=%s] want[rc=0 out=%s err=%s]\n' \
      "$name" "$rootname" "$entries" "$rc" "$out" "$err" "$exp_out" "$exp_err" >&2
  fi
done < "$CASES"
echo "expand-domain-skills.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
