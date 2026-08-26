#!/usr/bin/env bash
# milestone-driver - runner for the force-subagent.sh hook (issue #571).
# The hook takes no arguments and emits no stdout record, so there is no case
# table to drive: every assertion here is bespoke, against a fresh mktemp
# workspace, exactly like tests/tests-green.test.sh - the sibling hook runner
# this file is modelled on. One runner per script is the layout:
# .project/conventions.md (deterministic, unit-tested helpers).
#
# What it pins: the DENY path. The hook's only prior bash-3.2 coverage was
# .github/workflows/ci.yml (force-subagent - allow path (docs/ is always exempt)),
# which passes whether or not the gate can still block anything at all.
# A `**` sourceGlob is the shape every consumer profile writes,
# and flattening it to a case glob is the one construct in this hook that read
# differently on bash 3.2 than on 5.x, so the deny case leads and an
# unmatched-path allow stands beside it as the non-vacuity control.
#
# Twin parity is asserted on BEHAVIOR (exit codes for the same payloads), never
# on the two hooks' source bytes: the .sh and .ps1 twins legitimately differ in
# source through quote escaping (milestone-feeder #207). Both legs drive the
# same four payloads against the same workspace recipe.
#
# bash-3.2-safe (macOS ships 3.2 and never bash 4+): no `local -n`, no
# mapfile/readarray, no `${var,,}`.
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
HOOK="$ROOT/hooks/force-subagent.sh"
[ -f "$HOOK" ] || { echo "FATAL: missing $HOOK" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
# The escape hatch is inherited by the child and would allow EVERY case
# vacuously, turning a broken gate green. Clear it for this runner's children.
unset CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT

# Hook child interpreter, resolved once. The hooks ship for whatever bash the
# consumer has, and on macOS that is /bin/bash 3.2 - the venue this runner's
# deny case exists to cover. PATH bash is NOT that venue on the macOS CI job:
# .github/workflows/ci.yml (Put a modern bash on PATH for runner children)
# deliberately puts a modern bash ahead of it for the runners' script children
# (#557), which would mask the 3.2 hook child here. So on Darwin the hook child
# is named outright; elsewhere PATH bash is the venue.
BASH_BIN="$(command -v bash)"
if [ "$(uname -s)" = "Darwin" ] && [ -x /bin/bash ]; then BASH_BIN=/bin/bash; fi

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/fs.$$")"; mkdir -p "$TMP"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
ERRFILE="$TMP/err"

ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

# ws - a workspace whose driver.json is the whole ingredient list: an absent
# profile (or absent sourceGlobs) exits 0, so that file is what makes the gate
# live at all. No git repo is needed - this hook never shells out to git.
# `docs/**` sits in sourceGlobs on purpose: it makes the docs/ case assert that
# the always-exempt list wins over a matching glob, instead of passing because
# nothing matched.
ws() {
  local w
  w="$(mktemp -d "$TMP/ws.XXXXXX")"
  mkdir -p "$w/.milestone-config" "$w/skills/foo" "$w/docs"
  printf '%s\n' '{"sourceGlobs":["skills/**","docs/**"]}' \
    > "$w/.milestone-config/driver.json"
  printf '%s' "$w"
}

# run_hook <root> <file_path> [agent_id] - feed the hook the PreToolUse payload
# a Write/Edit carries and capture its exit code. Passing an agent_id models
# the dispatched implementer: the hook's subagent-context allow reads
# agent_id / agent_type / parent_session_id off the payload, not the
# environment. The hook writes only to stderr, so both streams go to one file.
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
# skills/foo/bar.md sits two segments deep, so this asserts the flattened `*`
# still crosses '/' - the whole point of the `**` -> `*` rewrite.
run_hook "$W" "$W/skills/foo/bar.md"
case "$ERR" in *"are blocked"*) SAW_MSG=1 ;; *) SAW_MSG=0 ;; esac
if [ "$RC" -eq 2 ] && [ "$SAW_MSG" -eq 1 ]; then ok; else
  no "deny-doublestar: rc=$RC (want 2) err=[$ERR]"; fi

# ---- allow: a path no sourceGlob matches ------------------------------------
# The non-vacuity control for the case above: a hook that denied everything
# would pass that one and fail this one.
run_hook "$W" "$W/README.md"
if [ "$RC" -eq 0 ]; then ok; else
  no "allow-unmatched: rc=$RC (want 0) err=[$ERR]"; fi

# ---- allow: docs/ is always exempt, ahead of the globs ----------------------
# docs/** IS a sourceGlob in this workspace, so an rc=0 here can only come from
# the always-exempt list running first.
run_hook "$W" "$W/docs/smoke.md"
if [ "$RC" -eq 0 ]; then ok; else
  no "allow-docs: rc=$RC (want 0) err=[$ERR]"; fi

# ---- allow: subagent context on the SAME path the deny case blocked ---------
run_hook "$W" "$W/skills/foo/bar.md" "agent-571"
if [ "$RC" -eq 0 ]; then ok; else
  no "allow-subagent-context: rc=$RC (want 0) err=[$ERR]"; fi

echo "force-subagent.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
