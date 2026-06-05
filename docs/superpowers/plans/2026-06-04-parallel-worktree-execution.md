# Parallel Worktree Execution Mode Implementation Plan

> **For agentic workers:** delivered as **GitHub milestone 1.5.0**. Each issue is one `/milestone-driver:solve-issue` unit; `solve-issue` generates the per-issue implementation steps at solve time. This repo's source is markdown skills/agents + JSON config (no unit-test harness) — verification is structural (`claude plugin validate`, JSON parse, cross-file consistency, `/code-review`). Steps use `- [ ]` checkboxes.

**Goal:** Add an opt-in `--parallel` mode to `solve-milestone` that builds the mutually-independent issues within a dependency Wave concurrently — each in its own git worktree — then integrates them through a single orchestrator-owned **serial verified merge tail**, cutting wall-clock on wide Waves without weakening any existing gate or the integration-branch blast-radius boundary. It also adds an opt-in **branch-per-wave integration granularity** (`integrationGranularity: "wave"`) that integrates a whole Wave on one branch → one PR → one CI run, to amortize CI cost on long pipelines.

**Architecture:** `solve-milestone --parallel` keeps the existing Phase 0 triage and dependency graph untouched. Per Wave it computes the *parallelizable set* (buildable + mutually independent), dispatches one subagent per issue running `solve-issue` in a new **worker mode** (own worktree, build + verify + review + PR, **stop before merge**, structured handback), barriers on the set, then runs a **serial verified merge tail**: merge the integration target into each green branch → re-run the gates → squash-merge — **force-free**, no history rewrite. Pulling the merge out of the workers and centralizing it is what keeps merges from racing and re-verifies each increment against accumulated state. Default (no flag) is unchanged: sequential, single working tree, no worktrees.

**Tech Stack:** Markdown skills/agents, `milestone-driver.json` (JSON), `git worktree`, `gh`, `git`. Grounding discipline (cite `file:line`; unverifiable → STOP/park) carries over from prior milestones and applies to every step here.

## Why parallel — and the three corrections that shaped this

The win is **parallelizing independent issues within a Wave**. Worktrees are the *isolation mechanism* that makes concurrent file-mutating builds safe; they are not themselves the win. The design converged through three corrections worth recording so they are not re-litigated at build time:

1. **The parallel unit is `/solve-issue <n>`, not `/solve-milestone`.** Handing each worker the milestone command would recursively re-drive the *entire* milestone (re-triage, re-loop) per agent. `solve-milestone` stays the single orchestrator; it fans out one `solve-issue` worker per issue.
2. **The merge-back is not free — it is the orchestrator-owned serial verified tail.** If each worker kept today's auto-merge ([solve-issue.md:165](../../../skills/solve-issue/SKILL.md)), N concurrent merges to one branch would (a) *race* — a textual conflict makes the loser's `gh pr merge` fail with nothing coordinating a re-integration — and (b) land an **untested combination** even when there is no textual conflict, because each branch was verified against the *pre-merge* tip. So the merge moves out of the workers into a serial tail the orchestrator owns.
3. **Dependency-independent ≠ conflict-free.** Two same-Wave issues with no `DEPENDS_ON` edge can still touch the same files. The merge tail's merge-in + re-verify is exactly where that surfaces, governed by the conflict policy below.

## Resolved design decisions (Decision Log)

