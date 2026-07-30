# Milestone granularity: solve-milestone reference

This file is loaded by solve-milestone when the profile resolves `integrationGranularity: "milestone"` (`docs/profile-schema.md:116`). It holds the milestone branch model, the local per-issue squash-merge both callers run, and the integration commit whose trailer carries each issue's audit trail and answers every resume question while nothing is pushed. Under `"issue"` or `"wave"` granularity this file is **never read**: those paths are byte-unchanged, and this file's absence causes no error and no behavior change. If it is **missing or unreadable** at the point solve-milestone needs it (granularity already resolved to `"milestone"`), that is a **systemic failure**: surface it and halt the run per core `SKILL.md`'s `## Autonomy` → "Systemic failures that halt the run", the same class as a missing `parallel-waves.md` under parallel mode. Do **not** silently degrade to `"issue"` granularity; that pushes a branch per issue, which is the CI-exhaustion behavior the key was set to remove. This is core machinery for the resolved granularity, not a best-effort integration like `trello-sync.md`.

---

## Branch model

| Element | Shape |
|---|---|
| Milestone branch | `milestone-<number>-<slug>`, cut from `integrationBranch` at run start |
| Issue branch | `issue/<n>-<slug>`, name unchanged (`.project/conventions.md#Naming`), cut from the **milestone branch**, never pushed |
| Integration | Local `git merge --squash issue/<n>-<slug>` plus one commit onto the milestone branch |
| Commit count | One commit per issue |
| Push count | One, at milestone end (#371). Nothing reaches origin before it, unconditionally: there is no per-issue push and no profile key that enables one. |

**Why the number leads the branch name.** The feeder's `update` can rename a milestone title, and the slug is title-derived, so the slug can go stale mid-milestone. The milestone number never changes, so a branch cut before a rename stays identifiable after it.

**Why issue branches keep their name.** `issue/<n>-<slug>` is already the convention (`.project/conventions.md#Naming`) and already what `solve-issue` step 3 cuts. Milestone granularity changes the branch's **base** (the milestone branch instead of `integrationBranch`) and its **fate** (never pushed, squash-merged locally). The name is unchanged, so nothing that matches or greps on `issue/<n>-` learns a second pattern.

The issue branch's working history stays local and disposable. The milestone branch carries exactly one reviewable commit per issue.

---

## Folding an issue into the milestone branch

**One description, two callers.** The **sequential loop** (core `SKILL.md` `### 4. Loop over issues in dependency-graph order`, run inline by the orchestrator once an issue's `solve-issue` returns) and the **parallel Phase 2 serial verified merge tail** (`skills/solve-milestone/parallel-waves.md:143-152`) both run the steps below, unchanged. Phase 2's integration target is already parameterized (`parallel-waves.md:149`: `<target>` is `integrationBranch` in issue granularity, the wave branch in wave granularity); milestone granularity adds the **milestone branch** as that parameter's third value. Neither caller carries its own copy of these mechanics.

On the milestone branch, for one built issue `<n>`:

1. **Squash-merge the issue branch.** `git merge --squash issue/<n>-<slug>`. This stages the accumulated result (everything already folded in, plus this issue) without committing, so step 2 re-verifies against integrated state, the same "every increment tested against accumulated state" guarantee the per-issue tail states (`parallel-waves.md:147`). Merging the target back into the issue branch first is unnecessary here, and nothing is pushed, so `parallel-waves.md:154`'s force-free reasoning has no push to apply to.
2. **Re-verify against the staged state.** Run `unitTestCmd` if defined, plus the gates the worker deferred (E2E, any server-starting preflight), exactly as `parallel-waves.md:150` runs them: once, against accumulated state.
3. **Commit.** Green → one commit in the shape below. That commit is the issue's whole footprint on the milestone branch.

**Conflict and red re-verify.** The **policy** is `parallel-waves.md:150-152`'s, unchanged and identical for both callers: bounded auto-resolve, else park `blocked`, preserve the branch, continue with the next issue. The **recovery mechanics necessarily differ**, because that path's step 1 is a real `git merge` on a per-issue disposable worker branch while step 1 above is `git merge --squash` onto the persistent milestone branch. **First**, `git merge --squash` never writes `MERGE_HEAD`, so `git merge --abort` cannot be used here: it fails with `fatal: There is no merge to abort (MERGE_HEAD missing).` and leaves the conflicted tree in place. Recover with `git restore --staged --worktree .`, which returns the tree to the last folded commit and leaves `HEAD` untouched. Do **not** substitute `git reset --hard HEAD`: it also works, but consumer destructive-command hooks routinely block `git reset --hard` by pattern, the same class of guard that made a history-rewriting push non-viable (`parallel-waves.md:154`), and a recovery command a consumer's guard blocks is not a recovery command. **Second**, **both** park branches below run that same `git restore` before moving to the next issue. `parallel-waves.md` needs no discard because each issue folds on its own disposable worker branch, so parked state is inert; here every issue folds onto the **same** milestone branch with no branch switch between issues, so an undiscarded fold corrupts the next one: a staged clean merge is silently swallowed by the next issue's commit, and a conflicted tree fails it outright (`error: Merging is not possible because you have unmerged files`).

- **Conflict** → **bounded auto-resolve** with full-milestone context (git's `ort` strategy already resolves non-overlapping same-file edits), then re-verify. Resolvable **and** green → commit per step 3. Non-trivial or ambiguous **or** red → `git restore --staged --worktree .`, **park `blocked`** (comment + label + preserve the issue branch), continue with the next issue.
- **Clean merge, red re-verify** → `git restore --staged --worktree .`, **park `blocked`** (the combination is broken; a human decides), continue with the next issue.

A parked issue leaves no commit on the milestone branch, so its trailer never appears and every issue depending on it stays unbuildable this run (see below). The milestone branch itself is preserved on a park, exactly as the parked issue's branch is.

---

## The integration commit

Subject line, a blank line, the Decision Log summary, a blank line, the Code Review block, a blank line, then `Issue: #<n>` as the last line:

```text
<type>(#<n>): <issue title>

- <choice> · <rationale> · <citation> · <rejected alternatives>
- … (one Decision Log entry per line, per `skills/output-style.md:78`)

Code-Review:
  - /code-review run: yes (omission is a park trigger — a submitted PR always carries a real review; a parked run opens no PR)
  - Findings: <count> in-scope finding(s) at <effort> effort
    - <finding> — <file:line it named> → re-dispatched and resolved | accepted (rationale: <…>) | triggered park
    - … (one line per finding, or "none" when count is 0)
  - No park-triggering findings. | Park-triggering findings: <list>

Issue: #<n>
```

**The Code Review block is copied, not re-derived.** Its five lines are the PR-body Code Review template (`skills/solve-issue/SKILL.md:198-202`) with their relative nesting intact and each indented two further spaces, under a `Code-Review:` opener. The block ends at the blank line before `Issue: #<n>`. Those five lines carry every slot of the `## Code Review` shape (`skills/output-style.md:79`): run + effort, finding count, per-finding resolution, evidence (the `file:line` each finding named), park-trigger list. A **zero-finding run keeps the same shape**: its per-finding line reads `none`, and the run's effort level stands as the evidence slot. Dropping a slot to shorten the commit message is incomplete, not concise (`skills/output-style.md:90`).

Two rules make the block safe to carry in a commit message:

- **The opener is the line `Code-Review:` at column 0, never a `## Code Review` heading.** The milestone PR body (#371) aggregates these blocks under **exactly one** anchored `## Code Review` heading, the shape `hooks/code-review-gate.sh` matches on both `gh pr create` and `gh pr merge` (`hooks/code-review-gate.sh:72`, `:79-83`). A heading carried inside each commit would put one per issue into that body.
- **Every line under the opener is indented.** No line of the block can then be read as a trailer, so the commit's final paragraph stays the single `Issue: #<n>` line each existing consumer parses.

---

## Resume and buildability from the trailer

One local query answers whether issue `<n>` is already integrated:

```bash
git log <milestone-branch> --grep='^Issue: #<n>$'
```

Non-empty output means that issue's commit is on the milestone branch. Empty means it is not.

**What it replaces.** The step-3 branch-state probe (`skills/solve-issue/SKILL.md:49-57`) derives resume state from `gh pr list` and `git ls-remote`, both of which read remote state. Under milestone granularity nothing is pushed until milestone end, so both find nothing and every issue looks like a cold start on a resumed run. The trailer query reads the one artifact that does exist locally at that point, and keeps resume state derived from git with no checkpoint file to maintain (`skills/solve-issue/SKILL.md:57`).

**What it re-grounds.** Buildability condition (a) (`skills/solve-milestone/SKILL.md:204-208`) asks whether every issue in `dependencyGraph.edges["<n>"]` is already merged to `integrationBranch`. Nothing merges to `integrationBranch` until milestone end, so condition (a) reads the milestone branch instead: a dependency is satisfied when the query above finds its trailer. Conditions (b) (live blocker label) and (c) (`issueStates[n].blockers == false`) are untouched.

**Empty state.** A trailer the query does not find is the normal unmet-dependency state, not an error. Condition (a) stays false for the issues that depend on `<n>` until the trailer appears, and nothing is logged or surfaced. On the first pass of a fresh run no trailer exists for any issue, which is the correct reading of an empty milestone branch rather than a fault to report.
