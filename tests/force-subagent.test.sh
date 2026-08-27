#!/usr/bin/env bash
# milestone-driver - runner for the force-subagent.sh hook (issue #571).
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
HOOK="$ROOT/hooks/force-subagent.sh"
[ -f "$HOOK" ] || { echo "FATAL: missing $HOOK" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
unset CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT

BASH_BIN="$(command -v bash)"
if [ "$(uname -s)" = "Darwin" ] && [ -x /bin/bash ]; then BASH_BIN=/bin/bash; fi

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/fs.$$")"; mkdir -p "$TMP"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
ERRFILE="$TMP/err"

ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

ws() {
  local w globs
  globs="${1:-[\"skills/**\",\"docs/**\"]}"
  w="$(mktemp -d "$TMP/ws.XXXXXX")"
  mkdir -p "$w/.milestone-config" "$w/skills/foo" "$w/docs"
  printf '{"sourceGlobs":%s}\n' "$globs" \
    > "$w/.milestone-config/driver.json"
  printf '%s' "$w"
}

run_hook() {
  if [ -n "${3:-}" ]; then
    jq -n --arg cwd "$1" --arg fp "$2" --arg a "$3" \
      '{tool_input:{file_path:$fp}, cwd:$cwd, agent_id:$a}'
  else
    jq -n --arg cwd "$1" --arg fp "$2" '{tool_input:{file_path:$fp}, cwd:$cwd}'
  fi | "$BASH_BIN" "$HOOK" > "$ERRFILE" 2>&1
  RC=$?
  ERR="$(cat "$ERRFILE")"
}

W="$(ws)"

# ---- deny: a `**` sourceGlob blocks a nested main-thread source edit --------
run_hook "$W" "$W/skills/foo/bar.md"
case "$ERR" in *"are blocked"*) SAW_MSG=1 ;; *) SAW_MSG=0 ;; esac
if [ "$RC" -eq 2 ] && [ "$SAW_MSG" -eq 1 ]; then ok; else
  no "deny-doublestar: rc=$RC (want 2) err=[$ERR]"; fi

# ---- allow: a path no sourceGlob matches ------------------------------------
run_hook "$W" "$W/README.md"
if [ "$RC" -eq 0 ]; then ok; else
  no "allow-unmatched: rc=$RC (want 0) err=[$ERR]"; fi

# ---- allow: docs/ is always exempt, ahead of the globs ----------------------
run_hook "$W" "$W/docs/smoke.md"
if [ "$RC" -eq 0 ]; then ok; else
  no "allow-docs: rc=$RC (want 0) err=[$ERR]"; fi

# ---- allow: subagent context on the SAME path the deny case blocked ---------
run_hook "$W" "$W/skills/foo/bar.md" "agent-571"
if [ "$RC" -eq 0 ]; then ok; else
  no "allow-subagent-context: rc=$RC (want 0) err=[$ERR]"; fi

# ---- deny: a globstar-prefix glob blocks a root-level path -----------------
WG="$(ws '["**/*.md"]')"
run_hook "$WG" "$WG/x.md"
if [ "$RC" -eq 2 ]; then ok; else
  no "globstar-root: rc=$RC (want 2) err=[$ERR]"; fi

echo "force-subagent.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
