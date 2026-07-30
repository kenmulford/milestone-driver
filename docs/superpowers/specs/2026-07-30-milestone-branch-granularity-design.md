# Milestone-scoped branch granularity: design

- **Issue:** #366
- **Milestone:** #33 (v1.18.0, milestone-scoped branching)
- **Status:** design of record for milestone #33. The milestone's other issues build against this
  document; it is not a proposal awaiting review.
- **Date:** 2026-07-30
- **Modifies:** `docs/superpowers/specs/2026-07-30-milestone-branch-granularity-design.md` (this
  file)
- **Does NOT modify:** no code or skill file changes in this pass. Design only.

## Overview / goal

Milestone granularity is a third `integrationGranularity` value, `"milestone"`, alongside today's
`"issue"` (the default) and `"wave"` (`docs/profile-schema.md:116`, `docs/architecture.md:229`).
One milestone run produces one local branch `milestone-<number>-<slug>`, one squash commit per
issue, one push, one PR into `integrationBranch`, and one CI run.

**What it fixes.** Consumer repos whose CI triggers on push to every branch exhaust GitHub runners
and container capacity while a milestone builds. `"wave"` granularity does not fix that: its
workers still push a branch per issue, and the wave branch is assembled "entirely from the
already-pushed per-issue logic branches" (`skills/solve-milestone/parallel-waves.md:175`). Wave
granularity trades O(issues) CI runs for O(waves) (`docs/profile-schema.md:206`); milestone
granularity trades them for O(milestones), and cuts the *pushes* as well as the PRs, which is the
part that triggers a push-on-every-branch workflow.

The second effect is independent of CI cost. A dependency chain builds straight through locally:
issue B cuts from the milestone branch with issue A's commit already on it, so there is no round
trip to origin per link in the chain.

**Scope boundary.**

| Boundary | Statement |
|---|---|
| Default | Stays `"issue"`. A profile with no `integrationGranularity` key behaves exactly as today (`docs/profile-schema.md:206`). |
| Existing paths | The `"issue"` and `"wave"` paths stay byte-unchanged. Nothing in this design edits either one. |
| Execution mode | Works under sequential and parallel execution alike. Sequential is the reference case; parallel workers inherit the behavior because the push suppression lives in `solve-issue` (resolved decision 1). |

## Branch model

| Element | Shape |
|---|---|
| Milestone branch | `milestone-<number>-<slug>`, cut from `integrationBranch` at run start |
| Issue branch | `issue/<n>-<slug>` (unchanged name, `.project/conventions.md#Naming`), cut from the **milestone branch**, never pushed |
| Integration | Local `git merge --squash issue/<n>-<slug>` plus a commit onto the milestone branch |
| Commit count | One commit per issue |

**Why the number leads the branch name.** The feeder's `update` can rename a milestone title, and
the slug is title-derived, so the slug can go stale mid-milestone. The milestone *number* never
changes. Leading with it keeps a branch cut before a rename identifiable afterward.

**Why issue branches keep their existing name.** `issue/<n>-<slug>` is already the convention
(`.project/conventions.md#Naming`) and already what `solve-issue` step 3 cuts. Milestone
granularity changes the branch's *base* (the milestone branch instead of `integrationBranch`) and
its *fate* (never pushed, squash-merged locally). It does not change the name, so nothing that
matches or greps on `issue/<n>-` needs to learn a second pattern.

The issue branch's working history stays local and disposable; the milestone branch carries exactly
one reviewable commit per issue.

## Commit-trailer resume mechanism

Every integration commit onto the milestone branch carries the trailer line:

```
Issue: #<n>
```

Resume state for issue `<n>` is then one local query:

```bash
git log <milestone-branch> --grep='^Issue: #<n>$'
```

A non-empty result means issue `<n>` is already integrated onto the milestone branch. Empty means
it is not.

