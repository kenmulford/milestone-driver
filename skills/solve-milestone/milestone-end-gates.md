# Milestone end gates: solve-milestone reference

Loaded once per run from `skills/solve-milestone/milestone-granularity.md`'s `## Milestone end: one push, one PR, one CI run`, after the simplify pass and before that section's step 1. Runs only under `"milestone"` granularity.

## Contents

The ordered sequence · Empty diff · The fix-dispatch loop · Cap spent, still red · The milestone review sub-entry

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

The cap is spent and a `/code-review` finding or a gate from steps 5 to 7 is still red: stop the sequence. Run `## Milestone end: one push, one PR, one CI run` steps 1 to 3 unchanged, then apply the `Red CI on the milestone PR` handling in place of step 4's merge.

## The milestone review sub-entry

Render step 4's `/code-review` result per `skills/solve-issue/SKILL.md` step 6.1's `Code-Review:` block shape, effort the verdict's, on the post-fix tree when a fix landed. `skills/solve-milestone/milestone-granularity.md (## Milestone end: one push, one PR, one CI run)` step 3 discovers it by its own `Milestone-End-Fix: <milestone-number>` key, the way it discovers `Simplify-Pass: `, and renders it as `### milestone review`. No commit found means the sequence converged with no fix dispatch: render step 4's own zero-finding result instead. Unlike `/simplify`'s sub-entry, this one is never omitted.
