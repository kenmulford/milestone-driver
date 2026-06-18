#!/usr/bin/env bash
# milestone-driver — no-PR-to-protected gate (Claude PreToolUse: Bash)
#
# Companion to the no-push gate: blocks `gh pr create --base <protected>`
# so the loop never opens a PR targeting the protected branch.
#
# Deny: exit 2 + stderr. Requires jq. Escape: CLAUDE_HOOK_DISABLE_NO_PUSH=1.
# Fail-open on parse/missing-profile.
#
# Residual risk: a bare `gh pr create` with no --base targets the repo's default
# branch; the /milestone-driver:solve-issue skill always passes --base explicitly, and GitHub
# branch protection is the server-side backstop.

[ "${CLAUDE_HOOK_DISABLE_NO_PUSH:-}" = "1" ] && exit 0

input="$(cat)"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0
[[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+create ]] || exit 0

project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"
profile="$project_dir/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0

protected="$(jq -r '.protectedBranch // empty' "$profile" 2>/dev/null)"
protected="${protected%$'\r'}"
[ -z "$protected" ] && exit 0

base=""
if [[ "$cmd" =~ (--base[=[:space:]]+|-B[[:space:]]+)\"?\'?([^[:space:]\"\']+) ]]; then
  base="${BASH_REMATCH[2]}"
fi

if [ "$base" = "$protected" ]; then
  echo "milestone-driver: opening a PR to protected branch '$protected' is blocked. Target the integration branch instead, or set CLAUDE_HOOK_DISABLE_NO_PUSH=1 to override." >&2
  exit 2
fi
exit 0
