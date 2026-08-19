---
name: solve-milestone
argument-hint: <milestone-name | milestone-number>
description: >-
  This skill should be used when the user invokes "/milestone-driver:solve-milestone <name>", or asks to "solve a milestone", "drive a milestone", or "work the milestone autonomously". Iterates every issue in a GitHub milestone in dependency order via /milestone-driver:solve-issue, re-syncing the integration branch between issues. Runs unattended: parks blocked or gapped issues and continues; only a systemic failure ends a run early. Builds mutually-independent issues within a Wave concurrently in git worktrees by default; a run-start barrier check drops to sequential only when a barrier is present.
---

# solve-milestone — autonomous driver

Order a milestone's issues, run `/milestone-driver:solve-issue` on each, integrate to `integrationBranch` between issues. Owns **ordering, the loop, branch re-sync, parking, the final summary**; `solve-issue` owns the per-issue pipeline.

**Coherence pass** (`coherenceReviewAgent`, read-only, never gates). Runs per-issue in `solve-issue` section 6, before that issue's `/code-review`. Under **wave granularity** it runs instead at the Phase-2 merge-tail re-verify point (`skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 2: serial verified merge tail`), against the integrated wave. Absent → skip silently.

**Blast radius.** Merge only to `integrationBranch`, never `protectedBranch`. Release, **closing the milestone object**, and deploy are human-only. This skill closes the milestone's **issues** and authors the CHANGELOG; never the **milestone**.

**Execution mode: parallel by default.** No flag, no opt-in. Resolved **once** at run start by the barrier cascade in the last Before-starting step (**Resolve execution mode**), then held all run. A typed `--parallel`, or "in parallel", in `$ARGUMENTS` is stripped and ignored by step 3's `--<token>` strip.

## Contents

Before starting · The procedure — 1. List the milestone's open issues · 2. Determine the order · 3. Determine the target version · Phase 0 — Triage · 4. Loop over issues in dependency-graph order · Permission pre-flight gate · 5. Finish · Autonomy · Output spec — Template 1 — Run start / plan board · Template 2 — Status update at each wave boundary · Template 3 — Final results · Output style · Final summary — 6. Author the CHANGELOG entry · Run-complete notification

## Before starting

