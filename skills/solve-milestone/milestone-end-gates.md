# Milestone end gates: solve-milestone reference

Loaded once per run from `skills/solve-milestone/milestone-granularity.md`'s `## Milestone end: one push, one PR, one CI run`, after the simplify pass and before that section's step 1. Runs only under `"milestone"` granularity.

## Contents

The ordered sequence · Empty diff · The fix-dispatch loop · Cap spent, still red · Attribution and revert · The run-scoped handler · The milestone review sub-entry

---

## The ordered sequence

Run these once over `<range>` (`git diff <integrationBranch>...<milestone-branch>`), in this order and no other.

| # | Step | Detail |
|---|---|---|
| 1 | Diff | `<range>`, read-only |
| 2 | Empty diff | No commits over `integrationBranch`: `## Empty diff` below, and end here |
| 3 | Coherence review | Dispatch the coherence agent read-only against `<range>`, `skills/solve-issue/coherence-review.md (### The pass)`. `skills/solve-issue/coherence-review.md (Never-gating.)` holds here too: its findings never enter the fix-dispatch cap |
| 4 | `/code-review` | One reviewer leaf, at the verdict `scripts/classify-review-depth.sh <repo-root> <integrationBranch>` returns, per `scripts/classify-review-depth.sh (Usage:)`, rooted at the milestone branch's checkout |
| 5 | Unit gate | `${CLAUDE_PLUGIN_ROOT}/scripts/unit-gate.<sh\|ps1> <repo-root>` (pwsh on Windows, bash elsewhere), never `unitTestCmd` directly |
| 6 | E2E | Only when an issue on the branch carries the `ui` label |
| 7 | Preflight | The Preflight row of `skills/solve-issue/SKILL.md § 4. Verification gates`. `skills/solve-issue/SKILL.md (the Preflight row above does not apply)` under the `"github-ci"` sentinel: this step defers to the milestone PR's own CI |
| 8 | Converge or fix | Nothing collected: `## Milestone end: one push, one PR, one CI run` step 1 proceeds. Otherwise: `## The fix-dispatch loop` |

## Empty diff

No commits over `integrationBranch`: log one line, end the sequence here, mirroring `skills/solve-milestone/simplify-pass.md (Zero findings, or a failure)` and `skills/solve-milestone/milestone-granularity.md (Nothing merged.)`. `## Milestone end: one push, one PR, one CI run` step 1 proceeds unchanged.

## The fix-dispatch loop

Collect every `/code-review` finding from step 4 and every red gate from steps 5 to 7. Coherence findings from step 3 never enter this set.

- Nothing collected: the pass converged. Proceed to `## Milestone end: one push, one PR, one CI run` step 1.
- One or more collected: dispatch the `implementerAgent` once, briefed with `<range>` and every collected finding and failure. It returns an uncommitted working tree, per its own contract.
- Commit: subject line, the fix's summary, then a final paragraph of exactly `Milestone-End-Fix: <milestone-number>`, the milestone path's shape at `skills/solve-milestone/simplify-pass.md (## Land the findings)`. No `Issue:` line.
- Re-run the sequence from step 1.

**Cap.** At most 3 fix dispatches per milestone end. The existing `hooks/dispatch-cap.sh (Agent "$implementer")` row enforces it, keyed on the milestone branch. A denied dispatch goes to `## Cap spent, still red`.

## Cap spent, still red

The cap is spent and a `/code-review` finding is still open: take `## The run-scoped handler` below.

The cap is spent and a gate from steps 5 to 7 is still red: attribute the failure and revert its commit, below.

## Attribution and revert

**Name the commit.** The red gate names the failing test's file. Diff each issue commit on `<range>` against its parent (`git show --name-only --format= <commit>`) for that file. Exactly one match names that commit's `Issue: #<n>` trailer as the culprit.

**No match, or more than one: bisect.** `git bisect start <milestone-branch> <integrationBranch>`, then `git bisect run` with the red gate's own command. One first-bad commit names the culprit the same way. No single commit: take `## The run-scoped handler` below, no revert, no park.

**Revert and park.** `git revert <commit>`, which keeps the reverted commit's `Issue: #<n>` trailer in history. Park that issue `blocked` (comment plus label, issue left open, `.project/design-philosophy.md#Error & failure philosophy`), the red gate's output as the comment's evidence. Hold the reverted issue number in run state: `skills/solve-milestone/milestone-granularity.md (The list names only issues whose trailer is on the branch, never a parked one.)` reads it to drop that issue from the PR-body enumeration and the close-list loop.

**Re-run once.** Re-run steps 5 to 7 once. Clean: proceed to `## Milestone end: one push, one PR, one CI run` step 1. Still red: `## The run-scoped handler` below, not a second revert.

## The run-scoped handler

Stop the sequence. Run `## Milestone end: one push, one PR, one CI run` steps 1 to 3 unchanged, then apply the `Red CI on the milestone PR` handling in place of step 4's merge.

## The milestone review sub-entry

Render step 4's `/code-review` result per `skills/solve-issue/SKILL.md` step 6.1's `Code-Review:` block shape, effort the verdict's, on the post-fix tree when a fix landed. `skills/solve-milestone/milestone-granularity.md (## Milestone end: one push, one PR, one CI run)` step 3 discovers it by its own `Milestone-End-Fix: <milestone-number>` key, the way it discovers `Simplify-Pass: `, and renders it as `### milestone review`. No commit found means the sequence converged with no fix dispatch: render step 4's own zero-finding result instead. Unlike `/simplify`'s sub-entry, this one is never omitted.
