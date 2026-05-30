#!/usr/bin/env bash
# milestone-driver — no-push gate (Claude PreToolUse: Bash, if: Bash(git push *)).
# Blocks a push targeting protectedBranch. Deny: exit 2. Requires jq.
# Escape: CLAUDE_HOOK_DISABLE_NO_PUSH=1. Fail-open.
[ "${CLAUDE_HOOK_DISABLE_NO_PUSH:-}" = "1" ] && exit 0
input="$(cat)"; [ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0
[[ "$cmd" =~ git[[:space:]]+push ]] || exit 0
project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"
profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0
protected="$(jq -r '.protectedBranch // empty' "$profile" 2>/dev/null)"; protected="${protected%$'\r'}"
[ -z "$protected" ] && exit 0
blocked=0
# explicit refspec naming the protected branch (e.g. "git push origin master", "HEAD:master", ":refs/heads/master")
if [[ "$cmd" =~ (^|[[:space:]:/])"$protected"([[:space:]]|$) ]]; then blocked=1; fi
# no explicit refspec but currently on the protected branch
cur="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$cur" = "$protected" ] && blocked=1
if [ "$blocked" = "1" ]; then
  echo "milestone-driver: pushing to protected branch '$protected' is blocked. Push the integration branch and open a PR, or set CLAUDE_HOOK_DISABLE_NO_PUSH=1 to override. (GitHub branch protection is the server-side backstop.)" >&2
  exit 2
fi
exit 0