1. **Auth preflight.** Run `gh auth status`. Non-zero exit, or output containing "not logged in" / "authentication failed" → print `Error: gh auth status failed — authenticate with 'gh auth login' before running solve-milestone.` and **halt**.
2. Read the profile (`docs/profile-schema.md`).

   | Decision point | Behavior |
   |---|---|
   | Resolution order (READ only; no migration here) | `<repo>/.milestone-config/driver.json`, else legacy root `<repo>/milestone-driver.json`. Both present → `.milestone-config/driver.json` wins; no move, no overwrite, no deletion of the leftover. |
   | Migration (`git mv`) of a legacy layout | Never on this orchestrator's own working tree. The **first dispatched `solve-issue`** performs it on its feature branch at step 3.5. An all-parked milestone defers it to the next building run; the transitional READ covers the gap. |
   | Neither file exists, or `integrationBranch` / `protectedBranch` / `sourceGlobs` missing | Invoke `milestone-driver:setup`, then continue. Do **not** fail. |
   | `implementerAgent` | Defaults to `milestone-driver:implementer`. |
   | Optional keys — `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `domainSkills`, `nonNegotiables` | Their steps skip cleanly when absent. |
   | `integrationGranularity` / `visualHold` (resolve BOTH here, once, hold all run) | Absent → `"issue"` and hold. **Fail-open, never a hard error:** an out-of-enum `integrationGranularity` degrades to `"issue"`, logging `integrationGranularity "<value>" is not one of "issue", "wave", "milestone", degraded to "issue"`; a non-boolean `visualHold` degrades toward holding, logging `visualHold "<value>" is not a boolean, degraded to holding the milestone PR`. A valid value logs nothing. Every later read uses the resolved value. |

   2.0.5. **Self-heal the scratch-ignore** — always, before any `.milestone-config/` scratch write. That directory also holds **tracked** config (`driver.json`, `feeder.json`): never blanket-ignore it, never add a `*` or `/` rule. Ensure a **committed** `.milestone-config/.gitignore` carrying the block below — absent → `mkdir -p .milestone-config` and write it; present → do nothing. The first dispatched `solve-issue` commits it alongside the migration.

      <!-- KEEP THIS BLOCK IN SYNC with the committed .milestone-config/.gitignore in this repo and with solve-issue / scripts/triage-cache.{sh,ps1} / hooks/tests-green.{sh,ps1}, feeder setup / plan. -->
      ```gitignore
      # milestone-driver / milestone-feeder per-clone scratch — git-invisible by default.
      # Committed so per-run scratch stays out of `git status` with zero user setup.
      # Patterns are relative to this .milestone-config/ directory. Tracked config
      # (driver.json, feeder.json) is intentionally NOT listed, so it stays tracked.
      preflight-notice
      trello-notice
      visualcapture-notice
      parallel-default-notice
      code-review-gate-notice
      aiprefilter-notice
      cost-record-notice
      uisurfaceglobs-notice
      triage-cache.json
      tests-stamp
      .runtime/
      worktrees/
      ```

   2.1. **One-time notices.** Immediately after the profile read: read `${CLAUDE_PLUGIN_ROOT}/skills/notices.md` and, in file order (= print order), evaluate each section whose `Skills` field includes `solve-milestone`, applying its `Trigger` → `Text` → `Marker` → `Legacy fallback` mechanics exactly as stated there.
3. **Resolve the milestone argument.** Strip flags from `$ARGUMENTS`: a flag is a token starting with `--`. Remove each `--<token>`, plus the following token when it does not start with `--` AND the flag is value-bearing (`--parallel` and `--driven` are boolean — strip the flag alone; any other `--<token>` followed by a non-flag token counts as value-bearing, strip both). Then:
   - **Purely numeric** (digits only): `gh api repos/{owner}/{repo}/milestones/<milestone-number> --jq '{number, title}'`. Found → record the canonical `{number, title}`, state `"Resolved milestone #<milestone-number> → '<title>'"`. Not found → print the available-milestones table and stop.
   - **Otherwise (title):** `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | select(.title=="<name>") | {number, title}'`. Found → record it, state `"Resolved milestone '<title>'"`. Not found → stop the same way.
   - **Numeric-title halt.** Resolved title purely numeric → **halt and prompt the human**; do not proceed to Phase 0. Triage reads a bare number as single-issue mode, so a purely-numeric milestone *title* must be renamed to a non-numeric one before this skill can drive it unattended.
   - **Available-milestones table** (error path): `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | [.number, .title] | @tsv'` as a Markdown table with columns `#` and `Title`.

   All downstream steps use the resolved `{number, title}`; do NOT re-read `$ARGUMENTS`.
   **3.5** `integrations.trello` present → read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/trello-sync.md` and run its run-start card resolution (best-effort; a Trello failure never blocks the run).
   **3.6 Cherry-pick check for a milestone under a parent group.** Fires only when `--driven` (step 5) is absent; when present, none of it runs — not the first-issue query, not the parent lookup. When absent:

      a. **Find the milestone's first issue** — lowest issue number, `--state all` so a fully-built milestone stays inspectable: `gh issue list --milestone "<resolved-title>" --state all --json number --jq 'sort_by(.number) | .[0].number'`. Nothing returned → fall through to step 4.
      b. **Read that issue's parent, checking `md-epic` in the same call:** `gh api repos/{owner}/{repo}/issues/<first-issue>/parent`. 404 → no parent. Any other successful response already includes `.labels` — check those for an exact `md-epic` match, no second call. A **non-404 failure** (auth, 5xx, network) is systemic, not "no parent" — surface it and halt per `## Autonomy`.
      c. **No parent, or a parent without `md-epic`** → fall through to step 4, no prompt.
      d. **A parent carrying `md-epic`** → read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/md-epic-parent-check.md` and run it: the three-option prompt (build just this milestone · hand off to `/milestone-driver:solve-issue <parent-number>` · pause), each option's branch, and the reactive-only out-of-order note. Reached on no other path.
4. Confirm the working tree is clean and the local `integrationBranch` is current (`git fetch`, fast-forward).
5. **Resolve execution mode (the LAST Before-starting step).** Resolve **once**, here; hold all run. Evaluate the cascade **top-down; first match wins**:

   **The `--driven` token.** An **interpreted token, not a parsed CLI flag** — recognized by string presence in the invocation text, never argument parsing. No human types it; an internal caller supplies it when dispatching this skill on its own behalf. It gates **only row 4 (the DB-hazard interview)**: a driven run takes row 4′ instead of prompting. **Every other Before-starting prompt is unaffected** — step 3's numeric-title halt still halts and prompts on a driven run.

   | # | Condition | Resolved mode | Dispatch | Surfacing |
   |---|---|---|---|---|
   | 1 | profile `parallel: false` | **sequential** | background leaf dispatch ok if the gate passes, else synchronous | quiet — standing opt-out |
   | 2 | permission-allowlist gap (`### Permission pre-flight gate`) | **sequential** | **synchronous** | 🔴 gap table + recommend `/fewer-permission-prompts` |
   | 3 | profile `parallel: true` | **parallel** | background | quiet — asserted safe |
   | 4 | `unitTestCmd` set AND `parallel` absent AND **interactive** | **interview → user's choice**, persisted to `parallel` | per choice | 🔴 up-front prompt (below) |
   | 4′ | same as row 4 but (`MILESTONE_DRIVER_NONINTERACTIVE=1` OR `--driven` present) | **sequential** | background leaf dispatch ok if the gate passes, else synchronous | loud `⚠` note + how to set `parallel: true`; **no persist** |
   | 5 | otherwise | **parallel** | background | quiet — default |

   **The permission pre-flight gate runs here, once** (`### Permission pre-flight gate`): a gap → synchronous dispatch + sequential mode (row 2); no gap → background dispatch is available and the cascade continues. The in-loop references (`sequential-loop.md` step 2, `parallel-waves.md` Phase 1 step 3) **read this decision**; the gate never re-fires mid-loop.

   **DB-hazard interview (row 4).** Trigger: `unitTestCmd` set AND `parallel` absent — the **only** trigger. Fire **once**, here, before Phase 0: read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/db-hazard-interview.md` and run it — the prompt, the Yes/No branches and their `parallel: true` / `parallel: false` writes to `.milestone-config/driver.json`, the persistence rule, and the row-4′ path (`MILESTONE_DRIVER_NONINTERACTIVE=1` OR `--driven`), which does not prompt, falls to sequential **with a loud note**, and persists nothing. On any other row it is **never read**.

      **Nothing to decide:** `parallel` absent AND `unitTestCmd` absent → row 5 → **parallel**, quiet; no interview, no persisted value.

   **Surface the resolved mode** and its reason; it drives Template 1's mode line.

   **5.1 Remediate handoff — the run-start question.** Is `/milestone-feeder:remediate` resolvable in this session? **Not resolvable** → no question, one log line, silent degrade; the file is **never read**. **Resolvable** → read `${CLAUDE_PLUGIN_ROOT}/skills/remediate-handoff.md` and run its `## The run-start question` verbatim — asked ONCE here, held all run, never re-asked per issue. `MILESTONE_DRIVER_NONINTERACTIVE=1` → do not ask: take that file's non-interactive default with a loud `⚠` note (`--driven` does not gate this). Never copy that file's procedure here.

