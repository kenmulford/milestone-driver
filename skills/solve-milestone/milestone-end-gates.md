# Milestone end gates: solve-milestone reference

Loaded once per run from `skills/solve-milestone/milestone-granularity.md`'s `## Milestone end: one push, one PR, one CI run` (the PR section), after the simplify pass, before its step 1.

## Contents

The ordered sequence · The fix-dispatch loop · Cap spent, still red · Attribution and revert · The run-scoped handler · The milestone review sub-entry

---

## The ordered sequence

Run these once over the read-only `<range>` (`git diff <integrationBranch>...<milestone-branch>`).

| # | Step | Detail |
|---|---|---|
| 2 | Empty diff | First run `${CLAUDE_PLUGIN_ROOT}/scripts/reset-dispatch-cap.<sh\|ps1> <repo-root> milestone-<n>`, so a resumed entry starts a fresh cap. No commits over `integrationBranch`: log one line, end the sequence; the PR section's step 1 proceeds |
| 3 | Coherence review | Only when `coherenceReviewAgent` is configured, else skip silently; dispatch it read-only against `<range>` per `skills/solve-issue/coherence-review.md (### The pass)`; its findings never enter the loop |
| 4 | `/code-review` | Per `skills/review-depth.md`, run `scripts/classify-review-depth.sh <repo-root> <integrationBranch>`, then run `/code-review` on the main line at the verdict's first-run effort with the ladder's flag. Each reviewer leaf is a `milestone-driver:reviewer` briefed with `<repo-root>` as worktree, the one sha `git merge-base <integrationBranch> HEAD` as `<base>` (so its diff holds an uncommitted fix), and `${CLAUDE_PLUGIN_ROOT}/scripts/classify-delta.<sh\|ps1>`; a `NO VERDICT` is re-dispatched once naming that input, then takes **Halt.** |
| 5 | Unit gate | `${CLAUDE_PLUGIN_ROOT}/scripts/unit-gate.<sh\|ps1> <repo-root>`, never `unitTestCmd` directly |
| 6 | E2E | Only when an issue on the branch carries the `ui` label and `e2eTestCmd` is defined: run `e2eTestCmd` against `e2eEnv` |
| 7 | Preflight | The Preflight row of `skills/solve-issue/SKILL.md § 4. Verification gates`. Under the `"github-ci"` sentinel it defers to the milestone PR's CI |
| 8 | Converge or fix | Nothing collected: the PR section's step 1 proceeds. Otherwise: `## The fix-dispatch loop` |

## The fix-dispatch loop

Collect every `/code-review` finding from step 4, each `→ open` Critical or Important finding in the `Simplify-Pass: <milestone-number>` commit's `Code-Review:` block, and every red gate from steps 5-7. Every implementer and planner brief's first line is `Milestone-End-Fix: <milestone-number>`, before any `Issue:` header.

- **Fix.** First write `<main-repo-root>/.milestone-config/.runtime/triage/milestone-<n>-findings.md`: each open finding as prefix and `<path>:<line>`, each red gate's output, the cited files. One `implementerAgent` dispatch on `agents/implementer.md`'s no-packet inputs: header `Issue: milestone-<n>`, that file as the plan, file scope `git diff --name-only <range>` plus one `Added scope: <path> (pre-existing <severity> finding)` line per pre-existing finding, the profile, `citationFormatPath`, expanded `domainSkills`; re-run from step 4 as the verify review, never step 3.
- **Commit.** Subject line, fix summary, step 4's `/code-review` result plus each fixed `Simplify-Pass` finding `→ re-dispatched and resolved`, in the `Code-Review:` block shape of `skills/solve-milestone/milestone-granularity.md (Wave granularity keeps the block.)`, final paragraph exactly `Milestone-End-Fix: <milestone-number>`; no `Issue:` line.
- **Route.** After a verify review, a Critical or Important finding on a line a fix commit added (`git diff <fix-commit>^ <fix-commit>`) sends the next dispatch to `milestone-driver:planner` while unspent, carrying every open Critical and Important finding.
- **Redesign.** The findings file, its fix shas added from the second dispatch on, and the packet `plans/milestone-<n>-redesign.md` in the same `.runtime/`. The brief carries an issue's inputs, worktree the milestone checkout, header `Issue: milestone-<n>`, `## Files` as `git diff --name-only <range>`. Approve with `scripts/check-packet.{sh,ps1} <packet> <repo-root>`; exit 0: one `implementerAgent` dispatch on it, Commit, re-run from step 4.

**Cap.** Per milestone end, 3 implementer dispatches (the redesign build included) and 1 planner dispatch, counted by `hooks/dispatch-cap.sh`'s `milestone-<n>` counter; an implementer dispatch the hook denies takes `## Cap spent, still red`.

## Cap spent, still red

**Precedence.** A Critical or Important finding open takes **Halt.**, ahead of a red gate; else a red gate from steps 5-7 takes attribution and revert; every gate green with only Minor findings open takes `## The run-scoped handler`.

**Halt.** Also taken by a planner `PARK`, a check-packet failure, a planner `DOMAIN_SKILLS_INVOKED` missing an expanded name, a second `NO VERDICT`, or an implementer `STATUS: STOPPED` from any milestone-end dispatch. Print `🔴 Milestone <milestone-number> halted before the PR (<cause>): [<Severity>] <path>:<line> <finding>; ...`, `<cause>` is `cap spent`, `planner PARK`, `check-packet FAIL`, `skill miss`, `no verdict` (the input the `NO VERDICT` named replaces the finding list), `implementer STOPPED`; run `${CLAUDE_PLUGIN_ROOT}/scripts/reset-dispatch-cap.<sh|ps1> <repo-root> milestone-<n>`; push nothing, open no PR, file no issue, post no comment; the branch stays local; the run ends (`.project/design-philosophy.md#Error & failure philosophy`).

## Attribution and revert

**Name the commit.** The red gate names the failing test's file; diff each issue commit on `<range>` against its parent (`git show --name-only --format= <commit>`); one match is a **candidate**.

**Confirm the candidate.** Run the red gate's command at the parent (expect green) and at the candidate (expect red). Both hold → revert it. Either fails: bisect.

**No match, more than one, or unconfirmed: bisect.** `git bisect start <milestone-branch> <integrationBranch>`, then `git bisect run` with the red gate's command. Record the first-bad sha, then `git bisect reset`. Its own `Issue: #<n>` trailer names the culprit. No single first-bad commit, or one with no `Issue: #<n>` trailer: take `## The run-scoped handler`, no revert, no park.

**Revert and park.** `git revert --no-edit <commit>`, keeping the reverted commit's `Issue: #<n>` trailer; append `Reverted-Issue: #<n>` as a final paragraph (`git commit --amend`). Park that issue `blocked`, with the red gate's output as evidence. `skills/solve-milestone/milestone-granularity.md (The list names only issues whose trailer is on the branch, never a parked one.)` then drops that issue from the trailer query, the PR-body enumeration, and the close-list loop.

**Re-run once.** Re-run steps 5-7. Clean: re-run `skills/solve-milestone/changelog-authoring.md` steps 6.2-6.5 with the reverted issue excluded, then the PR section's step 1. Still red: `## The run-scoped handler`, not a second revert.

## The run-scoped handler

Stop the sequence: run the PR section's steps 1-3 unchanged, then apply `Red CI on the milestone PR` in place of step 4's merge. Each open Minor finding's milestone-review line carries the disposition `→ open (cap spent; PR left unmerged)`.

## The milestone review sub-entry

`skills/solve-milestone/milestone-granularity.md (The milestone review gets a sub-entry too)` renders step 4's `/code-review` result.
