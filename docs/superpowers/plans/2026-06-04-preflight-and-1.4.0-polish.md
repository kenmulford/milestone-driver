# Preflight (CI-parity-lite) + 1.4.0 Polish Implementation Plan

> **For agentic workers:** delivered as **GitHub milestone 1.4.0**. Each issue is one `/milestone-driver:solve-issue` unit; `solve-issue` generates the per-issue implementation steps at solve time. This repo's source is markdown skills/agents + JSON config (no unit-test harness) — verification is structural (`claude plugin validate`, JSON parse, cross-file consistency, `/code-review`). Steps use `- [ ]` checkboxes.

**Goal:** Catch the lint/static/security gaffes that turn a PR red — *before* the PR — via one **optional, consumer-named** `preflightCmd`, run after `/code-review` and before commit. Roll it out so existing users discover it in plain English on first run after updating, and tighten the plugin's own output to concise + tabular.

**Architecture:** A single optional profile key `preflightCmd` (the consumer points it at their existing fast gate — `pre-commit run`, `make lint`, `npm run lint`, `bundle exec standardrb && brakeman -q`). `solve-issue` runs it as a gate that behaves exactly like the existing unit/E2E gates (re-dispatch on failure, "at most 2" cap, park `blocked` if non-converging). **No CI-config discovery, no per-tool keys, no new hooks** — see the reframe below.

**Tech Stack:** Markdown skills/agents, `milestone-driver.json` (JSON), `gh`, `git`. Grounding discipline (no guessing; cite `file:line`; unverifiable → STOP/park) carries over from the 1.3.0 plan and applies to every step here.

## Why light, not the discovery engine (the reframe)

**CI is the quality gate; `preflightCmd` is a latency optimization.** The repo's CI runs these checks authoritatively on the PR regardless — so a local gate catches nothing CI would miss; its only value is moving a red result earlier to dodge the fix→push→wait round trip. That value is real (observed twice on #56) but bounded, so the mechanism must be cheap. A CI-config discovery parser (the original #56) is a disproportionate, fragile build for a latency win CI already backstops; rejected. `/code-review` is semantic (bugs/reuse) and does **not** run StandardRB/Brakeman/ruff — so the gap is real but narrow (mechanical linters/scanners), which a one-line consumer-named command closes. The heterogeneous consumer base (MAUI + Rails) *favors* "each repo names its own gate" over any hardcoded tool list.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `docs/profile-schema.md` | modify | Add `preflightCmd` key (optional, new tier) + the run-it-after-review note |
| `skills/solve-issue/SKILL.md` | modify | Preflight gate step (after 6.1 review, before 6.4 bump/commit); + first-run notice in "Before starting"; + Output-style section |
| `skills/solve-milestone/SKILL.md` | modify | First-run notice in "Before starting"; + Output-style section |
| `skills/triage/SKILL.md` | modify | Output-style section |
| `skills/setup/SKILL.md` | modify | `preflightCmd` Phase-1 inference + Phase-2 tier prompt; + Output-style section |
| `.gitignore` | modify | Add `.milestone-driver-preflight-notice` marker (alongside the existing tests-stamp) |
| `README.md`, `docs/consumer-setup.md` | modify | Document preflight + the upgrade notice + the output-style norm |
| `.claude-plugin/plugin.json` | modify | Version → 1.4.0 (rides in the PRs per the existing bump convention) |

No `hooks/` changes.

## The `preflightCmd` gate (issue A)

