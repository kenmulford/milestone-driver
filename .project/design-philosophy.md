# Design philosophy

<!--
Part of your project docs (.project/). Tools read and cite this file as
`.project/design-philosophy.md#<section>`. Fill every [TBD]. A section left as
[TBD] is treated as "not specified" — tools fall back to inferred repo
convention rather than ground on a placeholder. Humans own this file; tools may
*propose* changes but never rewrite it. Keep the ## headings stable — they are
citation anchors. Add new sections by appending, not renaming.

Captured by milestone-bootstrapper (dogfood #235), grounded in this repo's own
docs. Every statement cites the source it was lifted from.
-->

## Architectural stance
What kind of system is this, and what does it fundamentally optimize for?
> A stack-agnostic Claude Code plugin: a generic engine ships in the plugin and each consumer repo supplies a thin per-repo profile (`docs/architecture.md` — "A generic engine ships in the plugin, and each repo supplies a thin profile"). It optimizes for **quality under automation** — the bigger the single ask of an AI, the worse the result, so it decomposes a milestone into small issues and runs each one through the same controlled gates, scaling the body of work up without scaling the per-step ask up (`README.md` "The point is quality" / "What makes it different").

## Layering & boundaries
The layers and the allowed dependency directions — what may depend on what, and what must never.
> Three defense-in-depth gating **layers** catch design gaps before they reach the integration branch (`docs/architecture.md#the-layered-gating-model`): Layer 0 — proactive triage (design gaps + dependency order, before any code); Layer 1 — the implementer's mid-build declaration (`NEW_UI_ELEMENTS` / `DESTRUCTIVE_OPS`); Layer 2 — the visual-review gate (UI PRs held open for human sign-off). Orthogonally, four **mechanical gates** are `PreToolUse` hooks that enforce *how* work is done — `force-subagent` (only a dispatched subagent may edit `sourceGlobs`; the main thread only orchestrates), `tests-green`, `no-push`, `no-pr-to-protected` (`docs/architecture.md#the-mechanical-gates`, `README.md` "Discipline is enforced by local hooks, not by trust"). The hard boundary: work merges **only** to the integration branch; the protected branch is never touched by the loop.

## What we optimize for
Ranked priorities, and the explicit non-goals that follow from them.
> 1) **Quality** of each merged change (small, gated, reviewed); 2) a **bounded blast radius** — every merge confined to an integration branch the consumer controls, with the release to the protected branch staying a manual human call (`README.md` "When to use it" / "Your release branch is never touched"); 3) an **auditable** unattended run — a Decision Log on every PR and labels on every borderline call (`README.md` "an audit trail you can review after an unattended run"). Non-goal: taking one big swing at a task — that is explicitly the thing this plugin exists *not* to do (`README.md#what-makes-it-different`).

## One-way doors
Decisions that require human sign-off *before* they're made — irreversible or expensive-to-reverse choices.
> Anything risky parks with a label instead of guessing (`README.md` "Anything risky… parks with a label instead of guessing"). Specifically: **never push to or open a PR against the protected branch** (mechanical `no-push` / `no-pr-to-protected` hooks); **never auto-merge a UI issue** — it is always held open with `needs review` for human visual sign-off (`docs/architecture.md` Layer 2, the three visual-capture invariants); **adding a new third-party dependency** is a STOP-and-ask, parked `needs decision`, never an autonomous call (`docs/architecture.md` label taxonomy; the implementer's new-dependency PAUSE gate). A design gap or contradictory acceptance criteria parks `needs design`.

## Error & failure philosophy
How the system handles and surfaces failure: fail-open vs fail-closed, the user-facing error policy, logging expectations.
> **Park, don't prompt** (`docs/architecture.md#park-dont-prompt`): in the autonomous runtime a blocker never means "stop and wait for a human" — it means post a comment opening with `🔴 Parked — <reason>`, apply exactly one blocker label (`blocked` / `needs design` / `needs decision`), leave the issue and its branch open, and continue the loop with independent clean issues. Only a **systemic** failure (auth/`gh` failure, a broken integration branch, missing tooling) ends the run early. The mechanical hooks are **fail-open** with a `CLAUDE_HOOK_DISABLE_*` escape hatch (`docs/architecture.md#the-mechanical-gates`). Optional integrations (Trello, visualCapture) are best-effort and **never gate a run** — absent means skip with one log line (`README.md#optional-integrations`, the visualCapture invariants).

## Testing philosophy
What we test, at what level, and what "verified" means before a change is done.
> Every issue is built **test-first**: a dispatched implementer subagent writes the change TDD red→green when a test layer exists, else verifies behavior by the best available means and reports it (`README.md#how-it-works` step 2; `skills/solve-issue/SKILL.md` steps 4-5). "Verified" before merge means: the unit gate is green (`unitTestCmd`, when defined), the E2E gate passes for UI surfaces (`e2eTestCmd`, when defined), and `/code-review` has converged — the fresh review is the last action before commit (`skills/solve-issue/SKILL.md` step 6.1). A red unit suite **blocks the commit** mechanically (`tests-green` hook). For this repo's own code, "verified" means both the bash leg and its PowerShell 7+ twin pass their `tests/*.test.{sh,ps1}` golden-matrix runners in CI (`.github/workflows/ci.yml`).
