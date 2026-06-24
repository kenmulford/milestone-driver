# Environment

<!--
Project doc (.project/). Cite as `.project/environment.md#<section>`. Declares what the
project's runtime and production environment looks like — the facts downstream tools ground
their data, test, and caching decisions in. It does NOT provision anything; it records the
model so issues don't drift. Fill every [TBD]; a section left [TBD] is treated as "not
specified." Humans own this file; tools propose, never rewrite. Keep the ## headings stable
— they are citation anchors.

Captured by milestone-bootstrapper (dogfood #235), grounded in this repo's own docs.
-->

## Environments
Which environments exist (production, staging, test, local) and how they differ.
> There is **no application runtime** and no deploy environment — this is a Claude Code plugin that runs inside a developer's Claude Code session against a GitHub repo on a gitflow-style branch model (`README.md#requirements`). The only "environments" are: a developer's **local CLI** (where the skills, hooks, and scripts execute), and **GitHub Actions CI** (`.github/workflows/ci.yml`, runs the shell test suites on every PR into `develop`). "Release" is a manual human promotion of the integration branch (`develop`) to the protected branch (`main`); the loop never performs it (`docs/consumer-setup.md#releasing-to-your-protected-branch`).

## Data stores
Databases and other persistent stores: the engine(s), and the **topology** — separate prod / staging / test databases, or a shared one. **Test-data isolation:** how tests get a clean, isolated database (a dedicated test DB, a per-worker DB suffix, transactional rollback, truncate-on-start). This is the single biggest drift source if left unstated.
> **None** — there is no database. All durable state lives in **GitHub** (issues, PRs, milestones, labels) and **git refs**. The only local state is per-clone runtime scratch under `.milestone-config/` — all gitignored: `tests-stamp`, `preflight-notice`, `trello-notice`, `visualcapture-notice`, `triage-cache.json`, `.runtime/`, `worktrees/` (`.milestone-config/.gitignore`). The committed `.milestone-config/driver.json` profile is deliberately **not** ignored. Test isolation for this repo's own shell tests: each test runner uses `mktemp`/per-run temp files to avoid fixed-path collisions under concurrent runs (`tests/extract-version.test.sh`).

## Caching
Whether caching exists and, if so, the layer and technology (in-memory, Redis, CDN), what is cached, and the invalidation policy. **"None" is a valid, drift-preventing answer** — record it explicitly.
> **None** in any infrastructural sense. The only "cache" is the per-clone, gitignored `.milestone-config/triage-cache.json` scratch the triage phase writes (`.milestone-config/.gitignore`); it is local-run state, not a service.

## Async & messaging
Background jobs, queues, streams, schedulers — or "none."
> **None.** The engine is synchronous within a Claude Code session. The closest thing to concurrency is the optional `--parallel` mode, which builds mutually-independent issues within a Wave concurrently in git worktrees (capped at 4 workers) and then integrates them through one serial verified merge tail (`docs/architecture.md#parallel-mode-optional`) — orchestrated worktrees, not a message queue.

## External services & integrations
Third-party services the app depends on: auth / identity, payments, email / SMS, object storage, analytics, other APIs.
> **GitHub** is the one hard dependency, reached through the authenticated `gh` CLI (issues, PRs, milestones, labels, branch protection). **Optional, best-effort, never-gating** integrations: a **Trello** board mirror via the `@delorenj/mcp-server-trello` MCP server when `integrations.trello` is in the profile (`README.md#optional-integrations`); the **visualCapture** render seam that attaches light/dark screenshots to held-open UI PRs (`docs/architecture.md#visual-capture-optional`); and the **milestone-coherence-reviewer** companion plugin for a post-build second opinion (`README.md#optional-integrations`). Each absent integration skips silently.

## Runtime & hosting
Where it runs and the runtime/version targets (hosting platform, language-runtime versions, regions). For mandated frameworks and packages, cross-reference `library-manifest.md`.
> Runs **client-side** in a Claude Code session on the developer's machine; no hosting, no server, no regions. Runtime targets: **bash + jq** (primary) and **PowerShell 7+** (fallback) for hooks and scripts; **`gh` authenticated** and **git** for all repo operations (`README.md#requirements`). CI runs on `ubuntu-latest`, which ships bash, jq, pwsh, and python3 preinstalled (`.github/workflows/ci.yml`). Mandated runtimes are cross-referenced in `library-manifest.md#runtime--frameworks`.
