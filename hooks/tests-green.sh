#!/usr/bin/env bash
# milestone-driver — tests-green gate (native git pre-commit)
#
# When staged changes touch the profile's sourceGlobs, runs unitTestCmd and
# blocks the commit if it fails. Harness-independent: guards human commits too.
#
# Install: wire this into <repo>/.git/hooks/pre-commit (see the plugin's
# consumer-setup docs). Requires jq. Escape: CLAUDE_HOOK_DISABLE_TESTS_GREEN=1
# Fail-open on missing profile/jq so a non-milestone-driver repo is unaffected.

[ "${CLAUDE_HOOK_DISABLE_TESTS_GREEN:-}" = "1" ] && exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
profile="$repo_root/.claude/milestone-driver.json"
[ -f "$profile" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

unit_cmd="$(jq -r '.unitTestCmd // empty' "$profile" 2>/dev/null)"
unit_cmd="${unit_cmd%$'\r'}"
[ -z "$unit_cmd" ] && exit 0

# Load sourceGlobs (strip CR — jq on Windows/msys emits CRLF).
globs=()
while IFS= read -r g; do g="${g%$'\r'}"; [ -n "$g" ] && globs+=("$g"); done \
  < <(jq -r '.sourceGlobs[]? // empty' "$profile" 2>/dev/null)

# Run tests only when staged files touch source/test globs (skip doc/config-only
# commits). With no globs declared, run unconditionally (safe default).
touched=0
[ ${#globs[@]} -eq 0 ] && touched=1
while IFS= read -r f; do
  [ -z "$f" ] && continue
  for g in "${globs[@]}"; do
    pat="${g//\*\*/\*}"
    # shellcheck disable=SC2254
    case "$f" in $pat) touched=1; break;; esac
  done
  [ "$touched" = "1" ] && break
done < <(git diff --cached --name-only)

[ "$touched" = "0" ] && exit 0

echo "milestone-driver: staged source changed — running unit suite ($unit_cmd) ..." >&2
if ! ( cd "$repo_root" && eval "$unit_cmd" ) >&2; then
  echo "milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override." >&2
  exit 1
fi
exit 0