| Decision | Choice | Rationale |
|---|---|---|
| Activation | A `--parallel` token the skill **recognizes** in `$ARGUMENTS` (plus the natural-language equivalent "in parallel") — not a parsed CLI flag | Claude Code does no argument parsing: `$ARGUMENTS` is string-substituted into the skill body and the model interprets the token. Activation = (1) a `description` trigger phrase + `argument-hint` (`<milestone-name> [--parallel]`) for the natural-language path and slash autocomplete, and (2) body logic that branches on the token. Explicit + scriptable; preserves unattended / cron runs (a prompt would block them). Absent → today's sequential behavior, unchanged. |
| Merge-conflict handling (tail) | **Bounded auto-resolve, else park** | Orchestrator attempts resolution with full-milestone context, then re-runs the unit gate. A non-trivial/ambiguous conflict **or** a red re-test → `git merge --abort` + park `blocked`. Safety valve on a risky op: a wrong auto-resolution can pass tests while silently corrupting logic, so the re-test + park fallback is mandatory. |
| Worker PR timing + tail integration | Workers push the branch + open the PR (parallel CI); the tail integrates via **merge-in** — merge the integration target into the worker branch → re-verify → `gh pr merge --squash` — **force-free** | Field-validated: `--force-with-lease` (and delete-then-repush) get blocked by consumer destructive-command hooks and the runtime's destructive-action classifier, which treat the safe variant like a raw `--force`; `no-push` permitting it is necessary but not sufficient. Merge-in gives the identical re-verify-against-accumulated-state guarantee with no history rewrite, and the merge commit is collapsed by the mandatory `--squash` (never reaching the integration target). The rebase + `--force-with-lease` variant stays available but must be allow-listed in the consumer's hooks/classifier. |
| Integration granularity | `integrationGranularity: "issue" \| "wave"` profile key (default `"issue"`); `"wave"` integrates a whole Wave on one branch → one PR → one CI run | For long/expensive CI, per-issue PRs cost O(issues) runs; wave-branching costs O(waves) and CI-validates the *assembled* wave. Trade-off: coarser failure isolation (one red CI blocks the wave) — viable because the local gates (unit + static preflight + `/code-review` + tail re-verify) catch most failures first. **Logic-only waves**; UI issues stay per-issue/held. Repo-stable economics → a profile key, not a per-run flag. |
| Concurrency cap | Hardcoded sane default (4 workers), no profile key | YAGNI — profile-schema's design principle is "new keys only when a real consumer needs them." A cap prevents resource exhaustion; tunability waits for a real ask. |
| Default behavior | Unchanged: sequential, single tree | Parallel is purely additive and opt-in; zero risk to existing users and existing runs. |

## Execution model (`--parallel`)

Phase 0 (triage → dependency graph + `issueStates`) and the version/target logic are **unchanged**. The parallel branch replaces only the step-4 build loop, and it operates **Wave by Wave**:

