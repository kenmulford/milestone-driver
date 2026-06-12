---
name: solve-milestone
argument-hint: <milestone-name | milestone-number> [--parallel]
description: This skill should be used when the user invokes "/milestone-driver:solve-milestone <name>", or asks to "solve a milestone", "drive a milestone", or "work the milestone autonomously". Autonomously iterates every issue in a GitHub milestone in dependency order, running /milestone-driver:solve-issue on each and re-syncing the integration branch between issues. Runs unattended; parks blocked/gapped issues and continues with clean ones — never waits on a human; only a systemic failure ends the run early. Accepts an optional `--parallel` flag (or the phrase 'in parallel') to build mutually-independent issues within a Wave concurrently in git worktrees.
---

# solve-milestone — autonomous driver

Drive an entire GitHub milestone to completion by ordering its issues and running `/milestone-driver:solve-issue` on each, integrating to `integrationBranch` between issues. This skill owns **ordering, the loop, branch re-sync, parking, and the final summary**; the full per-issue pipeline — root-cause, implementer dispatch, gates, review, PR, auto-merge on green (non-UI) or visual-review hold (UI), close — is delegated to `/milestone-driver:solve-issue`.

**Bounded blast radius.** The loop merges only to `integrationBranch`, never to `protectedBranch`. Release (`integrationBranch` → `protectedBranch`) and deploy stay manual and human-only. That boundary is what makes unattended operation safe.

**`--parallel` activation (recognized, not parsed).** Claude Code does **no** argument parsing — `$ARGUMENTS` is string-substituted — so this skill is **not** a CLI parser. Parallel mode is **recognized** when the invocation contains **either** a `--parallel` token in `$ARGUMENTS` **OR** the natural-language equivalent ("in parallel"); both route to the same parallel-mode behavior (`### Parallel mode (--parallel) — Phase 1: concurrent worker dispatch` below). **Absent either signal, today's sequential path runs byte-unchanged** — the loop (steps 1–5), the buildability conditions (a)/(b)/(c), and the buildable / not-buildable branches are untouched. Parallel mode is an additive opt-in; the blast-radius boundary above is identical in both modes (workers and the merge tail merge only to `integrationBranch`, never `protectedBranch`).

## Before starting

