---
name: solve-milestone
argument-hint: <milestone-name | milestone-number>
description: >-
  This skill should be used when the user invokes "/milestone-driver:solve-milestone <name>", or asks to "solve a milestone", "drive a milestone", or "work the milestone autonomously". Autonomously iterates every issue in a GitHub milestone in dependency order, running /milestone-driver:solve-issue on each and re-syncing the integration branch between issues. Runs unattended; parks blocked/gapped issues and continues with clean ones — never waits on a human; only a systemic failure ends the run early. Builds mutually-independent issues within a Wave concurrently in git worktrees by **default** (no flag); a run-start barrier check drops to sequential only when a barrier is present — a `parallel: false` profile opt-out, a permission-allowlist gap, or an unconfirmed test-isolation answer.
---

# solve-milestone — autonomous driver

Drive a GitHub milestone to completion: order its issues, run `/milestone-driver:solve-issue` on each, integrate to `integrationBranch` between issues. This skill owns **ordering, the loop, branch re-sync, parking, and the final summary**; the per-issue pipeline is `/milestone-driver:solve-issue`'s.

The **post-build coherence pass** (`coherenceReviewAgent`, read-only, optional, never-gating) is delegated too: per-issue inside `solve-issue` section 6, before that issue's `/code-review`; under **wave granularity** instead at the Phase-2 serial-merge-tail re-verify point (`skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 2: serial verified merge tail`), against the integrated wave. Coherence-reviewer absent → silently skipped.

**Bounded blast radius.** The loop merges only to `integrationBranch`, never to `protectedBranch`. Release (`integrationBranch` → `protectedBranch`), **closing the GitHub milestone object**, and deploy stay manual and human-only — the driver closes the milestone's **issues** and authors the CHANGELOG, never the **milestone** itself.

**Execution mode (parallel by default, barrier-checked).** No `--parallel` flag, no "in parallel" opt-in. The mode resolves **once** at run start, in the last Before-starting step (**Resolve execution mode**), via a barrier cascade, and holds all run. **Back-compat:** a habit-typed `--parallel` token (or the phrase "in parallel") in `$ARGUMENTS` is **harmlessly stripped and ignored** by the generic `--<token>` flag-strip in Before-starting step 3.

## Contents

Before starting · The procedure — 1. List the milestone's open issues · 2. Determine the order · 3. Determine the target version · Phase 0 — Triage · 4. Loop over issues in dependency-graph order · Permission pre-flight gate · 5. Finish · Autonomy · Output spec — Template 1 — Run start / plan board · Template 2 — Status update at each wave boundary · Template 3 — Final results · Output style · Final summary — 6. Author the CHANGELOG entry · Run-complete notification

## Before starting

