#!/usr/bin/env bash
# milestone-driver - runner for the dispatch-cap.sh hook. Bespoke cases against
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
HOOK="$ROOT/hooks/dispatch-cap.sh"
[ -f "$HOOK" ] || { echo "FATAL: missing $HOOK" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 3; }
unset CLAUDE_HOOK_DISABLE_DISPATCH_CAP

BASH_BIN="$(command -v bash)"
if [ "$(uname -s)" = "Darwin" ] && [ -x /bin/bash ]; then BASH_BIN=/bin/bash; fi

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/dc.$$")"; mkdir -p "$TMP"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
ERRFILE="$TMP/err"

ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

IMPL='milestone-driver:implementer'

ws() {
  local w branch profile
  branch="${1:-issue/7-x}"
  profile="${2:-{\"sourceGlobs\":[\"src/**\"]\}}"
  w="$(mktemp -d "$TMP/ws.XXXXXX")"
  git -C "$w" init -q >/dev/null 2>&1
  git -C "$w" config core.hooksPath "$w/.git/no-such-hooks"
  git -C "$w" config commit.gpgsign false
  git -C "$w" config user.email 'tests@milestone-driver.invalid'
  git -C "$w" config user.name 'dispatch-cap tests'
  printf 'seed\n' > "$w/README.md"
  git -C "$w" add -A >/dev/null 2>&1
  git -C "$w" commit -q -m base >/dev/null 2>&1
  git -C "$w" checkout -q -b "$branch" >/dev/null 2>&1
  if [ "$profile" != '-' ]; then
    mkdir -p "$w/.milestone-config"
    printf '%s\n' "$profile" > "$w/.milestone-config/driver.json"
  fi
  printf '%s' "$w"
}

run_hook() {
  local root="$1" tool="$2" who="$3" text="$4" agent="${5:-}"
  if [ "$tool" = "Skill" ]; then
    jq -n --arg cwd "$root" --arg t "$tool" --arg s "$who" --arg a "$text" --arg ag "$agent" \
      '{tool_name:$t, tool_input:{skill:$s, args:$a}, cwd:$cwd} + (if $ag != "" then {agent_id:$ag} else {} end)'
  else
    jq -n --arg cwd "$root" --arg t "$tool" --arg s "$who" --arg a "$text" --arg ag "$agent" \
      '{tool_name:$t, tool_input:{subagent_type:$s, prompt:$a}, cwd:$cwd} + (if $ag != "" then {agent_id:$ag} else {} end)'
  fi | "$BASH_BIN" "$HOOK" > "$ERRFILE" 2>&1
  RC=$?
  ERR="$(cat "$ERRFILE")"
}

expect() {
  if [ "$RC" -eq "$2" ]; then ok; else no "$1: rc=$RC (want $2) err=[$ERR]"; fi
}

# ---- implementer: 3 dispatches allowed, the 4th denied --------------------
W="$(ws)"
for i in 1 2 3; do
  run_hook "$W" Agent "$IMPL" "Build issue #7"; expect "implementer-allow-$i" 0
done
run_hook "$W" Agent "$IMPL" "Build issue #7"; expect "implementer-deny-4th" 2
case "$ERR" in *"dispatch cap"*"implementer dispatch 4 of at most 3 for issue 7"*) ok ;;
  *) no "implementer-deny-message: err=[$ERR]" ;; esac

# ---- the counter file -------------------------------------------------------
f="$W/.git/milestone-driver/dispatch-cap/implementer-7"
if [ -f "$f" ] && [ "$(cut -d' ' -f2 "$f")" = "3" ]; then ok; else
  no "counter-file: [$f] $(cat "$f" 2>/dev/null)"; fi

# ---- review: its own counter, 3 allowed, the 4th denied --------------------
for i in 1 2 3; do
  run_hook "$W" Skill code-review ""; expect "review-allow-$i" 0
done
run_hook "$W" Skill code-review ""; expect "review-deny-4th" 2
run_hook "$W" Skill code-review:code-review ""; expect "review-deny-namespaced" 2

