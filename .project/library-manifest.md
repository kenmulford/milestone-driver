# Library manifest

<!--
Project doc (.project/). Cite as `.project/library-manifest.md#<section>`. The
implementer's "new dependency = PAUSE" gate reads this; the coherence-reviewer
flags a new library that duplicates one listed here. Keep it current. Keep ##
headings stable — they are citation anchors.

Captured by milestone-bootstrapper (dogfood #235), grounded in this repo's own docs.
-->

## Runtime & frameworks
The platform/runtime and primary frameworks, with versions. (Mirror these into milestone-driver `nonNegotiables` where they're hard constraints.)
> This is a **Claude Code plugin**, not an application — there is no app language or package manager (no `package.json`, `*.csproj`, or `pyproject.toml`). The "runtime" is the plugin substrate: **markdown skills** (`skills/<verb>/SKILL.md`) + **markdown agents** (`agents/*.md`) + **cross-platform hooks** (bash-first, PowerShell 7+ fallback). The hard constraints are recorded in `.milestone-config/driver.json#nonNegotiables`: "Claude Code plugin: markdown skills + bash-first/pwsh-fallback hooks" and "Cross-platform: bash (jq) and PowerShell 7+". Plugin version is the single source of truth in `.claude-plugin/plugin.json` (`docs/architecture.md#plugin-version`).

## Approved libraries (by purpose)
One approved choice per purpose, so a redundant alternative is easy to spot.

| Purpose | Library | Notes |
|---|---|---|
| GitHub operations (issues, PRs, milestones) | `gh` CLI (authenticated) | The only way the engine talks to GitHub (`README.md#requirements`). |
| Version control / branch flow | `git` (gitflow-style integration branch) | `README.md#requirements`. |
| Hook + script shell (primary) | `bash` + `jq` | `jq` required for the bash path (`README.md#requirements`). |
| Hook + script shell (fallback) | PowerShell 7+ (`pwsh`) | Behavior-identical twin of every `.sh` (`hooks/run-hook.cmd` polyglot launcher). |
| Per-issue inner loop | the **superpowers** plugin | Required dependency, auto-installed on install (`.claude-plugin/plugin.json` dependencies; `README.md#requirements`). |
| Render-daemon test stub (CI only) | `python3` http server | Used only by the render-daemon test fixtures in CI (`.github/workflows/ci.yml`). |

## Adding a dependency (the gate)
A new dependency is a PAUSE, not an autonomous call. Record what it buys, its license / OSS status, and why nothing approved suffices; a human approves before it's added.
> A new dependency is a **STOP-and-ask**, parked with the `needs decision` label — the implementer halts and surfaces it rather than adding it autonomously (`docs/architecture.md#label-taxonomy`; the implementer subagent's new-dependency PAUSE gate). For this plugin the bar is especially high: a core non-negotiable is "**no new tool dependency**" — e.g. the CI-preflight parser deliberately uses a line-oriented parser over the narrow YAML surface rather than pulling in a YAML library (`docs/architecture.md#preflight-optional`, "no YAML library and **no new tool dependency**").

## Avoid / banned
Libraries explicitly not to use, and why.
> No YAML library (the CI-preflight parser stays dependency-free — `docs/architecture.md#preflight-optional`). Nothing that breaks the **cross-platform bash + PowerShell 7+** twin requirement or the **BOM-free UTF-8 / LF** convention (`.milestone-config/driver.json#nonNegotiables`; the `no-bom` hook). Nothing that assumes a single OS — every shell artifact must ship as a bash + pwsh pair.
