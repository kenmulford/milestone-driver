#!/usr/bin/env bash
# milestone-driver - dispatch-cap gate (Claude PreToolUse: Agent|Task|Skill)
#
# Per issue: at most 3 `/code-review` runs (Skill `code-review` / `*:code-review`)
# and 3 implementer dispatches (Agent/Task whose subagent_type is the profile's
# implementerAgent), the caps skills/review-depth.md states, plus 2 planner
# dispatches (subagent_type `milestone-driver:planner`, fixed, not profile-read).
# Main thread only; the parallel-mode reviewer leaf (general-purpose) is not counted.
# Key: branch `issue/<n>-*`, else `issue <n>` / `#<n>` in the brief, else the
# branch name. Counter: <git-common-dir>/milestone-driver/dispatch-cap/<kind>-<key>
# holds `<HEAD> <count>`; a moved HEAD or a park (`scripts/reset-dispatch-cap`)
# resets it.
# Deny: exit 2 + stderr. Escape: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1.
# Fail-open on missing jq/git, no repo, or unparsed stdin. bash-3.2-safe (the
# =~ patterns sit in variables: 3.2 mis-parses a quoted inline regex).

[ "${CLAUDE_HOOK_DISABLE_DISPATCH_CAP:-}" = "1" ] && exit 0

input="$(cat)"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

for field in agent_id agent_type parent_session_id; do
  val="$(printf '%s' "$input" | jq -r ".${field} // empty" 2>/dev/null)"
  [ -n "$val" ] && exit 0
done

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ -n "$tool" ] || exit 0

project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"

profile="$project_dir/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0
implementer="$(jq -r '.implementerAgent // empty' "$profile" 2>/dev/null | tr -d '\r')"
[ -n "$implementer" ] || implementer='milestone-driver:implementer'

# A Skill is matched on the name after its last `:`, so the `code-review` row
# also covers `*:code-review`; Task is the legacy name of Agent.
case "$tool" in
  Skill)
    who="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)"
    who="${who##*:}"; field='args' ;;
  Agent|Task)
    tool='Agent'; field='prompt'
    who="$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)" ;;
  *) exit 0 ;;
esac

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
text="$(printf '%s' "$input" | jq -r ".tool_input.$field // empty" 2>/dev/null)"

branch="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
key=''
re_branch='^issue/([0-9]+)'
re_issue='[Ii]ssue[[:space:]#:/_-]*([0-9]+)'
re_hash='#([0-9]+)'
if [[ $branch =~ $re_branch ]]; then
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
head="$(git -C "$project_dir" rev-parse HEAD 2>/dev/null)" || head='none'

dir="$common/milestone-driver/dispatch-cap"
mkdir -p "$dir" 2>/dev/null || exit 0
file="$dir/$kind-$key"

count=0
if [ -f "$file" ]; then
  read -r stored_head stored_count < "$file"
  [ "$stored_head" = "$head" ] && count="${stored_count:-0}"
fi
case "$count" in ''|*[!0-9]*) count=0 ;; esac

if [ "$count" -ge "$cap" ]; then
  case "$key" in *[!0-9]*) what="branch $key" ;; *) what="issue $key" ;; esac
  echo "milestone-driver: dispatch cap - this would be $kind dispatch $((count + 1)) of at most $cap for $what (skills/review-depth.md § The ladder). Park the issue instead of dispatching again. Reset: delete '$file', or set CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1 to override." >&2
  exit 2
fi

printf '%s %s\n' "$head" "$((count + 1))" > "$file" 2>/dev/null
exit 0