1. **Auth preflight.** Run `gh auth status`; on failure (non-zero exit, or any "not logged in" / "authentication failed" output) print a clear error — e.g. `"Error: gh auth status failed — authenticate with 'gh auth login' before running solve-milestone."` — and **halt immediately**.
2. Read the profile (see the plugin's `docs/profile-schema.md`).

   | Profile-resolution decision point | Behavior |
   |---|---|
   | Resolution order (transitional READ only; no migration move here) | `<repo>/.milestone-config/driver.json` first; if absent, the legacy root `<repo>/milestone-driver.json`. Both present → `.milestone-config/driver.json` wins, with no move, no overwrite, no deletion of the leftover root file. |
   | Migration (`git mv`) of a legacy layout | Never on this orchestrator's own working tree: that leaves an uncommitted relocation on `integrationBranch` with no commit path. The **first dispatched `solve-issue`** performs it on its feature branch at step 3.5, so the relocation rides that issue's PR; an all-parked milestone (no building run this pass) defers it to the next building run, the transitional READ covering the gap. |
   | Neither file exists, or `integrationBranch` / `protectedBranch` / `sourceGlobs` missing | Invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. |
   | `implementerAgent` | Defaults to `milestone-driver:implementer` when omitted. |
   | Optional keys — `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `domainSkills`, `nonNegotiables` | Their steps are skipped cleanly when absent. |
   | `integrationGranularity` / `visualHold` (resolve BOTH here, once, hold all run) | Absent → the documented defaults (`"issue"`; hold). **Fail-open, never a hard error**, like `maxParallelWorkers` (`skills/solve-milestone/parallel-waves.md (Resolve the concurrency cap)`) and `versioning` (`skills/solve-issue/SKILL.md (Fail-safe degradation)`): an **out-of-enum** `integrationGranularity` degrades to `"issue"`, logging `integrationGranularity "<value>" is not one of "issue", "wave", "milestone", degraded to "issue"`; a **non-boolean** `visualHold` degrades **toward holding**, logging `visualHold "<value>" is not a boolean, degraded to holding the milestone PR`. A valid value logs nothing. Every later read (`docs/profile-schema.md (How should built issues integrate?)`, `docs/profile-schema.md (Should the single milestone PR wait)`) uses this resolved value. |

   2.0.5. **Self-heal the scratch-ignore (always, before any `.milestone-config/` scratch write).** Per-clone scratch must be git-invisible from the first write, but `.milestone-config/` also holds **tracked** config (`driver.json`, `feeder.json`), so never blanket-ignore the directory and never add a blanket `*` or `/` rule. Ensure a **committed** `.milestone-config/.gitignore` carrying the block below: absent → create it (`mkdir -p .milestone-config`, then write the block); present → do nothing. The first dispatched `solve-issue` commits it on its feature branch alongside the migration.

      <!-- KEEP THIS BLOCK IN SYNC with the committed .milestone-config/.gitignore in this repo and with solve-issue / scripts/triage-cache.{sh,ps1}, feeder setup / plan. -->
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

   2.1. **One-time notices.** Immediately after the profile read: read `${CLAUDE_PLUGIN_ROOT}/skills/notices.md` and, in file order (= print order), evaluate each section whose `Skills` field includes `solve-milestone` (today: preflight, trello, visualcapture, parallel-default, code-review-gate, aiprefilter, cost-record, uisurfaceglobs), applying that section's `Trigger` → `Text` → `Marker` → `Legacy fallback` mechanics exactly as stated there.
3. **Resolve the milestone argument.** Strip flags from `$ARGUMENTS` (a flag is a token starting with `--`; remove each `--<token>`, and remove the immediately-following token only when it does not start with `--` AND the flag is value-bearing — `--parallel` and `--driven` are boolean, so strip the flag token alone; any other `--<token>` followed by a non-flag token is treated conservatively as value-bearing, strip both). Then:
   - **Purely numeric** (the stripped argument is digits only): `gh api repos/{owner}/{repo}/milestones/<milestone-number> --jq '{number, title}'`. Found → record the canonical `{number, title}`, state `"Resolved milestone #<milestone-number> → '<title>'"`. Not found → fail fast: print the available-milestones table below and stop.
   - **Otherwise (title/name):** `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | select(.title=="<name>") | {number, title}'`. Found → record it, state `"Resolved milestone '<title>'"`. Not found → fail fast the same way.
   - **Ambiguity note:** a purely-numeric milestone *title* (e.g. one titled `"2"`) is reachable via the numeric path. **If the resolved title is purely numeric, halt immediately and prompt the human** — triage reads a bare number as single-issue mode, so it must be renamed to a non-numeric title before this skill can drive it unattended. Do not proceed to Phase 0.
   - **Available-milestones table** (error path): `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | [.number, .title] | @tsv'` as a Markdown table with columns `#` and `Title`.

   All downstream steps use the resolved `{number, title}` — do NOT re-read `$ARGUMENTS` in `### 2. Determine the order` or Phase 0.
   **3.5** If `integrations.trello` is present in the profile, read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/trello-sync.md` and run its run-start card resolution (best-effort — a Trello failure never blocks the run).
   **3.6** **Cherry-pick check for a human-typed milestone under a parent group (fires only when `--driven` is absent).** `--driven` is defined in step 5 (string-presence recognition, #267); **when it is present this step does not execute at all** — not the first-issue query, not the parent lookup. When absent:

      a. **Find the milestone's first issue** — the lowest issue number assigned to it, `--state all` so a fully-built milestone stays inspectable: `gh issue list --milestone "<resolved-title>" --state all --json number --jq 'sort_by(.number) | .[0].number'`. Nothing returned (zero issues) → no-op; fall through to step 4.
      b. **Read that issue's parent, checking `md-epic` in the same call:** `gh api repos/{owner}/{repo}/issues/<first-issue>/parent`. A 404 means no parent; any other successful response already includes `.labels` — check those for an exact `md-epic` match (mirroring condition (b)'s live-label check in `### 4. Loop over issues in dependency-graph order`), no second call. A **non-404 failure of the `.../parent` call** (auth, 5xx, network) is systemic, not "no parent" — surface it and halt per `## Autonomy`.
      c. **No parent, or a parent without `md-epic`** → fall through to step 4, no prompt.
      d. **A parent carrying `md-epic`** → read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/md-epic-parent-check.md` and run it: the three-option prompt (build just this milestone · hand off to `/milestone-driver:solve-issue <parent-number>` · pause), each option's branch, and the reactive-only out-of-order note. Reached on no other path.
4. Confirm the working tree is clean and the local `integrationBranch` is current (`git fetch`, fast-forward).
5. **Resolve execution mode (the LAST Before-starting step).** Resolve the run's execution mode **once**, here, and hold it all run; nothing re-decides mid-loop. Evaluate the barrier cascade **top-down; first match wins**:

   **The `--driven` token.** An **interpreted token, not a parsed CLI flag** — recognized by **string presence** in the invocation text, never argument parsing, the way this plugin reads every invocation token (`skills/solve-issue/SKILL.md`'s `## Async mode (\`--async\`): retired`). No human types it; an internal caller supplies it when dispatching this skill on its own behalf. It gates **only row 4 below (the DB-hazard interview)** — a driven run takes row 4′ instead of prompting. **Every other Before-starting prompt is unaffected**: the purely-numeric-title halt in step 3 still halts and prompts on a driven run.

   | # | Condition | Resolved mode | Dispatch | Surfacing |
   |---|---|---|---|---|
   | 1 | profile `parallel: false` | **sequential** | background leaf dispatch ok if the gate passes, else synchronous | quiet — standing opt-out |
   | 2 | permission-allowlist gap (the `### Permission pre-flight gate`) | **sequential** | **synchronous** | 🔴 gap table + recommend `/fewer-permission-prompts` |
   | 3 | profile `parallel: true` | **parallel** | background | quiet — asserted safe |
   | 4 | `unitTestCmd` set AND `parallel` absent AND **interactive** | **interview → user's choice**, persisted to `parallel` | per choice | 🔴 up-front prompt (below) |
   | 4′ | same as row 4 but (`MILESTONE_DRIVER_NONINTERACTIVE=1` OR `--driven` present) | **sequential** | background leaf dispatch ok if the gate passes, else synchronous | loud `⚠` note + how to set `parallel: true`; **no persist** |
   | 5 | otherwise | **parallel** | background | quiet — default |

   **The permission pre-flight gate runs here, once** (`### Permission pre-flight gate`): a gap → synchronous dispatch + sequential mode (row 2); no gap → background dispatch is available and the cascade continues. The in-loop references (`sequential-loop.md` step 2, `parallel-waves.md` Phase 1 step 3) **read this resolved decision** — the gate does **not** re-fire mid-loop.

   **DB-hazard interview (row 4).** Trigger: `unitTestCmd` set AND `parallel` absent from the profile — the **only** trigger, because per-issue unit runs are the only gate run *concurrently* (`e2eTestCmd` and any server-starting preflight are deferred to the serial merge tail and run once). Fire it **once**, here, before Phase 0: read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/db-hazard-interview.md` and run it — the prompt, the Yes/No branches and their `parallel: true` / `parallel: false` writes to `.milestone-config/driver.json`, the persistence rule, and the row-4′ path (`MILESTONE_DRIVER_NONINTERACTIVE=1` OR `--driven`), which does not prompt, falls to sequential **with a loud note**, and persists nothing. On any other cascade row it is **never read**.

      **Nothing-to-decide:** `parallel` absent AND `unitTestCmd` absent → row 5 → **parallel**, quiet — **no interview, no persisted value**.

   **Surface the resolved mode.** State it and its reason in the run output; it drives Template 1's mode line (`## Output spec`).

## The procedure

### 1. List the milestone's open issues
Run `gh issue list --milestone "<resolved-title>" --state open`, `<resolved-title>` being the title from the canonical `{number, title}` resolved in Before-starting step 3.

### 2. Determine the order
The **milestone description is the ordering source of truth**. Read it (`gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '.description'`, preferred, else `gh api "repos/{owner}/{repo}/milestones?state=all" --jq '.[] | select(.title=="<resolved-title>") | .description'`) and follow the Wave / dependency sequence it records. No explicit order → fall back to ascending issue number and **state that assumption explicitly** in the run output.

### 3. Determine the target version

Read `versioning` from the profile. **Version-free mode** (`versioning: false`): skip this step entirely. Record "version-free run — no version determined or bumped" and proceed to Phase 0.

**Otherwise** (`versioning: true` or absent): read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/version-target.md` and run it — the deterministic extractor `${CLAUDE_PLUGIN_ROOT}/scripts/extract-version.{sh,ps1}` (issue #158; never parse by judgment), its result × `versioning` branch table (versioned / version-free with a logged reason / prompt), its fail-open behavior, the `MILESTONE_DRIVER_NONINTERACTIVE=1` degradation, and where the target is consumed. Hold that target for the loop. Under `versioning: false` it is **never read**.

### Phase 0 — Triage

Invoke triage across the whole milestone before the build loop begins:

```
/milestone-driver:triage <resolved-title>
```

(Pass the resolved title — triage's bare-number path means single-issue mode.)

1. **Present triage output.** Surface the all-clear or gap table in the run output; triage's output carries the Wave-ordered dependency graph whether or not there are gaps.

2. **Apply triage-recommended park labels.** Triage posts the `🔴 Triage` comment on each affected issue but applies no labels — that is this skill's job. For every issue where `issueStates[n].blockers == true`, apply its `issueStates[n].label` (`"needs design"` or `"needs decision"`) with the apply-time label helper from `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` Phase 4, using that taxonomy table's hex color and description. Where `issueStates[n].clearLabel == true` instead, remove the one park label the issue live-carries and add none (`skills/triage/blocker-resolver-dispatch.md (Unparking)`):

   ```
   gh label create "<name>" --color <hex> --description "<desc>" --force
   gh issue edit <n> --add-label "<name>"
   gh issue edit <n> --remove-label "<name>"     # clearLabel == true
   ```

2.5. If `integrations.trello` is configured, run trello-sync.md `## Phase 0 hooks` (best-effort).

3. **Seed the build queue.** Carry the full `dependencyGraph` and `issueStates` triage returned into the loop below; from here the loop drives from the validated graph, not the raw declared order.

### 4. Loop over issues in dependency-graph order

**Mode branch point.** In **parallel** mode (resolved at the *Resolve execution mode* Before-starting step): read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/parallel-waves.md` and run its Wave loop — `parallel-waves.md § Parallelizable-set selection (parallel mode)`, then `§ Parallel mode — Phase 1: concurrent stage dispatch`, `§ Parallel mode — Phase 2: serial verified merge tail`, `§ Integration granularity (issue vs wave)` — instead of the sequential build steps below; never silently degrade to sequential, which would skip real dispatched work. In **sequential** mode it is **never read**.
- **Granularity branch point.** Under `integrationGranularity: "milestone"` (resolved in the Before-starting profile read), read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/milestone-granularity.md`: `§ Branch model` and `§ Folding an issue into the milestone branch` own the mechanics behind condition (a) and every re-sync below, and `§ Creating the milestone branch` cuts `milestone-<number>-<slug>` from `integrationBranch` here, **before any issue branch** — every issue branch this run is cut from it, nothing reaching origin until milestone end. Under `"issue"` **never read**; under `"wave"` only where cited. Orthogonal to the mode branch point.

Create one TodoWrite item per issue. Process issues Wave by Wave; within a Wave, mutually independent issues may be taken in any order. For each issue, determine whether it is **buildable this pass** — iff ALL THREE hold:

- **(a)** every issue in `dependencyGraph.edges["<n>"]` (the issues this issue directly DEPENDS_ON) is already merged to `integrationBranch`, or, under `integrationGranularity: "milestone"`, carries its `Issue: #<n>` trailer on the milestone branch, since nothing merges to `integrationBranch` before milestone end (`milestone-granularity.md § Resume and buildability from the trailer`); **AND**
- **(b)** the issue currently carries **no blocker label** — check live: `gh issue view <n> --json labels --jq '[.labels[].name]'`, confirming none of `needs design`, `needs decision`, `blocked` is present. This live check is the **authoritative park-state**, catching Phase 0 triage parks AND prior-run build-time parks whose labels persist. A labeled issue must not be rebuilt until a human clears the label; **AND**
- **(c)** `issueStates[n].blockers == false` (this-run triage found no spec gap).

**If buildable:** read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/sequential-loop.md` and run its per-issue build steps 1–4 (re-sync the build target → run `solve-issue <n>` in-thread with both held values restated → park-and-continue on STOP/PAUSE → on-success terminal states, trello tick, milestone-granularity fold). In parallel mode it is **never read** — `parallel-waves.md`'s Wave loop replaces those steps.

**If not buildable (triage-parked, live-label park, or dependency not yet merged):** read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/not-buildable.md` and run it — the park-label back-fill and `in progress` marking for a triage/prior-run park (with the one-blocker-label-per-issue rule), and, for a dependency hold, the `blocked` label plus the byte-fixed `🔴 Blocked` comment and the transitive-dependent holds. A run whose issues are all buildable never reads it; both modes read it when one is not.

The loop **never waits on a human**. Every issue ends merged, **held at the visual-review gate** (an open `needs review` PR on a UI issue awaiting visual sign-off), or parked (labeled, branch open if applicable, comment posted). Comment provenance: triage parks carry Phase 0's `🔴 Triage` comment; build-time STOP/PAUSE parks the reason confirmed or posted at the park step (`sequential-loop.md` step 3c); dependency holds the `🔴 Blocked` comment (`not-buildable.md`).

In **versioned mode** the **first issue's PR** sets `plugin.json` to the target version; every later PR is **idempotent** — already at that version, `solve-issue`'s bump step makes no change. In **version-free mode** (`versioning: false`) no PR carries a version change.

### Permission pre-flight gate

**Runs once per run, at run-start mode resolution (the *Resolve execution mode* Before-starting step, row 2), before any dispatch — whenever background dispatch is about to be used** (parallel-by-default, plus the leaves the sequential loop dispatches). The mode cascade and the loop **read** its result. Background subagents auto-deny any tool call that would otherwise prompt, and a background leaf hitting an un-allowlisted tool fails outright with no interactive recovery.

**Allowlist source.** Union `permissions.allow` from all three Claude Code settings layers; absent or unreadable layers are skipped in the union, not counted as gaps:

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

**Gap detection and response.** No gaps → proceed with background dispatch as planned. **Gap detected** (the union misses part of that surface, or no layer is readable) → do **not** dispatch in the background: (1) surface a 🔴 gap table naming each missing grant and which settings layer(s) could supply it; (2) **fall back to synchronous dispatch for this run** — the run completes, it just does not use background concurrency; (3) recommend the consumer run `/fewer-permission-prompts` (see `docs/consumer-setup.md`). That result holds for the rest of the run — do not re-read settings per issue.

**Auto-deny handling.** A background leaf reporting an auto-deny it could not work around is a **park** — post a `blocked` comment naming the denied tool, apply `blocked` (+ `in progress` if the branch has commits), preserve the branch, continue. The comment and label are the durable record.

### 5. Finish
The run ends when no buildable issues remain.
If `integrations.trello` is present, apply `## Finish hooks` from `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/trello-sync.md` (best-effort — Trello failures never block the run; skipped updates surface in the final summary).

## Autonomy

- **Unattended between systemic failures.** Within an explicit `/milestone-driver:solve-milestone` run, operate autonomously. A `solve-issue` STOP or PAUSE **parks** that issue (label + open branch + comment) and the loop continues. Only a systemic failure ends the run early.
- **Systemic failures that halt the run** (examples): `gh auth` failure, a broken or inaccessible `integrationBranch`, missing required tooling (`gh`, `git`), and **any reference file this skill read-directs being missing or unreadable once its condition has fired** — `parallel-waves.md`, `milestone-granularity.md`, `sequential-loop.md`, `not-buildable.md`, `md-epic-parent-check.md`, `version-target.md`, `db-hazard-interview.md`, `changelog-authoring.md` (core machinery, unlike best-effort integrations such as `trello-sync.md` / `coherenceReviewAgent`, which degrade silently). These are conditions where no further issue can make progress: surface the failure, leave the working tree clean and all in-flight issues parked, present the final summary and stop — `## Run-complete notification` emits `🚨 Run halted — <reason>`.
- **Architecture is locked** per issue at its plan-approval time. A plan proven wrong is a park (STOP → park + continue), not a silent redesign. For the bounded definition of architecture vs implementation detail, see the Autonomy model in `solve-issue`.
- **Never escalate scope to `protectedBranch`.** No PR, push, or merge targets `protectedBranch` (enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection).

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
Mode cell: the mode resolved by the *Resolve execution mode* Before-starting step — `parallel`, or `sequential (<reason>)` where `<reason>` ∈ { `profile parallel:false`, `permission gap — see 🔴`, `test-isolation not confirmed` }.

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
PR cell: show the PR number if the issue has one, else —.

Gates legend: 🧪 = unit suite · 🔍 = code review · 🌐 = E2E

### Template 3 — Final results

The layout for `## Final summary` below; fill the metadata lines under the table from that section's requirements, derived from the run's tracked context.

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
PR cell: show the PR number if the issue has one, else —.

## Output style

Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` — this plugin's output contract. `## Terminal output` governs what this skill prints (including the `## Output spec` template rule); `## GitHub-facing prose`, `## When prose is the correct form`, and `## Evidence slots` govern every issue comment, PR body, and CHANGELOG entry it writes.

Read `${CLAUDE_PLUGIN_ROOT}/skills/citation-format.md` — the one format every citation in those slots takes.

## Final summary

Use Template 3 (`## Output spec`) as the layout. On completion or systemic-failure halt, report:

- **Issues built and merged** to `integrationBranch` (with PR links).
- **Issues parked** — per issue: number and title, the park label applied, the blocker reason, and the open feature branch (if applicable). Take the reason from the run's tracked context (the triage gap, the STOP/PAUSE reason, or the unmerged upstream). Not in active context → read `gh issue view <n> --json comments` and use the most recent format-matching comment, possibly from a prior run: one opening with `🔴 Triage` (triage-park), `🔴 Blocked` (dependency-hold), or `🔴 Parked` (build-park). gh returns comments oldest-first, so take the LAST match. Pre-1.7.0 runs may have left un-anchored build-park comments; with no anchored match, report "park reason not recorded (pre-1.7.0 park format)". Never invent a reason.
- **Open UI PRs** awaiting human merge: those carrying `needs review` (UI issues per issue #18, built but left open for visual sign-off), with PR links.
- **PRs carrying a `judgment call` label**, flagged for post-run review.
- **PRs missing a `## Code Review` section** — flagged, like `judgment call` PRs, for post-run human review before the `integrationBranch` → `protectedBranch` merge.
- **Auto-resolved-conflict issues** (parallel mode) — those whose merge conflict the serial verified merge tail **auto-resolved** (bounded auto-resolve) before merging, for a human to sanity-check.
- **Per-Wave parallel-set sizes** (parallel mode) — the parallelizable-set size dispatched each Wave.
- **The run ended because** no buildable issues remain — not because it is waiting on a human.
- The next human step: review parked issues and the open `needs review` PRs; clear park labels once their blockers are resolved and re-run for the rest; all work merged → run Template 3's `🔴 Your move:` item 3 verbatim — the driver closes the milestone's issues and authors the CHANGELOG, never the milestone itself — and deploy manually.

**Output ordering (clean-completion path only):** do not emit the Template 3 final summary until step 6 completes (`changelog-authoring.md § 6.9 Surface in the final summary "Your move" section`). On the systemic-halt path step 6 is skipped entirely (per its preamble) — emit Template 3 immediately.

### 6. Author the CHANGELOG entry

**Runs on the CLEAN COMPLETION PATH ONLY.** When the systemic-halt path reaches the Final summary, skip this step entirely and go straight to `## Run-complete notification`; that path ends with a 🚨 reason, not a 🏁 one.

**Guard — skip this step entirely if** either holds:

- The parked count for this run is greater than zero (any issue was parked), OR
- The run ended via a systemic halt (see preamble above)

The parked count comes from this run's **in-context tracking** — every issue that did not reach "merged" or "held at visual-review gate": parked at build time, skipped on triage blockers, AND excluded by the buildability check on a live blocker label (e.g. `blocked` from a prior run). It is Template 3's `⏸️ P` count. Do NOT re-derive via a live `gh issue list` query — that may find labels unrelated to this run.

Either condition holding → post _"Skipping CHANGELOG authoring — run did not fully complete (N parked)."_ and go straight to `## Run-complete notification`. Visual-review holds (open `needs review` PRs for UI issues) are expected clean-completion state and do NOT block CHANGELOG authoring.

**Guard passes** → read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/changelog-authoring.md` and run its steps 6.1–6.9 (idempotency check → PR summaries → categorize → theme → author the entry → branch name → doc-only PR → CI result → surface in the final summary). While the guard holds it is **never read**.

## Run-complete notification

After presenting the final summary (Template 3), emit a `PushNotification`:
- **Clean completion**: `🏁 <milestone-title> · ✅ M merged · 👁️ U open · ⏸️ P parked` (M, U, P are the counts from Template 3).
- **Systemic halt** (invoked from the Autonomy section's halt path): `🚨 Run halted — <reason>`, where `<reason>` is the systemic-failure description, e.g. "gh auth failure".

**Run-end cost record (additive, never-gating).** As the **last step of this `## Run-complete notification` section**, on the clean-completion and systemic-halt paths alike, emit one per-run cost record, then finish. It never blocks, parks, or changes the run's outcome (`.project/design-philosophy.md#Error & failure philosophy` — optional integrations never gate; absent means skip with one log line).

1. **Aggregate its own dispatches.** From the `<usage>` block each Agent-dispatch tool result carried this run — Phase 0 triage's own agent dispatches (triage runs in-thread, never as a dispatched agent) and each per-issue / per-wave `Agent(run_in_background: ...)` dispatch (whose completion notification carries the same block) — sum `subagent_tokens` per model tier (`opus` / `sonnet`, keyed by the dispatched agent's tier) and sum `duration_ms`, plus the orchestrator's own run clock → `wallClockSeconds`. Independent of any background `solve-issue`'s record — no cross-orchestrator de-dup.
2. **Map (auditable lower-bound).** Each tier's summed `subagent_tokens` → `inputTokens` wholly; `outputTokens` = 0; `cacheReadTokens` = `cacheWriteTokens` = 0 (not surfaced per-dispatch — the 0 sentinel per #320, never fabricated). Pass `provenanceNote: "unsplit-total-as-input"` so the writer marks the cost a lower-bound.
3. **Emit.** Pipe `{"runId":"<milestone id>","wallClockSeconds":<n>,"tiers":{"<tier>":{...}},"provenanceNote":"unsplit-total-as-input"}` to `${CLAUDE_PLUGIN_ROOT}/scripts/write-cost-record.{sh,ps1}` (pwsh on Windows, bash elsewhere — the host selection `${CLAUDE_PLUGIN_ROOT}/scripts/ci-preflight-steps.{sh,ps1}` uses). The single-record write to `.milestone-config/.runtime/cost-records/` is #320's.
4. **Skip cleanly.** Zero dispatches this run (e.g. a halt before Phase 0 dispatches anything) → skip the emission with one log line, no zero-value record. Writer script absent, or no `<usage>` figures surfaced → silent no-op, one log line. Never fails the run.
