# milestone-driver

> **Status: pre-1.0.** The generic engine — the skills, the bundled agents, and all mechanical-gate hooks — is built and verified. First-consumer wiring and the end-to-end dry-run are in progress; see [Build status](#build-status).

Milestone Driver turns a GitHub milestone into the unit of work. You hand it a milestone; it **triages every issue for design gaps and dependency order before any code is written**, then iterates the buildable issues in dependency order, and for each: identifies the root cause (or **parks the issue with a comment + label** if it can't), dispatches a TDD implementer subagent, runs your unit + E2E suites, requests a code review, opens a PR, and auto-merges to your integration branch once CI is green — **except UI issues, which open a PR for your visual sign-off** (with light + dark screenshots when a render capability is configured). It never touches your default/release branch — that stays your call, behind your manual deploy.

Discipline is enforced mechanically, not by trust: plugin `PreToolUse` hooks block commits on red tests and pushes to protected branches, and keep all source edits flowing through subagents (the main thread only orchestrates). Every consequential decision is written to the PR as a Decision Log and borderline calls are labeled, so you can audit a whole unattended run after the fact. Autonomy is bounded — architecture is locked at plan-approval time, and a blocker (a design gap, a one-way-door decision, an unmet gate) **parks the issue — a comment + a label + the open branch — and the loop continues with clean work** rather than drifting or stalling. Only a systemic failure (auth, a broken integration branch, missing tooling) halts the run.

Bring your own stack via a small config profile (test commands, branch names, source globs, domain skills). Reuses the superpowers skill set for the per-issue inner loop. Cross-platform hooks (bash-first, pwsh-fallback).

## What makes it different

Unlike issue-to-PR assistants (Copilot coding agent, Sweep, claude-code-action) or single-task agents, it operates at the milestone level and enforces its workflow with local mechanical gates — while keeping every merge bounded to an integration branch you control.

## Architecture

A generic engine ships in the plugin; each repo supplies a thin profile.

### Plugin contents (generic)

| Component | Path | Purpose |
|---|---|---|
| Driver skill | `skills/solve-milestone/SKILL.md` | The autonomous milestone loop (triage Phase 0, then the dependency-graph build loop) |
| Per-issue skill | `skills/solve-issue/SKILL.md` | The gated per-issue procedure |
| Triage skill | `skills/triage/SKILL.md` | The Layer-0 pre-build review phase — design gaps + dependency ordering (read-only; authors nothing) |
| Setup skill | `skills/setup/SKILL.md` | Profile bootstrap + create-if-missing provisioning of the label taxonomy |
| Implementer agent | `agents/implementer.md` | Self-contained TDD implementer subagent (a project may override via its profile) |
| Triage-reviewer agent | `agents/triage-reviewer.md` | Architect-lens reviewer — design consistency / buildability / completeness + dependency edges (read-only; profile-overridable) |
| Design-reviewer agent | `agents/design-reviewer.md` | Front-end-lens reviewer — UX gaps on UI-touching issues (read-only; profile-overridable) |
| Hooks | `hooks/` | All four gates are `PreToolUse` hooks invoked via `hooks/run-hook.cmd` (bash-first, pwsh-fallback, fail-open): `force-subagent`, `tests-green`, `no-push`, `no-pr-to-protected`. The triage / declaration / visual layers are **procedural** (skill-level), not hooks — see [The layered gating model](#the-layered-gating-model). |
| Manifest + registration | `.claude-plugin/plugin.json`, `hooks/hooks.json` | Plugin metadata and Claude-side hook registration |

**Plugin version** lives in `.claude-plugin/plugin.json` as the single source of truth — `marketplace.json` carries no `version` field (Claude Code resolves `plugin.json` first; setting both silently masks the marketplace value). The bump rides in the issue or milestone PR itself, not a separate chore: standalone `/milestone-driver:solve-issue` runs apply a patch bump and confirm; `/milestone-driver:solve-milestone` derives the target version from the milestone name and passes it to each issue run idempotently.

### Project profile (per-repo, committed `milestone-driver.json`)

| Key | Meaning | Required? |
|---|---|:---:|
| `integrationBranch` | Branch the loop merges into (e.g. `dev`) | ✅ |
| `protectedBranch` | Branch the loop must never push/PR to (e.g. `master`) | ✅ |
| `sourceGlobs` | Globs the `force-subagent` gate guards | ✅ |
| `implementerAgent` | Implementer subagent (defaults to the bundled one) | default-filled |
| `triageAgent` | Architect-lens triage reviewer (defaults to the bundled `triage-reviewer`) | default-filled |
| `designReviewAgent` | Front-end-lens design reviewer (defaults to the bundled `design-reviewer`) | default-filled |
| `unitTestCmd` | Command the `tests-green` gate runs | — |
| `e2eTestCmd` | E2E runner for the pre-merge gate (Appium, Selenium, Playwright, …) | — |
| `e2eEnv` | E2E environment config (e.g. endpoint/device) | — |
| `uiSurfaceGlobs` | Globs marking UI surfaces — drive design-lens triage and the visual-review gate; absent → neither runs | — |
| `domainSkills` | Domain skills the implementer consults for citations | — |
| `nonNegotiables` | Stack constraints recorded for the implementer | — |

Full schema: [`docs/profile-schema.md`](docs/profile-schema.md).

## The layered gating model

Three defense-in-depth layers catch **design gaps** — underspecified or self-contradictory acceptance criteria, silent UX gaps, rendered defects — *before* they reach your integration branch. They are **procedural** (skill-level STOP/park decisions), not mechanical hooks: deciding "is this a new UI element / a contradictory design / a destructive op" means reading a diff or a recorded design, which a path-pattern `PreToolUse` hook cannot do.

| Layer | When | Catches | Mechanism |
|---|---|---|---|
| **0 — Proactive triage** | Before any build — batched at `solve-milestone` start, single-issue at `solve-issue` start | Design contradictions, silent UX gaps, missing criteria, **dependency ordering** | `triage` skill + `triage-reviewer` (architect lens) + `design-reviewer` (front-end lens, UI issues only) |
| **1 — Implementer declaration** | After the implementer returns | `NEW_UI_ELEMENTS` / `DESTRUCTIVE_OPS` the implementer discovers mid-build | Implementer report fields the orchestrator gates on |
| **2 — Visual-review gate** | Post-build, pre-merge | Rendered defects that unit/E2E pass: misalignment, wrong default state, a flat list that should be grouped | UI issues leave the PR **open** for your visual sign-off (no auto-merge); light + dark screenshots are attached when a render capability is configured, otherwise a PR-open-for-human-test note — never fails, never auto-merges a UI issue |

Triage front-loads most gaps into one consolidated up-front review and emits a **dependency graph** that drives the build loop; the implementer declaration backstops what triage couldn't foresee; the visual gate catches what only renders on-device. The mechanical gates below enforce *how* work is done; these three layers gate *whether the design is sound enough to build and ship*.

### Park, don't prompt

This is an **autonomous** runtime: a blocker never means "stop and wait for a human." It means **park the issue and keep going** — post a comment saying what's needed, apply a label, leave the issue and its branch open, and continue the loop with independent, clean issues. The human is engaged **asynchronously** — by reviewing the comment + label after the run — not by an interactive mid-run prompt. Only a systemic failure (auth, a broken integration branch, missing tooling) ends the run early. (A standalone interactive `solve-issue` still parks durably; it may additionally narrate to the watching operator.)

### Label taxonomy

A park applies a comment **plus** a label, so you can triage a finished run by label. `setup` provisions these create-if-missing in the target repo:

| Label | Meaning |
|---|---|
| `in progress` | Branch open with partial / parked work |
| `blocked` | Held by an unmerged dependency, or an E2E-unverified park |
| `needs design` | Design direction required before building (insufficient / contradictory design; silent-criteria new UI) |
| `needs decision` | Non-design human decision required (new dependency; destructive-op confirm UX; architecture call) |
| `needs review` | Built; UI PR open awaiting your visual sign-off (incl. the no-render path) |
| `judgment call` | A borderline autonomous call worth a post-run audit |

A parked issue carries exactly one *blocker* label (`blocked` / `needs design` / `needs decision`), plus `in progress` if a branch exists; `needs review` and `judgment call` are orthogonal.

## The mechanical gates

| Gate | Mechanism |
|---|---|
| **force-subagent** | Plugin `PreToolUse` (`Write`/`Edit`/`MultiEdit`/`NotebookEdit`) — denies edits to `sourceGlobs` from the **main thread** (no subagent context); only the dispatched subagent may author app/test code. Docs, plans, and `.claude/**` stay editable by the orchestrator. |
| **tests-green** | Plugin `PreToolUse` (`Bash(git commit *)`) — runs `unitTestCmd` when staged files touch `sourceGlobs`; blocks the commit on red. |
| **no-push** | Plugin `PreToolUse` (`Bash(git push *)`) — rejects pushes to `protectedBranch`. GitHub branch protection is the server-side backstop. |
| **no-pr-to-protected** | Plugin `PreToolUse` (`Bash(gh pr create *)`) — blocks `gh pr create --base <protectedBranch>`. |

Each hook honors a `CLAUDE_HOOK_DISABLE_*` escape hatch.

## The skills

- **`/milestone-driver:solve-milestone <name>`** — triages the whole milestone for design gaps + dependency order (Phase 0), then iterates the buildable issues by the validated dependency graph, running `/milestone-driver:solve-issue` on each; auto-merges logic-only issues to the integration branch on green (UI issues open a PR for your visual sign-off), and re-syncs before the next dependent issue. Runs unattended; **parks** blocked/gapped issues and continues with clean ones — only a systemic failure ends the run early.
- **`/milestone-driver:solve-issue <n>`** — the rigid, gated per-issue procedure the orchestrator runs (never authoring code itself): single-issue triage, root-cause-or-park, implementer dispatch, unit + E2E gates, code review, PR, and auto-merge (or the visual-review hold for UI issues). Orchestrates the `superpowers:*` skills as its inner loop rather than reimplementing discipline.
- **`/milestone-driver:triage <milestone | issue>`** — the standalone Layer-0 review phase: emits an all-clear or a gap table and posts a blocker summary on each affected issue, without building anything. Invoked automatically by the two skills above; runnable on its own to pre-flight a milestone.

## Requirements

milestone-driver orchestrates existing tooling rather than reimplementing it:

- **The `superpowers` plugin — required.** The per-issue inner loop is built on `superpowers:*` skills (`systematic-debugging`, `subagent-driven-development`, `test-driven-development`, `verification-before-completion`, `requesting-code-review`, `finishing-a-development-branch`). It is declared in `plugin.json`'s `dependencies`, qualified to the `claude-plugins-official` marketplace, and this marketplace allowlists that source via `allowCrossMarketplaceDependenciesOn` — so Claude Code auto-installs `superpowers` on install, provided you have the official marketplace added.
- **GitHub CLI (`gh`)**, authenticated — issue, PR, and milestone operations.
- **git**, with the consuming repo using a gitflow-style integration branch.
- **bash (preferred) or PowerShell 7+ (`pwsh`)** for the hooks; `jq` is required for the bash path.

## Build status

1. **Scaffold** — manifest + directory layout ✓
2. **Generic engine** — the driver / per-issue / triage / setup skills, the implementer + triage-reviewer + design-reviewer agents, the four gate hooks, `hooks.json`, and the profile-schema doc ✓ (verified)
3. **First consumer** — profile + CLAUDE.md wiring in the first consuming repo *(in progress)*
4. **End-to-end dry-run** of `/milestone-driver:solve-issue`, then a full milestone via `/milestone-driver:solve-milestone` *(pending)*

## Topics

`claude-code` · `claude-code-plugin` · `ai-agents` · `autonomous-agents` · `agentic` · `github-milestones` · `github-issues` · `tdd` · `code-review` · `git-hooks` · `pull-requests` · `developer-tools`

## Installation

```
/plugin marketplace add kenmulford/milestone-driver
/plugin install milestone-driver@milestone-driver
```

This pulls in the required `superpowers` dependency (allowlisted from the official marketplace). **Restart Claude Code** after install — and after any hook change — so the plugin hooks load. See [`docs/consumer-setup.md`](docs/consumer-setup.md) for the full setup flow.

> Until v1 is released to `main`, add the marketplace from the `develop` branch; the default-branch form above works once `develop` → `main` is merged.

## License

[MIT](LICENSE) (provisional — finalized at publishing time).
