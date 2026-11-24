#!/usr/bin/env bash
# milestone-driver - dispatch-cap gate (Claude PreToolUse: Agent|Task|Skill, Codex: spawn_agent)
#
# Per issue: at most 3 `/code-review` runs (Skill `code-review` / `*:code-review`)
# and 3 implementer dispatches (Agent/Task whose subagent_type is the profile's
# implementerAgent), the caps skills/review-depth.md states, plus 2 planner
# dispatches (subagent_type `milestone-driver:planner`, fixed, not profile-read).
# Main thread only. On `issue/*`, `wave/*` or `milestone-*`, a main-thread Agent/Task
# dispatch with subagent_type general-purpose, claude or fork (any case) or none is denied
# (each runs on the parent's model and no cap counts it); every other named agent is not
# counted. Codex spawn_agent is never denied.
# Key: `milestone-<n>` for an implementer or planner brief that opens, after
# whitespace, with `Milestone-End-Fix: <n>` (Codex: task_name `<agent>_milestone_<n>_<attempt>`)
# on branch `milestone-<n>-*` (3 implementer + 1 planner
# per milestone end), else branch `issue/<n>-*`, else `issue <n>` / `#<n>` in the
# brief, else the branch name. Counter: <git-common-dir>/milestone-driver/dispatch-cap/<kind>-<key>
# holds `<HEAD> <count>`; a moved HEAD or a park (`scripts/reset-dispatch-cap`)
# resets it. The `milestone-<n>` counter holds `<branch> <count>` instead: a fix
# commit moves HEAD, so only the milestone-end Halt or the branch delete
# (`scripts/reset-dispatch-cap`) resets it, and its deny names that Halt.
# Deny: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON). Escape: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1.
# Fail-open on missing jq/git, no repo, or unparsed stdin. bash-3.2-safe (the
# =~ patterns sit in variables: 3.2 mis-parses a quoted inline regex).

[ "${CLAUDE_HOOK_DISABLE_DISPATCH_CAP:-}" = "1" ] && exit 0

input="$(cat)"
hook_dir="${BASH_SOURCE[0]%[/\\]*}"; [ "$hook_dir" = "${BASH_SOURCE[0]}" ] && hook_dir=.   # builtin: PATH may lack dirname
. "$hook_dir/hook-deny.sh"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

for field in agent_id agent_type parent_session_id; do
  val="$(printf '%s' "$input" | jq -r ".${field} // empty" 2>/dev/null | tr -d '\r')"
  [ -n "$val" ] && exit 0
done

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null | tr -d '\r')"
[ -n "$tool" ] || exit 0

project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"

profile="$project_dir/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0
implementer="$(jq -r '.implementerAgent // empty' "$profile" 2>/dev/null | tr -d '\r')"
[ -n "$implementer" ] || implementer='milestone-driver:implementer'

# A Skill is matched on the name after its last `:`, so the `code-review` row
# also covers `*:code-review`; Task is the legacy name of Agent.
main_agent=''; branch=''
case "$tool" in
  Skill)
    who="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null | tr -d '\r')"
    who="${who##*:}"; field='args' ;;
  Agent|Task)
    tool='Agent'; field='prompt'; main_agent=1   # the raw name: Codex spawn_agent also rewrites tool to Agent
    who="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null | tr -d '\r')" ;;
  *spawn_agent)
    # Codex encrypts the spawn message, so runtime-codex.md names the child
    # `<agent>_issue_<n>_<attempt>` or `<agent>_milestone_<n>_<attempt>` in task_name;
    # the bare name maps back to the row.
    tool='Agent'; field='task_name'
    who="$(printf '%s' "$input" | jq -r '.tool_input.task_name // empty' 2>/dev/null | tr -d '\r')"
    who="${who##*/}"; who="${who%%_issue*}"; who="${who%%_milestone*}"
    if [ "$who" = "${implementer##*:}" ]; then who="$implementer"; else who="milestone-driver:$who"; fi ;;
  *) exit 0 ;;
esac