**What this replaces.** Today's branch-state probe at `skills/solve-issue/SKILL.md:49-57` derives
resume state from `gh pr list` and `git ls-remote`, both of which read remote state. Under
milestone granularity nothing is pushed until the milestone ends, so both probes find nothing and
every issue looks like a cold start on a resumed run. The trailer query reads the one artifact that
*does* exist locally at that point.

**What this grounds.** The buildability check at `skills/solve-milestone/SKILL.md:204-208` makes
condition (a) "every issue in `dependencyGraph.edges["<n>"]` is already merged to
`integrationBranch`". Under milestone granularity nothing merges to `integrationBranch` until the
milestone-end merge, so condition (a) holds only where the edge list is empty. A Wave-1 issue with
no dependencies passes vacuously and builds. Any issue with a non-empty edge list stalls, because
the dependency it waits on never reaches `integrationBranch`. The trailer query is what condition
(a) reads instead: a dependency is satisfied when its integration commit is on the milestone
branch. Conditions (b) (live blocker label) and (c) (`issueStates[n].blockers == false`) are
untouched.

This keeps the no-checkpoint-file posture already stated for the existing probe
(`skills/solve-issue/SKILL.md:57`): resume state is derived from git, not from a file the run has
to maintain.

## Milestone-end sequence

1. **CHANGELOG commits onto the milestone branch.** The second PR on branch
   `docs/changelog-<slug>` is not opened (`skills/solve-milestone/SKILL.md:547-620`, steps
   6.6 to 6.8). The entry is authored exactly as today and committed onto the milestone branch, so
   it rides the one PR with everything else.
2. **Push `milestone-<number>-<slug>`.** This is the run's first push. Nothing before this point
   touched origin.
3. **Open one PR into `integrationBranch`,** carrying the aggregated `## Code Review` section. The
   section is required, not optional: `hooks/code-review-gate.sh` fires on both `gh pr create` and
   `gh pr merge`, so a PR body without an anchored `## Code Review` heading is denied at creation
   and again at merge.
4. **CI green, then `gh pr merge --squash --delete-branch`.**
5. **Close the issues explicitly,** one `gh issue close` call per issue:

   ```bash
   for n in <each issue number>; do gh issue close "$n" --reason completed; done
   ```

   The `Closes #n` keyword only fires on merge to the repository's default branch, and this PR
   targets `integrationBranch`, which is typically not the default branch
   (`skills/solve-milestone/parallel-waves.md:177`).

   **Known defect in the mirrored line.** `skills/solve-milestone/parallel-waves.md:177` ships the
   multi-issue form `gh issue close #a #b #c --reason completed`, which does not run. The command
   accepts exactly one issue (`gh issue close {<number> | <url>}`, gh 2.95.0), and an unquoted `#`
   opens a shell comment. Fixing that line is out of scope for milestone #33 and needs its own
   issue.
6. **Delete the local milestone branch and re-sync `integrationBranch`** (`git fetch`,
   fast-forward).

### Red CI on the milestone PR

Mirrors the CHANGELOG-PR handler at `skills/solve-milestone/SKILL.md:623-634`:

- Apply the `needs review` label to the milestone PR.
- Add one 🔴 line to the run output naming **every issue on the branch**, not just the milestone.
- Preserve the local milestone branch. The remote PR is still open and needs it.
- Do not re-attempt the merge.
- Do not close any issue. The work is unmerged, so every issue on the branch stays open.

The 🔴 line names every issue because a red milestone PR is the one failure mode where a human
inherits N issues' worth of work at once. A line that named only the PR would leave the operator to
reconstruct the contents from the diff.

## The visualHold gate

A milestone whose branch touches a `uiSurfaceGlobs` path (`docs/profile-schema.md:105`) gets the
`needs review` label and does **not** auto-merge. The PR is held open for human visual sign-off.

| Aspect | Rule |
|---|---|
| Trigger | Any path in the milestone branch's diff against `integrationBranch` matches `uiSurfaceGlobs` |
| Effect | Label `needs review`, hold the PR, no auto-merge |
| Sole override | The `visualHold: false` profile key |
| Key convention | Omit-the-default: absent means hold, matching `versioning` and `integrationGranularity` (`docs/profile-schema.md:190`) |
| Undeterminable diff | **Fail toward holding.** When the diff against `integrationBranch` cannot be determined, the gate holds the PR rather than auto-merging. |

