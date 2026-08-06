---
name: solve-issue
description: This skill should be used when the user invokes "/milestone-driver:solve-issue <n>", or asks to "solve issue <n>", "fix issue <n>", or "drive issue <n>" through the milestone-driver gated procedure. Runs one GitHub issue end-to-end as an orchestrator — triage, root-cause-or-park, dispatch the implementer subagent (TDD, citations), unit + E2E gates, code review, PR to the integration branch, auto-merge on CI green for non-UI issues (UI issues are held open for human visual sign-off), then close — never authoring application or test code on the main thread.
---

# solve-issue — gated per-issue procedure

Run exactly one GitHub issue through a fixed, gated pipeline. The main thread acts only as an **orchestrator**: read, decide, dispatch, review, integrate. It **never authors application or test code itself** — the `force-subagent` hook enforces this mechanically.

Orchestrate the `superpowers:*` skills for the inner loop rather than reimplementing their discipline. **Before anything else, check `#n`'s labels for `md-epic`: a parent issue takes `### Parent path` (see `skills/solve-issue/md-epic-fanout.md`) instead of the pipeline below.**

**Contents.** Before starting · The procedure (0 Triage · 1 Read the issue · 2 Evaluate the codebase for root cause · Build profile resolution · Resolve cited project-docs sections · Resolve cited `path (anchor)` citations · 3 Dispatch the implementer · 4 Verification gates · 6 Review → integrate → close) · Run-end cost record · Autonomy model · Permission pre-flight gate · Milestone granularity · Async mode · Parent-issue detection · Output spec (Template 1 · Template 2) · Output style · Non-negotiables

## Before starting

