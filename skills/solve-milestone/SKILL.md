---
name: solve-milestone
description: This skill should be used when the user invokes "/milestone-driver:solve-milestone <name>", or asks to "solve a milestone", "drive a milestone", or "work the milestone autonomously". Autonomously iterates every issue in a GitHub milestone in dependency order, running /milestone-driver:solve-issue on each and re-syncing the integration branch between issues. Runs unattended; parks blocked/gapped issues and continues with clean ones — never waits on a human; only a systemic failure ends the run early.
---

# solve-milestone — autonomous driver

Drive an entire GitHub milestone to completion by ordering its issues and running `/milestone-driver:solve-issue` on each, integrating to `integrationBranch` between issues. This skill owns **ordering, the loop, branch re-sync, parking, and the final summary**; the full per-issue pipeline — root-cause, implementer dispatch, gates, review, PR, auto-merge on green (non-UI) or visual-review hold (UI), close — is delegated to `/milestone-driver:solve-issue`.

**Bounded blast radius.** The loop merges only to `integrationBranch`, never to `protectedBranch`. Release (`integrationBranch` → `protectedBranch`) and deploy stay manual and human-only. That boundary is what makes unattended operation safe.

## Before starting

1. Read the profile at `milestone-driver.json` (repo root; see the plugin's `docs/profile-schema.md`). If the file is absent or any of `integrationBranch`, `protectedBranch`, or `sourceGlobs` is missing, invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. `implementerAgent` defaults to `milestone-driver:implementer` when omitted. The keys `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `domainSkills`, and `nonNegotiables` are optional; their steps are skipped cleanly when absent.
2. Confirm `gh auth status` is healthy and the named milestone exists.
3. Confirm the working tree is clean and the local `integrationBranch` is current (`git fetch`, fast-forward).

## The procedure

### 1. List the milestone's open issues
Run `gh issue list --milestone "<name>" --state open`.

### 2. Determine the order
The **milestone description is the ordering source of truth**. Read it (e.g. `gh api "repos/{owner}/{repo}/milestones" --jq '.[] | select(.title=="<name>") | .description'`) and follow the recorded Wave / dependency sequence. If the description records no explicit order, fall back to ascending issue number and **state that assumption explicitly** in the run output — do not silently pick an order.

### 3. Determine the target version

Read `versioning` from the profile. **Version-free mode** (`versioning: false`): skip this step entirely — no semver parse, **no prompt**, no target version (the milestone name need not be a version). Record "version-free run — no version determined or bumped" in the run output and proceed to Phase 0. **Versioned mode** (`versioning` `true` or absent): parse the milestone name and description for a semantically valid version (`x.y.z`). Derive the target version, **hold it in the orchestrator's context for the duration of the loop**, and record it in the run output. If no valid semver can be parsed, **prompt the user** before proceeding — do not guess.

> **Version source vs. version target.** In versioned mode the version **source** is the milestone (parsed here). The version **target** is `.claude-plugin/plugin.json`; the missing-`plugin.json` fail-safe for that target is applied downstream at `solve-issue` step 6.4 (the bump step), not here. Step 3 determines the source only; it adds no fail-safe branch of its own.
>
> **Precedence:** in versioned mode the milestone-derived target version is authoritative. The per-issue patch-default + confirm behavior in `solve-issue` does **not** fire inside a milestone run — the target version replaces it entirely.
>
> **Handoff:** in versioned mode the same main thread runs both `solve-milestone` and each `solve-issue` invocation, so the target version is available directly from the orchestrator's working context — it is **not** passed as a CLI argument to `solve-issue`.

### Phase 0 — Triage

Before the build loop begins, invoke the triage phase across the entire milestone:

```
/milestone-driver:triage <milestone-name>
```

1. **Present triage output.** Surface the all-clear or gap table in the run output so the operator can see what was found. The Wave-ordered dependency graph is included in triage's output regardless of whether there are gaps.

2. **Apply triage-recommended park labels.** Triage posts the `🔴 Triage` comment on each affected issue but does **not** apply labels — that is this skill's responsibility. For every issue where `issueStates[n].blockers == true`, apply its `issueStates[n].label` (`"needs design"` or `"needs decision"`) using the apply-time label helper from `skills/setup/SKILL.md` Phase 4:

   ```
   gh label create "<name>" --color <hex> --description "<desc>" --force
   gh issue edit <n> --add-label "<name>"
   ```

   Use the hex color and description from the taxonomy table in `skills/setup/SKILL.md` Phase 4.

3. **Seed the build queue.** Carry the full `dependencyGraph` and `issueStates` returned by triage into the loop below. The loop drives from the validated dependency graph — not the raw declared order — from this point forward.

### 4. Loop over issues in dependency-graph order

Create one TodoWrite item per issue. Drive the loop from the **validated dependency graph** produced by Phase 0. Process issues Wave by Wave; within a Wave, issues that are independent of each other may be treated as buildable in any order.

For each issue, determine whether it is **buildable this pass**. An issue is buildable iff ALL THREE conditions hold:

- **(a)** every issue in `dependencyGraph.edges["<n>"]` (the issues this issue directly DEPENDS_ON) is already merged to `integrationBranch`; **AND**
- **(b)** the issue currently carries **no blocker label** — check live: `gh issue view <n> --json labels --jq '[.labels[].name]'` and confirm none of `needs design`, `needs decision`, `blocked` is present. This live-label check is the **authoritative park-state**: it catches both triage parks labeled in Phase 0 AND prior-run build-time parks whose labels persist on the issue. A labeled issue must not be rebuilt until a human clears the label; **AND**
- **(c)** `issueStates[n].blockers == false` (this-run triage found no spec gap).

**If buildable:**

1. Ensure `integrationBranch` is current (`git fetch`, fast-forward) so dependent issues build on already-merged work.
2. Run `/milestone-driver:solve-issue <n>` (the target version from step 3 is already in the orchestrator's context and will be applied at the version-bump step).
3. **Park-and-continue on STOP/PAUSE:** if `/milestone-driver:solve-issue` returns a STOP or PAUSE (no root cause, new dependency, architecture conflict, scope overrun, ambiguity, unmet gate), **park the issue and continue** — do **not** halt the loop. Parking steps:
   a. Apply the appropriate label using the apply-time label helper (`needs decision` for a new dependency or architecture call; `needs design` for a design/spec gap; `blocked` for an unresolvable unmet gate).
   b. Apply `in progress` if a branch exists with commits.
   c. The STOP/PAUSE reason is already recorded on the issue (by `solve-issue` or the implementer). Confirm it is there; if not, post it via `gh issue comment <n>`.
   d. Leave the issue open; note it in the run output.
   e. Continue to the next issue in the dependency graph whose dependencies are merged.
4. **On success**, `/milestone-driver:solve-issue` has reached one of two terminal states: for a **non-UI issue** it has squash-merged to `integrationBranch` and closed the issue; for a **UI issue** held at the visual-review gate (`solve-issue` steps 7–9) it has left the PR **open** with the `needs review` label — not merged, issue not closed — for human visual sign-off (the final summary reports these open PRs). Re-sync the local `integrationBranch` (`git fetch`, fast-forward) before the next issue either way — for a UI issue nothing was merged, so the re-sync is a no-op.

**If not buildable (triage-parked, live-label park, or dependency not yet merged):**

- **Triage-parked or prior-run park** (`issueStates[n].blockers == true` OR live labels include a blocker label): in the common case the blocker label is already present (applied in Phase 0 or by a prior run); no build attempt. However, if Phase 0's label application was interrupted (e.g., a transient `gh` error), the label may be unexpectedly absent — check live: `gh issue view <n> --json labels --jq '[.labels[].name]'`. If none of `needs design`, `needs decision`, or `blocked` is present, apply `issueStates[n].label` now via the apply-time label helper (`gh label create … --force` + `gh issue edit <n> --add-label …`) before proceeding. This makes the branch idempotent and ensures the async handoff label is always on the issue. Apply `in progress` (via the apply-time helper) if a feature branch for this issue already exists with commits (check `git branch -a`). Note the issue in the run output (label + blocker reason) and continue.

  > **One blocker label per issue.** A parked issue carries exactly ONE blocker label. Do not apply `blocked` to an issue that already carries `needs design` or `needs decision` — the triage/design label is the root block and takes precedence; `blocked` would be redundant. (`in progress` is orthogonal and may still be applied.)

- **Dependency not yet merged** (condition (a) fails but conditions (b) and (c) pass — the issue is NOT itself triage- or live-label-parked): apply the `blocked` label (and `in progress` if a branch with commits exists) via the apply-time helper, and post a comment naming this issue's own unmerged upstream(s):
  `gh issue comment <n> --body "🔴 Blocked — held by unmerged upstream dependency: #<each unmerged issue in edges[\"<n>\"]>. This is a dependency-ordering hold (no design/decision work is needed for this issue itself). Once the upstream(s) are merged (and any upstream parks cleared), remove this \`blocked\` label and re-run solve-milestone to build this issue."`
  Then hold every transitive dependent (any issue whose `dependencyGraph.edges` include this issue or another held issue): for EACH such issue m, **before applying `blocked`**, check m's live labels (`gh issue view <m> --json labels --jq '[.labels[].name]'`). If m already carries `needs design`, `needs decision`, or `blocked`, do NOT add another blocker label — the existing label stands (one blocker label per issue). Otherwise apply `blocked` (+ `in progress` if it has a branch). In all cases post the same KIND of comment naming m's OWN unmerged upstream(s) from `edges["<m>"]` — not this issue's (same wording: dependency-ordering hold, clear `blocked` label and re-run). Note all held issues in the run output and continue with independent buildable issues.

The loop **never waits on a human**. It runs to completion — every issue is either done (merged), **held at the visual-review gate** (a UI issue with an open `needs review` PR awaiting human visual sign-off), or parked (labeled, branch open if applicable, comment posted). Comment provenance by park type: triage-parked issues carry the `🔴 Triage` comment posted by Phase 0; build-time STOP/PAUSE parks carry the reason confirmed or posted at the park step (step 3c above); dependency-held issues carry the `🔴 Blocked` comment posted in the dependency-not-yet-merged branch above. The run ends when no more buildable issues remain.

In **versioned mode** the **first issue's PR** sets `plugin.json` to the target version. Every subsequent issue's PR is **idempotent** — if `plugin.json` already carries the target version, the version bump step in `solve-issue` makes no change. In **version-free mode** (`versioning: false`) no PR carries a version change at all.

### 5. Finish
Continue until every issue is done (merged), held at the visual-review gate (a UI issue with an open `needs review` PR awaiting human visual sign-off), or parked. The run ends when no more buildable issues remain — not because it is waiting on a human.

## Autonomy

- **Unattended between systemic failures.** Within an explicit `/milestone-driver:solve-milestone` run, operate autonomously. A `solve-issue` STOP or PAUSE **parks** that issue (label + open branch + comment) and the loop continues — it does **not** halt the loop. Only a systemic failure ends the run early.
- **Systemic failures that halt the run** (examples): `gh auth` failure, a broken or inaccessible `integrationBranch`, missing required tooling (`gh`, `git`). These are conditions where no further issue can make progress. Surface the failure, leave the working tree clean and all in-flight issues parked, and stop.
- **Architecture is locked** per issue at its plan-approval time. The loop executes approved architecture; it does not pivot. A plan proven wrong is a park (STOP → park + continue), not a silent redesign. For the bounded definition of architecture vs implementation detail (the decision test), see the Autonomy model in `solve-issue`.
- **Never escalate scope to `protectedBranch`.** No PR, push, or merge targets `protectedBranch` (enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection).

## Final summary

On completion or systemic-failure halt, report:

- **Issues built and merged** to `integrationBranch` (with PR links).
- **Issues parked** — for each: the issue number and title, the park label applied, the blocker reason, and the open feature branch (if applicable). Report each parked issue's blocker reason from the run's tracked context — the loop recorded WHY each issue was parked as it happened (the triage gap, the STOP/PAUSE reason, or the unmerged upstream). If a reason is not in active context, read the issue's comments (`gh issue view <n> --json comments`) and use the park-reason comment posted during THIS run — the `🔴 Triage` comment (triage-park), the `🔴 Blocked` comment (dependency-hold), or the recorded STOP/PAUSE reason (build-park; note this may not carry a `🔴` prefix). Identify the park-reason comment by its content and recency-within-this-run; do **not** invent or hallucinate a reason, and do not mistake an external reply for the park reason.
- **Open UI PRs** awaiting human merge: PRs carrying the `needs review` label (UI issues per issue #18 that were built but left open for visual sign-off), listed with their PR links.
- **PRs carrying a `judgment call` label**, flagged for post-run review.
- **PRs missing a `## Code Review` section** in their body — flagged, like `judgment call` PRs, as requiring post-run human review before the `integrationBranch` → `protectedBranch` merge.
- **The run ended because** all issues are done (merged), held at the visual-review gate (open `needs review` PRs), or parked — not because it is waiting on a human.
- The next human step: review parked issues and the open `needs review` PRs; clear the park labels when the blockers are resolved and re-run to pick up the remaining work; when all work is merged, merge `integrationBranch` → `protectedBranch` and deploy manually.
