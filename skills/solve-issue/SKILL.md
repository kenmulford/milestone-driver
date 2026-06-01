---
name: solve-issue
description: This skill should be used when the user invokes "/milestone-driver:solve-issue <n>", or asks to "solve issue <n>", "fix issue <n>", or "drive issue <n>" through the milestone-driver gated procedure. Runs one GitHub issue end-to-end as an orchestrator — root-cause-or-STOP, dispatch the implementer subagent (TDD, citations), unit + E2E gates, code review, PR to the integration branch, auto-merge on CI green, then close — never authoring application or test code on the main thread.
---

# solve-issue — gated per-issue procedure

Run exactly one GitHub issue through a fixed, gated pipeline. The main thread acts only as an **orchestrator**: read, decide, dispatch, review, integrate. It **never authors application or test code itself** — the `force-subagent` hook enforces this mechanically, so honor it by design.

Orchestrate the `superpowers:*` skills for the inner loop rather than reimplementing their discipline.

## Before starting

1. Read the profile at `milestone-driver.json` (repo root; see the plugin's `docs/profile-schema.md`). If the file is absent or any of `integrationBranch`, `protectedBranch`, or `sourceGlobs` is missing, invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. `implementerAgent` defaults to `milestone-driver:implementer` when omitted. The keys `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `domainSkills`, and `nonNegotiables` are optional; their steps are skipped cleanly when absent.
2. Confirm the working tree is clean and the local `integrationBranch` is current (`git fetch`, fast-forward).
3. Cut a feature branch for the issue from `integrationBranch` (e.g. `issue/<n>-<slug>`).
4. Create one TodoWrite item per numbered step below. Work them in order — do not skip or reorder.

## The procedure

### 1. Read the issue
Run `gh issue view <n>` with comments. Restate the acceptance criteria plainly before continuing.

### 2. Evaluate the codebase for root cause
Invoke `superpowers:systematic-debugging`. Read the implicated code — the file(s) plus direct callers and callees.

**🔴 GATE — root cause:** If the root cause cannot be identified from the codebase, **STOP**. Post a comment describing the blocker (`gh issue comment <n>`) and halt. Do not proceed to implementation.

When found, write an **architecture-aware plan** with full awareness of the codebase and its conventions. This plan is the **locked** architecture for this issue.

### 3. Dispatch the implementer
Dispatch the profile's `implementerAgent` (default `milestone-driver:implementer`; a project-level override in the profile uses that agent's own name as-is) via the Agent tool, orchestrating `superpowers:subagent-driven-development` + `superpowers:test-driven-development`. Brief it like a colleague walking in cold: the issue, the approved plan, the profile, and the expected file scope.

Verify the returned report honors the implementer contract: least-code / reuse-first, TDD red→green observed (or a `VERIFICATION (no test layer)` section when `unitTestCmd` is absent), verified citations where citable sources exist, a Decision Log, and **changes left uncommitted**.

**🔴 GATE — new dependency:** If the implementer reports that the optimal solution requires a new library or toolkit, **PAUSE**. Post the library plus its license / OSS status on the issue and ask the user for approval before continuing.

### 4. Unit suite → green
If `unitTestCmd` is defined in the profile: run it and invoke `superpowers:verification-before-completion`. Report real output, never assertion.

If `unitTestCmd` is absent: skip this gate. The implementer is responsible for verifying behavior by the best available means and reporting it; the orchestrator accepts that report in lieu of a test run.

**🔴 GATE — tests (when `unitTestCmd` is defined):** A red suite blocks progress. Re-dispatch the implementer with the failure, or STOP if the failure reveals the plan is wrong (see Autonomy).

**Cap: at most 2 implementer re-dispatches on a red suite.** If the suite is still red after the 2nd re-dispatch, **STOP and resurface** — do not loop. A suite that won't go green usually means the plan is wrong (see Autonomy).

### 5. E2E pre-merge gate
Apply only when the change touches a UI surface and the profile defines `e2eTestCmd`:
- **Bug:** run a targeted subset that proves the fix.
- **Feature:** have the implementer author new end-to-end (E2E) tests covering reasonable user stories, then run them.

Use the profile's `e2eEnv` configuration. Skip this step only when the issue touches no UI.

**Cap: at most 2 E2E fix attempts.** If the E2E suite still fails after the 2nd fix, **STOP and resurface** — do not loop; a non-converging E2E gate usually means the plan is wrong (see Autonomy).

