---
name: solve-issue
description: This skill should be used when the user invokes "/milestone-driver:solve-issue <n>", or asks to "solve issue <n>", "fix issue <n>", or "drive issue <n>" through the milestone-driver gated procedure. Runs one GitHub issue end-to-end as an orchestrator — triage, root-cause-or-park, dispatch the implementer subagent (TDD, citations), unit + E2E gates, code review, PR to the integration branch, auto-merge on CI green for non-UI issues (UI issues are held open for human visual sign-off), then close — never authoring application or test code on the main thread.
---

# solve-issue — gated per-issue procedure

Run exactly one GitHub issue through a fixed, gated pipeline. The main thread acts only as an **orchestrator**: read, decide, dispatch, review, integrate. It **never authors application or test code itself** — the `force-subagent` hook enforces this mechanically. Orchestrate the `superpowers:*` skills for the inner loop. **Before anything else, check `#n`'s labels for `md-epic`: a parent issue takes `### Parent path` (see `skills/solve-issue/md-epic-fanout.md`) instead of the pipeline below.**

## Contents

Before starting · The procedure (0 Triage · 1 Read the issue · 2 Evaluate the codebase for root cause · Build profile resolution · Resolve cited project-docs sections · Resolve cited `path (anchor)` citations · 3 Dispatch the implementer · 4 Verification gates · 6 Review → integrate → close) · Run-end cost record · Autonomy model · Permission pre-flight gate · Milestone granularity · Async mode · Parent-issue detection · Output spec (Template 1 · Template 2) · Output style · Non-negotiables

## Before starting

Every `${CLAUDE_PLUGIN_ROOT}/scripts/*.{sh,ps1}` invocation in this skill selects its host the same way: **pwsh on Windows, bash elsewhere**.

