---
name: solve-issue
description: This skill should be used when the user invokes "/solve-issue <n>", or asks to "solve issue <n>", "fix issue <n>", or "drive issue <n>" through the milestone-driver gated procedure. Runs one GitHub issue end-to-end as an orchestrator — root-cause-or-STOP, dispatch the implementer subagent (TDD, citations), unit + E2E gates, code review, PR to the integration branch, auto-merge on CI green, then close — never authoring application or test code on the main thread.
version: 0.1.0
---

# solve-issue — gated per-issue procedure

Run exactly one GitHub issue through a fixed, gated pipeline. The main thread acts only as an **orchestrator**: read, decide, dispatch, review, integrate. It **never authors application or test code itself** — the `force-subagent` hook enforces this mechanically, so honor it by design.

Orchestrate the `superpowers:*` skills for the inner loop rather than reimplementing their discipline.

## Before starting

1. Read the profile at `.claude/milestone-driver.json` (see the plugin's `docs/profile-schema.md`). Fail fast if a required key is missing.
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
Dispatch the profile's `implementerAgent` (default `implementer`) via the Agent tool, orchestrating `superpowers:subagent-driven-development` + `superpowers:test-driven-development`. Brief it like a colleague walking in cold: the issue, the approved plan, the profile, and the expected file scope.

Verify the returned report honors the implementer contract: least-code / reuse-first, TDD red→green observed, verified citations from `domainSkills` + a docs MCP, a Decision Log, and **changes left uncommitted**.

**🔴 GATE — new dependency:** If the implementer reports that the optimal solution requires a new library or toolkit, **PAUSE**. Post the library plus its license / OSS status on the issue and ask the user for approval before continuing.

### 4. Unit suite → green
Run the profile's `unitTestCmd` and invoke `superpowers:verification-before-completion`. Report real output, never assertion.

**🔴 GATE — tests:** A red suite blocks progress. Re-dispatch the implementer with the failure, or STOP if the failure reveals the plan is wrong (see Autonomy).

### 5. E2E pre-merge gate
Apply only when the change touches a UI surface and the profile defines `e2eTestCmd`:
- **Bug:** run a targeted subset that proves the fix.
- **Feature:** have the implementer author new end-to-end (E2E) tests covering reasonable user stories, then run them.

Use the profile's `e2eEnv` configuration. Skip this step only when the issue touches no UI.

### 6. Review → integrate → close
1. Invoke `superpowers:requesting-code-review` (run `/code-review`) on the implementer's **uncommitted** changes. Address findings before committing.
2. Assemble the **Decision Log** from the implementer's report (each choice → rationale → citation → alternatives rejected) for the PR body, and post the citations on the issue for review (`gh issue comment <n>`).
3. Commit on the feature branch — the `tests-green` pre-commit hook re-checks the suite, and running `/code-review` first satisfies any review-before-commit gate.
4. Push the feature branch and open a PR with `--base <integrationBranch>` (never `protectedBranch` — enforced by the `no-push-to-protected` hook and GitHub branch protection). Put the Decision Log in the PR body. Add a `⚠ judgment-call` label if any borderline autonomous call was made.
5. **Auto-merge on green:** once CI is green, run `gh pr merge --squash --delete-branch`. This replaces the human-choice step of `superpowers:finishing-a-development-branch`.
6. Confirm the issue is closed (a linked PR auto-closes it; otherwise `gh issue close <n>`).

## Autonomy model (Balanced)

**Proceed autonomously (log on the PR):** implementation choices within the approved architecture; reuse of existing helpers, styles, and conventions; test design; local reversible refactors.

**🔴 STOP & resurface (halt, ask):** deviation from the approved architecture; any change to a shared contract, interface, base class, or DB schema used beyond this issue; a new dependency; edits outside the issue's expected file scope; a gate that cannot be met without a design change; material ambiguity in the issue's intent.

**Architecture is locked** at plan-approval time (step 2). The procedure executes approved architecture; it does not pivot. If implementation proves the plan wrong → STOP, not pivot.

**Audit trail (always):** a Decision Log on every PR, and a `⚠ judgment-call` label on borderline calls, so post-run PR review surfaces every judgment.

## Non-negotiables
- Gitflow. PRs target `integrationBranch` only — never `protectedBranch`.
- Honor the profile's `nonNegotiables` (framework versions, platform targets).
- The main thread never authors application or test code — always dispatch the implementer.
