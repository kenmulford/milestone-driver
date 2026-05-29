#!/usr/bin/env bash
# milestone-driver — no-push-to-protected gate (native git pre-push)
#
# Rejects any push whose remote ref is the profile's protectedBranch. The loop
# integrates to integrationBranch only; release to protectedBranch stays manual.
# GitHub branch protection is the server-side backstop.
#
# Install: wire this into <repo>/.git/hooks/pre-push (see the plugin's
# consumer-setup docs). Requires jq. Escape: CLAUDE_HOOK_DISABLE_NO_PUSH=1
#
# git passes ref updates on stdin: "<local ref> <local sha> <remote ref> <remote sha>"

[ "${CLAUDE_HOOK_DISABLE_NO_PUSH:-}" = "1" ] && exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
profile="$repo_root/.claude/milestone-driver.json"
[ -f "$profile" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

protected="$(jq -r '.protectedBranch // empty' "$profile" 2>/dev/null)"
protected="${protected%$'\r'}"
[ -z "$protected" ] && exit 0

blocked=0
while read -r _localref _localsha remoteref _remotesha; do
  [ -z "$remoteref" ] && continue
  if [ "$remoteref" = "refs/heads/$protected" ]; then blocked=1; fi
done

if [ "$blocked" = "1" ]; then
  echo "milestone-driver: pushing to protected branch '$protected' is blocked. Push the integration branch and open a PR instead, or set CLAUDE_HOOK_DISABLE_NO_PUSH=1 to override. (GitHub branch protection is the server-side backstop.)" >&2
  exit 1
fi
exit 0