### 6. Review → integrate → close
1. **Review and resolve.** Run `/code-review` (`superpowers:requesting-code-review`) on the implementer's **uncommitted** changes, then resolve findings autonomously per the Autonomy model — do **not** pause to ask the operator about an in-scope finding:
   - **In-scope** (cosmetic, naming, style, local reversible refactor, missing/weak test): re-dispatch the implementer to fix it (the main thread cannot edit `sourceGlobs` — `force-subagent`); log it in the Decision Log.
   - **STOP trigger** (architecture deviation; a shared contract/interface/schema change; a new dependency; edits outside the issue's file scope; an unmetable gate; material ambiguity): **STOP and resurface** — do not commit.

   **After a fix, before committing:**
   - **Code changed** (any `sourceGlobs` file): re-run `unitTestCmd` if defined (skip if absent), then re-run `/code-review` — the fresh review must be the **last action before commit**, so a review-before-commit gate passes on the first attempt (never retry past it).
   - **Document-only** (`*.md`, READMEs, doc/comment text — nothing under `sourceGlobs`): commit directly; no re-run needed (`tests-green` and a doc-aware review gate both no-op on doc-only).
   - **No in-scope findings:** commit directly.

   **Cap: at most 2 review→fix cycles.** If `/code-review` still returns in-scope findings after the 2nd fix, **STOP and resurface** the current diff — do not loop. A review that won't converge usually means the plan is wrong.
2. Assemble the **Decision Log** from the implementer's report (each choice → rationale → citation → alternatives rejected) for the PR body, and post the citations on the issue for review (`gh issue comment <n>`).
3. **Version bump.** Edit `.claude-plugin/plugin.json` `version` directly (it is config, not under `sourceGlobs`; the orchestrator edits it on the main thread — if a consumer's `sourceGlobs` covers `.claude-plugin/`, dispatch the implementer to apply the bump instead). This is a config edit, not a source change: **no `/code-review` re-run and no test re-run are needed; proceed directly to commit.**
   - **Milestone run** (a target version was determined by `solve-milestone` and is held in the orchestrator's context — it is not a CLI argument): set `plugin.json` `version` to that target. **Idempotent** — if already equal, no change; move on.
   - **Standalone run** (no milestone target in the orchestrator's context): apply a **patch** bump (`x.y.Z` → `x.y.(Z+1)`), state the new version to the user, and **ask whether it should be minor or major instead** — adjust before opening the PR.
   - `plugin.json` is the **single source of truth** for the plugin version. `marketplace.json` carries no `version` field (Claude Code resolves `plugin.json` first; setting both is a documented footgun that silently masks the marketplace value). The bump rides in this PR — no separate chore PR.
4. Commit on the feature branch — the `tests-green` hook (`PreToolUse` on `git commit`) re-checks the suite, and running `/code-review` first satisfies any review-before-commit gate.
5. Push the feature branch and open a PR with `--base <integrationBranch>` (never `protectedBranch` — enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection). Put the Decision Log in the PR body. Add a `⚠ judgment-call` label if any borderline autonomous call was made.
6. **Auto-merge on green:** once CI is green, run `gh pr merge --squash --delete-branch`. This replaces the human-choice step of `superpowers:finishing-a-development-branch`.
7. Confirm the issue is closed (a linked PR auto-closes it; otherwise `gh issue close <n>`).

## Autonomy model (Balanced)

**Proceed autonomously (log on the PR):** implementation choices within the approved architecture; reuse of existing helpers, styles, and conventions; test design; local reversible refactors; resolving in-scope `/code-review` findings (step 6.1).

**🔴 STOP & resurface (halt, ask):** deviation from the approved architecture; any change to a shared contract, interface, base class, or DB schema used beyond this issue; a new dependency; edits outside the issue's expected file scope; a gate that cannot be met without a design change; material ambiguity in the issue's intent.

**Within an explicit run, an in-scope `/code-review` finding is a *proceed-autonomously* event, not a clarifying-question moment** — fix it and log it. The operator pause is reserved for STOP triggers; the unattended contract overrides any general inclination to ask.

**Architecture is locked** at plan-approval time (step 2). The procedure executes approved architecture; it does not pivot. If implementation proves the plan wrong → STOP, not pivot.

A change is **architecture** (→ STOP) if it touches any of: a component or data structure named in the approved plan; a shared contract, interface, base class, DB schema, or public API used by code outside this issue; data ownership or a cross-component boundary; a new external dependency; or any file outside this issue's stated scope. A change is an **implementation detail** (→ proceed, log) if it is local to this issue's own files, changes no shared contract, and is reversible — a binding style, a private helper, a local refactor, or test design. When the distinction is genuinely ambiguous, treat it as architecture and STOP.

| Scenario | Classification | Action |
|---|---|---|
| Computed get-only binding → backed `SetProperty` (same property name, same consumer contract) | Implementation detail | Proceed, log in PR Decision Log |
| Extracting an existing method into a private helper in the same file | Implementation detail | Proceed, log if non-trivial |
| Adding a parameter to a shared interface used by other issues/components | Architecture | STOP |
| Moving data ownership from ViewModel A to Service B | Architecture | STOP |

**Audit trail (always):** a Decision Log on every PR, and a `⚠ judgment-call` label on borderline calls, so post-run PR review surfaces every judgment.

## Non-negotiables
- Gitflow. PRs target `integrationBranch` only — never `protectedBranch`.
- Honor the profile's `nonNegotiables` (framework versions, platform targets).
- The main thread never authors application or test code — always dispatch the implementer.
