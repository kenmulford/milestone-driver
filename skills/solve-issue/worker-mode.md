# Worker mode (`--worker`) — solve-issue reference

This file is loaded by `SKILL.md`'s `## Worker mode (\`--worker\`)` header when the dispatch text contains a `--worker` token. It defines the three deltas worker mode applies on top of the sequential pipeline, and the structured handback the orchestrator consumes. With no `--worker` token, this file is never read and the sequential pipeline in `SKILL.md` runs byte-unchanged.

---

Worker mode is the per-issue half of `solve-milestone`'s parallel (default) flow (milestone 1.5.0): the orchestrator builds mutually-independent issues within a dependency Wave concurrently — each in its own git worktree — then integrates them through an orchestrator-owned **serial verified merge tail**. This section defines the contract the parallel orchestration (#72), the merge tail (#73), and branch-per-Wave granularity (#75) consume; those skills do not exist yet, so the terms used here (`--worker`, "worker mode", "merge tail", "handback", "wave branch", "parallel-safe gates", "deferred gates") are the authoritative source.

Worker mode **is today's `solve-issue` pipeline with EXACTLY THREE DELTAS.** Everything else is identical: triage (run as Branch A when the brief embeds the result as explicit named values, or Branch B fallback when absent — workers re-invoke triage ONLY as Branch B fallback if the caller supplied no result) and the root-cause gate, the implementer dispatch and its contract, the declaration gates, the unit gate, `/code-review` and its **Code Review** section, the citations, park-don't-prompt (a worker never prompts a human — it parks), the Decision Log, the version-bump rules (step 6.4), and the audit trail all carry over verbatim. **The permission pre-flight gate is not in this carry-over list** — it is orchestrator-level, pre-dispatch behavior (see `SKILL.md`'s `## Permission pre-flight gate`); a worker is already backgrounded past it and never runs it. The **at-most-2 re-dispatch cap on every gate** carries over too, but follows its gate: each cap applies to the gate it guards, so the caps on the **parallel-safe gates the worker actually runs** travel with the worker, while the caps on the **deferred gates (E2E, any server-starting preflight)** move to the serial tail with those gates (Delta 2). This gate-split is the **mechanism** of Delta 2 ("builds but does not merge") — it is not a hidden fourth behavioral change. Only the three deltas below differ. Both Branch A and Branch B return the identical Step 7 schema — an issueStates entry plus an edges array, per skills/triage/SKILL.md — so the Blocker check and build-profile read are shape-identical regardless of which branch ran.

> **Permission pre-flight gate and worker mode.** The permission pre-flight gate (described in `SKILL.md`'s `## Permission pre-flight gate`) is **orchestrator-level, pre-dispatch behavior**. A worker is already backgrounded past it — the gate ran (or was skipped on a synchronous path) before the worker was dispatched. A worker **never runs the gate itself**.

### Delta 1 — Runs in an orchestrator-provided worktree

The **orchestrator owns worktree creation.** `git worktree add <path> -b issue/<n>-<slug> <integrationBranch>` is run by the orchestrator (solve-milestone, #72), which passes the worktree path to the worker. The worker **runs inside that provided worktree** — it does **not** create its own. This resolves ownership of `git worktree add`: the orchestrator, not the worker.

The branch-state probe (step 3 of the procedure) operates **inside that worktree**, and worker mode **replaces step-3 path (d)**. Because the orchestrator already cut the branch with `-b`, the cold worker start is a branch that *exists*, is clean, and is 0 commits ahead — a state that matches none of resume paths (a)/(b)/(c) and would fail path (d)'s "no branch" guard. That pre-cut-branch cold case is a **defined state, not a fall-through**: on a cold worker start the worker **builds directly on the orchestrator-created branch — it does not cut a fresh branch**. The probe's resume paths (a)/(b)/(c) still apply **unchanged** if a worker is re-dispatched against a worktree that already carries prior work (an open PR, commits ahead, or uncommitted changes). All other "Before starting" preconditions apply within the worktree, including the **step-3.5 profile migration**: each worker re-runs the idempotent migration preamble inside its own worktree, and the `git mv` rides that worker's branch (reconciled by the serial merge tail). It is idempotent, so a worktree cut from a tip where `.milestone-config/driver.json` already exists is a clean no-op.

**`force-subagent` compatibility (no change needed).** A worker's edits are already permitted: a dispatched subagent carries `agent_id` / `parent_session_id`, which the hook treats as allow (`hooks/force-subagent.sh:18-21` — the subagent-context allow loop). The profile (`.milestone-config/driver.json`, or a legacy root `milestone-driver.json`) is a committed, tracked file, so it is present in every worktree, and the hooks resolve it `cwd`-relative (`hooks/force-subagent.sh:34-40`) — they fire identically inside a worktree. No worktree-specific hook configuration is required.

### Delta 2 — Stops before the step-8 auto-merge; builds but does not merge

The worker builds, runs the **parallel-safe gates in the worktree**, does the version bump (step 6.4), commits, pushes, then **returns the branch instead of merging.** It does **not** run step 8 (auto-merge). Each worker applies the same idempotent bump to the shared milestone target in `plugin.json`; because the edits are identical same-line writes, the merge-in tail reconciles them in a 3-way merge without conflict — so the bump stays in the worker.

**Parallel-safe gates** (run in the worktree, in the parallel phase):
- the unit suite (step 4) if `unitTestCmd` is defined;
- `/code-review` and its resolve loop (step 6.1);
- the static `preflightCmd` — the lint / format / static-analysis / security-scan class only.

**Deferred gates** (NOT run by the worker — handed to the serial merge tail, #73). Concurrent workers each starting a **port-binding** gate (dev server / E2E / render-smoke) contend for the same fixed port. So in parallel builds the worker runs **only** the parallel-safe gates above; **E2E (step 4, E2E row) and any server-starting "preflight" are deferred to the serial tail**, where they run once against accumulated integrated state — also where they are more meaningful.
- **Step 7 (visual-review gate) splits the same way.** Opening the PR and applying the `needs review` label are parallel-safe, so a UI-issue worker does those. But the **render capture is port-binding** (it boots the render daemon — `scripts/render-daemon.{sh,ps1}` — which spins up the `visualCapture.serverCmd` app server on the consumer's fixed port) — so it is a **deferred gate too**: the worker **must not** boot the render daemon or capture in the parallel phase (a single per-run, fixed-port daemon cannot safely serve concurrent worktrees). The screenshots are owed by the **serial tail / human**, not attached by the worker. (So a parallel worker leaves a UI PR open with the `needs review` label but **no** screenshots yet; the serial tail or the human runs the step-7 capture flow before merge — consistent with step 7's "capture is convenience evidence; the human-before-merge checkpoint holds either way".)
- **Escape hatch:** a consumer can inject a per-worktree `PORT` (so each worktree binds a distinct port) to keep such a gate — including the render/screenshot capture — in the parallel phase instead of deferring it.

**PR-opening is granularity-conditional:**

| Granularity | Worker opens a PR? | Merge handling |
|---|---|---|
| **Issue (default)** | Yes — `--base <integrationBranch>`; for a UI issue the worker runs **only the parallel-safe part of step 7** (opens the PR, applies the `needs review` label) and **defers the render/screenshot capture to the serial tail / human** — see Delta 2 | The serial merge tail (#73) merges each PR individually; it (or the human) captures the deferred screenshots |
| **Wave (#75)** | No per-issue PR — hands the branch back | The orchestrator folds the branch into the **wave branch** (`wave/<milestone>-w<N>`) and opens one wave PR |

### Delta 3 — Returns a structured handback

The worker returns a structured handback as an **optimization hint** — it lets the orchestrator skip redundant git/gh queries when driving the merge tail and the final summary. It is explicitly **not** the source of truth. The Phase 1 barrier (`solve-milestone` step 5) **re-derives terminal state from git/gh** via the step-3 branch-state probe and uses the handback only as a hint: when the handback is present and well-formed the barrier skips the queries the probe would otherwise run; when the handback is **absent or partial** — e.g. the worker's final assistant message drifted off-format under a long, tool-heavy run — the barrier **fills in every field from ground truth** and no work is stranded. Each field below is independently re-derivable from git/gh, so the handback degrades gracefully:

```text
{ issue, status: built-green | parked, branch, worktreePath, prUrl?, isUI, declarations, parkLabel?, parkReason? }
```

| Handback field | Ground-truth source the barrier re-derives from |
|---|---|
| `status: built-green` | open PR for `issue/<n>-*`, or branch pushed with commits ahead of `integrationBranch` (step-3 probe paths a/b) |
| `status: parked` | park label (`needs design` / `needs decision` / `blocked`) + `🔴 Parked` / `🔴 Triage` / `🔴 Blocked` comment (the same signal the sequential loop reads) |
| `prUrl` | `gh pr list … select(.headRefName \| startswith("issue/<n>-"))` (verbatim step-3 path-a query) |
| `isUI` | `git diff <integrationBranch>...HEAD --name-only` ∩ `uiSurfaceGlobs` (re-derived as below, not from a PR) |
| `declarations` | the only field not in git/gh; reinforces `isUI`, which is independently computable — so a drop degrades gracefully |

- `prUrl?` — optional: present in **issue** granularity (the worker opened a PR); absent in **Wave** granularity (no per-issue PR).
- `isUI` — whether the issue touched a UI surface (drives the visual-review hold in the tail). The worker derives this from the **worktree diff against `integrationBranch`** — changed files matching `uiSurfaceGlobs` (`git diff <integrationBranch>...HEAD --name-only`), not from a PR's changed-file list — so `isUI` is computable whether or not a per-issue PR was opened (Wave granularity and parked workers have no per-issue PR). An implementer `NEW_UI_ELEMENTS: yes` declaration reinforces the signal, mirroring step 7.
- `declarations` — the implementer's `USER-FACING CHANGES` block (e.g. `NEW_UI_ELEMENTS`), carried through so the orchestrator does not re-read it.
- `parkLabel?` / `parkReason?` — present **only** when `status: parked`.

**A worker that parks hands back `status: parked`** with its `parkLabel` and `parkReason` (the same label/reason it would otherwise post per park-don't-prompt). The orchestrator excludes a parked issue from the merge tail with its branch and labels intact — exactly as the sequential loop excludes a parked issue. The barrier **re-derives the park from git/gh** (live labels + the step-3 probe), using `parkLabel` / `parkReason` from the handback only as a corroborating hint; the park is never inferred from the handback alone, so a dropped final message cannot hide a parked issue any more than it can strand a built-green one.

### Sequential behavior is byte-unchanged

These three deltas are the **only** differences. With no `--worker` token, the sequential pipeline in `SKILL.md` runs exactly as written — same gates, same caps, same merge, same close. Worker mode adds an opt-in path; it changes nothing about the default sequential run.
