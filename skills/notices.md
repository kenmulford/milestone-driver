# One-time notices — shared reference

This file is the single source of truth for milestone-driver's one-time upgrade
notices — the short, plain-English blurbs that introduce an optional feature
the first time a run would otherwise proceed without mentioning it. Both
`skills/solve-issue/SKILL.md` and `skills/solve-milestone/SKILL.md` read this
file rather than each carrying their own copy of the notice text, so that text
now exists exactly once and can no longer drift between the two skills.

It sits here — a peer of the skill folders, not nested inside either skill's
own directory — because it is the one reference file two different skills
consume. Every other sibling reference file in this plugin (`trello-sync.md`,
`parallel-waves.md`, `worker-mode.md`, `async-mode.md`) has exactly one owning
skill and lives inside that skill's own folder; this file has no single owner,
so it sits one level up instead.

This is a growing list — a new one-time notice is added as another `##`
section below, never restated inline in either SKILL.md.

## Section fields

Each `##` section below is one notice:

- **Marker** — the per-clone, gitignored marker file under `.milestone-config/`
  that makes the notice fire at most once per clone, and how it's created.
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
   `Marker` (`mkdir -p .milestone-config && touch .milestone-config/<marker>`),
   then — if the section names a `Legacy fallback` marker — remove that stale
   legacy root marker if present.
3. If false: stay silent — print nothing, write nothing.

A section whose `Skills` field does not include the running skill is never
evaluated by that skill — this is what keeps notices scoped to only
`solve-milestone` (or to both) exactly as scoped below. File order is print
order: on a fresh clone, the notices below print in the order the sections
appear in this file.

---

## preflight

- **Marker:** `.milestone-config/preflight-notice` — created via
  `mkdir -p .milestone-config && touch .milestone-config/preflight-notice`
  when the notice fires.
- **Skills:** solve-issue, solve-milestone
- **Trigger:** `preflightCmd` is **absent** from the profile **and**
  **neither** the new marker `.milestone-config/preflight-notice` **nor** the
  legacy root marker `.milestone-driver-preflight-notice` exists (transitional
  read — new path first, legacy root as fallback). Stay **silent** if
  `preflightCmd` is set **or** either marker already exists. The marker is
  per-clone and gitignored, so the notice shows at most once per clone (same
  pattern as `.milestone-config/tests-stamp`).
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

- **Marker:** `.milestone-config/trello-notice` — created via
  `mkdir -p .milestone-config && touch .milestone-config/trello-notice` when
  the notice fires.
- **Skills:** solve-milestone
- **Trigger:** ALL THREE conditions hold — (a) `mcp__trello__*` tools are
  present in the session (probe by checking if `mcp__trello__get_health` is
  available), (b) `integrations.trello` is **absent** from the profile, (c)
  **neither** the new marker `.milestone-config/trello-notice` **nor** the
  legacy root marker `.milestone-driver-trello-notice` exists (transitional
  read — new path first, legacy root as fallback). Stay **silent** if any
  condition fails. The marker is per-clone and gitignored.
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

- **Marker:** `.milestone-config/visualcapture-notice` — created via
  `mkdir -p .milestone-config && touch .milestone-config/visualcapture-notice`
  when the notice fires.
- **Skills:** solve-issue, solve-milestone
- **Trigger:** `visualCapture` is **absent** from the profile **and**
  `uiSurfaceGlobs` is **present** in the profile **and** the marker
  `.milestone-config/visualcapture-notice` is **absent**. Stay **silent** if
  any condition fails — `visualCapture` present (the feature is already
  configured), `uiSurfaceGlobs` absent (the repo has no UI surface to
  capture), or the marker already exists. The marker is per-clone and
  gitignored, so the notice shows at most once per clone (same lifecycle as
  `.milestone-config/preflight-notice`).
- **Legacy fallback:** none — unlike preflight/Trello, this marker is **born
  on the new `.milestone-config/` path**, so the gate checks only the
  new-path marker; there is no legacy-root fallback read and no
  stale-legacy-removal step.

**Text:**

```text
▶ New in 1.12.0 — optional visual capture (one-time notice)

| What | Capture rendered screenshots of your UI surfaces during the
|      | visual-review gate.
| Why  | The gate can then show the real rendered screenshots of your
|      | change instead of degrading to PR-open-for-human-test.
| How  | Run `/milestone-driver:setup` and choose the Visual Capture tier,
|      | or add a `visualCapture` block to .milestone-config/driver.json
|      | manually. Optional — skip and nothing changes.
```

