#!/usr/bin/env bash
# milestone-driver — force-subagent gate (Claude PreToolUse: Write|Edit|MultiEdit|NotebookEdit)
#
# Bash parity of force-subagent.ps1. Blocks main-thread edits to the consuming
# repo's source/test globs so application/test code is authored only by the
# dispatched implementer subagent. Requires `jq`.
#
# Deny mechanism: exit 2 + stderr. Escape hatch: CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT=1
# Fail-open: missing jq / parse errors exit 0 so a hook bug never bricks editing.

[ "${CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT:-}" = "1" ] && exit 0

input="$(cat)"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Subagent context -> allow.
for field in agent_id agent_type parent_session_id; do
  val="$(printf '%s' "$input" | jq -r ".${field} // empty" 2>/dev/null)"
  [ -n "$val" ] && exit 0
done

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
[ -z "$file_path" ] && exit 0
norm="${file_path//\\//}"

# Always-exempt paths. Source globs are gated even when markdown.
case "$norm" in
  */docs/*)      exit 0 ;;
  */.claude/*)   exit 0 ;;
  */Obsidian/*)  exit 0 ;;
esac

project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"

profile="$project_dir/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0

rel="$norm"
case "$norm" in
  "$project_dir"/*) rel="${norm#"$project_dir"/}" ;;
esac

while IFS= read -r g; do
  g="${g%$'\r'}"          # strip trailing CR (jq on Windows/msys emits CRLF)
  [ -z "$g" ] && continue
  pat="${g//\*\*/\*}"     # ** -> * ('*' in a case glob matches across '/')
  blocked=0
  # shellcheck disable=SC2254
  case "$rel"  in $pat)    blocked=1 ;; esac
  # shellcheck disable=SC2254
  case "$norm" in */$pat)  blocked=1 ;; esac
  if [ "$blocked" = "1" ]; then
    echo "milestone-driver: main-thread edits to source ('$rel') are blocked. Dispatch the implementer subagent to author application/test code, or set CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT=1 to override." >&2
    exit 2
  fi
done < <(jq -r '.sourceGlobs[]? // empty' "$profile" 2>/dev/null)

exit 0
