---
name: solve-milestone
argument-hint: <milestone-name | milestone-number>
description: This skill should be used when the user invokes "/milestone-driver:solve-milestone <name>", or asks to "solve a milestone", "drive a milestone", or "work the milestone autonomously". Autonomously iterates every issue in a GitHub milestone in dependency order, running /milestone-driver:solve-issue on each and re-syncing the integration branch between issues. Runs unattended; parks blocked/gapped issues and continues with clean ones — never waits on a human; only a systemic failure ends the run early. Builds mutually-independent issues within a Wave concurrently in git worktrees by **default** (no flag); a run-start barrier check drops to sequential only when a barrier is present — a `parallel: false` profile opt-out, a permission-allowlist gap, or an unconfirmed test-isolation answer.
---

# solve-milestone — autonomous driver

Drive an entire GitHub milestone to completion by ordering its issues and running `/milestone-driver:solve-issue` on each, integrating to `integrationBranch` between issues. This skill owns **ordering, the loop, branch re-sync, parking, and the final summary**; the full per-issue pipeline — root-cause, implementer dispatch, gates, review, PR, auto-merge on green (non-UI) or visual-review hold (UI), close — is delegated to `/milestone-driver:solve-issue`.

The **read-only post-build coherence pass** (an optional, never-gating second opinion on whether a built change fits the app, `coherenceReviewAgent`) is delegated too: it runs per-issue inside `solve-issue` section 6, before that issue's final `/code-review` (so sequential and issue-granularity runs get it automatically). Under **wave granularity** the assembled wave is the largest body reviewed before its one wave PR, so the coherence pass runs at the **Phase-2 serial-merge-tail re-verify point** (`skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 2: serial verified merge tail`) against the integrated wave. Like every optional integration it is silently skipped when the coherence-reviewer is absent.

**Bounded blast radius.** The loop merges only to `integrationBranch`, never to `protectedBranch`. Release (`integrationBranch` → `protectedBranch`), **closing the GitHub milestone object**, and deploy stay manual and human-only — the driver closes the milestone's **issues** and authors the CHANGELOG, but never closes the **milestone** itself. That boundary is what makes unattended operation safe.

**Execution mode (parallel by default, barrier-checked).** Parallel is the **default** execution mode — there is **no** `--parallel` flag and no "in parallel" trigger to opt in. The run instead resolves its mode **once** at run start, as the last Before-starting step (**Resolve execution mode**), via a barrier cascade: it runs **parallel** unless a barrier drops it to **sequential** — a `parallel: false` profile opt-out, a permission-allowlist gap (a physical barrier), or an unconfirmed test-isolation answer (the DB-hazard interview). The resolved mode is held for the whole run and drives the Phase 1 / Phase 2 machinery in `skills/solve-milestone/parallel-waves.md` (§ Parallel mode — Phase 1: concurrent worker dispatch). **Back-compat:** a habit-typed `--parallel` token (or the phrase "in parallel") in `$ARGUMENTS` is **harmlessly stripped and ignored** by the generic `--<token>` flag-strip in Before-starting step 3 — parallel is already the default, so it changes nothing and never corrupts the milestone identifier. When the resolved mode is **sequential**, the loop (steps 1–5), the buildability conditions (a)/(b)/(c), and the buildable / not-buildable branches run byte-unchanged. The blast-radius boundary above is identical in both modes (workers and the merge tail merge only to `integrationBranch`, never `protectedBranch`).

## Before starting