1. Read the profile (see the plugin's `docs/profile-schema.md`).

   | Profile-resolution decision point | Behavior |
   |---|---|
   | Resolution order (transitional) | Read `<repo>/.milestone-config/driver.json` first; if absent, fall back to the legacy root `<repo>/milestone-driver.json`. This transitional READ covers the gap before the migration move lands. |
   | Both files exist | `.milestone-config/driver.json` wins for the read. |
   | Migration (`git mv`) | Deferred to step 3.5, so it rides the feature branch and does **not** trip the clean-tree precondition (step 2). Do **not** move here. |
   | Neither file exists, or `integrationBranch` / `protectedBranch` / `sourceGlobs` missing | Invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. |
   | `implementerAgent` | Defaults to `milestone-driver:implementer` when omitted. |
   | Optional keys — `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `preflightCmd`, `domainSkills`, `nonNegotiables`, `projectDocs` | `projectDocs` defaults to `.project/` when absent. Their steps are skipped cleanly when absent. |

   1.1. **Self-heal the scratch-ignore (always, before any `.milestone-config/` scratch write).** Ensure a **committed** `.milestone-config/.gitignore` exists ignoring only the scratch names below; the directory also holds **tracked** config (`driver.json`, `feeder.json`), so never blanket-ignore it. Absent → create it (`mkdir -p .milestone-config`, then write the block). Present → do nothing. It rides the feature branch. (`driver.json` / `feeder.json` are intentionally NOT listed — never add a blanket `*` or `/` rule.)

      <!-- KEEP THIS BLOCK IN SYNC with the committed .milestone-config/.gitignore in this repo and with solve-milestone / scripts/triage-cache.{sh,ps1}, feeder setup / plan. -->
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

   1.1.1. **One-time notices.** Immediately after the profile read: read `${CLAUDE_PLUGIN_ROOT}/skills/notices.md` and, in file order, evaluate each section whose `Skills` field includes `solve-issue` (today: preflight, visualcapture, code-review-gate, aiprefilter, cost-record, uisurfaceglobs), applying that section's `Trigger` → `Text` → `Marker` → `Legacy fallback` mechanics. Never evaluate a section scoped only to `solve-milestone` (today: trello, parallel-default).
2. **Require a clean working tree** (cold-start precondition) **and a current local `integrationBranch`** (`git fetch`, fast-forward). One exception, never stashed or discarded: step 3's probe finding an existing `issue/<n>-*` branch (committed or uncommitted prior work) skips this enforcement. Any other dirty state is a cold-start violation.
3. **Branch-state probe (resume an interrupted run).** `git fetch` first, then classify prior progress from git + gh before cutting anything; first match wins:
   - **(a) A PR exists for `issue/<n>-*`**, merged or open (client-side filter: `gh pr list --state all --limit 200 --json number,headRefName,state,url --jq '.[] | select(.headRefName | startswith("issue/<n>-"))'`).
   - **(b) No PR; branch `issue/<n>-*` exists (local or remote) with commits ahead of `integrationBranch`.**
   - **(c) No PR; no commits ahead; the issue branch `issue/<n>-*` is checked out with uncommitted changes** (the normal implementer contract).
   - **(d) Otherwise (no branch, no PR, clean tree):** cut a fresh feature branch from `integrationBranch` (e.g. `issue/<n>-<slug>`) — cold start, dispatch the implementer (### 3. Dispatch the implementer). This is the normal first-pass state and never an error.

   **(d) runs inline; (a), (b) and (c) are resumes** — read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/resume-paths.md` and follow its `### Resume paths`.

   This derives resume-state entirely from git + gh; there is no checkpoint file. **Never skip `/code-review`** on a resumed path; a fix it triggers runs step 6's normal re-review and push cycle.

   **3.5. Profile migration (run once, on the feature branch).** With step 2 passed and the branch established: if `<repo>/.milestone-config/driver.json` exists, use it. Else if a legacy root `<repo>/milestone-driver.json` exists, migrate it — `mkdir -p .milestone-config`; `git mv <repo>/milestone-driver.json <repo>/.milestone-config/driver.json` (when git-tracked, else plain `mv`). Else it is a new project (setup creates the canonical file; the other skills auto-invoke setup; hooks fail-open). Idempotent: a no-op once `.milestone-config/driver.json` exists. When both exist, `.milestone-config/driver.json` wins — no move, no overwrite, no deletion of the leftover root file. The move rides the issue's PR, not a separate commit.
4. Create one TodoWrite item per numbered step below. Work them in order — do not skip or reorder.

## The procedure

**The park action, referenced by every park below.** Post a comment on the issue in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` and the reason (`gh issue comment <n>`); apply the named label, plus `in progress` when the feature branch has commits, via the apply-time helper (idempotent `gh label create --force` then `gh issue edit <n> --add-label`); leave the issue open; preserve the branch with any work done; and return. Never an interactive prompt.

### 0. Triage

**Two branches — always run one:**

**Branch A — Explicit-supply path (reuse).** Fires **iff the caller explicitly supplied this issue's triage result at invocation time** — an inline restatement carrying named fields with ACTUAL VALUES (e.g. "step-0 result for #N: `issueStates["N"] = { blockers: false, label: null, advisories: [...], risk: "light" }`, `edges["N"] = [...]`"). Fields absent, label-only, or partial is not an explicit supply and falls to Branch B. Use it directly — do **NOT** re-invoke `milestone-driver:triage <n>` — and proceed to the **Blocker check**. It IS this run's verified Phase 0 triage result, not a skip.

**Branch B — Standalone / fallback path.** No explicit supply — absent, partial, or merely recalled from earlier context — invoke `milestone-driver:triage <n>` (single-issue mode) and use the returned result for the **Blocker check**. Branch B is the safe default, never an error.

**Blocker check (both branches).** A Blocker for this issue → **park**: triage has already posted the `🔴 Triage` comment; VERIFY it exists (`gh issue view <n> --comments`) and post it if missing (idempotent); apply the recommended label from `issueStates["<n>"].label` — `needs design` for a design gap, `needs decision` for a non-design decision; do **not** proceed to step 1. All-clear or Advisory-only → proceed to step 1.

### 1. Read the issue
Run `gh issue view <n>` with comments. Restate the acceptance criteria plainly before continuing.

### 2. Evaluate the codebase for root cause
Invoke `superpowers:systematic-debugging`. Read the implicated code — the file(s) plus direct callers and callees.

**🔴 GATE — root cause:** root cause not identifiable from the codebase → **park** with `blocked` (or `needs design` if the gap is a design gap), describing the blocker. Do not proceed to implementation.

When found, write an **architecture-aware plan** grounded in the codebase and its conventions. That plan is the **locked** architecture for this issue.

**`design-cleared` means a decision was recorded**, not that it is correct or buildable: still **park** a `design-cleared` issue with `needs design` if the recorded/locked design is internally contradictory or will produce a poor result.

### Build profile resolution (resolved after step 0, governs steps 3–6)

Read `issueStates["<n>"].risk` from the step-0 result (held Phase 0 result in a milestone run, fresh single-issue return standalone): `"light"` or `"heavy"`, defaulting to `"heavy"` when absent or inconclusive. That one read governs the whole build profile:

| Profile | Implementer brief | E2E gate (step 4, E2E row) | `/code-review` effort (step 6.1) | Review cycles (step 6.1) |
|---|---|---|---|---|
| **Light** | Include a `risk:light` token in the brief | Skip when the issue touches no UI surface | `low` or `medium` | 1; a 2nd only on a Critical or Important finding |
| **Heavy** (default) | Standard TDD brief (no `risk:light`) | Per step 4's E2E row (UI surface + e2eTestCmd) | `high` or `xhigh` | 2 |

The safety floor is **unconditional for both profiles**: triage (step 0), the `tests-green` hook, and `force-subagent` always run. Light relaxes ceremony only — it never skips verification. (A parent issue carrying `md-epic` never enters this pipeline — see `skills/solve-issue/md-epic-fanout.md`.)

### Resolve cited project-docs sections (once, before dispatch)

Resolve the issue's cited `.project/` sections **once, here in the orchestrator**, so subagents receive the grounding text in their brief rather than re-reading whole docs. Runs after the build profile resolves and **before ### 3. Dispatch the implementer**, adding inputs to the step-3 brief.

1. **Source the docs root.** Use `projectDocs` already resolved at step 1 (defaults to `.project/`). Do **not** re-resolve the profile here.
2. **Parse the cited anchors.** From the issue body + acceptance criteria (read at step 1), collect the `.project/<doc>#<section>` anchors the issue cites — `<doc>` is the path under the docs root, `<section>` the heading text (e.g. `design-system.md#data-tables`).
3. **Pull a superset via the primitive.** Per cited anchor, plus its plausibly-relevant **sibling** sections, invoke the retrieval primitive `${CLAUDE_PLUGIN_ROOT}/scripts/read-doc-section.{sh,ps1}` once: `${CLAUDE_PLUGIN_ROOT}/scripts/read-doc-section.<sh|ps1> <doc-path> <anchor-text>`, `<anchor-text>` the heading text **without** leading `#`s. It prints **only** that section to stdout. **Bias toward over-inclusion** — **under-retrieval is the real risk**; the implementer keeps its own `Read`/grep tools for any **additional** on-demand anchor. Never whole-file inlining; resolve **once**, and do **not** have the implementer re-read whole files.
4. **Feed the result into the dispatch brief** as **the resolved `.project/` sections**.
5. **Resolve the repo file index (once).** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/build-file-index.{sh,ps1}` **once per run**, never per-issue inside a milestone loop. Pipe the diff-scoped `{"files":[...]}` to stdin; it prints one `<path> → <purpose>` line per file. Pass it into the ### 3 brief as **the resolved file index** — #318's `build-file-index` output format, consumed, not re-derived.
6. **Resolve the prose contract (once).** Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` **once per run**, never per-issue inside a milestone loop; pass its `## GitHub-facing prose`, `## When prose is the correct form`, `## Evidence slots`, and `## The two anti-criteria` sections into the ### 3 brief as **the resolved prose contract**. It governs the implementer's Decision Log and every other GitHub-facing shape its report feeds; the agent's own `## Communication style` may specialize it, never replace it. Sub-steps 5 and 6 apply **identically under both the `light` and `heavy` build profiles** — never skipped or altered for `risk:light`.

**Degradation (no error, ever):**
- **Absent `projectDocs`** → `.project/` (step 1).
- **Absent `.project/` directory**, or no cited anchors → **no-op**: no project grounding, **no error**, skipped cleanly like `unitTestCmd`/`preflightCmd`.
- **Missing/renamed cited anchor** → the primitive **fails loud** (non-zero exit, naming the anchor + file on stderr) rather than returning silent empty grounding. Do not swallow it.
- **Absent/failed file-index resolver** (`${CLAUDE_PLUGIN_ROOT}/scripts/build-file-index.{sh,ps1}` missing, or the invocation fails / emits no usable output) → **no-op**: **no file index**, **no error** — the absent-`.project/` shape, **not** fail-loud, because nothing cites the index by name.
- **Absent `skills/output-style.md`** (missing or unreadable) → **no-op**: **no prose contract**, **no error**, leaving each agent's own `## Communication style` as its only prose rule — again absent-`.project/`, **not** fail-loud.

### Resolve cited `path (anchor)` citations (once, before dispatch)

Resolve the issue's `path (anchor)` citations (`skills/citation-format.md`) **once, here in the orchestrator**, and thread the resolved table into **every** subagent brief this run composes — no subagent re-derives it. Runs with the block above, before **### 3. Dispatch the implementer**. Paths are repo-root-relative: an issue has no directory, so there is no multi-base fallback.

1. **Extract by model judgment over the `path (anchor)` shape — never a regex.** Apply `skills/citation-format.md`'s span and position tests to the issue body + acceptance criteria. A parenthetical following a path is **not** automatically a citation; both failure modes were measured here. `docs/superpowers/plans/2026-06-01-proactive-triage.md § New agent contract — `agents/triage-reviewer.md` (architect lens)` writes `` `agents/triage-reviewer.md` (architect lens) ``: the span closes before the parenthesis, so it is prose — resolving it anyway exits 1, a **false drift report**. `docs/profile-schema.md (each built issue opens its own PR)` writes `` `skills/setup/SKILL.md` (Phase 2) ``: also prose — resolving it anyway returns `PRIMARY 54` plus `MATCH 197`, a **confident wrong answer**. A regex produces both.
2. **Resolve each citation once.** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-citation.{sh,ps1}` once per citation: `resolve-citation.<sh|ps1> <file-path> <anchor-text>`. Exit 0 prints `PRIMARY <line> <text>` then zero or more `MATCH <line> <text>`, TAB-delimited, in file order; matching is literal, case-sensitive, and line-scoped.
3. **Feed the printed rows into the ### 3 briefs** as **the resolved citations**, in the same printed-output shape as the `read-doc-section` and `build-file-index` results above. Invent no new format.

**Degradation (no error, ever):**
- **No `path (anchor)` citation on the issue** → **no-op**: no `resolve-citation` invocation and no error, exactly like the absent-`.project/` branch above.
- **A cited anchor not found**, or an unreadable file → `resolve-citation` **fails loud** (nonzero exit, naming the anchor and file on stderr, stdout empty). Surface it; never swallow it. Exit 2 is a wrong argument count or an empty anchor.

### 3. Dispatch the implementer
Dispatch the profile's `implementerAgent` (default `milestone-driver:implementer`; a project-level override uses that agent's own name as-is) via the Agent tool, orchestrating `superpowers:subagent-driven-development` + `superpowers:test-driven-development`. Brief it like a colleague walking in cold: the issue, the approved plan, the profile, the expected file scope, the resolved `.project/` sections, the resolved file index, the resolved prose contract, and the resolved citations (omit any whose resolution was a no-op); under the `light` profile the brief MUST include a `risk:light` token. Extract/rename issues touching a widely-shared symbol carry ~2–3× the call-site-migration surface and more often consume both allowed re-dispatches; the cap still applies, and an issue that cannot converge parks like any other. **The brief MUST also carry this scratch-hygiene rule:** write scratch only under a path named for that issue or that agent, never the shared scratchpad directory, and report what a probe printed rather than writing a probe file to read back later.

**The implementer is a leaf.** It returns an uncommitted diff plus its report and dispatches no subagent of its own (`docs/architecture.md` → `## Dispatch topology`). Every fan-out in this pipeline is the orchestrator's.

Verify the report honors the implementer contract: least-code / reuse-first, TDD red→green observed (or a `VERIFICATION (no test layer)` section when `unitTestCmd` is absent), verified citations where citable sources exist, a Decision Log, a `USER-FACING CHANGES` block (with `NEW_UI_ELEMENTS: yes|no`, `DESTRUCTIVE_OPS: yes|no`, and `POST_REVIEW_CHANGES: yes|no`), and **changes left uncommitted**. Then apply the declaration gates:

- **`NEW_UI_ELEMENTS: yes`** and the acceptance criteria are silent on the element's visual/UX detail → **park** with `needs design`, documenting the new elements and the direction needed.
- **`DESTRUCTIVE_OPS: yes`** and the confirmation UX is unspecified → **park** with `needs decision`, documenting the missing confirm flow.

**🔴 GATE — new dependency:** the implementer reports that the optimal solution requires a new library or toolkit → **park** with `needs decision`, naming the library and its license / OSS status. Do not ask the operator interactively.

**🔴 GATE — implementer STOPPED:** `STATUS: STOPPED` (architecture conflict, scope overrun, out-of-scope edit, or missing/ambiguous brief) → **park** describing the conflict, with `needs design` for a design/spec conflict, `needs decision` for an architecture call, or `blocked` for an otherwise-unresolvable gate. `PAUSED-FOR-APPROVAL` indicates a new-dependency case and routes to the gate above.

### 4. Verification gates

Unit, E2E, and preflight share one shape — **act → verify → retry (cap 2) → park**. `/code-review` is listed for visibility (always-on — hence no trailing `?` in its row), but its in-scope-fix vs park-trigger classification does not fit a "re-run the same check" loop: it keeps its own procedure in step 6.1 and is **not** iterated by the shared loop below.

| Gate | Applicability | `act` | Cap | Park / escape policy |
|---|---|---|---|---|
| **Unit?** | `unitTestCmd` defined | Run `unitTestCmd`. | 2 re-dispatches | Park `blocked` (or `needs design` if the plan is wrong). |
| **E2E?** | Issue touches a UI surface **and** `e2eTestCmd` defined | Bug: run a targeted subset that proves the fix. Feature: implementer authors new E2E tests covering reasonable user stories, then runs them. Both against the profile's `e2eEnv`. | 2 fix attempts | Verified by other means (a DB assertion + an attached screenshot confirming the feature works) → quarantine the flaky test, proceed, log the quarantine in the PR's Code Review section, apply `judgment call`. Not otherwise verified → park `blocked`. |
| **`/code-review`** | Unconditional — always runs, no applicability flag | See step 6.1 — its own in-scope-fix / park-trigger classification | Per build profile (step 6.1). Light: 1 cycle, a 2nd only on a Critical or Important finding. Heavy: 2 | Step 6.1's own park-trigger classification (architecture deviation, shared-contract change, new dependency, out-of-scope edit, unmetable gate, material ambiguity) |
| **Preflight?** | `preflightCmd` defined (including the `"github-ci"` sentinel) | Run the literal `preflightCmd`; or, under `"github-ci"`, discover + run each CI-derived `STEP` (see below). | 2 re-dispatches | Park `blocked` (or `needs design` if the plan is wrong). |

**Preflight's `"github-ci"` sentinel mode.** When `preflightCmd` is the reserved sentinel `"github-ci"`, do **not** run it as a shell command — read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/preflight-github-ci.md` and follow its `### Sentinel mode`. Its cap, verify step, and park/escape policy are the Preflight row's, unchanged.

**🔴 GATE — shared loop (unit, E2E, preflight only):**

1. **Act.** Run the gate's `act` per the table row. Skip the gate cleanly, no error, when its applicability condition is not met (`unitTestCmd` absent; `e2eTestCmd` absent or no UI surface touched; `preflightCmd` absent).
2. **Verify.** Invoke `superpowers:verification-before-completion` and report real output, never assertion — for all three gates.
3. **Retry.** A failing gate re-dispatches the implementer with the failure — or **parks directly** if the failure reveals the plan is wrong (see Autonomy). A preflight fix routes through step 6.1's **After a fix, before committing** branch set — `${CLAUDE_PLUGIN_ROOT}/scripts/classify-delta.{sh,ps1}` picks the branch, and `code-changed` is the one that re-runs `unitTestCmd` and `/code-review`. **Cap: at most 2 re-dispatches/fix attempts, tracked per gate — never a shared/global budget across gates.**
4. **Park.** Still failing after its 2nd retry → apply that gate's park/escape policy from the table above; the failed gate and its real output are the park comment's evidence slot. E2E's row is the one exception: verified-by-other-means quarantines and proceeds instead of parking.

**Call sites.** Unit and E2E run back-to-back immediately after the implementer dispatch (step 3). Preflight fires as the concluding action of step 6.1, after the `/code-review` loop converges and before version bump/commit — not a numbered sibling step, so the `6.1 … 6.9` ordinals and their cross-references stay fixed.

### 6. Review → integrate → close

**Coherence review (before the final `/code-review`).** An optional read-only pass over the implementer's **uncommitted** diff. Run it **only** when the `coherenceReviewAgent` — profile key, default-filled to `milestone-coherence-reviewer:coherence-reviewer` — is **both** present (dispatchable in this session) **and** configured; absent/unavailable OR explicitly unconfigured → **silently skip**: no error, no block, no park, no prompt, at most one log line. When it runs, read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/coherence-review.md` and follow its `### The pass`.

1. **Review and resolve.** Run `/code-review` (`superpowers:requesting-code-review`) on the implementer's **uncommitted** changes, then resolve findings autonomously per the Autonomy model — never pause to ask the operator about an in-scope finding:
   - **In-scope** (cosmetic, naming, style, local reversible refactor, missing/weak test): re-dispatch the implementer to fix it (the main thread cannot edit `sourceGlobs` — `force-subagent`); log it in the Decision Log. **Light fixes only a Critical or Important finding**; a Minor one is accepted, not fixed. Heavy fixes every in-scope finding. Those severities are the reviewer template's (`skills/solve-milestone/parallel-waves.md (Critical / Important / Minor)`); a finding with none — including from a reviewer scoring by confidence — counts as **Important**.
   - **Park trigger** (architecture deviation; a shared contract/interface/schema change; a new dependency; edits outside the issue's file scope; an unmetable gate; material ambiguity): **park** with `needs design`, `needs decision`, or `blocked` as appropriate. Do not commit.

   **The orchestrator runs this review itself, dispatching the reviewers directly as leaves** (`docs/architecture.md` → `## Dispatch topology`), and **never dispatches an agent that itself runs `/code-review`** — that agent's internal fan-out would sit every reviewer at depth 2 and strand the pipeline uncommitted. Reviewing several issues **concurrently** pins the shape to exactly one reviewer leaf per issue (`skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 1: concurrent stage dispatch`, step 7). The gate is unconditional: its `### 4. Verification gates` row carries no applicability flag, and `hooks/code-review-gate.sh` denies a `gh pr create` / `gh pr merge` whose PR body carries no `## Code Review` section. **The brief MUST also carry the step-3 scratch-hygiene rule.**

   **Omitting `/code-review` is not permitted.** Skipped under any constraint (time, token budget, tool error, self-review substitution) → treat the omission as a park trigger and **park** with `blocked`, giving the reason.

   **After a fix, before committing.** **No in-scope findings → commit directly.** Otherwise at least one was fixed: read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/post-fix-commit.md` and follow its `### After a fix` — the document-only and `classify-delta` branches, the `tests-green` behavior they rely on, and the per-profile review→fix cycle cap.

   **Preflight gate (concluding action of 6.1).** Once the `/code-review` loop has converged, before version bump/commit, run the preflight gate — its applicability, `act`, cap, verify step, and park/escape policy are the **Preflight** row of `### 4. Verification gates` and its shared loop.
2. Assemble the **Decision Log** from the implementer's report for the PR body, and post the citations on the issue for review (`gh issue comment <n>`). Its slots are the Decision Log entry shape in `skills/output-style.md` — choice · rationale · citation · rejected alternatives, one entry per line.
3. **Assemble the Code Review section** for the PR body. Record whether `/code-review` ran, the finding count and severity per run (the 1st, and the 2nd if a re-review occurred), and each finding's resolution (re-dispatched and resolved / accepted with rationale / triggered park). Its slots are the `## Code Review` section shape in `skills/output-style.md`; the **evidence slot** is the ref each finding named (per `skills/citation-format.md`; or, at zero findings, the effort level used). **Absence of this section on a PR is a visible defect on PR review.** Template:

   ```text
   ## Code Review

   - /code-review run: yes (omission is a park trigger — a submitted PR always carries a real review; a parked run opens no PR)
   - Findings: <count> in-scope finding(s) at <effort> effort
     - <finding> — <the ref it named, per skills/citation-format.md> → re-dispatched and resolved | accepted (rationale: <…>) | triggered park
     - … (one line per finding, or "none" when count is 0)
   - No park-triggering findings. | Park-triggering findings: <list>
   ```

   The version-bump annotation this section carries is the one step 6.4's resolved mode names.

4. **Version bump.** Read `versioning` from the profile and select the mode: **Version-free mode** (`versioning: false`), **Fail-safe degradation** (versioned mode — `versioning` `true` or absent — but `.claude-plugin/plugin.json` does **not** exist), or **Versioned mode** (`versioning` `true` or absent, and `.claude-plugin/plugin.json` exists). Read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/version-bump.md` and follow its `### Modes` for that mode's mechanics, its **Code Review** annotation, and — under Versioned mode — the milestone-run vs standalone-run split.
5. Commit on the feature branch — the `tests-green` hook (`PreToolUse` on `git commit`) re-checks the suite. Review-before-commit is enforced by audit trail (the mandatory **Code Review** section), not by a commit-time hook; `hooks/code-review-gate.sh` gates `gh pr create` / `gh pr merge`, not `git commit`.
6. Push the feature branch and open a PR with `--base <integrationBranch>` (never `protectedBranch` — enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection). Put the Decision Log and the **Code Review** section in the PR body. Add a `judgment call` label if any borderline autonomous call was made.
7. **Visual-review gate (UI issues — Layer 2).** Determine whether this issue touches a UI surface: `uiSurfaceGlobs` is configured in the profile **and** the PR's changed files match one of those globs (an implementer `NEW_UI_ELEMENTS: yes` declaration reinforces this signal).
   - **Not a UI issue** (`uiSurfaceGlobs` absent, or the diff matches no `uiSurfaceGlobs` path): no visual gate — proceed to auto-merge (step 8).
   - **UI issue:** do **not** auto-merge. The terminal state is *PR open, awaiting human visual sign-off* — read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/visual-review-hold.md` and follow its `### The hold`.
8. **Auto-merge on green (non-UI issues only):** once CI is green, run `gh pr merge --squash --delete-branch`. This replaces the human-choice step of `superpowers:finishing-a-development-branch`. **UI issues are skipped here** — they remain open per the visual-review gate (step 7) until a human merges.
9. Confirm the issue is closed (a linked PR auto-closes it; otherwise `gh issue close <n>`). **For a UI issue held at the visual-review gate, the issue stays open** with its PR awaiting human visual sign-off — it closes when the human merges the PR.

## Run-end cost record (additive, never-gating)

As the **last action before returning to the caller** at **every** terminal exit — every park (steps 0, 2, 3, 4, 6.1), the step-7 visual-review hold, and the step-9 close — emit one per-run cost record. Additive and **never-gating**: it never blocks, parks, or changes any merge/park/close outcome (`.project/design-philosophy.md#Error & failure philosophy` — optional integrations never gate; absent means skip with one log line).

1. **Aggregate.** From the `<usage>` block each Agent-dispatch tool result carried this run (implementer, `/code-review`, coherence-reviewer, any direct triage dispatch — a background dispatch's completion notification carries the same block), sum `subagent_tokens` per model tier (`opus` / `sonnet`, keyed by the dispatched agent's tier) and `duration_ms` across dispatches, plus the orchestrator's own run clock → `wallClockSeconds`.
2. **Map (auditable lower-bound).** Each tier's summed `subagent_tokens` → `inputTokens` wholly; `outputTokens` = 0; `cacheReadTokens` = `cacheWriteTokens` = 0 (the 0 sentinel per #320, never fabricated). Pass `provenanceNote: "unsplit-total-as-input"` so the writer marks the cost a lower-bound.
3. **Emit.** Pipe `{"runId":"<issue branch / run id>","wallClockSeconds":<n>,"tiers":{"<tier>":{...}},"provenanceNote":"unsplit-total-as-input"}` to `${CLAUDE_PLUGIN_ROOT}/scripts/write-cost-record.{sh,ps1}`. The single-record write to `.milestone-config/.runtime/cost-records/` is #320's.
4. **Skip cleanly.** Zero dispatches this run (e.g. a triage-blocker park before any dispatch) → skip the emission with one log line, no zero-value record. Writer script absent, or no `<usage>` figures surfaced → silent no-op, one log line. Never fails the run.

## Autonomy model (Balanced)

**Proceed autonomously (log on the PR):** implementation choices within the approved architecture; reuse of existing helpers, styles, and conventions; test design; local reversible refactors; resolving in-scope `/code-review` findings (step 6.1).

**PARK & continue (the autonomous runtime parks; it does not interactively wait):** deviation from the approved architecture; any change to a shared contract, interface, base class, or DB schema used beyond this issue; a new dependency; edits outside the issue's expected file scope; a gate that cannot be met without a design change; material ambiguity in the issue's intent; `/code-review` omission or substitution — skipping `/code-review` for any reason (time, token budget, tool error, self-review substitution) is **not** an in-scope autonomous decision; budget pressure is not a permitted exception.

The park itself is `## The procedure`'s park action, its comment opening `🔴 Parked — <reason>` (e.g. `🔴 Parked — architecture conflict: shared interface change required`) and its `in progress` label the open-WIP signal the milestone loop relies on; that loop then continues with independent, clean issues. **Only a systemic failure** (auth/`gh` failure, broken `integrationBranch`, missing tooling) halts the whole run. A standalone interactive `solve-issue` still parks durably; it may additionally narrate to the watching operator.

**Additional park triggers** (each a park, **not** silent resolution and **not** an interactive prompt):
- The recorded/locked design is internally contradictory → park with `needs design`.
- A self-noted risk about the **approved** design (e.g. "this list could get long at realistic data volumes") → park with `needs design`.

**Architecture is locked** at plan-approval time (step 2). The procedure executes approved architecture. If implementation proves the plan wrong → park, not pivot.

A change is **architecture** (→ park) if it touches any of: a component or data structure named in the approved plan; a shared contract, interface, base class, DB schema, or public API used by code outside this issue; data ownership or a cross-component boundary; a new external dependency; or any file outside this issue's stated scope. A change is an **implementation detail** (→ proceed, log in the Decision Log, step 6.2) if it is local to this issue's own files, changes no shared contract, and is reversible — a binding style, a private helper extracted in the same file, a local refactor, or test design. When the distinction is genuinely ambiguous, treat it as architecture and park.

**Audit trail (always):** a Decision Log on every PR, a **Code Review** section recording every `/code-review` run and its findings/resolutions, and a `judgment call` label on borderline calls, so post-run PR review surfaces every judgment.

## Permission pre-flight gate

**Runs once per run, before the first background dispatch. Scope: this gate applies only when background dispatch is about to be used (a leaf dispatched as `Agent(run_in_background: true)`). A fully synchronous run SKIPS it entirely — not executed at all, no gate evaluation.**

Background subagents auto-deny any tool call that would otherwise prompt (documented Claude Code behavior), and a background leaf hitting an un-allowlisted tool fails outright with no interactive recovery. Before dispatching any leaf in the background, verify the session's permission allowlist is complete.

**Allowlist source — merged settings read.** Read `permissions.allow` from all three Claude Code settings layers and union them:

| Priority | File |
|---|---|
| 1 | `~/.claude/settings.json` (user global) |
| 2 | `.claude/settings.json` (project) |
| 3 | `.claude/settings.local.json` (project local) |

Absent or unreadable layers are skipped in the union, not treated as gaps. Synchronous fallback fires only when (1) the union fails to cover the required tool surface, or (2) no layer is readable.

With that union in hand, read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/permission-preflight.md` and follow its `### Tool surface and response`.

## Milestone granularity (`integrationGranularity: "milestone"`)

**Resolved from the profile at step 1, not from an invocation token.** When `integrationGranularity` resolves to `"milestone"` (`docs/profile-schema.md (How should built issues integrate?)`), read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/milestone-clauses.md` and apply its `### Clauses` — the per-step deltas that mode makes to the pipeline above — plus `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/milestone-granularity.md` for the branch model, the integration-commit trailer format, and the resume query. **When the key is absent or resolves to `"issue"` or `"wave"`, neither read happens, no clause applies, and the entire pipeline runs byte-unchanged.**

## Async mode (`--async`): retired

**`--async` is an interpreted token, not a parsed CLI flag.** Claude Code does no argument parsing — `$ARGUMENTS` is string-substituted — so the token is **recognized** by string presence in the invocation text. It is now **inert**: the pipeline above runs on the caller's own main line. A habit-typed or stale `--async` is a no-op, never an error (the same treatment a habit-typed `--parallel` gets in `solve-milestone`). **No run reads `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/async-mode.md`** — not with an `--async` token, not without one; this skill's size closure excludes it on exactly that ground (`scripts/check-size-budgets.sh (retired, inert — read on no run)`). It is a see-also for a human: the retirement record, its dispatch-topology reason, and what replaces it.

## Parent-issue detection (`md-epic`)

**Runs before anything else** — before `## Before starting` step 1 (profile read) and before `### 0. Triage`. Read `#n`'s labels: `gh issue view <n> --json labels`, exact match against `.labels[].name` for the literal `md-epic`. **When `md-epic` is absent, none of this section applies and the entire pipeline runs byte-unchanged, starting at `## Before starting` step 1.** When present, read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/md-epic-fanout.md` and follow its `### Parent path` — it replaces the rest of this skill's pipeline for this invocation.

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

<!-- Structural mirror of solve-milestone Template 2; keep column schema (Issue/Result/Gates/PR/Note) in sync. -->

One row per issue; emit only the row matching the actual outcome and suppress the others.

```text
🏁 Issue #[n] · [T] min

| Issue | Result     | Gates | PR | Note                    |
|-------|------------|-------|----|-------------------------|
| #201  | ✅ merged  | 🔍✓(0 findings)  | #301 | —    |
| #203  | 👁️ open   | 🔍✓(1 fixed)     | #303 | awaiting visual review  |
| #202  | ⏸️ parked  | —                | [#pr | —] | [park label]      |
| #204  | ✅ committed | 🔍✓(0 findings) | —    | committed on its branch |
```
PR cell: show the PR number if the issue has one, else —. Gates legend: 🧪 = unit suite · 🔍 = code review · 🌐 = E2E

## Output style

Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` — this plugin's output contract. Its `## Terminal output` section governs what this skill prints (including the `## Output spec` template rule); its `## GitHub-facing prose`, `## When prose is the correct form`, and `## Evidence slots` sections govern every issue comment, PR comment, Decision Log, and PR body this skill writes. The two surfaces are distinct — terminal rules never reach GitHub.

## Non-negotiables
- Gitflow. PRs target `integrationBranch` only — never `protectedBranch`.
- Honor the profile's `nonNegotiables` (framework versions, platform targets).
- The main thread never authors application or test code — always dispatch the implementer.