# ---- never counted: other agents and other skills, even on a capped key ---
run_hook "$W" Agent general-purpose "Review #7"; expect "allow-other-agent" 0
run_hook "$W" Skill superpowers:brainstorming ""; expect "allow-other-skill" 0
run_hook "$W" Bash "" ""; expect "allow-other-tool" 0

# ---- allow: subagent context on the capped key ----------------------------
run_hook "$W" Agent "$IMPL" "Build issue #7" "agent-1"; expect "allow-subagent-context" 0

# ---- allow: the escape hatch on the capped key -----------------------------
jq -n --arg cwd "$W" --arg s "$IMPL" '{tool_name:"Agent", tool_input:{subagent_type:$s, prompt:"x"}, cwd:$cwd}' > "$TMP/payload.json"
CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1 "$BASH_BIN" "$HOOK" < "$TMP/payload.json" > "$ERRFILE" 2>&1
RC=$?; ERR="$(cat "$ERRFILE")"; expect "allow-escape-hatch" 0

# ---- a moved HEAD resets the budget ----------------------------------------
printf 'more\n' >> "$W/README.md"
git -C "$W" commit -q -am step >/dev/null 2>&1
run_hook "$W" Agent "$IMPL" "Build issue #7"; expect "reset-on-new-head" 0

# ---- allow: no profile means not a milestone-driver repo -------------------
WN="$(ws issue/7-x -)"
for i in 1 2 3 4; do run_hook "$WN" Agent "$IMPL" "x"; done
expect "allow-no-profile" 0

# ---- legacy Task tool name is counted like Agent ---------------------------
WT="$(ws)"
for i in 1 2 3; do run_hook "$WT" Task "$IMPL" "x"; done
run_hook "$WT" Task "$IMPL" "x"; expect "task-deny-4th" 2

# ---- a profile's implementerAgent override is what gets counted ------------
WC="$(ws issue/7-x '{"implementerAgent":"acme:builder"}')"
for i in 1 2 3 4; do run_hook "$WC" Agent "$IMPL" "x"; done
expect "custom-agent-default-name-uncounted" 0
for i in 1 2 3; do run_hook "$WC" Agent acme:builder "x"; done
run_hook "$WC" Agent acme:builder "x"; expect "custom-agent-deny-4th" 2

# ---- off an issue branch (parallel mode), the brief names the issue --------
WP="$(ws develop)"
for i in 1 2 3; do run_hook "$WP" Agent "$IMPL" "Issue #11: add the thing. Depends on #3."; done
run_hook "$WP" Agent "$IMPL" "Issue #11: add the thing. Depends on #3."; expect "brief-key-deny-4th" 2
case "$ERR" in *"for issue 11 "*) ok ;; *) no "brief-key-is-11: err=[$ERR]" ;; esac
run_hook "$WP" Agent "$IMPL" "issue 12 - the other thing"; expect "brief-key-other-issue-allowed" 0
[ -f "$WP/.git/milestone-driver/dispatch-cap/implementer-12" ] && ok || no "brief-key-12-counter"
run_hook "$WP" Skill code-review ""; expect "branch-key-fallback" 0
[ -f "$WP/.git/milestone-driver/dispatch-cap/review-develop" ] && ok || no "branch-key-counter"
for i in 1 2; do run_hook "$WP" Skill code-review ""; done
run_hook "$WP" Skill code-review ""; expect "branch-key-deny-4th" 2
case "$ERR" in *"for branch develop "*) ok ;; *) no "branch-key-message: err=[$ERR]" ;; esac

# ---- a malformed profile still gates, with the default implementer name -----
WM="$(ws issue/7-x '{ not json')"
for i in 1 2 3; do run_hook "$WM" Agent "$IMPL" "x"; done
run_hook "$WM" Agent "$IMPL" "x"; expect "malformed-profile-deny-4th" 2

echo "dispatch-cap.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