1. **Auth preflight.** Run `gh auth status`. If it fails (non-zero exit or any "not logged in" / "authentication failed" output), print a clear error — e.g. `"Error: gh auth status failed — authenticate with 'gh auth login' before running solve-milestone."` — and **halt immediately**. Do NOT proceed to profile read, milestone resolution, or any other step.
2. Read the profile (see the plugin's `docs/profile-schema.md`).

   | Profile-resolution decision point | Behavior |
   |---|---|
   | Resolution order (transitional READ only — the orchestrator performs no migration move) | Read `<repo>/.milestone-config/driver.json` first; if absent, fall back to the legacy root `<repo>/milestone-driver.json`. |
   | Both files exist | `.milestone-config/driver.json` wins — no move, no overwrite, no deletion of the leftover root file. |
   | Migration (`git mv`) | solve-milestone does **not** run a `git mv` on its own (orchestrator) working tree — that would leave an uncommitted relocation sitting on `integrationBranch` with no commit path. |
   | Legacy layout | Migration is instead performed by the **first dispatched `solve-issue`** (it runs the move on its feature branch at step 3.5, so the relocation rides that issue's PR). |
   | All-parked milestone (no building run this pass) | Defers the move to the next building run; the transitional READ above covers the gap until it lands. |
   | Neither file exists, or `integrationBranch` / `protectedBranch` / `sourceGlobs` missing | Invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. |
   | `implementerAgent` | Defaults to `milestone-driver:implementer` when omitted. |
   | Optional keys — `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `domainSkills`, `nonNegotiables` | Optional; their steps are skipped cleanly when absent. |

   2.0.5. **Self-heal the scratch-ignore (always, before any `.milestone-config/` scratch write).** Per-clone scratch (`preflight-notice`, `trello-notice`, `triage-cache.json`, `tests-stamp`, plus the `.runtime/` and `worktrees/` dirs) must be git-invisible in the consumer repo from the first write, with zero user setup — but `.milestone-config/` also holds **tracked** config (`driver.json`, `feeder.json`), so the directory itself must not be blanket-ignored. Ensure a **committed** `.milestone-config/.gitignore` exists that ignores only those scratch names while leaving the config tracked. If the file is absent, create it (`mkdir -p .milestone-config`, then write the block below); if it already exists, do nothing. Unlike the profile `git mv` (which the orchestrator defers to the first `solve-issue`), this is a single new gitignore file that makes the orchestrator's own marker writes invisible; the first dispatched `solve-issue` commits it on its feature branch alongside the migration. (`driver.json` / `feeder.json` are intentionally NOT listed, so they stay tracked — never add a blanket `*` or `/` rule.)

      <!-- KEEP THIS BLOCK IN SYNC with the committed .milestone-config/.gitignore in this repo and with solve-issue / triage, feeder setup / plan. -->
      ```gitignore
      # milestone-driver / milestone-feeder per-clone scratch — git-invisible by default.
      # Committed so per-run scratch stays out of `git status` with zero user setup.
      # Patterns are relative to this .milestone-config/ directory. Tracked config
      # (driver.json, feeder.json) is intentionally NOT listed, so it stays tracked.
      preflight-notice
      trello-notice
      visualcapture-notice
      parallel-default-notice
      triage-cache.json
      tests-stamp
      .runtime/
      worktrees/
      ```

   2.1. **One-time notices.** Immediately after reading the profile: read `skills/notices.md` and, in file order, evaluate each section whose `Skills` field includes `solve-milestone` (today: preflight, trello, visualcapture, parallel-default) — for each, apply the `Trigger` → `Text` → `Marker` → `Legacy fallback` mechanics recorded in that section, exactly as stated there. File order is print order — today's order (preflight → trello → visualcapture → parallel-default) is unchanged.
3. **Resolve the milestone argument** (subsumes the old "named milestone exists" confirmation). Strip flags from `$ARGUMENTS` to get the bare argument (flags are tokens starting with `--`; for each `--<token>`, remove it; ALSO remove the immediately-following token only if that token does not start with `--` AND the flag is value-bearing: `--parallel` and `--driven` are boolean — strip the flag token only, do NOT consume the next token; any other `--<token>` with a following non-flag token is treated conservatively as value-bearing — strip both). Then:
   - **If purely numeric** (`$ARGUMENTS` minus flags is digits only): call `gh api repos/{owner}/{repo}/milestones/<milestone-number> --jq '{number, title}'` — if found, record the canonical `{number, title}` and state `"Resolved milestone #<milestone-number> → '<title>'"` in the run output; if not found, fail fast — print the available milestones as a **number + title table** (see format below) and stop.
   - **Otherwise (title/name):** call `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | select(.title=="<name>") | {number, title}'` — if found, record the canonical `{number, title}` and state `"Resolved milestone '<title>'"` in the run output; if not found, fail fast — print the available milestones as a **number + title table** and stop.
   - **Ambiguity note:** a purely-numeric milestone *title* (e.g. a milestone literally titled `"2"`) is reachable via the numeric-input path (routing is determined by `$ARGUMENTS` form — digits only — not by title content). After resolution, check the resolved title: **if it is purely numeric, halt immediately and prompt the human.** Triage interprets a bare number as single-issue mode, so the milestone title must be renamed to a non-numeric value before this skill can drive it unattended — do not proceed to Phase 0.
   - **Available-milestones table format** (for the error path): `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | [.number, .title] | @tsv'` formatted as a Markdown table with columns `#` and `Title`.

   All downstream steps use the resolved `{number, title}` — do NOT re-read `$ARGUMENTS` directly in the ordering step (procedure step 2, `### 2. Determine the order`) or Phase 0.
   **3.5** If `integrations.trello` is present in the profile, read `skills/solve-milestone/trello-sync.md` and run its run-start card resolution (best-effort — a Trello failure never blocks the run).
   **3.6** **Cherry-pick check for a human-typed milestone under a parent group (fires only when `--driven` is absent).** A milestone can be one ordered slice of a larger feature spanning several milestones, grouped under a parent GitHub issue that carries the `md-epic` label (recorded in `docs/superpowers/specs/2026-07-04-md-epic-driver-fanout-design.md`). When a human types `solve-milestone <name>` directly, this step warns them before they build only that slice. The `--driven` token (defined in step 5 below; string-presence recognition for this token added in #267) is never typed by a human — an automated fan-out loop supplies it when it dispatches this skill on its own behalf. **When `--driven` is present, this step does not execute at all** — not the first-issue query, not the parent lookup — so a driven run can never re-detect its own dispatching parent and re-prompt. This is what keeps the *driven* path true to this skill's own frontmatter contract, "never waits on a human... only a systemic failure ends the run early" — like the purely-numeric-title halt in step 3 above, this new prompt is a human-typed-invocation-only exception to that contract and never fires under `--driven`.

   When `--driven` is absent:

      a. **Find the resolved milestone's first issue** — the numerically lowest issue number currently assigned to it, `--state all` so a fully-built milestone is still inspectable:
         ```bash
         gh issue list --milestone "<resolved-title>" --state all --json number --jq 'sort_by(.number) | .[0].number'
         ```
         A milestone with zero issues yields nothing here — this step is then a no-op; fall through to step 4 below.
      b. **Read that issue's parent and check for `md-epic` in the same call:**
         ```bash
         gh api repos/{owner}/{repo}/issues/<first-issue>/parent
         ```
         A 404 response means no parent. Any other successful response already includes `.labels` — check it for an exact match against `md-epic` (mirroring the live-label check used in `### 4. Loop over issues in dependency-graph order`'s condition (b) below) without a second call.
      c. **No parent, or a parent without `md-epic`** → today's behavior, unchanged: fall through to step 4 below, no prompt.
      d. **A parent carrying `md-epic`** → prompt the human with exactly three options:

         ```text
         🔴 Milestone "<resolved-title>" belongs to parent issue #<parent-number>, which spans
            multiple milestones in a defined build order. Building just this milestone builds
            only one slice of that feature.
            [Build just this milestone] · [Hand off to solve-issue #<parent-number> — drive the
            whole parent in build order] · [Pause for clarification]
         ```

         - **Build just this milestone** → fall through to today's step 4 / step 5 / Phase 0 sequence exactly as the no-prompt branch above does — this milestone builds autonomously, same as today.
         - **Hand off** → invoke `/milestone-driver:solve-issue <parent-number>` directly (the same skill-invokes-skill pattern this skill already uses to invoke `/milestone-driver:triage`, Phase 0 below) and **stop this run's Before-starting sequence here** — no clean-tree check, no execution-mode resolution, no Phase 0 triage for this milestone under this invocation.
         - **Pause for clarification** → halt immediately. No build, no hand-off, no state change.
      e. **Out-of-order safety is reactive only.** If the human picks "build just this milestone" and one of its issues actually depends on unmerged work from an earlier, not-yet-built milestone in the same parent group, that dependency is not caught proactively — triage's `dependencyGraph` is scoped to this one milestone's own issues and has no edge into a different milestone. It surfaces reactively, through whatever build-time signal it naturally trips (the root-cause gate, a red suite, or an implementer-declared architecture conflict) — not through the same-milestone "held by unmerged upstream #N" proactive comment in `### 4. Loop over issues in dependency-graph order` below, which has no cross-milestone upstream to name. Expect a less specific park reason than that comment. No new mechanism.
      f. **A non-404 failure of the `.../parent` call** (auth, 5xx, network) is a systemic condition, not "no parent" — surface it and halt per the existing Autonomy contract below, the same as any other systemic failure.
4. Confirm the working tree is clean and the local `integrationBranch` is current (`git fetch`, fast-forward).
5. **Resolve execution mode (the LAST Before-starting step).** Runs **after** the clean-tree check (step 4) on purpose: the DB-hazard interview's single profile write (below) is then the one intentional uncommitted change, with no clean-tree conflict. Resolve the run's execution mode **once**, here, and hold the result for the whole run — every downstream reference reads this resolved decision; nothing re-decides mid-loop. Evaluate the barrier cascade **top-down; first match wins**:

   **The `--driven` token.** Like `--worker` (`skills/solve-issue/SKILL.md:327`) and `--async` (`skills/solve-issue/SKILL.md:395`), `--driven` is an **interpreted token, not a parsed CLI flag** — recognized by **string presence** in the invocation text, never argument parsing. It is never typed by a human — an internal caller (a future driven-invocation loop) supplies it when dispatching this skill on its own behalf. Today it gates **only row 4 below (the DB-hazard interview):** a driven run degrades that interview to its non-interactive path (row 4′) instead of prompting. **Other Before-starting steps that can prompt a human are unaffected** — e.g. the purely-numeric-title halt in step 3 above still halts and prompts even on a driven run. **When `--driven` is absent, this cascade and every other Before-starting step run byte-unchanged.**

   | # | Condition | Resolved mode | Dispatch | Surfacing |
   |---|---|---|---|---|
   | 1 | profile `parallel: false` | **sequential** | background/async ok if the gate passes, else synchronous | quiet — standing opt-out |
   | 2 | permission-allowlist gap (the `### Permission pre-flight gate`) | **sequential** | **synchronous** | 🔴 gap table + recommend `/fewer-permission-prompts` |
   | 3 | profile `parallel: true` | **parallel** | background | quiet — asserted safe |
   | 4 | `unitTestCmd` set AND `parallel` absent AND **interactive** | **interview → user's choice**, persisted to `parallel` | per choice | 🔴 up-front prompt (below) |
   | 4′ | same as row 4 but (`MILESTONE_DRIVER_NONINTERACTIVE=1` OR `--driven` present) | **sequential** | background/async ok if the gate passes, else synchronous | loud `⚠` note + how to set `parallel: true`; **no persist** |
   | 5 | otherwise | **parallel** | background | quiet — default |

   The outcome is `(mode ∈ {parallel, sequential}) × (dispatch ∈ {background, synchronous})`. Row 2 forces `synchronous` dispatch and, because parallel workers **require** background dispatch, also forces `sequential` — this physical barrier overrides even `parallel: true` downward (no config can grant a tool the session has not allow-listed). All other sequential outcomes may still use the sequential background/async path when the gate passes.

   **The permission pre-flight gate runs here, once** (per `### Permission pre-flight gate`) — it is the run's single background-dispatch permission decision (row 2). Union `permissions.allow` across the three settings layers; a gap → synchronous dispatch + sequential mode (row 2); no gap → background dispatch is available and the cascade continues. The in-loop references (the `### 4` loop's step 2 and `parallel-waves.md`'s Phase 1 dispatch step) **read this already-resolved decision** — the gate does **not** re-fire mid-loop.

   **DB-hazard interview (row 4).** Trigger: `unitTestCmd` is set AND `parallel` is absent from the profile. Fire it **once**, here at run start, before Phase 0. `unitTestCmd` presence is the **only** trigger — per-worker unit runs are the only gate run *concurrently*; `e2eTestCmd` and any server-starting preflight are deferred to the serial merge tail and run once, so they are not a concurrency hazard. Prompt:

      ```text
      ⚠ This repo runs unitTestCmd, and parallel workers share external services like your
        test database — a git worktree isolates the filesystem, not the DB. Is your test
        harness isolated per worker (or otherwise safe to run concurrently)?
        [Yes — go parallel] · [No — run sequential]
      ```

      - **Yes** → run **parallel**; write `parallel: true` to `.milestone-config/driver.json`.
      - **No** → run **sequential**; write `parallel: false`.
      - Either way, print the visible note: _"Recorded `parallel: <value>` in `.milestone-config/driver.json` — change it there anytime."_

      **Persistence** is a minimal in-place JSON edit of `.milestone-config/driver.json` that adds the `parallel` key, preserving every other key and the file's formatting. It is the orchestrator's own working-tree edit — **not** committed, rides no PR (a local `.milestone-config/` decision the operator commits if they want it shared). Because this step runs **after** the clean-tree check (step 4), this single `parallel`-key edit is the one intentional uncommitted change the driver made — no clean-tree conflict, no preflight special-casing. This is the deliberate write-rule deviation for `parallel` (see `docs/profile-schema.md`): an explicit boolean is written whenever the decision is made — both `true` and `false` — because omitting it would re-fire the interview on the next run while `unitTestCmd` is present.

      **Non-interactive (`MILESTONE_DRIVER_NONINTERACTIVE=1` OR `--driven` present — row 4′):** do **not** prompt. Fall to **sequential** with a loud note — `⚠ unitTestCmd set and no parallel-safety decision recorded — running sequential; set "parallel": true in .milestone-config/driver.json to enable parallel builds.` — and do **NOT** persist a value (no human decision was made). This mirrors the versioning `NONINTERACTIVE` degradation in `### 3. Determine the target version`. **`--driven` forces this same degradation**: a driven run has no human watching, so `--driven` present makes row 4's "interactive" condition read false — exactly as `MILESTONE_DRIVER_NONINTERACTIVE=1` already does — without requiring the environment variable to be set.

      **Nothing-to-decide:** `parallel` absent AND `unitTestCmd` absent → row 5 → **parallel**, quiet — **no interview fires and no value is persisted** (no hazard, no decision, so the profile is left byte-unchanged, per the "omit only when no decision was made" rule).

   **Surface the resolved mode.** State the resolved mode + reason in the run output; it drives Template 1's mode line (`## Output spec`) — one of `parallel` / `sequential (profile parallel:false)` / `sequential (permission gap — see 🔴)` / `sequential (test-isolation not confirmed)`.

## The procedure

### 1. List the milestone's open issues
Run `gh issue list --milestone "<resolved-title>" --state open`.

(Where `<resolved-title>` means the title from the canonical `{number, title}` resolved in Before-starting step 3.)

### 2. Determine the order
The **milestone description is the ordering source of truth**. Read it (e.g. `gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '.description'` or `gh api "repos/{owner}/{repo}/milestones?state=all" --jq '.[] | select(.title=="<resolved-title>") | .description'`) and follow the recorded Wave / dependency sequence. (Using the resolved number is more direct — prefer the by-number endpoint since it is already resolved.) If the description records no explicit order, fall back to ascending issue number and **state that assumption explicitly** in the run output — do not silently pick an order.

### 3. Determine the target version

Read `versioning` from the profile. **Version-free mode** (`versioning: false`): skip this step entirely — no extraction, no prompt, no target version. Record "version-free run — no version determined or bumped" and proceed to Phase 0.

**Otherwise** (`versioning: true` or absent): determine the target version with the deterministic extractor `scripts/extract-version.{sh,ps1}` (issue #158) — do **not** parse by judgment. Pipe the milestone's title + description as JSON to the extractor (bash where available, else pwsh):

```bash
gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '{title, description}' \
  | bash scripts/extract-version.sh        # pwsh -NoProfile -File scripts/extract-version.ps1 on pwsh-only hosts
```

The extractor prints the normalized version on **stdout**, or nothing — with a reason (`none` or `ambiguous:<candidates>`) on **stderr**. Branch on the result × `versioning`:

| Extractor result | `versioning` absent (opportunistic) | `versioning: true` (explicit opt-in) |
|---|---|---|
| version on stdout | **versioned** — hold it as the target for the loop; record it | **versioned** — same |
| empty + `none` | **version-free**, record "no parseable version in milestone — version-free run (logged)" | **prompt** the user: "No version found in milestone '<title>'. Enter a target version, or proceed version-free." |
| empty + `ambiguous:<list>` | **version-free**, record "ambiguous version in title (<list>) — version-free run (logged)" | **prompt**, listing `<list>` as the candidates to choose from |

**Non-interactive runs.** When `MILESTONE_DRIVER_NONINTERACTIVE=1` is set (scheduled / cron / headless), explicit `true` does **not** prompt — it degrades to version-free with a loud `⚠ explicit versioning:true but no parseable version — running version-free` warning and a logged note. The prompt path is interactive-main-thread only; this preserves unattended operation.

The extractor is fail-open: any internal error yields empty + `none`, so a missing interpreter or malformed input degrades exactly like "no version found".

> **Version source vs. version target.** In versioned mode the version **source** is the milestone (extracted here via the deterministic extractor). The version **target** is `.claude-plugin/plugin.json`; the missing-`plugin.json` fail-safe for that target is applied downstream at `solve-issue` step 6.4 (the bump step), not here. Step 3 determines the source only; it adds no fail-safe branch of its own.
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

**Mode branch point.** If the run resolved to **parallel** mode (the *Resolve execution mode* Before-starting step): read `skills/solve-milestone/parallel-waves.md` and run its Wave loop (Parallelizable-set selection → Phase 1 → Phase 2 → Integration granularity) instead of this section's per-issue loop below — do not run steps 1–5 below. If `parallel-waves.md` is missing or unreadable at this point, that is a **systemic failure**: surface it and halt the run per `## Autonomy` → "Systemic failures that halt the run" (do **not** silently degrade to sequential, which would silently skip real dispatched work). If the run resolved to **sequential** mode: `parallel-waves.md` is **never read** — this section (steps 1–5, the buildable / not-buildable branches) runs byte-unchanged below.

Create one TodoWrite item per issue. Drive the loop from the **validated dependency graph** produced by Phase 0. Process issues Wave by Wave; within a Wave, issues that are independent of each other may be treated as buildable in any order.

For each issue, determine whether it is **buildable this pass**. An issue is buildable iff ALL THREE conditions hold:

- **(a)** every issue in `dependencyGraph.edges["<n>"]` (the issues this issue directly DEPENDS_ON) is already merged to `integrationBranch`; **AND**
- **(b)** the issue currently carries **no blocker label** — check live: `gh issue view <n> --json labels --jq '[.labels[].name]'` and confirm none of `needs design`, `needs decision`, `blocked` is present. This live-label check is the **authoritative park-state**: it catches both triage parks labeled in Phase 0 AND prior-run build-time parks whose labels persist on the issue. A labeled issue must not be rebuilt until a human clears the label; **AND**
- **(c)** `issueStates[n].blockers == false` (this-run triage found no spec gap).

**If buildable:**

1. Ensure `integrationBranch` is current (`git fetch`, fast-forward) so dependent issues build on already-merged work.
2. **Before dispatching the first issue in the run** (once per run, not per issue): use the **dispatch decision already resolved at run start** (the *Resolve execution mode* Before-starting step, row 2 — the permission pre-flight gate ran there; do NOT re-run it). If that resolution found a permission gap → synchronous dispatch for this run (today's behavior, steps 2–4 unchanged, no background concurrency). If no gap → dispatch each issue as a background agent (`Agent(run_in_background: true)`), embedding BOTH the target version AND the Phase 0 triage result as named fields in the agent's prompt brief (e.g. `targetVersion: <x.y.z>` and `step-0 result for #N: { ... }`). A background agent has a fresh context and does NOT inherit the orchestrator's in-memory state — both values must be literally present in the prompt string, not inherited from context.

   When dispatching as a background agent: invoke `solve-issue <n> --async`. The orchestrator MUST embed the Phase 0 triage result as before (e.g. "step-0 result for #N: { blockers: false, label: null, advisories: [...], risk: light }, edges: [...]") so that step 0's Branch A can reuse it. **Await the completion notification** from the background agent before proceeding to the next issue — end the turn while waiting rather than poll (the harness re-invokes the main line when the background agent completes; see `solve-issue` `## Async mode` → `### How the caller dispatches` for the full wait/redirect pattern). When the notification arrives, re-derive terminal state from live `gh` queries — `gh issue view <n> --json labels,state` and `gh pr list --head issue/<n>-*` — to determine whether the issue was merged, held for visual review, or parked (there is no structured handback in `--async` mode). **Surface the wave-boundary status update using Template 2 from `## Output spec`**. Narrate any park (label + reason) sourced from the live issue labels. Apply park labels if needed. Re-sync `integrationBranch` (`git fetch`, fast-forward). Then dispatch the next issue.

   **Operator redirect window.** Between dispatches the main line is interactive — the background agent has completed and the main line is live. The operator can redirect before the next dispatch begins. The operator can also send the running background agent a mid-run message — delivered at the agent's next tool-use round, not instantaneously — but only by addressing that specific dispatched instance (its agent ID/name), never an agent-TYPE name like `milestone-driver:implementer`, which is not a reachable address.

   **Background agents never call PushNotification** — confirmed absent from subagent tool registries (see issue #97 recorded decision); the main line emits at this boundary. **SendMessage addressing:** the main line CAN send a dispatched background agent a mid-run message (delivered at its next tool-use round) — but only by that agent's own dispatched ID/name; an agent-TYPE name (e.g. `milestone-driver:implementer`) is not a reachable address, and only the session that spawned the agent can message it.

   **Sequential mode only** (not applicable to parallel worker handbacks — those are handled by `parallel-waves.md`'s Phase 1 step 5's parked-handback emit): After each issue completes in **sequential mode** (whether dispatched as a background agent or run synchronously as fallback), post the chunk-boundary board first (Template 2), then emit a `PushNotification` for the terminal state of the just-completed issue:
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

Relocated to `skills/solve-milestone/parallel-waves.md § Parallelizable-set selection (parallel mode)` — read there when the run resolves to parallel mode (see the mode branch point at the top of `### 4. Loop over issues in dependency-graph order` above).

### Permission pre-flight gate

**Runs once per run, at run-start mode resolution (the *Resolve execution mode* Before-starting step, row 2), before any dispatch.**

**Scope: this gate applies whenever background dispatch is about to be used — now the default path** (parallel-by-default, plus the sequential background/async dispatch path, #89). It runs once at run-start mode resolution (row 2); the mode cascade and the loop then **read** its result. A run that resolves to purely synchronous dispatch incurs no further gate cost.

Background subagents auto-deny any tool call that would otherwise prompt (documented Claude Code behavior). A background chunk hitting an un-allowlisted tool fails outright with no interactive recovery — park-don't-prompt becomes physically enforced. At run-start mode resolution (row 2), before any background dispatch (the async dispatch points, #89), run this gate to verify the session's permission allowlist is complete.

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

The gate fires **once per run**, not once per issue — at run-start mode resolution (row 2). After that single decision, the result (proceed / fallback) is held for the rest of the run — do not re-read settings on every issue.

**Worker auto-deny handling.** If a background worker chunk receives an auto-deny on a tool call mid-execution, treat it as a **park** — post a `blocked` comment on the issue naming the denied tool, apply the `blocked` label (+ `in progress` if the branch has commits), preserve the branch, and return the structured handback with `status: parked`, `parkLabel: "blocked"`, and `parkReason: "auto-deny on <tool>"`. This is the same park-don't-prompt contract all other gates use — an auto-deny is not a silent failure.

### Parallel mode — Phase 1: concurrent worker dispatch

Relocated to `skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 1: concurrent worker dispatch` — read there when the run resolves to parallel mode (see the mode branch point at the top of `### 4. Loop over issues in dependency-graph order` above).

### Parallel mode — Phase 2: serial verified merge tail

Relocated to `skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 2: serial verified merge tail` — read there when the run resolves to parallel mode (see the mode branch point at the top of `### 4. Loop over issues in dependency-graph order` above).

### Integration granularity (issue vs wave)

Relocated to `skills/solve-milestone/parallel-waves.md § Integration granularity (issue vs wave)` — read there when the run resolves to parallel mode (see the mode branch point at the top of `### 4. Loop over issues in dependency-graph order` above).

### 5. Finish
Continue until every issue is done (merged), held at the visual-review gate (a UI issue with an open `needs review` PR awaiting human visual sign-off), or parked. The run ends when no more buildable issues remain — not because it is waiting on a human.
If `integrations.trello` is present, apply `## Finish hooks` from `skills/solve-milestone/trello-sync.md` (best-effort — Trello failures never block the run; skipped updates surface in the final summary).

## Autonomy

- **Unattended between systemic failures.** Within an explicit `/milestone-driver:solve-milestone` run, operate autonomously. A `solve-issue` STOP or PAUSE **parks** that issue (label + open branch + comment) and the loop continues — it does **not** halt the loop. Only a systemic failure ends the run early.
- **Systemic failures that halt the run** (examples): `gh auth` failure, a broken or inaccessible `integrationBranch`, missing required tooling (`gh`, `git`), a missing or unreadable `skills/solve-milestone/parallel-waves.md` when the run has resolved to parallel mode (core default-on machinery, not a best-effort integration — unlike `trello-sync.md` / `coherenceReviewAgent`, which degrade silently). These are conditions where no further issue can make progress. Surface the failure, leave the working tree clean and all in-flight issues parked, then present the final summary and stop — the **Run-complete notification** block (below `## Final summary`) emits the `🚨 Run halted — <reason>` notification as its last step.
- **Architecture is locked** per issue at its plan-approval time. The loop executes approved architecture; it does not pivot. A plan proven wrong is a park (STOP → park + continue), not a silent redesign. For the bounded definition of architecture vs implementation detail (the decision test), see the Autonomy model in `solve-issue`.
- **Never escalate scope to `protectedBranch`.** No PR, push, or merge targets `protectedBranch` (enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection).

## Output spec

<!-- KEEP THIS ICON LEGEND BYTE-IDENTICAL across solve-issue and solve-milestone (see plan 2026-06-04 verification model). -->
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
3. All merged → merge `integrationBranch` → `protectedBranch` with `--merge` (not squash), merging the release PR *before* tagging, then **back-merge `protectedBranch` → `integrationBranch`** (history-only, conflict-free) so `integrationBranch` stays tag-current and topologically even, close the milestone (`gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed`), deploy — full ordered runbook in `docs/consumer-setup.md` § "Releasing to your protected branch"
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
- The next human step: review parked issues and the open `needs review` PRs; clear the park labels when the blockers are resolved and re-run to pick up the remaining work; when all work is merged, merge `integrationBranch` → `protectedBranch` with `--merge` (not squash), merging the release PR *before* tagging, then **back-merge `protectedBranch` → `integrationBranch`** (history-only, conflict-free, keeps `integrationBranch` tag-current and topologically even) (full ordered runbook in `docs/consumer-setup.md` § "Releasing to your protected branch"), close the GitHub milestone object (`gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed` — the driver closes the milestone's issues and authors the CHANGELOG, but never closes the milestone itself), and deploy manually.

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
- **No schema changes** to `.milestone-config/driver.json` (include this line only when true)

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
- **No schema changes** to `.milestone-config/driver.json` (include this line only when true)

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
