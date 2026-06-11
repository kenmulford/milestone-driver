---
name: solve-issue
description: This skill should be used when the user invokes "/milestone-driver:solve-issue <n>", or asks to "solve issue <n>", "fix issue <n>", or "drive issue <n>" through the milestone-driver gated procedure. Runs one GitHub issue end-to-end as an orchestrator — triage, root-cause-or-park, dispatch the implementer subagent (TDD, citations), unit + E2E gates, code review, PR to the integration branch, auto-merge on CI green for non-UI issues (UI issues are held open for human visual sign-off), then close — never authoring application or test code on the main thread.
---

# solve-issue — gated per-issue procedure

Run exactly one GitHub issue through a fixed, gated pipeline. The main thread acts only as an **orchestrator**: read, decide, dispatch, review, integrate. It **never authors application or test code itself** — the `force-subagent` hook enforces this mechanically, so honor it by design.

Orchestrate the `superpowers:*` skills for the inner loop rather than reimplementing their discipline.

## Before starting

1. Read the profile at `milestone-driver.json` (repo root; see the plugin's `docs/profile-schema.md`). If the file is absent or any of `integrationBranch`, `protectedBranch`, or `sourceGlobs` is missing, invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. `implementerAgent` defaults to `milestone-driver:implementer` when omitted. The keys `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `preflightCmd`, `domainSkills`, and `nonNegotiables` are optional; their steps are skipped cleanly when absent.
   1.1. **First-run preflight notice (one-time).** Immediately after reading the profile: if `preflightCmd` is **absent** from the profile **and** the marker file `.milestone-driver-preflight-notice` does **not** exist at the repo root, print the notice below verbatim, then create the marker (`touch .milestone-driver-preflight-notice`). Stay **silent** if `preflightCmd` is set **or** the marker already exists. The marker is per-clone and gitignored, so the notice shows at most once per clone (same pattern as `.milestone-driver-tests-stamp`).

      <!-- KEEP THIS NOTICE BLOCK BYTE-IDENTICAL across solve-issue and solve-milestone (see plan 2026-06-04 verification model). -->
      ```text
      ▶ New in 1.4.0 — optional preflight check (one-time notice)

      | What | Tell milestone-driver the command your CI uses for FAST checks
      |      | (lint, format, static analysis, security scan).
      | Why  | It runs that locally before opening the PR, so those checks are
      |      | caught and fixed up front instead of turning your PR red later.
      | How  | Add "preflightCmd" to milestone-driver.json. Optional — skip it
      |      | and nothing changes.

      Examples:
      | Stack        | preflightCmd                                   |
      | Ruby/Rails   | bundle exec standardrb && bundle exec brakeman -q |
      | Node/TS      | npm run lint                                    |
      | Any w/ pre-commit | pre-commit run --all-files                 |
      | Makefile     | make lint                                       |
      ```
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

**Two branches — always run one:**

**Branch A — Explicit-supply path (reuse).** Fires **iff the caller explicitly supplied this issue's triage result at invocation time** — in worker mode, as named-value fields embedded in the dispatch brief with actual values (e.g. `issueStates["<n>"] = { blockers: false, label: null, advisories: [...], risk: "light" }` and `edges["<n>"] = [...]`); in sequential mode, as an inline restatement by the orchestrator when invoking step 0 (e.g. "step-0 result for #N: { blockers: false, label: null, advisories: [...], risk: light }, edges: [...]"). When the result is explicitly supplied this way, use it directly — do **NOT** re-invoke `milestone-driver:triage <n>`. Proceed to the **Blocker check** below using the supplied result. This is not a skip: the explicitly supplied result IS the verified Phase 0 triage result for this run; the reuse branch consumes it rather than recomputing it.

**Branch B — Standalone / fallback path.** When no triage result was explicitly supplied at invocation time — anything absent, partial, or merely recalled from earlier context — invoke `milestone-driver:triage <n>` (single-issue mode) and use the returned result for the **Blocker check** below. Branch B is the safe default, never an error.

**Blocker check (both branches).** If the result indicates a Blocker for this issue → **park**: triage has already posted the `🔴 Triage` comment on the issue; VERIFY the comment exists (`gh issue view <n> --comments`) and post it if missing (idempotent); apply the recommended label from `issueStates["<n>"].label` — `needs design` for a design gap, `needs decision` for a non-design decision — via the apply-time helper (idempotent `gh label create --force` then `gh issue edit --add-label`); leave the issue open; do **not** proceed to step 1. Return to the caller — the milestone loop continues with independent, clean issues. All-clear or Advisory-only → proceed to step 1.

The safety floor is unconditional: triage step 0 always runs (via Branch A explicit-supply or Branch B fresh invocation) regardless of build profile. Light profile relaxes ceremony only — it never skips triage.

### 1. Read the issue
Run `gh issue view <n>` with comments. Restate the acceptance criteria plainly before continuing.

### 2. Evaluate the codebase for root cause
Invoke `superpowers:systematic-debugging`. Read the implicated code — the file(s) plus direct callers and callees.

**🔴 GATE — root cause:** If the root cause cannot be identified from the codebase, **park** the issue: post a comment opening with `🔴 Parked — ` and describing the blocker (`gh issue comment <n>`), apply the `blocked` label (or `needs design` if the gap is a design gap), apply `in progress` if the branch has commits, leave the branch open with any work done, and return. The milestone loop continues. Do not proceed to implementation.

When found, write an **architecture-aware plan** with full awareness of the codebase and its conventions. This plan is the **locked** architecture for this issue.

**`design-cleared` means a decision was recorded**, not that it is correct or buildable. The orchestrator may still **park** a `design-cleared` issue with `needs design` if the recorded/locked design is internally contradictory or will produce a poor result.

### Build profile resolution (resolved after step 0, governs steps 3–6)

Read `issueStates["<n>"].risk` from the step-0 triage result (held Phase 0 result in a milestone run, or fresh single-issue return in a standalone run). That value is either `"light"` or `"heavy"` (default `"heavy"` when absent or inconclusive). This single read governs the entire build profile for this issue:

| Profile | Implementer brief | E2E gate (step 5) | `/code-review` effort (step 6.1) |
|---|---|---|---|
| **Light** | Include a `risk:light` token in the brief | Skip when the issue touches no UI surface | `low` or `medium` |
| **Heavy** (default) | Standard TDD brief (no `risk:light`) | Per step 5 (UI surface + e2eTestCmd) | `high` or `xhigh` |

The safety floor is **unconditional for both profiles**: triage (step 0), the `tests-green` hook, and `force-subagent` always run regardless of profile. Light relaxes ceremony only — it never skips verification.

### 3. Dispatch the implementer
Dispatch the profile's `implementerAgent` (default `milestone-driver:implementer`; a project-level override in the profile uses that agent's own name as-is) via the Agent tool, orchestrating `superpowers:subagent-driven-development` + `superpowers:test-driven-development`. Brief it like a colleague walking in cold: the issue, the approved plan, the profile, and the expected file scope; when the build profile resolved above is `light`, the brief MUST include a `risk:light` token so the implementer applies the right verification mode. Note: extract/rename issues that touch a widely-shared symbol or component carry ~2–3× the call-site-migration surface of a typical feature issue, so they are more likely to consume both allowed re-dispatches before converging — the "at most 2" cap still applies, and an issue that cannot converge within it parks like any other (orchestrator judgment, not a profile key).

