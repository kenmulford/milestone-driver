# milestone-driver

> **Status: pre-1.0.** The generic engine — both skills, the implementer agent, and all mechanical-gate hooks — is built and verified. First-consumer wiring and the end-to-end dry-run are in progress; see [Build status](#build-status).

Milestone Driver turns a GitHub milestone into the unit of work. You hand it a milestone; it iterates the issues in dependency order, and for each: identifies the root cause (or stops and comments if it can't), dispatches a TDD implementer subagent, runs your unit + E2E suites, requests a code review, opens a PR, and auto-merges to your integration branch once CI is green — then moves to the next. It never touches your default/release branch — that stays your call, behind your manual deploy.

Discipline is enforced mechanically, not by trust: native git hooks block commits on red tests and pushes to protected branches, and a Claude Code hook keeps all source edits flowing through subagents (the main thread only orchestrates). Every consequential decision is written to the PR as a Decision Log and borderline calls are labeled, so you can audit a whole unattended run after the fact. Autonomy is bounded — architecture is locked at plan-approval time, and one-way-door decisions halt and ask rather than drift.

Bring your own stack via a small config profile (test commands, branch names, source globs, domain skills). Reuses the superpowers skill set for the per-issue inner loop. Cross-platform hooks (PowerShell + .sh).

## What makes it different

Unlike issue-to-PR assistants (Copilot coding agent, Sweep, claude-code-action) or single-task agents, it operates at the milestone level and enforces its workflow with local mechanical gates — while keeping every merge bounded to an integration branch you control.

## Architecture

A generic engine ships in the plugin; each repo supplies a thin profile.

### Plugin contents (generic)

| Component | Path | Purpose |
|---|---|---|
| Driver skill | `skills/solve-milestone/SKILL.md` | The autonomous milestone loop |
| Per-issue skill | `skills/solve-issue/SKILL.md` | The gated per-issue procedure |
| Implementer agent | `agents/implementer.md` | Self-contained TDD implementer subagent (a project may override via its profile) |
| Hooks | `hooks/` | `force-subagent` + `no-pr-to-protected` (`PreToolUse`), `tests-green` (native `pre-commit`), `no-push` (native `pre-push`) — each in `.ps1` and `.sh` |
| Manifest + registration | `.claude-plugin/plugin.json`, `hooks/hooks.json` | Plugin metadata and Claude-side hook registration |

### Project profile (per-repo, committed `.claude/milestone-driver.json`)

| Key | Meaning |
|---|---|
| `integrationBranch` | Branch the loop merges into (e.g. `dev`) |
| `protectedBranch` | Branch the loop must never push/PR to (e.g. `master`) |
| `sourceGlobs` | Globs the `force-subagent` gate guards |
| `unitTestCmd` | Command the `tests-green` gate runs |
| `e2eTestCmd` | E2E runner for the pre-merge gate (Appium, Selenium, Playwright, …) |
| `implementerAgent` | Implementer subagent (defaults to the bundled one) |
| `domainSkills` | Domain skills the implementer consults for citations |
| `nonNegotiables` | Stack constraints recorded for the implementer |
| `e2eEnv` | E2E environment config (e.g. endpoint/device) |

Full schema: [`docs/profile-schema.md`](docs/profile-schema.md).

## The mechanical gates

| Gate | Mechanism |
|---|---|
| **force-subagent** | Claude `PreToolUse` (`Write`/`Edit`/`MultiEdit`/`NotebookEdit`) — denies edits to `sourceGlobs` from the **main thread** (no subagent context); only the dispatched subagent may author app/test code. Docs, plans, and `.claude/**` stay editable by the orchestrator. |
| **tests-green** | Native `.git/hooks/pre-commit` — runs `unitTestCmd` when staged files touch `sourceGlobs`; blocks the commit on red. Harness-independent; guards human commits too. |
| **no-push / no-pr-to-protected** | Native `.git/hooks/pre-push` rejects pushes to `protectedBranch`; a Claude `PreToolUse` (`Bash`) scan blocks `gh pr create --base <protectedBranch>`. GitHub branch protection is the server-side backstop. |

Each hook honors a `CLAUDE_HOOK_DISABLE_*` escape hatch.

## The two skills

- **`/solve-milestone <name>`** — lists the milestone's issues, orders them by the Wave/dependency sequence recorded in the milestone description, and runs `/solve-issue` on each; auto-merges to the integration branch on green and re-syncs before the next dependent issue. Runs unattended; halts only at a STOP/PAUSE gate or when the milestone is done.
- **`/solve-issue <n>`** — the rigid, gated per-issue procedure the orchestrator runs (never authoring code itself). Orchestrates the `superpowers:*` skills as its inner loop rather than reimplementing discipline.

## Requirements

milestone-driver orchestrates existing tooling rather than reimplementing it:

- **The `superpowers` plugin — required.** The per-issue inner loop is built on `superpowers:*` skills (`systematic-debugging`, `subagent-driven-development`, `test-driven-development`, `verification-before-completion`, `requesting-code-review`, `finishing-a-development-branch`). It is declared in `plugin.json`'s `dependencies`, so Claude Code auto-installs it **when both plugins resolve within the same marketplace**. *Cross-marketplace note:* a bare dependency name resolves within the declaring plugin's marketplace; if milestone-driver and `superpowers` live in different marketplaces, the root marketplace must allowlist it via `allowCrossMarketplaceDependenciesOn`, or `superpowers` must be installed directly.
- **GitHub CLI (`gh`)**, authenticated — issue, PR, and milestone operations.
- **git**, with the consuming repo using a gitflow-style integration branch.
- **PowerShell 7+ (`pwsh`)** for the Claude-side hooks as registered in `hooks/hooks.json` — **or** `bash` + `jq`, if you repoint the hook commands at the matching `hooks/*.sh`.

## Build status

1. **Scaffold** — manifest + directory layout ✓
2. **Generic engine** — both skills, the implementer agent, the four gate hooks (`.ps1` + `.sh`), `hooks.json`, and the profile-schema doc ✓ (verified)
3. **First consumer** — profile + native-hook install + CLAUDE.md wiring in the first consuming repo *(in progress)*
4. **End-to-end dry-run** of `/solve-issue`, then a full milestone via `/solve-milestone` *(pending)*

## Topics

`claude-code` · `claude-code-plugin` · `ai-agents` · `autonomous-agents` · `agentic` · `github-milestones` · `github-issues` · `tdd` · `code-review` · `git-hooks` · `pull-requests` · `developer-tools`

## Installation

Published at [github.com/kenmulford/milestone-driver](https://github.com/kenmulford/milestone-driver). Local dev-install (e.g. `claude --plugin-dir`) for now; marketplace distribution is planned. After installing the plugin or changing any hook, **restart Claude Code** so the hooks load. Native git hooks (`tests-green`, `no-push`) are wired into each consuming repo's `.git/hooks` during consumer setup.

## License

[MIT](LICENSE) (provisional — finalized at publishing time).
