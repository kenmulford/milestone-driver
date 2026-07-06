---
name: solve-issue
description: This skill should be used when the user invokes "/milestone-driver:solve-issue <n>", or asks to "solve issue <n>", "fix issue <n>", or "drive issue <n>" through the milestone-driver gated procedure. Runs one GitHub issue end-to-end as an orchestrator — triage, root-cause-or-park, dispatch the implementer subagent (TDD, citations), unit + E2E gates, code review, PR to the integration branch, auto-merge on CI green for non-UI issues (UI issues are held open for human visual sign-off), then close — never authoring application or test code on the main thread.
---

# solve-issue — gated per-issue procedure

Run exactly one GitHub issue through a fixed, gated pipeline. The main thread acts only as an **orchestrator**: read, decide, dispatch, review, integrate. It **never authors application or test code itself** — the `force-subagent` hook enforces this mechanically, so honor it by design.

Orchestrate the `superpowers:*` skills for the inner loop rather than reimplementing their discipline. **Before anything else, check `#n`'s labels for `md-epic`: a parent issue takes `### Parent path` (see `## Parent-issue detection` near the end of this file) instead of the pipeline below.**

## Before starting

1. Read the profile (see the plugin's `docs/profile-schema.md`).

   | Profile-resolution decision point | Behavior |
   |---|---|
   | Resolution order (transitional) | Read `<repo>/.milestone-config/driver.json` first; if absent, fall back to the legacy root `<repo>/milestone-driver.json` — this transitional READ covers the gap before any migration move lands. |
   | Both files exist | `.milestone-config/driver.json` wins for the read. |
   | Migration (`git mv`) | Deferred to step 3.5 (after the clean-tree check and the feature-branch cut), so the actual `git mv` rides the feature branch's changes and does **not** trip the clean-tree precondition (step 2). Do **not** perform the move here. |
   | Neither file exists, or `integrationBranch` / `protectedBranch` / `sourceGlobs` missing | Invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. |
   | `implementerAgent` | Defaults to `milestone-driver:implementer` when omitted. |
   | Optional keys — `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `preflightCmd`, `domainSkills`, `nonNegotiables`, `projectDocs` | Optional; `projectDocs` defaults to `.project/` when absent. Their steps are skipped cleanly when absent. |

   1.1. **Self-heal the scratch-ignore (always, before any `.milestone-config/` scratch write).** Per-clone scratch (`preflight-notice`, `trello-notice`, `triage-cache.json`, `tests-stamp`, plus the `.runtime/` and `worktrees/` dirs) must be git-invisible in the consumer repo from the first write, with zero user setup — but `.milestone-config/` also holds **tracked** config (`driver.json`, `feeder.json`), so the directory itself must not be blanket-ignored. Ensure a **committed** `.milestone-config/.gitignore` exists that ignores only those scratch names while leaving the config tracked. If the file is absent, create it (`mkdir -p .milestone-config`, then write the block below). If it already exists, do nothing. This rides the feature branch and is committed with the issue work like any other repo change; it self-heals consumer repos that predate this seam. (`driver.json` / `feeder.json` are intentionally NOT listed, so they stay tracked — never add a blanket `*` or `/` rule.)

      <!-- KEEP THIS BLOCK IN SYNC with the committed .milestone-config/.gitignore in this repo and with solve-milestone / triage, feeder setup / plan. -->
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

   1.1.1. **First-run preflight notice (one-time).** Immediately after reading the profile: if `preflightCmd` is **absent** from the profile **and** **neither** the new marker `.milestone-config/preflight-notice` **nor** the legacy root marker `.milestone-driver-preflight-notice` exists (transitional read — new path first, legacy root as fallback), print the notice below verbatim, then create the new marker (`mkdir -p .milestone-config && touch .milestone-config/preflight-notice`) and **remove the stale legacy root marker** `.milestone-driver-preflight-notice` if present. Stay **silent** if `preflightCmd` is set **or** either marker already exists. The marker is per-clone and gitignored, so the notice shows at most once per clone (same pattern as `.milestone-config/tests-stamp`).

      <!-- KEEP THIS NOTICE BLOCK BYTE-IDENTICAL across solve-issue and solve-milestone (see plan 2026-06-04 verification model). -->
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

   1.1.2. **First-run visual-capture notice (one-time).** Immediately after the preflight notice (step 1.1.1): if `visualCapture` is **absent** from the profile **and** `uiSurfaceGlobs` is **present** in the profile **and** the marker `.milestone-config/visualcapture-notice` is **absent**, print the notice below verbatim, then create the marker (`mkdir -p .milestone-config && touch .milestone-config/visualcapture-notice`). Stay **silent** if any condition fails — `visualCapture` present (the feature is already configured), `uiSurfaceGlobs` absent (the repo has no UI surface to capture), or the marker already exists. Unlike the preflight/Trello notices, this marker is **born on the new `.milestone-config/` path**, so the gate checks **only** the new-path marker — there is **no** legacy-root fallback read and **no** stale-legacy-removal step. The marker is per-clone and gitignored, so the notice shows at most once per clone (same lifecycle as `.milestone-config/preflight-notice`).

      <!-- KEEP THIS NOTICE BLOCK BYTE-IDENTICAL across solve-issue and solve-milestone (see plan 2026-06-04 verification model). -->
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
2. **Confirm the working tree is clean** (cold-start precondition) **and the local `integrationBranch` is current** (`git fetch`, fast-forward). One expected exception is not a clean-tree violation and must **not** be stashed or discarded: if the probe in step 3 detects an existing `issue/<n>-*` branch — whether the branch carries committed or uncommitted prior work — prior in-progress changes are expected; skip the clean-tree enforcement and proceed to step 3 immediately. Any other dirty state is a cold-start violation.
3. **Branch-state probe (resume an interrupted run).** Run `git fetch` first, then determine prior progress from git + gh before cutting anything. Evaluate in this order:
   - **(a) A PR exists for `issue/<n>-*`** (client-side filter: `gh pr list --state all --limit 200 --json number,headRefName,state,url --jq '.[] | select(.headRefName | startswith("issue/<n>-"))'`):
     - **merged** → the work is already integrated; do **not** re-implement or open a new PR; **resume at step 9** (confirm the issue is closed / close it). A merged PR means the branch was deleted — this state is reached when a run is interrupted after the merge but before the issue is closed.
     - **open** → check out that branch; **resume at the visual-review gate / auto-merge (steps 7–8)** — do **not** re-implement and do **not** open a second PR. (The open PR is the authoritative "work is built and submitted" signal.)
   - **(b) No PR; branch `issue/<n>-*` exists (local or remote) with commits ahead of `integrationBranch`**: check both local and remote refs (`git branch -a --list "*issue/<n>-*"` or `git ls-remote --heads origin "issue/<n>-*"`); track the remote branch if no local branch exists (`git checkout --track origin/issue/<n>-<slug>`). Compute commits ahead against the remote-tracking ref if no local branch was present. Implementation is already present, so **skip re-implementation**. **Re-verify first** — if `unitTestCmd` is defined, run it and confirm green; if absent (no test layer), confirm the branch diff is non-empty and based on `integrationBranch` (`git diff <integrationBranch>...HEAD --stat`). Then **resume at step 6.1 (`/code-review`)** and follow step 6's normal flow from there (commit only if there are uncommitted changes, push, open PR) — review may not have run yet and is never skipped; if `/code-review` triggers a fix, the re-review and re-push cycle in step 6 applies normally. A red re-verify (or a diff that is empty / clearly on the wrong base) is not a special case: fall into the normal step-4 red-suite path (re-dispatch the implementer, existing "at most 2" cap; park if non-converging).
   - **(c) No PR; no commits ahead; but the issue branch `issue/<n>-*` is checked out with uncommitted changes** (the implementer left work uncommitted — the normal implementer contract): do **not** clobber; re-verify (same re-verify rule as (b)); **resume at step 6.1 (`/code-review`)** and follow step 6's normal flow. This is best-effort: it only recovers when the working tree is preserved in-place (in-place re-dispatch); a fresh clone with no preserved working tree has no uncommitted changes and falls to (d).
   - **(d) Otherwise (no branch, no PR, clean tree):** cut a fresh feature branch from `integrationBranch` (e.g. `issue/<n>-<slug>`) — cold start, dispatch the implementer (### 3. Dispatch the implementer).

   This derives resume-state entirely from git + gh; there is no checkpoint file to maintain, drift, or delete.

   **3.5. Profile migration (run once, on the feature branch).** Now that the clean-tree check (step 2) has passed and the feature branch is established (step 3), run the idempotent migration preamble: **Profile resolution & migration.** Resolve the profile: if `<repo>/.milestone-config/driver.json` exists, use it. Else if a legacy root `<repo>/milestone-driver.json` exists, migrate it first — `mkdir -p .milestone-config`; `git mv <repo>/milestone-driver.json <repo>/.milestone-config/driver.json` (when git-tracked, else plain `mv`) — then continue. Else (neither) it is a new project (setup creates the canonical file; the other skills auto-invoke setup; hooks fail-open). Idempotent: once `.milestone-config/driver.json` exists this is a no-op. When both files exist, `.milestone-config/driver.json` wins — no move, no overwrite, no deletion of the leftover root file. The move is part of the feature branch's changes and is committed with the issue work (it rides the issue's PR — no separate commit); the transitional read in step 1 covers the gap before it lands.
4. Create one TodoWrite item per numbered step below. Work them in order — do not skip or reorder.

### Resuming an interrupted run

| Detected state (from git + gh) | Resume at |
|---|---|
| Merged PR for `issue/<n>-*` | Step 9 (confirm/close the issue — work is already integrated) |
| Open PR for `issue/<n>-*` | Step 7 (visual-review gate) → step 8 (auto-merge for non-UI) |
| No PR; branch + commits ahead of `integrationBranch` (local or remote) | Step 6.1 (`/code-review`) after re-verify; follow step 6's normal flow: commit only if uncommitted, push, open PR |
| No PR; no commits ahead; issue branch checked out with uncommitted changes | Step 6.1 (`/code-review`) after re-verify; follow step 6's normal flow (best-effort: in-place re-dispatch only) |
| No branch, no PR, clean tree | Cold start: cut `issue/<n>-<slug>` from `integrationBranch`, dispatch implementer (### 3. Dispatch the implementer) |

On the "no PR, branch/uncommitted-changes" paths, commit **only if there are uncommitted changes**; if the work is already committed, skip straight to push + PR. Never skip `/code-review`; if `/code-review` triggers a fix, the re-review and push cycle in step 6 applies normally.

## The procedure

### 0. Triage

**Two branches — always run one:**

**Branch A — Explicit-supply path (reuse).** Fires **iff the caller explicitly supplied this issue's triage result at invocation time** — in worker mode, as named-value fields embedded in the dispatch brief with actual values (e.g. `issueStates["<n>"] = { blockers: false, label: null, advisories: [...], risk: "light" }` and `edges["<n>"] = [...]`); in sequential mode, as an inline restatement by the orchestrator when invoking step 0 (e.g. "step-0 result for #N: { blockers: false, label: null, advisories: [...], risk: light }, edges: [...]"). When the result is explicitly supplied this way, use it directly — do **NOT** re-invoke `milestone-driver:triage <n>`. Proceed to the **Blocker check** below using the supplied result. This is not a skip: the explicitly supplied result IS the verified Phase 0 triage result for this run; the reuse branch consumes it rather than recomputing it.

**Branch B — Standalone / fallback path.** When no triage result was explicitly supplied at invocation time — anything absent, partial, or merely recalled from earlier context — invoke `milestone-driver:triage <n>` (single-issue mode) and use the returned result for the **Blocker check** below. Branch B is the safe default, never an error.

**Blocker check (both branches).** If the result indicates a Blocker for this issue → **park**: triage has already posted the `🔴 Triage` comment on the issue; VERIFY the comment exists (`gh issue view <n> --comments`) and post it if missing (idempotent); apply the recommended label from `issueStates["<n>"].label` — `needs design` for a design gap, `needs decision` for a non-design decision — via the apply-time helper (idempotent `gh label create --force` then `gh issue edit --add-label`); leave the issue open; do **not** proceed to step 1. Return to the caller — the milestone loop continues with independent, clean issues. All-clear or Advisory-only → proceed to step 1.

The safety floor is unconditional: triage step 0 always runs (via Branch A explicit-supply or Branch B fresh invocation) regardless of build profile. Light profile relaxes ceremony only — it never skips triage. (A parent issue carrying `md-epic` never enters this pipeline — see `## Parent-issue detection`.)

### 1. Read the issue
Run `gh issue view <n>` with comments. Restate the acceptance criteria plainly before continuing.

### 2. Evaluate the codebase for root cause
Invoke `superpowers:systematic-debugging`. Read the implicated code — the file(s) plus direct callers and callees.

**🔴 GATE — root cause:** If the root cause cannot be identified from the codebase, **park** the issue: post a comment opening with `🔴 Parked — ` and describing the blocker (`gh issue comment <n>`), apply the `blocked` label (or `needs design` if the gap is a design gap), apply `in progress` if the branch has commits, leave the branch open with any work done, and return. The milestone loop continues. Do not proceed to implementation.

When found, write an **architecture-aware plan** with full awareness of the codebase and its conventions. This plan is the **locked** architecture for this issue.

**`design-cleared` means a decision was recorded**, not that it is correct or buildable. The orchestrator may still **park** a `design-cleared` issue with `needs design` if the recorded/locked design is internally contradictory or will produce a poor result.

### Build profile resolution (resolved after step 0, governs steps 3–6)

Read `issueStates["<n>"].risk` from the step-0 triage result (held Phase 0 result in a milestone run, or fresh single-issue return in a standalone run). That value is either `"light"` or `"heavy"` (default `"heavy"` when absent or inconclusive). This single read governs the entire build profile for this issue:

| Profile | Implementer brief | E2E gate (step 4, E2E row) | `/code-review` effort (step 6.1) |
|---|---|---|---|
| **Light** | Include a `risk:light` token in the brief | Skip when the issue touches no UI surface | `low` or `medium` |
| **Heavy** (default) | Standard TDD brief (no `risk:light`) | Per step 4's E2E row (UI surface + e2eTestCmd) | `high` or `xhigh` |

The safety floor is **unconditional for both profiles**: triage (step 0), the `tests-green` hook, and `force-subagent` always run regardless of profile. Light relaxes ceremony only — it never skips verification. (A parent issue carrying `md-epic` never enters this pipeline — see `## Parent-issue detection`.)

### Resolve cited project-docs sections (once, before dispatch)

Resolve the issue's cited `.project/` sections **once, here in the orchestrator** — so the implementer (and, when wired, the reviewers) receive the grounding text in their brief rather than each subagent re-reading whole docs. This block runs after the build profile is resolved and **before ### 3. Dispatch the implementer**. It is **additive grounding**: it changes no gate, no cap, and no other step's logic — it only adds an input to the dispatch brief composed in step 3.

1. **Source the docs root.** Use `projectDocs` already resolved at step 1 (defaults to `.project/` when the key is absent). Do **not** re-resolve the profile here.
2. **Parse the cited anchors.** From the issue body + the acceptance criteria (read at step 1), collect the `.project/<doc>#<section>` anchors the issue cites — `<doc>` is the path under the docs root, `<section>` is the heading text (an anchor like `design-system.md#data-tables`).
3. **Pull a superset via the primitive.** For each cited anchor — plus its plausibly-relevant **sibling** sections — invoke the retrieval primitive `scripts/read-doc-section.{sh,ps1}` (pwsh on Windows, bash elsewhere — same host selection as `scripts/ci-preflight-steps.{sh,ps1}` at step 6.1) once per section: `read-doc-section.<sh|ps1> <doc-path> <anchor-text>`, where `<doc-path>` is the doc under the docs root and `<anchor-text>` is the heading text **without** leading `#`s. It prints **only** that section to stdout. **Bias toward over-inclusion**: pull the cited sections and their siblings as a superset rather than the minimum, because **under-retrieval is the real risk** (`docs/efficiency-grounding-plan.md` Risks). The implementer keeps its own `Read`/grep tools for any **additional** on-demand anchor, so over-inclusion here never under-grounds the brief — but it also must never degrade into whole-file inlining (the do-NOT-do ceiling). Resolve **once**; do **not** have the implementer re-read whole files.
4. **Feed the result into the dispatch brief.** Collect the printed sections and pass them into the implementer brief composed in ### 3 as **the resolved `.project/` sections**.

**Degradation (no error, ever):**
- **Absent `projectDocs`** → defaults to `.project/` (resolved at step 1).
- **Absent `.project/` directory** (or no cited anchors) → this block is a **no-op**: dispatch proceeds with no project grounding and **no error** (skipped cleanly when absent, exactly like `unitTestCmd`/`preflightCmd`).
- **Missing/renamed cited anchor** → the primitive **fails loud** (non-zero exit, naming the anchor + file on stderr) so a drifted heading surfaces rather than returning silent empty grounding. Treat the loud failure as a signal that a cited anchor drifted — do not swallow it.

### 3. Dispatch the implementer
Dispatch the profile's `implementerAgent` (default `milestone-driver:implementer`; a project-level override in the profile uses that agent's own name as-is) via the Agent tool, orchestrating `superpowers:subagent-driven-development` + `superpowers:test-driven-development`. Brief it like a colleague walking in cold: the issue, the approved plan, the profile, the expected file scope, and the resolved `.project/` sections (from "Resolve cited project-docs sections (once, before dispatch)" above — omit this input when that block was a no-op); when the build profile resolved above is `light`, the brief MUST include a `risk:light` token so the implementer applies the right verification mode. Note: extract/rename issues that touch a widely-shared symbol or component carry ~2–3× the call-site-migration surface of a typical feature issue, so they are more likely to consume both allowed re-dispatches before converging — the "at most 2" cap still applies, and an issue that cannot converge within it parks like any other (orchestrator judgment, not a profile key).