Verify the returned report honors the implementer contract: least-code / reuse-first, TDD red→green observed (or a `VERIFICATION (no test layer)` section when `unitTestCmd` is absent), verified citations where citable sources exist, a Decision Log, a `USER-FACING CHANGES` block (with `NEW_UI_ELEMENTS: yes|no`, `DESTRUCTIVE_OPS: yes|no`, and `POST_REVIEW_CHANGES: yes|no`), and **changes left uncommitted**.

After verifying the report, apply the following declaration gates:

- **`NEW_UI_ELEMENTS: yes`** and the issue's acceptance criteria are silent on the element's visual/UX detail → **park** with `needs design`: post a comment opening with `🔴 Parked — ` documenting the new elements and what direction is needed (`gh issue comment <n>`), preserve the branch, apply the label (+ `in progress` if the branch has commits), and return. The human supplies direction and re-runs; there is no mid-run interactive resume.
- **`DESTRUCTIVE_OPS: yes`** and the confirmation UX is unspecified → **park** with `needs decision` (a missing confirm flow usually means the plan is incomplete): post a comment opening with `🔴 Parked — ` documenting the missing confirm flow on the issue (`gh issue comment <n>`), preserve the branch, apply the label (+ `in progress` if the branch has commits), and return.

**🔴 GATE — new dependency:** If the implementer reports that the optimal solution requires a new library or toolkit, **park** with `needs decision`: post a comment opening with `🔴 Parked — ` followed by the library name and its license / OSS status on the issue (`gh issue comment <n>`), preserve the branch, apply the `needs decision` label (+ `in progress` if the branch has commits), and return. The milestone loop continues. Do not ask the operator interactively.

