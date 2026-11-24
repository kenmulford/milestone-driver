#!/usr/bin/env bash
# milestone-driver - no-PR-to-protected gate (Claude PreToolUse: Bash, if: Bash(gh pr create *);
# and the GitHub MCP matcher mcp__.*github.*__(merge_pull_request|create_pull_request|
# update_pull_request|push_files|create_or_update_file|delete_file))
#
# Bash: blocks `gh pr create --base <protected>`, a first, coarse text check (and the
# only one under Codex). The exact checks run at execution time on real arguments:
# shims/gh for every gh route, git-hooks/pre-push for every push.
# MCP: structured tool_input, so exact. A PR base is allowlisted to integrationBranch
# (a merge reads the PR's base through `gh pr view`; one that cannot be resolved
# denies); a push or file write denies a protected branch (shims/_protected.sh).
#
# Deny: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON). Escape: CLAUDE_HOOK_DISABLE_NO_PUSH=1.
# Bash path: requires jq, fail-open on parse/missing-profile. MCP path without jq:
# denies, because no base can be read.

[ "${CLAUDE_HOOK_DISABLE_NO_PUSH:-}" = "1" ] && exit 0

input="$(cat)"
hook_dir="${BASH_SOURCE[0]%[/\\]*}"; [ "$hook_dir" = "${BASH_SOURCE[0]}" ] && hook_dir=.   # builtin: PATH may lack dirname
. "$hook_dir/hook-deny.sh"
[ -z "$input" ] && exit 0

mcp_re='^mcp__.*github.*__(merge_pull_request|create_pull_request|update_pull_request|push_files|create_or_update_file|delete_file)$'
if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
else
  tool=""; project_dir=""
  tn_re='"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)"'; cwd_re='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'
  [[ "$input" =~ $tn_re ]] && tool="${BASH_REMATCH[1]}"
  [[ "$input" =~ $cwd_re ]] && project_dir="${BASH_REMATCH[1]}"
  project_dir="${project_dir//\\\\/\\}"
fi
if [[ "$tool" =~ $mcp_re ]]; then
  mcp="${BASH_REMATCH[1]}"
  [ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
  project_dir="${project_dir//\\//}"
  . "$hook_dir/../shims/_protected.sh"
  md_profile "$project_dir"
  integ="$md_integ"
  unres='unknown base'; unres_b='unknown branch'

  block() {
    hook_deny "$input" "milestone-driver: $1 into '$2' is blocked. Agents stop at the integration branch '$integ'; anything past it is a human step."
  }

  if ! command -v jq >/dev/null 2>&1; then
    base_re='"base"[[:space:]]*:'
    case "$mcp" in
      merge_pull_request) block "merging a PR" "$unres" ;;
      create_pull_request) block "opening a PR" "$unres" ;;
      update_pull_request) [[ "$input" =~ $base_re ]] && block "retargeting a PR" "$unres" ;;
      *) block "pushing" "$unres_b" ;;
    esac
    exit 0
  fi

  # check_base <action> <base>: the allowlist; an empty base is unresolved.
  check_base() { [ "$2" = "$integ" ] || block "$1" "${2:-$unres}"; }

  # api_default <owner/repo>: prints the default branch a write naming no branch
  # lands on; returns 1 when the lookup fails.
  api_default() {
    local out
    out="$(gh api "repos/$1" --jq .default_branch 2>/dev/null)" || return 1
    out="${out%$'\r'}"; [ -n "$out" ] || return 1
    printf '%s' "$out"
  }

  # pr_base <pr-or-empty> <owner/repo-or-empty>: prints the PR's base branch;
  # returns 1 when gh or the lookup fails.
  pr_base() {
    local a=(pr view) out b
    [ -n "$1" ] && a+=("$1")
    [ -n "$2" ] && a+=(-R "$2")
    out="$(gh "${a[@]}" --json baseRefName 2>/dev/null)" || return 1
    b="$(printf '%s' "$out" | jq -r '.baseRefName // empty' 2>/dev/null)"; b="${b%$'\r'}"
    [ -n "$b" ] || return 1
    printf '%s' "$b"
  }

  base="$(printf '%s' "$input" | jq -r '.tool_input.base // empty' 2>/dev/null)"; base="${base%$'\r'}"
  branch="$(printf '%s' "$input" | jq -r '.tool_input.branch // empty' 2>/dev/null)"; branch="${branch%$'\r'}"
  o="$(printf '%s' "$input" | jq -r '.tool_input.owner // empty' 2>/dev/null)"; o="${o%$'\r'}"
  r="$(printf '%s' "$input" | jq -r '.tool_input.repo // empty' 2>/dev/null)"; r="${r%$'\r'}"
  case "$mcp" in
    merge_pull_request)
      n="$(printf '%s' "$input" | jq -r '.tool_input.pullNumber // empty' 2>/dev/null)"
      b="$(pr_base "$n" "$o/$r")" || block "merging a PR" "$unres"
      check_base "merging a PR" "$b" ;;
    create_pull_request) check_base "opening a PR" "$base" ;;
    update_pull_request) [ -n "$base" ] && check_base "retargeting a PR" "$base" ;;
    *)
      if [ -z "$branch" ]; then
        branch="$(api_default "$o/$r")" || block "pushing" "$unres_b"
      fi
      md_denied "$branch" && block "pushing" "$branch" ;;
  esac
  exit 0
fi
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
integ="$(jq -r '.integrationBranch // empty' "$profile" 2>/dev/null)"; integ="${integ%$'\r'}"
[ -z "$protected" ] && exit 0

base=""
if [[ "$cmd" =~ (--base[=[:space:]]+|-B[[:space:]]+)\"?\'?([^[:space:]\"\']+) ]]; then
  base="${BASH_REMATCH[2]}"
fi

if [ "$base" = "$protected" ]; then
  if [ -z "$integ" ]; then
    integ=develop
    git -C "$project_dir" rev-parse --verify --quiet refs/remotes/origin/develop >/dev/null 2>&1 || integ=dev
  fi
  hook_deny "$input" "milestone-driver: opening a PR into '$protected' is blocked. Agents stop at the integration branch '$integ'; anything past it is a human step."
fi
exit 0
