#!/usr/bin/env bash
# milestone-driver - unit gate: stage, run unitTestCmd, stamp on green (the
# lean-loop change, L1).
#
# The orchestrator's own full unitTestCmd runs - step 4's Unit gate, the
# post-fix `code-changed` re-run, a milestone fold's re-verify - call this
# instead of running unitTestCmd directly. It stages everything first (`git
# add -A`, so the stamp is keyed to the tree that will actually be committed,
# not to whatever a caller happened to stage already), runs the suite, and on
# green writes the same `<branch>:<treeSHA>` stamp `hooks/tests-green.sh
# (stamp-skip: skip re-running the suite when staged tree is identical to
# last green run)` reads - so the commit-time hook sees a tree it already
# knows is green and does not run the suite a second time. A red run clears
# any stamp so a later green run is never shadowed by a stale one.
#
# `git add -A` here does not disturb `scripts/classify-delta.sh --snapshot`'s
# verdict (it snapshots into its own temp index off the real index's content,
# not off staged/unstaged status - `scripts/classify-delta.sh (A snapshot is
# GIT_INDEX_FILE=<temp> git add -A then git write-tree)`), nor
# `scripts/classify-review-depth.sh`'s (it reads `git diff HEAD`, which is
# staged-and-unstaged-combined against HEAD either way).
#
# Usage: unit-gate.sh [--stamp-only] <repo-root>
#   --stamp-only  stage and write the stamp without running unitTestCmd at
#                 all - for a caller that has independently proven the
#                 staged tree already green elsewhere (a milestone fold whose
#                 squash-merge produced a tree identical to the issue
#                 branch's own already-verified tip -
#                 `skills/solve-milestone/milestone-granularity.md (Folding
#                 an issue into the milestone branch)`).
# Exit:  0   unitTestCmd absent, or no profile at all (no-op), or the suite
#            passed, or --stamp-only staged and stamped
#        1   the suite failed (any prior stamp cleared)
#        2   bad usage
# stdout carries the suite's own output (real evidence, never assertion,
# `superpowers:verification-before-completion`). stderr carries one status
# line per phase, mirroring hooks/tests-green.sh's wording.
set -u
stamp_only=0
if [ "${1:-}" = "--stamp-only" ]; then stamp_only=1; shift; fi
root="${1:-}"
[ -z "$root" ] && { echo "usage: unit-gate.sh [--stamp-only] <repo-root>" >&2; exit 2; }
profile="$root/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$root/milestone-driver.json"
[ -f "$profile" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
unit_cmd="$(jq -r '.unitTestCmd // empty' "$profile" 2>/dev/null)"; unit_cmd="${unit_cmd%$'\r'}"
[ -z "$unit_cmd" ] && exit 0

stamp_path="$root/.milestone-config/tests-stamp"
old_stamp_path="$root/.milestone-driver-tests-stamp"

# Self-heal the scratch-ignore BEFORE staging: a newly-created .gitignore
# must be part of the tree `git add -A` below stages and this stamp keys on,
# or a caller's own later `git add -A` (right before `git commit`) would pick
# it up as a fresh change and the commit-time hook would see a tree that no
# longer matches this stamp - one spurious re-run on a fresh consumer clone's
# first-ever green run. KEEP THIS BLOCK IN SYNC with hooks/tests-green.sh's
# own copy, with the committed .milestone-config/.gitignore in this repo, and
# with solve-issue / solve-milestone / scripts/triage-cache.{sh,ps1}, feeder
# setup / plan. tests/tests-green.test.{sh,ps1} and
# tests/unit-gate.test.{sh,ps1} pin the EMITTED bytes against that file, so a
# name added there and not here fails CI.
mkdir -p "$root/.milestone-config" 2>/dev/null || true
ignore_path="$root/.milestone-config/.gitignore"
if [ ! -f "$ignore_path" ]; then
  printf '%s\n' \
    '# milestone-driver / milestone-feeder per-clone scratch - git-invisible by default.' \
    '# Committed so per-run scratch stays out of `git status` with zero user setup.' \
    '# Patterns are relative to this .milestone-config/ directory. Tracked config' \
    '# (driver.json, feeder.json) is intentionally NOT listed, so it stays tracked.' \
    '*-notice' 'triage-cache.json' \
    'tests-stamp' '.runtime/' 'worktrees/' > "$ignore_path" 2>/dev/null || true
fi

git -C "$root" add -A 2>/dev/null

branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
tree_sha="$(git -C "$root" write-tree 2>/dev/null)"
stamp_key=""
if [ -n "$tree_sha" ]; then
  branch="${branch%$'\r'}"; tree_sha="${tree_sha%$'\r'}"
  stamp_key="${branch}:${tree_sha}"
fi

if [ "$stamp_only" = "1" ]; then
  echo "milestone-driver: unit gate - staged tree already proven green elsewhere, stamping without a suite run." >&2
else
  echo "milestone-driver: unit gate - running unit suite ($unit_cmd) ..." >&2
  if ! ( cd "$root" && eval "$unit_cmd" ); then
    [ -f "$stamp_path" ] && rm -f "$stamp_path"
    [ -f "$old_stamp_path" ] && rm -f "$old_stamp_path"
    echo "milestone-driver: unit gate - unit tests failed." >&2
    exit 1
  fi
fi

if [ -n "$stamp_key" ]; then
  if printf '%s' "$stamp_key" > "$stamp_path" 2>/dev/null; then
    [ -f "$old_stamp_path" ] && rm -f "$old_stamp_path" 2>/dev/null || true
  fi
  echo "milestone-driver: unit gate - suite green, stamp written for $stamp_key." >&2
fi
exit 0