**🔴 GATE — implementer STOPPED:** If the implementer returns `STATUS: STOPPED` (architecture conflict, scope overrun, out-of-scope edit, or missing/ambiguous brief), **park** the issue: post a comment opening with `🔴 Parked — ` and describing the conflict (`gh issue comment <n>`), apply the appropriate label (`needs design` for a design/spec conflict, `needs decision` for an architecture call, `blocked` for an otherwise-unresolvable gate) + `in progress` if the branch has commits, preserve the branch, and return. The milestone loop continues. (Architecture stays LOCKED — a plan proven wrong is a park, not a pivot.) `PAUSED-FOR-APPROVAL` from the implementer indicates a new-dependency case and routes to the new-dependency gate above.

### 4. Unit suite → green
If `unitTestCmd` is defined in the profile: run it and invoke `superpowers:verification-before-completion`. Report real output, never assertion.

If `unitTestCmd` is absent: skip this gate. The implementer is responsible for verifying behavior by the best available means and reporting it; the orchestrator accepts that report in lieu of a test run.

**🔴 GATE — tests (when `unitTestCmd` is defined):** A red suite blocks progress. Re-dispatch the implementer with the failure, or **park** if the failure reveals the plan is wrong (see Autonomy).

**Cap: at most 2 implementer re-dispatches on a red suite.** If the suite is still red after the 2nd re-dispatch, **park** the issue: comment on the issue opening with `🔴 Parked — ` and describing the failure and what is needed, apply `blocked` (or `needs design` if the plan is wrong) (+ `in progress` if the branch has commits), preserve the branch, and return. The milestone loop continues. A suite that won't go green usually means the plan is wrong (see Autonomy).

### 5. E2E pre-merge gate
Apply only when the change touches a UI surface and the profile defines `e2eTestCmd`:
- **Bug:** run a targeted subset that proves the fix.
- **Feature:** have the implementer author new end-to-end (E2E) tests covering reasonable user stories, then run them.

Use the profile's `e2eEnv` configuration. Skip this step only when the issue touches no UI.

**Cap: at most 2 E2E fix attempts.** If the E2E suite still fails after the 2nd fix, apply the following escape policy:

- **Verified by other means** (a DB assertion + an attached screenshot confirming the feature works): **quarantine** the flaky test, proceed, and log the quarantine in the PR's Code Review section + apply a `judgment call` label. Stack-specific E2E environment fixes stay consumer-side per the profile / `e2eEnv` — the engine adds only this policy.
- **Not otherwise verified**: **park** with `blocked` — comment on the issue opening with `🔴 Parked — ` and documenting the flake and what is unverified, preserve the branch, apply the label (+ `in progress` if the branch has commits), and return. The milestone loop continues.

A non-converging E2E gate usually means the plan is wrong (see Autonomy).