1. **Auth preflight.** Run `gh auth status`. If it fails (non-zero exit or any "not logged in" / "authentication failed" output), print a clear error — e.g. `"Error: gh auth status failed — authenticate with 'gh auth login' before running solve-milestone."` — and **halt immediately**. Do NOT proceed to profile read, milestone resolution, or any other step.
2. Read the profile at `milestone-driver.json` (repo root; see the plugin's `docs/profile-schema.md`). If the file is absent or any of `integrationBranch`, `protectedBranch`, or `sourceGlobs` is missing, invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. `implementerAgent` defaults to `milestone-driver:implementer` when omitted. The keys `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `domainSkills`, and `nonNegotiables` are optional; their steps are skipped cleanly when absent.
   2.1. **First-run preflight notice (one-time).** Immediately after reading the profile: if `preflightCmd` is **absent** from the profile **and** the marker file `.milestone-driver-preflight-notice` does **not** exist at the repo root, print the notice below verbatim, then create the marker (`touch .milestone-driver-preflight-notice`). Stay **silent** if `preflightCmd` is set **or** the marker already exists. The marker is per-clone and gitignored, so the notice shows at most once per clone (same pattern as `.milestone-driver-tests-stamp`).

      <!-- KEEP THIS NOTICE BLOCK BYTE-IDENTICAL across solve-issue and solve-milestone (see plan 2026-06-04 verification model). -->
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
   1.2. **One-time Trello upgrade notice (solve-milestone only).** *(Positioned here alongside step 2.1 — both run immediately after the profile read in step 2.)* After step 2.1: if ALL THREE conditions hold — (a) `mcp__trello__*` tools are present in the session (probe by checking if `mcp__trello__get_health` is available), (b) `integrations.trello` is **absent** from the profile, (c) the marker file `.milestone-driver-trello-notice` does **not** exist at the repo root — print the notice below, then create the marker (`touch .milestone-driver-trello-notice`). Stay **silent** if any condition fails. The marker is per-clone and gitignored.

      ```text
      ▶ New in 1.8.0 — optional Trello integration (one-time notice)

      | What | Mirror milestone progress to a Trello board (card per milestone,
      |      | checklist per issue, automatic state transitions).
      | Why  | Keep your Trello board in sync without manual updates.
      | How  | Run `/milestone-driver:setup` and choose the Trello tier, or add
      |      | `integrations.trello` to milestone-driver.json manually.
      |      | Optional — skip and nothing changes.
      | Req  | Requires @delorenj/mcp-server-trello in your Claude Code session.
      ```
3. **Resolve the milestone argument** (subsumes the old "named milestone exists" confirmation). Strip flags from `$ARGUMENTS` to get the bare argument (flags are tokens starting with `--`; for each `--<token>`, remove it; ALSO remove the immediately-following token only if that token does not start with `--` AND the flag is value-bearing: `--parallel` is boolean — strip the flag token only, do NOT consume the next token; any other `--<token>` with a following non-flag token is treated conservatively as value-bearing — strip both). Then:
   - **If purely numeric** (`$ARGUMENTS` minus flags is digits only): call `gh api repos/{owner}/{repo}/milestones/<milestone-number> --jq '{number, title}'` — if found, record the canonical `{number, title}` and state `"Resolved milestone #<milestone-number> → '<title>'"` in the run output; if not found, fail fast — print the available milestones as a **number + title table** (see format below) and stop.
   - **Otherwise (title/name):** call `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | select(.title=="<name>") | {number, title}'` — if found, record the canonical `{number, title}` and state `"Resolved milestone '<title>'"` in the run output; if not found, fail fast — print the available milestones as a **number + title table** and stop.
   - **Ambiguity note:** a purely-numeric milestone *title* (e.g. a milestone literally titled `"2"`) is reachable via the numeric-input path (routing is determined by `$ARGUMENTS` form — digits only — not by title content). After resolution, check the resolved title: **if it is purely numeric, halt immediately and prompt the human.** Triage interprets a bare number as single-issue mode, so the milestone title must be renamed to a non-numeric value before this skill can drive it unattended — do not proceed to Phase 0.
   - **Available-milestones table format** (for the error path): `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | [.number, .title] | @tsv'` formatted as a Markdown table with columns `#` and `Title`.

   All downstream steps use the resolved `{number, title}` — do NOT re-read `$ARGUMENTS` directly in the ordering step (procedure step 2, `### 2. Determine the order`) or Phase 0.
   **3.5** If `integrations.trello` is present in the profile, read `skills/solve-milestone/trello-sync.md` and run its run-start card resolution (best-effort — a Trello failure never blocks the run).
4. Confirm the working tree is clean and the local `integrationBranch` is current (`git fetch`, fast-forward).

## The procedure

### 1. List the milestone's open issues
Run `gh issue list --milestone "<resolved-title>" --state open`.

(Where `<resolved-title>` means the title from the canonical `{number, title}` resolved in Before-starting step 3.)

### 2. Determine the order
The **milestone description is the ordering source of truth**. Read it (e.g. `gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '.description'` or `gh api "repos/{owner}/{repo}/milestones?state=all" --jq '.[] | select(.title=="<resolved-title>") | .description'`) and follow the recorded Wave / dependency sequence. (Using the resolved number is more direct — prefer the by-number endpoint since it is already resolved.) If the description records no explicit order, fall back to ascending issue number and **state that assumption explicitly** in the run output — do not silently pick an order.

### 3. Determine the target version

Read `versioning` from the profile. **Version-free mode** (`versioning: false`): skip this step entirely — no semver parse, **no prompt**, no target version (the milestone name need not be a version). Record "version-free run — no version determined or bumped" in the run output and proceed to Phase 0. **Versioned mode** (`versioning` `true` or absent): parse the milestone name and description for a semantically valid version (`x.y.z`). Derive the target version, **hold it in the orchestrator's context for the duration of the loop**, and record it in the run output. If no valid semver can be parsed, **prompt the user** before proceeding — do not guess.

> **Version source vs. version target.** In versioned mode the version **source** is the milestone (parsed here). The version **target** is `.claude-plugin/plugin.json`; the missing-`plugin.json` fail-safe for that target is applied downstream at `solve-issue` step 6.4 (the bump step), not here. Step 3 determines the source only; it adds no fail-safe branch of its own.
>
> **Precedence:** in versioned mode the milestone-derived target version is authoritative. The per-issue patch-default + confirm behavior in `solve-issue` does **not** fire inside a milestone run — the target version replaces it entirely.
>
> **Handoff:** in versioned mode the same main thread runs both `solve-milestone` and each `solve-issue` invocation, so the target version is available directly from the orchestrator's working context — it is **not** passed as a CLI argument to `solve-issue`.

### Phase 0 — Triage

Before the build loop begins, invoke the triage phase across the entire milestone:

```
/milestone-driver:triage <resolved-title>
```

(Pass the resolved title — triage's bare-number path means single-issue mode, so always pass the title here. If the resolved title is purely numeric, the Before-starting step 3 guard applies — see the Caution there.)

1. **Present triage output.** Surface the all-clear or gap table in the run output so the operator can see what was found. The Wave-ordered dependency graph is included in triage's output regardless of whether there are gaps.

2. **Apply triage-recommended park labels.** Triage posts the `🔴 Triage` comment on each affected issue but does **not** apply labels — that is this skill's responsibility. For every issue where `issueStates[n].blockers == true`, apply its `issueStates[n].label` (`"needs design"` or `"needs decision"`) using the apply-time label helper from `skills/setup/SKILL.md` Phase 4:

   ```
   gh label create "<name>" --color <hex> --description "<desc>" --force
   gh issue edit <n> --add-label "<name>"
   ```

   Use the hex color and description from the taxonomy table in `skills/setup/SKILL.md` Phase 4.

2.5. If `integrations.trello` is configured, run trello-sync.md `## Phase 0 hooks` (best-effort).

3. **Seed the build queue.** Carry the full `dependencyGraph` and `issueStates` returned by triage into the loop below. The loop drives from the validated dependency graph — not the raw declared order — from this point forward.

### 4. Loop over issues in dependency-graph order

Create one TodoWrite item per issue. Drive the loop from the **validated dependency graph** produced by Phase 0. Process issues Wave by Wave; within a Wave, issues that are independent of each other may be treated as buildable in any order.

For each issue, determine whether it is **buildable this pass**. An issue is buildable iff ALL THREE conditions hold:

- **(a)** every issue in `dependencyGraph.edges["<n>"]` (the issues this issue directly DEPENDS_ON) is already merged to `integrationBranch`; **AND**
- **(b)** the issue currently carries **no blocker label** — check live: `gh issue view <n> --json labels --jq '[.labels[].name]'` and confirm none of `needs design`, `needs decision`, `blocked` is present. This live-label check is the **authoritative park-state**: it catches both triage parks labeled in Phase 0 AND prior-run build-time parks whose labels persist on the issue. A labeled issue must not be rebuilt until a human clears the label; **AND**
- **(c)** `issueStates[n].blockers == false` (this-run triage found no spec gap).

**If buildable:**

1. Ensure `integrationBranch` is current (`git fetch`, fast-forward) so dependent issues build on already-merged work.
2. **Before dispatching the first issue in the run** (once per run, not per issue): run the **permission pre-flight gate** per `### Permission pre-flight gate`. If a gap is found → fall back to synchronous dispatch for this run (today's behavior, steps 2–4 unchanged, no background concurrency). If no gap → dispatch each issue as a background agent (`Agent(run_in_background: true)`), embedding BOTH the target version AND the Phase 0 triage result as named fields in the agent's prompt brief (e.g. `targetVersion: <x.y.z>` and `step-0 result for #N: { ... }`). A background agent has a fresh context and does NOT inherit the orchestrator's in-memory state — both values must be literally present in the prompt string, not inherited from context.

   When dispatching as a background agent: invoke `solve-issue <n> --async`. The orchestrator MUST embed the Phase 0 triage result as before (e.g. "step-0 result for #N: { blockers: false, label: null, advisories: [...], risk: light }, edges: [...]") so that step 0's Branch A can reuse it. **Await the completion notification** from the background agent before proceeding to the next issue — the main line is live (interactive) between dispatches. When the notification arrives, re-derive terminal state from live `gh` queries — `gh issue view <n> --json labels,state` and `gh pr list --head issue/<n>-*` — to determine whether the issue was merged, held for visual review, or parked (there is no structured handback in `--async` mode). **Surface the wave-boundary status update using Template 2 from `## Output spec`**. Narrate any park (label + reason) sourced from the live issue labels. Apply park labels if needed. Re-sync `integrationBranch` (`git fetch`, fast-forward). Then dispatch the next issue.

   **Operator redirect window.** Between dispatches the main line is interactive — the background agent has completed and the main line is live. The operator can redirect before the next dispatch begins. Redirects are only possible at these chunk boundaries; they are not possible mid-run while a background agent is executing.

   **Background agents never call PushNotification** — confirmed absent from subagent tool registries (see issue #97 recorded decision); the main line emits at this boundary. **SendMessage/mid-chunk redirect does not exist in Claude Code** — do not narrate it.

   **Sequential mode only** (not applicable to parallel worker handbacks — those are handled by Phase 1 step 5's parked-handback emit): After each issue completes in **sequential mode** (whether dispatched as a background agent or run synchronously as fallback), post the chunk-boundary board first (Template 2), then emit a `PushNotification` for the terminal state of the just-completed issue:
   - **Issue parked** (any park subtype — triage-park, dependency-hold, STOP/build-park): emit `⏸️ #N parked — <reason>` (where `<reason>` is the park label + brief blocker description, e.g. "needs decision: new dependency").
   - **Issue completed** (merged or held for visual review): no per-issue notification here — the 🏁 run-complete notification (emitted after the Final summary) is the aggregate end signal.

   When falling back to synchronous dispatch: invoke `solve-issue <n>` as today (no `--async`). The orchestrator MUST restate the Phase 0 triage result inline when invoking step 0 — e.g. "step-0 result for #N: { blockers: false, label: null, advisories: [...], risk: light }, edges: [...]" — so that step 0's Branch A recognizes the explicitly supplied result and skips re-invoking triage. If the result is no longer reliably in context (long run, context compression), step 0 falls to Branch B (fresh single-issue triage) — Branch B is the safe default, never an error.

3. **Park-and-continue on STOP/PAUSE:** *(Under async dispatch: the background agent already ran park-don't-prompt — skip step (3c) below (the comment was already posted by the agent); the live label read in step 4.2 is the park confirmation. Under synchronous dispatch: proceed as follows.)* If `/milestone-driver:solve-issue` returns a STOP or PAUSE (no root cause, new dependency, architecture conflict, scope overrun, ambiguity, unmet gate), **park the issue and continue** — do **not** halt the loop. Parking steps:
   a. Apply the appropriate label using the apply-time label helper (`needs decision` for a new dependency or architecture call; `needs design` for a design/spec gap; `blocked` for an unresolvable unmet gate).
   b. Apply `in progress` if a branch exists with commits.
   c. The STOP/PAUSE reason is already recorded on the issue (by `solve-issue` or the implementer). Confirm it is there; if not, post it via `gh issue comment <n>`.
   d. Leave the issue open; note it in the run output.
   e. Continue to the next issue in the dependency graph whose dependencies are merged.
4. **On success**, `/milestone-driver:solve-issue` has reached one of two terminal states: for a **non-UI issue** it has squash-merged to `integrationBranch` and closed the issue; for a **UI issue** held at the visual-review gate (`solve-issue` steps 7–9) it has left the PR **open** with the `needs review` label — not merged, issue not closed — for human visual sign-off (the final summary reports these open PRs). For non-UI merged issues, if `integrations.trello` is present and a card handle was resolved, tick the checklist item for issue `#<n>` per `trello-sync.md § Issue granularity` (under `## Loop hooks`; best-effort; failure logged, loop continues). Re-sync the local `integrationBranch` (`git fetch`, fast-forward) before the next issue either way — for a UI issue nothing was merged, so the re-sync is a no-op.

**If not buildable (triage-parked, live-label park, or dependency not yet merged):**

- **Triage-parked or prior-run park** (`issueStates[n].blockers == true` OR live labels include a blocker label): in the common case the blocker label is already present (applied in Phase 0 or by a prior run); no build attempt. However, if Phase 0's label application was interrupted (e.g., a transient `gh` error), the label may be unexpectedly absent — check live: `gh issue view <n> --json labels --jq '[.labels[].name]'`. If none of `needs design`, `needs decision`, or `blocked` is present, apply `issueStates[n].label` now via the apply-time label helper (`gh label create … --force` + `gh issue edit <n> --add-label …`) before proceeding. This makes the branch idempotent and ensures the async handoff label is always on the issue. Apply `in progress` (via the apply-time helper) if a feature branch for this issue already exists with commits (check `git branch -a`). Note the issue in the run output (label + blocker reason) and continue.

  > **One blocker label per issue.** A parked issue carries exactly ONE blocker label. Do not apply `blocked` to an issue that already carries `needs design` or `needs decision` — the triage/design label is the root block and takes precedence; `blocked` would be redundant. (`in progress` is orthogonal and may still be applied.)

- **Dependency not yet merged** (condition (a) fails but conditions (b) and (c) pass — the issue is NOT itself triage- or live-label-parked): apply the `blocked` label (and `in progress` if a branch with commits exists) via the apply-time helper, and post a comment naming this issue's own unmerged upstream(s):
  `gh issue comment <n> --body "🔴 Blocked — held by unmerged upstream dependency: #<each unmerged issue in edges[\"<n>\"]>. This is a dependency-ordering hold (no design/decision work is needed for this issue itself). Once the upstream(s) are merged (and any upstream parks cleared), remove this \`blocked\` label and re-run solve-milestone to build this issue."`
  Then hold every transitive dependent (any issue whose `dependencyGraph.edges` include this issue or another held issue): for EACH such issue m, **before applying `blocked`**, check m's live labels (`gh issue view <m> --json labels --jq '[.labels[].name]'`). If m already carries `needs design`, `needs decision`, or `blocked`, do NOT add another blocker label — the existing label stands (one blocker label per issue). Otherwise apply `blocked` (+ `in progress` if it has a branch). In all cases post the same KIND of comment naming m's OWN unmerged upstream(s) from `edges["<m>"]` — not this issue's (same wording: dependency-ordering hold, clear `blocked` label and re-run). Note all held issues in the run output and continue with independent buildable issues.

The loop **never waits on a human**. It runs to completion — every issue is either done (merged), **held at the visual-review gate** (a UI issue with an open `needs review` PR awaiting human visual sign-off), or parked (labeled, branch open if applicable, comment posted). Comment provenance by park type: triage-parked issues carry the `🔴 Triage` comment posted by Phase 0; build-time STOP/PAUSE parks carry the reason confirmed or posted at the park step (step 3c above); dependency-held issues carry the `🔴 Blocked` comment posted in the dependency-not-yet-merged branch above. The run ends when no more buildable issues remain.

In **versioned mode** the **first issue's PR** sets `plugin.json` to the target version. Every subsequent issue's PR is **idempotent** — if `plugin.json` already carries the target version, the version bump step in `solve-issue` makes no change. In **version-free mode** (`versioning: false`) no PR carries a version change at all.

### Parallelizable-set selection (parallel mode)

This subsection applies **only** to `--parallel` mode (#72). The sequential loop above is **unchanged** — sequential processing builds issues one at a time in dependency-graph order, and nothing here alters that path. This subsection defines **only** which set a parallel orchestrator may dispatch concurrently; it consumes triage's existing outputs and adds no new behavior to the default run.

**The parallelizable set.** From the issues in the current Wave, an issue belongs to the parallelizable set **iff both** hold:

- it is **buildable this pass** — the three conditions **(a)/(b)/(c)** already defined above (every issue in `dependencyGraph.edges["<n>"]` merged to `integrationBranch`; no live blocker label; `issueStates[n].blockers == false`); **AND**
- it carries **no `dependencyGraph.edges["<n>"]` edge to another issue currently in the same candidate set** (mutual independence).

In short: the set is **buildable ∧ mutually-independent**. (Do not re-derive buildability here — it is exactly the (a)/(b)/(c) definition the sequential loop already uses; this subsection only adds the intra-set independence guard.)

**Why the intra-set edge check is a guard, not the workhorse.** Within a single Wave the issues are already mutually independent by construction — that is how triage forms a Wave — so in the common case the intra-set edge check excludes nothing. Its real job is the **shared-file-but-not-a-build-dependency** case: two same-Wave issues whose files overlap are **not** a build-time dependency (their files are disjoint *at build*), so triage draws **no `DEPENDS_ON` edge** between them and they correctly stay in the set. That overlap surfaces only **at merge**, where the orchestrator-owned **serial verified merge tail** (#73) reconciles it (git's `ort` strategy auto-resolves non-overlapping edits to the same file). Field-validated: two issues each appended a distinct child route to the same `app.routes.ts` — no `DEPENDS_ON` edge, both built concurrently, and the two non-overlapping additions auto-merged in the serial tail.

**Worked example.** A Wave holds buildable issues #A, #B, #C (deps merged, unparked, this-run triage-clean), and `dependencyGraph.edges` shows none of them depends on another → the parallelizable set is **{#A, #B, #C}**, dispatched concurrently (one `solve-issue --worker` each).

- **Guard via buildability (the common exclusion).** A later pass surfaces #D with no live block and `issueStates["D"].blockers == false`, but `edges["D"]` still names an unmerged #B. #D fails condition (a) → it is **not buildable**, so it is excluded — by the existing buildability definition, before the intra-set check even runs.
- **Guard via the shared-file case (what the edge check is actually for).** Suppose #A and #B both edit `app.routes.ts` but neither has a `DEPENDS_ON` edge to the other. They **stay in the set** and build concurrently; their same-file overlap is reconciled by the merge tail (#73), **not** by excluding either from the set.

**No triage change.** This selection consumes triage's existing `dependencyGraph` (`waves` + `edges`) and `issueStates` outputs **unchanged** — there is no modification to `triage` or `triage-reviewer`. It reads the same graph the sequential loop already drives from.

### Permission pre-flight gate

**Runs once per run, before the first background dispatch. Zero cost on synchronous paths.**

**Scope: this gate applies only when background dispatch is about to be used (`--parallel` mode or another background-dispatch path, #89). Sequential/synchronous runs never reach it — zero cost preserved.**

Background subagents auto-deny any tool call that would otherwise prompt (documented Claude Code behavior). A background chunk hitting an un-allowlisted tool fails outright with no interactive recovery — park-don't-prompt becomes physically enforced. Before activating any background dispatch (the async dispatch points, #89), run this gate to verify the session's permission allowlist is complete.

**Allowlist source — merged settings read.** Read `permissions.allow` from all three Claude Code settings layers and union them:

| Priority | File |
|---|---|
| 1 | `~/.claude/settings.json` (user global) |
| 2 | `.claude/settings.json` (project) |
| 3 | `.claude/settings.local.json` (project local) |

Absent or unreadable layers are skipped in the union (not treated as gaps). The union covers all readable layers. Synchronous fallback fires only when (1) the union fails to cover the required tool surface, or (2) no layer is readable.

**Pipeline tool surface.** The allowlist must cover, at minimum:

| Tool category | Required grants |
|---|---|
| Read-only gh ops | `gh pr list`, `gh issue view`, `gh issue list` |
| Git | `git commit`, `git push` |
| PR / issue writes | `gh pr create`, `gh pr merge`, `gh pr edit`, `gh pr comment` |
| Issue management | `gh issue edit`, `gh issue comment`, `gh issue close` |
| Label management | `gh label create` |
| Profile-defined commands | Each command in `unitTestCmd`, `preflightCmd`, `e2eTestCmd` (skip if absent) |

**Gap detection and response.**

- **No gaps:** proceed with background dispatch as planned.
- **Gap detected (union does not cover the required surface, or no layer is readable):** do **not** fire the background chunk. Instead:
  1. Surface a 🔴 gap table listing each missing grant and which settings layer(s) could supply it.
  2. **Fall back to synchronous dispatch for this run** — today's sequential behavior, unchanged. The run completes; it just does not use background concurrency.
  3. Recommend the consumer run `/fewer-permission-prompts` to establish a stable allowlist (see `docs/consumer-setup.md`).

The gate fires **once per run**, not once per issue. After the first background-dispatch decision point, the result (proceed / fallback) is held for the rest of the run — do not re-read settings on every issue.

**Worker auto-deny handling.** If a background worker chunk receives an auto-deny on a tool call mid-execution, treat it as a **park** — post a `blocked` comment on the issue naming the denied tool, apply the `blocked` label (+ `in progress` if the branch has commits), preserve the branch, and return the structured handback with `status: parked`, `parkLabel: "blocked"`, and `parkReason: "auto-deny on <tool>"`. This is the same park-don't-prompt contract all other gates use — an auto-deny is not a silent failure.

### Parallel mode (`--parallel`) — Phase 1: concurrent worker dispatch

This subsection applies **only** when parallel mode is active (recognized per **`--parallel` activation** above). **Absent the `--parallel` token / NL trigger, none of this runs and the sequential loop (steps 1–5) is byte-unchanged.** Parallel mode splits into two phases that share this skill's Phase 0 triage and dependency graph:

- **Phase 1 (this issue, #72)** — concurrent build + barrier. Builds the parallelizable set in a worktree fleet, but **does not integrate**. The barriered green set is held (branches built + pushed) for Phase 2.
- **Phase 2 (#73)** — the **serial verified merge tail**. Integrates the held green set to `integrationBranch` one branch at a time, running the deferred gates (E2E, any server-starting preflight) once against accumulated state. See `### Parallel mode (--parallel) — Phase 2: serial verified merge tail` below.

The parallel path completes across both phases: Phase 1 builds-but-does-not-integrate and barriers the green set; Phase 2 integrates that green set through the serial verified merge tail.

When active, after Phase 0 triage, process the milestone **Wave by Wave** (same Wave order the sequential loop uses). **Each Wave runs to completion across BOTH phases before the next Wave begins:** Phase 2 runs to completion at the end of the Wave — its squash-merges land on `integrationBranch` and the local `integrationBranch` is re-synced — **before** the next Wave's Phase 1 step 1 cuts its worktree fleet from `integrationBranch`. This makes a dependent Wave N+1 build on Wave N's integrated result (exactly like the sequential loop), so buildability condition (a) sees Wave N's upstream edges already merged rather than stale pre-Wave-N state. For each Wave:

1. **Compute the parallelizable set.** Per the `### Parallelizable-set selection` subsection above: the set is **buildable ∧ mutually-independent** (the (a)/(b)/(c) buildability conditions plus the intra-set independence guard). An empty set (every Wave issue parked or dependency-held) advances to the next Wave with nothing dispatched.

2. **Create the worktree fleet (orchestrator-owned).** The orchestrator creates **one worktree per set issue** into the gitignored scratch dir `.milestone-driver-worktrees/`:

   ```
   git worktree add .milestone-driver-worktrees/issue-<n> -b issue/<n>-<slug> <integrationBranch>
   ```

   **Pre-clean guard (resume-aware: makes fleet creation idempotent / re-runnable without destroying in-progress work).** `git worktree add` hard-fails if either the path `.milestone-driver-worktrees/issue-<n>` or the branch `issue/<n>-<slug>` is a leftover from a prior or interrupted run (`fatal: '…' already exists`, or `fatal: a branch named '…' already exists`), and `git worktree prune` does **not** remove an intact leftover directory. But a leftover branch may carry **real in-progress work** — commits from a worker that was interrupted (or parked) after committing but before pushing. `git branch -D` is a **force** delete that silently discards such unpushed commits, so the guard must **preserve-don't-clobber**: clear only provably-safe leftovers, and **resume** any leftover that carries work. Before each `git worktree add`, decide per leftover branch `issue/<n>-<slug>`:
   - **No leftover at all (cold case):** `git worktree add .milestone-driver-worktrees/issue-<n> -b issue/<n>-<slug> <integrationBranch>` as shown above.
   - **Leftover branch carries commits ahead of `integrationBranch` that are not yet pushed/merged** (in-progress work from an interrupted or parked prior run — check with `git rev-list --count <integrationBranch>..issue/<n>-<slug>` and confirm those commits are not on `origin/issue/<n>-<slug>`): do **NOT** `git branch -D`. **Attach a worktree to the existing branch** — `git worktree add .milestone-driver-worktrees/issue-<n> issue/<n>-<slug>` (no `-b`; checks out the existing branch with its commits) — and dispatch the worker against it. The worker's branch-state probe (`solve-issue` resume paths (a)/(b)/(c)) then **resumes** that work instead of losing it. (If a stale worktree **directory** is registered at that path, `git worktree remove --force .milestone-driver-worktrees/issue-<n>` / `git worktree prune` the directory entry first — but the **branch and its commits are preserved**.)
   - **Leftover is provably safe to discard** — the branch is **0 commits ahead** of `integrationBranch`, **or** already merged, **or** already pushed (its work survives on `origin`): clear it fully — `git worktree remove --force .milestone-driver-worktrees/issue-<n>` (if registered/present), `git worktree prune` (clear stale admin entries), `git branch -D issue/<n>-<slug>` — **then** create fresh with `git worktree add .milestone-driver-worktrees/issue-<n> -b issue/<n>-<slug> <integrationBranch>`.

   This **mirrors** the plugin's resume culture (`solve-issue`'s branch-state probe / resume paths (a)/(b)/(c)): re-running preserves in-progress work and only clears leftovers that are provably safe to discard — never force-deleting a branch that carries unpushed commits.

   The orchestrator owns `git worktree add` (consistent with the #70 worker contract, `solve-issue` Delta 1) — the worker runs **inside** the provided worktree and never cuts its own branch. Use explicit fleet management (`git worktree add -b … / remove / prune`); do **not** lean on generic worktree isolation, which can strand the shared checkout on a stray `issue/<n>` branch and leave worktrees needing prune.

3. **Dispatch concurrently, capped at 4.** Before dispatching: if `unitTestCmd` is defined in the profile (checkable) **and** `--parallel` mode is active (checkable), emit a one-time advisory: _"⚠ Parallel unit runs share external services (notably the test DB) unless the consumer's harness isolates per worker — see docs/consumer-setup.md §DB isolation under --parallel."_ Then proceed with parallel dispatch regardless; do not serialize.

   The permission pre-flight gate (see `### Permission pre-flight gate`) runs **once per run, before the first background dispatch in step 3**. If a gap is found → fall back to synchronous dispatch for this run. If no gap → proceed with background dispatch as described here.

   Dispatch **one background agent per set issue** as `Agent(run_in_background: true)` running:

   ```
   /milestone-driver:solve-issue <n> --worker
   ```

   in worker mode (#70), passing the issue's worktree path. The brief MUST embed the per-issue triage result as explicit named fields with ACTUAL VALUES — e.g. `issueStates["<n>"] = { blockers: false, label: null, advisories: [...], risk: "light" }` and `edges["<n>"] = [...]` (the concrete arrays/objects, not just the field names). A brief whose triage fields are absent, label-only, or partial causes the worker's step 0 to fall to Branch B (fresh single-issue triage) — this is the enforcement mechanism; Branch B is the safe default, never an error. Run the dispatches **concurrently, with no more than 4 workers running at once**. If the set is larger than 4, use a **rolling window / batches** so the in-flight count never exceeds 4 (as one worker returns, dispatch the next). Cap 4 is a safe, conservative default (field-validated: 5 concurrent builds + 5 reviews ran with no contention; 4 is the chosen default).

   **Workers never call PushNotification** — confirmed absent from subagent tool registries (see issue #97 recorded decision); workers return park/completion facts in the structured handback; the main line emits at Wave boundaries. **SendMessage/mid-chunk redirect does not exist in Claude Code** — do not narrate it.

   **Phase-2-before-next-Wave guarantee (explicit constraint).** Phase 2 runs to completion at the end of each Wave — its squash-merges land on `integrationBranch` and the local `integrationBranch` is re-synced — **before** the next Wave's Phase 1 step 1 cuts its worktree fleet from `integrationBranch`. This prevents port-binding-gate contention across waves and ensures every Wave builds on the prior Wave's fully integrated result.

4. **Barrier on the whole set.** **Await ALL completion notifications from dispatched background agents** before proceeding to Phase 2. This is the **barrier**: the Wave does not advance and Phase 2 does not begin until ALL background agents have returned their completion notification — i.e. until the entire dispatched set has completed.

5. **Collect handbacks.** Each worker returns the structured handback (#70):

   ```text
   { issue, status: built-green | parked, branch, worktreePath, prUrl?, isUI, declarations, parkLabel?, parkReason? }
   ```

   Separate `built-green` from `parked`:
   - **`built-green`** workers form the green set handed to Phase 2 (branches built + pushed, per-issue PR opened in issue granularity).
   - **`parked`** workers are **excluded from the merge tail**. The park was already handled inside the worker (park-don't-prompt): its **branch, label, and comment stay intact**. The orchestrator does not re-park or re-label — it simply omits the issue from Phase 2, exactly as the sequential loop excludes a parked issue, signaled through the handback rather than inferred from labels. For each parked handback, **emit one `⏸️ #N parked — <reason>` notification** (using `parkLabel` + `parkReason` from the handback) **before emitting the aggregate 🌊 wave-boundary notification**.

6. **Cleanup the fleet.** The orchestrator removes a worktree once it is integrated by Phase 2, **or** its issue parked, **or** at Wave end / run end:

   ```
   git worktree remove .milestone-driver-worktrees/issue-<n>
   ```

   A built-green worker has already **pushed its branch** (and, in issue granularity, opened a PR), so its **local worktree is safe to remove at Wave end / run end regardless of Phase 2** — the work is preserved on the remote branch / PR, not in the local worktree. Removing at Wave end / run end (rather than gating cleanup on Phase 2) prevents built-green worktrees from being orphaned, and — together with step 2's pre-clean guard — keeps the next `--parallel` run collision-free. Run `git worktree prune` **best-effort** at Wave end, at run end, and on systemic failure, to clear any stale fleet entries. The scratch dir `.milestone-driver-worktrees/` is gitignored, so the fleet never pollutes the working tree or a commit.

7. **Hand the green set to Phase 2.** The barriered `built-green` set is held (branches built + pushed) and integrated by **Phase 2 — the serial verified merge tail (#73)**. The split is explicit: **Phase 1 = concurrent build + barrier; Phase 2 (#73) = the serial verified merge tail below.** Phase 1 performs **no merge to `integrationBranch`** — workers build-but-do-not-merge (#70 Delta 2), and the green set waits at the barrier for Phase 2.

**Blast-radius boundary unchanged.** As in sequential mode, workers and the serial tail merge only to `integrationBranch`, **never** `protectedBranch`. Parallel mode adds concurrency and a worktree fleet; it does not widen the blast radius. **Reaffirmed: absent the `--parallel` token / NL trigger, none of Phase 1 runs and the sequential loop (steps 1–5) is byte-unchanged.**

### Parallel mode (`--parallel`) — Phase 2: serial verified merge tail

This subsection applies **only** when parallel mode is active (recognized per **`--parallel` activation** above). It runs **after** Phase 1's barrier, consuming the barriered `built-green` handbacks. **Phase 2 runs to completion at the end of each Wave** — its squash-merges land on `integrationBranch` and the local `integrationBranch` is re-synced — **before** the next Wave's Phase 1 step 1 cuts its worktree fleet from `integrationBranch`. A dependent Wave therefore always builds on the prior Wave's integrated result, exactly as the sequential loop guarantees. **Parked** workers are excluded — Phase 1 already omitted them, with branch + label + comment intact. **UI built-green issues are also NOT merged here** — they are held open with the `needs review` label (the Layer-2 visual gate, `solve-issue` step 7, unchanged). The tail integrates **only the non-UI built-green branches**.

**Run on the main working tree** (not in a worktree), over the built-green non-UI branches in **ascending-issue order**. **Force-free by default (merge-in — no history rewrite).** The **integration target advances after each merge**, so two same-Wave siblings that touch overlapping files are re-verified against each other — restoring the "every increment tested against accumulated state" guarantee that naive concurrent merging throws away. For each such branch:

1. **Merge the integration target INTO the worker branch.** `git fetch`, then `git merge <target>` where `<target>` is `integrationBranch` in issue granularity, or the **wave branch** in wave granularity (#75; see `### Integration granularity (issue vs wave)` below). This brings accumulated state onto the worker branch as an ordinary merge commit — a **fast-forwardable** push, **no `--force`**.
2. **Clean merge** → push (fast-forward) → **re-verify against accumulated state**: run `unitTestCmd` if defined, **plus the worker-deferred E2E / port-binding gates** (the gates the worker deferred per #70) — run **once here against accumulated integrated state**, where they are more meaningful. On green → `gh pr merge --squash --delete-branch` → re-sync local `integrationBranch` (`git fetch`, fast-forward). The `--squash` collapses the merge-in commit so the integration target's history stays linear.
3. **Conflict** → **bounded auto-resolve**: attempt resolution with full-milestone context (git's `ort` strategy already auto-resolves non-overlapping same-file edits — e.g. two siblings each appending a distinct route to the same file), then re-verify. **Resolvable AND green** → proceed to step 2's merge. **Non-trivial / ambiguous OR red** → `git merge --abort`, **park `blocked`** (comment + label + preserve branch), continue with the next branch.
4. **Clean merge but red re-verify** → **park `blocked`** (the combination is broken; a human decides), continue with the next branch.

**Why merge-in, not rebase + force (field-found).** A history-rewriting push is fragile across consumer safety setups: in a real run, `--force-with-lease` (and the delete-then-fresh-push fallback) were **BLOCKED** by two independent guards — a consumer destructive-command hook that treats the safe `--force-with-lease` like a raw `--force`, and the runtime's destructive-action classifier. A `no-push` hook permitting the push is **necessary but not sufficient** when those other guards stand. **Merge-in gives the identical re-verify guarantee with no history rewrite**, so it is the default. The **rebase + `--force-with-lease` variant stays available** as the allow-list-required alternative — but it **MUST be allow-listed** in the consumer's hooks / destructive-action classifier first.

**Reaffirm the blast-radius boundary:** the serial tail merges only to `integrationBranch`, **never** `protectedBranch`.

**Wave-boundary notification.** After Phase 2 completes for a Wave (all built-green non-UI branches merged, UI PRs held open, parked workers excluded) and before the next Wave's Phase 1 begins, emit a `PushNotification` — **only when another Wave follows** (🌊 is suppressed on the final Wave; the 🏁 run-complete notification is the single end signal):
```
🌊 Wave N done · X/Y ✅ · next: Wave N+1
```
Where N = the just-completed Wave number, X = issues merged this Wave (non-UI built-green, by Phase 2), Y = total issues in this Wave (all outcomes: merged + parked + triage-parked), next = Wave N+1 number. Parked-wave notifications (Class 1, per-issue) are already emitted individually as each park occurs; this wave-boundary notification covers the Wave's aggregate result.

### Integration granularity (issue vs wave)

`integrationGranularity: "issue" | "wave"`, default `"issue"`. This controls **how built issues integrate**, and is **orthogonal to `--parallel`** (which controls *how* issues build). The two combine or apply independently: any of {sequential, `--parallel`} × {`"issue"`, `"wave"`} is valid.

**`"issue"` (default) — byte-unchanged.** Today's model, unchanged. Each built issue opens **its own PR** → its own CI run → merges individually: in sequential mode each issue's `solve-issue` opens and merges its own PR (steps 1–5 / Phase 2 unchanged); in `--parallel` mode the Phase 2 serial verified merge tail merges each built-green PR in turn. Nothing in this path changes — the sequential loop, the buildability conditions, and the Phase 1 / Phase 2 mechanics are exactly as documented above.

**`"wave"`.** The merge-tail **MECHANISM is unchanged** (merge-in + re-verify against accumulated state + bounded auto-resolve, #73); only the **target** and **PR-opening** differ:

- **Worker opens no per-issue PR.** The worker (#70) builds + verifies + commits + pushes its branch and **hands it back** — it opens **no per-issue PR** (the `solve-issue` worker contract is already granularity-conditional: Wave granularity → no per-issue PR). Its handback carries no `prUrl`.
- **Integrate into a wave branch.** The orchestrator integrates the Wave's built-green **logic** branches into a **wave branch** `wave/<milestone>-w<N>` (N = the Wave number). **Create the wave branch fresh and idempotently:** unlike the per-issue `issue/<n>-<slug>` branches — which may carry **unpushed** worker commits that Phase 1's resume-aware pre-clean guard must preserve-don't-clobber (step 2) — the wave branch is a **regenerable integration artifact**, assembled entirely from the already-pushed per-issue logic branches, so it carries no unique unpushed work and is **safe to force-clear and rebuild** on every run. Before creating it, if a stale leftover exists from an interrupted prior run, delete it (`git branch -D wave/<milestone>-w<N>` locally; `git push origin --delete wave/<milestone>-w<N>` if it was pushed) and recreate it fresh from the current `integrationBranch` tip — no preserve concern, because the source work lives on the pushed per-issue logic branches. This keeps the wave path re-runnable, consistent with Phase 1's fleet idempotency. Then apply the **#73 policy unchanged**: merge each branch into the wave branch, re-verify against accumulated state (unit + deferred E2E / port-binding gates), bounded auto-resolve on conflict, else park `blocked` (label + comment + preserve branch) and continue with the next branch. The integration target is the wave branch, so siblings are re-verified against each other exactly as in the per-issue tail.
- **One wave PR.** The orchestrator opens **one wave PR** → `integrationBranch` whose body lists the Wave's logic issues. On **CI green**, it **squash-merges** the wave PR. A repo with **no required checks (no CI)** is **vacuously green** — proceed to squash-merge immediately, exactly as the per-issue path does (with no required status checks to gate on, `gh pr merge --squash` is mergeable; same behavior the per-issue auto-merge relies on, `solve-issue` step 8). Auto-merge-on-green moves from per-issue to **per-wave** — the whole assembled Wave merges on one green CI run.
- **Explicit issue close (do NOT rely on the `Closes #…` keyword).** A GitHub `Closes #n` keyword auto-closes an issue only when the PR merges into the repository's **default** branch. The wave PR targets `integrationBranch`, which is typically **not** the default branch (e.g. `develop` vs `main`), so the keyword would **not** fire. Therefore, after the wave PR squash-merges, the **orchestrator explicitly closes the Wave's logic issues** — `gh issue close #a #b #c --reason completed` — exactly as the per-issue path closes issues as a separate explicit action (the orchestrator merges and closes). If `integrations.trello` is present and a card handle was resolved, tick the checklist items for all logic issues just closed per `trello-sync.md § Wave granularity` (under `## Loop hooks`; best-effort per item; failure logged, loop continues). The wave PR body may still list the issues for traceability, but the close is the explicit `gh issue close` step, never the keyword.
- **Wave-branch disposition + re-sync.** After the wave PR squash-merges, **delete the wave branch** (`gh pr merge --squash --delete-branch`, plus `git branch -D wave/<milestone>-w<N>` locally if a local copy remains) and **re-sync the local `integrationBranch`** (`git fetch`, fast-forward) **before the next Wave** — consistent with the per-issue tail's `--delete-branch` + re-sync (Phase 2 step 2).

**Logic-only carve-out.** The Layer-2 visual gate is per-UI-issue, so a single wave PR cannot both auto-merge (logic) and hold open (UI). A Wave containing UI issues keeps those **per-issue / held**: each UI issue's worker opens its own PR with the `needs review` label (issue-granularity handling for that issue, held open for human visual sign-off), and **only the logic issues join the wave branch**. The wave PR's explicit-close list scopes **only the logic issues that actually joined the wave branch** — never the held UI issues.

**All-UI wave.** A Wave whose **entire** built-green set is UI issues opens **no wave branch and no wave PR** — every issue is held per-issue for visual sign-off, and there is nothing to integrate at the wave level.

**Trade-off.** O(waves) CI runs vs O(issues); CI validates the **assembled** Wave, catching integration-level issues an isolated per-issue build misses. But **one red wave-PR CI blocks the whole Wave** — acceptable because the strong local gates (unit + static preflight + `/code-review` + the tail's re-verify) catch most failures **before** CI; CI is the backstop. **Not** for repos with weak local gates.

**Reaffirm the blast-radius boundary:** the wave PR targets `integrationBranch`, **never** `protectedBranch`.

### 5. Finish
Continue until every issue is done (merged), held at the visual-review gate (a UI issue with an open `needs review` PR awaiting human visual sign-off), or parked. The run ends when no more buildable issues remain — not because it is waiting on a human.
If `integrations.trello` is present, apply `## Finish hooks` from `skills/solve-milestone/trello-sync.md` (best-effort — Trello failures never block the run; skipped updates surface in the final summary).

## Autonomy

- **Unattended between systemic failures.** Within an explicit `/milestone-driver:solve-milestone` run, operate autonomously. A `solve-issue` STOP or PAUSE **parks** that issue (label + open branch + comment) and the loop continues — it does **not** halt the loop. Only a systemic failure ends the run early.
- **Systemic failures that halt the run** (examples): `gh auth` failure, a broken or inaccessible `integrationBranch`, missing required tooling (`gh`, `git`). These are conditions where no further issue can make progress. Surface the failure, leave the working tree clean and all in-flight issues parked, then present the final summary and stop — the **Run-complete notification** block (below `## Final summary`) emits the `🚨 Run halted — <reason>` notification as its last step.
- **Architecture is locked** per issue at its plan-approval time. The loop executes approved architecture; it does not pivot. A plan proven wrong is a park (STOP → park + continue), not a silent redesign. For the bounded definition of architecture vs implementation detail (the decision test), see the Autonomy model in `solve-issue`.
- **Never escalate scope to `protectedBranch`.** No PR, push, or merge targets `protectedBranch` (enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection).

## Output spec

<!-- KEEP THIS ICON LEGEND BYTE-IDENTICAL across solve-issue and solve-milestone (see plan 2026-06-04 verification model). -->
**Icon legend:** ✅ merged · 🔨 building · ⏭️ queued · ⏸️ parked · 👁️ awaiting visual review · ⚖️ judgment call · 🔴 Your move

### Template 1 — Run start / plan board

Show after Phase 0 triage completes.

```text
🚀 Milestone v[version] — [N] issues · [W] waves · [--parallel | sequential] · ~[T]–[T2] min
   develop ← integration PRs · profile: <H> heavy / <L> light

| Wave | Issue | Title                    | Risk  | UI | Status      |
|------|-------|--------------------------|-------|----|-------------|
| 1    | #201  | Background wave dispatch | heavy | —  | 🔨 building |
| 2    | #203  | Status board templates   | light | 👁️  | ⏭️ queued   |

⏸️ Parked at triage: #202 — needs design (contradictory grouping spec)
▶ Wave 1 dispatched — the floor is yours.
```

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

Use as the layout for the Final summary section (see `## Final summary` below).
<!-- Post-run summary: columns differ from Template 2 by design — Gates is omitted (not relevant post-merge), Result → Outcome, Note → Follow-up (action-oriented framing). -->
Populate the metadata lines below the table from the `## Final summary` requirements below: derive each field from the run's tracked context.

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
3. All merged → integration → protected, deploy
```
PR cell: show the PR number if the issue has one, else —.

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present steps, gates, lists, and options as **tables**, not inline prose. Mark anything that needs a human with 🔴. (Mirrors the agents' communication-style contract.)

Use the templates in `## Output spec` at their prescribed trigger points. Between boards: one-line dispatch notes only — no narration paragraphs.

## Final summary

Use Template 3 from `## Output spec` (above) as the layout for this summary. All content requirements below remain in effect — each bullet maps to a row or section in the template.

On completion or systemic-failure halt, report:

- **Issues built and merged** to `integrationBranch` (with PR links).
- **Issues parked** — for each: the issue number and title, the park label applied, the blocker reason, and the open feature branch (if applicable). Report each parked issue's blocker reason from the run's tracked context — the loop recorded WHY each issue was parked as it happened (the triage gap, the STOP/PAUSE reason, or the unmerged upstream). If a reason is not in active context, read the issue's comments (`gh issue view <n> --json comments`) and use the most recent format-matching comment on the issue (which may be from a prior run — e.g. a cache-HIT park posts no fresh comment). A format-matching comment is one whose body opens with `🔴 Triage` (triage-park), `🔴 Blocked` (dependency-hold), or `🔴 Parked` (build-park). gh returns comments oldest-first — take the LAST format-matching comment. Back-compat note: issues parked by pre-1.7.0 runs may carry un-anchored build-park comments; if no anchored match exists, report "park reason not recorded (pre-1.7.0 park format)". Do **not** invent or hallucinate a reason.
- **Open UI PRs** awaiting human merge: PRs carrying the `needs review` label (UI issues per issue #18 that were built but left open for visual sign-off), listed with their PR links.
- **PRs carrying a `judgment call` label**, flagged for post-run review.
- **PRs missing a `## Code Review` section** in their body — flagged, like `judgment call` PRs, as requiring post-run human review before the `integrationBranch` → `protectedBranch` merge.
- **Auto-resolved-conflict issues** (parallel mode) — issues whose merge conflict the serial verified merge tail **auto-resolved** (bounded auto-resolve) before merging, listed so a human can sanity-check the reconciliation.
- **Per-Wave parallel-set sizes** (parallel mode) — for each Wave, how many issues built **concurrently** (the parallelizable-set size dispatched that Wave).
- **The run ended because** all issues are done (merged), held at the visual-review gate (open `needs review` PRs), or parked — not because it is waiting on a human.
- The next human step: review parked issues and the open `needs review` PRs; clear the park labels when the blockers are resolved and re-run to pick up the remaining work; when all work is merged, merge `integrationBranch` → `protectedBranch` and deploy manually.

**Output ordering (clean-completion path only):** On the clean-completion path, do not emit the Template 3 final summary until after step 6 completes (see step 6.9 — the CHANGELOG result is appended to the `🔴 Your move:` section before the summary is output). On the systemic-halt path, step 6 is skipped entirely (per step 6's preamble) — emit the Template 3 final summary immediately.

### 6. Author the CHANGELOG entry

**This step runs on the CLEAN COMPLETION PATH ONLY.** When the Autonomy section's systemic-halt path reaches the Final summary, skip this step entirely and proceed directly to the Run-complete notification. The systemic-halt path is identified by the fact that the run ended with a 🚨 reason (not a 🏁 reason).

**Guard — skip this step entirely if any condition holds:**

- The parked count for this run is greater than zero (any issue was parked), OR
- The run ended via a systemic halt (see preamble above)

The parked count is derived from this run's **in-context tracking** — it counts ALL issues that did not reach "merged" or "held at visual-review gate" status in this run: issues parked at build time, issues skipped due to triage blockers, AND issues excluded by the buildability check due to a live blocker label (e.g., `blocked` from a prior run). This is the `⏸️ P` count in Template 3's summary line. Do NOT re-derive via a live `gh issue list` query — a live query may find labels unrelated to this run's completion status.

If any condition holds, post to the run output: _"Skipping CHANGELOG authoring — run did not fully complete (N parked)."_ and proceed directly to the Run-complete notification.

Only proceed through steps 6.1–6.9 when **every issue in the milestone is either merged (non-UI) or held at the visual-review gate (UI)** — i.e. no parks. Visual-review holds (open `needs review` PRs for UI issues) are expected clean-completion state and do NOT block CHANGELOG authoring.

#### 6.1 Idempotency check

Determine the heading prefix based on the versioning mode:

- **Versioned mode** (`versioning: true` or absent): prefix is `## v<target-version> ` (with a trailing space)
- **Version-free mode** (`versioning: false`): full-line equality match after stripping whitespace: `trim(line) == '## <milestone title>'`. Strip leading and trailing whitespace (including `\r` on Windows) from each line before comparing — the trimmed line content must equal the heading with no additional characters. This prevents false-positive matches against entries like `## Q3 Hardening` when the current milestone is titled `Q3`.

If `CHANGELOG.md` exists on `integrationBranch`, read it (`git show <integrationBranch>:CHANGELOG.md` or read the working-tree copy after re-sync). Scan each line for the prefix starting at the beginning of the line. For versioned mode use a line-start prefix match on the trimmed line; for version-free mode use a full-line equality match after stripping whitespace: `trim(line) == '## <milestone title>'`. If a match is found → log _"CHANGELOG entry for `<version/title>` already exists — skipping."_ and proceed to the Run-complete notification. If no match → continue.

If `CHANGELOG.md` is absent, treat it as "no existing entry" and continue.

#### 6.2 Fetch PR summaries

For each issue merged in this run, look up its PR number from the **run's in-context issue→PR tracking table** (the same data that populates Template 2 and Template 3's PR column). If the PR number for a particular issue is not in active context, fall back to querying the issue's closing PR references:

```bash
gh issue view <n> --json closedByPullRequestsReferences --jq '.closedByPullRequestsReferences | map(select(.state == "MERGED")) | .[0].number // empty'
```

Before calling `gh pr view`, verify the PR number returned by the query is non-null and non-empty. If it is null or empty (no linked PR found), apply the following fallback: use the issue title as the What-column content for that issue and skip `gh pr view` for that issue. Record the gap in the run output: _"No merged PR found for issue #N — using issue title as summary."_

When a valid PR number is confirmed, call:

```bash
gh pr view <pr-number> --json title,body
```

Extract the summary line:

1. Look for a `## Summary` heading in the body (case-insensitive match on the heading text).
2. Take the **first non-blank line** immediately following that heading.
3. If no `## Summary` section is found, fall back to the PR title.

Record a triple for each issue: `{ issue: #N, pr: #P, summary: "<extracted line>" }`.

#### 6.3 Categorize issues

Group the merged issues into two buckets based on labels and title prefixes:

- **✨ Features / enhancements:** issues with label `enhancement`, `feature`, or title prefixes `feat(`, `polish(`. Issues that don't clearly match either bucket default to this one.
- **🔧 Fixes:** issues with label `bug` or `fix`, or title prefixes `fix(`.

A single issue belongs to exactly one bucket. If an issue matches both, prefer the fix bucket.

#### 6.4 Determine the milestone theme

1. Read the milestone description (`gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '.description'`).
2. Look for a dedicated theme line (a line starting with `Theme:` or `**Theme:**`). Use the text after the prefix as the one-sentence theme description.
3. If no theme line is found in the description, use the milestone title as both the heading theme and the theme description.

#### 6.5 Author the CHANGELOG entry

Construct the markdown block using the structure below. Mirror the v1.7.0 entry in `CHANGELOG.md` exactly — same heading format, same table schema, same section names.

**Versioned mode entry:**

```markdown
## v<target-version> — <milestone theme>

**Theme:** <one-sentence theme description>

### ✨ <Feature category label>

| Issue | PR | What |
|---|---|---|
| #N <issue title> | #P | <summary line> |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #N <issue title> | #P | <summary line> |

### Consumer notes (upgrading from <prev version>)

- <upgrade-relevant behavior changes, new artifacts, schema impact>
- **No schema changes** to `milestone-driver.json` (include this line only when true)

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: <comma-separated list of PRs with `judgment call` label, or "none">
```

**Version-free mode entry** (omit the version number and theme suffix; include Consumer notes and ⚖️ Post-run audit trail sections using the same rules as versioned mode — only the heading format differs):

```markdown
## <milestone title>

**Theme:** <one-sentence theme description>

### ✨ <Feature category label>

| Issue | PR | What |
|---|---|---|
| #N <issue title> | #P | <summary line> |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #N <issue title> | #P | <summary line> |

### Consumer notes

- <upgrade-relevant behavior changes, new artifacts, schema impact>
- **No schema changes** to `milestone-driver.json` (include this line only when true)

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: <comma-separated list of PRs with `judgment call` label, or "none">
```

Rules for authoring the entry:

- Omit the `### 🔧 Fixes` section entirely if there are no fix-bucket issues.
- Omit the `### ✨` section entirely if there are no feature-bucket issues (unusual, but possible).
- Feature category label: derive from the milestone theme or title (e.g. "Background orchestration", "Scannable output"). If none is obvious, use "Features / enhancements".
- Consumer notes: summarize new profile keys, changed behavior, new gitignored artifacts, schema changes — authored from what was actually built. Include the "No schema changes" line only when confirmed true.
- Post-run audit trail: list PRs carrying the `judgment call` label **from this run's in-context issue→PR tracking set** (the same set used for the Template 3 row entries — do NOT re-query `gh pr list`; read from context); write "none" if the list is empty.
- Prev version for the Consumer notes header: derive from the most recent `## v...` heading already in `CHANGELOG.md`. If CHANGELOG is absent or contains no `## v...` heading, use `git log --oneline --all -- CHANGELOG.md` to find the most recent commit that touched CHANGELOG.md, then run `git show <commit>:CHANGELOG.md | grep '^## v' | head -1` to extract the most recent version heading from history. If no prior CHANGELOG exists in history, omit the prev-version parenthetical from the Consumer notes heading and use simply `### Consumer notes`. Do NOT use `plugin.json` as a fallback — `plugin.json` holds the target version, not the previous one.

**Prepend the entry** into `CHANGELOG.md` after the file header (the `# Changelog` line and any intro prose that precedes the first `## v...` entry) but before that first `## v...` entry. Preserve the file header verbatim. If `CHANGELOG.md` is absent on `integrationBranch`, create a new one with a standard `# Changelog` header and intro paragraph, then append the new entry below. To retrieve an existing structure as a template: first run `git log --oneline --all -- CHANGELOG.md` to find the most recent commit that touched the file, then run `git show <commit>:CHANGELOG.md` to retrieve the content. If no prior version exists in history, use a minimal header (`# Changelog` followed by a blank line).

#### 6.6 Determine the branch name

- **Versioned mode:** `docs/changelog-v<target-version>` (e.g. `docs/changelog-v1.8.0`)
- **Version-free mode:** `docs/changelog-<milestone-slug>`, where slug = milestone title lowercased, spaces replaced by hyphens, non-alphanumeric characters (except hyphens) removed (e.g. milestone "Q3 Hardening" → `docs/changelog-q3-hardening`)

#### 6.7 Open the doc-only PR

Cut the branch from the current `integrationBranch` tip (step 6.7 re-syncs integrationBranch inline before branching — do not rely on a prior re-sync having occurred):

If the docs branch already exists from a prior interrupted run (local or on remote), check it out instead of creating it anew. This makes step 6.7 re-runnable.

```bash
# Ensure integrationBranch is current before cutting the docs branch
git checkout <integrationBranch>
git fetch
git merge --ff-only origin/<integrationBranch>
# Guard: if the docs branch already exists from a prior interrupted run, check it out instead of creating a new one
if git show-ref --verify --quiet refs/heads/docs/changelog-<slug>; then
  git checkout docs/changelog-<slug>
elif git ls-remote --exit-code origin docs/changelog-<slug> > /dev/null 2>&1; then
  git checkout --track origin/docs/changelog-<slug>
else
  git checkout -b docs/changelog-<slug> <integrationBranch>
fi
# edit CHANGELOG.md as authored in step 6.5
# If CHANGELOG.md was already committed on this branch (re-run after interruption), the commit is skipped (CHANGELOG is already in place).
git add CHANGELOG.md
# Run exactly ONE of the following — choose based on versioning mode:
git diff --cached --quiet || git commit -m "docs: v<version> release notes"           # VERSIONED MODE
# git diff --cached --quiet || git commit -m "docs: <milestone-title> release notes"  # VERSION-FREE MODE
# Run the versioned commit line when `versioning` is true or absent; uncomment the version-free line (and comment out the versioned line) when `versioning: false`.
git push -u origin docs/changelog-<slug>
# Check if a PR already exists for this branch (re-run safety)
existing_pr=$(gh pr list --head "docs/changelog-<slug>" --json number --jq '.[0].number // empty' 2>/dev/null)
if [ -n "$existing_pr" ]; then
  echo "CHANGELOG PR already open: #$existing_pr"
else
  # PR title uses the versioned or version-free form depending on mode:
  #   Versioned:    "docs: v<version> release notes"
  #   Version-free: "docs: <milestone-title> release notes"
  gh pr create \
    --base <integrationBranch> \
    --title "docs: <title>" \
    --body "$(cat <<'EOF'
## CHANGELOG preview

<paste the authored CHANGELOG entry verbatim here>

---

_This entry doubles as the GitHub-release body for the human release step._
EOF
)"
fi
```

Record the PR number and URL — either the newly created PR or the existing one found by the re-run guard.

#### 6.8 Handle CI result

The PR is doc-only; CI is typically vacuously green (no required status checks on a documentation-only change). Immediately attempt:

```bash
gh pr merge <pr-number> --squash --delete-branch
```

- **Success (CI green or no CI):** record _"CHANGELOG entry merged."_ and record the merge for the final summary. Then clean up the working tree:

  ```bash
  git checkout <integrationBranch>
  git fetch
  git merge --ff-only origin/<integrationBranch>   # fast-forward local branch to include the squash-merge commit
  # fast-forward local branch — git fetch alone does not advance the local ref
  git branch -d docs/changelog-<slug>   # safe to delete: local tip is reachable from integrationBranch after fast-forward
  ```

- **CI red:** do **not** block or fail the run. Apply the `needs review` label to the CHANGELOG PR (`gh pr edit <pr-number> --add-label "needs review"`). Add a 🔴 item to the run output:

  > 🔴 CHANGELOG PR needs human merge (CI red): #P — <pr-url>

  Return to `integrationBranch` but preserve the local `docs/changelog-<slug>` branch (the remote PR is still open and needs the branch):

  ```bash
  git checkout <integrationBranch>
  # do NOT delete the local docs/changelog-<slug> branch — remote PR is still open
  ```

  Do NOT re-attempt the merge. Proceed to the Run-complete notification.

#### 6.9 Surface in the final summary "Your move" section

**Output ordering:** The Template 3 final summary MUST NOT be emitted until step 6 completes. Hold the summary in-context through steps 6.1–6.8, then add this line to the `🔴 Your move:` section, and emit the complete Template 3 only after step 6.9.

Add one line to the `🔴 Your move:` list in Template 3 (the final summary):

- **Merged:** `CHANGELOG entry merged → use as GitHub release body (#P)`
- **Held open (CI red):** `🔴 CHANGELOG PR needs human merge (CI red): #P`

**Label collision note:** A CHANGELOG PR carrying the `needs review` label must be surfaced in the `🔴 Your move:` list only — it must NOT appear in the `👁️ open` rows of Template 3. The Final summary's "Open UI PRs awaiting human merge" bullet is scoped to PRs opened for issues in this run's issue set (cross-referenced against the run's in-context issue→PR tracking table), not all `needs review` PRs in the repo.

**Run-complete notification.** After presenting the final summary (Template 3), emit a `PushNotification`:
- **Clean completion**: `🏁 <milestone-title> · ✅ M merged · 👁️ U open · ⏸️ P parked` (where M, U, P are the counts from Template 3).
- **Systemic halt** (invoked from the Autonomy section's halt path): `🚨 Run halted — <reason>` (where `<reason>` is the systemic-failure description, e.g. "gh auth failure").