## The procedure

### 1. List the milestone's open issues

`gh issue list --milestone "<resolved-title>" --state open`, using the title resolved in Before-starting step 3.

### 2. Determine the order

The **milestone description is the ordering source of truth**. Read it (`gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '.description'`, else `gh api "repos/{owner}/{repo}/milestones?state=all" --jq '.[] | select(.title=="<resolved-title>") | .description'`) and follow the Wave / dependency sequence it records. No explicit order → fall back to ascending issue number and **state that assumption explicitly** in the run output.

### 3. Determine the target version

Read `versioning`. **`versioning: false`** → skip this step; record "version-free run — no version determined or bumped" and proceed to Phase 0.

**Otherwise** (`true` or absent) → read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/version-target.md` and run it: the deterministic extractor `${CLAUDE_PLUGIN_ROOT}/scripts/extract-version.{sh,ps1}` (never parse by judgment), its result × `versioning` branch table (versioned / version-free with a logged reason / prompt), its fail-open behavior, the `MILESTONE_DRIVER_NONINTERACTIVE=1` degradation, and where the target is consumed. Hold that target for the loop. Under `versioning: false` it is **never read**.

### Phase 0 — Triage

Invoke triage across the milestone before the build loop:

```
/milestone-driver:triage <resolved-title>
```

(Pass the resolved title — triage's bare-number path means single-issue mode.)

1. **Present triage output.** Surface the all-clear or gap table; triage's output carries the Wave-ordered dependency graph either way.

2. **Apply triage-recommended park labels.** Triage posts the `🔴 Triage` comment but applies no labels; that is this skill's job. For every issue where `issueStates[n].blockers == true`, apply its `issueStates[n].label` (`"needs design"` or `"needs decision"`) with the apply-time label helper from `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` Phase 4, using that taxonomy table's hex color and description. Where `issueStates[n].clearLabel == true` instead, remove the one park label the issue live-carries and add none (`skills/triage/blocker-resolver-dispatch.md (Unparking)`):

   ```
   gh label create "<name>" --color <hex> --description "<desc>" --force
   gh issue edit <n> --add-label "<name>"
   gh issue edit <n> --remove-label "<name>"     # clearLabel == true
   ```

   Under a held **Auto** answer, every issue parked here enters the `## The Auto loop` in `${CLAUDE_PLUGIN_ROOT}/skills/remediate-handoff.md` before step 3 — same gated read-direct, on this main line, cap 1 per issue per run; a `NEEDS_HUMAN` return or a still-dirty re-triage parks for good (`skills/remediate-handoff.md (Park for good)`).

