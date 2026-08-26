# One-time notices — shared reference

This file is the single source of truth for milestone-driver's one-time upgrade
notices — the short, plain-English blurbs that introduce an optional feature
the first time a run would otherwise proceed without mentioning it. Both
`skills/solve-issue/SKILL.md` and `skills/solve-milestone/SKILL.md` read it
instead of carrying their own copy, so the notice text exists exactly once.

It sits here — a peer of the skill folders, not nested inside either skill's
own directory — because two different skills consume it. Every other sibling
reference file (`trello-sync.md`, `parallel-waves.md`, `async-mode.md`) has
one owning skill and lives in that skill's folder; a file with no single
owner sits one level up instead.

This is a growing list — a new one-time notice is added as another `##`
section below, never restated inline in either SKILL.md.

## Contents

- [Section fields](#section-fields)
- [How each skill runs this file](#how-each-skill-runs-this-file)
- [preflight](#preflight)
- [trello](#trello)
- [visualcapture](#visualcapture)
- [parallel-default](#parallel-default)
- [code-review-gate](#code-review-gate)
- [aiprefilter](#aiprefilter)
- [cost-record](#cost-record)
- [uisurfaceglobs](#uisurfaceglobs)

## Section fields

Each `##` section below is one notice:

- **Marker** — the per-clone, gitignored marker file under `.milestone-config/`
  that makes the notice fire at most once per clone. Step 2 below creates it.
- **Skills** — which skill(s) evaluate this notice: `solve-issue`,
  `solve-milestone`, or both.
- **Trigger** — the exact condition that must hold for the notice to fire.
- **Legacy fallback** — the stale root marker checked alongside the new
  marker and removed once the notice fires, or `none` for a notice born
  entirely on the `.milestone-config/` path.
- **Text** — the notice's exact text, printed character-for-character.

## How each skill runs this file

Immediately after its own profile read, each skill iterates the sections below
**in file order** and, for each section whose `Skills` field includes its own
name:

1. Evaluate that section's `Trigger`.
2. If true: print the section's `Text` verbatim, then create the section's
   `Marker` (`mkdir -p .milestone-config && touch <Marker>`),
   then — if the section names a `Legacy fallback` marker — remove that stale
   legacy root marker if present.
3. If false: stay silent — print nothing, write nothing.

A section whose `Skills` field excludes the running skill is never evaluated
by it. File order is print order.

---

## preflight

- **Marker:** `.milestone-config/preflight-notice`
- **Skills:** solve-issue, solve-milestone
- **Trigger:** `preflightCmd` is **absent** from the profile **and**
  **neither** the new marker `.milestone-config/preflight-notice` **nor** the
  legacy root marker `.milestone-driver-preflight-notice` exists (transitional
  read — new path first, legacy root as fallback). Stay **silent** if
  `preflightCmd` is set **or** either marker already exists.
- **Legacy fallback:** `.milestone-driver-preflight-notice` — checked as part
  of the Trigger (silent if it already exists); when the notice fires, remove
  this stale legacy root marker if present.

**Text:**

```text
▶ New in 1.4.0 — optional preflight check (one-time notice)

| What | Tell milestone-driver the command your CI uses for FAST checks
|      | (lint, format, static analysis, security scan).
| Why  | It runs that locally before opening the PR, so those checks are
|      | caught and fixed up front instead of turning your PR red later.
| How  | Add "preflightCmd" to .milestone-config/driver.json. Optional — skip
|      | it and nothing changes.

Examples:
| Stack        | preflightCmd                                   |
| Ruby/Rails   | bundle exec standardrb && bundle exec brakeman -q |
| Node/TS      | npm run lint                                    |
| Any w/ pre-commit | pre-commit run --all-files                 |
| Makefile     | make lint                                       |
```

## trello

- **Marker:** `.milestone-config/trello-notice`
- **Skills:** solve-milestone
- **Trigger:** ALL THREE conditions hold — (a) `mcp__trello__*` tools are
  present in the session (probe by checking if `mcp__trello__get_health` is
  available), (b) `integrations.trello` is **absent** from the profile, (c)
  **neither** the new marker `.milestone-config/trello-notice` **nor** the
  legacy root marker `.milestone-driver-trello-notice` exists (transitional
  read — new path first, legacy root as fallback). Stay **silent** if any
  condition fails.
- **Legacy fallback:** `.milestone-driver-trello-notice` — checked as part of
  the Trigger (silent if it already exists); when the notice fires, remove
  this stale legacy root marker if present.

**Text:**

```text
▶ New in 1.8.0 — optional Trello integration (one-time notice)

| What | Mirror milestone progress to a Trello board (card per milestone,
|      | checklist per issue, automatic state transitions).
| Why  | Keep your Trello board in sync without manual updates.
| How  | Run `/milestone-driver:setup` and choose the Trello tier, or add
|      | `integrations.trello` to .milestone-config/driver.json manually.
|      | Optional — skip and nothing changes.
| Req  | Requires @delorenj/mcp-server-trello in your Claude Code session.
```

## visualcapture

- **Marker:** `.milestone-config/visualcapture-notice`
- **Skills:** solve-issue, solve-milestone
- **Trigger:** `visualCapture` is **absent** from the profile **and**
  `uiSurfaceGlobs` is **present** in the profile **and** the marker
  `.milestone-config/visualcapture-notice` is **absent**. Stay **silent** if
  any condition fails — `visualCapture` present (the feature is already
  configured), `uiSurfaceGlobs` absent (the repo has no UI surface to
  capture), or the marker already exists.
- **Legacy fallback:** none — this marker is **born on the new
  `.milestone-config/` path**: no legacy-root fallback read, no
  stale-legacy-removal step.

**Text:**

```text
▶ New in 1.12.0 — optional visual capture (one-time notice)

| What | Capture rendered screenshots of your UI surfaces and attach
|      | them to the PR.
| Why  | The PR then carries the real rendered screenshots of your
|      | change alongside the diff.
| How  | Run `/milestone-driver:setup` and choose the Visual Capture tier,
|      | or add a `visualCapture` block to .milestone-config/driver.json
|      | manually. Optional — skip and nothing changes.
```

## parallel-default

- **Marker:** `.milestone-config/parallel-default-notice`
- **Skills:** solve-milestone
- **Trigger:** the marker `.milestone-config/parallel-default-notice` is
  **absent**. Stay **silent** if the marker already exists.
- **Legacy fallback:** none — born on the new `.milestone-config/` path.

**Text:**

```text
▶ New in 1.14.0 — parallel builds are now the default (one-time notice)

| What | solve-milestone now builds mutually-independent issues in a Wave
|      | concurrently by default — the old `--parallel` flag is gone.
| Why  | Faster milestone runs, with no flag to remember. A run-start
|      | barrier check drops to sequential only when something makes
|      | parallel unsafe.
| Opt-out | Set "parallel": false in .milestone-config/driver.json to force
|      | sequential runs. Optional — leave it out to stay parallel.
| DB   | If your unit tests share a test database, the first run asks once
|      | whether your harness is isolated per worker, then records your
|      | answer as "parallel" so it never asks again.
```

## code-review-gate

- **Marker:** `.milestone-config/code-review-gate-notice`
- **Skills:** solve-issue, solve-milestone. **Trigger:** marker absent (silent once it exists). **Legacy fallback:** none — born on the new path.

**Text:**

```text
▶ New in 1.15.1 — mechanical code-review gate (one-time notice)

| What | Blocks `gh pr create`/`gh pr merge` when the PR body lacks the required '## Code Review' section (protectedBranch is exempt).
| Opt-out | CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1; missing jq/gh, or a failed `gh pr view`, fail open.
```

## aiprefilter

- **Marker:** `.milestone-config/aiprefilter-notice`
- **Skills:** solve-issue, solve-milestone. **Trigger:** `visualCapture` present with all three required keys (`serverCmd`, `readyUrl`, `signInPath`) AND `uiSurfaceGlobs` present AND `visualCapture.aiPrefilter` absent AND marker absent — silent if any fails. **Legacy fallback:** none — born on the new path.

**Text:**

```text
▶ New in 1.16.0 — optional AI screenshot pre-filter (one-time notice)

| What | An AI pass reads the screenshots visual capture already took and
|      | posts a per-surface pass / suspected-issue verdict on the PR,
|      | alongside the Visual evidence comment.
| Why  | Obvious rendered-layout breakage (overflow, overlap, blank or
|      | broken surfaces) is flagged on the PR before a human looks.
|      | Never a merge gate.
| How  | Add "aiPrefilter": true inside the visualCapture block in
|      | .milestone-config/driver.json. Optional — skip and nothing changes.
```

## cost-record

- **Marker:** `.milestone-config/cost-record-notice`
- **Skills:** solve-issue, solve-milestone. **Trigger:** marker absent (silent once it exists). **Legacy fallback:** none — born on the new path.

**Text:**

```text
▶ New in 1.16.0 — per-run cost record (one-time notice)

| What | Every run now writes one priced cost record (tokens × wall-clock, in $) to .milestone-config/.runtime/cost-records/ — passive, per-clone, additive, never-gating.
| Note | Gitignored scratch; absent writer / no usage figures → silent skip; cost is a lower-bound (unsplit tokens priced as input).
```

## uisurfaceglobs

- **Marker:** `.milestone-config/uisurfaceglobs-notice`
- **Skills:** solve-issue, solve-milestone. **Trigger:** `uiSurfaceGlobs` **absent** from the profile AND marker absent — silent if either fails. **Legacy fallback:** none — born on the new path.

**Text:**

```text
▶ New in 1.17.0 — tell milestone-driver where your UI lives (one-time notice)

| What | "uiSurfaceGlobs" marks which path patterns are UI surfaces.
| Why  | Without it two layers stay silently off: design-lens review in
|      | triage, and visual capture.
| How  | Run `/milestone-driver:setup` or add "uiSurfaceGlobs" to
|      | .milestone-config/driver.json. Optional — a repo with no UI skips it.
```