## parallel-default

- **Marker:** `.milestone-config/parallel-default-notice` — created via
  `mkdir -p .milestone-config && touch .milestone-config/parallel-default-notice`
  when the notice fires.
- **Skills:** solve-milestone
- **Trigger:** the marker `.milestone-config/parallel-default-notice` is
  **absent**. Stay **silent** if the marker already exists. The marker is
  per-clone and gitignored, so the notice shows at most once per clone.
- **Legacy fallback:** none — like visualcapture, this marker is **born on
  the new `.milestone-config/` path**, so the gate checks only the new-path
  marker; there is no legacy-root fallback read and no stale-legacy-removal
  step.

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

- **Marker:** `.milestone-config/code-review-gate-notice`, created via `mkdir -p .milestone-config && touch .milestone-config/code-review-gate-notice`.
- **Skills:** solve-issue, solve-milestone. **Trigger:** marker absent (silent once it exists; per-clone, gitignored, fires once). **Legacy fallback:** none — born on the new path, like visualcapture/parallel-default.

**Text:**

```text
▶ New in 1.15.1 — mechanical code-review gate (one-time notice)

| What | Blocks `gh pr create`/`gh pr merge` when the PR body lacks the required '## Code Review' section (protectedBranch is exempt).
| Opt-out | CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1; missing jq/gh, or a failed `gh pr view`, fail open.
```

## aiprefilter

- **Marker:** `.milestone-config/aiprefilter-notice` — created via
  `mkdir -p .milestone-config && touch .milestone-config/aiprefilter-notice`
  when the notice fires.
- **Skills:** solve-issue, solve-milestone
- **Trigger:** `visualCapture` is **present** in the profile with all three
  required keys (`serverCmd`, `readyUrl`, `signInPath`) **and**
  `uiSurfaceGlobs` is **present** in the profile **and**
  `visualCapture.aiPrefilter` is **absent** **and** the marker
  `.milestone-config/aiprefilter-notice` is **absent**. Stay **silent** if any
  condition fails — `aiPrefilter` already set (the pre-filter is configured
  either way), `visualCapture` absent/incomplete (nothing to pre-filter),
  `uiSurfaceGlobs` absent (the repo has no UI surface to capture — the
  pre-filter could never fire), or the marker already exists. The marker is per-clone and gitignored, so the
  notice shows at most once per clone (same lifecycle as
  `.milestone-config/visualcapture-notice`).
- **Legacy fallback:** none — like visualcapture/parallel-default/
  code-review-gate, this marker is **born on the new `.milestone-config/`
  path**, so the gate checks only the new-path marker; there is no legacy-root
  fallback read and no stale-legacy-removal step.

**Text:**

```text
▶ New in 1.16.0 — optional AI screenshot pre-filter (one-time notice)

| What | An AI pass reads the screenshots visual capture already took and
|      | posts a per-surface pass / suspected-issue verdict on the PR,
|      | alongside the Visual evidence comment.
| Why  | Obvious rendered-layout breakage — overflow, overlap, blank/broken
|      | surfaces — gets flagged before a human looks; the human stays the
|      | merge gate.
| How  | Add "aiPrefilter": true inside the visualCapture block in
|      | .milestone-config/driver.json. Optional — skip and nothing changes.
```

## cost-record

- **Marker:** `.milestone-config/cost-record-notice`, created via `mkdir -p .milestone-config && touch .milestone-config/cost-record-notice`.
- **Skills:** solve-issue, solve-milestone. **Trigger:** marker absent (silent once it exists; per-clone, gitignored, fires once). **Legacy fallback:** none — born on the new path, like visualcapture/parallel-default/code-review-gate/aiprefilter.

**Text:**

```text
▶ New in 1.16.0 — per-run cost record (one-time notice)

| What | Every run now writes one priced cost record (tokens × wall-clock, in $) to .milestone-config/.runtime/cost-records/ — passive, per-clone, additive, never-gating.
| Note | Gitignored scratch; absent writer / no usage figures → silent skip; cost is a lower-bound (unsplit tokens priced as input).
```