Verify the returned report honors the implementer contract: least-code / reuse-first, TDD red→green observed (or a `VERIFICATION (no test layer)` section when `unitTestCmd` is absent), verified citations where citable sources exist, a Decision Log, a `USER-FACING CHANGES` block (with `NEW_UI_ELEMENTS: yes|no`, `DESTRUCTIVE_OPS: yes|no`, and `POST_REVIEW_CHANGES: yes|no`), and **changes left uncommitted**.

After verifying the report, apply the following declaration gates:

- **`NEW_UI_ELEMENTS: yes`** and the issue's acceptance criteria are silent on the element's visual/UX detail → **park** with `needs design`: post a comment opening with `🔴 Parked — ` documenting the new elements and what direction is needed (`gh issue comment <n>`), preserve the branch, apply the label (+ `in progress` if the branch has commits), and return. The human supplies direction and re-runs; there is no mid-run interactive resume.
- **`DESTRUCTIVE_OPS: yes`** and the confirmation UX is unspecified → **park** with `needs decision` (a missing confirm flow usually means the plan is incomplete): post a comment opening with `🔴 Parked — ` documenting the missing confirm flow on the issue (`gh issue comment <n>`), preserve the branch, apply the label (+ `in progress` if the branch has commits), and return.

**🔴 GATE — new dependency:** If the implementer reports that the optimal solution requires a new library or toolkit, **park** with `needs decision`: post a comment opening with `🔴 Parked — ` followed by the library name and its license / OSS status on the issue (`gh issue comment <n>`), preserve the branch, apply the `needs decision` label (+ `in progress` if the branch has commits), and return. The milestone loop continues. Do not ask the operator interactively.