2.5. `integrations.trello` configured → run trello-sync.md `## Phase 0 hooks` (best-effort).

3. **Seed the build queue.** Carry triage's full `dependencyGraph` and `issueStates` into the loop; the loop drives from the validated graph, not the raw declared order.

### 4. Loop over issues in dependency-graph order

**Mode branch point.** In **parallel** mode: read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/parallel-waves.md` and run its Wave loop — `parallel-waves.md § Parallelizable-set selection (parallel mode)`, then `§ Parallel mode — Phase 1: concurrent stage dispatch`, `§ Parallel mode — Phase 2: serial verified merge tail`, `§ Integration granularity (issue vs wave)` — instead of the sequential build steps below. Never silently degrade to sequential. In **sequential** mode it is **never read**.
- **Granularity branch point** (orthogonal to the mode branch). Under `integrationGranularity: "milestone"`, read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/milestone-granularity.md`: `§ Branch model` and `§ Folding an issue into the milestone branch` own condition (a) and every re-sync below; `§ Creating the milestone branch` cuts `milestone-<number>-<slug>` from `integrationBranch` here, **before any issue branch**. Every issue branch this run is cut from it; nothing reaches origin until milestone end. Under `"issue"` **never read**; under `"wave"` only where cited.

Create one TodoWrite item per issue. Process issues Wave by Wave; within a Wave, mutually independent issues may be taken in any order. For each issue, determine whether it is **buildable this pass** — iff ALL THREE hold:

- **(a)** every issue in `dependencyGraph.edges["<n>"]` (those this issue directly DEPENDS_ON) is already merged to `integrationBranch`, or, under `integrationGranularity: "milestone"`, carries its `Issue: #<n>` trailer on the milestone branch (`milestone-granularity.md § Resume and buildability from the trailer`); **AND**
  - Before (b): where (a) holds and `edges["<n>"]` is non-empty, read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/blocked-label-clear.md` and run it.
- **(b)** the issue currently carries **no blocker label** — check live: `gh issue view <n> --json labels --jq '[.labels[].name]'`, confirming none of `needs design`, `needs decision`, `blocked` is present. This live check is the **authoritative park-state**. A labeled issue must not be rebuilt until a human (or Phase 0's Auto remediate loop) clears the label; **AND**
- **(c)** `issueStates[n].blockers == false`.

**If buildable:** read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/sequential-loop.md` and run its per-issue build steps 1–4 (re-sync the build target → run `solve-issue <n>` in-thread with the held values restated → park-and-continue on STOP/PAUSE → on-success terminal states, trello tick, milestone-granularity fold). In parallel mode it is **never read**.

