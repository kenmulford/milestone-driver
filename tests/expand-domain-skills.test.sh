#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for expand-domain-skills.sh (issue #589).
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
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/eds.$$")"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
OUTFILE="$TMP/out"; ERRFILE="$TMP/err"
HOMEDIR="$TMP/home"; mkdir -p "$HOMEDIR"
cp -R "$FIX"/* "$HOMEDIR"/
TAB=$'\t'

split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}
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
