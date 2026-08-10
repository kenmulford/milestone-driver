# Changelog

Release notes for milestone-driver. Versions before 1.7.0 are documented on the
[GitHub Releases page](https://github.com/kenmulford/milestone-driver/releases).

## v1.20.3 — the CHANGELOG's own prose contract

**Theme:** Release notes state what shipped and what a consumer must do; the slots that generate them are defined so the next entry cannot narrate how the work went.

### ✨ Prose contract

| Issue | PR | What |
|---|---|---|
| — apply the artifact prose contract to `CHANGELOG.md` | #483 | 789 → 717 lines with every issue and PR reference, release heading, release date and consumer-actionable note intact. Theme paragraphs become one line, a `What` cell states shipped behavior rather than build provenance, and each ⚖️ audit trail becomes the judgment-call line plus a fact list. |
| — define the CHANGELOG-entry slots in the generator | #483 | `skills/output-style.md`'s `## Evidence slots` row names four slots — theme, the per-bucket lines and their evidence, Consumer notes, the ⚖️ audit trail and its fact list — plus what is not one. `skills/solve-milestone/SKILL.md` step 6.5 reshapes its template to match and points at that row instead of restating it. |

### Consumer notes (upgrading from v1.20.2)

- **No schema changes** to `.milestone-config/driver.json`. No profile key added, removed or re-defaulted.
- **Behavior change, nothing to configure.** A completed `solve-milestone` run authors its CHANGELOG entry to the defined slots — shorter entries, the same facts. No skill gains or loses a step, and no gate changes.
- Both changed files are shipped plugin skills, so the contract governs your repo's CHANGELOG from the next completed milestone.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- `skills/output-style.md` is at 9412 of its 9500-byte ceiling and `skills/solve-issue/SKILL.md` at 69478 of 69500. The next edit to either fails the size ratchet until something is cut or the file is split.

## v1.20.2 — stop re-reviewing what cannot have broken

**Theme:** Two review-cycle costs removed — a comment-only fix no longer re-runs the suite or the review, and `risk:light` no longer pays for review rounds after a clean one.

### ✨ Review-cycle cost

| Issue | PR | What |
|---|---|---|
| #476 Comment-only deltas under sourceGlobs re-trigger the full review cycle | #478 | Step 6.1's post-fix split decides on delta content, not file path. New `scripts/classify-delta.{sh,ps1}` with a 66-row golden matrix per leg. |
| #477 risk:light relaxes review effort but not review cycle count | #479 | Light converges after one review cycle; a second runs only when the most recent review returned a Critical or Important finding. Heavy stays at two. |

### Consumer notes (upgrading from v1.20.1)

- **No schema changes** to `.milestone-config/driver.json`.
- New shipped scripts: `scripts/classify-delta.{sh,ps1}` plus `tests/classify-delta.{cases.tsv,test.sh,test.ps1}`. Both legs run in CI on every PR.
- The comment-only branch resolves every uncertainty to `code-changed`: unmapped extension, empty delta, untracked file, rename, mode change, deletion, a machine-read directive (`#!`, `// eslint-disable`, `//go:build`), a block comment followed by code on one line, and a heredoc payload line.
- The comment-only branch stages and commits in separate calls — `tests-green` is a `PreToolUse` hook that reads the index before the command runs. It is not a guaranteed second suite run: it no-ops when `unitTestCmd` is absent, when the staged tree matches the last green stamp, when `jq` is absent, or when `CLAUDE_HOOK_DISABLE_TESTS_GREEN=1` is set.
- Light reads the reviewer template's Critical / Important / Minor. A finding carrying no severity counts as Important, so Light degrades to Heavy rather than skipping a defect.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- `skills/solve-issue/SKILL.md` is at 69478 of its 69500-byte ceiling. The next edit to it fails the size ratchet until something is cut or the file is split.

## v1.20.1 — the cache that shipped switched off

**Theme:** v1.20.0's triage cache wrote entries with no usable key, so every lookup missed and the cache was inert in the release that introduced it; fixed here with three consistency defects a post-release coherence review found.

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #462 Triage Step 6.5 requires a cache key that Step 2.5 forbids deriving and triage-cache never prints | #473 | `write` takes the Step 2.5 GraphQL response as a fourth argument and stamps each entry's `key` from the same definition `lookup` compares against. The orchestrator never handles a key. |
| #466 Consumer docs say four gates where there are six, and three links point at a heading that moved | #469 | Four docs and one hook comment name all six shipped gates in one order; three dead links to `README.md#the-layered-gating-model` repointed to `docs/architecture.md`. |
| #464 The reviewer agent pair diverged | #470 | Restored `triage-reviewer.md`'s "you surface it, you don't design the fix" rule, plus five smaller divergences from `design-reviewer.md`. |
| #463 `docs/architecture.md:148` still calls implementation the sole concurrent stage, contradicting `:117` and `:145` after #400 | #467 | `:148` corrected to match `:117` and `:145` after #400 pipelined build and review. |

### Consumer notes (upgrading from v1.20.0)

- **Upgrade if you use `/milestone-driver:triage`.** On v1.20.0 the cache never matched, so every run re-dispatched a reviewer for every issue. Results were correct; you paid full triage cost each time. Existing `.milestone-config/triage-cache.json` files stay valid — the key format is unchanged, only which component computes it.
- `scripts/triage-cache.{sh,ps1}`'s `write` subcommand now takes **four** arguments (`write <repo-root> <entries.json> <graphql-response.json>`). Direct callers must add the response file. An absent or unreadable response is fail-open: entries are written without a key, exit 0, and those issues re-triage next run.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- Two ceilings in `scripts/check-size-budgets.{sh,ps1}` were raised by recorded decision: `agents/triage-reviewer.md` to 17000 bytes, `agents/design-reviewer.md` to 120 lines. That authorization is spent — the next edit to either re-derives downward as usual.
- **No gate catches a fix that reads correctly and no longer does the same thing.** Nine instances across this milestone, each caught by a reviewer opening the target and reading it, none by a gate — the result is valid, passes every check, and reads like it means what it used to. #466 corrected a gate count in a sentence and left the table 45 lines below still enumerating four; #464's ceiling raise would have collapsed the two rows `positional-desync` swaps to identical values, leaving the assertion passing while proving nothing.
- **v1.20.0 was tagged before #462 merged.** The fix was built, reviewed and green on an open PR at release time.
- **#465 was closed unbuilt** (eight tables of contents in four shapes). The inconsistency costs human navigation only: the model loads the whole file and cross-file references resolve against headings, not TOC labels. Its body also miscounted its own sites and cited `docs/plugin-features-reference.md`, which has never existed in the tree or in git history.
- Open, found here and not fixed: **#468** — `tests/build-file-index.test.sh`, `tests/extract-version.test.sh` and `tests/parse-md-epic-order.test.sh` use bash 4.3 namerefs (`local -n`) and report `0 passed` under the `/bin/bash 3.2.57` macOS ships; invisible in CI, which runs the bash suite on Ubuntu. **#471** — the bash and PowerShell legs sort labels differently outside the BMP, so an issue carrying both an emoji label and a `U+E000-FFFF` label gets a different cache key per platform.

## v1.20.0 — anchor every citation, then cut 20%

**Theme:** Every live line citation became a content anchor or heading reference, repo-root-relative became the only conforming path base, and `scripts/check-citations.{sh,ps1}` resolves them in CI so a reworded line fails the build. The second half trimmed the governed skill and agent files by 7.3% of bytes against a 20% target.

### ✨ Anchors, and the gate that keeps them true

| Issue | PR | What |
|---|---|---|
| #431 convert every live line citation to an anchor | #447 | 152 line citations converted, each verified by a resolver run (exit 0, exactly one `PRIMARY`, zero `MATCH`). Three line-style citations survive deliberately and are named in the PR: two illustrate the line form, one points into the sibling `milestone-feeder` repo. |
| #430 retarget 20 broken line citations and drop 2 to a file that never existed | #444 | Every line number re-derived against the real target. Three sites asserted a process-ID threshold of `<= 0` where `scripts/render-daemon.ps1` ships `<= 1`; the claim was corrected before #431 froze it into an anchor. Both citations to `docs/efficiency-grounding-plan.md` were dropped — no doc in this repo makes that claim. |
| #429 declare repo-root-relative the only conforming citation base | #445 | `skills/citation-format.md` named four citation forms but not what directory a `path` resolves from, and no resolver does repo-root discovery. Live citations used both bases: 132 repo-root, 47 citing-file-relative, 8 neither. Repo-root-relative is now the single conforming base, with no fallback. |
| #425 same-file citations must use a heading, not an anchor | #442 | An anchor citation written into its own target file reproduces the anchor on the citing line, which `resolve-citation.sh` labels `PRIMARY` at exit 0. Inside its own target file, write a heading citation — a citing line is not a heading. Live same-file count measured at 0. |
| #432 gate `path (anchor)` citations repo-wide | #456 | `scripts/check-citations.{sh,ps1}` walks the tree, resolves every `path (anchor)` citation byte-identically on both legs, and runs in CI as a runner plus a pass over this repo's real tree. Clean at merge: `SUMMARY ok=189 failed=0`. Catches both a broken anchor and an anchor that resolves twice, which exit status alone cannot see. |
| #427 govern `skills/citation-format.md` in the size ratchet | #448 | The shared citation reference loads into context like every other governed file and eight files point at it, but it was absent from the size check. Now governed at 230 lines / 13000 bytes, re-derived from a fresh measure. |
| #428 make the governed set one row per file so ceilings cannot drift | #446 | The parity guard compared only the lengths of three parallel arrays, so a positional desync measured files against other files' ceilings and exited 0. The governed set is now one row per file, `<path> <lineCeiling> <byteCeiling>`. Written RED first; twin equivalence reconstructed across 14 malformed row shapes. |

### ✂️ The 20% cut

| Issue | PR | What |
|---|---|---|
| #433 trim `skills/solve-milestone/SKILL.md` | #449 | 664 / 76470 → 602 / 65569, a 14.3% byte reduction across 129 edits. Two cuts that read as prose but were content were restored: step 6.5's literal `git show <commit>:CHANGELOG.md`, and versioned mode's leading-whitespace qualifier for a CHANGELOG heading match. |
| #434 trim `skills/solve-issue/SKILL.md` | #450 | 394 / 76940 → 357 / 66075, a 14.1% reduction across 64 hunks. A stale claim that the plugin ships no code-review hook was corrected — `hooks/code-review-gate.sh` exists. A park trigger that had survived only in a label-conditioned form was restored unconditional. |
| #441 extract the triage cache mechanics to `scripts/triage-cache.{sh,ps1}` | #451 | Steps 2.5 and 6.5 re-taught the cache mechanics in prose on every invocation; a script executes and costs zero context. `skills/triage/SKILL.md` goes 450 / 42130 → 368 / 36670. Building it RED found a real bug: PowerShell's `ConvertFrom-Json` coerces an ISO-8601 string to `[datetime]`, so the composed key came out in culture format — a permanent 100% cache miss at exit 0. |
| #435 trim `skills/triage/SKILL.md` | #452 | 368 / 36670 → 368 / 34789, a 5.1% reduction. #441 had already harvested this file. Review found 579 further cuttable bytes; they were left, because the residual is exact commands, two agent return contracts, a JSON shape and two measured findings. |
| #436 trim `skills/solve-milestone/parallel-waves.md` | #453 | Read in full on every run that does not hit a barrier. 205 / 64827 → 186 / 58981, a 9.0% reduction — the only issue in the cut whose byte and line targets both cleared. All 17 removed spans were traced to a surviving statement or classified as rationale. |
| #437 trim the user-facing trio | #454 | `skills/setup/SKILL.md`, `skills/notices.md`, `skills/output-style.md`: 620 / 54565 → 601 / 47894, a 12.2% reduction. The largest cut in `notices.md` had replaced each notice's literal marker-writing command with a generic template that does not compose (all eight marker values already carry the `.milestone-config/` prefix) — the composed `touch` would have failed and every one-time notice would have re-printed forever. Fixed; all eight verified by running the composed command. |
| #438 trim the four conditionally-loaded reference files | #457 | `trello-sync.md`, `milestone-granularity.md`, `async-mode.md`, `md-epic-fanout.md`: 625 / 59707 → 621 / 55475, a 7.1% reduction. This cleared the milestone's last ratchet failure — `milestone-granularity.md` had been 342 bytes over ceiling since #431, since anchors are longer than the line numbers they replaced. One requested cut was refused: the caller does not state what the cut text states, and what it does state contradicts it. |
| #439 trim the three agent briefs, and fix `implementer.md`'s return-shape examples | #455 | `design-reviewer.md` 15721 → 13929 (11.4%), `triage-reviewer.md` 16356 → 14216 (13.1%), `implementer.md` 14614 → 14147 (3.2%). Two examples in `agents/implementer.md` taught return tokens the consumer cannot parse — `PAUSE` where `skills/solve-issue/SKILL.md` matches `PAUSED-FOR-APPROVAL`, `STOP` where it matches `STATUS: STOPPED`. All eleven Blocker-producing rules re-probed by literal substring and confirmed intact. |

### 🔧 Behavior and correctness

| Issue | PR | What |
|---|---|---|
| #400 pipeline Phase 1, removing the Stage A to Stage B barrier | #459 | Each issue's reviewer now dispatches the moment that issue's own implementer returns and clears its gates, instead of waiting for the whole wave to build. `maxParallelWorkers` becomes one shared in-flight counter spanning build and review, allocated by a four-row ladder. Total wall clock is unchanged; a fast issue frees its slot and opens its PR immediately (at cap 2, one PR opens at t=11 instead of t=40). Four review rounds found 9 ladder defects invisible to all four gates and all 26 suites, including a single-issue wave that finished its review and stalled with the work uncommitted. |
| #440 gate the reviewer-state Blocker paths behind a source set | #458 | `agents/triage-reviewer.md` produced a Blocker from twelve places; seven test a property of the issue, five tested a property of the reviewer ("I am unsure", "a convention probably exists"), and only one required the reviewer to have looked anywhere first. Those five now require a completed search over an explicit source set derived from what that agent's brief receives. `agents/design-reviewer.md` carried all five near-verbatim and was fixed in the same pass. Twelve issues previously parked in this repo re-classified: 12/12 still park, each for an issue-traceable reason. |
| #408 correct the `--driven` analogy at `solve-milestone` step 3.6 | #443 | `skills/solve-milestone/SKILL.md` asserted at one line that a halt never fires under `--driven` and stated the opposite 33 lines later. The analogy is inverted in place; the authoritative line is byte-unchanged and the file is line-count neutral, so all 56 inbound citations still resolve. |

### Consumer notes (upgrading from v1.19.0)

- **Nothing to do on upgrade.** No schema changes to `.milestone-config/driver.json`; no key added, removed, renamed or re-defaulted. Every invocation token behaves as in v1.19.0.
- **New artifacts:** `scripts/check-citations.{sh,ps1}` (a CI gate) and `scripts/triage-cache.{sh,ps1}` (a runtime primitive the triage skill calls), each with its test twin, cases table and fixtures.
- **CI grows three steps per leg**, six total: the `triage-cache` runner, the `check-citations` runner, and one `check-citations` run against this repo's real tree.
- **The gate verifies exactly one citation form.** `scripts/check-citations.{sh,ps1}` resolves `path (anchor)`. The other three forms are counted and reported `UNVERIFIED`, not checked, so `failed=0` says nothing about them. On this repo the gate reports `ok=194 failed=0` with `unverified=81` — 57 `path#Heading`, 21 `path § Heading`, 3 `path:line`.
- **The gate skips six trees**, each emitted as an `EXCLUDED` record with its skip count, including `.milestone-config/worktrees/` and `.milestone-feeder/`.
- **`.gitattributes` now pins `*.md` to `eol=lf`.** A checkout with `core.autocrlf=true` previously added a byte per line and failed the size gate on files a contributor had never touched.
- **A parallel `solve-milestone` run reviews as it goes (#400).** `parallel` and `maxParallelWorkers` keep their names, shapes and defaults. What changes is what the cap counts: one number covering build leaves and review leaves together, rather than a separate allowance per stage.
- **Triage parks fewer issues (#440).** A reviewer can still raise a Blocker on anything recorded in the issue. It can no longer raise one for being unsure without exhausting a named source set first, and a found, cited convention whose soundness it cannot certify is now Advisory. Nothing to configure. Expect the largest change in repos with thin `.project/` docs.
- **Contributors to this repo: the ceiling rule is `actual × 1.05`, not `target × 1.05`**, and the line axis has a minimum-headroom floor mirroring the byte axis's 500-byte rounding. Consumers are unaffected; the ratchet governs this repo's own skill and agent files.

### ⚖️ Post-run audit trail

Judgment-call PRs: none. All 18 issues in milestone #37 merged and closed, zero parked.

- **The 20% target was not met on any file.** Across the whole governed set (15 files) from base commit `c379bb3` to the end-of-milestone pass: 427611 → 396568 bytes, 3479 → 3313 lines — 7.3% of bytes, 4.8% of lines. Best single file is `skills/triage/SKILL.md` at 17.0% net, which is an extraction plus a trim. Per-issue byte yields ran 3.0% (`trello-sync.md`) to 15.2% (`notices.md`). Four files grew: `parallel-waves.md` +4.6% (#400's scheduler), both reviewer briefs (#440's source sets), and `skills/citation-format.md` 9536 → 12060 bytes (#427 brought a previously ungoverned file under the ratchet, and anchors cost bytes against the line numbers they replace).
- **#432 shipped with two acceptance criteria formally dropped**, recorded in the PR and in both script headers. (1) `path#Heading` and `path § Heading` resolution — a heading matcher produced 23 FAIL records against 23 correct citations. (2) A syntactic same-file rule — every skill file here is named `SKILL.md`, so a basename comparison flagged 3 cross-file citations as same-file; same-file citations are caught by match count instead.
- **#400's slot-allocation order contradicted a recorded decision.** `docs/briefs/2026-07-31-post-alienation-followups.md § Decision 1: the concurrency cap. SETTLED.` records build-first as settled on 2026-07-30; #400's acceptance criterion 2 says the opposite. Review-first was re-ratified 2026-08-06 and the brief is marked superseded in place, scoped to its two slot-preference statements.
- **Ceilings were re-derived once at the end of the milestone**, not per issue: 5 line ceilings and 10 byte ceilings lowered, 8 rows derived above their current value and held. Issue bodies assuming `target × 1.05` recorded numbers that would have failed three files.
- Fixed in the end pass: the citation gate walked `.milestone-config/worktrees/` (58 FAIL records from deliberately-broken fixture anchors, red only for the person running the driver), and governed `*.md` was not yet pinned to `eol=lf`.
- Open follow-ups: **#468** — three test runners use bash 4.3 namerefs and cannot run under real `/bin/bash 3.2.57` (`tests/build-file-index.test.sh`, `tests/extract-version.test.sh`, `tests/parse-md-epic-order.test.sh`, each `local -n _arr="$2"`). **`skills/solve-milestone/milestone-granularity.md`** documents a pre-clean-guard placement in Before-starting that `skills/solve-milestone/SKILL.md` contradicts by cutting the milestone branch inside the issue loop. **`agents/design-reviewer.md`** criterion 3 reads as "found pattern → never Blocker", conflicting with its own rendered-outcome row. **15 `path § Heading` citations use a bare filename** instead of the repo-root-relative path `skills/citation-format.md` requires — six in `skills/solve-milestone/SKILL.md`, nine in `parallel-waves.md`; the gate does not cover that form.

## v1.19.0 — citation anchors

**Theme:** A citation can now name its target by a content anchor that survives line drift, with a resolver that fails loud when the anchor is gone and resolve-once blocks in triage and solve-issue so no subagent reasons from a moved citation.

### ✨ Citation anchors

| Issue | PR | What |
|---|---|---|
| #416 Define the citation format in `skills/citation-format.md` | #420 | New shared reference naming all four citation forms in live use and defining `path (anchor)` in full: the parse rule, literal-string resolution, what marks text as a citation, and the fail-closed rule for an anchor that is present but not found. |
| #417 Ship the resolve-citation twin pair with its test twin | #421 | Dependency-free bash + PowerShell 7 resolver reporting every literal-substring occurrence of an anchor as TAB records, fail-closed on every error path, with a 21-case golden-matrix runner per leg in CI. |
| #418 Resolve source citations before dispatch | #422 | Resolve-once blocks in `solve-issue` and `triage` resolve an issue's citations and thread the resolved table into the subagent briefs, so no subagent re-derives a citation and a drifted anchor fails loud. |
| #380 triage-reviewer's Completeness criterion covers edit-site coverage | #419 | The triage reviewer sweeps for restated edit sites instead of confirming only the ones it was handed, returning every unenumerated site as one `missing-criteria` gap. |

### Consumer notes (upgrading from v1.18.0)

- **No schema changes** to `.milestone-config/driver.json`.
- **Nothing breaks.** `path:line` and `path:start-end` remain valid to write and resolve as before. The anchor form is additive; no evidence slot requires it.
- **New artifacts:** `scripts/resolve-citation.{sh,ps1}` (a runtime primitive, not a CI gate — it returns records at exit 0 and never fails a build), `tests/resolve-citation.test.{sh,ps1}` with its cases table and fixtures, and `skills/citation-format.md`.
- **CI grows one step per leg.**
- **Anchors are literal strings, never parsed symbols.** Resolution is a case-sensitive, line-scoped substring search — not a regex, not language-aware. Write the shortest string that uniquely names the region.
- **Extraction is model judgment, not pattern matching.** A parenthetical following a path is not automatically a citation.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- `tests/resolve-citation.test.ps1` asserts with `[string]::Equals(…, Ordinal)`, diverging from the bare `-eq` in its eight sibling pwsh runners, because `-eq` is case-insensitive and culture-sensitive and the issue required exact assertion. Migrating the house idiom is a separate sweep.

## v1.18.0 — milestone-scoped branching and dispatch topology

**Theme:** Two bodies of work. A whole milestone can build on one local branch and reach the integration branch through a single push, PR and CI run. And the worker layer is deleted: the orchestrator is the only session that fans out, every dispatched agent is a leaf at depth 1 where its completion notification arrives, and an issue outside the barrier partition is named and recovered rather than vanishing.

### ✨ Milestone-scoped branching

| Issue | PR | What |
|---|---|---|
| #368 add `milestone-granularity.md` with the branch model and local integration mechanics | #386 | New `skills/solve-milestone/milestone-granularity.md` holds the branch model, the local `git merge --squash` fold both the sequential loop and the parallel merge tail run, and the integration commit whose `Issue: #<n>` trailer carries that issue's Decision Log and Code Review block. Issue branches keep their `issue/<n>-<slug>` name, are cut from the milestone branch, and are never pushed. Read only under `"milestone"` granularity; missing there it halts rather than degrading to `"issue"`. |
| #371 add the milestone-end sequence and the red-CI handler | #388 | Replaces `solve-milestone` steps 6.6–6.8: commit the CHANGELOG onto the milestone branch, push once, open one PR into `integrationBranch`, merge on green, then close each issue with its own `gh issue close` — `Closes #n` fires only on a merge into the default branch. Red CI is run-scoped: label the PR `needs review`, name every issue on the branch in one 🔴 line, preserve the branch, close nothing. |
| #376 add the `visualHold` milestone-PR gate and carve out architecture invariant 3 | #394 | `visualHold` decides whether the single milestone PR waits for human UI sign-off, resolved through a first-match-wins table whose indeterminate-diff row holds. `docs/architecture.md` invariant 3 gets an explicit carve-out: under `"milestone"` the hold moves from the per-issue PR to the milestone PR, and only an operator writing `visualHold: false` merges it. |
| #374 make milestone-branch creation resume-safe against a leftover branch | #392 | Until the milestone-end push the milestone branch is the only copy of every issue folded in, so a resumed run must never re-cut it. Four legs, first match wins: cold cuts fresh; provably safe (0 commits ahead, or a merged PR) clears and re-cuts; carries-work attaches; ambiguous or a failed probe preserves the branch and halts. |
| #379 make `solve-issue` granularity-aware: branch base, commit trailer, suppressed push/PR/merge, resume probe | #390 | Under `"milestone"`, `solve-issue` cuts from the milestone branch, writes the extended commit trailer, suppresses its own push, PR and merge, and answers "already integrated?" from `git log <milestone-branch> --grep='^Issue: #<n>$'` rather than remote state that does not yet exist. `async-mode.md` follows. |
| #372 add the milestone branch as `parallel-waves`' third merge target | #389 | The worktree base becomes `<base>` in place of a hardcoded `integrationBranch`, so parallel workers cut from the milestone branch under `"milestone"` and behave as before under the other two values. |
| #375 wire milestone granularity into `solve-milestone` SKILL.md | #393 | `integrationGranularity` and `visualHold` resolve once at run start and hold for the whole run. Fail-open: an out-of-enum granularity degrades to `"issue"` with a logged line, a non-boolean `visualHold` degrades toward holding. Nothing re-resolves mid-run. |
| #377 add `integrationGranularity: "milestone"` and `visualHold` to the profile schema | #381 | `docs/profile-schema.md` gains the third enum value and the `visualHold` row, both optional and omit-the-default, plus why `"wave"` does not solve the push-per-issue problem. |
| #370 offer milestone granularity in the setup skill's Integration tier | #387 | The interview offers the third value. `"milestone"` fires a non-blocking precondition prompt carrying both CI branch-filter forms and suppresses the wave prompt. Write rule unchanged: omit the key for `"issue"`. |
| #369 document milestone granularity for consumers | #385 | `docs/architecture.md` gains a milestone-granularity section; `docs/consumer-setup.md` gains the walkthrough (both branch-filter forms, the red-CI behavior, the `visualHold` table); the README names all three values. |
| #366 record the milestone-granularity design spec | #383 | Committed at `docs/superpowers/specs/2026-07-30-milestone-branch-granularity-design.md`. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #378 record a size-budget ceiling raise in the PR Decision Log | #382 | The ceiling-ratchet header said a raise needs a recorded decision "on the issue that grows the file"; every PR body already carries a Decision Log, which is where a reviewer looks. Both twins now say so. Enforcement unchanged. |

### 🧵 Dispatch topology: every dispatched agent is a leaf

| Issue | PR | What |
|---|---|---|
| #361 delete the worker layer: the orchestrator fans out by stage, dispatched agents are leaves | #401 | Worker mode, the `--worker` token, Delta 3's structured handback and `--async`'s dispatch contract are deleted. Phase 1 dispatches by stage: concurrent implementer leaves, a barrier, concurrent reviewer leaves, then an unbarriered per-issue tail the orchestrator runs itself. A dispatched agent that dispatches a child seats that child at depth 2, where the completion notification never arrives and the parent's turn ends with the work uncommitted. `docs/architecture.md § Dispatch topology` is the invariant's one home. |
| #362 name the `abandoned` bucket, recover once, then park | #405 | The barrier partition ran on `built-green` and `parked`, which are not exhaustive: an issue in neither vanished with no label, comment or notification — the exact shape of an auto-denied background leaf, context exhaustion, or a killed run. `abandoned` is a named third bucket with its own probe legs (no PR, no pushed branch ahead of base, no park label), resolved by a recover-once ladder at cap 1 inside the same pass. |
| #363 `ort` auto-resolves non-adjacent same-file edits, not non-overlapping ones | #403 | Two edits on directly adjacent lines conflict; one unchanged line between them merges clean. So any file with a single shared append point (a changelog table, a barrel export, a DI registration list) conflicts by construction under concurrency. Swapped at five sites, and the two park-call sites now carry that this shape sits within bounded auto-resolve rather than triggering a park. |
| #365 tell every dispatched agent to namespace its own scratch | #404 | Concurrent agents shared one scratchpad directory and overwrote each other's probe files, producing a false cross-worktree-write alarm. One rule in two byte-identical families — seven dispatch sites state what the brief must carry, three agent contracts state what the agent honors: write scratch only under a path named for that issue or agent, and report what a probe printed rather than writing a file to read back. |
| #364 caveat the version-free CHANGELOG idempotency check against heading suffixes | #398 | Version-free mode compares the whole line, so a heading carrying `(partial)`, `(in progress)` or a date is not equal to `## <milestone title>`: the check reports no existing entry and prepends a duplicate section. Versioned mode is immune (its prefix ends in a trailing space). The caveat is appended byte-identically at both sites; strict equality stands, since widening the match would let `## Q3 Hardening` satisfy a milestone titled `Q3`. |
| #397 re-derive 18 stale cross-file citations | #409 | 18 citations re-derived: 6 into heading anchors that survive a line shift, 12 into corrected line numbers. Only 8 of the 12 had no heading to anchor to, their targets inside a 116-line heading-free stretch. The issue title's "5 of 8" does not reconcile with the PR's evidence table. |
| #399 the size-budget ratchet governs bytes as well as lines | #410 | Counting lines only meant prose appended to an existing line grew context cost at zero reported movement: PR #398 added 1,052 bytes at a flat 664 lines, and three later merges added 3,818 more the same way. Both twins hold a per-file byte ceiling beside the line ceiling, rounded up to the next 500 bytes. Lines stay as an independent second ceiling, because `file:line` citations pay a cost for line growth no byte count expresses. |

### Consumer notes (upgrading from v1.17.0)

- **Nothing to do on upgrade.** The default is still `"issue"`, and the `"issue"` and `"wave"` paths are byte-unchanged.
- **Schema change, both parts optional.** `integrationGranularity` now accepts `"milestone"` alongside `"issue"` and `"wave"`; `visualHold` is new. Both default to today's behavior when absent.
- **Opting in has one prereq.** Set `{ "integrationGranularity": "milestone" }`, then filter your own push-triggered workflows to ignore the `milestone-*` prefix: `branches-ignore: ['milestone-*']`, or `branches: ['**', '!milestone-*']` with the negation last. One form per event, never both. Skip the filter and the milestone-end push starts your push workflow while the PR run rebuilds the same commit.
- **The `milestone-` branch prefix is a stable, externally-consumed contract** — consumer CI filters are written against it.
- **`visualHold` is the one UI sign-off.** Absent (the default) holds the milestone PR whenever the branch's diff against `integrationBranch` touched a `uiSurfaceGlobs` path, and holds when that diff cannot be read. `visualHold: false` is the sole override. A non-boolean value holds, with a logged note. There is no `--no-visual-hold` token, and the key is read only under `"milestone"`.
- **Raising a governed file's size-budget ceiling is now recorded in the Decision Log of the PR that grows the file**, not on the issue (#378). Contributors only; consumers are unaffected.
- **`parallel` and `maxParallelWorkers` keep their names and defaults, but "how wide" counts something different (#361).** Concurrency moved from one worker per issue to one leaf agent per issue per stage: the run builds the Wave's issues concurrently, barriers, reviews them concurrently, then runs the gates, version bump, commit and PR from the main line. A value of 8 now buys 8 concurrent implementers then 8 concurrent reviewers, rather than 8 issues each running a full pipeline. `--worker` is gone and `--async` is inert.
- **An issue whose agent dies mid-build is recovered instead of lost (#362).** It is classified `abandoned`, rebuilt once from its existing worktree, and parked `blocked` with branch and worktree preserved only if the retry also fails. Nothing to configure; you will see one retry where you previously saw silence.
- **`merge=union` has a documented answer (#363).** `docs/consumer-setup.md` says why not to reach for it on a shared append point: union never reports a conflict, so it removes the only signal you would get, and it interleaves multi-line changes into structurally broken output.
- **Contributors gain a second axis a PR can fail on (#399).** A byte ceiling sits alongside the line ceiling for every governed file, so appending prose can fail the ratchet at zero line delta.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- **#361 closes the "workers strand on nested sub-agent dispatch" defect** v1.17.0 left open, rooted in [anthropics/claude-code#75043](https://github.com/anthropics/claude-code/issues/75043). Nothing waits on a depth-2 notification because nothing runs at depth 2.
- **#400 is parked `needs design`, not built.** #362 made the Stage A/B barrier load-bearing: an issue still mid-build presents the identical ground truth the `abandoned` classifier keys on, so removing the barrier would dispatch a second implementer into a worktree the first is still writing. Two decisions are owed: a per-issue readiness gate step 9 can trust, and a combined `maxParallelWorkers` accounting rule. (Built in v1.20.0.)
- **#399 rejected the word-count convention `superpowers:writing-skills` prescribes**, on a measurement: word count splits on whitespace, so `scripts/check-size-budgets.ps1` scores 1 word for 30 bytes, and the governed files are dense with exactly that token shape.
- **A mid-flight redirect to a running subagent never arrived, and the agent's final report described the retracted instruction as applied.** Caught by reading the changed files, not the report. A correction travelling parent→child is as unreliable as a completion notification travelling child→parent; only the second direction was in scope for #361. Derive-from-artifacts covers the outcome; nothing yet covers the instruction.
- **`hooks/code-review-gate.sh` caught the orchestrator skipping review** on #399 — it denies a `gh pr create` whose body carries no `## Code Review` section. Worth recording because a backstop that has never fired cannot be told apart from one that does not work.
- Open follow-ups: **#402, #406, #407** — four more stale cross-file citations plus #407's durable fix (check heading anchors, not line numbers). **#408** — `skills/solve-milestone/SKILL.md` contradicts itself on whether the purely-numeric-title halt fires under `--driven`. **A twin divergence, deferred** — a governed file that is present but unreadable records `OK` and exits 0 on the bash side of `check-size-budgets` while the PowerShell twin throws; which way both should go was out of scope for #399.

## v1.17.0 — reviewer grounding & output style

**Theme:** Reviewer claims get a defined research path and a scope-honesty rule, and every GitHub-facing shape this plugin writes gets one governing prose contract with an evidence slot.

### ✨ Reviewer grounding & output style

| Issue | PR | What |
|---|---|---|
| #336 wire `domainSkills` into the triage/design reviewer input contract | #344 | v1.16.1's "verify it is a genuine best practice" sub-step shipped with no research mechanism. `domainSkills` now threads through `skills/triage/SKILL.md` Step 1, both Step 3 brief lists, and both reviewer agents' "What you receive", as one ordered step: framework docs, then `domainSkills`, then repo patterns. No new profile key. |
| #341 consolidate the 4× output-style block; add a GitHub prose contract | #345 | New `skills/output-style.md` is the single source: the terminal-vs-GitHub surface split, the prose contract, when prose is the correct form, and evidence slots for 10 shapes. Four skill blocks become pointers; three agents' `## Communication style` declare themselves narrow overrides. Injected at two resolve-once blocks. |
| #342 require reviewer claims to state their verification scope | #346 | Both Rigor gates enforced only that a citation exists, so a correct `file:line` attached to an un-enumerated quantifier ("all three controllers", "14 of 15") passed. Two bullets per reviewer agent add the scope rule and "identical code is not identical exposure". No new GAPS `type`, no new schema field. |

### 🔧 Fixes

Found by a `plugin-dev:skill-reviewer` pass over all four skills after the three issues above merged.

| Issue | PR | What |
|---|---|---|
| #348 reference-file reads used bare relative paths | #357 | 20 reads of plugin-shipped files, plus every `scripts/…` invocation, resolved against the consumer repo's CWD where none of them exist. Three had absent-to-no-op branches, so #341's prose contract silently never reached any agent outside this repo. All now prefixed with `${CLAUDE_PLUGIN_ROOT}`. Verified against a real consumer repo. |
| #349 setup described `domainSkills` as implementer-only | #352 | #336 broadened the consumer set but left `skills/setup/SKILL.md` describing the old truth, in the one place a user decides whether to configure the key. Line-neutral copy fix. |
| #350 run-complete notification nested inside a skipped step | #353 | `Run-complete notification` and `Run-end cost record` lived under `#### 6.9`, inside the CHANGELOG step the systemic-halt path skips entirely, so a halt lost both the 🚨 signal and the cost record. Promoted to a top-level section; four cross-references corrected. |
| #351 setup never interviewed `uiSurfaceGlobs` | #355 | The key appeared zero times in the interview, so a user could configure the full `visualCapture` block and get design-lens review, the visual gate and visual capture all silently off. Adds the tier before Visual Capture, gated on both its Phase-1 signal and this key, plus a one-time notice for existing installs. |
| #354 CI-red CHANGELOG branch jumped past step 6.9 | #356 | The CI-red branch skipped `#### 6.9`'s required "Held open (CI red)" Your-move append. One line. |

### Consumer notes (upgrading from v1.16.1)

- **New shipped file:** `skills/output-style.md`, governed in `scripts/check-size-budgets.{sh,ps1}`. The four `## Output style` blocks in `setup` / `triage` / `solve-issue` / `solve-milestone` are pointers to it.
- **`setup` now asks for `uiSurfaceGlobs`.** Existing profiles keep working; a one-time notice points out the gap on the next run. Without the key, design-lens review, the visual-review gate and visual capture stay off.
- **Plugin-shipped paths in skill text carry `${CLAUDE_PLUGIN_ROOT}`.** Consumer-repo paths (`.milestone-config/`, `.project/`, `sourceGlobs` matches) still resolve against your repo.
- **Behavior change, no config change.** Reviewers verify a convention against an ordered path (docs → `domainSkills` → repo patterns) rather than assumption, and may not assert a count or universal quantifier they did not enumerate. Expect scope qualifications like "confirmed at `x.rb:201`; 2 other call sites not individually checked".
- **`domainSkills` is optional and degrades cleanly** — absent, the step is skipped; it never makes the docs check optional. All three injected inputs are additive grounding whose absence is never a STOP condition.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

Open at this release:

- **Workers strand on nested sub-agent dispatch.** Four of eight workers ended their turn waiting on a child that never re-invoked them; completed work sat uncommitted until the orchestrator probed the worktree. Root cause is upstream: [anthropics/claude-code#75043](https://github.com/anthropics/claude-code/issues/75043). The workarounds that held were reviewing in-turn with no dispatch, or polling the artifact's file content rather than the child's transcript. (Fixed in v1.18.0 by #361.)
- **A ceiling-table edit can break the golden-matrix fixtures with no review lens catching it.** #341 added `skills/output-style.md` to `scripts/check-size-budgets.*` and broke `tests/check-size-budgets.test.sh` (0/3). Five `/code-review` lenses cleared it; the coherence pass caught it.
- **The repo's own `domainSkills` went unconsulted while authoring changes to its skills.** Three findings from that guidance remain unfiled: `skills/solve-milestone/SKILL.md` is 658 lines against a documented 500-line limit, all four frontmatter descriptions summarize workflow (which `writing-skills` shows causes agents to skip the skill body), and no skill edit in this milestone was preceded by the baseline pressure test its Iron Law requires.
- **`${CLAUDE_PLUGIN_ROOT}` prefixing has no machine enforcement.** #348 placed 28 substrings by hand; nothing stops the next skill edit from reintroducing a bare path.

## v1.16.1 — convention-search before parking as `needs design`

**Theme:** Before triage parks an issue as `needs design`, both reviewer agents must search the existing codebase for a convention that answers the gap, and emulate a sound one (cited) rather than recommend a new approach.

### ✨ Triage convention-search

| Issue | PR | What |
|---|---|---|
| #334 require a convention search before `needs design` | #335 | `triage-reviewer` criterion 2 and `design-reviewer` criteria 1 and 3 require an active search of `sourceGlobs` / `uiSurfaceGlobs` plus the resolved `.project/` sections before emitting a `needs design` Blocker. A found, verified best-practice convention downgrades to an emulate-and-cite Advisory; the Blocker is reserved for a genuinely dry search or no conventional default. `skills/triage/SKILL.md` label routing unchanged. |

### Consumer notes (upgrading from v1.16.0)

- **Behavior refinement, no config change.** Triage parks fewer issues as `needs design`: an established, sound convention that answers an under-specified choice is recorded as an emulate-and-cite Advisory and the build proceeds. A dry search still parks exactly as before.
- The ungroundable "there is probably a convention" case is still a Blocker, not a pass.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.16.0 — run-efficiency grounding

**Theme:** Three additions to cut cache-aware dollar cost and sharpen grounding: a diff-scoped repo file map injected into subagent briefs, an optional AI pre-filter over captured screenshots, and a per-run cache-aware cost record.

### ✨ Run-efficiency grounding

| Issue | PR | What |
|---|---|---|
| #318 file-index resolver | #324 | New `scripts/build-file-index.{sh,ps1}`: a diff-scoped `path → purpose (+ callers/symbols)` index, grep-based, no new tool dependency, golden-matrix tested both legs. |
| #321 inject file index | #326 | The resolve-once dispatch block injects that index into the implementer brief alongside the `.project/` sections. No-op, no error, when the resolver is absent or fails. |
| #319 screenshot pre-filter | #323 | Optional `visualCapture.aiPrefilter` pass reads the captured PNGs and posts a per-surface/viewport/appearance verdict beside the "👁️ Visual evidence" comment. Never a merge gate, never auto-merges a UI issue. |
| #320 cost-record writer | #325 | New `scripts/write-cost-record.{sh,ps1}`: writes one cache-aware dollar cost, token breakdown and wall-clock record to `.milestone-config/.runtime/`. Fail-open, non-gating; hardcoded rate snapshot, optional `provenanceNote`. |
| #322 emit cost record | #328 | `solve-issue` and `solve-milestone` emit that record at every terminal exit. Never gates a run; silent no-op when the writer or usage figures are absent. |

### Consumer notes (upgrading from v1.15.1)

- New **optional** profile sub-key `visualCapture.aiPrefilter` (default absent/`false` → skipped); sparse-write, byte-unchanged when absent.
- Two new **gitignored** per-run artifact kinds under `.milestone-config/.runtime/`. The file index is in-memory only; cost records are written there. No change to committed config.
- Cost figures are a deliberate **lower bound**: the framework surfaces only a per-dispatch token total (recorded as `inputTokens`, marked `unsplit-total-as-input`); cache-read/cache-write are recorded `0`, never fabricated.
- New one-time notices (`aiPrefilter`, `cost-record`) surface once per clone.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.15.1 — audit remediation: progressive disclosure, wave checkpoint, mechanical gates

Patch release — the audit-remediation milestone, 15 issues, all merged CI-green.

- **Progressive disclosure**: solve-issue's worker-mode (#282), async-mode (#283), md-epic fan-out (#284) and solve-milestone's parallel-waves (#285) extracted into sibling reference docs loaded only when triggered; agent briefs trimmed (#286, #287, #288).
- **Reliability**: unified act→verify→retry gate loop (#290); `wave-state.json` checkpoint with trust-but-verify freshness for resumed runs (#291); triage stale-edge dedup — M fetches, not N×M (#293).
- **Mechanical enforcement**: `code-review-gate` hook — PRs must carry their `## Code Review` section (bash+pwsh twins, 22-case golden matrix) plus a macos-latest CI job running all six hooks under real /bin/bash 3.2 (#289); per-file ratcheted size budgets in CI, one-way tightening (#295).
- **Truth-ups**: one-time notices consolidated into `skills/notices.md` (#292); honesty pass on stale claims (#294); SendMessage/mid-run-redirect claims corrected and the background-wait pattern documented (#281).

## v1.15.0 — Parent-issue fan-out (md-epic)

**Theme:** A GitHub issue labeled `md-epic` can anchor a feature too big for one milestone: list the milestones in its body in build order, and `solve-issue` on that parent drives them one at a time. Entirely opt-in, gated on the label, off by default.

### ✨ A parent issue can anchor and drive a group of milestones

| Issue | PR | What |
|---|---|---|
| #266 Add the md-epic-order block parser | #271 | New `scripts/parse-md-epic-order.{sh,ps1}`: locates the fenced `md-epic-order` block, validates each `number:`/`title:` line, and reports the first malformed line by position. No `gh` calls, no network. |
| #267 Recognize `--driven` and suppress the DB-hazard interview | #272 | `solve-milestone` recognizes an internal `--driven` token, read the same way as `--worker` and `--async`. When present the DB-hazard interview degrades straight to its non-interactive sequential path — a driven run has no human to answer it. |
| #268 Detect md-epic parent issues and fan out over their milestones | #273 | `solve-issue` checks an issue's labels for `md-epic` before anything else. A parent parses the ordered milestone list from its body, resolves each entry to a real milestone, and drives them one at a time via `solve-milestone --driven`, resuming completed milestones and parking the parent itself when the list is missing or malformed. |
| #269 Add the human cherry-pick prompt for a directly-targeted milestone | #274 | `solve-milestone` on a milestone belonging to an `md-epic` parent asks first: build just this milestone, hand off to `solve-issue` on the parent, or pause. A driven run skips the prompt. |
| #270 Document md-epic in README, architecture, and this changelog | #275 | A `## Parent issues (md-epic)` README section and the mechanism writeup in `docs/architecture.md`. |

### Consumer notes (upgrading from v1.14.0)

- **Entirely opt-in.** No `md-epic` label anywhere in your repo means `solve-issue` and `solve-milestone` behave exactly as in v1.14.0.
- **New internal token `--driven`.** Like `--worker` and `--async`, recognized by string presence and never typed by a human; the parent-issue fan-out loop supplies it.
- **No schema changes** to `.milestone-config/driver.json`.
- **The other half ships later.** Creating a parent issue — applying the label, writing the ordered milestone list, linking each milestone's issues as sub-issues — is the feeder's and bootstrapper's job, specced separately and not yet built. Until then, hand-author a parent issue to the contract in `docs/architecture.md`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.14.0 — Parallel by default

**Theme:** `solve-milestone` builds a milestone's mutually-independent issues in parallel by default; a run-start barrier check drops to sequential only when something makes parallel unsafe. `maxParallelWorkers` tunes the width, and a one-time notice tells existing users the default changed.

### ✨ Parallel is the default, with a safety check instead of a flag

| Issue | PR | What |
|---|---|---|
| #250 Flip solve-milestone to parallel-by-default | #256 | The `--parallel` flag and the "in parallel" phrase are gone. Every run resolves the mode once through a barrier cascade: parallel unless `parallel: false`, a session permission the background workers need is not allow-listed, or the repo runs unit tests and the one-time test-database question is unanswered. A habit-typed `--parallel` is ignored. Wires the worker cap to `maxParallelWorkers` and adds the one-time notice. |
| #251 Add setup's conditional parallel question | #257 | First-run setup asks — only if the project runs unit tests — whether the test harness is isolated per worker, and records the answer as `parallel`. Projects with no unit tests are never asked and stay parallel. |
| #252 Document the parallel and maxParallelWorkers keys | #258 | Documents both keys, including the deliberately-opposite write rules: `parallel` always records an explicit yes/no, `maxParallelWorkers` follows the usual omit-for-default. |
| #253 Rewrite consumer-setup's parallel section | #259 | Rewrites the guide to the default-with-opt-out model, keeping the existing DB-isolation guidance. |
| #254 Reframe architecture.md's parallel-mode model | #260 | Reframes the section from opt-in to parallel-by-default with the barrier cascade. Worktree-fleet and serial-merge-tail mechanics are unchanged. |
| #255 Retire leftover --parallel wording | #261 | Retires the remaining `--parallel` framing across the other skills, scripts and docs. Wording only. |

### Consumer notes (upgrading from v1.13.0)

- **Parallel builds are the default.** To keep building one issue at a time, set `"parallel": false`. A passed `--parallel` is stripped and ignored.
- **New key `parallel` (boolean, optional).** Absent means "not yet decided": the run goes parallel unless the repo defines `unitTestCmd`, in which case the first run asks once whether the test harness is isolated per worker (a git worktree isolates files, not the DB) and records the answer here. `true` forces parallel; `false` forces sequential. A missing session permission still overrides `true` down to sequential.
- **New key `maxParallelWorkers` (integer, optional, default 4).** How many mutually-independent issues build at once within a Wave. An absent or invalid value falls back to 4.
- **Headless / CI runs** (`MILESTONE_DRIVER_NONINTERACTIVE=1`) never see the test-database prompt — they run sequentially with a loud note until the profile sets `"parallel": true`.
- **Schema change:** two new optional keys. An existing profile keeps working unchanged, and the first run seeds `parallel` when a test-DB hazard is present.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.13.0 — An optional coherence check before the final review

- **The driver auto-runs an optional coherence pass before the final code review.** When the milestone-coherence-reviewer companion plugin is installed, `solve-issue` dispatches it read-only over the built change just before the final `/code-review`, as a never-gating post-build pass. Wired via a new default-filled `coherenceReviewAgent` profile key (`milestone-coherence-reviewer:coherence-reviewer`); silently skipped when the companion is absent. It heals via follow-ups and never blocks or changes a merge. (#231)
- **Fixed: flaky `shell-tests (bash)` render-daemon teardown.** The idempotent-teardown case asserted process liveness the instant `stop` returned, racing the asynchronous SIGTERM teardown sends best-effort, so a loaded CI runner could flake (`teardown: … alive=1`) and block green merges. The test now polls for process death with a bounded window and escalates to a guarded SIGKILL only as a diagnostic — which still fails the test if `stop` did not reap. Mirrored into the PowerShell twin. Test-infra only. (#240)

## v1.12.2 — Triage now catches changes that leave existing users in the dark

_Released 2026-06-23._

**Theme:** When an issue affects existing users or their config, triage now requires a discovery path — a one-time notice, a re-run-setup prompt, or a documented upgrade note — and flags the issue when there is none.

### ✨ Triage insists every existing-user-facing change has a way to be found

| Issue | PR | What |
|---|---|---|
| #224 Add an existing-user discovery/migration-path criterion to the driver's triage-reviewer | #226 | Triage checks whether an issue affects an already-set-up install (a new config key, a changed default, behavior an existing install would not surface on its own) and, if so, looks for a discovery path. Missing path → **Advisory**, pointing at the driver's one-time-notice pattern; escalates to **Blocker** only when the gap makes the issue undeliverable. A brand-new feature an existing install cannot reach is exempt. "It's non-breaking" is not a reason to skip the check. |
| #223 Extend the 3 KEEP-IN-SYNC markers to name the feeder's setup + plan write sites | #225 | The three hand-synced git-ignore scratch blocks carry comments listing where their siblings live; those comments now also name the two copies the companion milestone-feeder plugin writes. Comment text only. |

### Consumer notes (upgrading from v1.12.1)

- **Triage flags an existing-user-facing change that nobody can discover.** No discovery path and existing users affected → **Advisory** (**Blocker** only when the gap makes the issue undeliverable). Exempt: a brand-new feature an existing install cannot reach. The check fires on impact to an already-set-up user, not on whether a change is breaking.
- **#223 is internal maintenance only** — comment text on the driver's hand-synced git-ignore blocks. Nothing visible in your runs.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.12.1 — A one-time nudge so upgraders find the new screenshots feature

_Released 2026-06-23._

**Theme:** v1.12.0's opt-in screenshots were discoverable only at first-time setup, so an existing install never heard about them. A one-time note now surfaces the feature in repos that have UI screens and no visual-capture config.

### ✨ Discoverability

| Issue | PR | What |
|---|---|---|
| #219 Add one-time "New in 1.12.0 — optional visual capture" discovery notice to solve-issue + solve-milestone, gitignore the marker | #220 | Prints a one-time, opt-in-framed note only when all three hold: no `visualCapture` block, the repo declares `uiSurfaceGlobs`, and this checkout has not shown the note. Then it drops a marker and stays quiet. Same pattern as the 1.4.0 preflight and 1.8.0 Trello notices; the marker lives only at `.milestone-config/visualcapture-notice`, with no legacy fallback. |

### Consumer notes (upgrading from v1.12.0)

- **You will see a one-time note if you have UI screens but no visual-capture config.** It prints at most once per checkout; a marker file then silences it. Skipping it changes nothing about your run.
- **Silent when there is nothing to say:** repos with a `visualCapture` block, repos declaring no `uiSurfaceGlobs`, and any checkout that already saw it.
- **New per-checkout marker `.milestone-config/visualcapture-notice`**, git-ignored via the committed scratch-ignore list.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.12.0 — Opt-in screenshots on your UI pull requests

_Released 2026-06-23._

**Theme:** The driver can boot your app, drive it to each changed screen, and attach the screenshots to a UI issue's PR. Strictly opt-in; the screenshots are evidence, never a gate — a UI issue is still never auto-merged, and any capture failure degrades to the manual-visual-test note.

### ✨ Opt-in visual capture for UI pull requests

| Issue | PR | What |
|---|---|---|
| #208 Render-daemon lifecycle seam — one-per-run app-server boot/reuse | #212 | New `scripts/render-daemon.{sh,ps1}`, called as `start` / `status` / `stop`. Reads `visualCapture.serverCmd` and `readyUrl` from the profile; `start` reuses a running daemon or boots the app server once per run, spawned detached in its own process group and polled at the ready URL before returning. `stop` is idempotent and tears down the whole process group, so a compound `cd app && npm run dev` command's children die with it. A stale or dead state file is cleaned and treated as down, never reused, never an error. State lives in `.milestone-config/.runtime/render-daemon.json`. Dependency-free beyond `jq` and `curl`/`wget`. |
| #209 Optional `visualCapture` profile block — schema, validation, setup tier | #213 | Documents the block in `docs/profile-schema.md`: `serverCmd`, `readyUrl`, `signInPath` (all three required when the block is present), plus optional `persona` (default `"super-admin"`), `viewports` (default desktop-only `1440×900`) and `appearances` (default `["light"]`). A block missing any required key is treated as absent and logged; absent = behavior byte-unchanged. Adds a Phase-2 Visual Capture tier to `setup`, surfacing only on a detected signal and writing a sparse object. |
| #210 Capture per-surface visual evidence for UI-issue PRs | #214 | Wires capture into `solve-issue` step 7. For a UI issue on a serial run with a complete block: boot the daemon, sign in through the test seam as the configured persona (substituting `{persona}` into `signInPath`), then drive Playwright MCP once per changed surface × viewport × appearance. Shots are pushed to an orphan `visual-review-assets` branch and embedded in one "👁️ Visual evidence" PR comment. Any failure posts the human-visual-test note instead, never fails the run, never auto-merges. Under parallel runs, capture defers to the serial merge tail — one fixed-port daemon cannot serve concurrent worktrees. |
| #211 Document the visualCapture seam; retire dead `screenshotCmd` prose | #215 | Removes the never-built `screenshotCmd` language from `docs/profile-schema.md` and `docs/consumer-setup.md`, adds a "One render daemon per run" section and the three invariants to `docs/architecture.md`. |

### Consumer notes (upgrading from v1.11.2)

- **New optional profile block `visualCapture`.** Leave it out and nothing changes — no app booted, no screenshot attempted, no new gate, prompt or error.
- **Opting in needs two things on your side:** a browser driven through Playwright MCP, and a seeded app server the driver can boot with a passwordless test sign-in. Declare it with `serverCmd`, `readyUrl` and `signInPath` (e.g. `/dev/sign_in/{persona}`). Optional `persona`, `viewports` and `appearances` default to super-admin, desktop-only, light. Skip any one required key and no block is written.
- **New artifact:** `scripts/render-daemon.{sh,ps1}`. Dependency-free beyond `jq` and `curl` or `wget`.
- **New `setup` tier:** on a detected visual-capture signal, setup walks you through the keys. No signal → skipped silently, like the E2E tier.
- **The three invariants.** (1) Opt-in: absent block = today's behavior exactly. (2) Never fails the run: any capture failure degrades to the human-visual-test note. (3) Never auto-merges a UI issue: the PR is still held open with `needs review`. Logic-only PRs still auto-merge on green; a repo with no `uiSurfaceGlobs` is unaffected.
- **Under parallel runs:** a UI-issue worker opens the PR and applies `needs review` but attaches no screenshots; the serial tail or you capture before merge. Injecting a per-worktree `PORT` opts capture back into the parallel phase.
- **No changes to any existing profile key.**

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.11.2 — Ground the release tail in docs, and make the auto-merge gate real

_Released 2026-06-23._

**Theme:** The human-owned release tail is now documented correctly — merge the release PR with `--merge`, never `--squash` — and this repo's own auto-merge gate runs a real test suite instead of merging on a vacuous green.

### 📖 Document the release tail correctly (`--merge`, not `--squash`)

| Issue | PR | What |
|---|---|---|
| #160 Adopt `--merge` for the release PR + harden the release tail | #204 | Rewrites `docs/consumer-setup.md § Releasing to your protected branch` into the complete ordered runbook. **Merge the integration→protected release PR with `--merge`, never `--squash`:** a squash puts a commit on the protected branch the integration branch never sees, so the two diverge and the next release PR conflicts (typically on `.claude-plugin/plugin.json` + `CHANGELOG.md`) — and a PR-locked integration branch cannot be resolved by pushing, forcing a history-only back-merge PR. The runbook spells out the ordered tail: open and merge the release PR with `--merge` **before** tagging → tag and cut the Release after the merge → close the milestone object → deploy, with the `--notes`-from-CHANGELOG form and `--generate-notes` as the no-CHANGELOG fallback. Two footguns are called out: a bare `gh release create` before the PR merges tags the old tip with wrong notes (happened in v1.9.2), and a PR-locked integration branch blocks direct pushes even for admins. `solve-milestone`'s 🔴 Your move recap and Final-summary next-step both name `--merge` and merge-before-tag. |

### 🧪 Make the driver's own auto-merge gate real

| Issue | PR | What |
|---|---|---|
| #179 Add a CI check on develop so auto-merge gates on tests | #205 | New `.github/workflows/ci.yml` runs the repo's shell test suites on every PR into `develop`: two `ubuntu-latest` jobs, `shell-tests (bash)` and `shell-tests (pwsh)`, covering `tests/extract-version.test` and `tests/ci-preflight-steps.test` on both legs. In the 1.11.0 wave the driver auto-merged on "green CI" with no required status check, so green was vacuous. |

### Consumer notes (upgrading from v1.11.1)

- **#160 is documentation only** — no change to how the driver runs. If you have been squash-merging integration→protected release PRs and hitting recurring conflicts on the next cut, that is the cause; switch to `--merge`. Full runbook in `docs/consumer-setup.md § Releasing to your protected branch`.
- **The CI workflow (#179) gates this repo's `develop` only.** It does not change the installed plugin or your repo; the suite still provisions a CI gate for your repo separately.
- 🔴 **Operator follow-up, not shipped here:** making the two checks *required* on `develop` is a one-time branch-protection step — adding `shell-tests (bash)` and `shell-tests (pwsh)` to the required-checks list via `gh api -X PUT .../branches/develop/protection`, preserving `enforce_admins`. The workflow makes the checks run; the protection PUT makes a red PR unmergeable.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.11.1 — Ground the builder in your project's house docs (anchored retrieval)

_Released 2026-06-22._

**Theme:** The driver's builder and both pre-build reviewers now receive the exact `.project/` sections an issue cites, pulled section by section rather than whole-file, so the plugin that writes the code reads the same source of truth as the one that planned it. Part 2 of 3 of the suite-wide grounding seam.

### ✨ Project-docs grounding via anchored retrieval

| Issue | PR | What |
|---|---|---|
| #183 Add the projectDocs profile key | #190 | New optional `projectDocs` key (default `.project/`, absent-means-default), mirroring the feeder; resolved at the solve-issue and triage profile reads. |
| #184 Ship the read-doc-section primitive | #191 | New dependency-free `scripts/read-doc-section.{sh,ps1}`: given a doc and a `## anchor`, prints only that section and **fails loud** (non-zero exit) on a missing or renamed anchor — never silent empty grounding. Ships a 5-case test twin. |
| #185 Resolve cited sections once in solve-issue | #192 | Resolves the issue's cited `.project/<doc>#<section>` anchors once, pulls a superset via the primitive, and passes the sections into the implementer brief. |
| #186 Resolve cited sections once in triage | #193 | Resolves the cited sections once per issue and passes the same sections into both reviewer briefs. |
| #187 Wire the implementer | #194 | The implementer's "What you receive" consumes the provided sections; Read/grep for additional anchors is retained. |
| #188 Wire the triage-reviewer | #195 | Grounds its five-criteria assessment in the provided sections; on-demand reads retained. |
| #189 Wire the design-reviewer | #196 | Grounds its assessment in the provided sections; on-demand reads retained. |

### 🧹 Scratch hygiene

| Issue | What |
|---|---|
| #199 Self-ignore per-clone scratch | Ships a committed `.milestone-config/.gitignore` that makes per-clone runtime scratch (`preflight-notice`, `trello-notice`, `triage-cache.json`, `tests-stamp`, plus `.runtime/` and `worktrees/`) git-invisible in any repo the plugin runs in, from the first write, with zero user setup — while tracked config (`driver.json`, `feeder.json`) stays tracked. The `tests-green` hook and the scratch-write steps in `solve-issue` / `solve-milestone` / `triage` self-heal the file when absent, so existing repos pick it up on their next run. |

### Consumer notes (upgrading from v1.11.0)

- **New optional profile key `projectDocs`** — where your standing docs live. Default `.project/`; set it only if they live elsewhere.
- **No grounding without docs.** No `.project/` directory, or an issue citing no `.project/#section` anchors, is a clean no-op with no error.
- **Anchored, never whole-file.** Grounding pulls only the cited `## sections` plus plausibly-relevant siblings, so per-dispatch token cost scales with cited-section size, not doc size. A drifted or renamed anchor is a loud failure, not silent empty grounding.
- **New artifact:** `scripts/read-doc-section.{sh,ps1}` (+ its test twin). Dependency-free.
- **Additive to existing gates.** No gate logic, five-criteria assessment or existing profile key changes.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.11.0 — Right model for each job: a stronger builder, leaner reviewers

_Released 2026-06-22._

**Theme:** Each built-in helper is pinned to the model tier that fits its job — the builder to the strong tier, the two pre-build reviewers to a leaner tier an A/B test showed catches the same blocking problems.

### ⚙️ Efficiency & quality — model assigned per helper

| Issue | PR | What |
|---|---|---|
| #173 Pin the implementer (code-writer) to the strong tier | #177 | The implementer is the only helper that writes production and test code. Its model frontmatter goes `inherit` → `opus`, so code is written by the strong tier regardless of the session model, cutting first-try misses against the ≤2-per-gate retry caps. Also bumps the plugin version to 1.11.0. |
| #176 Pin both pre-build reviewers to the mid tier | #178 | The triage-reviewer and design-reviewer only read and check an issue against five fixed criteria; they author nothing, and they are the highest-fan-out helpers in a run (~20× triage, ~17× design per milestone). Both go `inherit` → `sonnet`. The "genuinely unsure → escalate to Blocker" fail-safe is untouched. |

An A/B test recorded on the tracking issue compared models on the reviewers' real job: **Sonnet caught 9 / 9 blocking problems, identical to Opus at 9 / 9**, at the cost of one extra false flag on a clean issue. Haiku was disqualified — it missed a real blocking problem. The fixtures were text-only, so the repo-grounded dependency and pattern checks were not exercised; live-run Blocker recall is monitored and the reviewers revert to `inherit` if a real Blocker is ever missed.

### 📖 Docs — simpler install

The Quickstart leads with the **milestone-suite** install path — one marketplace cataloging all three milestone plugins — keeping the per-repo install as a labeled alternative. ([#167](https://github.com/kenmulford/milestone-driver/issues/167))

### Consumer notes (upgrading from v1.10.0)

- **No config or schema changes.** Only which model each built-in helper uses, plus a README edit.
- **The pins take effect on your next run.** The code-writer always uses the top tier; the two pre-build reviewers always use the mid tier, regardless of your session model.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.10.0 — Deterministic, tested semver extraction for milestone version detection

**Theme:** `solve-milestone` step 3 extracts the milestone version deterministically instead of by model judgment, and `preflightCmd` gains a `"github-ci"` sentinel that derives the local preflight gate from the repo's own CI.

### ✨ Deterministic version extraction

`scripts/extract-version.{sh,ps1}` — a behavior-identical pair driven by the shared golden matrix `tests/extract-version.cases.tsv` — extracts the version from the milestone title (description as fallback) and reports `none` / `ambiguous:<candidates>` on a miss. Step 3 maps that outcome against `versioning` to versioned / version-free / prompt, splitting the previously-identical `absent` and `true` semantics.

### ✨ CI-aware preflight (`preflightCmd: "github-ci"`)

`preflightCmd` accepts the reserved sentinel `"github-ci"` alongside its literal-command mode, deriving the preflight gate from the repo's GitHub Actions CI so a cheap CI check (e.g. `npm audit --omit=dev --audit-level=high`) is front-run locally before the PR instead of being hand-transcribed and forgotten. `scripts/ci-preflight-steps.{sh,ps1}` (golden matrix `tests/fixtures/ci-preflight/`) parses local `.github/workflows/*.yml` with a constrained line parser — no new tool dependency, no network — discovers the PR-gating workflows and emits each job's `run:` steps in order. `solve-issue` step 6.1 runs them through the existing tool-presence-guard → re-dispatch (cap 2) → park machinery. Skip rules drop `uses:` steps, secrets / services / deploy, `${{ }}`-interpolated and step-`if:` steps; `working-directory` is honored and `continue-on-error` steps never park. Coverage is logged ("mirrored N, skipped M"), and a PR-gating workflow yielding zero runnable steps is a visible warning, not a clean pass. One optional `ciWorkflow` key narrows discovery to a single workflow. Documented limitations, with CI as the authority: no `uses:` recursion, no `matrix` expansion, no `act` fidelity, GitHub Actions only. ([#162](https://github.com/kenmulford/milestone-driver/issues/162))

### Consumer notes

- **Behavior change (default `versioning`):** with `versioning` absent (the default), a milestone whose title has no parseable version now **silently runs version-free** instead of parsing by judgment or prompting. Confirm your milestone titles carry a version, or set `versioning: true` to be prompted on a miss.
- **No schema break:** `preflightCmd` keeps its literal-command and absent behavior byte-for-byte; `"github-ci"` and the optional `ciWorkflow` key are additive.

## v1.9.2 — Make the manual close-the-milestone step explicit

**Theme:** Closing the GitHub milestone object is named as a manual, human-only step, with the exact command surfaced — the driver closes a milestone's issues and authors the CHANGELOG, but never the milestone itself.

### ✨ Release-tail clarity

| Issue | PR | What |
|---|---|---|
| #153 make the manual close-the-milestone step explicit | #154 | Names the step in both blast-radius statements (`solve-milestone` SKILL + `docs/architecture.md`) and surfaces `gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed` in the 🔴 Your move block and the Final-summary next-step bullet. |

### Consumer notes (upgrading from v1.9.1)

- **Documentation only** — no change to how the driver runs. After it merges every issue and authors the CHANGELOG, the release tail tells you to close the GitHub milestone object (`gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed`).
- **No schema changes** to `.milestone-config/driver.json`.
- Milestone #16 also included #152, locking this repo's own `develop` to PR-only. Author-repo configuration with **no effect on the installed plugin**; noted for milestone completeness.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.9.1 — Finish the `.milestone-config/` relocation: the per-clone runtime markers move out of the repo root

**Theme:** v1.9.0 relocated the committed profile but left five per-clone runtime artifacts in the target repo root. All five now live under `.milestone-config/` without the redundant `milestone-driver-` prefix, read transitionally (new path first, legacy root as fallback) with the stale root file auto-cleaned on the first new write.

### ✨ Per-clone runtime markers move under `.milestone-config/`

| Issue | PR | What |
|---|---|---|
| #148 Relocate the 5 remaining root-litter runtime markers | #149 | Moves `tests-stamp`, `preflight-notice`, `trello-notice`, `triage-cache.json` and the `worktrees/` scratch dir under `.milestone-config/`. Each persistent marker is read new-path-first with a legacy-root fallback and writes only to the new path (`mkdir -p` / `New-Item -Force` before every write), removing the stale root file on the first new write. The `tests-green` hook skips the suite on either path's matching `branch:treeSHA` and clears both stamps on red; `triage` reads and writes the cache transitionally on both the `jq` and `ConvertFrom-Json` paths; the one-time notice markers stay silent if either marker exists; `worktrees/` is a pure path relocation. `.sh`/`.ps1` parity preserved. |

### Consumer notes (upgrading from v1.9.0)

- **No action required.** Each marker is read from `.milestone-config/<marker>` first and falls back transitionally to the legacy root `.milestone-driver-<marker>`, so an in-flight clone behaves identically: no duplicate notice, no triage-cache rebuild, no re-run of an already-green suite. On the first write to the new path the stale legacy file is removed.
- **No schema change.** These markers are per-clone and gitignored. `.gitignore` adds the five new paths and keeps the legacy root ignores (commented as transitional). The committed `.milestone-config/driver.json` is not ignored.
- **Leftover root files self-clean.** A pre-existing `.milestone-driver-tests-stamp` / `-preflight-notice` / `-trello-notice` / `-triage-cache.json` is read once as the fallback, then removed when the new-path file is first written. A leftover `.milestone-driver-worktrees/` dir is harmless — gitignored and unused; remove it at leisure.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.9.0 — Suite-wide `.milestone-config/` profile location

**Theme:** The driver profile moves to a canonical `<repo>/.milestone-config/driver.json`, read transitionally from the legacy root and auto-migrated on the first build — the precondition the sibling `milestone-feeder` assumes when it reads the driver's shared keys from the same directory.

### ✨ Canonical `.milestone-config/` profile location

| Issue | PR | What |
|---|---|---|
| #144 Resolve profile from `.milestone-config/driver.json` first | #145 | Resolves the profile from `.milestone-config/driver.json`, falling back transitionally to the legacy root `milestone-driver.json` so gates keep firing on un-migrated repos. All eight gate hooks do the two-step read and never mutate (`.ps1` uses the portable multi-arg `Join-Path`). Migration is commit-clean: `setup` and `solve-issue` perform the `git mv` (solve-issue on the feature branch at step 3.5, riding the issue PR), `solve-milestone` migrates via its first dispatched build, and `triage` stays read-only — it surfaces a "legacy profile detected" note but never moves the file. Idempotent everywhere; when both files exist `.milestone-config/driver.json` wins, with no overwrite and no deletion of the leftover root file. |

### Consumer notes (upgrading from v1.8.1)

- **No action required.** The legacy root `milestone-driver.json` is still read transitionally. On the first `setup` or `solve-issue` build a legacy root profile is `git mv`'d to `.milestone-config/driver.json`; `solve-milestone` migrates via its first dispatched build; `triage` is read-only. When both exist, `.milestone-config/driver.json` wins and the leftover root file is left for you to remove.
- **No schema change** — the keys are identical; only the location moved. Add new keys to `.milestone-config/driver.json` going forward.
- **PowerShell gate hooks** resolve the new path with the portable multi-arg `Join-Path` form (PowerShell 7+).

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.8.1 — Surface what the engine already does (and fix the capture defect underneath)

**Theme:** Existing capability made visible — fewer false triage Blockers, a triage cache that says when it skips, the wave trade-off surfaced at the setup decision point — on one reliability repair: the parallel barrier reads git/gh ground truth instead of a worker's free-text handback. Plus a cross-platform gate fix reported from the field.

### ✨ Surfacing the engine's existing behavior

| Issue | PR | What |
|---|---|---|
| #135 setup Integration tier | #141 | Adds an optional Integration tier to `/milestone-driver:setup` for `integrationGranularity`, an existing schema key that was never prompted, defaulting to `issue`. Choosing `wave` fires a non-blocking precondition prompt — is `preflightCmd` set? is `unitTestCmd` your full suite? — surfacing the "one red wave-PR CI blocks the whole Wave" trade-off where the choice is made. |
| #134 visible cache writes | #139 | The best-effort triage cache write no longer fails silently: the Bash path emits a stderr line on `jq`-absent and on write-fail, the PowerShell `catch` surfaces a `Write-Warning`, and the Step 5 output line gains a conditional `; cache write skipped this run` clause. The never-gating contract is unchanged. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #132 barrier reads ground truth | #137 | The parallel Phase 1 barrier re-derives each worker's terminal state from git/gh (the `solve-issue` step-3 probe) instead of trusting the worker's free-text handback, fixing the ~37% handback tail-drop and the hand-finish race. The handback is demoted to an optimization hint; the happy-path partition is byte-identical. |
| #133 fewer false triage Blockers | #138 | `triage-reviewer` downgrades a choice an established repo convention or sibling pattern already answers from Blocker to Advisory (criterion 2 carve-out plus a severity-rule row). Genuine ambiguity still escalates. |
| #136 Unix gate exec bit | #140 | `hooks/run-hook.cmd` was committed mode `100644`, so on macOS/Linux `/bin/sh -c` could not `exec` it (`EACCES`, exit 126) and **every PreToolUse gate was silently inert on Unix**. Now committed `0755`. Cross-platform safe. Reported and verified by @gcpeacock-npm. |

### Consumer notes (upgrading from v1.8.0)

- **🔴 macOS/Linux: all gates now actually run.** Before this release `hooks/run-hook.cmd` shipped non-executable, so every PreToolUse gate died with "Permission denied" and was silently inert. If you applied the `chmod +x` cache workaround, it is no longer needed.
- **New `setup` Integration tier** offers `integrationGranularity`. **No schema change** — the key already existed. Existing profiles need no migration.
- **Triage: fewer false Blockers.** Choices an established convention answers are Advisory rather than parking the issue.
- **Triage cache writes are observable** — a skipped or failed write prints a one-line warning. Still best-effort, never gating.
- **Parallel runs are more robust to dropped worker handbacks** — no happy-path change; the barrier no longer strands a built branch when a worker's final message drifts off-format.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.8.0 — Optional Trello board sync + auto-authored release notes

**Theme:** Milestone progress optionally mirrors to a Trello board — a card per milestone moving Queue → In Progress → In Review with a per-issue checklist — and the release notes author themselves at milestone completion. Both opt-in and best-effort; absent their config the loop is byte-unchanged.

### ✨ Trello integration (the #99–#104 family)

| Issue | PR | What |
|---|---|---|
| #99 Profile node + setup tier | #123 | New optional `integrations.trello` node (`boardId` required when present; `lists.queue`/`inProgress`/`inReview` default independently to `Queue`/`In Progress`/`In Review`) and an External integrations tier added last in `/milestone-driver:setup`, suppressed on auto-bootstrap. Presence enables; absence skips silently. |
| #100 trello-sync.md + run-start resolution | #125 | New `skills/solve-milestone/trello-sync.md`, read only when `integrations.trello` is present, holding all ten sync conventions: best-effort wrapper, availability probe, ensure-list auto-create, card-resolution order (back-link anchor → name-match → create), idempotent `<!-- trello: … -->` back-link, card state machine, and main-thread-only thread safety. Adds run-start card resolution (step 3.5) and the one-time upgrade notice (step 1.2). |
| #101 Phase 0 hooks | #128 | After triage, posts the triage summary (all-clear or gap table + Wave graph) as a card comment and moves Queue → In Progress when ≥1 issue is buildable; all-parked leaves the card in Queue with an explanatory comment. |
| #102 Loop hooks | #126 | Ticks the card's `#<n>` checklist item when an issue merges (visual-gate holds excluded), under both issue and wave granularity; in parallel runs, ticks fire in the serial merge tail on the main thread. Per-item best-effort. |
| #103 Finish hooks | #127 | Posts the final-summary card comment and moves In Progress → In Review only when zero open issues carry a blocker label; parks-remaining stays In Progress with a comment; a systemic halt posts the comment but does not move. |
| #104 Docs + dogfood | #129 | README "Optional integrations" paragraph and a `docs/consumer-setup.md` Trello section: the MCP prerequisite, both enablement paths, the tracked lifecycle, and the four known limitations. |

### ✨ Release automation

| Issue | PR | What |
|---|---|---|
| #121 Auto-author the CHANGELOG | #124 | When a `solve-milestone` run ends with every issue merged (no parks, no holds), the orchestrator authors a `## v<version>` CHANGELOG entry as a final doc-only PR to the integration branch: themed issue/PR/what tables, Consumer notes, and a Post-run audit trail. Idempotent (heading-prefix match), skips on any park or hold, headed by the milestone title in version-free mode. |

### Consumer notes (upgrading from 1.7.0)

- **New optional profile node `integrations.trello`.** Absent → every Trello step skips silently and the loop is byte-unchanged. Present → requires the `@delorenj/mcp-server-trello` MCP server loaded in your session; the plugin itself has no Trello dependency.
- **Enable it** by re-running `/milestone-driver:setup` (the External integrations tier is last; existing values pre-fill) or by hand-adding the node — see `docs/consumer-setup.md`.
- **New gitignored marker:** `.milestone-driver-trello-notice` at the repo root. Safe to delete.
- **Release notes author themselves.** A fully-completed run ends with a CHANGELOG PR; a run with any park or hold authors nothing.

### ⚖️ Post-run audit trail

Judgment-call PRs: none. All seven PRs (#123–#129) carry a `## Code Review` section with their findings and resolutions.

## v1.7.0 — Interactive background orchestration, scannable output, triage reuse

**Theme:** The orchestrator no longer clogs the main conversation line, the run is scannable at a glance, and repeat runs stop paying the re-triage tax. Includes the 1.7.1 triage-reuse milestone, rolled in.

### ✨ Background orchestration (the #89 family)

| Issue | PR | What |
|---|---|---|
| #89 Chunked background dispatch | #112 | The milestone loop dispatches each issue (sequential) or each Wave's workers (parallel) via `Agent(run_in_background: true)`. The main line stays interactive; the operator can redirect between chunks. Standalone `solve-issue` gains an opt-in `--async` token (pipeline unchanged except the version-bump confirm defaults to patch, logged as a judgment call). |
| #95 Permission pre-flight gate | #109 | Background subagents auto-deny any tool call that would prompt, so before the first background dispatch the gate verifies the union of readable `permissions.allow` layers (user + project + local) covers the pipeline's tool surface. Gap → 🔴 gap table + synchronous fallback. Workers convert mid-chunk auto-denies to parks. |
| #97 Main-line push notifications | #113 | One notification per event that matters: `⏸️ #N parked — <reason>`, `🌊 Wave N done` (suppressed on the final Wave), `🏁` run complete / `🚨` systemic halt. Main line only — `PushNotification` does not exist in subagent registries. |

### ✨ Scannable output

| Issue | PR | What |
|---|---|---|
| #96 Output spec | #105 | Shared icon legend plus three structured templates: run-start plan board, chunk-boundary status update, final results board. Tables and icons replace free-form narration at every reporting point. |
| #116 Output-spec polish | #118 | The six accepted findings from #105: PR-cell emit rule, one `[..]` placeholder convention, `🔴 Your move` casing, definition-before-reference section order, continuous example cast (#201/#202/#203) across all three templates. |

### ✨ Triage reuse (1.7.1, rolled in)

| Issue | PR | What |
|---|---|---|
| #106 Step-0 context handoff | #111 | `solve-issue` step 0 reuses the milestone run's Phase 0 triage result when the caller explicitly supplies it, eliminating the intra-run N+1 re-triage. Anything not explicitly supplied falls back to fresh single-issue triage. |
| #107 Per-issue result cache | #110 | `.milestone-driver-triage-cache.json` (gitignored) caches per-issue triage results keyed on change signals (labels, body edit time, comment count, milestone description). Unchanged issues skip agent dispatch across invocations; any change — including upstream edges closing unmerged — forces fresh triage. Absent or corrupt cache degrades to full re-triage. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #98 Milestone ID or name | #108 | `solve-milestone 10` and `solve-milestone "1.7.0"` both resolve: number-first for numeric input, paginated title lookup otherwise, fail-fast table of available milestones. |
| #114 Contradictory gate paragraphs | #117 | Deleted two stale STOP-flavored duplicates left by the 1.6.0 autonomy rewrite. Park-don't-prompt is the single directive at the red-suite cap and the `/code-review`-omission gate. |
| #115 Park-reason lookup + park anchor | #119 | Build-park comments open with the canonical `🔴 Parked — ` anchor, joining `🔴 Triage` and `🔴 Blocked`, making the final summary's park-reason lookup a pure prefix match (last matching comment, any run). No match → "park reason not recorded", never a guess. |

### Consumer notes (upgrading from 1.6.0)

- **Allowlist before backgrounding.** Background dispatch activates only when the pre-flight gate passes. Run `/fewer-permission-prompts` or allowlist your git/gh/test commands to enable it; otherwise runs fall back to synchronous behavior.
- **New gitignored artifact:** `.milestone-driver-triage-cache.json` at the repo root. Safe to delete at any time.
- **Park comments changed shape.** New parks open with `🔴 Parked — `. Issues parked by pre-1.7.0 runs report "park reason not recorded (pre-1.7.0 park format)" — read the issue directly for those.
- **No schema changes** to `milestone-driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: #105, #109, #110, #113, #119 (#115). Each carries its accepted findings and rationale in its Code Review section.
