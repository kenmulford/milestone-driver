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
echo "milestone-driver: staged source changed — running unit suite ($unit_cmd) ..." >&2
if ! ( cd "$project_dir" && eval "$unit_cmd" ) >&2; then
  echo "milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override." >&2
  exit 2
fi
exit 0
