# Milestone end gates: solve-milestone reference

Loaded once per run from `skills/solve-milestone/milestone-granularity.md`'s `## Milestone end: one push, one PR, one CI run`, after the simplify pass, before that section's step 1. Runs only under `"milestone"` granularity.

## Contents

The ordered sequence · The fix-dispatch loop · Cap spent, still red · Attribution and revert · The run-scoped handler · The milestone review sub-entry

---

## The ordered sequence

Run these once over `<range>` (`git diff <integrationBranch>...<milestone-branch>`), in this order and no other. There is no step 1: `<range>` above is read-only. The gap stays rather than renumber (`skills/solve-issue/SKILL.md (There is no step 5)`).

| # | Step | Detail |
|---|---|---|
| 2 | Empty diff | No commits over `integrationBranch`: log one line, end the sequence here, mirroring `skills/solve-milestone/simplify-pass.md (Zero findings, or a failure)` and `skills/solve-milestone/milestone-granularity.md (Nothing merged.)`. `## Milestone end: one push, one PR, one CI run` step 1 proceeds unchanged |
| 3 | Coherence review | Only when `coherenceReviewAgent` is present and configured (`skills/solve-issue/SKILL.md (is both present (dispatchable in this session) and configured)`); absent/unconfigured → skip silently. When it runs: dispatch the coherence agent read-only against `<range>`, `skills/solve-issue/coherence-review.md (### The pass)`. `skills/solve-issue/coherence-review.md (Never-gating.)` holds here too: findings never enter the fix-dispatch cap |
| 4 | `/code-review` | Read `skills/review-depth.md` and follow it: run `scripts/classify-review-depth.sh <repo-root> <integrationBranch>` (`scripts/classify-review-depth.sh (Usage:)`), rooted at the milestone branch's checkout, and dispatch one reviewer leaf at the verdict's first-run effort |
| 5 | Unit gate | `${CLAUDE_PLUGIN_ROOT}/scripts/unit-gate.<sh\|ps1> <repo-root>` (pwsh on Windows, bash elsewhere), never `unitTestCmd` directly |
| 6 | E2E | Only when an issue on the branch carries the `ui` label and `e2eTestCmd` is defined: run `e2eTestCmd` against `e2eEnv` |
| 7 | Preflight | The Preflight row of `skills/solve-issue/SKILL.md § 4. Verification gates`. `skills/solve-issue/SKILL.md (the Preflight row above does not apply)` under the `"github-ci"` sentinel: this step defers to the milestone PR's CI |
| 8 | Converge or fix | Nothing collected: `## Milestone end: one push, one PR, one CI run` step 1 proceeds. Otherwise: `## The fix-dispatch loop` |

## The fix-dispatch loop

Collect every `/code-review` finding from step 4 and every red gate from steps 5-7; step 3's coherence findings never enter it.

- One or more collected: dispatch the `implementerAgent` once, briefed with `<range>` and every finding and failure. It returns an uncommitted working tree, per its own contract.
- Commit: subject line, the fix's summary, step 4's `/code-review` result in `skills/solve-issue/SKILL.md` step 6.3's `Code-Review:` block shape, then a final paragraph of exactly `Milestone-End-Fix: <milestone-number>` (the milestone path's shape at `skills/solve-milestone/simplify-pass.md (## Land the findings)`). No `Issue:` line.
- Re-run the sequence from step 4, never re-running step 3's coherence pass on a fix commit.

**Cap.** At most 3 fix dispatches per milestone end, counted in the orchestrator's own run state, never `hooks/dispatch-cap.sh` (it resets on every fix commit's HEAD move): a 4th takes `## Cap spent, still red`.

## Cap spent, still red

**Precedence.** A gate from steps 5-7 still red takes attribution and revert below, whether or not a `/code-review` finding is open too. Every gate green with a finding still open instead takes `## The run-scoped handler`.

## Attribution and revert

**Name the commit.** The red gate names the failing test's file; diff each issue commit on `<range>` against its parent (`git show --name-only --format= <commit>`); one match is a **candidate**, not the culprit.

**Confirm the candidate.** Run the red gate's command at the parent (expect green) and at the candidate (expect red). Both hold → revert it, below. Either fails - not the culprit: bisect, below.

**No match, more than one, or unconfirmed: bisect.** `git bisect start <milestone-branch> <integrationBranch>`, then `git bisect run` with the red gate's command. Record the first-bad sha, then `git bisect reset`. Its own `Issue: #<n>` trailer names the culprit. No single first-bad commit, or one with no `Issue: #<n>` trailer (a landed `Milestone-End-Fix:` commit, say): take `## The run-scoped handler` below, no revert, no park.

**Revert and park.** `git revert --no-edit <commit>`, keeping the reverted commit's `Issue: #<n>` trailer; append `Reverted-Issue: #<n>` as a final paragraph (`git commit --amend`). Park that issue `blocked` (comment plus label, left open, `.project/design-philosophy.md#Error & failure philosophy`), with the red gate's output as evidence. `skills/solve-milestone/milestone-granularity.md (The list names only issues whose trailer is on the branch, never a parked one.)` then drops that issue from the trailer query, the PR-body enumeration, and the close-list loop.

**Re-run once.** Re-run steps 5-7. Clean: re-run `skills/solve-milestone/changelog-authoring.md` steps 6.2-6.5 with the reverted issue excluded, then `## Milestone end: one push, one PR, one CI run` step 1. Still red: `## The run-scoped handler` below, not a second revert.

## The run-scoped handler

Stop the sequence: run `## Milestone end: one push, one PR, one CI run` steps 1-3 unchanged, then apply `Red CI on the milestone PR` in place of step 4's merge.

## The milestone review sub-entry

`skills/solve-milestone/milestone-granularity.md § Milestone end: one push, one PR, one CI run` step 3's "The milestone review gets a sub-entry too" bullet renders this sequence's step 4 `/code-review` result; nothing here restates it.