**🔴 GATE — implementer STOPPED:** If the implementer returns `STATUS: STOPPED` (architecture conflict, scope overrun, out-of-scope edit, or missing/ambiguous brief), **park** the issue: post a comment opening with `🔴 Parked — ` and describing the conflict (`gh issue comment <n>`), apply the appropriate label (`needs design` for a design/spec conflict, `needs decision` for an architecture call, `blocked` for an otherwise-unresolvable gate) + `in progress` if the branch has commits, preserve the branch, and return. The milestone loop continues. (Architecture stays LOCKED — a plan proven wrong is a park, not a pivot.) `PAUSED-FOR-APPROVAL` from the implementer indicates a new-dependency case and routes to the new-dependency gate above.

### 4. Verification gates

Unit, E2E, and preflight share one shape — **act → verify → retry (cap 2) → park** — closing a drift where only the unit gate invoked `superpowers:verification-before-completion`. The table states each gate's applicability, `act`, cap, and park/escape policy; the shared loop below it is the one procedure the three invoke, each at its existing pipeline position. `/code-review` is listed for visibility (it is a gate too, always-on — hence no trailing `?` in its row, unlike the other three) but keeps its own distinct procedure in step 6.1: its in-scope-fix vs park-trigger classification doesn't fit the generic "re-run the same check" shape, so it is **not** iterated by this shared loop.