**If not buildable** (triage-parked, live-label park, or dependency not yet merged): read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/not-buildable.md` and run it — the park-label back-fill and `in progress` marking for a triage/prior-run park (with the one-blocker-label-per-issue rule), and, for a dependency hold, the `blocked` label plus the byte-fixed `🔴 Blocked` comment and the transitive-dependent holds. Both modes read it when an issue is not buildable.

The loop **never waits on a human**. Every issue ends merged, **held at the visual-review gate** (an open `needs review` PR on a UI issue), or parked (labeled, branch open if applicable, comment posted). Comment provenance: triage parks carry Phase 0's `🔴 Triage` comment; build-time STOP/PAUSE parks the reason posted at the park step (`sequential-loop.md` step 3c); dependency holds the `🔴 Blocked` comment (`not-buildable.md`).

In **versioned mode** the **first issue's PR** sets `plugin.json` to the target version; every later PR is idempotent. In **version-free mode** no PR carries a version change.

### Permission pre-flight gate

**Runs once per run, at run-start mode resolution (row 2 above), before any dispatch — whenever background dispatch is about to be used.** The mode cascade and the loop **read** its result.

**Allowlist source.** Union `permissions.allow` from all three settings layers; absent or unreadable layers are skipped in the union, not counted as gaps:

| Priority | File |
|---|---|
| 1 | `~/.claude/settings.json` (user global) |
| 2 | `.claude/settings.json` (project) |
| 3 | `.claude/settings.local.json` (project local) |

<!-- KEEP THIS BLOCK IN SYNC with skills/solve-issue/permission-preflight.md § Tool surface and response, its second copy. -->
**Pipeline tool surface.** The union must cover at minimum:

| Tool category | Required grants |
|---|---|
| Read-only gh ops | `gh pr list`, `gh issue view`, `gh issue list` |
| Git | `git commit`, `git push` |
| PR / issue writes | `gh pr create`, `gh pr merge`, `gh pr edit`, `gh pr comment` |
| Issue management | `gh issue edit`, `gh issue comment`, `gh issue close` |
| Label management | `gh label create` |
| Profile-defined commands | Each command in `unitTestCmd`, `preflightCmd`, `e2eTestCmd` (skip if absent) |

**Gap detection and response.** No gaps → proceed with background dispatch. **Gap detected** (the union misses part of that surface, or no layer is readable) → do **not** dispatch in the background: (1) surface a 🔴 gap table naming each missing grant and which settings layer(s) could supply it; (2) **fall back to synchronous dispatch for this run**; (3) recommend the consumer run `/fewer-permission-prompts` (see `docs/consumer-setup.md`). That result holds for the rest of the run — do not re-read settings per issue.

**Auto-deny handling.** A background leaf reporting an auto-deny it could not work around is a **park**: post a `blocked` comment naming the denied tool, apply `blocked` (+ `in progress` if the branch has commits), preserve the branch, continue.

### 5. Finish

The run ends when no buildable issues remain.
`integrations.trello` present → apply `## Finish hooks` from `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/trello-sync.md` (best-effort; skipped updates surface in the final summary).

## Autonomy

- **Unattended between systemic failures.** Operate autonomously within an explicit `/milestone-driver:solve-milestone` run. A `solve-issue` STOP or PAUSE **parks** that issue (label + open branch + comment) and the loop continues.
- **Systemic failures that halt the run** (examples): `gh auth` failure, a broken or inaccessible `integrationBranch`, missing required tooling (`gh`, `git`), and **any reference file this skill read-directs being missing or unreadable once its condition has fired** — `parallel-waves.md`, `milestone-granularity.md`, `blocked-label-clear.md`, `sequential-loop.md`, `not-buildable.md`, `md-epic-parent-check.md`, `version-target.md`, `db-hazard-interview.md`, `changelog-authoring.md`. Best-effort integrations (`trello-sync.md`, `coherenceReviewAgent`) degrade silently instead. These are conditions where no further issue can make progress: surface the failure, leave the working tree clean and all in-flight issues parked, present the final summary and stop — `## Run-complete notification` emits `🚨 Run halted — <reason>`.
- **Architecture is locked** per issue at its plan-approval time. A plan proven wrong is a park (STOP → park + continue), not a silent redesign. For architecture vs implementation detail, see `solve-issue`'s Autonomy model.
- **Never escalate scope to `protectedBranch`.** No PR, push, or merge targets `protectedBranch`.

## Output spec

<!-- KEEP THIS ICON LEGEND BYTE-IDENTICAL across solve-issue and solve-milestone. -->
**Icon legend:** ✅ merged · 🔨 building · ⏭️ queued · ⏸️ parked · 👁️ awaiting visual review · ⚖️ judgment call · 🔴 Your move

### Template 1 — Run start / plan board

Show after Phase 0 triage completes.