### 6. Review → integrate → close
1. **Review and resolve.** Run `/code-review` (`superpowers:requesting-code-review`) on the implementer's **uncommitted** changes, then resolve findings autonomously per the Autonomy model — do **not** pause to ask the operator about an in-scope finding:
   - **In-scope** (cosmetic, naming, style, local reversible refactor, missing/weak test): re-dispatch the implementer to fix it (the main thread cannot edit `sourceGlobs` — `force-subagent`); log it in the Decision Log.
   - **Park trigger** (architecture deviation; a shared contract/interface/schema change; a new dependency; edits outside the issue's file scope; an unmetable gate; material ambiguity): **park** the issue — comment opening with `🔴 Parked — ` on the issue, apply the appropriate label (`needs design`, `needs decision`, or `blocked`) (+ `in progress` if the branch has commits), preserve the branch, and return. Do not commit.

   **Omitting `/code-review` is not permitted.** If skipped under any constraint (time, token budget, tool error, self-review substitution), treat the omission as a park trigger — comment the reason on the issue, preserve the branch, apply `blocked` (+ `in progress` if the branch has commits), and return.

   **After a fix, before committing:**
   - **Code changed** (any `sourceGlobs` file): re-run `unitTestCmd` if defined (skip if absent), then re-run `/code-review` — the fresh review must be the **last action before commit**. The procedure does not loop past a second clean review. `POST_REVIEW_CHANGES: yes` is the implementer's machine-checkable signal that its edits were review-driven and the re-review is due; any `sourceGlobs` change independently triggers the re-review as a backstop, so a re-dispatch that changed source is always re-reviewed even if the field is `no`.
   - **Document-only** (`*.md`, READMEs, doc/comment text — nothing under `sourceGlobs`): commit directly; no re-run needed (`tests-green` no-ops on doc-only, and `/code-review` need not be re-run for a doc-only fix).
   - **No in-scope findings:** commit directly.

   **Cap: at most 2 review→fix cycles.** If `/code-review` still returns in-scope findings after the 2nd fix, **park** the issue: comment opening with `🔴 Parked — ` and the current diff state on the issue, apply `needs design` or `blocked` as appropriate (+ `in progress` if the branch has commits), preserve the branch, and return. The milestone loop continues. A review that won't converge usually means the plan is wrong.

   **Preflight gate (after the `/code-review` resolve loop converges, before version bump/commit).** Once the `/code-review` loop above has converged, run the profile's `preflightCmd` in the repo root — the consumer-named fast pre-PR checks (lint / format / static analysis / security scan). Skip cleanly if `preflightCmd` is absent (exactly like `unitTestCmd`/`e2eTestCmd` absent). Capture real output, never assert. This mirrors the unit gate (step 4); it is positioned here as the concluding action of 6.1 rather than as a numbered sibling step so the `6.1 … 6.9` ordinals (and their internal + external cross-references) stay fixed.
   - **Non-zero exit → gate failure → re-dispatch the implementer** with the failing command + its captured output. A source-changing fix re-runs `unitTestCmd` if defined (skip if absent), re-runs `/code-review` (honoring the "fresh review is the last action before commit" rule above), and re-runs `preflightCmd`.
   - **Cap: at most 2 implementer re-dispatches** on a failing preflight gate. If `preflightCmd` is still non-zero after the 2nd re-dispatch, **park `blocked`**: comment on the issue opening with `🔴 Parked — ` and describing what failed and what is needed, apply `blocked` (or `needs design` if the plan is wrong) (+ `in progress` if the branch has commits), preserve the branch, and return. The milestone loop continues. Park-don't-prompt, consistent with every other gate.
   - A non-converging preflight gate usually means the plan is wrong (see Autonomy).
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

In the autonomous runtime, a park means: post a comment on the issue that **opens with `🔴 Parked — ` followed by the reason** (e.g. `🔴 Parked — architecture conflict: shared interface change required`); apply the appropriate label (`needs design`, `needs decision`, or `blocked`); also apply the `in progress` label (via the apply-time helper) when the feature branch has commits — `in progress` is the open-WIP signal the milestone loop and post-run review rely on; leave the issue open; leave the branch open with any work preserved; and return — the milestone loop continues with independent, clean issues. **Only a systemic failure** (auth/`gh` failure, broken `integrationBranch`, missing tooling) halts the whole run. A standalone interactive `solve-issue` still parks durably (comment + label + open branch); it may additionally narrate to the watching operator.

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

## Permission pre-flight gate

**Runs once per run, before the first background dispatch. Zero cost on synchronous paths.**

**Scope: this gate applies only when background dispatch is about to be used (the async dispatch points introduced in #89). Sequential/synchronous runs SKIP it entirely — skipped, not merely cheap; the gate is not executed at all on a sequential run.**

> **Sequential / synchronous runs SKIP this gate entirely** — it is not merely cheap, it is not executed at all. The gate applies only when background dispatch is about to be used (the async dispatch points introduced in #89). On a sequential run, proceed directly to the first background-dispatch step without any gate evaluation.

Background subagents auto-deny any tool call that would otherwise prompt (documented Claude Code behavior). A background chunk hitting an un-allowlisted tool fails outright with no interactive recovery — park-don't-prompt becomes physically enforced. Before activating any background dispatch (the async dispatch points, #89), run this gate to verify the session's permission allowlist is complete.

**Allowlist source — merged settings read.** Read `permissions.allow` from all three Claude Code settings layers and union them:

| Priority | File |
|---|---|
| 1 | `~/.claude/settings.json` (user global) |
| 2 | `.claude/settings.json` (project) |
| 3 | `.claude/settings.local.json` (project local) |

Absent or unreadable layers are skipped in the union (not treated as gaps). The union covers all readable layers. Synchronous fallback fires only when (1) the union fails to cover the required tool surface, or (2) no layer is readable.

**Pipeline tool surface.** The allowlist must cover, at minimum:

| Tool category | Required grants |
|---|---|
| Read-only gh ops | `gh pr list`, `gh issue view`, `gh issue list` |
| Git | `git commit`, `git push` |
| PR / issue writes | `gh pr create`, `gh pr merge`, `gh pr edit`, `gh pr comment` |
| Issue management | `gh issue edit`, `gh issue comment`, `gh issue close` |
| Label management | `gh label create` |
| Profile-defined commands | Each command in `unitTestCmd`, `preflightCmd`, `e2eTestCmd` (skip if absent) |

**Gap detection and response.**

- **No gaps:** proceed with background dispatch as planned.
- **Gap detected (union does not cover the required surface, or no layer is readable):** do **not** fire the background chunk. Instead:
  1. Surface a 🔴 gap table listing each missing grant and which settings layer(s) could supply it.
  2. **Fall back to synchronous dispatch for this run** — today's sequential behavior, unchanged. The run completes; it just does not use background concurrency.
  3. Recommend the consumer run `/fewer-permission-prompts` to establish a stable allowlist (see `docs/consumer-setup.md`).

The gate fires **once per run**, not once per issue. After the first background-dispatch decision point, the result (proceed / fallback) is held for the rest of the run — do not re-read settings on every issue.

**Worker auto-deny handling.** If a background worker chunk receives an auto-deny on a tool call mid-execution, treat it as a **park** — post a comment opening with `🔴 Parked — auto-deny on <tool>` on the issue, apply the `blocked` label (+ `in progress` if the branch has commits), preserve the branch, and return the structured handback with `status: parked`, `parkLabel: "blocked"`, and `parkReason: "auto-deny on <tool>"` (see Worker mode Delta 3 for the full handback schema — `parkLabel`, `parkReason`, and the handback structure are defined there). This is the same park-don't-prompt contract all other gates use — an auto-deny is not a silent failure. On a sequential (non-worker) run, no structured handback exists — park via the normal park steps (comment, label, preserve branch, return); there is no `parkLabel`/`parkReason` handback because there is no orchestrator to receive one.

## Worker mode (`--worker`)

Worker mode is the per-issue half of `solve-milestone`'s opt-in `--parallel` flow (milestone 1.5.0): the orchestrator builds mutually-independent issues within a dependency Wave concurrently — each in its own git worktree — then integrates them through an orchestrator-owned **serial verified merge tail**. This section defines the contract the parallel orchestration (#72), the merge tail (#73), and branch-per-Wave granularity (#75) consume; those skills do not exist yet, so the terms used here (`--worker`, "worker mode", "merge tail", "handback", "wave branch", "parallel-safe gates", "deferred gates") are the authoritative source.

**`--worker` is an interpreted token, not a parsed CLI flag.** Claude Code does no argument parsing — `$ARGUMENTS` is string-substituted — so worker mode is **recognized** when the dispatch text contains a `--worker` token (with the orchestrator-provided worktree path), exactly as the rest of the plugin treats flags. **When the `--worker` token is absent, none of this section applies and the entire sequential pipeline above runs byte-unchanged.** Sequential (non-worker) `solve-issue` is the default and is unaffected.

Worker mode **is today's `solve-issue` pipeline with EXACTLY THREE DELTAS.** Everything else is identical: triage (run as Branch A when the brief embeds the result as explicit named values, or Branch B fallback when absent — workers re-invoke triage ONLY as Branch B fallback if the caller supplied no result) and the root-cause gate, the implementer dispatch and its contract, the declaration gates, the unit gate, `/code-review` and its **Code Review** section, the citations, park-don't-prompt (a worker never prompts a human — it parks), the Decision Log, the version-bump rules (step 6.4), and the audit trail all carry over verbatim. **The permission pre-flight gate is not in this carry-over list** — it is orchestrator-level, pre-dispatch behavior (see the section above); a worker is already backgrounded past it and never runs it. The **at-most-2 re-dispatch cap on every gate** carries over too, but follows its gate: each cap applies to the gate it guards, so the caps on the **parallel-safe gates the worker actually runs** travel with the worker, while the caps on the **deferred gates (E2E, any server-starting preflight)** move to the serial tail with those gates (Delta 2). This gate-split is the **mechanism** of Delta 2 ("builds but does not merge") — it is not a hidden fourth behavioral change. Only the three deltas below differ. Both Branch A and Branch B return the identical Step 7 schema — an issueStates entry plus an edges array, per skills/triage/SKILL.md — so the Blocker check and build-profile read are shape-identical regardless of which branch ran.

> **Permission pre-flight gate and worker mode.** The permission pre-flight gate (described in the section above) is **orchestrator-level, pre-dispatch behavior**. A worker is already backgrounded past it — the gate ran (or was skipped on a synchronous path) before the worker was dispatched. A worker **never runs the gate itself**.

### Delta 1 — Runs in an orchestrator-provided worktree

The **orchestrator owns worktree creation.** `git worktree add <path> -b issue/<n>-<slug> <integrationBranch>` is run by the orchestrator (solve-milestone, #72), which passes the worktree path to the worker. The worker **runs inside that provided worktree** — it does **not** create its own. This resolves ownership of `git worktree add`: the orchestrator, not the worker.

The branch-state probe (step 3 of the procedure) operates **inside that worktree**, and worker mode **replaces step-3 path (d)**. Because the orchestrator already cut the branch with `-b`, the cold worker start is a branch that *exists*, is clean, and is 0 commits ahead — a state that matches none of resume paths (a)/(b)/(c) and would fail path (d)'s "no branch" guard. That pre-cut-branch cold case is a **defined state, not a fall-through**: on a cold worker start the worker **builds directly on the orchestrator-created branch — it does not cut a fresh branch**. The probe's resume paths (a)/(b)/(c) still apply **unchanged** if a worker is re-dispatched against a worktree that already carries prior work (an open PR, commits ahead, or uncommitted changes). All other "Before starting" preconditions apply within the worktree.

**`force-subagent` compatibility (no change needed).** A worker's edits are already permitted: a dispatched subagent carries `agent_id` / `parent_session_id`, which the hook treats as allow (`hooks/force-subagent.sh:18-21` — the subagent-context allow loop). The profile (`milestone-driver.json`) is a committed, tracked file, so it is present in every worktree, and the hooks resolve it `cwd`-relative (`hooks/force-subagent.sh:34-38`) — they fire identically inside a worktree. No worktree-specific hook configuration is required.

### Delta 2 — Stops before the step-8 auto-merge; builds but does not merge

The worker builds, runs the **parallel-safe gates in the worktree**, does the version bump (step 6.4), commits, pushes, then **returns the branch instead of merging.** It does **not** run step 8 (auto-merge). Each worker applies the same idempotent bump to the shared milestone target in `plugin.json`; because the edits are identical same-line writes, the merge-in tail reconciles them in a 3-way merge without conflict — so the bump stays in the worker.

**Parallel-safe gates** (run in the worktree, in the parallel phase):
- the unit suite (step 4) if `unitTestCmd` is defined;
- `/code-review` and its resolve loop (step 6.1);
- the static `preflightCmd` — the lint / format / static-analysis / security-scan class only.

**Deferred gates** (NOT run by the worker — handed to the serial merge tail, #73). Concurrent workers each starting a **port-binding** gate (dev server / E2E / render-smoke) contend for the same fixed port. So in parallel mode the worker runs **only** the parallel-safe gates above; **E2E (step 5) and any server-starting "preflight" are deferred to the serial tail**, where they run once against accumulated integrated state — also where they are more meaningful.
- **Step 7 (visual-review gate) splits the same way.** Opening the PR and applying the `needs review` label are parallel-safe, so a UI-issue worker does those. But the **render/screenshot capture is port-binding** (it spins up a render server via `e2eEnv` / `screenshotCmd`) — so it is a **deferred gate too**: the worker **must not** spawn a render server in the parallel phase. The screenshots are owed by the **serial tail / human**, not attached by the worker. (So a parallel worker leaves a UI PR open with the `needs review` label but **no** screenshots yet; the tail or the human captures them before merge — consistent with step 7's existing "screenshot is convenience evidence; the human-before-merge checkpoint holds either way".)
- **Escape hatch:** a consumer can inject a per-worktree `PORT` (so each worktree binds a distinct port) to keep such a gate — including the render/screenshot capture — in the parallel phase instead of deferring it.

**PR-opening is granularity-conditional:**

| Granularity | Worker opens a PR? | Merge handling |
|---|---|---|
| **Issue (default)** | Yes — `--base <integrationBranch>`; for a UI issue the worker runs **only the parallel-safe part of step 7** (opens the PR, applies the `needs review` label) and **defers the render/screenshot capture to the serial tail / human** — see Delta 2 | The serial merge tail (#73) merges each PR individually; it (or the human) captures the deferred screenshots |
| **Wave (#75)** | No per-issue PR — hands the branch back | The orchestrator folds the branch into the **wave branch** (`wave/<milestone>-w<N>`) and opens one wave PR |

### Delta 3 — Returns a structured handback

The worker returns a structured handback so the orchestrator can drive the merge tail and the final summary without re-deriving state from git/gh:

```text
{ issue, status: built-green | parked, branch, worktreePath, prUrl?, isUI, declarations, parkLabel?, parkReason? }
```

- `prUrl?` — optional: present in **issue** granularity (the worker opened a PR); absent in **Wave** granularity (no per-issue PR).
- `isUI` — whether the issue touched a UI surface (drives the visual-review hold in the tail). The worker derives this from the **worktree diff against `integrationBranch`** — changed files matching `uiSurfaceGlobs` (`git diff <integrationBranch>...HEAD --name-only`), not from a PR's changed-file list — so `isUI` is computable whether or not a per-issue PR was opened (Wave granularity and parked workers have no per-issue PR). An implementer `NEW_UI_ELEMENTS: yes` declaration reinforces the signal, mirroring step 7.
- `declarations` — the implementer's `USER-FACING CHANGES` block (e.g. `NEW_UI_ELEMENTS`), carried through so the orchestrator does not re-read it.
- `parkLabel?` / `parkReason?` — present **only** when `status: parked`.

**A worker that parks hands back `status: parked`** with its `parkLabel` and `parkReason` (the same label/reason it would otherwise post per park-don't-prompt). The orchestrator excludes a parked issue from the merge tail with its branch and labels intact — exactly as the sequential loop excludes a parked issue, just signaled through the handback instead of inferred from labels.

### Sequential behavior is byte-unchanged

These three deltas are the **only** differences. With no `--worker` token, the pipeline above runs exactly as written — same gates, same caps, same merge, same close. Worker mode adds an opt-in path; it changes nothing about the default sequential run.

## Async mode (`--async`)

**`--async` is an interpreted token, not a parsed CLI flag.** Claude Code does no argument parsing — `$ARGUMENTS` is string-substituted — so async mode is **recognized** when the invocation text contains an `--async` token. **When the `--async` token is absent, none of this section applies and the entire sequential pipeline above runs byte-unchanged.** Async mode is an opt-in signal to the caller (main line or user session) to dispatch this skill as `Agent(run_in_background: true)` — it does not alter the internal pipeline, except for Delta A1 below.

### How the caller dispatches

When the caller invokes `solve-issue <n> --async`, it dispatches the full pipeline as `Agent(run_in_background: true)`. The main line (or user session) **awaits the completion notification** from the Agent tool when the background agent finishes. There is no mid-run redirect — the background agent runs to completion; redirects are impossible once it is dispatched. **No PushNotification is sent by the background agent** — PushNotification is confirmed absent from subagent tool registries (see issue #97 recorded decision). The main line (caller) emits the park or wave-boundary notification at this chunk boundary, after receiving the Agent tool completion notification and re-deriving terminal state from live `gh` queries.

### Pre-dispatch: permission pre-flight gate

Before the caller dispatches any background agent, run the **permission pre-flight gate** per `## Permission pre-flight gate` above.

- **No gaps:** proceed — dispatch `solve-issue <n>` as `Agent(run_in_background: true)`.
- **Gap detected:** do **not** dispatch as a background agent. Surface the 🔴 gap table and recommend `/fewer-permission-prompts`. **Fall back to synchronous dispatch** — invoke `solve-issue <n>` (no `--async`) as the normal sequential pipeline. The run completes; it just does not use background concurrency.

### Inside the background agent: the pipeline runs byte-unchanged

The full sequential pipeline (steps 0–9) runs **byte-unchanged** inside the background agent — all gates, park-don't-prompt, PR, auto-merge on green for non-UI issues, visual-review hold for UI issues, close — **except Delta A1**.

### Delta A1 — Version-bump confirm suppressed

The standalone-run patch-bump confirm (the interactive "ask whether it should be minor or major" in step 6.4 standalone runs) cannot prompt from a background context — background subagents auto-deny any tool call that would otherwise prompt (documented Claude Code behavior).

Under `--async`, the bump **defaults to patch** (`x.y.Z` → `x.y.(Z+1)`). This default is **logged in the Decision Log** and the PR carries a `judgment call` label so the call is auditable post-run. Milestone runs are **unaffected** — the milestone-derived target version already replaces the confirm entirely (step 6.4 milestone-run path).

Delta A1 is the **only** behavioral delta because it is the only step in the sequential pipeline that would interactively prompt in a standalone run. All other gates, caps, and park-don't-prompt behavior are unchanged.

### Background agent constraints

- **Auto-deny:** background subagents auto-deny any tool call that would otherwise prompt. The permission pre-flight gate (run before dispatch) guards against un-allowlisted tool calls; Delta A1 eliminates the only remaining interactive confirm. Any unexpected auto-deny mid-run is treated as a park — same park-don't-prompt contract as every other gate.
- **No PushNotification:** the background agent does not send notifications — PushNotification is confirmed absent from subagent tool registries (see issue #97 recorded decision). The main-line caller emits at chunk boundaries (parks + wave completions + run complete/halt).
- **Caller obligation on completion** *(applies to the calling session, not the background agent)*. When the background chunk's completion notification arrives, the calling session re-derives terminal state from live `gh` queries and emits **one notification per dispatched issue**: `⏸️ #N parked — <reason>` if the issue was parked (park reason = the last comment on the issue opening with `🔴 Triage`, `🔴 Blocked`, or `🔴 Parked` — gh returns comments oldest-first, take the LAST match; if none, report "park reason not recorded"), or a `🏁`-style one-liner (e.g. `🏁 #N merged` or `🏁 #N open — awaiting visual review`) if the issue completed (PR merged or held for visual review). This mirrors the handback facts for `--worker` mode; one emit per run, always by the calling session, never by the background agent. (When `--async` is dispatched by `solve-milestone`, solve-milestone's own emit rules govern — per-issue completion notifications are suppressed in sequential mode in favor of the aggregate `🏁` run-complete signal; this per-issue obligation applies to standalone callers outside solve-milestone's orchestration.)
- **No SendMessage/mid-chunk redirect:** the background agent runs to completion; mid-run redirect is not possible in Claude Code.

## Output spec

<!-- KEEP THIS ICON LEGEND BYTE-IDENTICAL across solve-issue and solve-milestone (see plan 2026-06-04 verification model). -->
**Icon legend:** ✅ merged · 🔨 building · ⏭️ queued · ⏸️ parked · 👁️ awaiting visual review · ⚖️ judgment call · 🔴 Your move

### Template 1 — Run start / plan board

Show after the ### 0. Triage step completes.

```text
🚀 Issue #201 — [title] · [risk: light | heavy] · [UI | non-UI]

| Issue | Title   | Risk   | UI | Status      |
|-------|---------|--------|----|-------------|
| #201  | [title] | [risk] | —  | 🔨 building |

▶ Building — the floor is yours.
```

### Template 2 — Issue completion (terminal output)

This is the terminal output for solve-issue. It mirrors the issue-row format of solve-milestone's Template 2.
<!-- Structural mirror of solve-milestone Template 2; keep column schema (Issue/Result/Gates/PR/Note) in sync. -->

One row per issue; emit only the row that matches the actual outcome and suppress the other rows — the `✅ merged` row when the PR was merged, the `👁️ open` row when the PR is awaiting visual review, or the `⏸️ parked` row when the issue was parked.

```text
🏁 Issue #[n] · [T] min

| Issue | Result     | Gates | PR | Note                    |
|-------|------------|-------|----|-------------------------|
| #201  | ✅ merged  | 🔍✓(0 findings)  | #301 | —    |
| #203  | 👁️ open   | 🔍✓(1 fixed)     | #303 | awaiting visual review  |
| #202  | ⏸️ parked  | —                | [#pr | —] | [park label]      |
```
PR cell: show the PR number if the issue has one, else —.

Gates legend: 🧪 = unit suite · 🔍 = code review · 🌐 = E2E

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present steps, gates, lists, and options as **tables**, not inline prose. Mark anything that needs a human with 🔴. (Mirrors the agents' communication-style contract.)

Use the templates in `## Output spec` at their prescribed trigger points. Between boards: one-line dispatch notes only — no narration paragraphs.

## Non-negotiables
- Gitflow. PRs target `integrationBranch` only — never `protectedBranch`.
- Honor the profile's `nonNegotiables` (framework versions, platform targets).
- The main thread never authors application or test code — always dispatch the implementer.