| Gate | Applicability | `act` | Cap | Park / escape policy |
|---|---|---|---|---|
| **Unit?** | `unitTestCmd` defined | Run `unitTestCmd`. | 2 re-dispatches | Park `blocked` (or `needs design` if the plan is wrong). |
| **E2E?** | Issue touches a UI surface **and** `e2eTestCmd` defined | Bug: run a targeted subset that proves the fix. Feature: implementer authors new end-to-end (E2E) tests covering reasonable user stories, then runs them. Both against the profile's `e2eEnv`. | 2 fix attempts | **Distinct — not homogenized:** verified by other means (a DB assertion + an attached screenshot confirming the feature works) → quarantine the flaky test, proceed, log the quarantine in the PR's Code Review section, apply `judgment call`. Not otherwise verified → park `blocked`. |
| **`/code-review`** | Unconditional — always runs, no applicability flag | See step 6.1 — its own in-scope-fix / park-trigger classification | 2 review→fix cycles (step 6.1's own cap) | Step 6.1's own park-trigger classification (architecture deviation, shared-contract change, new dependency, out-of-scope edit, unmetable gate, material ambiguity) |
| **Preflight?** | `preflightCmd` defined (including the `"github-ci"` sentinel) | Run the literal `preflightCmd`; or, under `"github-ci"`, discover + run each CI-derived `STEP` (see below). | 2 re-dispatches | Park `blocked` (or `needs design` if the plan is wrong). |

**Preflight's `"github-ci"` sentinel mode.** When `preflightCmd` is the reserved sentinel `"github-ci"` (rather than a literal command), do not run it as a shell command. Instead invoke the discovery component `scripts/ci-preflight-steps.{sh,ps1}` (pwsh on Windows, bash elsewhere) in the repo root — pass the optional `ciWorkflow` profile value as its 2nd argument to narrow to one workflow. It reads the local `.github/workflows/*.yml` (never the network) and emits an ordered, TAB-separated record stream: `STEP <wf> <job> <coe> <wdir> <cmd>` (a runnable step; `coe=1` = `continue-on-error`; `wdir` = `working-directory`, `""` = repo root; `cmd` has newlines encoded as `\n`), `SKIP`/`CHECK`/`WARN` lines, and a final `SUMMARY mirrored=N skipped=M`. Run each `STEP` in declaration order, one at a time:
- **Surface the coverage summary loudly** in the run output — the `SUMMARY`, the mirrored `CHECK` names, and the `SKIP` reasons ("mirrored N checks, skipped M"). Any `WARN` line — especially the **silent-under-run** warning (a PR-gating workflow that produced zero runnable steps because its real checks live behind a `uses:` reusable/composite workflow) — must be surfaced as a **visible warning, not treated as a clean pass**.
- **For each `STEP`:** apply the **tool-presence guard** — first **decode the `cmd`'s `\n`-encoded newlines back to real newlines** (the record stores a multi-line `run:` with literal two-character `\n` separators), **then** take the leading tool as the first token of the first command in the decoded `run:` script (split on newline / `&&` / `;` / `|`; best-effort); if that tool is absent from `PATH`, **skip + log** "couldn't run locally (`<tool>` absent)". Otherwise run the command in `wdir` (repo root when empty). A non-zero exit is a **real failure** and feeds the shared loop below — **except** a `coe=1` (`continue-on-error`) step, whose failure is logged but **never** counts as a real failure (never triggers a park).
- A parse error or no workflows → the component emits an empty `STEP` list with a `WARN` reason; the gate then **no-ops cleanly** (same as an absent `preflightCmd`), never a hard crash.

**🔴 GATE — shared loop (unit, E2E, preflight only; `/code-review` keeps its own loop in step 6.1):**

1. **Act.** Run the gate's `act` per the table row. Skip the gate cleanly, no error, when its applicability condition is not met (`unitTestCmd` absent; `e2eTestCmd` absent or no UI surface touched; `preflightCmd` absent) — the same absent-skip convention used across the profile.
2. **Verify.** Invoke `superpowers:verification-before-completion` and report real output, never assertion — uniformly for all three gates (this is the drift this section closes: previously only the unit gate did this).
3. **Retry.** A failing gate re-dispatches the implementer with the failure — or **parks directly** if the failure reveals the plan is wrong (see Autonomy). A source-changing preflight fix also re-runs `unitTestCmd` if defined and re-runs `/code-review` (honoring step 6.1's "fresh review is the last action before commit" rule). **Cap: at most 2 re-dispatches/fix attempts, tracked per gate — never a shared/global budget across gates.**
4. **Park.** If the gate is still failing after its 2nd retry, apply that gate's park/escape policy from the table above: comment on the issue opening with `🔴 Parked — ` describing what failed and what is needed, apply `blocked` (or `needs design` if the plan is wrong) (+ `in progress` if the branch has commits), preserve the branch, and return. The milestone loop continues. (E2E's escape policy is the one exception to this generic park shape — see its table row: "verified by other means" quarantines and proceeds instead of parking.) A gate that won't converge usually means the plan is wrong (see Autonomy).

**Call sites are unchanged.** Unit and E2E run back-to-back immediately after the implementer dispatch (step 3) — exactly where they ran before this merge; retiring the `### 5.` heading only folds its content up into this step, it does not reorder anything. Preflight's call site does not move either — it still fires as the concluding action of step 6.1, after the `/code-review` loop converges, before version bump/commit (see step 6.1) — that positioning, not a numbered sibling step, is what keeps the `6.1 … 6.9` ordinals (and their cross-references) fixed.

### 6. Review → integrate → close

**Coherence review (before the final `/code-review`).** Before step-6.1's `/code-review`, optionally run a read-only post-build coherence pass over the implementer's **uncommitted** diff — the same uncommitted changes `/code-review` reviews next.

- **Resolve the agent.** The coherence agent is the profile key `coherenceReviewAgent`, **default-filled** to `milestone-coherence-reviewer:coherence-reviewer` (same default-fill pattern as `implementerAgent` / `triageAgent` / `designReviewAgent`, `docs/profile-schema.md:68`).
- **Gate — present AND configured.** Run the pass **only** when the coherence-reviewer agent is **both** present (dispatchable in this session) **and** configured (the `coherenceReviewAgent` key resolves, or its bundled default applies). If the agent is **absent/unavailable** OR explicitly unconfigured → **silently skip**: no error, no block, no park, no prompt — at most a single log line. This is the absent-means-skip convention used by `unitTestCmd` (`docs/profile-schema.md:101`), `preflightCmd` (`docs/profile-schema.md:111`), `integrations.trello` (`docs/profile-schema.md:119`), and `visualCapture` (`docs/profile-schema.md:104`).
- **When it runs.** Dispatch the coherence agent **read-only** against the implementer's uncommitted diff. The pass is the milestone-coherence-reviewer's own read-only contract — it returns findings and, per its own standalone contract, **routes its own drift** (trivial → small-issue note; small/medium → current-milestone issues; large → a feeder brief). The driver does **not** re-implement that heal routing here; it wires only the dispatch.
- **Never-gating.** The coherence pass **never** blocks, **never** parks, and **never** changes the merge decision — the build proceeds to step-6.1 `/code-review` regardless of what coherence found. Coherence heals via follow-ups; it does not gate (`.project/design-philosophy.md#Error & failure philosophy` — optional integrations never gate a run; absent means skip; `README.md` coherence-reviewer pointer — post-build, no edits).
- **Out of scope (deferred).** This step wires the **dispatch only**. The large-drift → milestone-feeder → auto-run-driver auto-handoff is a **separate deferred change** (#232) and is **not** part of this step.

1. **Review and resolve.** Run `/code-review` (`superpowers:requesting-code-review`) on the implementer's **uncommitted** changes, then resolve findings autonomously per the Autonomy model — do **not** pause to ask the operator about an in-scope finding:
   - **In-scope** (cosmetic, naming, style, local reversible refactor, missing/weak test): re-dispatch the implementer to fix it (the main thread cannot edit `sourceGlobs` — `force-subagent`); log it in the Decision Log.
   - **Park trigger** (architecture deviation; a shared contract/interface/schema change; a new dependency; edits outside the issue's file scope; an unmetable gate; material ambiguity): **park** the issue — comment opening with `🔴 Parked — ` on the issue, apply the appropriate label (`needs design`, `needs decision`, or `blocked`) (+ `in progress` if the branch has commits), preserve the branch, and return. Do not commit.

   **Omitting `/code-review` is not permitted.** If skipped under any constraint (time, token budget, tool error, self-review substitution), treat the omission as a park trigger — comment the reason on the issue, preserve the branch, apply `blocked` (+ `in progress` if the branch has commits), and return.

   **After a fix, before committing:**
   - **Code changed** (any `sourceGlobs` file): re-run `unitTestCmd` if defined (skip if absent), then re-run `/code-review` — the fresh review must be the **last action before commit**. The procedure does not loop past a second clean review. `POST_REVIEW_CHANGES: yes` is the implementer's machine-checkable signal that its edits were review-driven and the re-review is due; any `sourceGlobs` change independently triggers the re-review as a backstop, so a re-dispatch that changed source is always re-reviewed even if the field is `no`.
   - **Document-only** (`*.md`, READMEs, doc/comment text — nothing under `sourceGlobs`): commit directly; no re-run needed (`tests-green` no-ops on doc-only, and `/code-review` need not be re-run for a doc-only fix).
   - **No in-scope findings:** commit directly.

   **Cap: at most 2 review→fix cycles.** If `/code-review` still returns in-scope findings after the 2nd fix, **park** the issue: comment opening with `🔴 Parked — ` and the current diff state on the issue, apply `needs design` or `blocked` as appropriate (+ `in progress` if the branch has commits), preserve the branch, and return. The milestone loop continues. A review that won't converge usually means the plan is wrong.

   **Preflight gate (concluding action of 6.1).** Once the `/code-review` loop above has converged, before version bump/commit, run the preflight gate — its applicability, `act` (including the `"github-ci"` sentinel discovery mode), cap, verify step, and park/escape policy are the **Preflight** row of `### 4. Verification gates` and its shared loop; nothing is restated here. It fires here, as the concluding action of 6.1 rather than as a numbered sibling step, so the `6.1 … 6.9` ordinals (and their internal + external cross-references) stay fixed.
2. Assemble the **Decision Log** from the implementer's report (each choice → rationale → citation → alternatives rejected) for the PR body, and post the citations on the issue for review (`gh issue comment <n>`).
3. **Assemble the Code Review section** for the PR body — the evidence half of the audit trail (the Decision Log records *why* a choice was made; the Code Review section records *what review found* and how it was cleared). Record: whether `/code-review` ran, the finding count and severity per run (the 1st, and the 2nd if a re-review occurred), and each finding's resolution (re-dispatched and resolved / accepted with rationale / triggered park). If a run returned zero findings, state that with the run's effort level. **Absence of this section on a PR is a visible defect on PR review.** Use this template in the PR body:

   ```text
   ## Code Review

   - /code-review run: yes (omission is a park trigger — a submitted PR always carries a real review; a parked run opens no PR)
   - Findings: <count> in-scope finding(s) at <effort> effort
     - <finding> → re-dispatched and resolved | accepted (rationale: <…>) | triggered park
     - … (one line per finding, or "none" when count is 0)
   - No park-triggering findings. | Park-triggering findings: <list>
   ```

   The version-bump annotation this section carries depends on the mode resolved in step 6.4: "version-bump only — no logic change" in versioned mode; "version-free — no version bump" for a deliberately version-free repo (`versioning: false`); and "version-free — no version bump (plugin.json absent)" for the fail-safe (degraded) path. The parenthetical distinguishes a deliberately version-free repo from a misconfigured-versioned repo that degraded.

4. **Version bump.** Read `versioning` from the profile first.
   - **Version-free mode** (`versioning: false`): **skip the bump entirely** — make no edit to `.claude-plugin/plugin.json`. Annotate the **Code Review** section "version-free — no version bump" and proceed to commit. (Steps below do not apply.)
   - **Fail-safe degradation** (versioned mode — `versioning` `true` or absent — but `.claude-plugin/plugin.json` does **not** exist): do **not** fail. Degrade to version-free: skip the bump, log a one-line note (e.g. "versioned mode but no `.claude-plugin/plugin.json` — degraded to version-free, no bump"), annotate the **Code Review** section "version-free — no version bump (plugin.json absent)", and proceed to commit.
   - **Versioned mode** (`versioning` `true` or absent, and `.claude-plugin/plugin.json` exists): edit `.claude-plugin/plugin.json` `version` directly (it is config, not under `sourceGlobs`; the orchestrator edits it on the main thread — if a consumer's `sourceGlobs` covers `.claude-plugin/`, dispatch the implementer to apply the bump instead). This is a config edit, not a source change: **no `/code-review` re-run and no test re-run are needed; proceed directly to commit.** The carve-out covers only the `/code-review` run — the PR still requires its **Code Review** section, annotated "version-bump only — no logic change."
     - **Milestone run** (a target version was determined by `solve-milestone` and is held in the orchestrator's context — it is not a CLI argument): set `plugin.json` `version` to that target. **Idempotent** — if already equal, no change; move on.
     - **Standalone run** (no milestone target in the orchestrator's context): apply a **patch** bump (`x.y.Z` → `x.y.(Z+1)`), state the new version to the user, and **ask whether it should be minor or major instead** — adjust before opening the PR.
     - `plugin.json` is the **single source of truth** for the plugin version. `marketplace.json` carries no `version` field (Claude Code resolves `plugin.json` first; setting both is a documented footgun that silently masks the marketplace value). The bump rides in this PR — no separate chore PR.
5. Commit on the feature branch — the `tests-green` hook (`PreToolUse` on `git commit`) re-checks the suite. Review-before-commit is enforced by audit trail (the mandatory **Code Review** section), not by a shipped hook — the plugin ships no code-review hook.
6. Push the feature branch and open a PR with `--base <integrationBranch>` (never `protectedBranch` — enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection). Put the Decision Log and the **Code Review** section in the PR body. Add a `judgment call` label if any borderline autonomous call was made.
7. **Visual-review gate (UI issues — Layer 2).** Determine whether this issue touches a UI surface: `uiSurfaceGlobs` is configured in the profile **and** the PR's changed files match one of those globs (an implementer `NEW_UI_ELEMENTS: yes` declaration reinforces this signal).
   - **Not a UI issue** (`uiSurfaceGlobs` absent, or the diff matches no `uiSurfaceGlobs` path): no visual gate — proceed to auto-merge (step 8).
   - **UI issue:** do **not** auto-merge. The terminal state for this issue is *PR open, awaiting human visual sign-off* — apply the `needs review` label **to the PR** via the apply-time helper (idempotent `gh label create --force` then `gh pr edit <pr> --add-label "needs review"`) and leave the PR open for a human to test-render and merge. `solve-milestone`'s final summary lists all open `needs review` PRs.
     - **`visualCapture` configured** (the profile carries a `visualCapture` block with all three required keys — `serverCmd`, `readyUrl`, `signInPath`) **and this is a sequential run** (see the deferral below): capture convenience evidence inline. Any failure in this flow degrades to the human-test note below — it never fails the run and never auto-merges. The flow:
       1. **Boot the render daemon (once per run, reused).** Run `scripts/render-daemon.<sh|ps1> start` in the repo root (pwsh on Windows, bash elsewhere — the same host selection as `scripts/ci-preflight-steps.{sh,ps1}` at step 6.1). The daemon reads `visualCapture.serverCmd` and `visualCapture.readyUrl` **from the profile itself** (you do not pass them), spawns the seeded/persona app server detached, polls `readyUrl` until ready, and writes `.milestone-config/.runtime/render-daemon.json` (`port` · `token` · `pid` · `readyUrl` · `startedAt`). A nonzero exit means boot/reuse failed → degrade to the human-test note. **Derive the app origin (`scheme://host:port`) for the navigation below — `readyUrl` is the readiness probe only, not the navigation base.** `readyUrl` is a `/health`-style URL (e.g. `http://127.0.0.1:3000/health`), so take its scheme + host + port **origin** (strip the path and query): `http://127.0.0.1:3000`. Cross-check the origin's port against the state file's `port` field. Do **not** use `readyUrl` verbatim as the base — concatenating its trailing path would yield a malformed route.
       2. **Authenticate via the test sign-in seam.** Resolve `{persona}` from `visualCapture.persona` (default `super-admin`), substitute it into `visualCapture.signInPath` (e.g. `/dev/sign_in/{persona}` → `/dev/sign_in/super-admin`), and drive **Playwright MCP** to navigate `<origin><signInPath>` (the app origin from step 7.1 + the persona-substituted path, e.g. `http://127.0.0.1:3000/dev/sign_in/super-admin`) to establish the authenticated session.
       3. **Capture each surface × viewport × appearance.** For each **agent-supplied** surface route + required on-screen state (the implementing agent supplies the route(s) and target state per issue — there is no per-repo route map): for each entry in `visualCapture.viewports` (default `{ "desktop": { "width": 1440, "height": 900 } }`) and each entry in `visualCapture.appearances` (default `["light"]`), resize the Playwright MCP viewport, set the appearance, navigate `<origin><surface-route>` (the same app origin from step 7.1 + the agent-supplied route) into its required state, and capture one screenshot named `issue<n>-<slug>-<viewport>-<appearance>.png` (e.g. `issue42-prayer-list-desktop-light.png` — the per-viewport/appearance suffix keeps the fan-out filenames collision-free).
       4. **Publish.** Push the PNGs to an orphan `visual-review-assets` branch (so binary evidence never lands on `integrationBranch`) and post a **single** PR comment titled **"👁️ Visual evidence"** (`gh pr comment <pr>`) that, per shot, embeds the raw image and links its blob. The 👁️ glyph deliberately reuses the board legend's "awaiting visual review" marker — same review concept, documented reuse, not a second meaning.
     - **Degradation — `visualCapture` absent or incomplete (missing a required key), OR any capture failure** (daemon will not boot/reuse, sign-in fails, a surface will not render, push fails): do **not** fail and do **not** auto-merge — post a note on the PR (`gh pr comment <pr>`) that visual evidence is unavailable and a **human visual test is required before the merge to `integrationBranch`**. Capture is convenience evidence only; the human-before-merge checkpoint holds either way, and the `needs review` label keeps the PR held open for human sign-off regardless.
   - This makes auto-merge opt-in per issue class: logic-only / non-UI issues auto-merge on green (step 8); UI issues await human merge regardless of render capability.
8. **Auto-merge on green (non-UI issues only):** once CI is green, run `gh pr merge --squash --delete-branch`. This replaces the human-choice step of `superpowers:finishing-a-development-branch`. **UI issues are skipped here** — they remain open per the visual-review gate (step 7) until a human merges.
9. Confirm the issue is closed (a linked PR auto-closes it; otherwise `gh issue close <n>`). **For a UI issue held at the visual-review gate, the issue stays open** with its PR awaiting human visual sign-off — it closes when the human merges the PR.

## Autonomy model (Balanced)

**Proceed autonomously (log on the PR):** implementation choices within the approved architecture; reuse of existing helpers, styles, and conventions; test design; local reversible refactors; resolving in-scope `/code-review` findings (step 6.1).

**PARK & continue (the autonomous runtime parks; it does not interactively wait):** deviation from the approved architecture; any change to a shared contract, interface, base class, or DB schema used beyond this issue; a new dependency; edits outside the issue's expected file scope; a gate that cannot be met without a design change; material ambiguity in the issue's intent; `/code-review` omission or substitution — skipping `/code-review` for any reason (time, token budget, tool error, self-review substitution) is **not** an in-scope autonomous decision; budget pressure is not a permitted exception.

In the autonomous runtime, a park means: post a comment on the issue that **opens with `🔴 Parked — ` followed by the reason** (e.g. `🔴 Parked — architecture conflict: shared interface change required`); apply the appropriate label (`needs design`, `needs decision`, or `blocked`); also apply the `in progress` label (via the apply-time helper) when the feature branch has commits — `in progress` is the open-WIP signal the milestone loop and post-run review rely on; leave the issue open; leave the branch open with any work preserved; and return — the milestone loop continues with independent, clean issues. **Only a systemic failure** (auth/`gh` failure, broken `integrationBranch`, missing tooling) halts the whole run. A standalone interactive `solve-issue` still parks durably (comment + label + open branch); it may additionally narrate to the watching operator.

**Additional park triggers:**
- The recorded/locked design is internally contradictory → park with `needs design`.
- The orchestrator (or triage) judges the approved design will produce a poor result → park with `needs design`.
- A self-noted risk about the **approved** design (e.g. "this list could get long at realistic data volumes") → park with `needs design`. Each of these is a park (comment + label + open branch), **not** silent resolution and **not** an interactive prompt.
- An implementer-declared `NEW_UI_ELEMENTS: yes` with the acceptance criteria silent on the element's visual/UX detail → park with `needs design`.
- An implementer-declared `DESTRUCTIVE_OPS: yes` with the confirmation UX unspecified → park with `needs decision`.

**Within an explicit run, an in-scope `/code-review` finding is a *proceed-autonomously* event, not a clarifying-question moment** — fix it and log it. The operator pause is reserved for park triggers; the unattended contract overrides any general inclination to ask.

**Architecture is locked** at plan-approval time (step 2). The procedure executes approved architecture; it does not pivot. If implementation proves the plan wrong → park, not pivot.

A change is **architecture** (→ park) if it touches any of: a component or data structure named in the approved plan; a shared contract, interface, base class, DB schema, or public API used by code outside this issue; data ownership or a cross-component boundary; a new external dependency; or any file outside this issue's stated scope. A change is an **implementation detail** (→ proceed, log) if it is local to this issue's own files, changes no shared contract, and is reversible — a binding style, a private helper, a local refactor, or test design. When the distinction is genuinely ambiguous, treat it as architecture and park.

| Scenario | Classification | Action |
|---|---|---|
| Computed get-only binding → backed `SetProperty` (same property name, same consumer contract) | Implementation detail | Proceed, log in PR Decision Log |
| Extracting an existing method into a private helper in the same file | Implementation detail | Proceed, log if non-trivial |
| Adding a parameter to a shared interface used by other issues/components | Architecture | Park |
| Moving data ownership from ViewModel A to Service B | Architecture | Park |

**Audit trail (always):** a Decision Log on every PR, a **Code Review** section recording every `/code-review` run and its findings/resolutions, and a `judgment call` label on borderline calls, so post-run PR review surfaces every judgment.

## Permission pre-flight gate

**Runs once per run, before the first background dispatch. Zero cost on synchronous paths.**

**Scope: this gate applies only when background dispatch is about to be used (the async dispatch points introduced in #89). Sequential/synchronous runs SKIP it entirely — skipped, not merely cheap; the gate is not executed at all on a sequential run.**

> **Sequential / synchronous runs SKIP this gate entirely** — it is not merely cheap, it is not executed at all. The gate applies only when background dispatch is about to be used (the async dispatch points introduced in #89). On a sequential run, proceed directly to the first background-dispatch step without any gate evaluation.

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

**Worker auto-deny handling.** If a background worker chunk receives an auto-deny on a tool call mid-execution, treat it as a **park** — post a comment opening with `🔴 Parked — auto-deny on <tool>` on the issue, apply the `blocked` label (+ `in progress` if the branch has commits), preserve the branch, and return the structured handback with `status: parked`, `parkLabel: "blocked"`, and `parkReason: "auto-deny on <tool>"` (see Worker mode Delta 3 for the full handback schema — `parkLabel`, `parkReason`, and the handback structure are defined there). This is the same park-don't-prompt contract all other gates use — an auto-deny is not a silent failure. On a sequential (non-worker) run, no structured handback exists — park via the normal park steps (comment, label, preserve branch, return); there is no `parkLabel`/`parkReason` handback because there is no orchestrator to receive one.

## Worker mode (`--worker`)

Worker mode is the per-issue half of `solve-milestone`'s parallel (default) flow (milestone 1.5.0): the orchestrator builds mutually-independent issues within a dependency Wave concurrently — each in its own git worktree — then integrates them through an orchestrator-owned **serial verified merge tail**. This section defines the contract the parallel orchestration (#72), the merge tail (#73), and branch-per-Wave granularity (#75) consume; those skills do not exist yet, so the terms used here (`--worker`, "worker mode", "merge tail", "handback", "wave branch", "parallel-safe gates", "deferred gates") are the authoritative source.

**`--worker` is an interpreted token, not a parsed CLI flag.** Claude Code does no argument parsing — `$ARGUMENTS` is string-substituted — so worker mode is **recognized** when the dispatch text contains a `--worker` token (with the orchestrator-provided worktree path), exactly as the rest of the plugin treats flags. **When the `--worker` token is absent, none of this section applies and the entire sequential pipeline above runs byte-unchanged.** Sequential (non-worker) `solve-issue` is the default and is unaffected.

Worker mode **is today's `solve-issue` pipeline with EXACTLY THREE DELTAS.** Everything else is identical: triage (run as Branch A when the brief embeds the result as explicit named values, or Branch B fallback when absent — workers re-invoke triage ONLY as Branch B fallback if the caller supplied no result) and the root-cause gate, the implementer dispatch and its contract, the declaration gates, the unit gate, `/code-review` and its **Code Review** section, the citations, park-don't-prompt (a worker never prompts a human — it parks), the Decision Log, the version-bump rules (step 6.4), and the audit trail all carry over verbatim. **The permission pre-flight gate is not in this carry-over list** — it is orchestrator-level, pre-dispatch behavior (see the section above); a worker is already backgrounded past it and never runs it. The **at-most-2 re-dispatch cap on every gate** carries over too, but follows its gate: each cap applies to the gate it guards, so the caps on the **parallel-safe gates the worker actually runs** travel with the worker, while the caps on the **deferred gates (E2E, any server-starting preflight)** move to the serial tail with those gates (Delta 2). This gate-split is the **mechanism** of Delta 2 ("builds but does not merge") — it is not a hidden fourth behavioral change. Only the three deltas below differ. Both Branch A and Branch B return the identical Step 7 schema — an issueStates entry plus an edges array, per skills/triage/SKILL.md — so the Blocker check and build-profile read are shape-identical regardless of which branch ran.

> **Permission pre-flight gate and worker mode.** The permission pre-flight gate (described in the section above) is **orchestrator-level, pre-dispatch behavior**. A worker is already backgrounded past it — the gate ran (or was skipped on a synchronous path) before the worker was dispatched. A worker **never runs the gate itself**.

### Delta 1 — Runs in an orchestrator-provided worktree

The **orchestrator owns worktree creation.** `git worktree add <path> -b issue/<n>-<slug> <integrationBranch>` is run by the orchestrator (solve-milestone, #72), which passes the worktree path to the worker. The worker **runs inside that provided worktree** — it does **not** create its own. This resolves ownership of `git worktree add`: the orchestrator, not the worker.

The branch-state probe (step 3 of the procedure) operates **inside that worktree**, and worker mode **replaces step-3 path (d)**. Because the orchestrator already cut the branch with `-b`, the cold worker start is a branch that *exists*, is clean, and is 0 commits ahead — a state that matches none of resume paths (a)/(b)/(c) and would fail path (d)'s "no branch" guard. That pre-cut-branch cold case is a **defined state, not a fall-through**: on a cold worker start the worker **builds directly on the orchestrator-created branch — it does not cut a fresh branch**. The probe's resume paths (a)/(b)/(c) still apply **unchanged** if a worker is re-dispatched against a worktree that already carries prior work (an open PR, commits ahead, or uncommitted changes). All other "Before starting" preconditions apply within the worktree, including the **step-3.5 profile migration**: each worker re-runs the idempotent migration preamble inside its own worktree, and the `git mv` rides that worker's branch (reconciled by the serial merge tail). It is idempotent, so a worktree cut from a tip where `.milestone-config/driver.json` already exists is a clean no-op.

**`force-subagent` compatibility (no change needed).** A worker's edits are already permitted: a dispatched subagent carries `agent_id` / `parent_session_id`, which the hook treats as allow (`hooks/force-subagent.sh:18-21` — the subagent-context allow loop). The profile (`.milestone-config/driver.json`, or a legacy root `milestone-driver.json`) is a committed, tracked file, so it is present in every worktree, and the hooks resolve it `cwd`-relative (`hooks/force-subagent.sh:34-40`) — they fire identically inside a worktree. No worktree-specific hook configuration is required.

### Delta 2 — Stops before the step-8 auto-merge; builds but does not merge

The worker builds, runs the **parallel-safe gates in the worktree**, does the version bump (step 6.4), commits, pushes, then **returns the branch instead of merging.** It does **not** run step 8 (auto-merge). Each worker applies the same idempotent bump to the shared milestone target in `plugin.json`; because the edits are identical same-line writes, the merge-in tail reconciles them in a 3-way merge without conflict — so the bump stays in the worker.

**Parallel-safe gates** (run in the worktree, in the parallel phase):
- the unit suite (step 4) if `unitTestCmd` is defined;
- `/code-review` and its resolve loop (step 6.1);
- the static `preflightCmd` — the lint / format / static-analysis / security-scan class only.

**Deferred gates** (NOT run by the worker — handed to the serial merge tail, #73). Concurrent workers each starting a **port-binding** gate (dev server / E2E / render-smoke) contend for the same fixed port. So in parallel builds the worker runs **only** the parallel-safe gates above; **E2E (step 4, E2E row) and any server-starting "preflight" are deferred to the serial tail**, where they run once against accumulated integrated state — also where they are more meaningful.
- **Step 7 (visual-review gate) splits the same way.** Opening the PR and applying the `needs review` label are parallel-safe, so a UI-issue worker does those. But the **render capture is port-binding** (it boots the render daemon — `scripts/render-daemon.{sh,ps1}` — which spins up the `visualCapture.serverCmd` app server on the consumer's fixed port) — so it is a **deferred gate too**: the worker **must not** boot the render daemon or capture in the parallel phase (a single per-run, fixed-port daemon cannot safely serve concurrent worktrees). The screenshots are owed by the **serial tail / human**, not attached by the worker. (So a parallel worker leaves a UI PR open with the `needs review` label but **no** screenshots yet; the serial tail or the human runs the step-7 capture flow before merge — consistent with step 7's "capture is convenience evidence; the human-before-merge checkpoint holds either way".)
- **Escape hatch:** a consumer can inject a per-worktree `PORT` (so each worktree binds a distinct port) to keep such a gate — including the render/screenshot capture — in the parallel phase instead of deferring it.

**PR-opening is granularity-conditional:**

| Granularity | Worker opens a PR? | Merge handling |
|---|---|---|
| **Issue (default)** | Yes — `--base <integrationBranch>`; for a UI issue the worker runs **only the parallel-safe part of step 7** (opens the PR, applies the `needs review` label) and **defers the render/screenshot capture to the serial tail / human** — see Delta 2 | The serial merge tail (#73) merges each PR individually; it (or the human) captures the deferred screenshots |
| **Wave (#75)** | No per-issue PR — hands the branch back | The orchestrator folds the branch into the **wave branch** (`wave/<milestone>-w<N>`) and opens one wave PR |

### Delta 3 — Returns a structured handback

The worker returns a structured handback as an **optimization hint** — it lets the orchestrator skip redundant git/gh queries when driving the merge tail and the final summary. It is explicitly **not** the source of truth. The Phase 1 barrier (`solve-milestone` step 5) **re-derives terminal state from git/gh** via the step-3 branch-state probe and uses the handback only as a hint: when the handback is present and well-formed the barrier skips the queries the probe would otherwise run; when the handback is **absent or partial** — e.g. the worker's final assistant message drifted off-format under a long, tool-heavy run — the barrier **fills in every field from ground truth** and no work is stranded. Each field below is independently re-derivable from git/gh, so the handback degrades gracefully:

```text
{ issue, status: built-green | parked, branch, worktreePath, prUrl?, isUI, declarations, parkLabel?, parkReason? }
```

| Handback field | Ground-truth source the barrier re-derives from |
|---|---|
| `status: built-green` | open PR for `issue/<n>-*`, or branch pushed with commits ahead of `integrationBranch` (step-3 probe paths a/b) |
| `status: parked` | park label (`needs design` / `needs decision` / `blocked`) + `🔴 Parked` / `🔴 Triage` / `🔴 Blocked` comment (the same signal the sequential loop reads) |
| `prUrl` | `gh pr list … select(.headRefName \| startswith("issue/<n>-"))` (verbatim step-3 path-a query) |
| `isUI` | `git diff <integrationBranch>...HEAD --name-only` ∩ `uiSurfaceGlobs` (re-derived as below, not from a PR) |
| `declarations` | the only field not in git/gh; reinforces `isUI`, which is independently computable — so a drop degrades gracefully |

- `prUrl?` — optional: present in **issue** granularity (the worker opened a PR); absent in **Wave** granularity (no per-issue PR).
- `isUI` — whether the issue touched a UI surface (drives the visual-review hold in the tail). The worker derives this from the **worktree diff against `integrationBranch`** — changed files matching `uiSurfaceGlobs` (`git diff <integrationBranch>...HEAD --name-only`), not from a PR's changed-file list — so `isUI` is computable whether or not a per-issue PR was opened (Wave granularity and parked workers have no per-issue PR). An implementer `NEW_UI_ELEMENTS: yes` declaration reinforces the signal, mirroring step 7.
- `declarations` — the implementer's `USER-FACING CHANGES` block (e.g. `NEW_UI_ELEMENTS`), carried through so the orchestrator does not re-read it.
- `parkLabel?` / `parkReason?` — present **only** when `status: parked`.

**A worker that parks hands back `status: parked`** with its `parkLabel` and `parkReason` (the same label/reason it would otherwise post per park-don't-prompt). The orchestrator excludes a parked issue from the merge tail with its branch and labels intact — exactly as the sequential loop excludes a parked issue. The barrier **re-derives the park from git/gh** (live labels + the step-3 probe), using `parkLabel` / `parkReason` from the handback only as a corroborating hint; the park is never inferred from the handback alone, so a dropped final message cannot hide a parked issue any more than it can strand a built-green one.

### Sequential behavior is byte-unchanged

These three deltas are the **only** differences. With no `--worker` token, the pipeline above runs exactly as written — same gates, same caps, same merge, same close. Worker mode adds an opt-in path; it changes nothing about the default sequential run.

## Async mode (`--async`)

**`--async` is an interpreted token, not a parsed CLI flag.** Claude Code does no argument parsing — `$ARGUMENTS` is string-substituted — so async mode is **recognized** when the invocation text contains an `--async` token. **When the `--async` token is absent, none of this section applies and the entire sequential pipeline above runs byte-unchanged.** Async mode is an opt-in signal to the caller (main line or user session) to dispatch this skill as `Agent(run_in_background: true)` — it does not alter the internal pipeline, except for Delta A1, in `skills/solve-issue/async-mode.md`.

Read `skills/solve-issue/async-mode.md` for the full `--async` dispatch contract — how the caller dispatches, the pre-dispatch permission pre-flight gate, the byte-unchanged in-agent pipeline, Delta A1 (the suppressed version-bump confirm), and the background-agent constraints.

## Parent-issue detection (`md-epic`)

**Runs before anything else** — before `## Before starting` step 1 (profile read) and before `### 0. Triage`. Read `#n`'s labels: `gh issue view <n> --json labels`, exact match against `.labels[].name` for the literal `md-epic`. This is the same opt-in-fork shape already used for the `--worker` token (`## Worker mode`, above) and the `--async` token (`## Async mode`, above) — a label read here instead of a dispatch token.

- **No `md-epic`** → today's entire pipeline runs byte-unchanged, starting at `## Before starting` step 1. Nothing in this section or `### Parent path` below applies.
- **`md-epic` present** → `#n` is a **parent issue** — a pure orchestration node that carries no code. Do **not** proceed to `## Before starting` steps 2/3, `### 0. Triage`, root-cause, or the implementer for `#n`. Go directly to `### Parent path` below; it replaces the rest of this skill's pipeline for this invocation.

### Parent path

A parent issue's body carries an ordered list of milestones — the build order for a feature too large for one milestone (the read-contract in `docs/superpowers/specs/2026-07-04-md-epic-driver-fanout-design.md`). This path drives that list to completion; it never authors code for `#n` itself.

1. **Profile read only.** Run `## Before starting` step 1 (profile read) — the fan-out loop needs `integrationBranch` to re-sync between milestones. **Skip steps 2 and 3** (the clean-tree check and the branch-state probe) — a parent issue authors no code, so it has no feature branch and no branch state to probe.

2. **Parse the ordered milestone list** from `#n`'s raw body with the #266 parser (pwsh on Windows, bash elsewhere — same host selection as `scripts/ci-preflight-steps.{sh,ps1}` at step 6.1):

   ```bash
   gh issue view <n> --json body --jq .body | bash scripts/parse-md-epic-order.sh
   # pwsh -NoProfile -File scripts/parse-md-epic-order.ps1 on pwsh-only hosts
   ```

   The parser emits one `<kind>\t<raw>` record per entry on stdout (`kind` = `number`|`title`), or exits nonzero with the failure named on stderr — it never calls `gh` and never resolves an entry itself (`scripts/parse-md-epic-order.sh`, issue #266).

   **A nonzero exit parks the PARENT issue `#n` — the fan-out never starts.** No `md-epic-order` block, an unterminated fence, or one malformed line all invalidate the whole list (a half-parsed build order is unsafe to act on). Post a comment on `#n` opening `🔴 Parked — ` quoting the parser's stderr (`gh issue comment <n>`), apply `blocked` via the apply-time helper (`gh label create --force` then `gh issue edit <n> --add-label blocked`), leave `#n` open, and return. No milestone in the list is driven this run.

   **A zero exit with ZERO entries (empty stdout) also parks `#n` — this is not a silent success.** A well-formed `md-epic-order` block with no interior entries parses cleanly (exit 0) but has nothing to drive; treat it the same class as an authoring mistake, not a valid empty run. Post a comment on `#n` opening `🔴 Parked — ` naming "empty md-epic-order block — no milestones to drive" (`gh issue comment <n>`), apply `blocked` via the apply-time helper (`gh label create --force` then `gh issue edit <n> --add-label blocked`), leave `#n` open, and return. No milestone in the list is driven this run.

3. **Resolve each `{kind, raw}` entry to a live milestone**, mirroring `solve-milestone`'s own number/title resolution (`skills/solve-milestone/SKILL.md:102-106`):
   - `number: <raw>` → `gh api repos/{owner}/{repo}/milestones/<raw> --jq '{number, title}'`. A non-2xx response means "does not resolve."
   - `title: <raw>` → `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | select(.title=="<raw>") | {number, title}'`. Zero or multiple matches both mean "does not resolve" — never guess between two same-titled milestones.
   - **Does not resolve, OR resolves but has zero total issues** (`open_issues + closed_issues == 0`) → **skip only that entry** — not a park. Log a warning line in the aggregate summary (step 6) and continue with the next entry.

4. **Drive each resolved milestone sequentially, in listed order** — never concurrently; a later milestone may depend on an earlier one's merged code:
   - **Resume-skip, no local checkpoint** (mirrors the no-checkpoint-file philosophy already stated for the branch-state probe, `## Before starting` step 3). Before driving, re-read the milestone's counts: `gh api repos/{owner}/{repo}/milestones/<number> --jq '{open_issues, closed_issues}'`. `open_issues == 0` AND `closed_issues > 0` → already complete — skip **silently**, count it done in the summary. This makes re-running the parent idempotent with no state file to maintain.
   - **Numeric-title guard (skip-with-warning).** Before driving a milestone that is not already complete, check its resolved title from step 3's `{number, title}`. If the title is **purely numeric** (digits only), do **not** drive it: `solve-milestone`'s own purely-numeric-title halt (`skills/solve-milestone/SKILL.md:105`) is a human-prompt halt that is **not** suppressed by `--driven` (`skills/solve-milestone/SKILL.md:143`), so driving it would stall the unattended fan-out forever waiting on a human. **Skip that milestone with a warning** in the aggregate summary (step 6) instead — the human must rename it to a non-numeric title before it can be driven unattended — and continue with the next entry.
   - **Otherwise, drive it:** invoke `/milestone-driver:solve-milestone <number> --driven` — the skill-invokes-skill pattern `solve-milestone` already uses to invoke `/milestone-driver:triage` (`skills/solve-milestone/SKILL.md:218-224`) — and await completion. `--driven` suppresses the DB-hazard interview (`skills/solve-milestone/SKILL.md:143`, `:151`, `:173`) so the fan-out never blocks on a prompt nobody is watching for.
   - **Re-sync `integrationBranch`** (`git fetch`, fast-forward) after each milestone, before advancing to the next, so the next milestone builds on the prior one's merged work.
   - **A systemic failure inside a driven `solve-milestone`** (`gh auth`, a broken `integrationBranch`, missing tooling — `skills/solve-milestone/SKILL.md:478-481`) halts the **whole fan-out loop**, not just the current milestone — later milestones cannot be driven safely either.

5. **`#n` itself is never built.** It carries no code, so it never goes through `### 0. Triage`, root-cause-or-park, or the implementer dispatch — it is a pure orchestration node. Its label state changes only via the park path in step 2 above.

6. **Aggregate summary**, one row per milestone — mirroring `solve-milestone`'s own run-complete reporting shape (Template 3, `skills/solve-milestone/SKILL.md:527`; the Final summary content requirements, `:560`). Classify each driven milestone from ground truth after driving, not from the driven run's own narrative (the same re-derive-over-handback posture already used at the Wave barrier, `skills/solve-milestone/SKILL.md:399`, `:413-417`):

   | Milestone | Outcome | Note |
   |---|---|---|
   | #<number> — <title> | done already \| built this run \| held for visual review \| parked with opens | warning text for a skipped entry, or — |

   - **done already** — the resume-skip in step 4 fired before driving (`open_issues == 0`, `closed_issues > 0`, never dispatched this run).
   - **built this run** — after driving, `open_issues == 0` and `closed_issues > 0`.
   - **held for visual review** — after driving, `open_issues > 0` and every remaining open issue is a UI issue with an open PR carrying `needs review`.
   - **parked with opens** — after driving, `open_issues > 0` and at least one remaining open issue carries a blocker label (`needs design` / `needs decision` / `blocked`).
   - A milestone with both open `needs review` PRs and parked issues reports both facts in its Note column.
   - Each **skipped entry** from step 3 gets its own row (raw reference + why it didn't resolve, or "0 issues") rather than being silently dropped from the summary.
   - A milestone **skipped by the numeric-title guard** (step 4) also gets its own row — `#<number> — <title>` — with the Note column stating it cannot be driven unattended until the human renames it to a non-numeric title.

## Output spec

<!-- KEEP THIS ICON LEGEND BYTE-IDENTICAL across solve-issue and solve-milestone (see plan 2026-06-04 verification model). -->
**Icon legend:** ✅ merged · 🔨 building · ⏭️ queued · ⏸️ parked · 👁️ awaiting visual review · ⚖️ judgment call · 🔴 Your move

### Template 1 — Run start / plan board

Show after the ### 0. Triage step completes.

```text
🚀 Issue #201 — [title] · [risk: light | heavy] · [UI | non-UI]

| Issue | Title   | Risk   | UI | Status      |
|-------|---------|--------|----|-------------|
| #201  | [title] | [risk] | —  | 🔨 building |

▶ Building — the floor is yours.
```

### Template 2 — Issue completion (terminal output)

This is the terminal output for solve-issue. It mirrors the issue-row format of solve-milestone's Template 2.
<!-- Structural mirror of solve-milestone Template 2; keep column schema (Issue/Result/Gates/PR/Note) in sync. -->

One row per issue; emit only the row that matches the actual outcome and suppress the other rows — the `✅ merged` row when the PR was merged, the `👁️ open` row when the PR is awaiting visual review, or the `⏸️ parked` row when the issue was parked.

```text
🏁 Issue #[n] · [T] min

| Issue | Result     | Gates | PR | Note                    |
|-------|------------|-------|----|-------------------------|
| #201  | ✅ merged  | 🔍✓(0 findings)  | #301 | —    |
| #203  | 👁️ open   | 🔍✓(1 fixed)     | #303 | awaiting visual review  |
| #202  | ⏸️ parked  | —                | [#pr | —] | [park label]      |
```
PR cell: show the PR number if the issue has one, else —.

Gates legend: 🧪 = unit suite · 🔍 = code review · 🌐 = E2E

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present steps, gates, lists, and options as **tables**, not inline prose. Mark anything that needs a human with 🔴. (Mirrors the agents' communication-style contract.)

Use the templates in `## Output spec` at their prescribed trigger points. Between boards: one-line dispatch notes only — no narration paragraphs.

## Non-negotiables
- Gitflow. PRs target `integrationBranch` only — never `protectedBranch`.
- Honor the profile's `nonNegotiables` (framework versions, platform targets).
- The main thread never authors application or test code — always dispatch the implementer.
