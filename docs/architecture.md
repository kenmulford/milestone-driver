# Architecture

A generic engine ships in the plugin, and each repo supplies a thin profile.

## Plugin contents

| Component | Path | Purpose |
|---|---|---|
| Driver skill | `skills/solve-milestone/SKILL.md` | The autonomous milestone loop (triage Phase 0, then the dependency-graph build loop) |
| Per-issue skill | `skills/solve-issue/SKILL.md` | The gated per-issue procedure |
| Triage skill | `skills/triage/SKILL.md` | The Layer-0 pre-build review phase: design gaps plus dependency ordering (read-only; authors nothing) |
| Setup skill | `skills/setup/SKILL.md` | Profile bootstrap plus create-if-missing provisioning of the label taxonomy |
| Implementer agent | `agents/implementer.md` | Self-contained TDD implementer subagent (a project may override via its profile) |
| Triage-reviewer agent | `agents/triage-reviewer.md` | Architect-lens reviewer: design consistency / buildability / completeness plus dependency edges (read-only; profile-overridable) |
| Design-reviewer agent | `agents/design-reviewer.md` | Front-end-lens reviewer: UX gaps on UI-touching issues (read-only; profile-overridable) |
| Hooks | `hooks/` | All four gates are `PreToolUse` hooks invoked via `hooks/run-hook.cmd` (bash-first, pwsh-fallback, fail-open): `force-subagent`, `tests-green`, `no-push`, `no-pr-to-protected`. The triage / declaration / visual layers are procedural (skill-level), not hooks. See [The layered gating model](#the-layered-gating-model). |
| Manifest plus registration | `.claude-plugin/plugin.json`, `hooks/hooks.json` | Plugin metadata and Claude-side hook registration |

## Plugin version

Plugin version lives in `.claude-plugin/plugin.json` as the single source of truth. `marketplace.json` carries no `version` field (Claude Code resolves `plugin.json` first; setting both silently masks the marketplace value). The bump rides in the issue or milestone PR itself, not a separate chore: standalone `/milestone-driver:solve-issue` runs apply a patch bump and confirm; `/milestone-driver:solve-milestone` derives the target version from the milestone title and passes it to each issue run idempotently. Version detection is a deterministic, unit-tested extractor (`scripts/extract-version.{sh,ps1}`, issue #158), not model judgment: it scans the milestone title (description as fallback) for a `v`-optional 2/3/4-part version and normalizes it. `versioning: false` is version-free mode (no extraction, no bump). With `versioning` absent the run is opportunistic — a parseable version is used, otherwise it silently degrades to version-free; with explicit `versioning: true` a miss or ambiguous title prompts the operator (degrades with a warning when non-interactive). Fail-safe: a versioned repo whose `.claude-plugin/plugin.json` is missing degrades to version-free with a logged note rather than failing the run.

## The layered gating model

Three defense-in-depth layers catch design gaps (underspecified or self-contradictory acceptance criteria, silent UX gaps, rendered defects) before they reach your integration branch. They are procedural (skill-level STOP/park decisions), not mechanical hooks: deciding "is this a new UI element / a contradictory design / a destructive op" means reading a diff or a recorded design, which a path-pattern `PreToolUse` hook cannot do.

| Layer | When | Catches | Mechanism |
|---|---|---|---|
| 0 - Proactive triage | Before any build: batched at `solve-milestone` start, single-issue at `solve-issue` start | Design contradictions, silent UX gaps, missing criteria, dependency ordering | `triage` skill plus `triage-reviewer` (architect lens) plus `design-reviewer` (front-end lens, UI issues only) |
| 1 - Implementer declaration | After the implementer returns | `NEW_UI_ELEMENTS` / `DESTRUCTIVE_OPS` the implementer discovers mid-build | Implementer report fields the orchestrator gates on |
| 2 - Visual-review gate | Post-build, pre-merge | Rendered defects that unit/E2E pass: misalignment, wrong default state, a flat list that should be grouped | UI issues leave the PR open for your visual sign-off (no auto-merge); light plus dark screenshots are attached when a render capability is configured, otherwise a PR-open-for-human-test note. Never fails, never auto-merges a UI issue |

Triage front-loads most gaps into one consolidated up-front review and emits a dependency graph that drives the build loop; the implementer declaration backstops what triage couldn't foresee; the visual gate catches what only renders on-device. The mechanical gates below enforce how work is done; these three layers gate whether the design is sound enough to build and ship.

### Park, don't prompt

This is an autonomous runtime: a blocker never means "stop and wait for a human." It means park the issue and keep going: post a comment saying what's needed, apply a label, leave the issue and its branch open, and continue the loop with independent, clean issues. The human is engaged asynchronously, by reviewing the comment plus label after the run, not by an interactive mid-run prompt. Only a systemic failure (auth, a broken integration branch, missing tooling) ends the run early. (A standalone interactive `solve-issue` still parks durably; it may additionally narrate to the watching operator.)

### Label taxonomy

A park applies a comment plus a label, so you can triage a finished run by label. `setup` provisions these create-if-missing in the target repo:

| Label | Meaning |
|---|---|
| `in progress` | Branch open with partial / parked work |
| `blocked` | Held by an unmerged dependency, or an E2E-unverified park |
| `needs design` | Design direction required before building (insufficient / contradictory design; silent-criteria new UI) |
| `needs decision` | Non-design human decision required (new dependency; destructive-op confirm UX; architecture call) |
| `needs review` | Built; UI PR open awaiting your visual sign-off (incl. the no-render path) |
| `judgment call` | A borderline autonomous call worth a post-run audit |

A parked issue carries exactly one blocker label (`blocked` / `needs design` / `needs decision`), plus `in progress` if a branch exists; `needs review` and `judgment call` are orthogonal.

## The mechanical gates

| Gate | Mechanism |
|---|---|
| force-subagent | Plugin `PreToolUse` (`Write`/`Edit`/`MultiEdit`/`NotebookEdit`): denies edits to `sourceGlobs` from the main thread (no subagent context); only the dispatched subagent may author app/test code. Docs, plans, and `.claude/**` stay editable by the orchestrator. |
| tests-green | Plugin `PreToolUse` (`Bash(git commit *)`): runs `unitTestCmd` when staged files touch `sourceGlobs`; blocks the commit on red. |
| no-push | Plugin `PreToolUse` (`Bash(git push *)`): rejects pushes to `protectedBranch`. GitHub branch protection is the server-side backstop. |
| no-pr-to-protected | Plugin `PreToolUse` (`Bash(gh pr create *)`): blocks `gh pr create --base <protectedBranch>`. |

Each hook honors a `CLAUDE_HOOK_DISABLE_*` escape hatch.

## Preflight (optional)

An optional, consumer-named `preflightCmd` runs your repo's fast pre-PR checks (lint / format / static analysis / security scan) locally during a run. CI stays the authority: your CI runs these on the PR regardless, so preflight catches nothing CI would miss. Its only value is moving a red result earlier, before the PR, so a lint/static/security failure is caught and fixed up front instead of turning the PR red and costing a fix, push, wait round trip.

Where it slots: the concluding action of `solve-issue` step 6.1, after the `/code-review` resolve loop converges, and before the version bump and commit. It behaves like the unit gate (step 4): a non-zero exit re-dispatches the implementer with the failing command plus output (its own "at most 2" cap), and a non-converging gate parks the issue `blocked`. When `preflightCmd` is absent the gate is skipped cleanly.

**CI-derived mode (`preflightCmd: "github-ci"`).** Instead of a literal command, the reserved sentinel `"github-ci"` auto-derives the preflight checks from the repo's GitHub Actions CI, so a cheap CI check (the motivating case: `npm audit --omit=dev --audit-level=high`) is front-run locally before the PR rather than hand-transcribed — and never drifts out of sync with CI. A behavior-identical script pair `scripts/ci-preflight-steps.{sh,ps1}` parses the local `.github/workflows/*.yml` with a constrained, line-oriented parser over the narrow surface only (`run:` + `working-directory` / `if` / `uses` / `continue-on-error` + the workflow `on:` trigger) — no YAML library and **no new tool dependency**, and it never calls the network. It emits each PR-gating workflow's `run:` steps in declaration order; step 6.1 runs them through the existing tool-presence-guard → run → re-dispatch (cap 2) → park machinery. Skip-rules drop what can't run locally (`uses:` steps, secrets / services / deploy, `${{ }}`-interpolated `run:`, step-level `if:`), `working-directory` is honored, and `continue-on-error` steps never count as a real failure. Two guardrails make the coverage honest: **loud coverage logging** ("mirrored N checks, skipped M (reasons)") on every run, and a **silent-under-run guard** — a PR-gating workflow that produces zero runnable steps (its real checks hidden behind a `uses:` reusable/composite workflow) is a **visible warning, not a clean pass**, so the gate cannot quietly recreate the very gap it closes.

**Documented limitations (deliberately not built — CI remains the authority).** The CI-derived mode does not recurse into `uses:` reusable/composite workflows (it warns instead), does not expand `matrix`, does not replicate the CI runner (`act`-in-Docker is a possible future opt-in), and supports GitHub Actions only. Residual false-failure classes — network-dependent audits, local-vs-CI version skew, missing lockfile / `node_modules` state — are accepted because a park is recoverable: a false park costs a human glance, never a bad merge.

**Known limitation under `--parallel`.** There is no per-step static-vs-port-binding classification — that is deferred, not implemented. Consequently, under `--parallel` a CI-derived **server-starting** gating step (one that binds a port / starts a long-running server) would run inside **every** worker concurrently and contend for the same port. The mode does not detect or isolate this. Scope it out with the `ciWorkflow` override (narrow to a workflow with no server-starting gating step), or avoid `preflightCmd: "github-ci"` together with `--parallel` when CI's PR-gating steps start a server. This is not handled automatically.

Also accepted: both impls honor `continue-on-error` only at **step** scope — a **job-level** `continue-on-error: true` is not modeled, so a failing step in such a job would park on a real failure rather than being treated as tolerated. Job-scope handling is deferred.

This is a procedural (skill-level) gate, not a mechanical `PreToolUse` hook. It is not one of the four hooks in [The mechanical gates](#the-mechanical-gates). See [`profile-schema.md`](profile-schema.md) for the `preflightCmd` and `ciWorkflow` keys.

## The skills

- `/milestone-driver:solve-milestone <name>`: triages the whole milestone for design gaps plus dependency order (Phase 0), then iterates the buildable issues by the validated dependency graph, running `/milestone-driver:solve-issue` on each; auto-merges logic-only issues to the integration branch on green (UI issues open a PR for your visual sign-off), and re-syncs before the next dependent issue. Runs unattended; parks blocked/gapped issues and continues with clean ones. Only a systemic failure ends the run early.
- `/milestone-driver:solve-issue <n>`: the rigid, gated per-issue procedure the orchestrator runs (never authoring code itself): single-issue triage, root-cause-or-park, implementer dispatch, unit plus E2E gates, code review, PR, and auto-merge (or the visual-review hold for UI issues). Orchestrates the `superpowers:*` skills as its inner loop rather than reimplementing discipline.
- `/milestone-driver:triage <milestone | issue>`: the standalone Layer-0 review phase: emits an all-clear or a gap table and posts a blocker summary on each affected issue, without building anything. Invoked automatically by the two skills above; runnable on its own to pre-flight a milestone.

## Parallel mode (optional)

By default the milestone loop is sequential: it builds one issue at a time in dependency order, single working tree, no worktrees. Version 1.5.0 adds an opt-in `--parallel` mode that builds the mutually-independent issues within a single Wave concurrently, each in its own git worktree, then integrates them through one orchestrator-owned serial verified merge tail. The default stays sequential; parallel mode is purely additive.

Parallel mode is not a CLI flag the engine parses. Claude Code does no argument parsing, so the mode is recognized when the invocation contains either a `--parallel` token or the natural-language phrase "in parallel". Absent either signal, the sequential path runs unchanged.

### Wave-by-Wave model

Parallel mode reuses the same Phase 0 triage and the same Wave-ordered dependency graph the sequential loop uses, and it processes the milestone Wave by Wave. Each Wave runs to completion before the next Wave begins, so a dependent Wave still builds on the prior Wave's integrated result. Per Wave:

1. Compute the parallelizable set. From the current Wave, an issue is in the set if it is buildable this pass (its dependencies are merged to the integration branch, it carries no live blocker label, and triage found no spec gap) and it is mutually independent of the other issues in the set. In short, the set is buildable and mutually-independent. Within a Wave the issues are already mutually independent by triage's construction, so the independence check is a guard; its real job is the shared-file-but-not-a-build-dependency case (two same-Wave issues whose files overlap but which carry no dependency edge), which the merge tail reconciles later.
2. Dispatch concurrently in a worktree fleet. The orchestrator owns worktree creation: it creates one git worktree per set issue (under the gitignored scratch dir `.milestone-config/worktrees/`) and dispatches one `solve-issue --worker` subagent into each. The worker runs inside the provided worktree and never cuts its own branch. Dispatch is capped at 4 concurrent workers (a conservative default, not a profile key); a larger set uses a rolling window so the in-flight count never exceeds 4.
3. Barrier on the whole set. The Wave does not advance and integration does not begin until every dispatched worker hands back. A worker returns either built-green (branch built, verified, pushed) or parked (the worker handled the park itself, with branch plus label plus comment intact, and is simply excluded from integration).

Worker mode is today's `solve-issue` pipeline with three deltas: it runs in the orchestrator-provided worktree, it builds but does not auto-merge (it returns the branch instead), and it returns a structured handback. Everything else (triage, the root-cause gate, the implementer dispatch, the unit gate, `/code-review`, the version bump, park-don't-prompt, the audit trail, and the at-most-2 re-dispatch cap on every gate) carries over verbatim.

### Serial verified merge tail

Phase 1 builds but does not integrate. Phase 2, the serial verified merge tail, integrates the barriered built-green branches one at a time, in ascending-issue order, on the main working tree. It is force-free by default (merge-in, no history rewrite). For each branch the orchestrator merges the integration target into the worker branch as an ordinary merge commit (a fast-forwardable push, no `--force`), re-verifies against accumulated state (the unit suite if defined, plus the worker-deferred E2E and any server-starting preflight gates, run once here against the integrated result where they are more meaningful), and on green squash-merges the PR. The squash collapses the merge-in commit so the integration target's history stays linear. The integration target advances after each merge, so two same-Wave siblings that touch overlapping files are re-verified against each other, restoring the "every increment tested against accumulated state" guarantee that naive concurrent merging throws away.

Merge-in is the default rather than rebase plus force because a history-rewriting push is fragile across consumer safety setups: a consumer destructive-command hook and the runtime's destructive-action classifier can both block even the safe `--force-with-lease`, and a `no-push` hook permitting the push is necessary but not sufficient when those other guards stand. Merge-in gives the identical re-verify guarantee with no history rewrite. The rebase plus `--force-with-lease` variant stays available, but it must be allow-listed in the consumer's hooks and destructive-action classifier first.

UI issues are not merged by the tail. They are held open with the `needs review` label for human visual sign-off (the Layer-2 visual gate, unchanged). The tail integrates only the non-UI built-green branches.

### Bounded auto-resolve conflict policy

When a merge-in conflicts, the tail applies bounded auto-resolve. Git's `ort` merge strategy already auto-resolves non-overlapping edits to the same file (for example, two siblings each appending a distinct route to the same routes file), and the tail re-verifies the result. A resolvable and green merge proceeds. A non-trivial or ambiguous conflict, or a red re-verify, is not auto-accepted: the tail runs `git merge --abort`, parks the issue `blocked` (comment plus label plus preserved branch), and continues with the next branch. A clean merge that re-verifies red is parked the same way, because the combination is broken and a human decides. The final summary lists every auto-resolved-conflict issue so a human can sanity-check the reconciliation.

### Hooks inside a worktree

The four mechanical gates behave correctly inside a worktree with no worktree-specific configuration:

| Gate | Behavior in a worktree |
|---|---|
| force-subagent | A worker is a dispatched subagent, so its edits are already allowed. The profile is a committed file present in every worktree, and the hook resolves it relative to the working directory, so it fires identically per-worktree. |
| tests-green | The `.milestone-config/tests-stamp` is keyed `branch:treeSHA`, so a per-worktree stamp is correct, not a collision. Each worktree's branch and tree get their own key. |
| no-push | Unaffected. It guards only `protectedBranch`; feature-branch pushes from a worktree are allowed. |
| no-pr-to-protected | Unaffected. The worker opens PRs with `--base <integrationBranch>`, so they pass. |
| **Shared external services (test DB, caches, fixed ports)** | A worktree isolates the **filesystem**, not external services. Under `--parallel`, all N concurrent `unitTestCmd` runs share external services (notably `DATABASE_URL` / the test DB) unless the consumer's harness provides per-worker isolation (e.g. `parallel_tests` / `TEST_ENV_NUMBER` DB-suffix pattern, or per-worker `DATABASE_URL`). This is a **consumer responsibility** — `--parallel` does not inject DB isolation. See [consumer setup — DB isolation under `--parallel`](consumer-setup.md#db-isolation-under---parallel-consumer-responsibility). |

One per-clone marker becomes per-worktree: the `.milestone-config/preflight-notice` one-time notice marker is per-clone, so inside a worktree it becomes per-worktree (the notice could print once per worktree). This is acceptable, and the worktree setup can `touch` the marker to suppress it.

### Blast radius is unchanged

Parallel mode adds concurrency and a worktree fleet; it does not widen the blast radius. As in sequential mode, the workers and the serial tail merge only to the integration branch, never to the protected branch. Release (integration branch to protected branch), closing the GitHub milestone object, and deploy stay manual and human-only — the driver closes the milestone's issues and authors the CHANGELOG, but never closes the milestone itself.

## Integration granularity (issue vs wave)

`integrationGranularity` is a profile key, `"issue"` or `"wave"`, default `"issue"`. It controls how built issues integrate, and it is orthogonal to `--parallel` (which controls how issues build). The two combine or apply independently: any of sequential or parallel, crossed with issue or wave granularity, is valid.

`"issue"` (the default) is today's model, unchanged. Each built issue opens its own PR, gets its own CI run, and merges individually. In sequential mode each issue's `solve-issue` opens and merges its own PR; in parallel mode the serial verified merge tail merges each built-green PR in turn.

`"wave"` integrates a whole Wave on one branch. The merge-tail mechanism is unchanged (merge-in plus re-verify against accumulated state plus bounded auto-resolve); only the target and the PR-opening differ:

- The worker opens no per-issue PR. It builds, verifies, commits, and pushes its branch, then hands the branch back.
- The orchestrator integrates the Wave's built-green logic branches into a wave branch `wave/<milestone>-w<N>` (N is the Wave number), applying the same merge-tail policy with the wave branch as the integration target, so siblings are re-verified against each other exactly as in the per-issue tail.
- The orchestrator opens one wave PR to the integration branch and squash-merges it on CI green. Auto-merge-on-green moves from per-issue to per-wave: the whole assembled Wave merges on one green CI run.
- After the squash-merge the orchestrator explicitly closes the Wave's logic issues with `gh issue close`. A GitHub `Closes #n` keyword auto-closes an issue only when the PR merges into the repository's default branch; the wave PR targets the integration branch, which is typically not the default branch, so the keyword would not fire. The explicit close is the reliable mechanism.

The logic-only carve-out: the visual-review gate is per-UI-issue, so a single wave PR cannot both auto-merge (logic) and hold open (UI). A Wave containing UI issues keeps those per-issue and held, each opening its own `needs review` PR for human visual sign-off, and only the logic issues join the wave branch.

The trade-off: wave granularity costs O(waves) CI runs instead of O(issues), and CI validates the assembled Wave, catching integration-level issues an isolated per-issue build misses. But one red wave-PR CI blocks the whole Wave. That is acceptable because the strong local gates (unit plus static preflight plus `/code-review` plus the tail's re-verify) catch most failures before CI, so CI is the backstop. It is not for repos with weak local gates. As with parallel mode, the wave PR targets the integration branch, never the protected branch.

## Output style

The skills and agents follow a concise, tabular output norm: status and outcomes are stated flatly, steps / gates / lists / options are presented as tables rather than inline prose, and any item that needs a human is marked with 🔴.

---

For the product overview and quickstart, see the [README](../README.md). For the full profile reference, see [`profile-schema.md`](profile-schema.md); the three required keys are `integrationBranch`, `protectedBranch`, and `sourceGlobs`.