```text
🚀 Milestone v[version] — [N] issues · [W] waves · [resolved mode: parallel | sequential (<reason>)] · ~[T]–[T2] min
   develop ← integration PRs · profile: <H> heavy / <L> light

| Wave | Issue | Title                    | Risk  | UI | Status      |
|------|-------|--------------------------|-------|----|-------------|
| 1    | #201  | Background wave dispatch | heavy | —  | 🔨 building |
| 2    | #203  | Status board templates   | light | 👁️  | ⏭️ queued   |

⏸️ Parked at triage: #202 — needs design (contradictory grouping spec)
▶ Wave 1 dispatched — the floor is yours.
```
Mode cell: `parallel`, or `sequential (<reason>)` where `<reason>` ∈ { `profile parallel:false`, `permission gap — see 🔴`, `test-isolation not confirmed` }.

### Template 2 — Status update at each wave boundary

Show after each Wave completes.
<!-- Structural mirror of solve-issue Template 2; keep column schema (Issue/Result/Gates/PR/Note) in sync. -->

```text
🌊 Wave [N] done · [T] min · milestone [done]/[total] ✅

| Issue | Result    | Gates            | PR   | Note                    |
|-------|-----------|------------------|------|-------------------------|
| #201  | ✅ merged | 🧪✓ 🔍✓(2 fixed) | #301        | ⚖️ quarantined flaky E2E |
| #202  | ⏸️ parked | —                | [#pr | —]   | needs decision: new dep  |

▶ Next: Wave 2 (#203 👁️, #204) — redirect or reprioritize before it lands.
```
PR cell: the PR number if the issue has one, else —.
Note cell: an issue the run sent through the Auto loop records its outcome there — `remediated, cleared` (re-triage clean, label cleared), `remediated, still parked` (cap spent or re-triage still dirty), or `NEEDS_HUMAN, parked` (`skills/remediate-handoff.md (Park for good)`); Result still shows the state the pipeline reached. No Auto loop → the cell is unchanged.

Gates legend: 🧪 = unit suite · 🔍 = code review · 🌐 = E2E

### Template 3 — Final results

The layout for `## Final summary` below; fill the metadata lines from that section's requirements.

```text
🏁 v[version] complete · [T] min · ✅ [M] merged · 👁️ [U] open · ⏸️ [P] parked

| Issue | Outcome   | PR          | Follow-up                                  |
|-------|-----------|-------------|--------------------------------------------|
| #201  | ✅ merged | #301        | —                                          |
| #203  | 👁️ open   | #303        | render + merge (light/dark shots attached) |
| #202  | ⏸️ parked | [#pr | —]   | clear `needs decision` (new dep)           |

Judgment-call PRs: [list or "none"]
PRs missing Code Review section: [list or "none"]
Auto-resolved conflicts: [list or "none"]
Per-wave sizes: Wave 1 · [N] issues · [T] min | Wave 2 · …

🔴 Your move:
1. Review & merge each open PR (👁️ rows above) — visual sign-off; check ⚖️ judgment-call PRs too
2. Clear park labels → re-run
3. All merged → merge `integrationBranch` → `protectedBranch` with `--merge` (not squash), merging the release PR *before* tagging, then **back-merge `protectedBranch` → `integrationBranch`** (history-only, conflict-free) so `integrationBranch` stays tag-current and topologically even, close the milestone (`gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed`), deploy — full ordered runbook in `docs/consumer-setup.md` § "Releasing to your protected branch"
```
PR cell: the PR number if the issue has one, else —. Follow-up cell: the same auto-remediate outcome Template 2's Note cell records.

## Output style

Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` — this plugin's output contract. `## Terminal output` governs what this skill prints (including the `## Output spec` template rule); `## GitHub-facing prose`, `## When prose is the correct form`, and `## Evidence slots` govern every issue comment, PR body, and CHANGELOG entry it writes.

Read `${CLAUDE_PLUGIN_ROOT}/skills/citation-format.md` — the one format every citation in those slots takes.

## Final summary

Use Template 3 as the layout. On completion or systemic-failure halt, report:

- **Issues built and merged** to `integrationBranch`, with PR links.
- **Issues parked** — per issue: number and title, the park label applied, the blocker reason, the auto-remediate outcome when the run attempted the Auto loop, and the open feature branch if applicable. Take the reason from the run's tracked context (the triage gap, the STOP/PAUSE reason, or the unmerged upstream). Not in active context → read `gh issue view <n> --json comments` and use the most recent format-matching comment, possibly from a prior run: one opening with `🔴 Triage` (triage-park), `🔴 Blocked` (dependency-hold), or `🔴 Parked` (build-park). gh returns comments oldest-first, so take the LAST match. No anchored match → report "park reason not recorded (pre-1.7.0 park format)". Never invent a reason.
- **Open UI PRs** awaiting human merge: those carrying `needs review`, with PR links.
- **PRs carrying a `judgment call` label**, flagged for post-run review.
- **PRs missing a `## Code Review` section**, flagged the same way, for review before the `integrationBranch` → `protectedBranch` merge.
- **Auto-resolved-conflict issues** (parallel mode) — those whose merge conflict the serial verified merge tail auto-resolved, for a human to sanity-check.
- **Per-Wave parallel-set sizes** (parallel mode).
- **The run ended because** no buildable issues remain — not because it is waiting on a human.
- The next human step: review parked issues and the open `needs review` PRs; clear park labels once their blockers are resolved and re-run for the rest; all work merged → run Template 3's `🔴 Your move:` item 3 verbatim, then deploy manually.

**Output ordering (clean-completion path only):** do not emit Template 3 until step 6 completes (`skills/solve-milestone/changelog-authoring.md § 6.9 Surface in the final summary "Your move" section`). On the systemic-halt path step 6 is skipped — emit Template 3 immediately.

### 6. Author the CHANGELOG entry

**Runs on the CLEAN COMPLETION PATH ONLY.** When the systemic-halt path reaches the Final summary, skip this step and go straight to `## Run-complete notification`.

**Guard — skip this step entirely if** either holds:

- The parked count for this run is greater than zero, OR
- The run ended via a systemic halt

The parked count comes from this run's **in-context tracking** — every issue that did not reach "merged" or "held at visual-review gate": parked at build time, skipped on triage blockers, AND excluded by the buildability check on a live blocker label (e.g. `blocked` from a prior run). It is Template 3's `⏸️ P` count. Do NOT re-derive via a live `gh issue list` query, which may find labels unrelated to this run.

Either condition holding → post _"Skipping CHANGELOG authoring — run did not fully complete (N parked)."_ and go straight to `## Run-complete notification`. Visual-review holds do NOT block CHANGELOG authoring.

**Guard passes** → read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/changelog-authoring.md` and run its steps 6.1–6.9 (idempotency check → PR summaries → categorize → theme → author the entry → branch name → doc-only PR → CI result → surface in the final summary). While the guard holds it is **never read**.

## Run-complete notification

After Template 3, emit a `PushNotification`:
- **Clean completion**: `🏁 <milestone-title> · ✅ M merged · 👁️ U open · ⏸️ P parked`, the counts from Template 3.
- **Systemic halt**: `🚨 Run halted — <reason>`, where `<reason>` is the systemic-failure description, e.g. "gh auth failure".

**Run-end cost record (additive, never-gating).** **Last step of this section**, on the clean-completion and systemic-halt paths alike: emit one per-run cost record, then finish. It never blocks, parks, or changes the run's outcome.

1. **Aggregate.** From the `<usage>` block on each Agent-dispatch result this run — Phase 0 triage's own dispatches and each per-issue / per-wave `Agent(run_in_background: ...)` dispatch — sum `subagent_tokens` per model tier (`opus` / `sonnet`, keyed by the dispatched agent's tier) and sum `duration_ms`; add the orchestrator's own run clock → `wallClockSeconds`. No cross-orchestrator de-dup.
2. **Map (auditable lower-bound).** Each tier's summed `subagent_tokens` → `inputTokens` wholly; `outputTokens`, `cacheReadTokens` and `cacheWriteTokens` = 0, the sentinel, never fabricated. Pass `provenanceNote: "unsplit-total-as-input"` so the writer marks the cost a lower-bound.
3. **Emit.** Pipe `{"runId":"<milestone id>","wallClockSeconds":<n>,"tiers":{"<tier>":{...}},"provenanceNote":"unsplit-total-as-input"}` to `${CLAUDE_PLUGIN_ROOT}/scripts/write-cost-record.{sh,ps1}` (pwsh on Windows, bash elsewhere), which writes one record to `.milestone-config/.runtime/cost-records/`.
4. **Skip cleanly.** Zero dispatches this run → skip the emission with one log line, no zero-value record. Writer script absent, or no `<usage>` figures surfaced → silent no-op, one log line. Never fails the run.