| Step | Owner | Action |
|---|---|---|
| Per-Wave set | Orchestrator | Compute the **parallelizable set**: issues in the current Wave that are *buildable* (all `DEPENDS_ON` already merged to `integrationBranch`; no live blocker label; `issueStates[n].blockers == false`) **and** carry no `DEPENDS_ON` edge to another issue in the same set. (Within a Wave these are already mutually dependency-independent by triage's construction; the check is a guard.) |
| Phase 1 — parallel build | One subagent per set issue | Dispatch concurrently (cap 4), each running `/solve-issue <n> --worker`. Barrier: await the whole set before Phase 2. A worker that *parks* returns a parked handback (label + comment already applied) and is simply excluded from the merge tail. |
| Phase 2 — serial verified merge tail | Orchestrator (main working tree) | Integrate the **built-green non-UI** branches one at a time, in deterministic order (ascending issue #). UI issues are **not** merged — they stay open with `needs review` (Layer-2 visual gate, unchanged). Each merge advances the integration target, so the next branch merges in accumulated work before its re-verify. |
| Advance | Orchestrator | After the tail drains, the Wave's work is on `integrationBranch`; recompute the next Wave's buildable set and repeat. |

Parking, dependency-holds, the `judgment call` audit label, and the final-summary contract are inherited from the sequential loop; the summary gains two lines (auto-resolved-conflict issues, and the per-Wave parallel set sizes).

### Phase 2 — the serial verified merge tail (detail)

For each built-green non-UI branch, in order (force-free — no history rewrite):

1. `git fetch`; **merge the current integration target into the worker branch** (`git merge <target>`, where `<target>` is `integrationBranch` in issue granularity or the **wave branch** in wave granularity — see #75). This brings accumulated state onto the branch as an ordinary merge commit — a fast-forwardable push, no `--force`.
2. **Clean merge** → push (fast-forward) → re-verify against accumulated state: `unitTestCmd` if defined, plus any worker-deferred E2E / port-binding gate (see Worker mode) → on green, `gh pr merge --squash --delete-branch` → re-sync local `integrationBranch`. The `--squash` collapses the merge-in commit, so the integration target's history stays linear.
3. **Conflict** → bounded auto-resolve: attempt resolution with full-milestone context (git's `ort` strategy already auto-resolves non-overlapping same-file edits — e.g. two siblings appending distinct routes), then re-verify. Resolvable **and** green → continue at step 2's merge. Non-trivial/ambiguous **or** red → `git merge --abort`, park `blocked` (comment + label + preserve branch), continue with the next branch.
4. **Clean merge but red re-verify** → park `blocked` (the combination is broken; a human decides), continue.

Because the integration target advances after each merge, two same-Wave siblings that touch overlapping files are re-verified against each other — restoring the "every increment tested against accumulated state" guarantee that naive concurrent merging throws away. (The rebase + `--force-with-lease` variant gives the same result but requires consumer allow-listing; see the Decision Log.)

## Worker mode (`solve-issue`, the delta)

Worker mode is today's `solve-issue` with **exactly three deltas** — everything else (gates, caps, citations, park-don't-prompt, the `## Code Review` section) is identical, to keep blast radius minimal:

1. **Runs in an orchestrator-provided worktree** — `git worktree add <path> -b issue/<n>-<slug> <integrationBranch>` — instead of the main working tree. The branch-state probe ([solve-issue.md:36](../../../skills/solve-issue/SKILL.md)) operates inside that worktree.
2. **Stops before auto-merge** ([solve-issue.md:165](../../../skills/solve-issue/SKILL.md), step 8). It builds, runs the **parallel-safe gates in the worktree** — unit + `/code-review` + lightweight static preflight (lint/format/static analysis/security) — does the version bump, commits, pushes, and **returns the branch instead of merging**. PR-opening is **granularity-conditional**: in issue granularity (default) the worker opens the PR and applies `needs review` for UI issues; in wave granularity it opens **no per-issue PR** — the orchestrator folds the branch into the wave branch and opens one wave PR (#75). **Environment / port-binding gates (E2E, and any server-starting "preflight") are deferred to the serial tail** — concurrent workers would otherwise contend for a fixed port, and these gates are more meaningful run against accumulated state; a consumer can opt into per-worktree `PORT` injection to keep such a gate in the parallel phase instead.
3. **Returns a structured handback**: `{ issue, status: built-green | parked, branch, worktreePath, prUrl, isUI, declarations, parkLabel?, parkReason? }` so the orchestrator can drive the merge tail and the summary without re-deriving state.

`force-subagent` already permits a worker's edits — a dispatched subagent carries `agent_id`/`parent_session_id`, which the hook treats as allow ([force-subagent.sh:18-21](../../../hooks/force-subagent.sh)). The profile is a committed, tracked file, so it is present in every worktree and the hooks resolve it `cwd`-relative — they fire identically inside a worktree.

## Worktree lifecycle + hooks compatibility

| Concern | Behavior |
|---|---|
| Creation | Orchestrator creates the worktree off the current `integrationBranch` tip (`git worktree add <path> -b issue/<n>-<slug> <integrationBranch>`) and passes the path to the worker; the worker runs inside it and never cuts its own branch. |
| Cleanup | Orchestrator removes each worktree after its branch merges or parks (`git worktree remove`), and runs `git worktree prune` best-effort at run end / on systemic failure. |
| `force-subagent` | `cwd`-relative profile resolution; worker is a subagent → edits allowed ([force-subagent.sh:18-21](../../../hooks/force-subagent.sh)). ✅ fires correctly per-worktree. |
| `tests-green` | Stamp `.milestone-driver-tests-stamp` is keyed `branch:treeSHA` ([tests-green.sh:31-35](../../../hooks/tests-green.sh)) → a per-worktree stamp is *correct*, not a collision. ✅ |
| `no-push` | Guards only `protectedBranch`; feature-branch push **and** `--force-with-lease` are allowed ([no-push.sh:18-23](../../../hooks/no-push.sh)). ✅ |
| `no-pr-to-protected` | Worker opens PRs `--base <integrationBranch>` → allowed. ✅ |
| `.milestone-driver-preflight-notice` | Per-clone marker becomes per-worktree → the one-time notice could print once per worktree. Acceptable; optionally suppressed by `touch`-ing the marker during worktree setup. |
| Port-binding gates | E2E + any server-starting "preflight" are **deferred to the serial tail** (concurrent workers would contend for a fixed port — field-found on a `:4200` dev-server smoke); per-worktree `PORT` injection is the opt-in alternative. |
| Blast radius | Unchanged — the tail merges only to `integrationBranch`, never `protectedBranch`. Parallelism does not widen the boundary. |

## Integration granularity (issue vs wave)

A second axis, orthogonal to `--parallel`, set by the `integrationGranularity` profile key (default `"issue"`):

- **`"issue"` (default, today's model):** each built issue opens its own PR → its own CI run → merges individually. Granular review, revert, and per-issue failure isolation. Cost: O(issues) CI runs.
- **`"wave"`:** the whole Wave integrates on a single branch `wave/<milestone>-w<N>` → **one PR → one CI run** → merge the wave. Cost: O(waves) CI runs, and CI validates the *assembled* wave (catches integration-level issues an isolated per-issue build misses). For long/expensive pipelines, the big saving.

The merge-tail mechanism is **unchanged** — only its *target* and the worker's PR-opening differ:

| Phase | `"wave"` behavior |
|---|---|
| Worker (#70) | Builds + verifies + commits + pushes its branch, **opens no per-issue PR**; hands the branch back. |
| Merge tail (#73) | Integrates each branch into the **wave branch** (not `integrationBranch`) via the same merge-in + re-verify + bounded-auto-resolve policy. |
| Wave PR (#75) | Orchestrator opens **one** PR `wave/<milestone>-w<N>` → `integrationBranch` listing the wave's logic issues; on CI green, squash-merges the wave, then **explicitly `gh issue close`s** the wave's logic issues (the `Closes #…` keyword does **not** fire on a merge to the non-default `integrationBranch`, so the close is an explicit step), and advances. Auto-merge-on-green moves per-issue → **per-wave**. |

**Logic-only carve-out:** the Layer-2 visual gate is per-UI-issue, so a wave PR cannot both auto-merge (logic) and hold open (UI). A wave containing UI issues keeps those **per-issue / held**; only the logic issues join the wave branch.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `skills/solve-issue/SKILL.md` | modify | Worker mode: the three deltas (worktree, stop-before-merge, structured handback) + granularity-conditional PR-opening. Issue #70. |
| `skills/solve-milestone/SKILL.md` | modify | Parallelizable-set selection (#71); `--parallel` activation + Phase-1 concurrent dispatch + worktree fleet + cap + cleanup (#72); Phase-2 serial verified merge tail + bounded conflict resolve + UI-hold + Wave advance (#73); branch-per-wave integration — wave-branch target + single wave PR + `integrationGranularity` (#75). |
| `docs/profile-schema.md` | modify | `--parallel` arg semantics, the `integrationGranularity` key (the one new key, justified by a real consumer need), the worktree/concurrency-cap note. Issues #74, #75. |
| `README.md`, `docs/architecture.md`, `docs/consumer-setup.md` | modify | Document parallel mode, the merge-tail model, and the conflict policy. Issue #74. |
| `.gitignore` | modify | Ignore the worktree scratch dir (e.g. `.milestone-driver-worktrees/`). Issue #72. |
| `.claude-plugin/plugin.json` | modify | Version → 1.5.0 (rides in the PRs per the existing bump convention). |

## Issue decomposition (milestone 1.5.0)

| # | Issue (proposed title) | Wave | Depends on |
|---|---|:--:|---|
| #76 | `docs: land the 1.5.0 implementation plan (parallel worktree execution + branch-per-wave)` | 0 | — |
| #70 | `feat(solve-issue): worker mode — run in a provided worktree, build-but-don't-merge, structured handback` | 1 | — |
| #71 | `feat(solve-milestone): parallelizable-set selection from the triage dependency graph` | 1 | — |
| #72 | `feat(solve-milestone): --parallel activation + Phase 1 concurrent worker dispatch (worktree fleet, concurrency cap, cleanup)` | 2 | #70, #71 |
| #73 | `feat(solve-milestone): Phase 2 serial verified merge tail — merge-in, re-verify, bounded conflict resolve, UI-hold` | 3 | #72 |
| #75 | `feat: branch-per-wave integration granularity — integrationGranularity profile key, wave-branch target, single wave PR` | 4 | #70, #72, #73 |
| #74 | `docs(1.5.0): parallel worktree execution + branch-per-wave — architecture, README, consumer-setup, schema` | 5 | #70, #71, #72, #73, #75 |

**Note on the milestone's own Wave 1:** #70 (edits `solve-issue/SKILL.md`) and #71 (edits `solve-milestone/SKILL.md`) touch disjoint files, so they are a genuine 2-wide parallel set — this milestone dogfoods the feature it builds. #72 and #73 also edit `solve-milestone/SKILL.md`, so they are serialized after #71 by that shared file (a concrete instance of "dependency-independent ≠ conflict-free": the ordering is what prevents the overlap).

## Acceptance criteria

- **#76** — this plan doc (`docs/superpowers/plans/2026-06-04-parallel-worktree-execution.md`) is committed to the repo via a PR to `integrationBranch`; doc-only, resolved **first** so every subsequent issue branch carries the plan. `claude plugin validate` unaffected.
- **#70** — `solve-issue` documents a `--worker` mode with exactly the three deltas (provided worktree; stop before step-8 auto-merge; structured handback shape spelled out). The branch-state probe runs inside the worktree. **In parallel mode the worker runs only the parallel-safe gates (unit + `/code-review` + static preflight); environment / port-binding gates (E2E, any server-starting "preflight") are deferred to the serial tail** (concurrent workers would contend for a fixed port), with per-worktree `PORT` injection as the opt-in alternative. PR-opening is granularity-conditional (issue: worker opens the PR + `needs review` for UI; wave: no per-issue PR — orchestrator opens one wave PR, see #75). Sequential (non-worker) behavior is byte-unchanged. `claude plugin validate` passes; worker/sequential contracts are cross-file-consistent with `solve-milestone`.
- **#71** — `solve-milestone` documents the parallelizable-set algorithm: buildable (deps merged, no blocker label, triage-clean) ∧ mutually independent within the Wave; consumes triage's existing `dependencyGraph`/`issueStates` (no triage change). Worked example included. No behavior change to the sequential loop.
- **#72** — the skill **recognizes** a `--parallel` token in `$ARGUMENTS` (and the NL equivalent "in parallel") — no CLI parser, it is interpreted text; `solve-milestone` frontmatter gains an `argument-hint` (`<milestone-name> [--parallel]`) and a `description` trigger phrase so both the slash and natural-language forms route to parallel mode. When active and after Phase 0, the orchestrator dispatches one `solve-issue --worker` subagent per set issue, concurrently, capped at 4, barriering on the set; creates/cleans the worktree fleet; `.milestone-driver-worktrees/` git-ignored. Absent → sequential path runs unchanged. Parked workers are excluded from the tail with their labels intact.
- **#73** — Phase-2 serial verified merge tail documented, **force-free by default**: merge the integration target into each branch → re-verify (`unitTestCmd` if defined, plus deferred E2E / port-binding gates) → `gh pr merge --squash` → re-sync, in ascending-issue order; **bounded auto-resolve else park `blocked`** on conflict (`git merge --abort`); park `blocked` on clean-merge-but-red; UI issues held open (never merged); integration target advances between merges. The rebase + `--force-with-lease` variant is documented as an allow-list-required alternative. Final summary gains the auto-resolved-conflict + parallel-set-size lines. Blast-radius boundary (never `protectedBranch`) reaffirmed.
- **#75** — `integrationGranularity: "issue" \| "wave"` documented in `solve-milestone` + `profile-schema.md` (default `"issue"`). In `"wave"`: the merge tail's target is a wave branch `wave/<milestone>-w<N>`; the worker opens no per-issue PR (#70); the orchestrator opens **one wave PR** → `integrationBranch` with `Closes #…` for the wave's issues, then merges the wave on CI green. **Logic-only carve-out:** a wave with UI issues keeps those per-issue/held; only logic issues join the wave branch. Auto-merge-on-green moves per-issue → per-wave. Issue granularity (default) is byte-unchanged. `claude plugin validate` passes.
- **#74** — `architecture.md` gains a parallel-mode section (the Wave-by-Wave model + merge tail + conflict policy + hooks-in-worktree table) **and an integration-granularity section (issue vs wave)**; README + consumer-setup note `--parallel` **and `integrationGranularity` with their trade-offs**; `profile-schema.md` documents the `--parallel` arg, the **`integrationGranularity` key**, and the concurrency-cap rationale; `plugin.json` at 1.5.0. Cross-file terms (`--parallel`, "worker mode", "merge tail", "integration granularity") are consistent across all docs and both skills.

## Proposed milestone 1.5.0 description

A one-line summary + the Wave table above with the real issue numbers (filled immediately after issue creation, since `solve-milestone` reads the milestone description as the ordering source of truth — [solve-milestone.md:44](../../../skills/solve-milestone/SKILL.md)).

## Verification model

`claude plugin validate . --strict` after each skill/schema edit; JSON parse of `plugin.json`; cross-file consistency (the `--worker` contract and the handback shape named identically in `solve-issue` and `solve-milestone`; the conflict policy described once and referenced); `/code-review` before each commit. No behavioral test harness exists in this repo, so worker/tail logic is verified by structural review + a dogfood run of `solve-milestone 1.5.0 --parallel` against this milestone's own 2-wide Wave 1.

## Out of scope (explicitly)

- **File-overlap pre-detection** — predicting textual conflicts *before* build. v1 proceeds optimistically and lets the merge tail's conflict policy catch overlaps. An advisory overlap signal in triage is a possible follow-up, not v1.
- **Cross-Wave / stacked-PR parallelism for *dependent* issues** — only mutually-independent same-Wave issues parallelize. A dependent issue still waits for its upstream to merge (it needs that code to exist).
- **A `maxParallelism` profile key** — the cap is a hardcoded default until a real consumer needs to tune it.
- **Changing the default** — sequential remains the default; parallel is opt-in.

## Risks & trade-offs

- **Semantic (logical) conflicts** — two issues, no textual conflict, combined logic broken. Mitigated by the serial re-verify (re-run the gates on each branch after merging in the accumulated tip). Residual risk only when `unitTestCmd` is absent, where verification falls back to structural/`/code-review` — same limitation the sequential loop already has.
- **Auto-resolve risk** — bounded by the mandatory re-test + park fallback (Decision Log).
- **Disk / resource** — N worktrees + N concurrent builds; the concurrency cap (4) bounds it.
- **History-rewriting pushes are fragile across consumers** — `--force-with-lease` (and delete-then-repush) can be blocked by consumer destructive-command hooks and the runtime's destructive-action classifier. The default tail is therefore **merge-in (force-free)**; the rebase variant requires consumer allow-listing.
- **Wave-granularity failure isolation** — in `integrationGranularity: "wave"`, one red wave-PR CI blocks the whole wave (bisect to find the culprit). Acceptable because the local gates (unit + static preflight + `/code-review` + tail re-verify) catch most failures before the wave PR; CI is the backstop. Not for repos with weak local gates.
