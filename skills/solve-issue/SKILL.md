---
name: solve-issue
description: This skill should be used when the user invokes "/milestone-driver:solve-issue <n>", or asks to "solve issue <n>", "fix issue <n>", or "drive issue <n>" through the milestone-driver gated procedure. Runs one GitHub issue end-to-end as an orchestrator — triage, root-cause-or-park, dispatch the implementer subagent (TDD, citations), unit + E2E gates, code review, PR to the integration branch, auto-merge on CI green for non-UI issues (UI issues are held open for human visual sign-off), then close — never authoring application or test code on the main thread.
---

# solve-issue — gated per-issue procedure

Run exactly one GitHub issue through a fixed, gated pipeline. The main thread acts only as an **orchestrator**: read, decide, dispatch, review, integrate. It **never authors application or test code itself** — the `force-subagent` hook enforces this mechanically, so honor it by design.

Orchestrate the `superpowers:*` skills for the inner loop rather than reimplementing their discipline.

## Before starting

1. Read the profile at `milestone-driver.json` (repo root; see the plugin's `docs/profile-schema.md`). If the file is absent or any of `integrationBranch`, `protectedBranch`, or `sourceGlobs` is missing, invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. `implementerAgent` defaults to `milestone-driver:implementer` when omitted. The keys `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `domainSkills`, and `nonNegotiables` are optional; their steps are skipped cleanly when absent.
2. **Confirm the working tree is clean** (cold-start precondition) **and the local `integrationBranch` is current** (`git fetch`, fast-forward). If the probe in step 3 detects an existing `issue/<n>-*` branch — whether the branch carries committed or uncommitted prior work — prior in-progress changes are expected and must **not** be stashed or discarded before the probe runs; skip the clean-tree enforcement and proceed to step 3 immediately.
3. **Branch-state probe (resume an interrupted run).** Run `git fetch` first, then determine prior progress from git + gh before cutting anything. Evaluate in this order:
   - **(a) A PR exists for `issue/<n>-*`** (client-side filter: `gh pr list --state all --limit 200 --json number,headRefName,state,url --jq '.[] | select(.headRefName | startswith("issue/<n>-"))'`):
     - **merged** → the work is already integrated; do **not** re-implement or open a new PR; **resume at step 9** (confirm the issue is closed / close it). A merged PR means the branch was deleted — this state is reached when a run is interrupted after the merge but before the issue is closed.
     - **open** → check out that branch; **resume at the visual-review gate / auto-merge (steps 7–8)** — do **not** re-implement and do **not** open a second PR. (The open PR is the authoritative "work is built and submitted" signal.)
   - **(b) No PR; branch `issue/<n>-*` exists (local or remote) with commits ahead of `integrationBranch`**: check both local and remote refs (`git branch -a --list "*issue/<n>-*"` or `git ls-remote --heads origin "issue/<n>-*"`); track the remote branch if no local branch exists (`git checkout --track origin/issue/<n>-<slug>`). Compute commits ahead against the remote-tracking ref if no local branch was present. Implementation is already present, so **skip re-implementation**. **Re-verify first** — if `unitTestCmd` is defined, run it and confirm green; if absent (no test layer), confirm the branch diff is non-empty and based on `integrationBranch` (`git diff <integrationBranch>...HEAD --stat`). Then **resume at step 6.1 (`/code-review`)** and follow step 6's normal flow from there (commit only if there are uncommitted changes, push, open PR) — review may not have run yet and is never skipped; if `/code-review` triggers a fix, the re-review and re-push cycle in step 6 applies normally. A red re-verify (or a diff that is empty / clearly on the wrong base) is not a special case: fall into the normal step-4 red-suite path (re-dispatch the implementer, existing "at most 2" cap; park if non-converging).
   - **(c) No PR; no commits ahead; but the issue branch `issue/<n>-*` is checked out with uncommitted changes** (the implementer left work uncommitted — the normal implementer contract): do **not** clobber; re-verify (same re-verify rule as (b)); **resume at step 6.1 (`/code-review`)** and follow step 6's normal flow. This is best-effort: it only recovers when the working tree is preserved in-place (in-place re-dispatch); a fresh clone with no preserved working tree has no uncommitted changes and falls to (d).
   - **(d) Otherwise (no branch, no PR, clean tree):** cut a fresh feature branch from `integrationBranch` (e.g. `issue/<n>-<slug>`) — cold start, dispatch the implementer (### 3. Dispatch the implementer).

   This derives resume-state entirely from git + gh; there is no checkpoint file to maintain, drift, or delete.
4. Create one TodoWrite item per numbered step below. Work them in order — do not skip or reorder.

### Resuming an interrupted run

| Detected state (from git + gh) | Resume at |
|---|---|
| Merged PR for `issue/<n>-*` | Step 9 (confirm/close the issue — work is already integrated) |
| Open PR for `issue/<n>-*` | Step 7 (visual-review gate) → step 8 (auto-merge for non-UI) |
| No PR; branch + commits ahead of `integrationBranch` (local or remote) | Step 6.1 (`/code-review`) after re-verify; follow step 6's normal flow: commit only if uncommitted, push, open PR |
| No PR; no commits ahead; issue branch checked out with uncommitted changes | Step 6.1 (`/code-review`) after re-verify; follow step 6's normal flow (best-effort: in-place re-dispatch only) |
| No branch, no PR, clean tree | Cold start: cut `issue/<n>-<slug>` from `integrationBranch`, dispatch implementer (### 3. Dispatch the implementer) |

On the "no PR, branch/uncommitted-changes" paths, commit **only if there are uncommitted changes**; if the work is already committed, skip straight to push + PR. Never skip `/code-review`; if `/code-review` triggers a fix, the re-review and push cycle in step 6 applies normally.

## The procedure

### 0. Triage
Invoke `milestone-driver:triage <n>` (single-issue mode). If triage returns a **Blocker** for this issue → **park**: triage has already posted the `🔴 Triage` comment on the issue; apply the recommended label from `issueStates["<n>"].label` — `needs design` for a design gap, `needs decision` for a non-design decision — via the apply-time helper (idempotent `gh label create --force` then `gh issue edit --add-label`); leave the issue open; do **not** proceed to step 1. Return to the caller — the milestone loop continues with independent, clean issues. All-clear or Advisory-only → proceed to step 1.

### 1. Read the issue
Run `gh issue view <n>` with comments. Restate the acceptance criteria plainly before continuing.

### 2. Evaluate the codebase for root cause
Invoke `superpowers:systematic-debugging`. Read the implicated code — the file(s) plus direct callers and callees.

**🔴 GATE — root cause:** If the root cause cannot be identified from the codebase, **park** the issue: post a comment describing the blocker (`gh issue comment <n>`), apply the `blocked` label (or `needs design` if the gap is a design gap), apply `in progress` if the branch has commits, leave the branch open with any work done, and return. The milestone loop continues. Do not proceed to implementation.

When found, write an **architecture-aware plan** with full awareness of the codebase and its conventions. This plan is the **locked** architecture for this issue.

**`design-cleared` means a decision was recorded**, not that it is correct or buildable. The orchestrator may still **park** a `design-cleared` issue with `needs design` if the recorded/locked design is internally contradictory or will produce a poor result.

### 3. Dispatch the implementer
Dispatch the profile's `implementerAgent` (default `milestone-driver:implementer`; a project-level override in the profile uses that agent's own name as-is) via the Agent tool, orchestrating `superpowers:subagent-driven-development` + `superpowers:test-driven-development`. Brief it like a colleague walking in cold: the issue, the approved plan, the profile, and the expected file scope. Note: extract/rename issues that touch a widely-shared symbol or component carry ~2–3× the call-site-migration surface of a typical feature issue, so they are more likely to consume both allowed re-dispatches before converging — the "at most 2" cap still applies, and an issue that cannot converge within it parks like any other (orchestrator judgment, not a profile key).

Verify the returned report honors the implementer contract: least-code / reuse-first, TDD red→green observed (or a `VERIFICATION (no test layer)` section when `unitTestCmd` is absent), verified citations where citable sources exist, a Decision Log, a `USER-FACING CHANGES` block (with `NEW_UI_ELEMENTS: yes|no`, `DESTRUCTIVE_OPS: yes|no`, and `POST_REVIEW_CHANGES: yes|no`), and **changes left uncommitted**.

After verifying the report, apply the following declaration gates:

- **`NEW_UI_ELEMENTS: yes`** and the issue's acceptance criteria are silent on the element's visual/UX detail → **park** with `needs design`: document the new elements and what direction is needed in a comment (`gh issue comment <n>`), preserve the branch, apply the label (+ `in progress` if the branch has commits), and return. The human supplies direction and re-runs; there is no mid-run interactive resume.
- **`DESTRUCTIVE_OPS: yes`** and the confirmation UX is unspecified → **park** with `needs decision` (a missing confirm flow usually means the plan is incomplete): document on the issue, preserve the branch, apply the label (+ `in progress` if the branch has commits), and return.

**🔴 GATE — new dependency:** If the implementer reports that the optimal solution requires a new library or toolkit, **park** with `needs decision`: post the library plus its license / OSS status on the issue (`gh issue comment <n>`), preserve the branch, apply the `needs decision` label (+ `in progress` if the branch has commits), and return. The milestone loop continues. Do not ask the operator interactively.

**🔴 GATE — implementer STOPPED:** If the implementer returns `STATUS: STOPPED` (architecture conflict, scope overrun, out-of-scope edit, or missing/ambiguous brief), **park** the issue: post a comment describing the conflict (`gh issue comment <n>`), apply the appropriate label (`needs design` for a design/spec conflict, `needs decision` for an architecture call, `blocked` for an otherwise-unresolvable gate) + `in progress` if the branch has commits, preserve the branch, and return. The milestone loop continues. (Architecture stays LOCKED — a plan proven wrong is a park, not a pivot.) `PAUSED-FOR-APPROVAL` from the implementer indicates a new-dependency case and routes to the new-dependency gate above.

### 4. Unit suite → green
If `unitTestCmd` is defined in the profile: run it and invoke `superpowers:verification-before-completion`. Report real output, never assertion.

If `unitTestCmd` is absent: skip this gate. The implementer is responsible for verifying behavior by the best available means and reporting it; the orchestrator accepts that report in lieu of a test run.

**🔴 GATE — tests (when `unitTestCmd` is defined):** A red suite blocks progress. Re-dispatch the implementer with the failure, or **park** if the failure reveals the plan is wrong (see Autonomy).

**Cap: at most 2 implementer re-dispatches on a red suite.** If the suite is still red after the 2nd re-dispatch, **park** the issue: comment on the issue describing the failure and what is needed, apply `blocked` (or `needs design` if the plan is wrong) (+ `in progress` if the branch has commits), preserve the branch, and return. The milestone loop continues. A suite that won't go green usually means the plan is wrong (see Autonomy).

**Cap: at most 2 implementer re-dispatches on a red suite.** If the suite is still red after the 2nd re-dispatch, **STOP and resurface** — do not loop. A suite that won't go green usually means the plan is wrong (see Autonomy).

### 5. E2E pre-merge gate
Apply only when the change touches a UI surface and the profile defines `e2eTestCmd`:
- **Bug:** run a targeted subset that proves the fix.
- **Feature:** have the implementer author new end-to-end (E2E) tests covering reasonable user stories, then run them.

Use the profile's `e2eEnv` configuration. Skip this step only when the issue touches no UI.

**Cap: at most 2 E2E fix attempts.** If the E2E suite still fails after the 2nd fix, apply the following escape policy:

- **Verified by other means** (a DB assertion + an attached screenshot confirming the feature works): **quarantine** the flaky test, proceed, and log the quarantine in the PR's Code Review section + apply a `judgment call` label. Stack-specific E2E environment fixes stay consumer-side per the profile / `e2eEnv` — the engine adds only this policy.
- **Not otherwise verified**: **park** with `blocked` — comment on the issue documenting the flake and what is unverified, preserve the branch, apply the label (+ `in progress` if the branch has commits), and return. The milestone loop continues.

A non-converging E2E gate usually means the plan is wrong (see Autonomy).

### 6. Review → integrate → close
1. **Review and resolve.** Run `/code-review` (`superpowers:requesting-code-review`) on the implementer's **uncommitted** changes, then resolve findings autonomously per the Autonomy model — do **not** pause to ask the operator about an in-scope finding:
   - **In-scope** (cosmetic, naming, style, local reversible refactor, missing/weak test): re-dispatch the implementer to fix it (the main thread cannot edit `sourceGlobs` — `force-subagent`); log it in the Decision Log.
   - **Park trigger** (architecture deviation; a shared contract/interface/schema change; a new dependency; edits outside the issue's file scope; an unmetable gate; material ambiguity): **park** the issue — comment the finding on the issue, apply the appropriate label (`needs design`, `needs decision`, or `blocked`) (+ `in progress` if the branch has commits), preserve the branch, and return. Do not commit.

   **Omitting `/code-review` is not permitted.** If skipped under any constraint (time, token budget, tool error, self-review substitution), treat the omission as a park trigger — comment the reason on the issue, preserve the branch, apply `blocked` (+ `in progress` if the branch has commits), and return.

   **Omitting `/code-review` is not permitted.** If skipped under any constraint (time, token budget, tool error, self-review substitution), treat the omission as a STOP trigger — halt, post the reason on the issue, and do not commit.

   **After a fix, before committing:**
   - **Code changed** (any `sourceGlobs` file): re-run `unitTestCmd` if defined (skip if absent), then re-run `/code-review` — the fresh review must be the **last action before commit**. The procedure does not loop past a second clean review. `POST_REVIEW_CHANGES: yes` is the implementer's machine-checkable signal that its edits were review-driven and the re-review is due; any `sourceGlobs` change independently triggers the re-review as a backstop, so a re-dispatch that changed source is always re-reviewed even if the field is `no`.
   - **Document-only** (`*.md`, READMEs, doc/comment text — nothing under `sourceGlobs`): commit directly; no re-run needed (`tests-green` no-ops on doc-only, and `/code-review` need not be re-run for a doc-only fix).
   - **No in-scope findings:** commit directly.

   **Cap: at most 2 review→fix cycles.** If `/code-review` still returns in-scope findings after the 2nd fix, **park** the issue: comment the current diff state on the issue, apply `needs design` or `blocked` as appropriate (+ `in progress` if the branch has commits), preserve the branch, and return. The milestone loop continues. A review that won't converge usually means the plan is wrong.
2. Assemble the **Decision Log** from the implementer's report (each choice → rationale → citation → alternatives rejected) for the PR body, and post the citations on the issue for review (`gh issue comment <n>`).
3. **Assemble the Code Review section** for the PR body — the evidence half of the audit trail (the Decision Log records *why* a choice was made; the Code Review section records *what review found* and how it was cleared). Record: whether `/code-review` ran, the finding count and severity per run (the 1st, and the 2nd if a re-review occurred), and each finding's resolution (re-dispatched and resolved / accepted with rationale / triggered park). If a run returned zero findings, state that with the run's effort level. **Absence of this section on a PR is a visible defect on PR review.** Use this template in the PR body:

   ```text
   ## Code Review

   - /code-review run: yes (omission is a park trigger — a submitted PR always carries a real review; a parked run opens no PR)
   - Findings: <count> in-scope finding(s) at <effort> effort
     - <finding> → re-dispatched and resolved | accepted (rationale: <…>) | triggered park
     - … (one line per finding, or "none" when count is 0)
   - No park-triggering findings. | Park-triggering findings: <list>
   ```

   The version-bump annotation this section carries depends on the mode resolved in step 6.4: "version-bump only — no logic change" in versioned mode; "version-free — no version bump" for a deliberately version-free repo (`versioning: false`); and "version-free — no version bump (plugin.json absent)" for the fail-safe (degraded) path. The parenthetical distinguishes a deliberately version-free repo from a misconfigured-versioned repo that degraded.

4. **Version bump.** Read `versioning` from the profile first.
   - **Version-free mode** (`versioning: false`): **skip the bump entirely** — make no edit to `.claude-plugin/plugin.json`. Annotate the **Code Review** section "version-free — no version bump" and proceed to commit. (Steps below do not apply.)
   - **Fail-safe degradation** (versioned mode — `versioning` `true` or absent — but `.claude-plugin/plugin.json` does **not** exist): do **not** fail. Degrade to version-free: skip the bump, log a one-line note (e.g. "versioned mode but no `.claude-plugin/plugin.json` — degraded to version-free, no bump"), annotate the **Code Review** section "version-free — no version bump (plugin.json absent)", and proceed to commit.
   - **Versioned mode** (`versioning` `true` or absent, and `.claude-plugin/plugin.json` exists): edit `.claude-plugin/plugin.json` `version` directly (it is config, not under `sourceGlobs`; the orchestrator edits it on the main thread — if a consumer's `sourceGlobs` covers `.claude-plugin/`, dispatch the implementer to apply the bump instead). This is a config edit, not a source change: **no `/code-review` re-run and no test re-run are needed; proceed directly to commit.** The carve-out covers only the `/code-review` run — the PR still requires its **Code Review** section, annotated "version-bump only — no logic change."
     - **Milestone run** (a target version was determined by `solve-milestone` and is held in the orchestrator's context — it is not a CLI argument): set `plugin.json` `version` to that target. **Idempotent** — if already equal, no change; move on.
     - **Standalone run** (no milestone target in the orchestrator's context): apply a **patch** bump (`x.y.Z` → `x.y.(Z+1)`), state the new version to the user, and **ask whether it should be minor or major instead** — adjust before opening the PR.
     - `plugin.json` is the **single source of truth** for the plugin version. `marketplace.json` carries no `version` field (Claude Code resolves `plugin.json` first; setting both is a documented footgun that silently masks the marketplace value). The bump rides in this PR — no separate chore PR.
5. Commit on the feature branch — the `tests-green` hook (`PreToolUse` on `git commit`) re-checks the suite. Review-before-commit is enforced by audit trail (the mandatory **Code Review** section), not by a shipped hook — the plugin ships no code-review hook.
6. Push the feature branch and open a PR with `--base <integrationBranch>` (never `protectedBranch` — enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection). Put the Decision Log and the **Code Review** section in the PR body. Add a `judgment call` label if any borderline autonomous call was made.
7. **Visual-review gate (UI issues — Layer 2).** Determine whether this issue touches a UI surface: `uiSurfaceGlobs` is configured in the profile **and** the PR's changed files match one of those globs (an implementer `NEW_UI_ELEMENTS: yes` declaration reinforces this signal).
   - **Not a UI issue** (`uiSurfaceGlobs` absent, or the diff matches no `uiSurfaceGlobs` path): no visual gate — proceed to auto-merge (step 8).
   - **UI issue:** do **not** auto-merge. The terminal state for this issue is *PR open, awaiting human visual sign-off* — apply the `needs review` label **to the PR** via the apply-time helper (idempotent `gh label create --force` then `gh pr edit <pr> --add-label "needs review"`) and leave the PR open for a human to test-render and merge. `solve-milestone`'s final summary lists all open `needs review` PRs.
     - **Render capability configured** (`e2eEnv`, or a `screenshotCmd` if the consumer supplies one): capture screenshots of the new surface in **both light and dark** appearance and attach them to the PR (`gh pr comment <pr>` with the images, or embed in the PR body) as convenience evidence for the reviewer.
     - **No render capability:** do **not** fail and do **not** auto-merge — post a note on the PR (`gh pr comment <pr>`) that visual evidence is unavailable and a **human visual test is required before the merge to `integrationBranch`**. The screenshot is convenience evidence only; the human-before-merge checkpoint holds either way.
   - This makes auto-merge opt-in per issue class: logic-only / non-UI issues auto-merge on green (step 8); UI issues await human merge regardless of render capability.
8. **Auto-merge on green (non-UI issues only):** once CI is green, run `gh pr merge --squash --delete-branch`. This replaces the human-choice step of `superpowers:finishing-a-development-branch`. **UI issues are skipped here** — they remain open per the visual-review gate (step 7) until a human merges.
9. Confirm the issue is closed (a linked PR auto-closes it; otherwise `gh issue close <n>`). **For a UI issue held at the visual-review gate, the issue stays open** with its PR awaiting human visual sign-off — it closes when the human merges the PR.

## Autonomy model (Balanced)

**Proceed autonomously (log on the PR):** implementation choices within the approved architecture; reuse of existing helpers, styles, and conventions; test design; local reversible refactors; resolving in-scope `/code-review` findings (step 6.1).

**PARK & continue (the autonomous runtime parks; it does not interactively wait):** deviation from the approved architecture; any change to a shared contract, interface, base class, or DB schema used beyond this issue; a new dependency; edits outside the issue's expected file scope; a gate that cannot be met without a design change; material ambiguity in the issue's intent; `/code-review` omission or substitution — skipping `/code-review` for any reason (time, token budget, tool error, self-review substitution) is **not** an in-scope autonomous decision; budget pressure is not a permitted exception.

In the autonomous runtime, a park means: post a comment on the issue documenting what was hit and what is needed to clear it; apply the appropriate label (`needs design`, `needs decision`, or `blocked`); also apply the `in progress` label (via the apply-time helper) when the feature branch has commits — `in progress` is the open-WIP signal the milestone loop and post-run review rely on; leave the issue open; leave the branch open with any work preserved; and return — the milestone loop continues with independent, clean issues. **Only a systemic failure** (auth/`gh` failure, broken `integrationBranch`, missing tooling) halts the whole run. A standalone interactive `solve-issue` still parks durably (comment + label + open branch); it may additionally narrate to the watching operator.

**Additional park triggers:**
- The recorded/locked design is internally contradictory → park with `needs design`.
- The orchestrator (or triage) judges the approved design will produce a poor result → park with `needs design`.
- A self-noted risk about the **approved** design (e.g. "this list could get long at realistic data volumes") → park with `needs design`. Each of these is a park (comment + label + open branch), **not** silent resolution and **not** an interactive prompt.
- An implementer-declared `NEW_UI_ELEMENTS: yes` with the acceptance criteria silent on the element's visual/UX detail → park with `needs design`.
- An implementer-declared `DESTRUCTIVE_OPS: yes` with the confirmation UX unspecified → park with `needs decision`.

**Within an explicit run, an in-scope `/code-review` finding is a *proceed-autonomously* event, not a clarifying-question moment** — fix it and log it. The operator pause is reserved for park triggers; the unattended contract overrides any general inclination to ask.

**Architecture is locked** at plan-approval time (step 2). The procedure executes approved architecture; it does not pivot. If implementation proves the plan wrong → park, not pivot.

A change is **architecture** (→ park) if it touches any of: a component or data structure named in the approved plan; a shared contract, interface, base class, DB schema, or public API used by code outside this issue; data ownership or a cross-component boundary; a new external dependency; or any file outside this issue's stated scope. A change is an **implementation detail** (→ proceed, log) if it is local to this issue's own files, changes no shared contract, and is reversible — a binding style, a private helper, a local refactor, or test design. When the distinction is genuinely ambiguous, treat it as architecture and park.

| Scenario | Classification | Action |
|---|---|---|
| Computed get-only binding → backed `SetProperty` (same property name, same consumer contract) | Implementation detail | Proceed, log in PR Decision Log |
| Extracting an existing method into a private helper in the same file | Implementation detail | Proceed, log if non-trivial |
| Adding a parameter to a shared interface used by other issues/components | Architecture | Park |
| Moving data ownership from ViewModel A to Service B | Architecture | Park |

**Audit trail (always):** a Decision Log on every PR, a **Code Review** section recording every `/code-review` run and its findings/resolutions, and a `judgment call` label on borderline calls, so post-run PR review surfaces every judgment.

## Non-negotiables
- Gitflow. PRs target `integrationBranch` only — never `protectedBranch`.
- Honor the profile's `nonNegotiables` (framework versions, platform targets).
- The main thread never authors application or test code — always dispatch the implementer.
