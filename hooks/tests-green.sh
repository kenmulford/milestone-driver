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
profile="$project_dir/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$project_dir/milestone-driver.json"
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
# New canonical path under .milestone-config/; old root path read transitionally as a
# fallback (mirrors the profile two-step read above). Write always goes to the new path.
stamp_path="$project_dir/.milestone-config/tests-stamp"
old_stamp_path="$project_dir/.milestone-driver-tests-stamp"
stamp_key=""
branch="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
tree_sha="$(git -C "$project_dir" write-tree 2>/dev/null)"
if [ $? -eq 0 ] && [ -n "$tree_sha" ]; then
  branch="${branch%$'\r'}"; tree_sha="${tree_sha%$'\r'}"
  stamp_key="${branch}:${tree_sha}"
  # Read the new path; if absent, fall back to the old root path. Skip on either match.
  read_stamp=""
  if [ -f "$stamp_path" ]; then
    read_stamp="$(cat "$stamp_path" 2>/dev/null | tr -d '\r\n')"
  elif [ -f "$old_stamp_path" ]; then
    read_stamp="$(cat "$old_stamp_path" 2>/dev/null | tr -d '\r\n')"
  fi
  if [ -n "$read_stamp" ] && [ "$read_stamp" = "$stamp_key" ]; then
    echo "milestone-driver: staged tree unchanged since last green run — skipping unit suite." >&2
    exit 0
  fi
fi
# --- end stamp-skip ---
echo "milestone-driver: staged source changed — running unit suite ($unit_cmd) ..." >&2
if ! ( cd "$project_dir" && eval "$unit_cmd" ) >&2; then
  # Clear stale green stamps (both new and legacy root) so a red run never grants a future skip.
  [ -f "$stamp_path" ] && rm -f "$stamp_path"
  [ -f "$old_stamp_path" ] && rm -f "$old_stamp_path"
  echo "milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override." >&2
  exit 2
fi
# Write stamp on green to the new path (best-effort — failure does not fail the hook).
# mkdir -p first; no writer may assume .milestone-config/ exists. Remove the stale
# legacy root stamp once the new one is written, so it stops shadowing future reads.
if [ -n "$stamp_key" ]; then
  mkdir -p "$project_dir/.milestone-config" 2>/dev/null || true
  # Self-heal the scratch-ignore: ensure a committed .milestone-config/.gitignore so
  # per-clone scratch (this stamp, preflight/trello notices, triage cache, worktrees)
  # is git-invisible in the consumer repo from the first write, while tracked config
  # (driver.json, feeder.json — intentionally NOT listed) stays tracked. Best-effort;
  # only created when absent, so a user-edited file is never clobbered.
  ignore_path="$project_dir/.milestone-config/.gitignore"
  if [ ! -f "$ignore_path" ]; then
    printf '%s\n' \
      '# milestone-driver / milestone-feeder per-clone scratch — git-invisible by default.' \
      '# Committed so per-run scratch stays out of `git status` with zero user setup.' \
      '# Patterns are relative to this .milestone-config/ directory. Tracked config' \
      '# (driver.json, feeder.json) is intentionally NOT listed, so it stays tracked.' \
      'preflight-notice' 'trello-notice' 'triage-cache.json' 'tests-stamp' \
      '.runtime/' 'worktrees/' > "$ignore_path" 2>/dev/null || true
  fi
  if printf '%s' "$stamp_key" > "$stamp_path" 2>/dev/null; then
    [ -f "$old_stamp_path" ] && rm -f "$old_stamp_path" 2>/dev/null || true
  fi
fi
exit 0