- **Profile key** `preflightCmd` (string, optional, new "Preflight" tier). Absent → gate skipped cleanly, exactly like `unitTestCmd`/`e2eTestCmd` absent. Plain-language: "A single command that runs your project's fast pre-PR checks (lint, format, static analysis, security scan) — whatever your CI enforces beyond tests."
- **Placement in `solve-issue` step 6:** after the `/code-review` resolve loop converges (6.1) and **before** the version bump (6.4) / commit (6.5). Mirrors how the unit gate (4) and E2E gate (5) sit before integrate.
- **Behavior:** run `preflightCmd` in the repo root, capture real output. Non-zero exit → gate failure → re-dispatch the implementer with the failing command + output (the existing **"at most 2"** cap); a source-changing fix re-runs `unitTestCmd` (if defined) and re-runs `/code-review` (the existing "fresh review is the last action before commit" rule) and re-runs preflight. Non-converging after the cap → **park `blocked`** (comment what failed + what's needed, preserve the branch, `+ in progress` if commits, return — the loop continues). Park-don't-prompt, consistent with every other gate.
- **Scope guidance (docs, not enforced):** point it at the *fast* gates; the heavy test suite is already covered by `unitTestCmd`, so a consumer who includes the full suite in `preflightCmd` is just paying for it twice — note this, don't police it.
- **Setup integration:** Phase-1 silent inference detects a candidate (`.pre-commit-config.yaml` → `pre-commit run --all-files`; `package.json` `scripts.lint` → `npm run lint`; `Makefile` `lint`/`check` target; `bin/` lint scripts); Phase-2 presents it in a new "Preflight" tier with skip-consequence ("Skip → no preflight gate; CI-only lint/scan, caught on the PR instead of locally") and an example if none detected.

## The first-run upgrade notice (issue B)

Existing 1.3.2 users have a valid profile, so `setup` won't auto-run on update. Surface `preflightCmd` proactively:

- In `solve-issue` and `solve-milestone` "Before starting" (after reading the profile): **if `preflightCmd` is absent AND the marker file `.milestone-driver-preflight-notice` does not exist** → print the notice once, then create the marker. If `preflightCmd` is set, or the marker exists, say nothing.
- The marker is gitignored (per-clone, one-time — same pattern as `.milestone-driver-tests-stamp`).
- **Notice content — plain English for a dev or tech-PM, as a table, with examples:**

  ```text
  ▶ New in 1.4.0 — optional preflight check (one-time notice)

  | What | Tell milestone-driver the command your CI uses for FAST checks
  |      | (lint, format, static analysis, security scan).
  | Why  | It runs that locally before opening the PR, so those checks are
  |      | caught and fixed up front instead of turning your PR red later.
  | How  | Add "preflightCmd" to milestone-driver.json. Optional — skip it
  |      | and nothing changes.

  Examples:
  | Stack        | preflightCmd                                   |
  | Ruby/Rails   | bundle exec standardrb && bundle exec brakeman -q |
  | Node/TS      | npm run lint                                    |
  | Any w/ pre-commit | pre-commit run --all-files                 |
  | Makefile     | make lint                                       |
  ```

## Plugin output-style guideline (issue C)

The agents already carry a "Communication style" section; the skills don't. Add a short **`## Output style`** section to `solve-issue`, `solve-milestone`, `triage`, and `setup`:

> **Output style.** Be concise — report status and outcomes flatly, no wall-of-text. Present steps, gates, lists, and options as **tables**, not inline prose. Mark anything that needs a human with 🔴. (Mirrors the agents' communication-style contract.)

## Issue decomposition (milestone 1.4.0)

| # | Issue (proposed title) | Wave | Depends on |
|---|---|:--:|---|
| A | (rescope #56) feat(preflight): optional `preflightCmd` gate in solve-issue + setup inference + schema | 1 | — |
| B | feat: first-run-after-update notice for `preflightCmd` (plain-English, examples, one-time marker) | 2 | A |
| C | chore(skills): add concise + tabular Output-style guideline to the skills | 2 | A *(shared files)* |
| D | docs(1.4.0): README + consumer-setup for preflight, the upgrade notice, and the output-style norm | 3 | A, B, C |

**Acceptance criteria:**
- **A** — `preflightCmd` documented in `docs/profile-schema.md` (optional, Preflight tier, skip-consequence); `solve-issue` runs it after `/code-review` and before commit with the re-dispatch/cap/park behavior above; absent → skipped cleanly; `setup` infers a candidate (Phase 1) and prompts it (Phase 2). `claude plugin validate` passes.
- **B** — `solve-issue`/`solve-milestone` emit the one-time plain-English notice (table + examples) when `preflightCmd` is absent and the marker is missing, then write the marker; silent when set or already shown; `.milestone-driver-preflight-notice` added to `.gitignore`.
- **C** — the four skills carry the `## Output style` section verbatim-consistent with the agents' contract; no behavioral change beyond presentation.
- **D** — README documents the preflight gate + the output-style norm; consumer-setup notes preflight in the run flow + the upgrade notice; `plugin.json` at 1.4.0.

**#56 rescope:** #56's body currently describes the rejected CI-config discovery engine. Before it becomes issue A, rewrite its body to the `preflightCmd` approach with a short "rescoped from discovery → consumer-named command; CI is the authority, this is a latency optimization" note, preserving the original problem/scenario (the two observed misses) as the motivation.

**Proposed milestone 1.4.0 description:** the reframe one-liner + the Wave table above with real issue numbers (filled at creation).

## Verification model

`claude plugin validate . --strict` after skill/schema edits; JSON parse of `plugin.json`; cross-file consistency (`preflightCmd` named identically in schema, solve-issue, setup; the notice text identical in both skills); `/code-review` before each commit. No behavioral test harness exists in this repo.

## Out of scope (explicitly)

- CI-config discovery / YAML parsing (the rejected heavy path).
- Per-tool profile keys (`lintCmd`, etc.) — one composite `preflightCmd` only.
- Enforcing dedup against the test suite — documented guidance, not policed.
