# Milestone granularity: solve-milestone reference

Loaded when the profile resolves `integrationGranularity: "milestone"` (`docs/profile-schema.md (How should built issues integrate?)`). Missing or unreadable at that point is a **systemic failure**: surface it and halt the run per core `SKILL.md`'s `## Autonomy` → "Systemic failures that halt the run". Do **not** silently degrade to `"issue"` granularity; that pushes a branch per issue, the CI exhaustion the key was set to remove.

## Contents

Branch model · Folding an issue into the milestone branch · The integration commit · Resume and buildability from the trailer · Milestone end: one push, one PR, one CI run (The visualHold gate · Red CI on the milestone PR) · Creating the milestone branch: resume-safe pre-clean guard

---

## Branch model

| Element | Shape |
|---|---|
| Milestone branch | `milestone-<number>-<slug>`, cut from `integrationBranch` at run start |
| Issue branch | `issue/<n>-<slug>`, name unchanged (`.project/conventions.md#Naming`), cut from the **milestone branch**, never pushed |
| Integration | Local `git merge --squash issue/<n>-<slug>` plus one commit onto the milestone branch |
| Commit count | One commit per issue |
| Push count | One, at milestone end (#371). Nothing reaches origin before it, unconditionally: there is no per-issue push and no profile key that enables one. |

The number leads the branch name because the title-derived slug can go stale mid-milestone (the feeder's `update` renames titles); the number never changes. A built issue's branch keeps its name (`.project/conventions.md#Naming`): milestone granularity changes only a branch's **base** and its **fate**, never its name.

---

## Folding an issue into the milestone branch

**One description, two callers:** the **sequential loop** (core `SKILL.md` `### 4. Loop over issues in dependency-graph order`) and the **parallel Phase 2 serial verified merge tail** (`skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 2: serial verified merge tail`) both run the steps below. Phase 2's `<target>` parameter is already `integrationBranch` (issue granularity) or the wave branch (wave granularity); milestone granularity adds the **milestone branch** as its third value.

On the milestone branch, for one built issue `<n>`:

1. **Squash-merge the issue branch.** `git merge --squash issue/<n>-<slug>`. This stages the accumulated result without committing, so step 2 re-verifies against integrated state (`skills/solve-milestone/parallel-waves.md (Run on the main working tree)`). Merging the target back into the issue branch first is unnecessary here: nothing is pushed.
2. **Re-verify against the staged state.** Run `unitTestCmd` if defined, plus the gates the concurrent stage deferred (E2E, any server-starting preflight), exactly as `parallel-waves.md`'s Phase 2 step 2 runs them: once, against accumulated state.
3. **Commit.** Green → one commit in the shape below. That commit is the issue's whole footprint on the milestone branch.

**Conflict and red re-verify.** The **policy** is `skills/solve-milestone/parallel-waves.md (push (fast-forward))`'s, identical for both callers: bounded auto-resolve, else park `blocked`, preserve the branch, continue with the next issue. The **recovery mechanics necessarily differ**, because that path merges on a disposable per-issue branch while step 1 above squash-merges onto the persistent milestone branch. **First**, `git merge --squash` never writes `MERGE_HEAD`, so `git merge --abort` cannot be used here: it fails with `fatal: There is no merge to abort (MERGE_HEAD missing).` and leaves the conflicted tree in place. Recover with `git restore --staged --worktree .`, which returns the tree to the last folded commit and leaves `HEAD` untouched. Do **not** substitute `git reset --hard HEAD`: consumer destructive-command hooks routinely block that pattern (`skills/solve-milestone/parallel-waves.md (Why merge-in, not rebase + force)`). **Second**, **both** park branches below run that same `git restore` before moving to the next issue: every issue folds onto the **same** milestone branch with no branch switch between issues, so an undiscarded fold corrupts the next one — a staged clean merge is silently swallowed by the next issue's commit, and a conflicted tree fails it outright (`error: Merging is not possible because you have unmerged files`).

- **Conflict** → **bounded auto-resolve** with full-milestone context (git's `ort` strategy already resolves **non-adjacent** same-file edits; two edits on directly adjacent lines conflict, so a file with one shared append point conflicts by construction under concurrency), then re-verify. **That shape is *within* bounded auto-resolve, not a park trigger:** both hunks are additive and order is not semantically load-bearing. Park stays for genuinely ambiguous semantics, a conflict still non-trivial after the attempt, or a red re-verify. Resolvable **and** green → commit per step 3. Non-trivial or ambiguous **or** red → `git restore --staged --worktree .`, **park `blocked`** (comment + label + preserve the issue branch), continue with the next issue.
- **Clean merge, red re-verify** → `git restore --staged --worktree .`, **park `blocked`** (the combination is broken; a human decides), continue with the next issue.

A parked issue leaves no commit, so its trailer never appears and its dependents stay unbuildable this run. The milestone branch itself is preserved on a park, exactly as the parked issue's branch is.

---

## The integration commit

Subject line, a blank line, the Decision Log summary, a blank line, the Code Review block, a blank line, then `Issue: #<n>` as the last line:

```text
<type>(#<n>): <issue title>

- <choice> · <rationale> · <citation> · <rejected alternatives>
- … (one Decision Log entry per line, per `skills/output-style.md (Decision Log entry** (PR body))`)

Code-Review:
  - /code-review run: yes (omission is a park trigger — a submitted PR always carries a real review; a parked run opens no PR)
  - Findings: <count> in-scope finding(s) at <effort> effort
    - <finding> — <the ref it named, per skills/citation-format.md> → re-dispatched and resolved | accepted (rationale: <…>) | triggered park
    - … (one line per finding, or "none" when count is 0)
  - No park-triggering findings. | Park-triggering findings: <list>

Issue: #<n>
```

**The Code Review block is copied, not re-derived.** Its five lines are the PR-body Code Review template (`skills/solve-issue/SKILL.md (/code-review run: yes)`), relative nesting intact, each indented two further spaces under a `Code-Review:` opener; the block ends at the blank line before `Issue: #<n>`. The five lines carry every slot of the `## Code Review` shape (`skills/output-style.md (run + effort · finding count)`), evidence included. A **zero-finding run keeps the shape**: per-finding line `none`, effort level as the evidence slot. Dropping a slot to shorten the commit message is incomplete, not concise (`skills/output-style.md (Guardrail — concision cuts prose)`).

Two rules make the block safe to carry in a commit message:

- **The opener is the line `Code-Review:` at column 0, never a `## Code Review` heading.** The milestone PR body aggregates these blocks under **exactly one** anchored `## Code Review` heading, the shape `hooks/code-review-gate.sh` matches on both `gh pr create` and `gh pr merge` (`hooks/code-review-gate.sh (heading='## Code Review')`, `hooks/code-review-gate.sh (heading_match <text>)`). A heading carried inside each commit would put one per issue into that body.
- **Every line under the opener is indented.** No line of the block can then be read as a trailer, so the commit's final paragraph stays the single `Issue: #<n>` line each existing consumer parses.

---

## Resume and buildability from the trailer

One local query answers whether issue `<n>` is already integrated:

```bash
git log <milestone-branch> --grep='^Issue: #<n>$'
```

Non-empty output means that issue's commit is on the milestone branch. Empty means it is not.

**What it replaces.** The step-3 branch-state probe (`skills/solve-issue/SKILL.md (Branch-state probe)`) reads `gh pr list` and `git ls-remote`; nothing is pushed until milestone end, so both find nothing and every issue looks like a cold start on a resumed run. The trailer query reads the one artifact that exists locally, keeping resume state derived from git with no checkpoint file (`skills/solve-issue/SKILL.md (This derives resume-state entirely)`).

**What it re-grounds.** Buildability condition (a) (`skills/solve-milestone/SKILL.md (For each issue, determine whether)`) reads the milestone branch instead of `integrationBranch` (where nothing merges until milestone end): a dependency is satisfied when the query above finds its trailer. Conditions (b) (live blocker label) and (c) (`issueStates[n].blockers == false`) are untouched.

**Empty state.** A trailer the query does not find is the normal unmet-dependency state, not an error: condition (a) stays false for the issues that depend on `<n>` until the trailer appears, nothing is logged or surfaced, and a fresh run's first pass — no trailer for any issue — is an empty milestone branch read correctly.

---

## Milestone end: one push, one PR, one CI run

Runs once, after the loop finishes. Steps 6.1 to 6.5 (`skills/solve-milestone/changelog-authoring.md § 6.1 Idempotency check`) still author the CHANGELOG entry; this sequence **replaces steps 6.6 to 6.8** (`skills/solve-milestone/changelog-authoring.md § 6.6 Determine the branch name`), which cut `docs/changelog-<slug>` and open a second PR. Nothing has reached origin before this point, so this is the single place the milestone's work lands.

The skip-if-any-issue-parked guard (`skills/solve-milestone/SKILL.md (Guard — skip this step entirely if)`) is scoped to CHANGELOG **authoring**, so here it gates **step 1 alone**. Steps 2 to 6 run for whatever did merge.

1. **Commit the CHANGELOG onto the milestone branch.** Reuse step 6.7's commit message, versioned or version-free by mode (`skills/solve-milestone/changelog-authoring.md (git commit -m "docs: v<version> release notes")`). Step 6.1's idempotency read targets the **milestone branch** (`git show <milestone-branch>:CHANGELOG.md`), not `integrationBranch` (`skills/solve-milestone/changelog-authoring.md (read the working-tree copy after re-sync)`): the entry lands on the milestone branch, so a resumed run reading `integrationBranch` finds nothing and prepends a duplicate. Guard holds → skip this step; the PR then carries no CHANGELOG entry and everything below still runs.
2. **Push the milestone branch.** `git push -u origin milestone-<number>-<slug>`. The run's first and only push.
3. **Open one PR into `integrationBranch`.** Guard it for re-run safety exactly as step 6.7 does, checking `gh pr list --head "milestone-<number>-<slug>" --json number --jq '.[0].number // empty'` for an already-open PR before `gh pr create` and reusing the number it finds (`skills/solve-milestone/changelog-authoring.md § Check if a PR already exists for this branch (re-run safety)`). Base `<integrationBranch>`, never `protectedBranch`. Body:
   - The **wave-PR-body shape** (`skills/solve-milestone/integration-granularity.md (One wave PR)`): one line per issue on the branch, its evidence slot naming that issue's branch and the gates it passed during the fold.
   - A **Decision Log** and **exactly one** anchored `## Code Review` heading, each carrying one `### #<n>` sub-entry per issue: that issue's Decision Log lines and its `Code-Review:` block, lifted from its integration commit and de-indented back to column 0. The block's slots are defined in `## The integration commit` above; do not restate them here. Both sections are required by `.project/conventions.md#Commits & PRs`, and the `## Code Review` heading is checked at **both** `gh pr create` and `gh pr merge` (`hooks/hooks.json (Bash(gh pr merge *))` and its `gh pr create` sibling row directly above, `hooks/code-review-gate.sh (heading='## Code Review')`, `hooks/code-review-gate.sh (heading_match <text>)`).
   - The **milestone branch is the only source** for those sub-entries. A resumed run holding nothing in context rebuilds the whole section by reading each issue's commit with `git log <milestone-branch> --grep='^Issue: #<n>$'`. The `gh pr view` fallback issue and wave granularity rely on (`skills/solve-milestone/changelog-authoring.md (For each issue merged in this run)`) is unreachable here, because milestone granularity opens no per-issue PR; step 6.2's own summary lookup takes its documented issue-title fallback (`skills/solve-milestone/changelog-authoring.md (verify the PR number returned by the query)`) for that same reason.
4. **CI green, then merge, unless `### The visualHold gate` below holds the PR.** `gh pr merge --squash --delete-branch` (`.project/conventions.md#Commits & PRs`). A hold suppresses this step and step 5. Red CI takes the red-CI handler below instead of this step and step 5.
5. **Close every issue on the branch, one `gh issue close` call each.**

   ```bash
   for n in <each issue number>; do gh issue close "$n" --reason completed; done
   ```

   `Closes #n` fires only on a merge into the repository's **default** branch, and this PR targets `integrationBranch`, which typically is not it (`skills/solve-milestone/integration-granularity.md (Explicit issue close)`). The loop form is required: `gh issue close` accepts exactly one issue, and an unquoted `#` opens a shell comment. The list names **only** issues whose trailer is on the branch, never a parked one.
6. **Delete the local milestone branch and re-sync.** `git checkout <integrationBranch>`, `git fetch`, fast-forward, then `git branch -d milestone-<number>-<slug>`, exactly as step 6.8's cleanup does for its docs branch (`skills/solve-milestone/changelog-authoring.md (git branch -d docs/changelog-<slug>)`).

**Nothing merged.** Every issue parked or triage-blocked leaves the milestone branch with no commits over `integrationBranch`: no push, no PR, no close, no branch to delete. This is the all-UI-Wave precedent (`skills/solve-milestone/integration-granularity.md (All-UI wave)`).

### The visualHold gate

Step 4's precondition, green CI only, this granularity only (`docs/profile-schema.md (Should the single milestone PR wait)`). Under `"issue"` and `"wave"` the per-issue Layer-2 visual gate is the visual gate and this one is never reached; here that per-issue gate is bypassed whole (`skills/solve-issue/SKILL.md (Visual-review gate)`), so this is the milestone's one UI sign-off. First match wins:

| Condition | Step 4 |
|---|---|
| `visualHold: false` in the profile | **Merge.** The operator's one affirmative act disables the gate outright, so no diff is read. A non-boolean value is not `false`: it holds, with a logged note. |
| `uiSurfaceGlobs` absent | **Merge.** The repo declares no UI surface, so there is nothing to hold for, exactly as with the per-issue gate. |
| The milestone branch's diff against `integrationBranch` cannot be determined | **Hold.** Never merge on an unread diff: an unreviewed UI merge is a one-way door, while an over-strict hold costs one human action (`.project/design-philosophy.md#One-way doors`). |
| That diff touches a `uiSurfaceGlobs` path | **Hold.** Match `git diff --name-only <integrationBranch>...milestone-<number>-<slug>` against the globs, the same derivation the per-issue gate uses (`skills/solve-milestone/parallel-waves.md (independently from)`). |
| It touches none | **Merge.** |

**A hold takes `### Red CI on the milestone PR`'s shape below, with a green build and a different reason:** every step there applies unchanged, including the preserved local milestone branch and the step-2 re-entry whose step-3 guard reuses the open PR. What the 🔴 line says is the one difference: the build is green and the work is waiting on one human look, never a failure to fix.

### Red CI on the milestone PR

**Run-scoped, not issue-scoped.** Not a park (`skills/solve-issue/SKILL.md (PARK & continue)` is per-issue; the loop is already over) and not a systemic halt (`skills/solve-milestone/SKILL.md (conditions where no further issue can make progress)`): no single issue owns a failure N issues share. Take the CHANGELOG-PR-red shape (`skills/solve-milestone/changelog-authoring.md (CI red:)`), which labels the **PR** rather than parking anything.

- Apply `needs review` to the milestone PR: `gh pr edit <pr-number> --add-label "needs review"`.
- Emit one 🔴 line into the Template 3 final summary's `🔴 Your move:` section (`skills/solve-milestone/changelog-authoring.md § 6.9 Surface in the final summary "Your move" section`) naming **every issue on the branch**, not just the PR — a line naming only the PR leaves the human to reconstruct its contents from the diff.
- Preserve the local milestone branch. The remote PR is still open and needs it.
- Do **not** re-attempt the merge, and do **not** close any issue: the work is unmerged, so every issue on the branch stays open.

A later re-invocation over the preserved branch re-enters at step 2, and step 3's guard reuses the open PR instead of creating a second one.

---

## Creating the milestone branch: resume-safe pre-clean guard

Runs in Before-starting, after the clean-tree and current-`integrationBranch` precondition (`skills/solve-milestone/SKILL.md (Confirm the working tree is clean)`) and before Phase 0 triage (`skills/solve-milestone/SKILL.md § Phase 0 — Triage`). Adds no numbered step — step 5 stays the last Before-starting step (`skills/solve-milestone/SKILL.md (Resolve execution mode (the LAST Before-starting step).**)`) — and puts the branch in place before step 5's DB-hazard profile write and before either loop cuts from it (`skills/solve-milestone/parallel-waves.md (Create the worktree fleet)`). Step 4 leaves `HEAD` on `integrationBranch`, so clearing a leftover needs no branch switch.

**The discard-safe set is smaller than an issue branch's.** Until the milestone-end push, the milestone branch is the only copy of every folded issue, so a naive re-cut (`git branch -D`, then recreate) on a resumed run destroys work that exists nowhere else. The posture is `skills/solve-milestone/parallel-waves.md (Pre-clean guard)`'s preserve-don't-clobber: clear only a provably-safe leftover, attach to any leftover that carries work. Of the three discard-safe conditions listed for an issue branch (`skills/solve-milestone/contingencies.md (Leftover is provably safe to)`), **already pushed does not transfer**: a pushed-but-unmerged milestone branch can carry completed issues' commits absent from `integrationBranch`.

**Not the issue-branch guard.** `skills/solve-milestone/parallel-waves.md (Pre-clean guard)` guards a leftover per-issue branch `issue/<n>-<slug>` before each `git worktree add`; it still runs per issue branch under parallel mode. This one runs once per run over the single milestone branch.

**Probes, all read-only.** Existence: `git show-ref --verify --quiet refs/heads/milestone-<number>-<slug>` plus `git ls-remote --heads origin milestone-<number>-<slug>` (the local-and-remote pair `skills/solve-issue/SKILL.md (exists (local or remote) with commits)` already probes with). Commits ahead: `git rev-list --count <integrationBranch>..milestone-<number>-<slug>`, mirroring `skills/solve-milestone/contingencies.md (Leftover is provably safe to)`'s first sub-condition. Merged PR: `gh pr list --head "milestone-<number>-<slug>" --state merged --json number --jq '.[0].number // empty'`, the head-filtered form the milestone-end PR guard already uses (`## Milestone end` step 3), narrowed to merged.

Evaluate in order, first match wins:

1. **Cold: no branch locally and none on `origin`.** Cut it fresh from `integrationBranch` as `## Branch model` above specifies: `git checkout -b milestone-<number>-<slug> <integrationBranch>`. The normal first-pass state, not anything to report.
2. **Provably safe to discard: 0 commits ahead of `integrationBranch`, or a merged PR exists for the branch.** Clear it fully, `git branch -D milestone-<number>-<slug>`, then cut fresh exactly as leg 1 does. The 0-ahead case is a branch cut and then interrupted before any issue integrated; the merged case is a run interrupted between the milestone-end merge and step 6's local delete. Do **not** re-point the branch with `git reset --hard <integrationBranch>` instead: consumer destructive-command hooks routinely block that pattern (`## Folding an issue into the milestone branch` above).
3. **Carries work: commits ahead of `integrationBranch`, no merged PR.** **Attach, never `git branch -D`.** Local branch: `git checkout milestone-<number>-<slug>`. Remote-only: `git checkout --track origin/milestone-<number>-<slug>`, the tracking form `skills/solve-issue/SKILL.md (exists (local or remote) with commits)` uses for the same case. No `-b` on either, mirroring `skills/solve-milestone/contingencies.md (Leftover branch carries commits)`. Which issues on the branch are already integrated is **not** decided here: each `solve-issue` reads its own `Issue: #<n>` trailer through its own resume probe (`skills/solve-issue/SKILL.md (Branch-state probe)`).
4. **Ambiguous, or a probe failed.** An indeterminate `git rev-list` or `gh pr list` result, or a probe exiting non-zero (auth, network, a malformed ref): **default to preserve** — never `git branch -D` — and end the run with the systemic-halt shape (`skills/solve-milestone/SKILL.md (conditions where no further issue can make progress)`, its literal text at `skills/solve-milestone/SKILL.md (is the systemic-failure description)`), with no blocker label and no issue comment: this guard runs before Phase 0 triage, so no issue has been selected (`.project/design-philosophy.md#Error & failure philosophy`). An empty `gh pr list` result is not ambiguity — it is a determinate "no merged PR", and legs 2 and 3 decide on the ahead-count alone.
