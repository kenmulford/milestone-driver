# Shared deny for every gate. Codex ignores exit 2 and blocks only on a stdout
# permissionDecision, so a payload carrying turn_id (Codex) gets that JSON and
# exit 0. Claude Code keeps exit 2 + stderr.
# Usage: hook_deny "$input" "milestone-driver: <reason>"
hook_deny() {
  if [ -n "$(printf '%s' "$1" | jq -r '.turn_id // empty' 2>/dev/null)" ]; then
    # -a: ASCII-only, so the JSON survives a non-UTF-8 stdout.
    jq -acn --arg r "$2" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
  fi
  echo "$2" >&2
  exit 2
}
