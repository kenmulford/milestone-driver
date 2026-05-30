---
name: solve-milestone
description: This skill should be used when the user invokes "/solve-milestone <name>", or asks to "solve a milestone", "drive a milestone", or "work the milestone autonomously". Autonomously iterates every issue in a GitHub milestone in dependency order, running /solve-issue on each and re-syncing the integration branch between issues. Runs unattended; halts only at a STOP/PAUSE gate or when the milestone is complete.
version: 0.1.0
---

# solve-milestone — autonomous driver

Drive an entire GitHub milestone to completion by ordering its issues and running `/solve-issue` on each, integrating to `integrationBranch` between issues. This skill owns **ordering, the loop, branch re-sync, halting, and the final summary**; the full per-issue pipeline — root-cause, implementer dispatch, gates, review, PR, auto-merge, close — is delegated to `/solve-issue`.

**Bounded blast radius.** The loop merges only to `integrationBranch`, never to `protectedBranch`. Release (`integrationBranch` → `protectedBranch`) and deploy stay manual and human-only. That boundary is what makes unattended operation safe.

## Before starting

1. Read the profile at `milestone-driver.json` (repo root; see the plugin's `docs/profile-schema.md`). Fail fast if a required key is missing.
2. Confirm `gh auth status` is healthy and the named milestone exists.
3. Confirm the working tree is clean and the local `integrationBranch` is current (`git fetch`, fast-forward).

## The procedure

### 1. List the milestone's open issues
Run `gh issue list --milestone "<name>" --state open`.

### 2. Determine the order
The **milestone description is the ordering source of truth**. Read it (e.g. `gh api "repos/{owner}/{repo}/milestones" --jq '.[] | select(.title=="<name>") | .description'`) and follow the recorded Wave / dependency sequence. If the description records no explicit order, fall back to ascending issue number and **state that assumption explicitly** in the run output — do not silently pick an order.

### 3. Loop over issues in order
Create one TodoWrite item per issue. For each issue, in order:

1. Ensure `integrationBranch` is current (`git fetch`, fast-forward) so dependent issues build on already-merged work.
2. Run `/solve-issue <n>`.
3. **🔴 Halt on gate:** if `/solve-issue` hits a STOP or PAUSE (no root cause, new dependency, architecture conflict, scope overrun, ambiguity, unmetable gate), **halt the loop and resurface**. Do not start dependent issues on top of incomplete work.
4. On success, `/solve-issue` has already squash-merged to `integrationBranch` and closed the issue. Re-sync the local `integrationBranch` before the next issue.

### 4. Finish
Continue until every issue is done or a gate halts the loop.

## Autonomy

- **Unattended between gates.** Within an explicit `/solve-milestone` run, operate autonomously and pause only at the `/solve-issue` STOP/PAUSE gates above or at completion — not for routine implementation choices.
- **Architecture is locked** per issue at its plan-approval time. The loop executes approved architecture; it does not pivot. A plan proven wrong is a STOP, not a redesign.
- **Never escalate scope to `protectedBranch`.** No PR, push, or merge targets `protectedBranch` (enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection).

## Final summary

On halt or completion, report:
- Issues merged to `integrationBranch` (with PR links).
- Issues skipped or blocked, and why (the STOP/PAUSE reason).
- PRs carrying a `⚠ judgment-call` label, flagged for post-run review.
- The next human step (review the merged PRs; when ready, merge `integrationBranch` → `protectedBranch` and deploy manually).
