# Proactive Triage & Design-Gap Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: this plan is delivered as **GitHub milestone 1.3.0**. Each issue below is one `/milestone-driver:solve-issue` unit; `solve-issue` generates the bite-sized, architecture-aware implementation plan per issue at solve time (this repo's source is markdown skills/agents + JSON config, and has no unit-test harness — verification is structural, see "Verification model"). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Before any code is written, triage a milestone's issues — through a software-architect lens, offloading UI concerns to a front-end-designer lens — for **design gaps** and **dependency ordering**, emitting either an all-clear or a concise gap table (with a blocker summary posted on each affected issue), then drive the build loop from the resulting dependency graph (build clean/independent issues immediately, hold gapped ones and their dependents). Backstop it with implementer surface-declarations, a post-build visual-review gate for UI issues, and a verified-by-other-means E2E escape.

**Architecture:** Three defense-in-depth layers around the existing per-issue pipeline. Layer 0 (the priority) is a new bundled **`triage` skill** invoked by `solve-milestone` (Phase 0, batched across the milestone) and `solve-issue` (single-issue), driven by two new bundled agents — **`triage-reviewer`** (architect lens) and **`design-reviewer`** (front-end lens) — both profile-overridable exactly like `implementerAgent`. The dependency graph triage produces feeds `solve-milestone`'s loop continuation. Layer 1 is implementer surface-declarations (`NEW_UI_ELEMENTS` / `DESTRUCTIVE_OPS`) the orchestrator gates on. Layer 2 is the post-build visual-review gate (existing issue #18). **No new mechanical hooks** — every new gate is procedural (skill STOP/PAUSE), because deciding "is this a new UI element / a contradictory design / a destructive op" requires reading a diff or a design, which a `PreToolUse` hook (a string/path pattern-matcher) cannot do.

**Tech Stack:** Markdown skills/agents, `milestone-driver.json` profile (JSON), `gh`, `git`. No code test suite — verification is JSON-parse + `claude plugin validate` + cross-file consistency + `/code-review` + a triage dry-run against the issue-#43 scenario.

