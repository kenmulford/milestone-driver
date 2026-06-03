#!/usr/bin/env bash
# milestone-driver — tests-green gate (Claude PreToolUse: Bash, if: Bash(git commit *)).
# Runs unitTestCmd when staged files touch sourceGlobs; blocks the commit on red.
# Deny: exit 2. Requires jq. Escape: CLAUDE_HOOK_DISABLE_TESTS_GREEN=1. Fail-open.
[ "${CLAUDE_HOOK_DISABLE_TESTS_GREEN:-}" = "1" ] && exit 0
input="$(cat)"; [ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
# Self-scope to commits (parity with no-push; defends the "if predicate runs
# always when the command is too complex to parse" fallthrough).
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
if [ -n "$cmd" ] && ! [[ "$cmd" =~ git[[:space:]]+commit ]]; then exit 0; fi
project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"
profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0
unit_cmd="$(jq -r '.unitTestCmd // empty' "$profile" 2>/dev/null)"; unit_cmd="${unit_cmd%$'\r'}"
[ -z "$unit_cmd" ] && exit 0
globs=(); while IFS= read -r g; do g="${g%$'\r'}"; [ -n "$g" ] && globs+=("$g"); done \
  < <(jq -r '.sourceGlobs[]? // empty' "$profile" 2>/dev/null)
touched=0; [ ${#globs[@]} -eq 0 ] && touched=1
while IFS= read -r f; do
  [ -z "$f" ] && continue
  for g in "${globs[@]}"; do pat="${g//\*\*/\*}"; case "$f" in $pat) touched=1; break;; esac; done
  [ "$touched" = "1" ] && break
done < <(git -C "$project_dir" diff --cached --name-only 2>/dev/null)
[ "$touched" = "0" ] && exit 0
# --- stamp-skip: skip re-running the suite when staged tree is identical to last green run ---
stamp_path="$project_dir/.milestone-driver-tests-stamp"
stamp_key=""
branch="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
tree_sha="$(git -C "$project_dir" write-tree 2>/dev/null)"
if [ $? -eq 0 ] && [ -n "$tree_sha" ]; then
  branch="${branch%$'\r'}"; tree_sha="${tree_sha%$'\r'}"
  stamp_key="${branch}:${tree_sha}"
  if [ -f "$stamp_path" ] && [ "$(cat "$stamp_path" 2>/dev/null | tr -d '\r\n')" = "$stamp_key" ]; then
    echo "milestone-driver: staged tree unchanged since last green run — skipping unit suite." >&2
    exit 0
  fi
fi
# --- end stamp-skip ---
echo "milestone-driver: staged source changed — running unit suite ($unit_cmd) ..." >&2
if ! ( cd "$project_dir" && eval "$unit_cmd" ) >&2; then
  # Clear stale green stamp so a red run never grants a future skip.
  [ -f "$stamp_path" ] && rm -f "$stamp_path"
  echo "milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override." >&2
  exit 2
fi
# Write stamp on green (best-effort — failure does not fail the hook).
if [ -n "$stamp_key" ]; then
  printf '%s' "$stamp_key" > "$stamp_path" 2>/dev/null || true
fi
exit 0