Failing toward holding is the direction that cannot silently merge unreviewed UI. The opposite
default would turn every transient git failure into an unreviewed UI merge, which is exactly the
outcome invariant 3 exists to prevent.

**Relationship to invariant 3.** `docs/architecture.md:103-109` states three visual-capture
invariants; invariant 3 is "Never auto-merge a UI issue", with no override. This design amends that
invariant with **one explicit operator override**, `visualHold: false`, and scopes the amendment to
milestone granularity only. Issue and wave granularity keep today's per-issue visual gate untouched
and keep invariant 3 absolute. The override exists because milestone granularity collapses N issues
into one PR: without it, a single UI-touching issue anywhere in a milestone holds the whole
milestone, and a repo that does not want that has no per-issue escape hatch left to reach for.

## Non-goals

- **Part B, the milestone-bootstrapper foreign-workflow CI-filter rule.** A separate repo, specced
  and shipped after Part A. Nothing in this design depends on it.
- **Docker-based local validation.** Not part of this design.
- **A new `skills/notices.md` discovery section.** No one-time discovery notice ships (resolved
  decision 5).
- **Any `hooks/` change.** `hooks/code-review-gate.sh` is read and depended on, not modified.
- **Any new `scripts/` helper.** No new script twin is added by this design.
- **`solve-issue` step 6.4's per-issue version bump.** Its behavior is out of scope here.

## Resolved decisions

1. **Milestone granularity works in sequential mode.** The push suppression lives in `solve-issue`,
   not in the sequential loop, so parallel workers inherit it for free: worker mode "is today's
   `solve-issue` pipeline with EXACTLY THREE DELTAS"
   (`skills/solve-issue/worker-mode.md:9`). **Rejected: forcing parallel mode when
   `integrationGranularity: "milestone"` is set.** Not implementable. The permission-allowlist
   barrier is unconditional and "overrides even `parallel: true` downward"
   (`skills/solve-milestone/SKILL.md:109`), so a granularity key cannot force parallel up past it;
   and forcing parallel would silently override a standing `parallel: false` opt-out, which is a
   deliberate operator decision the granularity key has no business reversing.

