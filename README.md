# milestone-driver

> **Status: in development (scaffold).** The manifest and directory layout exist; skills, the implementer agent, and the mechanical-gate hooks are not yet implemented. See the [build plan](#build-status) for the roadmap.

A distributable **Claude Code plugin** that takes a **GitHub milestone** and autonomously iterates its issues. For each issue it: fetches and reads it → finds the root cause (or **stops** and comments) → dispatches a TDD implementer subagent → runs the unit suite → runs targeted UI (Appium) tests → runs `/code-review` → opens a PR → **auto-merges to the integration branch on CI green** → closes the issue.

The discipline is **mechanical, not advisory.** Three hooks (a `PreToolUse` hook plus native git `pre-commit`/`pre-push` hooks) make the load-bearing rules un-bypassable, so the methodology can't be routed around under execution momentum.

The engine is **stack-agnostic.** Each consuming repo supplies a thin, committed profile at `.claude/milestone-driver.json`.

## Why it exists

Advisory guidance (CLAUDE.md, memories, output styles) gets routed around under execution momentum. `milestone-driver` moves the load-bearing rules from *advisory* to *mechanical* (git hooks + a Claude `PreToolUse` hook) and encodes the methodology as a rigid, gated skill that the main thread runs **as an orchestrator — never as an author**. The goal: complete a whole milestone autonomously, without drift, with high accuracy, and with a post-run audit trail so every judgment call is visible.

## Architecture

A generic engine ships in the plugin; each repo supplies a thin profile.

### Plugin contents (generic)

| Component | Path | Purpose |
|---|---|---|
| Driver skill | `skills/solve-milestone/SKILL.md` | The autonomous milestone loop |
| Per-issue skill | `skills/solve-issue/SKILL.md` | The gated per-issue procedure |
| Implementer agent | `agents/implementer.md` | Self-contained TDD implementer subagent (a project may override via its profile) |
| Hooks | `hooks/` | `force-subagent` (`PreToolUse`), `tests-green` (native `pre-commit`), `no-push-to-protected` (native `pre-push`) — authored in both `.ps1` and `.sh` |
| Manifest + registration | `.claude-plugin/plugin.json`, `hooks/hooks.json` | Plugin metadata and hook registration |

### Project profile (per-repo, committed `.claude/milestone-driver.json`)

| Key | Meaning |
|---|---|
| `integrationBranch` | Branch the loop merges into (e.g. `dev`) |
| `protectedBranch` | Branch the loop must never push/PR to (e.g. `master`) |
| `sourceGlobs` | Globs the `force-subagent` gate guards |
| `unitTestCmd` | Command the `tests-green` gate runs |
| `uiTestCmd` | Targeted UI/Appium runner |
| `implementerAgent` | Implementer subagent (defaults to the bundled one) |
| `domainSkills` | Domain skills + MCP the implementer relies on |
| `nonNegotiables` | Stack constraints recorded for the implementer |
| `appium` | Appium endpoint / device config |

Full schema documentation will live alongside the implementation.

## The mechanical gates

| Gate | Mechanism |
|---|---|
| **force-subagent** | Claude `PreToolUse` (`Edit`/`Write`) — denies edits to source/test globs from the **main thread** (where `agent_id` is absent); only the dispatched subagent may author app/test code. Docs, plans, and `.claude/**` stay editable by the orchestrator. |
| **tests-green-before-commit** | Native `.git/hooks/pre-commit` — runs `unitTestCmd` on a non-metadata diff and blocks on red. Harness-independent; guards human commits too. |
| **no-push-to-protected** | Native `.git/hooks/pre-push` rejecting pushes to `protectedBranch`, with a secondary scan of `gh pr create --base <protected>`. GitHub branch protection is the server-side backstop. |

Each hook honors a `CLAUDE_HOOK_DISABLE_*` escape hatch.

## The two skills

- **`/solve-milestone <name>`** — lists the milestone's issues, orders them by the Wave/dependency sequence recorded in the milestone description, and runs `/solve-issue` on each; auto-merges to the integration branch on green and re-syncs before the next dependent issue. Runs unattended; halts only at a STOP condition or when the milestone is done.
- **`/solve-issue <n>`** — the rigid, gated per-issue procedure the orchestrator runs (never authoring code itself). Orchestrates the `superpowers:*` skills as its inner loop rather than reimplementing discipline.

## Build status

This repository is being built in sequence:

1. **Scaffold** — manifest + directory layout *(current step)*
2. Skills (`/solve-issue`, `/solve-milestone`), the implementer agent, the three hooks (`.ps1` + `.sh`), and the profile-schema doc
3. PracticingPrayer as consumer #1 (profile + CLAUDE.md section)
4. End-to-end dry-run of `/solve-issue` before handing over a full milestone

## Installation

Not yet published. Local dev-install / marketplace instructions will be added once the plugin is functional.

## License

[MIT](LICENSE) (provisional — finalized at publishing time).
