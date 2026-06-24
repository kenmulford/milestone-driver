# Conventions

<!--
Project doc (.project/). Cite as `.project/conventions.md#<section>`. This is the file the
implementer and coherence-reviewer lean on hardest — "reuse conventions" and
"does this fit the app?" both resolve here. Prefer pointing at a canonical
exemplar in the codebase (path:line) over prose. Keep ## headings stable — they
are citation anchors.

Captured by milestone-bootstrapper (dogfood #235), grounded in this repo's own docs.
-->

## Naming
Files, types, functions, tests, branches.
> **Skills:** `skills/<verb>/SKILL.md` (verb = the user-facing command, e.g. `solve-issue`, `solve-milestone`, `triage`, `setup`). **Agents:** `agents/<role>.md` (e.g. `implementer.md`, `triage-reviewer.md`, `design-reviewer.md`). **Hooks:** one gate per name, shipped as a cross-platform twin `hooks/<gate>.{sh,ps1}` (e.g. `force-subagent`, `tests-green`, `no-push`, `no-pr-to-protected`, `no-bom`). **Helper scripts:** `scripts/<name>.{sh,ps1}` twins (e.g. `extract-version`, `render-daemon`, `ci-preflight-steps`). **Feature branches:** `issue/<n>-<slug>` cut from the integration branch (`skills/solve-issue/SKILL.md` step 3). **Config:** `.milestone-config/driver.json` + `.milestone-config/feeder.json` (canonical path; a legacy root `milestone-driver.json` is read transitionally and migrated).

## File & folder layout
Where things go, and the shape of a feature.
> `skills/` (one folder per skill), `agents/` (reviewer + implementer subagents), `hooks/` (the four mechanical gates + `no-bom`, registered in `hooks/hooks.json`, dispatched by the `hooks/run-hook.cmd` polyglot launcher), `scripts/` (deterministic, unit-tested helpers), `tests/` (one runner per script, plus `fixtures/`), `docs/` (architecture, profile-schema, consumer-setup, plus `docs/superpowers/` plans + specs), `.claude-plugin/` (`plugin.json` = version source of truth, `marketplace.json`). A new mechanical behavior = a `hooks/<gate>.{sh,ps1}` twin + a `hooks.json` entry; a new deterministic helper = a `scripts/<name>.{sh,ps1}` twin + a `tests/<name>.test.{sh,ps1}` runner.

## Test patterns
Where tests live, how they're named, fixtures/factories, and what a good test looks like.
> Tests live in `tests/`, named `<script>.test.{sh,ps1}` — a **behavior-identical bash + PowerShell 7+ pair** per script. Pattern: a **golden-matrix runner** that drives the script under test against a `.tsv`/`fixtures/` case table and asserts stdout + stderr exactly (`tests/extract-version.test.sh` + `tests/extract-version.cases.tsv`). Runners are self-contained: they probe for required tools (`command -v jq`) and use `mktemp` per-run temp files to stay collision-free under concurrency. CI runs **both legs** of every twin on every PR into `develop` (`.github/workflows/ci.yml` — `shell-tests-bash` + `shell-tests-pwsh` jobs). A good test for this repo proves the bash and pwsh twins behave identically.

## Canonical exemplars (mirror these)
The reference implementations to copy when building something similar. Point at real code.

| For… | Mirror | Notes |
|---|---|---|
| A new mechanical gate (PreToolUse hook) | `hooks/force-subagent.sh` + `hooks/force-subagent.ps1`, registered in `hooks/hooks.json`, launched via `hooks/run-hook.cmd` | Cross-platform twin; fail-open with a `CLAUDE_HOOK_DISABLE_*` escape hatch. |
| A new deterministic helper script | `scripts/extract-version.sh` + `scripts/extract-version.ps1` | Twin pair; pure/unit-testable; no model judgment. |
| Its test | `tests/extract-version.test.sh` + `.ps1` driving `tests/extract-version.cases.tsv` | Golden-matrix runner asserting stdout + stderr. |
| A new skill | `skills/solve-issue/SKILL.md` (gated per-issue procedure) | Frontmatter `name`/`description`; numbered, gated procedure; tabular output with 🔴 markers. |
| A reviewer subagent | `agents/triage-reviewer.md` | Read-only; returns a structured findings block; never writes code or posts comments. |

## Commits & PRs
Message format and PR expectations.
> **Issue PRs squash-merge into `develop`** (the integration branch) once CI is green, keeping integration history linear (`skills/solve-issue/SKILL.md:237`; `gh pr merge --squash --delete-branch`). Every PR body carries a **Decision Log** and a **Code Review** section; a borderline autonomous call adds a `judgment call` label (`skills/solve-issue/SKILL.md` step 6). The **release PR** (`develop` → `main`) is the one exception: merge it with **`--merge`, never `--squash`** — squashing diverges the branches and conflicts the next release on `plugin.json` + `CHANGELOG.md` (`docs/consumer-setup.md:232`). The release PR, tag, and milestone-close are **manual and human-only**; the loop never opens a PR to `main` (`no-pr-to-protected` hook). Co-author trailer convention applies to commit messages.

## Versioning
Does the project follow semantic versioning? If so, **where the version lives** and the **bump cadence**.
> **SemVer, yes.** The version lives in **`.claude-plugin/plugin.json`** as the single source of truth — `marketplace.json` carries no `version` field (`docs/architecture.md#plugin-version`). The bump **rides the issue or milestone PR itself**, never a separate chore: a standalone `solve-issue` applies a **patch** bump; `solve-milestone` derives the target version from the **milestone title** (a deterministic, unit-tested extractor — `scripts/extract-version.{sh,ps1}`) and passes it to each issue run idempotently. `versioning: false` is version-free mode. Tagging and cutting the GitHub Release happen **manually after** the `develop`→`main` release merge (`docs/consumer-setup.md#releasing-to-your-protected-branch`).