# Dispatch contract: runs before the table, so a denied dispatch never reads or writes a counter.
# A failing branch read or a detached HEAD (`HEAD`) allows; the glob is a `case`, not an inline =~ (bash 3.2).
catch_all=''
[ -n "$main_agent" ] && case "$(printf '%s' "$who" | tr 'A-Z' 'a-z')" in ''|general-purpose|claude|fork) catch_all=1 ;; esac
if [ -n "$catch_all" ]; then
  branch="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
  case "$branch" in
    issue/*|wave/*|milestone-*)
      subject="subagent_type $who"; [ -z "$who" ] && subject='no subagent_type'
      roster="$implementer, milestone-driver:planner, milestone-driver:reviewer, milestone-driver:triage-reviewer, milestone-driver:design-reviewer, milestone-driver:blocker-resolver, milestone-driver:process-auditor, milestone-coherence-reviewer:coherence-reviewer"
      hook_deny "$input" "milestone-driver: dispatch contract - a main-thread Agent dispatch with $subject is denied on branch $branch. Dispatch a named agent: $roster. Operator override: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1." ;;
  esac
fi

# Rows of <tool> <match> <kind> <cap>, first match wins. An indexed array, not a
# heredoc: a heredoc needs a writable TMPDIR on bash 3.2.
table=(
  Skill code-review              review      3
  Agent "$implementer"           implementer 3
  Agent milestone-driver:planner planner     2
)
kind=''
cap=''
i=0
while [ "$i" -lt "${#table[@]}" ]; do
  if [ "${table[i]}" = "$tool" ] && [ "${table[i+1]}" = "$who" ]; then
    kind="${table[i+2]}"; cap="${table[i+3]}"; break
  fi
  i=$((i + 4))
done
[ -n "$kind" ] || exit 0
text="$(printf '%s' "$input" | jq -r ".tool_input.$field // empty" 2>/dev/null | tr -d '\r')"

[ -n "$branch" ] || branch="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
key=''
token=''
ms_key=''
re_branch='^issue/([0-9]+)'
re_ms_branch='^milestone-([0-9]+)-'
re_marker='^[[:space:]]*Milestone-End-Fix:[[:space:]]*([0-9]+)'
[ "$field" = task_name ] && re_marker='_milestone_([0-9]+)_'
re_issue='[Ii]ssue[[:space:]#:/_-]*([0-9]+)'
re_hash='#([0-9]+)'
if [ "$kind" != review ] && [[ $branch =~ $re_ms_branch ]]; then
  ms_n="${BASH_REMATCH[1]}"
  if [[ $text =~ $re_marker ]] && [ "${BASH_REMATCH[1]}" = "$ms_n" ]; then
    key="milestone-$ms_n"; token="$branch"; ms_key=1
    [ "$kind" = planner ] && cap=1
  fi
fi
[ -n "$key" ] || if [[ $branch =~ $re_branch ]]; then
  key="${BASH_REMATCH[1]}"
elif [[ $text =~ $re_issue ]]; then
  key="${BASH_REMATCH[1]}"
elif [[ $text =~ $re_hash ]]; then
  key="${BASH_REMATCH[1]}"
else
  key="$(printf '%s' "$branch" | tr -c 'A-Za-z0-9._-' '_')"
fi
[ -n "$key" ] || key='default'

common="$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null)" || exit 0
common="${common//\\//}"
case "$common" in
  /*|[A-Za-z]:/*) ;;
  *) common="$project_dir/$common" ;;
esac
[ -n "$token" ] || token="$(git -C "$project_dir" rev-parse HEAD 2>/dev/null)" || token='none'

dir="$common/milestone-driver/dispatch-cap"
mkdir -p "$dir" 2>/dev/null || exit 0
file="$dir/$kind-$key"

count=0
if [ -f "$file" ]; then
  read -r stored_token stored_count < "$file"
  [ "$stored_token" = "$token" ] && count="${stored_count:-0}"
fi
case "$count" in ''|*[!0-9]*) count=0 ;; esac

if [ "$count" -ge "$cap" ]; then
  root="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/}"
  [ -n "$ms_key" ] && hook_deny "$input" "milestone-driver: dispatch cap - this would be $kind dispatch $((count + 1)) of at most $cap for milestone end $ms_n. Follow the cap-spent path of ${root}skills/solve-milestone/milestone-end-gates.md; its Halt runs ${root}scripts/reset-dispatch-cap.<sh|ps1> <repo-root> $key, so a resumed milestone end starts a fresh budget. Operator override: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1."
  case "$key" in *[!0-9]*) what="branch $key" ;; *) what="issue $key" ;; esac
  hook_deny "$input" "milestone-driver: dispatch cap - this would be $kind dispatch $((count + 1)) of at most $cap for $what (${root}skills/review-depth.md § The ladder). Park the issue; the park action clears this counter. Operator override: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1."
fi

printf '%s %s\n' "$token" "$((count + 1))" > "$file" 2>/dev/null
exit 0