2. **`milestoneBranchPush` is dropped entirely.** Ship the `"final"` behavior as the only behavior:
   no profile key, no interview question, no cascade row. **Rejected: a `milestoneBranchPush`
   key with a `"per-issue"` value.** Two reasons, both grounded. No issue in this milestone stated
   a benefit for `"per-issue"`, and per-push-per-issue is precisely the CI-exhaustion behavior
   milestone granularity exists to remove, so the key's only setting would undo the feature. And
   wave granularity set the precedent for this exact situation: it **states** its trade-off ("one
   red wave-PR CI blocks the whole Wave") and **accepts** it in prose, rather than shipping a knob
   to undo it (`docs/profile-schema.md:206`). Recorded here so the key does not get re-proposed as
   an obvious missing escape hatch: it was considered and ruled out, not overlooked.

3. **A size-budget ceiling raise is recorded in the PR's Decision Log.** Amend the `.sh` ratchet
   header to say so (`scripts/check-size-budgets.sh:18-19` today says a raise "requires a recorded
   decision on the issue that grows the file"), and mirror the clause into the `.ps1` twin, which
   drops it today (`scripts/check-size-budgets.ps1:3-5` defers to the `.sh` header for the full
   discipline). Every other per-change decision in this repo already lives in the PR body
   (`.project/conventions.md#Commits & PRs`: "Every PR body carries a **Decision Log**").

4. **`--no-visual-hold` is dropped.** `visualHold: false` in `.milestone-config/driver.json` is the
   sole override. **Rejected: a `--no-visual-hold` invocation token.** No runtime discriminator
   exists between a human-typed token and an internally-supplied one, so a token override could be
   injected by any dispatch path and there is no way for the gate to tell an operator's deliberate
   override from a caller's. A visual-hold override is a human decision, and the profile key is the
   only surface that records one durably and reviewably. The profile-key-only shape is already
   ratified for the analogous control: `parallel: false` is "the **only** force-sequential surface"
   and "there is **no `--sequential` flag**" (`docs/consumer-setup.md:94`). Recorded here so the
   token does not get re-proposed as a per-run convenience.

5. **No one-time discovery notice.** The `"issue"` default stays byte-unchanged
   (`docs/profile-schema.md:206`), so no existing consumer has anything silently switched off and
   there is nothing for a notice to warn about. Discovery arrives through the setup Integration
   tier (`docs/profile-schema.md:83`, the Integration tier that already prompts for
   `integrationGranularity`) and the consumer docs.

## Cross-references

- `docs/profile-schema.md:83` and `:116` are the `integrationGranularity` tier row and schema row
  that gain the `"milestone"` value.
- `docs/profile-schema.md:105` is `uiSurfaceGlobs`, which drives the `visualHold` gate's trigger.
- `docs/profile-schema.md:190` is the omit-the-default convention `visualHold` follows.
- `docs/profile-schema.md:206` is the `integrationGranularity` note: the byte-unchanged `"issue"`
  default, and wave granularity's state-the-trade-off precedent behind resolved decision 2.
- `docs/architecture.md:103-109` are the three visual-capture invariants; invariant 3 ("Never
  auto-merge a UI issue") is what the `visualHold` gate amends for milestone granularity only.
- `docs/architecture.md:229` is the existing `integrationGranularity` definition and its
  orthogonality to execution mode.
- `docs/consumer-setup.md:94` is the `parallel: false` profile-key-only precedent behind resolved
  decision 4.
- `skills/solve-issue/SKILL.md:49-57` is the step-3 branch-state probe the commit-trailer query
  replaces.
- `skills/solve-issue/worker-mode.md:9` is the "EXACTLY THREE DELTAS" carry-over that makes
  suppression in `solve-issue` reach parallel workers.
- `skills/solve-milestone/SKILL.md:109` is the unconditional permission-allowlist barrier behind
  resolved decision 1.
- `skills/solve-milestone/SKILL.md:204-208` are the three buildability conditions; (a) reads the
  commit trailer under milestone granularity.
- `skills/solve-milestone/SKILL.md:547-620` are CHANGELOG steps 6.6 to 6.8, whose separate
  `docs/changelog-<slug>` PR is replaced by a commit onto the milestone branch.
- `skills/solve-milestone/SKILL.md:623-634` is the CHANGELOG-PR red-CI handler the milestone-PR
  red-CI handling mirrors.
- `skills/solve-milestone/parallel-waves.md:175` is the wave-branch assembly that still requires a
  push per issue.
- `skills/solve-milestone/parallel-waves.md:177` is the explicit `gh issue close`, and why the
  `Closes #n` keyword does not fire against `integrationBranch`.
- `hooks/code-review-gate.sh` fires on both `gh pr create` and `gh pr merge`, which is why the one
  milestone PR must carry an aggregated `## Code Review` section.
- `scripts/check-size-budgets.sh:45-59` is the governed-`FILES` array. `docs/superpowers/` has no
  entry, so no line-count ceiling governs this file.
- `scripts/check-size-budgets.sh:18-19` and `scripts/check-size-budgets.ps1:3-5` are the ratchet
  headers resolved decision 3 amends and mirrors.
- `.project/conventions.md#Naming` is the `issue/<n>-<slug>` branch convention, kept unchanged.
- `.project/conventions.md#Commits & PRs` is the Decision-Log-in-the-PR-body convention behind
  resolved decision 3.
- `docs/superpowers/specs/2026-07-04-md-epic-driver-fanout-design.md` is the section shape this
  spec mirrors.