1. Read the profile (see the plugin's `docs/profile-schema.md`).

   | Profile-resolution decision point | Behavior |
   |---|---|
   | Resolution order (transitional) | Read `<repo>/.milestone-config/driver.json` first; if absent, fall back to the legacy root `<repo>/milestone-driver.json`. This transitional READ covers the gap before the migration move lands. |
   | Both files exist | `.milestone-config/driver.json` wins for the read. |
   | Migration (`git mv`) | Deferred to step 3.5, so the `git mv` rides the feature branch and does **not** trip the clean-tree precondition (step 2). Do **not** perform the move here. |
   | Neither file exists, or `integrationBranch` / `protectedBranch` / `sourceGlobs` missing | Invoke `milestone-driver:setup` to bootstrap it, then continue — do **not** fail. |
   | `implementerAgent` | Defaults to `milestone-driver:implementer` when omitted. |
   | Optional keys — `unitTestCmd`, `e2eTestCmd`, `e2eEnv`, `preflightCmd`, `domainSkills`, `nonNegotiables`, `projectDocs` | Optional; `projectDocs` defaults to `.project/` when absent. Their steps are skipped cleanly when absent. |

   1.1. **Self-heal the scratch-ignore (always, before any `.milestone-config/` scratch write).** Per-clone scratch must be git-invisible from the first write with zero user setup, but `.milestone-config/` also holds **tracked** config (`driver.json`, `feeder.json`), so the directory itself must not be blanket-ignored. Ensure a **committed** `.milestone-config/.gitignore` exists that ignores only the scratch names below. Absent → create it (`mkdir -p .milestone-config`, then write the block). Present → do nothing. It rides the feature branch and is committed with the issue work, self-healing consumer repos that predate this seam. (`driver.json` / `feeder.json` are intentionally NOT listed, so they stay tracked — never add a blanket `*` or `/` rule.)

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

   1.1.1. **One-time notices.** Immediately after reading the profile: read `${CLAUDE_PLUGIN_ROOT}/skills/notices.md` and, in file order, evaluate each section whose `Skills` field includes `solve-issue` (today: preflight, visualcapture, code-review-gate, aiprefilter, cost-record, uisurfaceglobs) — for each, apply the `Trigger` → `Text` → `Marker` → `Legacy fallback` mechanics recorded in that section. `solve-issue` never evaluates a section scoped only to `solve-milestone` (today: trello, parallel-default).
2. **Confirm the working tree is clean** (cold-start precondition) **and the local `integrationBranch` is current** (`git fetch`, fast-forward). One exception, never stashed or discarded: if step 3's probe finds an existing `issue/<n>-*` branch (carrying committed or uncommitted prior work), skip the clean-tree enforcement and go straight to step 3. Any other dirty state is a cold-start violation. Under `"milestone"` granularity the branch this issue is measured against is the **milestone branch** (`skills/solve-milestone/milestone-granularity.md (Milestone branch)`), which is local and never pushed: there is nothing to fetch or fast-forward, so confirm that branch exists and is the cut point instead of fast-forwarding `integrationBranch`.
3. **Branch-state probe (resume an interrupted run).** Run `git fetch` first, then determine prior progress from git + gh before cutting anything. Evaluate in this order:
   - **(a) A PR exists for `issue/<n>-*`** (client-side filter: `gh pr list --state all --limit 200 --json number,headRefName,state,url --jq '.[] | select(.headRefName | startswith("issue/<n>-"))'`):
     - **merged** → the work is already integrated; do **not** re-implement or open a new PR; **resume at step 9** (confirm the issue is closed / close it). A merged PR means the branch was deleted; this state follows an interrupt between merge and close.
     - **open** → check out that branch; **resume at the visual-review gate / auto-merge (steps 7–8)** — do **not** re-implement and do **not** open a second PR. The open PR is the authoritative "work is built and submitted" signal.
   - **(b) No PR; branch `issue/<n>-*` exists (local or remote) with commits ahead of `integrationBranch`**: check both local and remote refs (`git branch -a --list "*issue/<n>-*"` or `git ls-remote --heads origin "issue/<n>-*"`); track the remote branch if no local branch exists (`git checkout --track origin/issue/<n>-<slug>`), and compute commits ahead against the remote-tracking ref in that case. **Skip re-implementation.** **Re-verify first** — if `unitTestCmd` is defined, run it and confirm green; if absent (no test layer), confirm the branch diff is non-empty and based on `integrationBranch` (`git diff <integrationBranch>...HEAD --stat`). Then **resume at step 6.1 (`/code-review`)** and follow step 6's normal flow from there (commit only if there are uncommitted changes, push, open PR). A red re-verify, or a diff that is empty / clearly on the wrong base, falls into the normal step-4 red-suite path (re-dispatch the implementer, the "at most 2" cap; park if non-converging). Under `"milestone"` granularity the commits-ahead computation and that `git diff` re-verify both take the **milestone branch** in place of `integrationBranch`, and the resumed step-6 flow commits without pushing and opens no PR (step 6.6).
   - **(c) No PR; no commits ahead; but the issue branch `issue/<n>-*` is checked out with uncommitted changes** (the normal implementer contract): do **not** clobber; re-verify (same rule as (b)); **resume at step 6.1 (`/code-review`)** and follow step 6's normal flow. Best-effort: it only recovers when the working tree is preserved in-place (in-place re-dispatch); a fresh clone has no uncommitted changes and falls to (d).
   - **(d) Otherwise (no branch, no PR, clean tree):** cut a fresh feature branch from `integrationBranch` (e.g. `issue/<n>-<slug>`) — cold start, dispatch the implementer (### 3. Dispatch the implementer). Under `"milestone"` granularity the cut point is the **milestone branch**, never `integrationBranch` (`skills/solve-milestone/milestone-granularity.md (Issue branch)`).

   This derives resume-state entirely from git + gh; there is no checkpoint file to maintain. **Never skip `/code-review`** on a resumed path; if it triggers a fix, step 6's re-review and push cycle applies normally. Under `"milestone"` granularity nothing is pushed before milestone end, so path (a)'s `gh pr list` and path (b)'s `git ls-remote` half finding **no match is the normal state**, never read as "nothing built"; path (b)'s local-ref half (`git branch -a --list "*issue/<n>-*"`) still matches, because the issue branch is local and carries local commits. Evaluate the trailer query **between (a) and (b)**: `git log <milestone-branch> --grep='^Issue: #<n>$'` (`skills/solve-milestone/milestone-granularity.md § Resume and buildability from the trailer`). A hit means the issue is **already integrated**: return "already integrated": no re-implementing, no re-verifying, no re-opening. No hit plus a local branch with commits ahead of the milestone branch is path (b); no hit and no branch is cold-start path (d), the normal first-pass state and never an error.

   **3.5. Profile migration (run once, on the feature branch).** With the clean-tree check (step 2) passed and the feature branch established (step 3), run the idempotent migration preamble: if `<repo>/.milestone-config/driver.json` exists, use it. Else if a legacy root `<repo>/milestone-driver.json` exists, migrate it first — `mkdir -p .milestone-config`; `git mv <repo>/milestone-driver.json <repo>/.milestone-config/driver.json` (when git-tracked, else plain `mv`) — then continue. Else (neither) it is a new project (setup creates the canonical file; the other skills auto-invoke setup; hooks fail-open). Idempotent: once `.milestone-config/driver.json` exists this is a no-op. When both files exist, `.milestone-config/driver.json` wins — no move, no overwrite, no deletion of the leftover root file. The move rides the issue's PR — no separate commit; under `"milestone"` granularity no per-issue PR is opened, so it rides the issue's own step-6.5 commit onto the milestone branch, #368.
4. Create one TodoWrite item per numbered step below. Work them in order — do not skip or reorder.

## The procedure

### 0. Triage

**Two branches — always run one:**

**Branch A — Explicit-supply path (reuse).** Fires **iff the caller explicitly supplied this issue's triage result at invocation time** — as an inline restatement by the orchestrator when invoking step 0, carrying named fields with ACTUAL VALUES (e.g. "step-0 result for #N: `issueStates["N"] = { blockers: false, label: null, advisories: [...], risk: "light" }`, `edges["N"] = [...]`"). A restatement whose fields are absent, label-only, or partial is not an explicit supply and falls to Branch B. Use the supplied result directly — do **NOT** re-invoke `milestone-driver:triage <n>` — and proceed to the **Blocker check** below. It IS this run's verified Phase 0 triage result, not a skip.

**Branch B — Standalone / fallback path.** When no triage result was explicitly supplied at invocation time — anything absent, partial, or merely recalled from earlier context — invoke `milestone-driver:triage <n>` (single-issue mode) and use the returned result for the **Blocker check** below. Branch B is the safe default, never an error.

**Blocker check (both branches).** If the result indicates a Blocker for this issue → **park**: triage has already posted the `🔴 Triage` comment on the issue; VERIFY the comment exists (`gh issue view <n> --comments`) and post it if missing (idempotent); apply the recommended label from `issueStates["<n>"].label` — `needs design` for a design gap, `needs decision` for a non-design decision — via the apply-time helper (idempotent `gh label create --force` then `gh issue edit --add-label`); leave the issue open; do **not** proceed to step 1. Return to the caller. All-clear or Advisory-only → proceed to step 1.

### 1. Read the issue
Run `gh issue view <n>` with comments. Restate the acceptance criteria plainly before continuing.

### 2. Evaluate the codebase for root cause
Invoke `superpowers:systematic-debugging`. Read the implicated code — the file(s) plus direct callers and callees.

**🔴 GATE — root cause:** If the root cause cannot be identified from the codebase, **park** the issue: post a comment in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` and describing the blocker (`gh issue comment <n>`), apply the `blocked` label (or `needs design` if the gap is a design gap), apply `in progress` if the branch has commits, leave the branch open with any work done, and return. Do not proceed to implementation.

When found, write an **architecture-aware plan** with full awareness of the codebase and its conventions. This plan is the **locked** architecture for this issue.

**`design-cleared` means a decision was recorded**, not that it is correct or buildable. The orchestrator may still **park** a `design-cleared` issue with `needs design` if the recorded/locked design is internally contradictory or will produce a poor result.

### Build profile resolution (resolved after step 0, governs steps 3–6)

Read `issueStates["<n>"].risk` from the step-0 triage result (held Phase 0 result in a milestone run, fresh single-issue return in a standalone run): `"light"` or `"heavy"`, defaulting to `"heavy"` when absent or inconclusive. This single read governs the whole build profile for this issue:

| Profile | Implementer brief | E2E gate (step 4, E2E row) | `/code-review` effort (step 6.1) |
|---|---|---|---|
| **Light** | Include a `risk:light` token in the brief | Skip when the issue touches no UI surface | `low` or `medium` |
| **Heavy** (default) | Standard TDD brief (no `risk:light`) | Per step 4's E2E row (UI surface + e2eTestCmd) | `high` or `xhigh` |

The safety floor is **unconditional for both profiles**: triage (step 0), the `tests-green` hook, and `force-subagent` always run regardless of profile. Light relaxes ceremony only — it never skips verification. (A parent issue carrying `md-epic` never enters this pipeline — see `skills/solve-issue/md-epic-fanout.md`.)

### Resolve cited project-docs sections (once, before dispatch)

Resolve the issue's cited `.project/` sections **once, here in the orchestrator** — so the implementer (and, when wired, the reviewers) receive the grounding text in their brief rather than each subagent re-reading whole docs. This block runs after the build profile is resolved and **before ### 3. Dispatch the implementer**. It only adds an input to the dispatch brief composed in step 3.

1. **Source the docs root.** Use `projectDocs` already resolved at step 1 (defaults to `.project/` when the key is absent). Do **not** re-resolve the profile here.
2. **Parse the cited anchors.** From the issue body + the acceptance criteria (read at step 1), collect the `.project/<doc>#<section>` anchors the issue cites — `<doc>` is the path under the docs root, `<section>` is the heading text (an anchor like `design-system.md#data-tables`).
3. **Pull a superset via the primitive.** For each cited anchor — plus its plausibly-relevant **sibling** sections — invoke the retrieval primitive `${CLAUDE_PLUGIN_ROOT}/scripts/read-doc-section.{sh,ps1}` (pwsh on Windows, bash elsewhere — the host selection every `${CLAUDE_PLUGIN_ROOT}/scripts/*.{sh,ps1}` invocation in this skill uses) once per section: `${CLAUDE_PLUGIN_ROOT}/scripts/read-doc-section.<sh|ps1> <doc-path> <anchor-text>`, where `<doc-path>` is the doc under the docs root and `<anchor-text>` is the heading text **without** leading `#`s. It prints **only** that section to stdout. **Bias toward over-inclusion** — **under-retrieval is the real risk**. The implementer keeps its own `Read`/grep tools for any **additional** on-demand anchor, so over-inclusion never under-grounds the brief; it must still never degrade into whole-file inlining. Resolve **once**; do **not** have the implementer re-read whole files.
4. **Feed the result into the dispatch brief.** Collect the printed sections and pass them into the implementer brief composed in ### 3 as **the resolved `.project/` sections**.
5. **Resolve the repo file index (once).** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/build-file-index.{sh,ps1}` **once per run** — never re-invoked per-issue inside a milestone loop. Pipe the diff-scoped `{"files":[...]}` to its stdin; it prints one `<path> → <purpose>` line per file. Pass the printed index into the implementer brief composed in ### 3 as **the resolved file index**, alongside the resolved `.project/` sections. The shape is #318's `build-file-index` output format — consume it, do not re-derive it.
6. **Resolve the prose contract (once).** Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` **once per run** — never re-read per-issue inside a milestone loop — and pass its `## GitHub-facing prose`, `## When prose is the correct form`, `## Evidence slots`, and `## The two anti-criteria` sections into the implementer brief composed in ### 3 as **the resolved prose contract**, alongside the resolved `.project/` sections and the resolved file index. It governs the implementer's Decision Log and every other GitHub-facing shape its report feeds; the agent's own `## Communication style` may specialize it but never replace it. Sub-steps 5 and 6 both apply **identically under both the `light` and `heavy` build profiles** — never skipped or altered for `risk:light` issues.

**Degradation (no error, ever):**
- **Absent `projectDocs`** → defaults to `.project/` (resolved at step 1).
- **Absent `.project/` directory** (or no cited anchors) → this block is a **no-op**: dispatch proceeds with no project grounding and **no error** (skipped cleanly when absent, exactly like `unitTestCmd`/`preflightCmd`).
- **Missing/renamed cited anchor** → the primitive **fails loud** (non-zero exit, naming the anchor + file on stderr) so a drifted heading surfaces rather than returning silent empty grounding. Treat the loud failure as a signal that a cited anchor drifted — do not swallow it.
- **Absent/failed file-index resolver** (`${CLAUDE_PLUGIN_ROOT}/scripts/build-file-index.{sh,ps1}` missing, or the invocation fails / emits no usable output) → **no-op**: dispatch proceeds with **no file index** in the brief and **no error** — the absent-`.project/` shape, **not** the fail-loud missing-anchor one, because nothing cites the index by name.
- **Absent `skills/output-style.md`** (missing or unreadable) → **no-op**: dispatch proceeds with **no prose contract** in the brief and **no error**, leaving each agent's own `## Communication style` as its only prose rule — again the absent-`.project/` shape, **not** fail-loud.

### Resolve cited `path (anchor)` citations (once, before dispatch)

Resolve the issue's `path (anchor)` citations (`skills/citation-format.md`) **once, here in the orchestrator**, and thread the resolved table into **every** subagent brief this run composes — no subagent re-derives it. Runs with the block above, before **### 3. Dispatch the implementer**. Paths are repo-root-relative: an issue has no directory, so there is no multi-base fallback.

1. **Extract by model judgment over the `path (anchor)` shape — never a regex.** Apply `skills/citation-format.md`'s span and position tests to the issue body + acceptance criteria. A parenthetical following a path is **not** automatically a citation; both failure modes were measured here. `docs/superpowers/plans/2026-06-01-proactive-triage.md § New agent contract — `agents/triage-reviewer.md` (architect lens)` writes `` `agents/triage-reviewer.md` (architect lens) ``: the span closes before the parenthesis, so it is prose — resolving it anyway exits 1, a **false drift report**. `docs/profile-schema.md (each built issue opens its own PR)` writes `` `skills/setup/SKILL.md` (Phase 2) ``: also prose — resolving it anyway returns `PRIMARY 54` plus `MATCH 197`, a **confident wrong answer**. A regex produces both.
2. **Resolve each citation once.** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-citation.{sh,ps1}` (pwsh on Windows, bash elsewhere) once per citation: `resolve-citation.<sh|ps1> <file-path> <anchor-text>`. Exit 0 prints `PRIMARY <line> <text>` then zero or more `MATCH <line> <text>`, TAB-delimited, in file order; matching is literal, case-sensitive, and line-scoped.
3. **Feed the result into the dispatch brief.** Pass the printed rows into the briefs composed in ### 3 as **the resolved citations**, in the same printed-output shape as the `read-doc-section` and `build-file-index` results above. Invent no new format.

**Degradation (no error, ever):**
- **No `path (anchor)` citation on the issue** → **no-op**: no `resolve-citation` invocation and no error, exactly like the absent-`.project/` branch above.
- **A cited anchor not found**, or an unreadable file → `resolve-citation` **fails loud** (nonzero exit, naming the anchor and file on stderr, stdout empty), like the missing-anchor branch above. Surface the failure; never swallow it. Exit 2 is a wrong argument count or an empty anchor.

### 3. Dispatch the implementer
Dispatch the profile's `implementerAgent` (default `milestone-driver:implementer`; a project-level override in the profile uses that agent's own name as-is) via the Agent tool, orchestrating `superpowers:subagent-driven-development` + `superpowers:test-driven-development`. Brief it like a colleague walking in cold: the issue, the approved plan, the profile, the expected file scope, the resolved `.project/` sections, the resolved file index, the resolved prose contract, and the resolved citations (all four from the two resolve-once blocks above — omit any whose resolution was a no-op); when the build profile resolved above is `light`, the brief MUST include a `risk:light` token so the implementer applies the right verification mode. Note: extract/rename issues touching a widely-shared symbol or component carry ~2–3× the call-site-migration surface of a typical feature issue, so they more often consume both allowed re-dispatches — the "at most 2" cap still applies, and an issue that cannot converge within it parks like any other (orchestrator judgment, not a profile key). **The brief MUST also carry this scratch-hygiene rule:** write scratch only under a path named for that issue or that agent, never the shared scratchpad directory, and report what a probe printed rather than writing a probe file to read back later.

**The implementer is a leaf.** It does the work itself and returns an uncommitted diff plus its report; it dispatches no subagent of its own (`docs/architecture.md` → `## Dispatch topology`). Every fan-out in this pipeline is the orchestrator's.

Verify the returned report honors the implementer contract: least-code / reuse-first, TDD red→green observed (or a `VERIFICATION (no test layer)` section when `unitTestCmd` is absent), verified citations where citable sources exist, a Decision Log, a `USER-FACING CHANGES` block (with `NEW_UI_ELEMENTS: yes|no`, `DESTRUCTIVE_OPS: yes|no`, and `POST_REVIEW_CHANGES: yes|no`), and **changes left uncommitted**. Then apply the declaration gates:

- **`NEW_UI_ELEMENTS: yes`** and the issue's acceptance criteria are silent on the element's visual/UX detail → **park** with `needs design`: post a comment in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` documenting the new elements and what direction is needed (`gh issue comment <n>`), preserve the branch, apply the label (+ `in progress` if the branch has commits), and return.
- **`DESTRUCTIVE_OPS: yes`** and the confirmation UX is unspecified → **park** with `needs decision`: post a comment in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` documenting the missing confirm flow on the issue (`gh issue comment <n>`), preserve the branch, apply the label (+ `in progress` if the branch has commits), and return.

**🔴 GATE — new dependency:** If the implementer reports that the optimal solution requires a new library or toolkit, **park** with `needs decision`: post a comment in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` followed by the library name and its license / OSS status on the issue (`gh issue comment <n>`), preserve the branch, apply the `needs decision` label (+ `in progress` if the branch has commits), and return. Do not ask the operator interactively.

**🔴 GATE — implementer STOPPED:** If the implementer returns `STATUS: STOPPED` (architecture conflict, scope overrun, out-of-scope edit, or missing/ambiguous brief), **park** the issue: post a comment in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` and describing the conflict (`gh issue comment <n>`), apply the appropriate label (`needs design` for a design/spec conflict, `needs decision` for an architecture call, `blocked` for an otherwise-unresolvable gate) + `in progress` if the branch has commits, preserve the branch, and return. `PAUSED-FOR-APPROVAL` from the implementer indicates a new-dependency case and routes to the new-dependency gate above.

### 4. Verification gates

Unit, E2E, and preflight share one shape — **act → verify → retry (cap 2) → park**. `/code-review` is listed for visibility (always-on — hence no trailing `?` in its row), but its in-scope-fix vs park-trigger classification does not fit a "re-run the same check" loop, so it keeps its own procedure in step 6.1 and is **not** iterated by the shared loop below.

| Gate | Applicability | `act` | Cap | Park / escape policy |
|---|---|---|---|---|
| **Unit?** | `unitTestCmd` defined | Run `unitTestCmd`. | 2 re-dispatches | Park `blocked` (or `needs design` if the plan is wrong). |
| **E2E?** | Issue touches a UI surface **and** `e2eTestCmd` defined | Bug: run a targeted subset that proves the fix. Feature: implementer authors new E2E tests covering reasonable user stories, then runs them. Both against the profile's `e2eEnv`. | 2 fix attempts | Verified by other means (a DB assertion + an attached screenshot confirming the feature works) → quarantine the flaky test, proceed, log the quarantine in the PR's Code Review section, apply `judgment call`. Under `"milestone"` granularity that log lands in the step-6.5 commit's `Code-Review:` block and the label on the **issue** (#368; steps 6.3, 6.6). Not otherwise verified → park `blocked`. |
| **`/code-review`** | Unconditional — always runs, no applicability flag | See step 6.1 — its own in-scope-fix / park-trigger classification | 2 review→fix cycles (step 6.1's own cap) | Step 6.1's own park-trigger classification (architecture deviation, shared-contract change, new dependency, out-of-scope edit, unmetable gate, material ambiguity) |
| **Preflight?** | `preflightCmd` defined (including the `"github-ci"` sentinel) | Run the literal `preflightCmd`; or, under `"github-ci"`, discover + run each CI-derived `STEP` (see below). | 2 re-dispatches | Park `blocked` (or `needs design` if the plan is wrong). |

**Preflight's `"github-ci"` sentinel mode.** When `preflightCmd` is the reserved sentinel `"github-ci"`, do not run it as a shell command. Instead invoke the discovery component `${CLAUDE_PLUGIN_ROOT}/scripts/ci-preflight-steps.{sh,ps1}` (pwsh on Windows, bash elsewhere) in the repo root — pass the optional `ciWorkflow` profile value as its 2nd argument to narrow to one workflow. It reads the local `.github/workflows/*.yml` (never the network) and emits an ordered, TAB-separated record stream: `STEP <wf> <job> <coe> <wdir> <cmd>` (a runnable step; `coe=1` = `continue-on-error`; `wdir` = `working-directory`, `""` = repo root; `cmd` has newlines encoded as `\n`), `SKIP`/`CHECK`/`WARN` lines, and a final `SUMMARY mirrored=N skipped=M`. Run each `STEP` in declaration order, one at a time:
- **Surface the coverage summary loudly** in the run output — the `SUMMARY`, the mirrored `CHECK` names, and the `SKIP` reasons ("mirrored N checks, skipped M"). Any `WARN` line — especially the **silent-under-run** warning (a PR-gating workflow that produced zero runnable steps because its real checks live behind a `uses:` reusable/composite workflow) — must be surfaced as a **visible warning, not treated as a clean pass**.
- **For each `STEP`:** apply the **tool-presence guard** — first **decode the `cmd`'s `\n`-encoded newlines back to real newlines** (the record stores a multi-line `run:` with literal two-character `\n` separators), **then** take the leading tool as the first token of the first command in the decoded `run:` script (split on newline / `&&` / `;` / `|`; best-effort); if that tool is absent from `PATH`, **skip + log** "couldn't run locally (`<tool>` absent)". Otherwise run the command in `wdir` (repo root when empty). A non-zero exit is a **real failure** and feeds the shared loop below — **except** a `coe=1` (`continue-on-error`) step, whose failure is logged but **never** counts as a real failure (never triggers a park).
- A parse error or no workflows → the component emits an empty `STEP` list with a `WARN` reason; the gate then **no-ops cleanly** (same as an absent `preflightCmd`), never a hard crash.

**🔴 GATE — shared loop (unit, E2E, preflight only):**

1. **Act.** Run the gate's `act` per the table row. Skip the gate cleanly, no error, when its applicability condition is not met (`unitTestCmd` absent; `e2eTestCmd` absent or no UI surface touched; `preflightCmd` absent).
2. **Verify.** Invoke `superpowers:verification-before-completion` and report real output, never assertion — for all three gates.
3. **Retry.** A failing gate re-dispatches the implementer with the failure — or **parks directly** if the failure reveals the plan is wrong (see Autonomy). A source-changing preflight fix also re-runs `unitTestCmd` if defined and re-runs `/code-review` (honoring step 6.1's "fresh review is the last action before commit" rule). **Cap: at most 2 re-dispatches/fix attempts, tracked per gate — never a shared/global budget across gates.**
4. **Park.** If the gate is still failing after its 2nd retry, apply that gate's park/escape policy from the table above: comment on the issue in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` — the failed gate and its real output are the evidence slot — apply `blocked` (or `needs design` if the plan is wrong) (+ `in progress` if the branch has commits), preserve the branch, and return. E2E's table row is the one exception to this park shape: verified-by-other-means quarantines and proceeds instead of parking.

**Call sites.** Unit and E2E run back-to-back immediately after the implementer dispatch (step 3). Preflight fires as the concluding action of step 6.1, after the `/code-review` loop converges and before version bump/commit — that positioning, not a numbered sibling step, is what keeps the `6.1 … 6.9` ordinals and their cross-references fixed.

### 6. Review → integrate → close

**Coherence review (before the final `/code-review`).** Optionally run a read-only post-build coherence pass over the implementer's **uncommitted** diff.

- **Resolve the agent.** The coherence agent is the profile key `coherenceReviewAgent`, **default-filled** to `milestone-coherence-reviewer:coherence-reviewer` (same default-fill pattern as `implementerAgent` / `triageAgent` / `designReviewAgent`, `docs/profile-schema.md (Keep it minimal and)`).
- **Gate — present AND configured.** Run the pass **only** when the coherence-reviewer agent is **both** present (dispatchable in this session) **and** configured (the `coherenceReviewAgent` key resolves, or its bundled default applies). If the agent is **absent/unavailable** OR explicitly unconfigured → **silently skip**: no error, no block, no park, no prompt — at most a single log line. This is the absent-means-skip convention used by `unitTestCmd` (`docs/profile-schema.md (What command runs the unit tests? Absent →)`), `preflightCmd` (`docs/profile-schema.md (Either a single literal command)`), `integrations.trello` (`docs/profile-schema.md (Trello board integration node. Presence)`), and `visualCapture` (`docs/profile-schema.md (Visual-capture render seam)`).
- **When it runs.** Dispatch the coherence agent **read-only** against the implementer's uncommitted diff. It returns findings and, per its own standalone contract, **routes its own drift** (trivial → small-issue note; small/medium → current-milestone issues; large → a feeder brief); the driver wires only the dispatch and re-implements no heal routing. **The brief MUST also carry the step-3 scratch-hygiene rule.** The large-drift → milestone-feeder → auto-run-driver auto-handoff is deferred to #232 and is **not** part of this step.
- **Never-gating.** The coherence pass **never** blocks, **never** parks, and **never** changes the merge decision — the build proceeds to step-6.1 `/code-review` regardless of what coherence found (`.project/design-philosophy.md#Error & failure philosophy` — optional integrations never gate a run; absent means skip; `README.md` coherence-reviewer pointer — post-build, no edits).

1. **Review and resolve.** Run `/code-review` (`superpowers:requesting-code-review`) on the implementer's **uncommitted** changes, then resolve findings autonomously per the Autonomy model — do **not** pause to ask the operator about an in-scope finding:
   - **In-scope** (cosmetic, naming, style, local reversible refactor, missing/weak test): re-dispatch the implementer to fix it (the main thread cannot edit `sourceGlobs` — `force-subagent`); log it in the Decision Log.
   - **Park trigger** (architecture deviation; a shared contract/interface/schema change; a new dependency; edits outside the issue's file scope; an unmetable gate; material ambiguity): **park** the issue — comment in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` on the issue, apply the appropriate label (`needs design`, `needs decision`, or `blocked`) (+ `in progress` if the branch has commits), preserve the branch, and return. Do not commit.

   **The orchestrator runs this review itself, dispatching the reviewers directly as leaves** (`docs/architecture.md` → `## Dispatch topology`). The installed `/code-review` command fans out internally, so a review launched from inside a dispatched agent sits every reviewer at depth 2, where a completion notification never arrives and the pipeline stops mid-cycle with the work uncommitted. On the orchestrator's own main line that fan-out lands at depth 1; **the orchestrator never dispatches an agent that itself runs `/code-review`**. Reviewing several issues **concurrently** pins the shape to exactly one reviewer leaf per issue (`skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 1: concurrent stage dispatch`, step 7), never a per-issue agent that runs the command. The gate is unconditional — its row in `### 4. Verification gates` carries no applicability flag, and `hooks/code-review-gate.sh` denies a `gh pr create` / `gh pr merge` whose PR body carries no `## Code Review` section. **The brief MUST also carry the step-3 scratch-hygiene rule.**

   **Omitting `/code-review` is not permitted.** If skipped under any constraint (time, token budget, tool error, self-review substitution), treat the omission as a park trigger — comment the reason on the issue, preserve the branch, apply `blocked` (+ `in progress` if the branch has commits), and return.

   **After a fix, before committing:**
   - **Code changed** (any `sourceGlobs` file): re-run `unitTestCmd` if defined (skip if absent), then re-run `/code-review` — the fresh review must be the **last action before commit**. The procedure does not loop past a second clean review. `POST_REVIEW_CHANGES: yes` is the machine-checkable signal that the re-review is due; any `sourceGlobs` change independently triggers it as a backstop, so a re-dispatch that changed source is always re-reviewed even if the field is `no`.
   - **Document-only** (`*.md`, READMEs, doc/comment text — nothing under `sourceGlobs`): commit directly; no re-run needed (`tests-green` no-ops on doc-only, and `/code-review` need not be re-run for a doc-only fix).
   - **No in-scope findings:** commit directly.

   **Cap: at most 2 review→fix cycles.** If `/code-review` still returns in-scope findings after the 2nd fix, **park** the issue: comment in the park-comment shape (`skills/output-style.md`) opening with `🔴 Parked — ` and the current diff state on the issue, apply `needs design` or `blocked` as appropriate (+ `in progress` if the branch has commits), preserve the branch, and return. A review that won't converge usually means the plan is wrong.

   **Preflight gate (concluding action of 6.1).** Once the `/code-review` loop above has converged, before version bump/commit, run the preflight gate — its applicability, `act` (including the `"github-ci"` sentinel discovery mode), cap, verify step, and park/escape policy are the **Preflight** row of `### 4. Verification gates` and its shared loop.
2. Assemble the **Decision Log** from the implementer's report for the PR body, and post the citations on the issue for review (`gh issue comment <n>`). Its slots are the Decision Log entry shape in `skills/output-style.md` — choice · rationale · citation · rejected alternatives, one entry per line. Under `"milestone"` granularity there is no per-issue PR body: the Decision Log is written into the step-6.5 commit in the trailer shape `skills/solve-milestone/milestone-granularity.md § The integration commit` defines (the durable record the fold and the milestone PR read, #371), and the citation post to the issue (`gh issue comment <n>`) is unchanged.
3. **Assemble the Code Review section** for the PR body. Record: whether `/code-review` ran, the finding count and severity per run (the 1st, and the 2nd if a re-review occurred), and each finding's resolution (re-dispatched and resolved / accepted with rationale / triggered park). Its slots are the `## Code Review` section shape in `skills/output-style.md`; the **evidence slot** is the ref each finding named (per `skills/citation-format.md`; or, at zero findings, the effort level the run used). **Absence of this section on a PR is a visible defect on PR review.** Under `"milestone"` granularity this section travels in the step-6.5 commit instead, as the indented `Code-Review:` block `skills/solve-milestone/milestone-granularity.md (The Code Review block is copied)` defines (never a `## Code Review` heading, never a per-issue PR body), and #371 aggregates it onto the milestone PR. Use this template in the PR body:

   ```text
   ## Code Review

   - /code-review run: yes (omission is a park trigger — a submitted PR always carries a real review; a parked run opens no PR)
   - Findings: <count> in-scope finding(s) at <effort> effort
     - <finding> — <the ref it named, per skills/citation-format.md> → re-dispatched and resolved | accepted (rationale: <…>) | triggered park
     - … (one line per finding, or "none" when count is 0)
   - No park-triggering findings. | Park-triggering findings: <list>
   ```

   The version-bump annotation this section carries is the one step 6.4's resolved mode names.

4. **Version bump.** Read `versioning` from the profile first.
   - **Version-free mode** (`versioning: false`): **skip the bump entirely** — make no edit to `.claude-plugin/plugin.json`. Annotate the **Code Review** section "version-free — no version bump" and proceed to commit. (Steps below do not apply.)
   - **Fail-safe degradation** (versioned mode — `versioning` `true` or absent — but `.claude-plugin/plugin.json` does **not** exist): do **not** fail. Degrade to version-free: skip the bump, log a one-line note (e.g. "versioned mode but no `.claude-plugin/plugin.json` — degraded to version-free, no bump"), annotate the **Code Review** section "version-free — no version bump (plugin.json absent)", and proceed to commit.
   - **Versioned mode** (`versioning` `true` or absent, and `.claude-plugin/plugin.json` exists): edit `.claude-plugin/plugin.json` `version` directly (it is config, not under `sourceGlobs`; the orchestrator edits it on the main thread — if a consumer's `sourceGlobs` covers `.claude-plugin/`, dispatch the implementer to apply the bump instead). **No `/code-review` re-run and no test re-run are needed; proceed directly to commit.** The carve-out covers only the `/code-review` run — the PR still requires its **Code Review** section (under `"milestone"` granularity, the step-6.5 commit's `Code-Review:` block per step 6.3, #368), annotated "version-bump only — no logic change."
     - **Milestone run** (a target version was determined by `solve-milestone` and is held in the orchestrator's context — it is not a CLI argument): set `plugin.json` `version` to that target. **Idempotent** — if already equal, no change; move on.
     - **Standalone run** (no milestone target in the orchestrator's context): apply a **patch** bump (`x.y.Z` → `x.y.(Z+1)`), state the new version to the user, and **ask whether it should be minor or major instead** — adjust before opening the PR (under `"milestone"` granularity, before the step-6.5 commit, #368). **This ask never fires inside a milestone run.** The guard is the **caller**, not whether a target version is still in context: a milestone run's contract is that the loop **never waits on a human** (`skills/solve-milestone/SKILL.md`'s `### 4. Loop over issues in dependency-graph order`), which a blocking question would break. When a milestone run reaches this bullet because the held target dropped out of context, re-derive the target from the milestone itself (the same title / `scripts/extract-version` read `solve-milestone`'s `### 3. Determine the target version` already performs) and take the milestone-run path above; if that read also fails, apply the patch bump **non-interactively**, apply the `judgment call` label, and proceed. Only a genuinely standalone invocation asks.
     - `plugin.json` is the **single source of truth** for the plugin version. `marketplace.json` carries no `version` field (Claude Code resolves `plugin.json` first; setting both is a documented footgun that silently masks the marketplace value). The bump rides in this PR — no separate chore PR; under `"milestone"` granularity it rides this issue's step-6.5 commit instead (#368).
5. Commit on the feature branch — the `tests-green` hook (`PreToolUse` on `git commit`) re-checks the suite. Review-before-commit is enforced by audit trail (the mandatory **Code Review** section), not by a commit-time hook; `hooks/code-review-gate.sh` gates `gh pr create` / `gh pr merge`, not `git commit`. Under `"milestone"` granularity this commit carries the Decision Log summary, the `Code-Review:` block, and `Issue: #<n>` as its last line, in the exact shape `skills/solve-milestone/milestone-granularity.md § The integration commit` defines. That trailer is what the resume probe reads and what #371 aggregates onto the milestone PR.
6. Push the feature branch and open a PR with `--base <integrationBranch>` (never `protectedBranch` — enforced by the `no-push` / `no-pr-to-protected` hooks and GitHub branch protection). Put the Decision Log and the **Code Review** section in the PR body. Add a `judgment call` label if any borderline autonomous call was made. **Skipped whole under `"milestone"` granularity:** nothing is pushed and no per-issue PR is opened (`skills/solve-milestone/milestone-granularity.md (One, at milestone end (#371).)`), the issue's terminal state is committed on its branch and handed back for the orchestrator's local squash-fold, and a `judgment call` label earned this issue goes on the **issue** instead.
7. **Visual-review gate (UI issues — Layer 2).** Determine whether this issue touches a UI surface: `uiSurfaceGlobs` is configured in the profile **and** the PR's changed files match one of those globs (an implementer `NEW_UI_ELEMENTS: yes` declaration reinforces this signal). **Bypassed whole under `"milestone"` granularity** (no glob match test, no `needs review` label, no render-daemon boot, no capture, no `visual-review-assets` push, no AI pre-filter): every substep below reads a PR step 6.6 did not open, and visual review defers wholesale to the milestone-end `visualHold` gate, which tests the whole milestone branch's diff against `integrationBranch` (`docs/profile-schema.md (Should the single milestone PR wait)`; `docs/superpowers/specs/2026-07-30-milestone-branch-granularity-design.md § The visualHold gate`).
   - **Not a UI issue** (`uiSurfaceGlobs` absent, or the diff matches no `uiSurfaceGlobs` path): no visual gate — proceed to auto-merge (step 8).
   - **UI issue:** do **not** auto-merge. The terminal state for this issue is *PR open, awaiting human visual sign-off* — apply the `needs review` label **to the PR** via the apply-time helper (idempotent `gh label create --force` then `gh pr edit <pr> --add-label "needs review"`) and leave the PR open for a human to test-render and merge. `solve-milestone`'s final summary lists all open `needs review` PRs.
     - **`visualCapture` configured** (the profile carries a `visualCapture` block with all three required keys — `serverCmd`, `readyUrl`, `signInPath`) **and this is a sequential run** (see the deferral below): capture convenience evidence inline. Any failure in this flow degrades to the human-test note below — it never fails the run and never auto-merges. The flow:
       1. **Boot the render daemon (once per run, reused).** Run `${CLAUDE_PLUGIN_ROOT}/scripts/render-daemon.<sh|ps1> start` in the repo root (pwsh on Windows, bash elsewhere). The daemon reads `visualCapture.serverCmd` and `visualCapture.readyUrl` **from the profile itself** (you do not pass them), spawns the seeded/persona app server detached, polls `readyUrl` until ready, and writes `.milestone-config/.runtime/render-daemon.json` (`port` · `token` · `pid` · `readyUrl` · `startedAt`). A nonzero exit means boot/reuse failed → degrade to the human-test note. **Derive the app origin (`scheme://host:port`) for the navigation below — `readyUrl` is the readiness probe only, not the navigation base.** `readyUrl` is a `/health`-style URL (e.g. `http://127.0.0.1:3000/health`), so take its scheme + host + port **origin** (strip the path and query): `http://127.0.0.1:3000`. Cross-check that port against the state file's `port` field. Used verbatim as the base, `readyUrl`'s trailing path yields a malformed route.
       2. **Authenticate via the test sign-in seam.** Resolve `{persona}` from `visualCapture.persona` (default `super-admin`), substitute it into `visualCapture.signInPath` (e.g. `/dev/sign_in/{persona}` → `/dev/sign_in/super-admin`), and drive **Playwright MCP** to navigate `<origin><signInPath>` (step 7.1's origin + that path, e.g. `http://127.0.0.1:3000/dev/sign_in/super-admin`) to establish the authenticated session.
       3. **Capture each surface × viewport × appearance.** For each **agent-supplied** surface route + required on-screen state (the implementing agent supplies both per issue; there is no per-repo route map): for each entry in `visualCapture.viewports` (default `{ "desktop": { "width": 1440, "height": 900 } }`) and each entry in `visualCapture.appearances` (default `["light"]`), resize the Playwright MCP viewport, set the appearance, navigate `<origin><surface-route>` into its required state, and capture one screenshot named `issue<n>-<slug>-<viewport>-<appearance>.png` — the per-viewport/appearance suffix keeps the fan-out filenames collision-free.
       4. **Publish.** Push the PNGs to an orphan `visual-review-assets` branch (so binary evidence never lands on `integrationBranch`) and post a **single** PR comment titled **"👁️ Visual evidence"** (`gh pr comment <pr>`) in the 👁️/🤖 comment shape (`skills/output-style.md`) that, per shot, names its surface × viewport × appearance and fills the evidence slot by embedding the raw image and linking its blob. The 👁️ glyph reuses the board legend's "awaiting visual review" marker — same concept, not a second meaning.
       5. **AI pre-filter (optional).** Gated on `visualCapture.aiPrefilter: true`. Absent or `false` → **no-op, skip with one log line**; everything downstream (the degradation bullet's own trigger, the `needs review` hold, the gate) proceeds exactly as if this substep did not exist. When it is `true` and **at least one** screenshot from step 7.3 was captured, immediately after the Publish comment (step 7.4) the **orchestrator itself** reads each captured PNG directly via its own image-reading capability and assigns each shot a one-line verdict — **`pass`** or **`suspected-issue: <one-line reason>`**. **Consume the captured PNG artifacts ONLY** — no new browser stack, no `puppeteer-core`, no re-render, no server boot, no Playwright MCP; it reads the exact files step 7.3 wrote (`issue<n>-<slug>-<viewport>-<appearance>.png`).
          - **Verdicts and comment.** Produce **one verdict per surface × viewport × appearance** — the same combination step 7.3 enumerated — and post **all** verdicts in **one** separate PR comment titled **"🤖 AI pre-filter verdicts"** (`gh pr comment <pr>`), posted **after** and **never** editing, replacing, or merged into the "👁️ Visual evidence" comment. Use the 👁️/🤖 comment shape (`skills/output-style.md`): each verdict names its surface × viewport × appearance, and the **evidence slot** is the named defect. A `suspected-issue` reason names **only obvious rendered-layout breakage (overflow, overlap, blank/broken surface, unstyled content) — never a subjective/aesthetic judgment.**
          - **Empty state and error path.** Zero PNGs captured at step 7.3 → no-op: skip with one log line and post no verdict comment. Sub-key absent/`false`, `visualCapture` absent/incomplete, or reading/interpreting any PNG failing → **skip the entire pre-filter substep with one log line**. Neither ever fails the run, blocks the Publish comment, or alters the degradation note below.
          - **Never a merge gate.** The pre-filter is a **convenience signal for the human reviewer**, who stays the merge gate: it **NEVER auto-merges a UI issue** and never changes the merge decision, whatever the verdicts.
     - **Degradation — `visualCapture` absent or incomplete (missing a required key), OR any capture failure** (daemon will not boot/reuse, sign-in fails, a surface will not render, push fails): do **not** fail and do **not** auto-merge — post a note on the PR (`gh pr comment <pr>`) that visual evidence is unavailable and a **human visual test is required before the merge to `integrationBranch`**. The `needs review` label keeps the PR held open for human sign-off regardless.
8. **Auto-merge on green (non-UI issues only):** once CI is green, run `gh pr merge --squash --delete-branch`. This replaces the human-choice step of `superpowers:finishing-a-development-branch`. **UI issues are skipped here** — they remain open per the visual-review gate (step 7) until a human merges. **Skipped whole under `"milestone"` granularity:** there is no per-issue PR to merge; the milestone branch pushes and merges once, at milestone end (#371).
9. Confirm the issue is closed (a linked PR auto-closes it; otherwise `gh issue close <n>`). **For a UI issue held at the visual-review gate, the issue stays open** with its PR awaiting human visual sign-off — it closes when the human merges the PR. **Skipped whole under `"milestone"` granularity:** the work has not reached origin yet, so closing here would contradict the milestone-end explicit close and the red-CI "do not close any issue" handler; the close is deferred to that milestone-end sequence (#371).

## Run-end cost record (additive, never-gating)

As the **last action before returning to the caller** at **every** terminal exit — every park (steps 0, 2, 3, 4, 6.1), the step-7 visual-review hold, the step-9 close, and, under `"milestone"` granularity, the step-6.5 commit that replaces both — emit one per-run cost record. Additive and **never-gating**: it never blocks, parks, or changes any merge/park/close outcome (`.project/design-philosophy.md#Error & failure philosophy` — optional integrations never gate; absent means skip with one log line).

1. **Aggregate.** From the `<usage>` block each Agent-dispatch tool result carried this run (implementer, `/code-review`, coherence-reviewer, any direct triage dispatch — a background dispatch's completion notification carries the same block), sum `subagent_tokens` per model tier (`opus` / `sonnet`, keyed by the dispatched agent's tier) and sum `duration_ms` across dispatches, plus the orchestrator's own run clock → `wallClockSeconds`.
2. **Map (auditable lower-bound).** Each tier's summed `subagent_tokens` → `inputTokens` wholly; `outputTokens` = 0; `cacheReadTokens` = `cacheWriteTokens` = 0 (not surfaced per-dispatch — the 0 sentinel per #320, never fabricated). Pass `provenanceNote: "unsplit-total-as-input"` so the writer marks the cost a lower-bound.
3. **Emit.** Pipe `{"runId":"<issue branch / run id>","wallClockSeconds":<n>,"tiers":{"<tier>":{...}},"provenanceNote":"unsplit-total-as-input"}` to `${CLAUDE_PLUGIN_ROOT}/scripts/write-cost-record.{sh,ps1}` (pwsh on Windows, bash elsewhere). The single-record write to `.milestone-config/.runtime/cost-records/` is #320's responsibility.
4. **Skip cleanly.** Zero dispatches this run (e.g. a triage-blocker park before any dispatch) → skip the emission with one log line, no zero-value record. Writer script absent, or no `<usage>` figures surfaced at all → silent no-op, one log line. Never fails the run.

## Autonomy model (Balanced)

**Proceed autonomously (log on the PR; on the step-6.5 commit trailer under `"milestone"` granularity, #368):** implementation choices within the approved architecture; reuse of existing helpers, styles, and conventions; test design; local reversible refactors; resolving in-scope `/code-review` findings (step 6.1).

**PARK & continue (the autonomous runtime parks; it does not interactively wait):** deviation from the approved architecture; any change to a shared contract, interface, base class, or DB schema used beyond this issue; a new dependency; edits outside the issue's expected file scope; a gate that cannot be met without a design change; material ambiguity in the issue's intent; `/code-review` omission or substitution — skipping `/code-review` for any reason (time, token budget, tool error, self-review substitution) is **not** an in-scope autonomous decision; budget pressure is not a permitted exception.

In the autonomous runtime, a park means: post a comment on the issue that **opens with `🔴 Parked — ` followed by the reason** (e.g. `🔴 Parked — architecture conflict: shared interface change required`); apply the appropriate label (`needs design`, `needs decision`, or `blocked`); also apply the `in progress` label (via the apply-time helper) when the feature branch has commits — the open-WIP signal the milestone loop and post-run review rely on; leave the issue open; leave the branch open with any work preserved; and return — the milestone loop continues with independent, clean issues. **Only a systemic failure** (auth/`gh` failure, broken `integrationBranch`, missing tooling) halts the whole run. A standalone interactive `solve-issue` still parks durably (comment + label + open branch); it may additionally narrate to the watching operator.

**Additional park triggers** (each a park: comment + label + open branch, **not** silent resolution and **not** an interactive prompt):
- The recorded/locked design is internally contradictory → park with `needs design`.
- A self-noted risk about the **approved** design (e.g. "this list could get long at realistic data volumes") → park with `needs design`.

**Architecture is locked** at plan-approval time (step 2). The procedure executes approved architecture. If implementation proves the plan wrong → park, not pivot.

A change is **architecture** (→ park) if it touches any of: a component or data structure named in the approved plan; a shared contract, interface, base class, DB schema, or public API used by code outside this issue; data ownership or a cross-component boundary; a new external dependency; or any file outside this issue's stated scope. A change is an **implementation detail** (→ proceed, log in the Decision Log, step 6.2) if it is local to this issue's own files, changes no shared contract, and is reversible — a binding style, a private helper extracted in the same file, a local refactor, or test design. When the distinction is genuinely ambiguous, treat it as architecture and park.

**Audit trail (always):** a Decision Log on every PR (in the step-6.5 commit trailer under `"milestone"` granularity, steps 6.2 and 6.3), a **Code Review** section recording every `/code-review` run and its findings/resolutions, and a `judgment call` label on borderline calls, so post-run PR review surfaces every judgment. Under `"milestone"` granularity that label goes on the **issue** (step 6.6) and the post-run review is the single milestone PR's (#368).

## Permission pre-flight gate

**Runs once per run, before the first background dispatch. Scope: this gate applies only when background dispatch is about to be used (a leaf dispatched as `Agent(run_in_background: true)`). A fully synchronous run SKIPS it entirely — skipped, not merely cheap; the gate is not executed at all, and the run proceeds directly with no gate evaluation.**

Background subagents auto-deny any tool call that would otherwise prompt (documented Claude Code behavior). A background leaf hitting an un-allowlisted tool fails outright with no interactive recovery. Before dispatching any leaf in the background, run this gate to verify the session's permission allowlist is complete.

**Allowlist source — merged settings read.** Read `permissions.allow` from all three Claude Code settings layers and union them:

| Priority | File |
|---|---|
| 1 | `~/.claude/settings.json` (user global) |
| 2 | `.claude/settings.json` (project) |
| 3 | `.claude/settings.local.json` (project local) |

Absent or unreadable layers are skipped in the union, not treated as gaps. Synchronous fallback fires only when (1) the union fails to cover the required tool surface, or (2) no layer is readable.

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
- **Gap detected (union does not cover the required surface, or no layer is readable):** do **not** dispatch in the background. Instead:
  1. Surface a 🔴 gap table listing each missing grant and which settings layer(s) could supply it.
  2. **Fall back to synchronous dispatch for this run.** The run completes; it just does not use background concurrency.
  3. Recommend the consumer run `/fewer-permission-prompts` to establish a stable allowlist (see `docs/consumer-setup.md`).

After the first background-dispatch decision point, the result (proceed / fallback) is held for the rest of the run — do not re-read settings on every issue.

**Auto-deny handling.** When a leaf (implementer, reviewer) reports an auto-deny it could not work around, treat it as a **park**: post a comment opening with `🔴 Parked — auto-deny on <tool>` on the issue, apply the `blocked` label (+ `in progress` if the branch has commits), preserve the branch, and return. The park itself is the durable record: the orchestrator runs on the main line, so the label and comment it just wrote are what the milestone loop reads back, and no separate return payload carries the park.

## Milestone granularity (`integrationGranularity: "milestone"`)

**Resolved from the profile at step 1, not from an invocation token.** When `integrationGranularity` resolves to `"milestone"` (`docs/profile-schema.md (How should built issues integrate?)`), read `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/milestone-granularity.md` for the branch model, the integration-commit trailer format, and the resume query, and apply the `"milestone"` clause each step above carries: branch base (steps 2, 3), audit-trail destination (6.2, 6.3), trailer (6.5), suppressed push/PR (6.6), bypassed visual gate (7), suppressed auto-merge (8) and close (9). **When the key is absent or resolves to `"issue"` or `"wave"`, none of those clauses applies and the entire pipeline runs byte-unchanged.**

## Async mode (`--async`): retired

**`--async` is an interpreted token, not a parsed CLI flag.** Claude Code does no argument parsing — `$ARGUMENTS` is string-substituted — so the token is **recognized** by string presence in the invocation text. It is now **inert**: the pipeline above runs on the caller's own main line. A habit-typed or stale `--async` is a no-op, never an error (the same treatment a habit-typed `--parallel` gets in `solve-milestone`).

It is retired because what the token used to mean — dispatching this whole pipeline as `Agent(run_in_background: true)` — violates the dispatch topology: this skill dispatches an implementer and a review fan-out, so running it inside a dispatched agent puts both at depth 2 (`docs/architecture.md` → `## Dispatch topology`). Read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/async-mode.md` for the retirement record and what replaces it.

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

One row per issue; emit only the row that matches the actual outcome and suppress the others. Under `"milestone"` granularity no PR is opened, so a completed issue emits the `✅ committed` row instead: the same completed-successfully ✅ the legend already carries, an empty PR cell per the PR-cell rule below, and the issue's own terminal state in the Note cell.

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

Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` — the single source of truth for this plugin's output contract. Its `## Terminal output` section governs what this skill prints (including the `## Output spec` template rule, which applies to this skill); its `## GitHub-facing prose`, `## When prose is the correct form`, and `## Evidence slots` sections govern every issue comment, PR comment, Decision Log, and PR body this skill writes. The two surfaces are distinct — the terminal rules never reach GitHub.

## Non-negotiables
- Gitflow. PRs target `integrationBranch` only — never `protectedBranch`.
- Honor the profile's `nonNegotiables` (framework versions, platform targets).
- The main thread never authors application or test code — always dispatch the implementer.