**Source of the design:** the PracticingPrayer 1.5.0 `solve-milestone` run feedback (≈8 human prompts on 1.5 issues), issue [#18](https://github.com/kenmulford/milestone-driver/issues/18), and the architect + staff-SWE consultation recorded in session.

---

## Why this shape (the reframe)

The 1.5.0 run cost ~8 prompts on 1.5 issues because problems were discovered **late and serially** — each mid-flight, after work was done. The root cause is **underspecified / internally-contradictory acceptance criteria**, not merge timing; auto-merge was doing exactly what it was built to do. Front-loading a batched triage converts serial mid-run surprises into one consolidated up-front review, and the dependency graph it produces dissolves the "leave PRs open vs keep the loop running" tension via **data** (which issues are independent) rather than stacked branches (premature — 0 current use cases).

## Grounding discipline (non-negotiable)

Every step, issue, agent finding, dependency edge, design-gap call, and verification in this plan resolves **grounded in the actual artifact** — the real issue text, the real recorded design, source read at `file:line`, and real command/run output. **No guessing, no hypotheses presented as fact, no lazy shortcuts.** This extends the implementer's existing anti-fabrication contract (`agents/implementer.md`: "never fabricate a citation"; "grep before you rely on it") to the triage and design reviewers and to issue authoring itself:

- A `triage-reviewer` dependency edge cites the actual reference (e.g. "#B's criteria call `IImportService.Confirm`, introduced by #A — `file:line`"), never "probably depends on."
- A `design-reviewer` gap names the actual recorded line it contradicts and the actual existing pattern it should mirror (cite the file), never an imagined one.
- If buildability/consistency/sufficiency **cannot be determined from the real artifact**, that is a **Blocker** (missing information) — flag it; do not guess a resolution.
- Verification shows real evidence (validate output, parse result, an actually-run dry-run), never asserted. If the real artifact can't be obtained, **STOP** — never fabricate a stand-in.

## Autonomous progress — park, don't prompt (non-negotiable)

The goal of this plugin is **autonomous progress.** A STOP/PAUSE at implementation time **never** means "interactively prompt the operator and wait." It means **park the issue and keep going**:

1. **Document** on the issue (`gh issue comment`) what was hit and what is needed to clear it.
2. **Leave the issue open.**
3. **Leave the branch open** if work was done — preserve the work on the feature branch (commit what is committable; if a red gate blocks the commit, retain/push the WIP and say so) and name the branch in the comment.
4. **Label** the issue per the taxonomy below.
5. The milestone loop **continues** with independent, clean issues; only the parked issue and its transitive dependents are held. The run ends when every issue is **done or parked** — never by waiting on a human.

The human is engaged **asynchronously** — through the comment + label, reviewed after the run — not by an interactive prompt. PAUSE vs STOP becomes a *label* distinction (`needs decision` vs `needs design`/`blocked`), not a "wait for a reply" distinction. (This is the plugin's autonomous runtime; it is distinct from interactive collaboration on the main thread.)

**Only a systemic failure halts the whole run** — auth/`gh` failure, a broken `integrationBranch`, missing tooling — because nothing further can proceed. An issue-level blocker is a park, not a halt. A standalone interactive `solve-issue` still parks durably (comment + label + open branch); it may additionally narrate to the watching operator.

## The layered model

| Layer | When | Catches | Mechanism |
|---|---|---|---|
| **0 — Proactive triage** *(priority)* | Before any build, batched at `solve-milestone` start (single-issue at `solve-issue` start) | Design contradictions, silent UX gaps, missing criteria, **dependency ordering** | New `triage` skill + `triage-reviewer` (architect) + `design-reviewer` (front-end) agents |
| **1 — Implementer declaration** | After the implementer returns | `NEW_UI_ELEMENTS` / `DESTRUCTIVE_OPS` the implementer discovers mid-build that triage couldn't foresee | Implementer report fields + `solve-issue` PAUSE/STOP triggers |
| **2 — Visual-review gate** | Post-build, pre-merge | Rendered defects unit/E2E pass: misalignment, missing toolbar, wrong default state, save-not-enabling | Issue #18: screenshots (light/dark) on the PR, PR left open, no auto-merge for UI issues. **No render capability → skip the picture, keep the checkpoint: PR stays open for human test before merge (never fail, never auto-merge UI).** |

Defense in depth: triage front-loads most design gaps, the declaration backstops what the implementer discovers, the visual gate catches what only renders on-device. #43 would have been caught **twice** — at triage (contradiction → Blocker; design-reviewer flags "flat 16-row list ≠ ConfirmImportPage grouping") and again at the visual gate.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `agents/triage-reviewer.md` | create | Architect-lens reviewer: design consistency/buildability/completeness + dependency edges (read-only, returns structured findings) |
| `agents/design-reviewer.md` | create | Front-end-designer-lens reviewer: UX gaps/risks on UI-touching issues (read-only, returns structured findings) |
| `skills/triage/SKILL.md` | create | The triage phase: batch (milestone) + single (issue) modes; dispatch reviewers; aggregate; emit all-clear or gap table; post blocker summaries; return the validated dependency graph |
| `skills/solve-milestone/SKILL.md` | modify | Add Phase 0 (invoke `triage`); replace the linear loop with dependency-graph-driven proceed-on-clean / hold-gapped continuation |
| `skills/solve-issue/SKILL.md` | modify | Add step 0 (single-issue triage); redefine `design-cleared`; add STOP (contradictory/risky design) + the new-UI PAUSE / destructive STOP triggers; add the verified-by-other-means E2E escape |
| `agents/implementer.md` | modify | Add `USER-FACING CHANGES` block (`NEW_UI_ELEMENTS`, `DESTRUCTIVE_OPS`) to the report contract |
| `docs/profile-schema.md` | modify | Add `uiSurfaceGlobs`, `triageAgent`, `designReviewAgent` keys + PP example |
| `README.md` | modify | Document the layered gating model + the triage phase + new profile keys |
| `docs/consumer-setup.md` | modify | Note the triage phase and the visual-review gate in the run flow |
| `.claude-plugin/plugin.json` | modify | Version → 1.3.0 (rides in the issue PRs per the existing bump convention) |

No `hooks/` changes. No new mechanical gates.

---

## New agent contract — `agents/triage-reviewer.md` (architect lens)

Frontmatter: `name: triage-reviewer`; `model: inherit`; `color: cyan`; description mirroring `implementer.md`'s style (dispatched by the `triage` skill; read-only; never writes code or posts comments; returns structured findings). System prompt body:

- **Identity:** a staff/architect-level reviewer assessing whether a GitHub issue is *buildable as recorded* — not whether code is written well. Stack-agnostic; the profile + brief carry the stack.
- **Receives:** one issue (number, title, body, acceptance criteria), its recorded design decisions (issue comments / `design-cleared` notes), the milestone description (declared Wave/dependency order), and the profile (`sourceGlobs`, `uiSurfaceGlobs`, `nonNegotiables`). May read the implicated code (read-only) to ground its assessment.
- **Assesses, per issue:**
  1. **Consistency** — is the recorded design internally contradictory? (the #43 failure: "literal ConfirmImport chrome" vs "flat list, no collection picker").
  2. **Buildability** — can it be built exactly as specified without inventing an unrecorded decision?
  3. **Completeness** — do the acceptance criteria cover the needed states/branches/error paths, or are there silent gaps?
  4. **Dependencies** — does it reference a type/file/contract/screen another issue introduces? Emit explicit edges (`#B depends on #A because …`), validating/augmenting the milestone's declared order.
  5. **UI flag** — does it touch a `uiSurfaceGlobs` path (or carry a UI label)? If so, mark `needsDesignReview: true` (the `triage` skill dispatches `design-reviewer`).
- **Returns** (the structured value to the `triage` skill — no prose, no comments posted):
  ```
  ISSUE: <n>
  DEPENDS_ON: [<issue numbers>]   # validated edges, with one-line reasons
  NEEDS_DESIGN_REVIEW: yes | no
  GAPS:
    - lens: architect
      severity: Blocker | Advisory
      type: contradiction | not-buildable | missing-criteria | undeclared-dependency | risky-design
      description: <one line>
      to_clear: <what the human must decide/record to clear it>
    - … (or "none")
  ```
- **Severity rule:** internal contradiction, not-buildable, and undeclared hard dependency are **Blocker**. "Could be better" / non-blocking ambiguity is **Advisory**. When genuinely unsure, escalate to Blocker (mirrors `solve-issue`'s "ambiguous → treat as architecture → STOP").
- **Rigor gate (hard — no hypotheses, no guesses, no low-effort passes):** every finding cites its grounding (the exact contradictory recorded line, or `file:line` for a dependency/contract). A claim you cannot ground in the actual artifact is emitted as a **Blocker** ("cannot verify X from the issue/code"), never as an assumption or a confident guess. An `all clear` is a *positive* check of each acceptance criterion and each dependency — not the absence of an obvious problem. "Looks fine / probably / should be ok," skipping the implicated code, or inventing intent the spec doesn't state are contract violations. The seniority is enforced by this gate, not asserted by the title.
- **Refuses:** writing code, posting issue comments, designing the fix. It surfaces gaps; the human/consumer resolves them.

## New agent contract — `agents/design-reviewer.md` (front-end lens)

Frontmatter: `name: design-reviewer`; `model: inherit`; `color: magenta`; description (dispatched by `triage` for UI-touching issues; read-only; returns structured findings). System prompt body:

- **Identity:** a senior front-end/UX reviewer judging whether a recorded UI design will **produce an acceptable rendered result** — not implementing it. Stack-agnostic (XAML/MAUI, web, native — the brief says which).
- **Receives:** a UI-touching issue + its recorded design + pointers to the existing UI surfaces it neighbors (so it can compare to established patterns), via `uiSurfaceGlobs`.
- **Assesses:** scalability of the design at realistic data volumes (the #43 "flat 16-row list, no grouping" failure); consistency with existing patterns in the same app (e.g., card grouping in `ConfirmImportPage`); missing states (empty / loading / error / disabled); missing affordances (confirm dialog for a destructive action; Save/Cancel; enablement rules); obvious accessibility gaps. Explicitly flags any case where the **approved** design "will produce a poor result" — that is a Blocker, per issue #18's STOP corollary.
- **Spec-sufficiency is the triage gate (no screenshot needed up front):** the question at triage is whether the recorded design is *specified enough to build correctly* — does it state layout/grouping, the key states, the affordances, or name an existing pattern to mirror? **Ample specifics → no gap, the build proceeds** (a screenshot is not required to start). **Absent / vague / self-contradictory specifics → Blocker**, so the human supplies direction before any code is written. Screenshots belong to the post-build gate (Layer 2 / issue #18), never here. Ground every "ample vs insufficient" call in the actual recorded text — do not infer intent the spec doesn't state.
- **Returns:**
  ```
  ISSUE: <n>
  GAPS:
    - lens: design
      severity: Blocker | Advisory
      type: spec-insufficiency | scalability | pattern-inconsistency | missing-state | missing-affordance | accessibility
      description: <one line>
      to_clear: <suggested resolution or reference pattern (e.g. "group under collection headers like ConfirmImportPage")>
    - … (or "none")
  ```
- **Rigor gate (hard — no hypotheses, no guesses, no low-effort passes):** every gap names the actual recorded line and the actual existing pattern it should mirror (cite the file). A UX risk you cannot ground (e.g. a scalability claim with no real data source to point to) is emitted as a **Blocker** ("cannot verify"), never guessed. An `all clear` means you positively checked scalability, states, affordances, and pattern-consistency against the real surfaces — not that nothing jumped out. "Looks fine / probably," not reading the neighboring views, or comparing to an imagined pattern are contract violations.
- **Refuses:** producing the final visual design (that's the human / a consumer designer), writing code, posting comments.

---

## New skill contract — `skills/triage/SKILL.md`

Frontmatter `name: triage`; description triggering on `/milestone-driver:triage <milestone-name | issue-number>`, "triage the milestone/issue", "review for gaps". Body:

- **Purpose:** the pre-build review phase. Reviews issues for design gaps + dependency ordering, emits an all-clear or a gap table, posts a blocker summary on each affected issue, and returns the validated dependency graph. **Authors nothing**; opens no PRs.
- **Announce to the user first:** "Standing by while I review the issue(s) for gaps and dependencies that would need your input before building." (matches the requested UX).
- **Modes:** argument is a milestone name → **batch** (all open issues in the milestone); argument is an issue number → **single**.
- **Procedure:**
  1. Read the profile (`triageAgent` default `milestone-driver:triage-reviewer`; `designReviewAgent` default `milestone-driver:design-reviewer`; `uiSurfaceGlobs`).
  2. Batch mode: read the milestone description for the declared Wave/dependency order (same source `solve-milestone` uses).
  3. Dispatch `triageAgent` per issue (parallelizable). For each issue it returns `NEEDS_DESIGN_REVIEW: yes`, dispatch `designReviewAgent`.
  4. Aggregate: build the validated dependency graph from `DEPENDS_ON` edges; collect all `GAPS`.
  5. **Output to the user:**
     - **All clear** (no Blocker gaps): `✅ All clear` + the Wave-ordered dependency graph + any Advisory notes (one line each).
     - **Gaps:** a table — `| Issue | Lens | Severity | Gap | What's needed |` — Blockers first.
  6. **Comment + label each affected issue** (`gh issue comment <n>`, then apply `needs design` / `needs decision` / `blocked` per the taxonomy, create-if-missing): a brief `🔴 Triage` summary of its Blocker gaps and what's needed to clear them. Blockers live on the originating issue (the "icing") as a durable async handoff — never an interactive prompt.
  7. **Return** (to a calling skill): the validated dependency graph + per-issue `{blockers: bool, advisories: […]}`.
- **Severity → effect:** a Blocker **parks** that issue (the caller applies the label + leaves it open) and the loop moves on; Advisories are logged, not gating.

---

## Edits to existing skills (precise)

### `skills/solve-milestone/SKILL.md`
- **New "Phase 0 — Triage"** before the loop: invoke `triage <milestone>`; present its table/all-clear (blocker comments + labels are already on the issues). Then drive the loop from the **validated dependency graph**, not the raw declared order.
- **Loop continuation (proceed-on-clean / park-and-continue):** for each issue in Wave order, build it **iff** (a) every issue it `DEPENDS_ON` is already merged to `integrationBranch`, **and** (b) it carries no unresolved park label. Otherwise it is **parked** (or held behind an unmerged dependency, labeled `blocked`) and the loop **continues with independent, clean issues** — it never waits on a human. This is what lets UI issues sit as open PRs (#18, `needs review`) without stalling unrelated work.
- **Final summary additions:** issues built; issues **parked** (each with its label + the blocker + the open branch); UI PRs awaiting human merge (`needs review`, #18). The run ended because all issues are done or parked — not because it is waiting.
- **Reframe the existing "Halt on gate" step:** a `solve-issue` STOP/PAUSE no longer halts the whole loop — the issue is parked (label + open branch) and the loop proceeds to the next issue whose dependencies are merged. Only a systemic failure (auth, broken `integrationBranch`, missing tooling) ends the run early.

### `skills/solve-issue/SKILL.md`
- **New step 0 — Triage:** invoke `triage <n>` (single). A returned **Blocker** → **park** the issue (triage already posted the comment): apply the label (`needs design` for a design gap, `needs decision` for a non-design decision), leave it open, do not build. The milestone loop moves on. All-clear or Advisory-only → proceed.
- **`design-cleared` redefinition (in step 2):** `design-cleared` means *a decision was recorded*, **not** that it is correct/buildable. The orchestrator may still **park** a `design-cleared` issue with `needs design` if the recorded design is contradictory or will produce a poor result.
- **New park triggers (Autonomy model):** recorded/locked design is internally contradictory; the orchestrator (or triage) judges the approved design will produce a poor result; a self-noted risk about the **approved** design (e.g. "this list could get long"). Each is a **park** (`needs design` + comment + open branch), **not** silent resolution and **not** an interactive prompt.
- **Layer-1 declaration gates (step 3/6, on the implementer report):**
  - `NEW_UI_ELEMENTS: yes` **and** the issue's acceptance criteria are silent on the element's visual/UX detail → **park** with `needs design`: document the new elements + what direction is needed, preserve the branch, continue. (The human supplies direction and re-runs; there is no mid-run interactive resume.)
  - `DESTRUCTIVE_OPS: yes` **and** the confirmation UX is unspecified → **park** with `needs decision` (a missing confirm flow usually means the plan is incomplete): document, preserve the branch, continue.
- **E2E escape (step 5):** after the existing cap, add — if the suite remains flaky on UI-traversal **but the feature is verified by other means** (DB assertion + attached screenshot), **quarantine** the flaky test, proceed, and log it in the PR's Code Review section + a `judgment call` label. If the feature is **not** otherwise verified → **park** with `blocked` (document the flake + what is unverified). Stack-specific E2E environment fixes stay consumer-side per the profile/`e2eEnv` — the engine adds only this policy.
- **Reframe all existing STOP/PAUSE language** (the root-cause gate, the new-dependency PAUSE, the architecture STOP, and the unit-redispatch / E2E / review caps) to the **park** semantics: comment on the issue + apply the label (`needs decision` / `needs design` / `blocked`) + leave the branch open with the work — then the loop continues. The existing root-cause gate already comments; add the label + open-branch + continue. No path interactively prompts; only a systemic failure halts the run.

### `agents/implementer.md`
- Add to the **Output format** report, after `FILES CHANGED`:
  ```
  USER-FACING CHANGES:
  - NEW_UI_ELEMENTS: yes | no   # a new visible/interactive element, screen, dialog, or form field (not a restyle/reword of an existing one)
  - DESTRUCTIVE_OPS: yes | no    # a user-exposed delete / archive / bulk-update / irreversible state change (not internal cleanup)
  ```
  Plus one contract line: classify honestly; "user-exposed" is the predicate for `DESTRUCTIVE_OPS` (an invisible internal migration is `no`).

### `docs/profile-schema.md` (new keys — justified by consumer #1 PracticingPrayer, per the "real second consumer" rule)
- `uiSurfaceGlobs` — `string[]`, Optional, Triage/Visual tier: globs marking UI surfaces (e.g. `["PrayerApp/Views/**","**/*.xaml"]`); drives `design-reviewer` dispatch and the visual gate (#18). Absent → no design-lens review / no visual gate. **Screenshot capture for the visual gate requires a render capability** declared via `e2eEnv` (or a `screenshotCmd`); when that is absent the gate degrades to PR-open-for-human-test (never fails, never auto-merges UI). Triage itself needs no render capability — it reviews recorded design + source.
- `triageAgent` — `string`, default-filled `milestone-driver:triage-reviewer` (mirrors `implementerAgent`).
- `designReviewAgent` — `string`, default-filled `milestone-driver:design-reviewer`.

---

## Label taxonomy (autonomous async handoff)

A park applies a comment **plus** a label; the human reviews by label after the run. There is no single official GitHub status-label standard (GitHub's defaults carry none), so these use the widely-used community conventions. The plugin **provisions them (create-if-missing)** in the target repo — consumer repos won't have them.

| Label | Meaning | Applied when | Cleared by |
|---|---|---|---|
| `in progress` | Branch open with partial/parked work | An issue's branch has commits but it isn't done (incl. a mid-work park) | Merge / further work |
| `blocked` | Can't proceed; waiting on something external | Held by an unmerged dependency; E2E-unverified park | The blocker clears |
| `needs design` | Design direction required before building | Triage/design Blocker (insufficient/contradictory design); silent-criteria new UI | Human records the design on the issue |
| `needs decision` | Non-design human decision required | New dependency; destructive-op confirm UX; architecture call | Human records the decision |
| `needs review` | Built; awaiting human review/merge | UI PR open awaiting visual sign-off (incl. the no-render path) | Human reviews + merges |
| `judgment call` | Borderline autonomous call — audit it | An in-scope autonomous decision worth post-run review (the existing `⚠ judgment-call`) | Human audits post-run |

A parked issue carries one *blocker* label (`blocked` / `needs design` / `needs decision`), plus `in progress` if a branch exists; `judgment call` and `needs review` are orthogonal. Labels are applied idempotently (create-if-missing), so re-runs never duplicate them.

## Issue decomposition (milestone 1.3.0)

Waves are the dependency order recorded in the milestone description (the `solve-milestone` ordering source of truth). Within a Wave, issues are independent and parallelizable.

| # | Issue (proposed title) | Wave | Depends on | Touches |
|---|---|:--:|---|---|
| A | feat(profile): add `uiSurfaceGlobs`, `triageAgent`, `designReviewAgent` keys | 1 | — | `docs/profile-schema.md`, PP profile |
| B | feat(agents): add bundled `triage-reviewer` (architect-lens) agent | 1 | — | `agents/triage-reviewer.md` |
| C | feat(agents): add bundled `design-reviewer` (front-end-lens) agent | 1 | — | `agents/design-reviewer.md` |
| D | feat(implementer): declare `NEW_UI_ELEMENTS` / `DESTRUCTIVE_OPS` in the report | 1 | — | `agents/implementer.md` |
| E | feat(skill): add the `triage` skill (batch + single, gap table, blocker comments + labels, dependency graph) | 2 | A, B, C, J | `skills/triage/SKILL.md` |
| F | feat(solve-milestone): Phase 0 triage + dependency-graph proceed-on-clean / park-and-continue loop | 3 | E, J | `skills/solve-milestone/SKILL.md` |
| G | feat(solve-issue): step 0 triage; redefine `design-cleared`; design-gap parks (`needs design`/`needs decision`); E2E verified-by-other-means escape | 3 | D, E, J | `skills/solve-issue/SKILL.md` |
| H | feat(solve-issue): visual-review gate for UI issues (screenshots, PR-open, auto-merge opt-in) — **existing #18** | 4 | A | `skills/solve-issue/SKILL.md` |
| I | docs(1.3.0): document the layered gating model, triage phase, and new profile keys | 5 | A–H, J | `README.md`, `docs/consumer-setup.md` |
| J | feat(setup): provision the label taxonomy (create-if-missing) + apply-time label helper | 1 | — | `skills/setup/SKILL.md` |

**Acceptance criteria per issue** (the executable contract; `solve-issue` writes the bite-sized plan):

- **A** — schema doc lists the three keys with tier/required/description + a PP example using `uiSurfaceGlobs`; honors the "added because consumer #1 needs them" note; `triageAgent`/`designReviewAgent` documented as default-filled like `implementerAgent`. Profile JSON still parses.
- **B** — `agents/triage-reviewer.md` exists with the frontmatter + contract above; returns the specified structured block; explicitly read-only and never posts comments. `claude plugin validate` passes.
- **C** — `agents/design-reviewer.md` exists with the contract above; read-only; severity rule includes "approved design will produce a poor result = Blocker". `claude plugin validate` passes.
- **D** — implementer report contains the `USER-FACING CHANGES` block with both fields + the honesty/predicate line; existing report sections unchanged.
- **E** — `triage` skill: handles milestone-name (batch) and issue-number (single); dispatches `triageAgent` then `designReviewAgent` (only when `NEEDS_DESIGN_REVIEW`); emits `✅ All clear` + graph, or the `| Issue | Lens | Severity | Gap | What's needed |` table; posts a `🔴 Triage` comment per affected issue; returns the dependency graph; authors no code, opens no PR. **Dry-run (real artifact, not a reconstruction):** against the actual `kenmulford/PracticingPrayer` #43 design + its recorded comments, triage returns a Blocker naming the recorded contradiction (intent "mirror ConfirmImport grouping" vs the "flat list, no collection picker" sub-decision). If #43 can't be retrieved at execution, STOP — do not fabricate a stand-in.
- **F** — `solve-milestone` invokes `triage` as Phase 0 and orders the loop by the validated graph; builds an issue only when its dependencies are merged and it has no park label; **parks** blocked issues (+ transitive dependents) and **continues with clean issues — never waits on a human**; final summary lists parked issues (with labels) and open UI PRs.
- **G** — `solve-issue` invokes single-issue `triage` at step 0 (Blocker → **park** with the right label); `design-cleared` redefined; the three new **park** triggers + the two declaration gates (park with `needs design`/`needs decision`) present in the Autonomy model; E2E verified-by-other-means quarantine escape with the "not-otherwise-verified → **park** (`blocked`)" guard. No path interactively prompts the operator.
- **J** — `setup` (and an apply-time helper the skills call) ensures the six taxonomy labels exist in the target repo via idempotent create-if-missing; names/colors match the taxonomy; the existing `⚠ judgment-call` is reconciled to `judgment call`; re-runs create no duplicates. E/F/G/triage consume this — it is a Wave-1 foundation.
- **H** (#18) — for `uiSurfaceGlobs`-touching issues: screenshots (light+dark) attached to the PR **when a render capability is configured** (`e2eEnv`/`screenshotCmd`); PR opened but **not** auto-merged; auto-merge becomes opt-in per issue class (logic-only auto-merges, UI issues await human merge); inconsistent `design-cleared` already a STOP (lands via G). **No-render degradation:** when capture capability is absent, the gate does **not** fail and does **not** auto-merge — it leaves the PR **open** with a posted note that visual evidence is unavailable and a human visual test is required before the merge to `integrationBranch`. The screenshot is convenience evidence; the human-before-merge checkpoint holds either way. (Consumers with no `uiSurfaceGlobs` have no UI issues and auto-merge normally.)
- **I** — README gate section documents the three layers + triage; consumer-setup notes the triage phase and visual gate in the run flow; profile-schema cross-linked; `plugin.json` at 1.3.0.

**Proposed milestone 1.3.0 description (ordering source of truth):**
> **1.3.0 — Proactive triage & design-gap gating.** Front-load a software-architect + front-end-designer review of each issue for design gaps and dependency ordering before building; drive the loop from the resulting dependency graph; backstop with implementer surface-declarations, a post-build visual-review gate, and a verified-by-other-means E2E escape.
> **Wave 1 (parallel, no deps):** #A profile keys · #B triage-reviewer agent · #C design-reviewer agent · #D implementer declarations · #J label provisioning.
> **Wave 2:** #E triage skill (needs A, B, C, J).
> **Wave 3 (parallel):** #F solve-milestone integration (needs E, J) · #G solve-issue integration (needs D, E, J).
> **Wave 4:** #H visual-review gate / #18 (needs A).
> **Wave 5:** #I docs + 1.3.0 (needs all).

---

## Verification model (this repo)

No unit-test harness exists; recent history is `docs(...)` commits. Verification per issue is structural:
1. `claude plugin validate . --strict` after agent/skill/manifest edits.
2. JSON parse of any edited JSON (`plugin.json`, profile examples).
3. Cross-file consistency (the same key/field/agent name used everywhere it's referenced — e.g. `triageAgent` default matches the bundled agent's `name`).
4. `/code-review` before each commit (per repo convention; the mandatory PR `## Code Review` section).
5. **Behavioral dry-run for E (grounded on the real artifact):** run `triage` against **`kenmulford/PracticingPrayer` issue #43** (verified OPEN, milestone 1.5.0) and its recorded design comments; confirm it flags the recorded contradiction as a Blocker and posts the comment. If #43 cannot be retrieved at execution, STOP — do not fabricate a stand-in scenario.

## Self-review (against the spec)

- Spec coverage: run feedback #1 → H(#18); #2 → B/E/G (`design-cleared` redefinition + contradiction Blocker); #3 → F (dependency-graph loop) + H (auto-merge opt-in); #4 → G (verified-by-other-means escape; env fixes stay consumer-side); #5 → H + B/C. Peer recs: implementer declarations → D + G; gate-before-merge generalized to gate-before-build → E/G; dependency tension → F via the graph. ✅ all mapped.
- Type/name consistency: `triageAgent`→`triage-reviewer`, `designReviewAgent`→`design-reviewer`, `uiSurfaceGlobs` used identically in A, E, H; report fields `NEW_UI_ELEMENTS`/`DESTRUCTIVE_OPS` identical in D and G. ✅
- No placeholders: agent + skill contracts are fully specified above; per-issue bite-sized steps are intentionally deferred to `solve-issue` (this repo's own mechanism) rather than duplicated here where they'd go stale.

## Out of scope (explicitly)

- Stacked branches for dependent-issue parallelism (premature; 0 use cases).
- Stack-specific E2E environment fixes (Debug-seed build, emulator storage, Appium shim, AutomationId) — these stay in PracticingPrayer's `run-uitests.ps1` + `e2eEnv`, not the portable engine.
- A `gatingPosture` dial / N independent gate toggles — the selective-by-default triage + `uiSurfaceGlobs` already deliver the "reasonable medium"; add knobs only when a second consumer demonstrates a divergent need (per the profile's anti-speculative-expansion rule).
