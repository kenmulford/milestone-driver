# Plan — driver: ground in `.project/` via anchored retrieval (grounding seam, part 2/3)

**Goal:** close the grounding GAP. Wire the **implementer**, **triage-reviewer**, and
**design-reviewer** to ground in the project brain (`.project/`) the same way the feeder does — but
via **section-level (anchored) retrieval**, so the plugin that *writes the code* shares one source of
truth with the plugin that *planned it* (sync), **without** multiplying tokens.

> Part of the suite grounding seam. Siblings: `milestone-bootstrapper/docs/efficiency-grounding-plan.md`
> (emits the `projectDocs` key — do that first) and
> `milestone-feeder/docs/efficiency-grounding-plan.md` (shared digest). Tracked as the held issue
> **driver #172** (+ the anchored-retrieval primitive, rank #19 in `milestone-suite/benchmarks/analysis-report.md`).

## Why this is the crux

A clean grep shows the driver reads **zero** `.project/` docs today — the implementer + reviewers
ground only off `domainSkills` (skill *IDs*), `nonNegotiables`, repo patterns, and the feeder-baked
issue body. So the **project brain never reaches the implementer directly**, contradicting the
suite's stated intent that *both* plugins ground in it. The feeder grounds in `.project/`; the driver
doesn't — that's the drift. (`milestone-suite/benchmarks/discovery-map.md` §3.)

**Critical economics:** wiring this naively (whole-file inlining) is a **net token cost**
(~+2K template, ~+4.5–7K populated, × *every* implementer/triage/design dispatch). It only nets a win
— and only stays affordable for a rich `.project/` — via **anchored retrieval**: pull just the cited
`## sections` an issue touches, bounded by relevant-section size regardless of total doc size. So
this plan's value is **consistency/quality first**, with the token cost held down by selective
retrieval. **Never close the gap by dropping grounding to save tokens; never close it whole-file.**

## Current state

- Implementer/reviewers: no `.project/` reads (grep-clean).
- `driver.json`: no `projectDocs` key.
- The feeder already bakes `.project/<doc>.md#<section>` citations into issue bodies — the
  **citation-anchor discipline already exists** and can drive which sections to retrieve.

## The change

- [ ] **Schema + read.** Add `projectDocs` (default `.project/`, absent-means-default) to
      `docs/profile-schema.md`, mirroring the feeder, and read it where the driver resolves its
      profile. (Bootstrapper #38 emits the value; default to `.project/` even if absent.)
- [ ] **Anchored-retrieval primitive.** Ship a dependency-free `scripts/read-doc-section.sh` + `.ps1`
      twin: given a doc path and a `## anchor`, print only that section. **Fail loud** (non-zero exit)
      on a missing anchor, so a drifted heading surfaces rather than returning silent empty
      grounding. Reuse the existing anchor-walk pattern used elsewhere in the suite.
- [ ] **Resolve cited sections once, in the orchestrator.** In `solve-issue` / `triage`, before
      dispatch, resolve which `.project/<doc>#<section>` anchors the issue cites (from the issue body
      + acceptance criteria), pull a **superset** of plausibly-relevant sections via the primitive,
      and pass them into the dispatch briefs. Do **not** have each subagent re-read whole files.
- [ ] **Wire the three agents.** Update `agents/implementer.md`, `agents/triage-reviewer.md`,
      `agents/design-reviewer.md` "What you receive" to consume the provided `.project/` sections;
      keep their `Read`/grep tools for **on-demand** pulls of additional anchors (never under-ground).
- [ ] **Degrade gracefully.** Absent `projectDocs` → `.project/`. Absent `.project/` directory →
      proceed with no project grounding, no error (mirrors the feeder's best-effort contract).

## Acceptance criteria

- [ ] On a UI issue that cites `.project/design-system.md#data-tables`, the implementer + reviewers
      receive **that section** in their briefs (verified), not the whole file and not nothing.
- [ ] Per-dispatch grounding tokens scale with **cited-section size, not total doc size** — validated
      against a realistically-sized `.project/` (anchored < whole-file; see Measurement).
- [ ] A missing/renamed anchor causes a **loud failure**, not empty grounding.
- [ ] Quality gates still pass (the feeder→driver triage stays `GAPS: none`; PRs stay green-CI);
      grounding is **additive** — it raises consistency, changes no existing gate logic.
- [ ] Absent `.project/` → run proceeds unchanged (no new hard dependency).

## Measurement (lean — the one place token economics must be checked)

The current fixtures are tiny, so the grounding lever won't show and naive grounding could regress.
Before merging: on a **realistic `.project/`** (a small rich fixture or a real repo), measure
**whole-file vs anchored** per-dispatch grounding and confirm anchored is cheaper while preserving
the cited grounding. Reuse the harness in `milestone-suite/benchmarks/`. This is a validation step
*within* the work, not a separate gate.

## Dependencies & sequence

1. **bootstrapper #38** emits `projectDocs` (do first; but driver defaults to `.project/` regardless).
2. Build the **primitive**, then wire the orchestrator resolution, then the three agent briefs.
3. Land via feature branch → `develop` PR.

## Risks / non-negotiables

- **Anchored, never whole-file** — whole-file inlining is the do-NOT-do ceiling (net cost, and
  unbounded for a rich `.project/`).
- **Under-retrieval is the real risk** — mitigate with a superset of plausibly-relevant sections +
  on-demand `Read`. **Never trade grounding completeness for tokens.**
- **Prompt-caching is NOT plugin-actionable** here (Markdown agents, no `cache_control` surface) —
  do not pursue it as a plugin edit; the lever is selective retrieval + resolve-once.
