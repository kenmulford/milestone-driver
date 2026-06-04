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

Plugin version lives in `.claude-plugin/plugin.json` as the single source of truth. `marketplace.json` carries no `version` field (Claude Code resolves `plugin.json` first; setting both silently masks the marketplace value). The bump rides in the issue or milestone PR itself, not a separate chore: standalone `/milestone-driver:solve-issue` runs apply a patch bump and confirm; `/milestone-driver:solve-milestone` derives the target version from the milestone name and passes it to each issue run idempotently. Set `versioning: false` to opt out, which is version-free mode: no semver parse, no prompt, no bump (for repos that keep their version elsewhere, like a `.csproj`). Fail-safe: a versioned repo whose `.claude-plugin/plugin.json` is missing degrades to version-free with a logged note rather than failing the run.

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

This is a procedural (skill-level) gate, not a mechanical `PreToolUse` hook. It is not one of the four hooks in [The mechanical gates](#the-mechanical-gates). See [`profile-schema.md`](profile-schema.md) for the `preflightCmd` key.

## The skills

- `/milestone-driver:solve-milestone <name>`: triages the whole milestone for design gaps plus dependency order (Phase 0), then iterates the buildable issues by the validated dependency graph, running `/milestone-driver:solve-issue` on each; auto-merges logic-only issues to the integration branch on green (UI issues open a PR for your visual sign-off), and re-syncs before the next dependent issue. Runs unattended; parks blocked/gapped issues and continues with clean ones. Only a systemic failure ends the run early.
- `/milestone-driver:solve-issue <n>`: the rigid, gated per-issue procedure the orchestrator runs (never authoring code itself): single-issue triage, root-cause-or-park, implementer dispatch, unit plus E2E gates, code review, PR, and auto-merge (or the visual-review hold for UI issues). Orchestrates the `superpowers:*` skills as its inner loop rather than reimplementing discipline.
- `/milestone-driver:triage <milestone | issue>`: the standalone Layer-0 review phase: emits an all-clear or a gap table and posts a blocker summary on each affected issue, without building anything. Invoked automatically by the two skills above; runnable on its own to pre-flight a milestone.

## Output style

The skills and agents follow a concise, tabular output norm: status and outcomes are stated flatly, steps / gates / lists / options are presented as tables rather than inline prose, and any item that needs a human is marked with 🔴.

---

For the product overview and quickstart, see the [README](../README.md). For the full profile reference, see [`profile-schema.md`](profile-schema.md); the three required keys are `integrationBranch`, `protectedBranch`, and `sourceGlobs`.
