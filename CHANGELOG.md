# Changelog

Release notes for milestone-driver. Versions before 1.7.0 are documented on the
[GitHub Releases page](https://github.com/kenmulford/milestone-driver/releases).

## v1.20.1 — the cache that shipped switched off

**Theme:** v1.20.0 moved the triage cache's mechanics out of the skill and into a script, and in doing so left the skill asking for something it also forbade. Step 6.5 said every cache entry must carry a `key` "computed at Step 2.5"; Step 2.5 said not to compute keys; and the script never printed one. There was no legal way to fill the field, so entries were written without a usable key and every later lookup missed — the cache was inert in the release that introduced it. It is fixed here, along with three consistency defects a post-release coherence review turned up. No new features, no behavior changes beyond the fix.

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #462 Triage Step 6.5 requires a cache key that Step 2.5 forbids deriving and triage-cache never prints | #473 | `write` takes the Step 2.5 GraphQL response as a fourth argument and stamps each entry's `key` from the same definition `lookup` compares against, so the orchestrator never handles a key at all |
| #466 Consumer docs say four gates where there are six, and three links point at a heading that moved | #469 | Four docs and one hook comment now name all six shipped gates in one order; three dead links to `README.md#the-layered-gating-model` repointed to `docs/architecture.md` |
| #464 The reviewer agent pair diverged | #470 | Restored the "you surface it, you don't design the fix" rule that #439 removed from `triage-reviewer.md` while leaving `design-reviewer.md`'s equivalent, plus five smaller divergences |
| #463 `docs/architecture.md:148` still calls implementation the sole concurrent stage | #467 | Corrected to match `:117` and `:145` after #400 pipelined build and review |

### Consumer notes (upgrading from v1.20.0)

- **Upgrade if you use `/milestone-driver:triage`.** On v1.20.0 the triage cache never matched, so every run re-dispatched a reviewer for every issue. Nothing was wrong with the results; you paid full triage cost each time. Existing `.milestone-config/triage-cache.json` files are **not** invalidated — the key format is unchanged, only which component computes it.
- `scripts/triage-cache.{sh,ps1}`'s `write` subcommand now takes **four** arguments (`write <repo-root> <entries.json> <graphql-response.json>`). If you call it directly, add the response file. An absent or unreadable response stays fail-open: entries are written without a key, exit 0, and those issues re-triage next run.
- Two ceilings in `scripts/check-size-budgets.{sh,ps1}` were raised by recorded decision, each narrowed to what its file needed: `agents/triage-reviewer.md` to 17000 bytes, `agents/design-reviewer.md` to 120 lines. The authorization is recorded in the script header and is spent — the next edit to either re-derives downward as usual.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

**Why a patch release at all.** v1.20.0 was tagged and released before #462 merged. The defect was known and its fix was built, reviewed and green on an open PR at the time of the release; it simply had not landed. Recorded rather than smoothed over.

**One issue was cut, not built.** #465 (eight tables of contents in four inconsistent shapes) was closed unbuilt: the inconsistency costs human navigation and nothing else, since the model loads the whole file regardless and cross-file references resolve against headings rather than TOC labels. Its body also records three errors of its own — it miscounted its own sites, cited `docs/plugin-features-reference.md` which has never existed in the tree or in git history, and declared an independence that was not true.

**Two defects found and filed, not fixed:** #468, three test runners use bash 4.3 namerefs and report `0 passed` under the `/bin/bash 3.2.57` macOS ships — invisible in CI, which runs the bash suite on Ubuntu and reserves its macOS leg for hooks; and #471, the bash and PowerShell legs sort labels in different orders outside the BMP, so an issue carrying both an emoji label and a `U+E000-FFFF` label gets a different cache key on each platform.

**The recurring failure of this milestone, now nine instances.** A fix that reads correctly and no longer does the same thing. #466 corrected a gate count in a sentence and left the table 45 lines below it still enumerating four. #464's ceiling raise would have collapsed the two rows `positional-desync` swaps to identical values, leaving the assertion passing while proving nothing. #464 also introduced a fresh false claim into the very comment block it was repairing. Every instance was caught by a reviewer opening the target and reading it. **None was caught by a gate**, because in every case the result is valid, passes every check, and reads like it means what it used to.

## v1.20.0 — anchor every citation, then cut 20%

**Theme:** Two things this plugin is built out of got fixed at once. A *citation* is a pointer this repo's skills and agent briefs write next to a claim, naming the file the claim comes from, so that a model reading the skill can go check it rather than take it on faith. v1.19.0 added a second way to write one: name the target by a quoted string of its own content (an *anchor*) instead of by line number, which a single edit above the target silently invalidates. This release finishes that migration and makes it stick. Every live line citation became an anchor or a heading reference, repo-root-relative paths became the only conforming way to write a path, 20 citations that already pointed at the wrong content were retargeted, and `scripts/check-citations.{sh,ps1}` now walks the whole tree in CI, so a reworded line fails the build instead of quietly misdirecting its next reader. The second half is size. Every skill and agent file the driver loads is context spent on every run, and this milestone set out to cut 20% of the bytes from the ones loaded most. It cut 7.3% of the bytes and 4.8% of the lines across the governed set. What did not come out, and why, is recorded in the audit trail. Two issues are not cleanup: a parallel run's reviews no longer wait for the wave's slowest build, and the two reviewer agents can no longer stop an issue because *they* were unsure.

### ✨ Anchors, and the gate that keeps them true

| Issue | PR | What |
|---|---|---|
| #431 convert every live line citation to an anchor | #447 | **152 line citations converted**, each verified by an actual resolver run: exit 0, exactly one `PRIMARY`, zero `MATCH`. Three line-style citations legitimately survive and are named in the PR: two are the deliberate illustrations inside the paragraph documenting the line form, one points into the sibling `milestone-feeder` repo where no local file can resolve. Review caught 15 defects, 13 of them anchors straddling a `**` emphasis boundary or truncated mid-phrase, and 2 of those 13 would have resolved to the wrong line at exit 0. |
| #430 retarget 20 broken line citations and drop 2 to a file that never existed | #444 | Every line number re-derived by opening the real target, not copied from the issue. Three targets improved on the issue's own numbers. Two rows turned out to have a wrong *claim* rather than a wrong line: three sites asserted a process-ID threshold of `<= 0` where `scripts/render-daemon.ps1:174` ships `<= 1`, so the sweep corrected the claim before #431 could freeze it into an anchor. Both citations to `docs/efficiency-grounding-plan.md` were dropped rather than re-sourced, because no doc in this repo makes that claim and inventing a target would fabricate a citation. |
| #429 declare repo-root-relative the only conforming citation base | #445 | `skills/citation-format.md` named all four citation forms but never said what directory a `path` resolves *from*, and no resolver does repo-root discovery, so a path resolved against whatever the working directory happened to be. Live citations used both bases: 132 repo-root, 47 that opened only from the citing file's own directory, 8 neither. Repo-root-relative is now the single conforming base for all four forms, with no fallback, and the PR records all three real outcomes of a mis-based path, including the one that opens the wrong file at exit 0. |
| #425 same-file citations must use a heading, not an anchor | #442 | An anchor citation written into the file it points at reproduces its anchor on its own line, so the citing line is itself a match. `scripts/resolve-citation.sh` labels the first occurrence `PRIMARY` with no citing-line exclusion, so a citation sitting above its target resolves to itself, at exit 0, with no error. The rule is now recorded: inside its own target file, write a heading citation, which cannot collide because a citing line is not a heading. Verified by probe, and the live same-file count re-measured at 0 by two people under three normalizations. |
| #432 gate `path (anchor)` citations repo-wide | #456 | The gate the rest of the milestone needed. `scripts/check-citations.{sh,ps1}` walks the tree, finds every `path (anchor)` citation and resolves it, byte-identically on both legs, wired into CI as a runner plus a run against this repo's real tree. Clean tree at merge: `SUMMARY ok=189 failed=0`. It catches both failure shapes: a broken anchor (one reworded line in `scripts/read-doc-section.sh` produces 5 FAIL records across 4 files) and an anchor that resolves but matches twice, which exit status alone cannot see. Review found 6 defects, 4 of them differences between the two legs that the golden fixtures structurally could not reach, including a FIFO that hung the PowerShell leg forever and a BOM that turned the same tree green on one leg and red on the other. |
| #427 govern `skills/citation-format.md` in the size ratchet | #448 | The shared citation reference loads into context like every other governed file, and eight files point readers at it, but it was absent from the size check, so it could grow unnoticed. Now governed at **230 lines / 13000 bytes**, re-derived from a fresh measure rather than the issue's pre-milestone figures, which were stale on four separate counts the PR tables. |
| #428 make the governed set one row per file so ceilings cannot drift | #446 | The size check's parity guard compared only the *lengths* of its three parallel arrays, so a **positional** desync kept all three lengths equal, measured files against other files' ceilings and still exited 0. The governed set is now one row per file, `<path> <lineCeiling> <byteCeiling>`, so a ceiling cannot be moved apart from its path. Written RED first: three new cases failed before the parse changed. Twin equivalence was reconstructed independently across 14 malformed row shapes, and the fail-loud behavior was proven by defeating it rather than asserted. |

### ✂️ The 20% cut

| Issue | PR | What |
|---|---|---|
| #433 trim `skills/solve-milestone/SKILL.md` | #449 | The largest governed file in the repo, loaded in full on every run. **664 lines / 76470 bytes → 602 / 65569, a 14.3% byte reduction** across 129 measured edits, every delta measured from the exact strings rather than estimated. Review caught two cuts that read as prose but were content: step 6.5 lost the literal `git show <commit>:CHANGELOG.md` that retrieves the file, and versioned mode lost the qualifier that lets a CHANGELOG heading with leading whitespace still match. Both restored. |
| #434 trim `skills/solve-issue/SKILL.md` | #450 | Loaded on every `solve-issue` invocation and every milestone-built issue. **394 / 76940 → 357 / 66075, a 14.1% reduction** across 64 hunks. A stale claim was corrected while trimming around it: the file said the plugin ships no code-review hook, and `hooks/code-review-gate.sh` exists. Review caught a park trigger that had survived only in a form conditioned on a label, which would have let a self-contradictory design pass ungated; restored unconditional. |
| #441 extract the triage cache mechanics to `scripts/triage-cache.{sh,ps1}` | #451 | The triage skill keeps a cache recording which issues it already triaged and what invalidates that record, and steps 2.5 and 6.5 re-taught its mechanics in prose on **every** invocation. Moving them to a reference file would have moved the bytes without cutting the cost, since both sections load every run; a script executes and costs zero context. `skills/triage/SKILL.md` goes **450 / 42130 → 368 / 36670**. Building it in RED found a real bug: PowerShell's `ConvertFrom-Json` coerces an ISO-8601 string to a `[datetime]`, so the composed cache key came out in culture format and produced a permanent 100% cache miss that still exits 0. |
| #435 trim `skills/triage/SKILL.md` | #452 | **368 / 36670 → 368 / 34789, a 5.1% reduction.** The yield is small because #441 had already harvested this file two hours earlier: three of the ten planned cuts sat inside the moved text and two survived only as reworded fragments. Every line number in the issue's cut table was stale, so each cut was re-located by its quoted text. Review scanned the surviving 34789 bytes independently and found 579 further cuttable bytes; they were left, because the residual is exact commands, two agent return contracts, a JSON shape and two measured findings. |
| #436 trim `skills/solve-milestone/parallel-waves.md` | #453 | Read in full on every run that does not hit a barrier, since parallel is the default. At 315 bytes per line it was the densest file in the governed set against a median near 100. **205 / 64827 → 186 / 58981, a 9.0% reduction**, and the only issue in the cut whose byte and line targets both cleared. The issue's own cut table over-quoted by 460 bytes, making its target unreachable as written; the gap was closed with four cuts found outside the plan, and all 17 removed spans were traced to a surviving statement or classified as rationale. |
| #437 trim the user-facing trio | #454 | `skills/setup/SKILL.md`, `skills/notices.md` and `skills/output-style.md`: three reference files with no owning skill folder, all loaded in full on every run of their caller. **620 / 54565 → 601 / 47894, a 12.2% reduction.** Review caught the milestone's sharpest defect: the largest cut in `notices.md` removed each notice's own literal marker-writing command in favor of a generic template that does not compose, because all eight marker values already carry the `.milestone-config/` prefix. The composed `touch` would have failed, no marker written, and **every one-time notice would have re-printed on every run, forever.** Fixed and all eight verified empirically by running the composed command and stat-ing the result. |
| #438 trim the four conditionally-loaded reference files | #457 | `trello-sync.md`, `milestone-granularity.md`, `async-mode.md` and `md-epic-fanout.md`. **625 / 59707 → 621 / 55475, a 7.1% reduction**, and this is what cleared the milestone's last ratchet failure: `milestone-granularity.md` had been 342 bytes over its ceiling since #431, because anchors are longer than the line numbers they replaced and that file holds more citations into `parallel-waves.md` than any other. Six passages were reduced to pointers and every target was read and quoted first. One requested cut was refused with evidence, because the caller does not state what the cut text states and what it does state contradicts it. |
| #439 trim the three agent briefs, and fix `implementer.md`'s return-shape examples | #455 | Each brief loads in full every time its agent is dispatched. `design-reviewer.md` 15721 → 13929 (11.4%), `triage-reviewer.md` 16356 → 14216 (13.1%), `implementer.md` 14614 → 14147 (3.2%). The fix half: two examples in `agents/implementer.md` taught return tokens the consumer cannot parse, `PAUSE` where `skills/solve-issue/SKILL.md` matches `PAUSED-FOR-APPROVAL` and `STOP` where it matches `STATUS: STOPPED`. All eleven Blocker-producing rules were re-probed by literal substring and confirmed intact, because a criterion surviving with a changed scope word is worse than a missing one: it looks intact. |

### 🔧 Behavior and correctness

| Issue | PR | What |
|---|---|---|
| #400 pipeline Phase 1, removing the Stage A to Stage B barrier | #459 | A parallel `solve-milestone` run built a wave's issues concurrently, waited for all of them, then reviewed them concurrently. Every issue's review therefore waited on the slowest build in the wave. Each issue's reviewer now dispatches the moment that issue's own implementer returns and clears its gates, with `maxParallelWorkers` becoming **one shared in-flight counter spanning build and review**, allocated by a four-row ladder. Measured against #400's own timings, wall clock is identical and structurally so, because the reviews pulled forward exactly offset the delayed build. What changes is that a fast issue frees its slot and opens its PR immediately: at cap 2, one issue's PR opens at t=11 instead of t=40. Four review rounds found 9 defects in the ladder, every one invisible to all four gates and all 26 test suites, including a single-issue wave that finished its review and then stalled forever with the work uncommitted. |
| #440 gate the reviewer-state Blocker paths behind a source set | #458 | Before building an issue, `triage` dispatches a reviewer agent that either clears the issue or raises a **Blocker**, which stops the issue, posts a comment, applies a label and waits for a human. Across ten-plus consumer repos that fired on 50-70% of a milestone's issues. `agents/triage-reviewer.md` produced a Blocker from twelve places; **seven test a property of the issue, five tested a property of the reviewer** ("I am unsure", "a convention probably exists", "I could not ground this"), and only one path required the reviewer to have looked anywhere first. Those five now require a completed search over an explicit source set, derived per agent from what that agent's brief actually receives. `agents/design-reviewer.md` carried all five near-verbatim and was fixed in the same pass. Twelve issues recorded as parked in this repo were re-classified against the new rules: 12/12 still park, every one for an issue-traceable reason. |
| #408 correct the `--driven` analogy at `solve-milestone` step 3.6 | #443 | `skills/solve-milestone/SKILL.md` asserted at one line that a halt never fires under `--driven` and stated the opposite 33 lines later. Whichever an implementer read first won, and the wrong branch leads to deleting a live guard or writing fan-out code that waits on a prompt no human will answer. The analogy is inverted in place; the authoritative line is provably byte-unchanged and the file is line-count neutral, so all 56 inbound citations still resolve. |

### Consumer notes (upgrading from v1.19.0)

- **Nothing breaks, and there is nothing to do on upgrade.** No schema changes to `.milestone-config/driver.json`. No key was added, removed, renamed or re-defaulted. Every invocation token behaves as it did in v1.19.0.
- **New artifacts:** `scripts/check-citations.{sh,ps1}` (a CI gate) and `scripts/triage-cache.{sh,ps1}` (a runtime primitive the triage skill calls), each with its test twin, cases table and fixtures under `tests/`.
- **CI grows three steps per leg**, six total: the `triage-cache` runner, the `check-citations` runner, and one run of `check-citations` against this repo's real tree.
- **The gate verifies exactly one citation form.** `scripts/check-citations.{sh,ps1}` resolves `path (anchor)` citations. The other three forms are **counted and reported `UNVERIFIED`, not checked**, so `failed=0` says nothing about them. On this repo today the gate reports `ok=194 failed=0` with `unverified=81`, split 57 `path#Heading`, 21 `path § Heading`, 3 `path:line`. Two acceptance criteria were formally dropped to ship it; see the audit trail.
- **The gate skips six trees**, each emitted as an `EXCLUDED` record with its skip count, including `.milestone-config/worktrees/` and `.milestone-feeder/`. Those are other checkouts and a sibling plugin's scratch, not this repo.
- **`.gitattributes` now pins `*.md` to `eol=lf`.** Governed markdown was the last text class still on `text=auto`, so a checkout with `core.autocrlf=true` added a byte per line and failed the size gate on two agent files a contributor had never touched.
- **A parallel `solve-milestone` run now reviews as it goes (#400).** `parallel` and `maxParallelWorkers` keep their names, shapes and defaults, so no profile needs an edit. What changes is what the cap counts: it is now one number covering build leaves and review leaves together, rather than a separate allowance per stage. Total wall clock is unchanged; a fast issue's PR opens as soon as that issue is done instead of after the whole wave.
- **Triage should stop parking issues on its own uncertainty (#440).** A reviewer can still raise a Blocker on anything recorded in the issue, unchanged. It can no longer raise one for being unsure without having exhausted a named set of sources first, and a found, cited convention whose soundness it cannot certify is now **Advisory**, not a Blocker. Nothing to configure. Expect fewer parks in repos with thin `.project/` docs, which is where the removed paths fired hardest.
- **Contributors to this repo: the ceiling rule is `actual × 1.05`, not `target × 1.05`**, and the line axis gained a minimum-headroom floor mirroring the byte axis's 500-byte rounding. Consumers of the plugin are unaffected; the ratchet governs this repo's own skill and agent files.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none. No PR in milestone #37 carries the `judgment call` label; the divergences below were never flagged that way, which is why they are recorded here. All 18 issues merged and closed, zero parked.

**The 20% target was not met on any file, and the honest aggregate is 7.3% of bytes and 4.8% of lines.** Measured across the whole governed set as it stands, all 15 files, from the milestone's base commit `c379bb3` to the end-of-milestone pass: **427611 → 396568 bytes, 3479 → 3313 lines**. The line axis is the harsher of the two and the one worth reading against a 20% target. The best single file is `skills/triage/SKILL.md` at 17.0% net, and that is an extraction plus a trim rather than a trim alone. Per-issue byte yields ran from 3.0% (`trello-sync.md`) to 15.2% (`notices.md`). Four files moved the other way and all four are accounted for above: `parallel-waves.md` grew 4.6% because #400 added a scheduler; both reviewer briefs grew because #440 added the source sets; and `skills/citation-format.md` grew **9536 → 12060 bytes (171 → 219 lines)**, which is two real outcomes rather than a rounding artifact. #427 brought a previously ungoverned file under the ratchet mid-milestone, so the set got larger by acquiring a file rather than by any file bloating, and #431's anchors cost bytes because an anchor is longer than the line number it replaces. A milestone that spends bytes to buy citation durability, inside a milestone whose other half is spending them down, is the trade this release made on purpose. The reason the target was missed is the same in every PR: the residual is rules, degradation branches, literal commands, measured findings and citations, and this repo's own rule is that concision cuts prose and never content (`skills/output-style.md`). Several targets were also unreachable as written. Several were derived from pre-milestone baselines that #431's anchor conversion had already moved, one issue's cut table over-quoted its own plan by 460 bytes, and `notices.md` was required to both add a 380-byte table of contents and land under a limit it overshot by 622.

**#432 shipped with two acceptance criteria formally dropped**, by an explicit scope decision recorded in the PR and in both script headers rather than skipped quietly. The issue's locked spec produced **26 FAIL records against correct citations** on a clean tree. Dropped: (1) resolving `path#Heading` and `path § Heading`, because a heading matcher wired into this walk produced 23 FAIL records against 23 correct citations, 13 of them GitHub-slug headings, 8 markdown link targets that are not citations at all, and 2 headings holding backticks a backtick-delimited token cannot bound; (2) a syntactic same-file rule, because every skill file in this repo is named `SKILL.md`, so a basename comparison flagged 3 cross-file citations as same-file. Same-file citations are instead caught by match count, since a citing line reproduces its own anchor. So the gate verifies that every `path (anchor)` citation resolves to exactly one line in a file inside the walked set, and verifies nothing about the other three forms.

**#400's slot-allocation order contradicted a recorded decision, and both records now stand.** `docs/briefs/2026-07-31-post-alienation-followups.md`, under `## Decision 1: the concurrency cap. SETTLED.`, records build-first as settled in an interview with the repo owner on **2026-07-30**: when a slot frees, an implementer takes it before a waiting reviewer. #400's acceptance criterion 2 says the opposite. **The repo owner re-ratified review-first on 2026-08-06**, and the brief is marked superseded **in place**: a block quote added under the heading, nothing deleted or rewritten, scoping the supersede to the two slot-preference statements, naming the new rule and its date, and flagging that the brief's "documented as strictly per-stage in three places" is now false in all three. Shipping two contradictory "settled" rules was the defect; which one won is settled.

**The ceiling rule is `actual × 1.05`, not `target × 1.05`.** `scripts/check-size-budgets.sh` has recorded since #399 that ceilings only go down, that each starts at the governed file's actual count plus roughly 5% headroom, and that a byte ceiling rounds up to the next 500 bytes. Several issue bodies in this milestone instead assume `target × 1.05` and record specific numbers from it: #438 records eight such numbers and, because its targets were not met, applying them would have failed three files. #435's instruction to hold a line ceiling and #439's recorded 14000-byte figure were both invalid for the same reason, and #439's would have re-blocked the very issue #439 existed to unblock. Every trim and extraction issue therefore stripped its own ceiling edit and deferred it, so the ceilings were re-derived once at the end against measured actuals: **5 line ceilings and 10 byte ceilings lowered, 8 rows derived above their current value and every one held.** That end pass also added a **line-axis minimum-headroom floor**, because the byte axis's 500-byte rounding had no line-side equivalent and `actual × 1.05` grants a 33-line file only 2 lines of room, which one ordinary bullet would trip.

**Two defects this milestone introduced and then caught in the end pass.** The citation gate walked the driver's own scratch worktrees under `.milestone-config/worktrees/`, where a worktree's own `tests/fixtures/` resolves to a path matching no repo-relative exclusion prefix. Measured with two worktrees live, that was **58 FAIL records from deliberately-broken fixture anchors on a tree whose tracked files were clean**, and it went red only for the person running the driver, never in CI. And governed `*.md` was never pinned to `eol=lf`, so a Windows clone with `core.autocrlf=true` gained a byte per line and **failed the size gate on two agent files a contributor had not touched**. Both are fixed in the end-of-milestone pass.

Four known follow-ups, none filed as issues yet:

- **Three test runners use bash 4.3 namerefs and cannot run under real `/bin/bash 3.2.57`**, which is the shell macOS ships and which several PRs in this milestone verified against deliberately. `tests/build-file-index.test.sh:30`, `tests/extract-version.test.sh:19` and `tests/parse-md-epic-order.test.sh:24` each declare `local -n _arr="$2"`.
- **`skills/solve-milestone/milestone-granularity.md` documents a pre-clean-guard placement its caller contradicts.** It says the guard runs in Before-starting, after the precondition checks and before Phase 0 triage. `skills/solve-milestone/SKILL.md:195` cuts the milestone branch inside the issue loop, after Phase 0. #438 refused a cut that would have deleted the only statement of the Before-starting placement and left the contradicting one standing.
- **`agents/design-reviewer.md` criterion 3 reads as "found pattern → never Blocker"**, which conflicts with its own rendered-outcome row for a found pattern that still renders badly at realistic volumes. Byte-identical on `origin/develop`, so #440 did not create it, but #440's severity-row widening makes that boundary load-bearing.
- **15 `path § Heading` citations use a bare filename** instead of the repo-root-relative path `skills/citation-format.md` requires, six in `skills/solve-milestone/SKILL.md` and nine in `skills/solve-milestone/parallel-waves.md`. The new gate does not cover them: it verifies only the `path (anchor)` form and reports `§` and `#` forms as unverified.

One process note worth recording. The same failure shape appeared in five separate issues this milestone: a literal replaced by a pointer, or a rule replaced by a restatement, that reads correctly and no longer does the same thing. Every instance was caught by review reading the target and quoting it, and none by a gate. `notices.md`'s marker template is the clearest case, because it would have silently re-printed every one-time notice on every run forever. The trims that landed cleanest are the ones whose PRs traced each removed span to a surviving statement before claiming the bytes.

## v1.19.0 — citation anchors

**Theme:** Citations in this repo pointed at source by line number, so any edit above a cited line silently invalidated them — nothing warned, the citation still looked well-formed, and it sent its reader to the wrong place. This release gives a citation a content anchor that survives line drift, ships a resolver that fails loud when an anchor is gone, and wires that resolution into triage and solve-issue so a subagent never reasons from a citation that has moved. Existing `path:line` and `path:start-end` citations stay fully valid to write; no evidence slot requires an anchor, and none was changed to require one.

### ✨ Citation anchors

| Issue | PR | What |
|---|---|---|
| #416 Define the citation format in `skills/citation-format.md` | #420 | New shared reference naming all four citation forms in live use, defining `path (anchor)` in full — the parse rule, literal-string resolution, what marks text as a citation at all, and the fail-closed rule for an anchor that is present but not found. |
| #417 Ship the resolve-citation twin pair with its test twin | #421 | Dependency-free bash + PowerShell 7 resolver reporting every literal-substring occurrence of an anchor as TAB records, fail-closed on every error path, with a 21-case golden-matrix runner per leg wired into CI. |
| #418 Resolve source citations before dispatch | #422 | Resolve-once blocks in `solve-issue` and `triage` that resolve an issue's citations via the resolver and thread the resolved table into the subagent briefs they compose, so no subagent re-derives a citation and a drifted anchor fails loud. |
| #380 triage-reviewer's Completeness criterion covers edit-site coverage | #419 | The triage reviewer now sweeps for restated edit sites instead of confirming only the ones it was handed, returning every unenumerated site as one `missing-criteria` gap. |

### Consumer notes (upgrading from v1.18.0)

- **No schema changes** to `.milestone-config/driver.json`.
- **Nothing breaks.** `path:line` and `path:start-end` citations remain valid to write and resolve exactly as before. The anchor form is additive.
- **New artifacts:** `scripts/resolve-citation.{sh,ps1}` (a runtime primitive, not a CI gate — it returns records at exit 0 and never fails a build), `tests/resolve-citation.test.{sh,ps1}` with its cases table and fixtures, and `skills/citation-format.md`.
- **CI grows one step per leg.** `shell-tests-bash` and `shell-tests-pwsh` each run the new runner.
- **Citation anchors are literal strings, never parsed symbols.** Resolution is a case-sensitive, line-scoped substring search — not a regex, and not language-aware. Write the shortest string that uniquely names the region you mean.
- **Extraction is model judgment, not pattern matching.** A parenthetical following a path is not automatically a citation; two measured examples in this repo's own prose show what a regex gets wrong in both directions.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

Two calls worth recording. `skills/triage/SKILL.md` finished at **41934/42000 bytes — 66 bytes of headroom**; the next change touching it needs a ceiling decision. And `tests/resolve-citation.test.ps1` asserts with `[string]::Equals(…, Ordinal)`, deliberately diverging from all eight sibling pwsh runners' bare `-eq`, because that operator is case-insensitive and culture-sensitive and the issue required exact assertion; migrating the house idiom is a separate sweep.

## v1.18.0 — milestone-scoped branching and dispatch topology

**Theme:** Two largely separate bodies of work. A whole milestone can now build on one local branch and reach the integration branch through a single push, a single PR, and a single CI run, for repos whose CI fires on a push to every branch and where one branch per issue exhausts the runners. And the worker layer is deleted: the orchestrator is the only session that fans out, every dispatched agent is a leaf at depth 1 where its completion notification actually arrives, and an issue that falls outside the barrier partition is now named and recovered rather than disappearing with no label, no comment, and no notification. The two halves meet in one place: both govern `scripts/check-size-budgets.{sh,ps1}`, and the one line-ceiling raise the second half needed was recorded under the Decision-Log convention the first half set.

### ✨ Milestone-scoped branching

| Issue | PR | What |
|---|---|---|
| #368 add `milestone-granularity.md` with the branch model and local integration mechanics | #386 | New `skills/solve-milestone/milestone-granularity.md` (157 lines, governed at ceiling 165 in `scripts/check-size-budgets.{sh,ps1}`) holds the mechanism: the branch model, the local `git merge --squash` fold that both the sequential loop and the parallel merge tail run, and the integration commit whose `Issue: #<n>` trailer carries that issue's Decision Log and Code Review block. Issue branches keep their `issue/<n>-<slug>` name but are cut from the milestone branch and never pushed. Read only when granularity resolves to `"milestone"`; missing under that granularity it halts the run rather than degrading to `"issue"`, which would restore the per-issue push the key was set to remove. |
| #371 add the milestone-end sequence and the red-CI handler | #388 | The milestone-end sequence replaces `solve-milestone` steps 6.6 to 6.8: commit the CHANGELOG onto the milestone branch (no second PR), push once, open one PR into `integrationBranch`, merge on green, then close each issue with its own `gh issue close` call, because `Closes #n` fires only on a merge into the repository's default branch. Red CI on that PR is run-scoped, neither a per-issue park nor a systemic halt: label the PR `needs review`, name every issue on the branch in one 🔴 line, preserve the branch, close nothing. |
| #376 add the `visualHold` milestone-PR gate and carve out architecture invariant 3 | #394 | `visualHold` decides whether the single milestone PR waits for human UI sign-off, resolved through a first-match-wins table whose indeterminate-diff row holds. `docs/architecture.md` invariant 3, "never auto-merge a UI issue", gets an explicit carve-out instead of a silent weakening: under `"milestone"` the hold moves up from the per-issue PR to the milestone PR, and the only thing that merges it is an operator writing `visualHold: false` by hand. |
| #374 make milestone-branch creation resume-safe against a leftover branch | #392 | Until the milestone-end push, the milestone branch is the only copy of every issue folded in so far, so a resumed run must never re-cut it. Four legs, first match wins: cold cuts fresh; provably safe (0 commits ahead, or a merged PR for the branch) clears and re-cuts; carries-work attaches instead of deleting; ambiguous or a failed probe preserves the branch and halts. Already-pushed is deliberately absent from the discard-safe set the worker-branch guard uses. |
| #379 make `solve-issue` granularity-aware: branch base, commit trailer, suppressed push/PR/merge, resume probe | #390 | Under `"milestone"`, `solve-issue` cuts its issue branch from the milestone branch, writes the extended commit trailer, suppresses its own push, PR, and merge, and answers "is this issue already integrated?" from `git log <milestone-branch> --grep='^Issue: #<n>$'` rather than `gh pr list` and `git ls-remote`, which read remote state that does not yet exist on this path. `async-mode.md` follows. |
| #372 add the milestone branch as `parallel-waves`' third merge target | #389 | `parallel-waves.md` already parameterized its merge target, so the milestone branch becomes that parameter's third value. The worktree base becomes `<base>` in place of a hardcoded `integrationBranch`, so parallel workers cut from the milestone branch under `"milestone"` and behave exactly as before under the other two values. |
| #375 wire milestone granularity into `solve-milestone` SKILL.md | #393 | `integrationGranularity` and `visualHold` both resolve once at run start and are held for the whole run, alongside the pre-clean guard call site, the fold step in the loop, and the milestone-end handoff. Resolution is fail-open: an out-of-enum granularity degrades to `"issue"` with a logged line, a non-boolean `visualHold` degrades toward holding. Nothing re-resolves mid-run. |
| #377 add `integrationGranularity: "milestone"` and `visualHold` to the profile schema | #381 | `docs/profile-schema.md` gains the third enum value and the `visualHold` row, both optional and both omit-the-default, plus two notes: why `"wave"` does not solve the push-per-issue problem, and what each `visualHold` state does. |
| #370 offer milestone granularity in the setup skill's Integration tier | #387 | The setup interview now offers the third value. Choosing `"milestone"` fires its own non-blocking precondition prompt carrying both CI branch-filter forms, and suppresses the wave prompt. Write rule unchanged: omit the key for `"issue"`, write the value only when the user picks it. |
| #369 document milestone granularity for consumers | #385 | `docs/architecture.md` gains a milestone-granularity section, `docs/consumer-setup.md` gains the walkthrough (both branch-filter forms, why one event may not set `branches` and `branches-ignore` together, the red-CI behavior, the `visualHold` table), and the README's granularity sentence names all three values. |
| #366 record the milestone-granularity design spec | #383 | Committed at `docs/superpowers/specs/2026-07-30-milestone-branch-granularity-design.md`, so the branch model, the trailer contract, and the rejected alternatives are readable without walking the PR trail. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #378 record a size-budget ceiling raise in the PR Decision Log | #382 | The ceiling-ratchet header in `scripts/check-size-budgets.{sh,ps1}` said a raise needs a recorded decision "on the issue that grows the file". Every PR body already carries a Decision Log (`.project/conventions.md:38`), which is where the record belongs and where a reviewer looks for it. Both script twins now say so; enforcement behavior is unchanged. |

### 🧵 Dispatch topology: every dispatched agent is a leaf

| Issue | PR | What |
|---|---|---|
| #361 delete the worker layer: the orchestrator fans out by stage, dispatched agents are leaves | #401 | The core fix. Worker mode, the `--worker` token, Delta 3's structured handback, and `--async`'s dispatch contract are all deleted. Phase 1 now dispatches by stage: concurrent implementer leaves, a barrier, concurrent reviewer leaves, then an unbarriered per-issue tail the orchestrator runs on its own line. A dispatched agent that dispatches a child seats that child at depth 2, where the completion notification never arrives and the parent's turn ends for good with the work uncommitted; keeping every agent at depth 1 is what removes that. `docs/architecture.md` gained a `## Dispatch topology` section so the invariant has one home the skills and agents can cite instead of nine restatements. |
| #362 name the `abandoned` bucket, recover once, then park | #405 | The barrier partition ran on two buckets, `built-green` and `parked`, which are not exhaustive: an issue in neither vanished with no label, no comment, and no notification. An auto-denied background leaf, context exhaustion, and a killed run all produce exactly that shape. `abandoned` is now a named third bucket with its own probe legs (no PR, no pushed branch carrying commits ahead of the base, no park label), resolved by a recover-once ladder, cap 1, inside the same pass, so every dispatched issue leaves step 9 as `built-green` or `parked`. |
| #363 `ort` auto-resolves non-adjacent same-file edits, not non-overlapping ones | #403 | The difference is load-bearing: two edits on directly adjacent lines conflict, while one unchanged line between them merges clean. So any file with a single shared append point (a changelog table, a barrel export, a DI registration list) conflicts by construction under concurrency, which the old wording implied it would not. Swapped at five sites. The two sites where the orchestrator makes the park call also now carry the fact that this shape sits *within* bounded auto-resolve rather than triggering a park, because the swap on its own would have made the merge tail park more often than it did before. |
| #365 tell every dispatched agent to namespace its own scratch | #404 | Concurrent agents shared one scratchpad directory and overwrote each other's probe files, producing a false cross-worktree-write alarm that cost a full verification cycle to disprove. One rule in two byte-identical families: seven dispatch sites state what the brief must carry, three agent contracts state what the agent honors. Write scratch only under a path named for that issue or that agent, and report what a probe printed rather than writing a probe file to read back later. |
| #364 caveat the version-free CHANGELOG idempotency check against heading suffixes | #398 | Step 6.1 decides whether this release already has a CHANGELOG section. Version-free mode compares the whole line for equality, so a heading carrying `(partial)`, `(in progress)`, or a date is not equal to `## <milestone title>`: the match fails, the check reports no existing entry, and steps 6.2 to 6.5 prepend a duplicate section beside the one already there. Versioned mode is immune because its prefix ends in a trailing space. The caveat is appended byte-identically at both sites and the strict equality rule deliberately stands, since widening the match is what would let `## Q3 Hardening` satisfy a milestone titled `Q3`. |
| #397 re-derive 18 stale cross-file citations | #409 | Cross-file citations into `skills/solve-milestone/SKILL.md` drifted as that file grew. The issue title's "5 of 8" does not reconcile with the PR's own evidence table: measured on `db24a40^`, `md-epic-fanout.md` carried 8 full-form `solve-milestone/SKILL.md:NNN` citations plus 3 bare `:NNN` shorthand the table never examined, and all 11 changed in the merge. Across the whole set 18 were re-derived, 6 into heading anchors (`skills/solve-milestone/SKILL.md § Final summary`) that survive a line shift entirely and 12 into corrected line numbers. Only 8 of those 12 had no heading to anchor to, their targets sitting inside a 116-line heading-free stretch; the other 4 point into sections that do have one (`## Autonomy`, `## Final summary`, `## Run-complete notification`). |
| #399 the size-budget ratchet governs bytes as well as lines | #410 | Counting lines only meant prose appended to an existing line grew real context cost while the check reported zero movement: PR #398 added 1,052 bytes to `skills/solve-milestone/SKILL.md` at a flat 664 lines and the ratchet saw nothing, and three later merges in this same milestone added another 3,818 bytes across the governed set the same way. Both twins now hold a per-file byte ceiling beside the line ceiling, rounded up to the next 500 bytes so the 14 derivations stay arithmetic rather than 14 judgment calls. Lines stay as an independent second ceiling, because this repo's `file:line` citations pay a cost for line growth that no byte count can express. |

### Consumer notes (upgrading from v1.17.0)

- **Nothing to do on upgrade.** The default is still `"issue"`, and the `"issue"` and `"wave"` paths are byte-unchanged. A profile that does not set `integrationGranularity` behaves exactly as it did in v1.17.0.
- **Schema change, both parts optional.** `.milestone-config/driver.json` gained one new enum value and one new key: `integrationGranularity` now accepts `"milestone"` alongside `"issue"` and `"wave"`, and `visualHold` is new. Both default to today's behavior when absent, so an existing profile stays valid untouched.
- **Opting in, and its one prereq.** Set `{ "integrationGranularity": "milestone" }`, then filter your own push-triggered workflows to ignore the `milestone-*` prefix: `branches-ignore: ['milestone-*']`, or `branches: ['**', '!milestone-*']` with the negation last. Set one form per event, never both. Skip the filter and the single milestone-end push starts your push workflow while the PR run rebuilds the same commit, so the assembled milestone is paid for twice.
- **The `milestone-` branch prefix is a stable, externally-consumed contract.** Consumer CI filters are written against it, so it will not be renamed out from under them.
- **`visualHold` is the one UI sign-off.** Absent (the default) holds the milestone PR for a human whenever the branch's diff against `integrationBranch` touched a `uiSurfaceGlobs` path, and holds when that diff cannot be read. `visualHold: false` is the sole override and auto-merges on green CI. A non-boolean value holds, with a logged note. There is no `--no-visual-hold` invocation token, and the key is read only under `"milestone"` granularity.
- **One convention change reaches every granularity.** Raising a governed file's size-budget ceiling is now recorded in the Decision Log of the PR that grows the file, not on the issue (#378). Contributors to this repo will notice; consumers of the plugin are unaffected.
- **`parallel` and `maxParallelWorkers` keep their names and defaults, but "how wide" now counts something different (#361).** Concurrency moved from one worker per issue to one leaf agent per issue **per stage**: your `solve-milestone` run builds the Wave's issues concurrently, barriers, reviews them concurrently, and then runs the gates, the version bump, the commit, and the PR from the main line. `parallel` still decides *whether*, `maxParallelWorkers` still decides *how wide* (default 4), and neither key changes shape, so an existing profile needs no edit. What changes is what a value of, say, 8 buys you: 8 concurrent implementers, then 8 concurrent reviewers, rather than 8 issues each running their own full pipeline. The `--worker` and `--async` invocation tokens are gone and inert respectively; neither was ever typed by a human. Every gate, cap, and park behaves as before, `/code-review` included.
- **An issue whose agent dies mid-build is recovered instead of lost (#362).** A parallel Wave used to sort its dispatched issues into built-green and parked, which left no bucket for an issue whose agent was auto-denied a tool, ran out of context, or was killed: that issue got no label, no comment, and no line in the run summary. It is now classified `abandoned`, rebuilt once from its existing worktree, and parked `blocked` with its branch and worktree preserved only if the retry also fails. Nothing to configure; you will see one retry where you previously saw silence.
- **`merge=union` now has a documented answer (#363).** `docs/consumer-setup.md` says why not to reach for it when two concurrent issues collide on one shared append point: union never reports a conflict, so it removes the only signal you would get, and it interleaves multi-line changes into structurally broken output, such as a table row landing below the trailing bullets. The collision itself is now correctly described as within bounded auto-resolve, so the merge tail parks no more often than before.
- **Contributors to this repo gain a second axis a PR can fail on (#399).** `scripts/check-size-budgets.{sh,ps1}` checks a byte ceiling alongside the line ceiling for every governed file, so appending prose to an existing line can now fail the ratchet at zero line delta. Raising either ceiling still takes a recorded decision in the Decision Log of the PR that grows the file. Consumers of the plugin are unaffected: the ratchet governs this repo's own skill and agent files.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none. No PR in either milestone carries the `judgment call` label; the acceptance-criteria divergences below were never flagged that way, which is why they are recorded here.

**One of the four defects the v1.17.0 audit trail left open is closed here.** That release recorded "Workers strand on nested sub-agent dispatch" among the defects **not** fixed there, rooted in [anthropics/claude-code#75043](https://github.com/anthropics/claude-code/issues/75043): a nested child runs async regardless of `run_in_background`, and its completion notification misdelivers to the main conversation. #361 is that fix. Nothing waits on a notification at depth 2 any more because nothing runs at depth 2: the orchestrator is the only session that fans out, and `docs/architecture.md` → `## Dispatch topology` records the invariant. The other three stay open: the ceiling-table edit that breaks the golden-matrix fixtures with no review lens catching it, the repo's own `domainSkills` going unconsulted while its skills are edited, and `${CLAUDE_PLUGIN_ROOT}` prefixing having no machine enforcement.

**#400 is parked `needs design`, not built.** It proposed removing the Stage A to Stage B barrier so a fast issue's review need not wait on the slowest build in the Wave. #362 landed after #400 was filed and made that barrier load-bearing: step 9 partitions the whole dispatched set, and the barrier is the only thing guaranteeing every implementer has already returned when it runs. An issue still mid-build presents the identical ground truth the `abandoned` classifier keys on (no PR, no pushed branch, no park label), so removing the barrier would classify a healthy in-flight issue as abandoned and dispatch a second implementer into a worktree the first is still writing to. Two decisions are owed before it can build: a per-issue readiness gate step 9 can trust in place of the barrier, and a combined `maxParallelWorkers` accounting rule once builds and reviews overlap.

**Three issues diverged from what was literally prescribed for them, two from their own acceptance criteria and one from a convention this repo's `domainSkills` set.** Recorded here because a reader diffing an issue against its PR would otherwise find an unexplained gap:

- **#365 dropped two sites its ACs named and added one they did not.** One dropped site was a single arm of an in-scope/park-trigger pair. The other is recorded as a no-op, because once #361 retired `--async` that step composes no brief for the rule to ride on. The shipped shape is seven dispatch sites plus three agent contracts, matched to where a dispatch actually happens rather than to the enumeration the issue was written against.
- **#362's AC 5 was already satisfied by #361** and is recorded as a no-op rather than re-implemented. AC 6 was not: its *cited lines* no longer carried any worker claim, but its live form did, since `docs/architecture.md` still asserted "Those two are not exhaustive" against the new three-bucket partition. That line was amended. Separately, the empty-diff no-change outcome is now decided at step 6 instead of step 9: no artifact distinguishes a leaf that finished with nothing to do from one that died before writing anything, so step 9 cannot tell them apart and step 6, which knows what it dispatched and why, can.
- **#399 rejected the word-count convention `superpowers:writing-skills` prescribes**, and recorded a measurement rather than a preference: word count splits on whitespace, so `scripts/check-size-budgets.ps1` scores 1 word for 30 bytes, and the governed files are dense with exactly that path, flag, and backtick token shape.

Process defects surfaced during this run:

- **A mid-flight redirect to a subagent never arrived, and the agent's final report described the retracted instruction as applied.** During #362 the orchestrator sent a correction to a running leaf. The agent had already completed, shipped the retracted version, and then reported it as the corrected one. It was caught only by reading the changed files instead of trusting the report. This is the same failure class the milestone fixes, arriving through a channel the milestone does not cover: a correction travelling parent to child is exactly as unreliable as a completion notification travelling child to parent, and only the second direction was in scope. Derive-from-artifacts already covers the outcome; nothing yet covers the instruction.
- **The `/code-review` gate hook caught the orchestrator skipping review** on #399, the one issue here that adds new logic to an executable script rather than editing a data table inside one: #361 and #362 both touch `scripts/check-size-budgets.{sh,ps1}`, but only to drop a governed file and to move a ceiling, while #399 adds byte counting, the three-way length-parity guard, and a fifth golden case. `hooks/code-review-gate.sh` denies a `gh pr create` whose body carries no `## Code Review` section, and that is what fired. Worth recording because the hook exists precisely as a mechanical backstop against a gate the orchestrator would otherwise police itself on, and a backstop that has never fired cannot be told apart from one that does not work.

Follow-ups filed, not fixed here:

- **#402, #406, #407**: three issues covering four more stale cross-file citations of the kind #397 re-derived, #407 naming two of them, plus the durable fix #407 proposes, which is to check heading anchors rather than line numbers.
- **#408**: `skills/solve-milestone/SKILL.md:66` contradicts `:99` on whether the purely-numeric-title halt fires under `--driven`.
- **A twin divergence, deferred.** A governed file that is present but unreadable records `OK` and exits 0 on the bash side of `check-size-budgets`, while the PowerShell twin throws. The two disagree and neither is obviously right; deciding which way both should go was out of scope for #399.

## v1.17.0 — reviewer grounding & output style

**Theme:** Reviewer claims now have a defined research path and a scope-honesty rule, and every GitHub-facing shape this plugin writes has one governing prose contract with an evidence slot.

### ✨ Reviewer grounding & output style

| Issue | PR | What |
|---|---|---|
| #336 wire `domainSkills` into the triage/design reviewer input contract | #344 | v1.16.1's "verify it is a genuine best practice" sub-step shipped with no defined research mechanism. Wires the existing `domainSkills` key through `skills/triage/SKILL.md` Step 1 + both Step 3 brief lists and both reviewer agents' "What you receive", as **one ordered step** — framework docs first, then `domainSkills`, then repo patterns — matching `agents/implementer.md:41-44`. No new profile key. |
| #341 consolidate the 4× output-style block; add a GitHub prose contract | #345 | New `skills/output-style.md` (91 lines) is the single source: the terminal-vs-GitHub surface split, the prose contract, when prose is the correct form, and evidence slots for 10 shapes. Four skill blocks become pointers; three agents' `## Communication style` reconcile and declare themselves narrow overrides. Injected at **two** resolve-once blocks — `solve-issue` → implementer, `triage` → both reviewers. |
| #342 require reviewer claims to state their verification scope | #346 | Both Rigor gates enforced only that a citation *exists*. A correct `file:line` attached to an un-enumerated quantifier ("all three controllers", "14 of 15") passed every bullet. Two bullets per reviewer agent add the scope rule and "identical code is not identical exposure". No new GAPS `type`, no new schema field. |

### 🔧 Fixes

Found by a `plugin-dev:skill-reviewer` pass over all four skills after the three issues above merged.

| Issue | PR | What |
|---|---|---|
| #348 reference-file reads used bare relative paths | #357 | 20 reads of plugin-shipped files, plus every `scripts/…` invocation, resolved against the consumer repo's CWD where none of them exist. Three had absent-to-no-op branches, so #341's prose contract silently never reached any agent outside this repo. All now prefixed with `${CLAUDE_PLUGIN_ROOT}` per `plugin-dev:plugin-structure` § Portable Path References. Verified against a real consumer repo. |
| #349 setup described `domainSkills` as implementer-only | #352 | #336 broadened the consumer set but left `skills/setup/SKILL.md:45,142` describing the old truth — in the one place a user decides whether to configure the key at all. Line-neutral copy fix. |
| #350 run-complete notification nested inside a skipped step | #353 | `Run-complete notification` and `Run-end cost record` lived under `#### 6.9`, inside the CHANGELOG step the systemic-halt path is told to skip entirely. A halt lost both the 🚨 signal and the whole cost record. Promoted to a top-level section; four cross-references corrected. |
| #351 setup never interviewed `uiSurfaceGlobs` | #355 | The key appeared zero times in the setup interview, so a user could configure the full `visualCapture` block and get design-lens review, the visual gate, and visual capture all silently off. Adds the tier before Visual Capture, gates that tier on both its Phase-1 signal and this key, and ships a one-time notice for existing installs. |
| #354 CI-red CHANGELOG branch jumped past step 6.9 | #356 | `#### 6.8`'s CI-red branch jumped forward past `#### 6.9`, skipping its required "Held open (CI red)" Your-move append. One line. |

### Consumer notes (upgrading from v1.16.1)

- **New shipped file:** `skills/output-style.md`, governed in `scripts/check-size-budgets.{sh,ps1}` at ceiling 100 (currently 91). The four `## Output style` blocks in `setup` / `triage` / `solve-issue` / `solve-milestone` are now pointers to it.
- **`setup` now asks for `uiSurfaceGlobs`.** Existing profiles are unaffected and keep working; a one-time notice points out the gap on the next run. Without the key, design-lens review, the visual-review gate, and visual capture stay off — that was already true and is now stated at the point of decision.
- **Plugin-shipped paths in skill text now carry `${CLAUDE_PLUGIN_ROOT}`.** Consumer-repo paths (`.milestone-config/`, `.project/`, `sourceGlobs` matches) are unchanged and still resolve against your repo.
- **Behavior change, no config change.** Reviewers verify a convention is a genuine framework idiom against an ordered path (docs → `domainSkills` → repo patterns) rather than their own assumption, and may no longer assert a count or universal quantifier they did not enumerate. Expect scope qualifications like "confirmed at `x.rb:201`; 2 other call sites not individually checked" in triage comments and `to_clear` fields.
- **`domainSkills` is optional and degrades cleanly** — absent, the step is skipped; it never makes the docs check optional. All three injected inputs (`.project/` sections, file index, prose contract) are additive grounding whose absence is never a STOP condition.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

Process defects surfaced during this run and are **not** fixed here:

- **Workers strand on nested sub-agent dispatch.** Four of eight workers ended their turn waiting on a child that never re-invoked them; completed work sat uncommitted until the orchestrator probed the worktree. Root cause is upstream, not this plugin: [anthropics/claude-code#75043](https://github.com/anthropics/claude-code/issues/75043) — nested children run async regardless of `run_in_background`, and their completion notifications misdeliver to the main conversation. The workarounds that held were doing the review in-turn with no dispatch at all, or polling the artifact's file content rather than the child's transcript. `skills/solve-issue/SKILL.md` step 6.1 documents neither.
- **A ceiling-table edit can break the golden-matrix fixtures with no review lens catching it.** #341 added `skills/output-style.md` to `scripts/check-size-budgets.*` and broke `tests/check-size-budgets.test.sh` (0/3). Five `/code-review` lenses cleared it; the coherence pass caught it.
- **The repo's own `domainSkills` were not consulted while authoring changes to its skills.** `.milestone-config/driver.json` declares `plugin-dev:*` and `superpowers:writing-skills`; neither informed the issues filed from the skill-review pass. #348's first draft consequently proposed a mechanism that mis-resolved all of its own paths, and was rewritten against `plugin-dev:plugin-structure` before building. Three findings from that guidance remain unfiled: `skills/solve-milestone/SKILL.md` is 658 lines against a documented 500-line limit, all four frontmatter descriptions summarize workflow (which `writing-skills` shows causes agents to skip the skill body), and no skill edit in this milestone was preceded by the baseline pressure test its Iron Law requires.
- **`${CLAUDE_PLUGIN_ROOT}` prefixing has no machine enforcement.** #348 placed 28 substrings by hand; nothing stops the next skill edit from reintroducing a bare path. A CI grep was scoped as a follow-up rather than expanding #348.

## v1.16.1 — convention-search before parking as `needs design`

**Theme:** Before triage parks an issue as `needs design`, both reviewer agents must now actively search the existing codebase for a convention that answers the gap — and when they find a sound, idiomatic one, default to emulating it (cited) rather than recommending a new approach. A passive "note the convention if you happen to see it" check becomes a required search → verify-best-practice → emulate-or-park gate.

### ✨ Triage convention-search

| Issue | PR | What |
|---|---|---|
| #334 require a convention search before `needs design` | #335 | `triage-reviewer` criterion 2 (Buildability) and `design-reviewer` criteria 1 (Spec-sufficiency) & 3 (Pattern consistency) now require an active search of `sourceGlobs` / `uiSurfaceGlobs` plus the resolved `.project/` sections before emitting a `needs design` Blocker; a found, verified best-practice convention downgrades to an emulate-and-cite Advisory (cited at `file:line`), reserving the Blocker for a genuinely dry search or no conventional default. Severity tables and rigor gates updated in both agents; `skills/triage/SKILL.md` label routing unchanged. |

### Consumer notes (upgrading from v1.16.0)

- **Behavior refinement, no config change.** Triage now parks fewer issues as `needs design`: when an established, sound convention already answers an under-specified choice, it is recorded as an emulate-and-cite Advisory (cited at `file:line`) and the build proceeds, instead of parking. A genuinely dry search — no sound convention found — still parks exactly as before.
- Prose-only change to `agents/triage-reviewer.md` and `agents/design-reviewer.md`; the ungroundable "there is probably a convention" case is explicitly still a Blocker (not a pass).
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.16.0 — run-efficiency grounding

**Theme:** Cut cache-aware dollar cost and sharpen grounding on every driver run — a diff-scoped repo file-map injected into subagent briefs, an optional AI pre-filter over captured screenshots, and a per-run cache-aware cost record — extending existing mechanisms only, with no new persistent stores, daemons, or browser stacks.

### ✨ Run-efficiency grounding

| Issue | PR | What |
|---|---|---|
| #318 file-index resolver | #324 | New `scripts/build-file-index.{sh,ps1}` twin: a diff-scoped `path → purpose (+ callers/symbols)` index, grep-based, no new tool dependency, golden-matrix tested both legs. |
| #321 inject file index | #326 | The resolve-once dispatch block now injects that file index into the implementer brief alongside the `.project/` sections — additive grounding, no-op (no error) when the resolver is absent or fails. |
| #319 screenshot pre-filter | #323 | Optional `visualCapture.aiPrefilter` pass reads the captured PNGs and posts a per-surface/viewport/appearance verdict beside the "👁️ Visual evidence" comment. Pre-filter only — never a merge gate, never auto-merges a UI issue. |
| #320 cost-record writer | #325 | New `scripts/write-cost-record.{sh,ps1}` twin: writes one cache-aware dollar cost + token breakdown + wall-clock record to `.milestone-config/.runtime/`. Fail-open, non-gating; hardcoded rate snapshot, optional `provenanceNote`. |
| #322 emit cost record | #328 | `solve-issue` and `solve-milestone` emit that record at run-end (every terminal exit). Never gates a run; silent no-op when the writer or usage figures are absent. |

### Consumer notes (upgrading from v1.15.1)

- New **optional** profile sub-key `visualCapture.aiPrefilter` (default absent/`false` → skipped); sparse-write, byte-unchanged when absent.
- Two new **gitignored** per-run artifact kinds under `.milestone-config/.runtime/` (the file index is in-memory only; cost records are written there). No change to committed config.
- Cost figures are a deliberate **lower-bound** approximation: the framework surfaces only a per-dispatch token total (recorded as `inputTokens`, marked `unsplit-total-as-input` in the record's `rateSnapshot`); cache-read/cache-write are recorded `0`, never fabricated.
- New one-time notices (`aiPrefilter`, `cost-record`) surface once per clone.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.15.1 — audit remediation: progressive disclosure, wave checkpoint, mechanical gates

Patch release — the audit-remediation milestone (15 issues, all merged CI-green).

- **Progressive disclosure**: solve-issue's worker-mode (#282), async-mode (#283), md-epic fan-out (#284) and solve-milestone's parallel-waves (#285) extracted into sibling reference docs loaded only when triggered; agent briefs trimmed (#286, #287, #288)
- **Reliability**: unified act→verify→retry gate loop (#290); `wave-state.json` checkpoint with trust-but-verify freshness for resumed runs (#291); triage stale-edge dedup — M fetches, not N×M (#293)
- **Mechanical enforcement**: `code-review-gate` hook — PRs must carry their `## Code Review` section (bash+pwsh twins, 22-case golden matrix) plus a macos-latest CI job running all six hooks under real /bin/bash 3.2 (#289); per-file ratcheted size budgets in CI, one-way tightening (#295)
- **Truth-ups**: one-time notices consolidated into `skills/notices.md` (#292); honesty pass on stale claims (#294); SendMessage/mid-run-redirect claims corrected + background-wait pattern documented (#281)

## v1.15.0 — Parent-issue fan-out (md-epic)

**Theme:** A GitHub issue labeled `md-epic` can now anchor a feature that's too big for one milestone. List the milestones in the parent issue's body, in build order, and running `solve-issue` on that parent drives them one at a time. Running `solve-milestone` directly on one of those milestones now asks first whether you meant to build just that slice. This is entirely opt-in — driver-side support only, gated on a label, and off by default.

### ✨ A parent issue can now anchor and drive a group of milestones

| Issue | PR | What |
|---|---|---|
| #266 Add the md-epic-order block parser | #271 | Adds a deterministic parser (`scripts/parse-md-epic-order.{sh,ps1}`) for the ordered milestone list in a parent issue's body: it locates the fenced `md-epic-order` block, validates each `number:`/`title:` line, and reports the first malformed line by position. No `gh` calls, no network. |
| #267 Recognize `--driven` and suppress the DB-hazard interview | #272 | `solve-milestone` now recognizes an internal `--driven` token, read the same way as `--worker` and `--async`. When present, the DB-hazard interview degrades straight to its non-interactive sequential path instead of prompting, since a driven run has no human watching to answer it. |
| #268 Detect md-epic parent issues and fan out over their milestones | #273 | `solve-issue` now checks an issue's labels for `md-epic` before anything else. A parent issue takes a new path instead of building: it parses the ordered milestone list from its body, resolves each entry to a real milestone, and drives them one at a time via `solve-milestone --driven`, resuming already-completed milestones and parking the parent issue itself — not silently skipping — when the list is missing or malformed. |
| #269 Add the human cherry-pick prompt for a directly-targeted milestone | #274 | When you run `solve-milestone` directly on a milestone that turns out to belong to an `md-epic` parent, it now asks first: build just this milestone, hand off to `solve-issue` on the parent to drive the whole feature in order, or pause. A driven run (`--driven` present) skips this prompt entirely. |
| #270 Document md-epic in README, architecture, and this changelog | #275 | This entry, plus a `## Parent issues (md-epic)` section in the README and a full mechanism writeup in `docs/architecture.md`. |

### Consumer notes (upgrading from v1.14.0)

- **Entirely opt-in.** Nothing changes unless you label a GitHub issue `md-epic`. No `md-epic` label anywhere in your repo means `solve-issue` and `solve-milestone` behave exactly as they did in v1.14.0.
- **New internal token `--driven`.** Like `--worker` and `--async`, it's recognized by string presence and never typed by a human — the parent-issue fan-out loop supplies it when it drives a milestone on its own behalf.
- **No schema changes** to `.milestone-config/driver.json` — this release adds no new profile key.
- **The other half ships later.** Creating a parent issue — applying the `md-epic` label, writing the ordered milestone list, linking each milestone's issues as GitHub sub-issues — is the feeder's and bootstrapper's job, specced separately and not yet built. Until then, a parent issue must be hand-authored to the contract documented in `docs/architecture.md`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.14.0 — Parallel by default

**Theme:** `solve-milestone` now builds a milestone's mutually-independent issues in parallel **by default** — no flag to remember. A run-start barrier check quietly drops the run back to sequential only when something makes parallel unsafe (you've opted out, the session is missing a permission the background workers need, or a test-database question hasn't been answered yet). A new key lets you tune how many issues build at once, and a one-time notice tells existing users the default changed.

### ✨ Parallel is the default, with a safety check instead of a flag

| Issue | PR | What |
|---|---|---|
| #250 Flip solve-milestone to parallel-by-default | #256 | Parallel is now the default execution mode — the `--parallel` flag (and the "in parallel" phrase) is gone. Instead, at the start of every run the driver resolves the mode once through a barrier cascade: it goes **parallel** unless a barrier is present — you set `parallel: false`, the session hasn't allow-listed a tool the background workers need (a permission gap forces sequential), or your repo runs unit tests and the one-time test-database question hasn't been answered. A habit-typed `--parallel` is harmlessly ignored. This PR also wires the worker cap to the new `maxParallelWorkers` key and adds a one-time notice announcing the change. |
| #251 Add setup's conditional parallel question | #257 | The first-run setup now asks — **only if your project runs unit tests** — whether your test harness is isolated per worker so parallel builds are safe, and records your answer as the `parallel` key so you're not asked again. Projects with no unit tests are never asked and stay parallel by default. |
| #252 Document the parallel and maxParallelWorkers keys | #258 | Documents the two new profile keys in the profile schema, including the deliberately-opposite write rules (`parallel` always records an explicit yes/no; `maxParallelWorkers` follows the usual omit-for-default). |
| #253 Rewrite consumer-setup's parallel section | #259 | Rewrites the consumer-setup guide's parallel section to the default-with-opt-out model — the up-front test-database question, the `parallel: false` opt-out, the tunable worker cap — while keeping the existing DB-isolation guidance. |
| #254 Reframe architecture.md's parallel-mode model | #260 | Reframes the architecture doc's parallel-mode section from opt-in to parallel-by-default with the barrier cascade. The underlying worktree-fleet and serial-merge-tail mechanics are unchanged — only how the mode is entered. |
| #255 Retire leftover --parallel wording | #261 | Retires the remaining `--parallel` framing across the other skills, scripts, and docs so everything names the new default consistently. Wording only — no behavior change. |

### Consumer notes (upgrading from v1.13.0)

- **Parallel builds are now the default.** If you want to keep building one issue at a time, set `"parallel": false` in `.milestone-config/driver.json`. The old `--parallel` flag and the "in parallel" phrase are gone — if you still pass `--parallel`, it's harmlessly stripped and ignored (parallel is already the default).
- **New key `parallel` (boolean, optional).** Absent means "not yet decided": the run goes parallel *unless* your repo defines `unitTestCmd`, in which case the first run asks once whether your test harness is isolated per worker (parallel workers share your test database — a git worktree isolates files, not the DB) and records your answer here. `true` = force parallel; `false` = force sequential. A missing session permission still overrides `true` down to sequential.
- **New key `maxParallelWorkers` (integer, optional, default 4).** Tunes how many mutually-independent issues build at once within a Wave. Omit it to get 4; set it only to override. An absent or invalid value falls back to 4.
- **Headless / CI runs** (`MILESTONE_DRIVER_NONINTERACTIVE=1`) never see the test-database prompt — they run sequentially with a loud note until you set `"parallel": true` in the profile.
- **Schema change:** two new optional keys — `parallel` and `maxParallelWorkers` — are added to `.milestone-config/driver.json`. Both are optional; an existing profile keeps working unchanged, and the first run seeds `parallel` for you when a test-DB hazard is present.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.13.0 — An optional coherence check before the final review

- **The driver now auto-runs an optional coherence pass before the final code review.** When the milestone-coherence-reviewer companion plugin is installed, `solve-issue` dispatches it read-only over the built change just before the final `/code-review`, as a never-gating post-build coherence pass. It's wired via a new default-filled `coherenceReviewAgent` profile key (`milestone-coherence-reviewer:coherence-reviewer`) and is silently skipped when the companion is absent (absent-means-skip). It heals via follow-ups and never blocks or changes a merge. (#231)
- **Fixed: flaky `shell-tests (bash)` render-daemon teardown.** The `render-daemon` test's idempotent-teardown case asserted process liveness the instant `stop` returned, racing the asynchronous SIGTERM that teardown sends best-effort — so on a loaded CI runner the process could still be alive for a microsecond and the required check would flake (`teardown: ... alive=1`), blocking otherwise-green merges. The test now polls for actual process death with a bounded window and escalates to a guarded SIGKILL only as a diagnostic safety net (which still fails the test if `stop` didn't reap, so a real teardown regression can't hide). Mirrored into the PowerShell twin to keep the golden-matrix pair behavior-identical. Test-infra only — no behavior change to the daemon. (#240)

## v1.12.2 — Triage now catches changes that leave existing users in the dark

_Released 2026-06-23._

**Theme:** Before the driver builds an issue, it triages it for gaps. Until now, that review could wave through an issue that quietly added a new config key, flipped a default, or introduced behavior an existing install would never stumble across on its own — leaving everyone who already set the driver up with no way to discover the change. This release closes that hole: when an issue actually affects existing users or their config, triage now looks for a discovery path — a one-time notice, a "re-run setup" prompt, or a documented upgrade note — and flags the issue if there's none. It's the same discovery-path principle the milestone-feeder already enforced on its own path, now made the default on the driver's main review. A second, internal-only touch-up keeps the driver's hand-maintained git-ignore scratch blocks pointing at all their sibling copies — including the two that live in the companion milestone-feeder plugin.

### ✨ Triage now insists every existing-user-facing change has a way to be found

| Issue | PR | What |
|---|---|---|
| #224 Add an existing-user discovery/migration-path criterion to the driver's triage-reviewer | #226 | When the driver triages an issue, it now checks one more thing: if the issue affects people who already have the driver set up — a new config key, a changed default, a behavior an existing install wouldn't surface on its own — it looks for a way those users would actually find out about the change. That discovery path can be a one-time notice (the pattern the driver already ships), a prompt to re-run setup, or a documented upgrade note. If the issue affects existing users and offers none of those, triage flags it. It's an **Advisory** by default — it tells you the gap and points you at the driver's own one-time-notice pattern as the fix — and only escalates to a **Blocker** when the missing discovery path makes the issue impossible to deliver. A brand-new feature an existing install can't even reach yet is exempt: the check only fires when an already-set-up user would genuinely be affected. "It's non-breaking" on its own isn't a reason to skip it. |
| #223 Extend the 3 KEEP-IN-SYNC markers to name the feeder's setup + plan write sites | #225 | The driver keeps three identical little git-ignore scratch blocks in sync by hand, and each one carries a comment listing where its siblings live so a maintainer editing one is pointed at the rest. Those comments now also name the two matching copies that the companion milestone-feeder plugin writes (at its setup and plan sites), so editing any one copy points you at every copy across both plugins. Comment text only — no behavior change, and nothing a consumer ever sees. |

### Consumer notes (upgrading from v1.12.1)

- **Triage now flags an existing-user-facing change that nobody can discover.** When the driver triages an issue that adds a config key, changes a default, or introduces behavior an existing install wouldn't surface on its own, it checks for a discovery path — a one-time notice, a re-run-setup prompt, or a documented upgrade note. No discovery path and existing users are affected → the issue is flagged as an **Advisory** (escalating to a **Blocker** only if the gap makes the issue un-deliverable). **What's exempt:** a brand-new feature an existing install can't even reach yet. The check fires on impact to an already-set-up user, not on whether a change is "breaking" — "non-breaking" alone doesn't skip it.
- **#223 is internal maintenance only.** It updates the cross-reference comments on the driver's hand-synced git-ignore scratch blocks so they name the matching copies in the companion milestone-feeder plugin. Comment text only — no behavior change, nothing visible in your runs.
- **No schema changes** to `.milestone-config/driver.json` — neither change adds or alters a profile key.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.12.1 — A one-time nudge so upgraders find the new screenshots feature

_Released 2026-06-23._

**Theme:** Last release added opt-in screenshots on your UI pull requests — but you'd only ever hear about it the first time you set the driver up. If you already had the driver configured and just pulled the update, the feature was there and you'd never know. This release fixes that: the next time the driver runs in a repo that has UI screens but no visual-capture set up yet, it prints a short, one-time note telling you the feature exists and how to turn it on. It's a nudge, not a prompt — you can ignore it and nothing changes. It shows at most once per checkout, then never again, and it stays completely silent for repos that already turned visual capture on or that have no UI to screenshot in the first place.

### ✨ Discoverability

| Issue | PR | What |
|---|---|---|
| #219 Add one-time "New in 1.12.0 — optional visual capture" discovery notice to solve-issue + solve-milestone, gitignore the marker | #220 | When the driver works an issue or a milestone, it now prints a one-time, opt-in-framed note pointing you at v1.12.0's optional screenshots — but only when all three are true: your profile has no `visualCapture` block yet, your repo *does* declare UI screens (`uiSurfaceGlobs`), and this checkout hasn't shown the note before. After it prints once, it drops a small marker file and stays quiet from then on. It's silent for repos that already configured visual capture and for repos with no UI surface at all. Same pattern as the existing one-time preflight (1.4.0) and Trello (1.8.0) notices; the marker lives only at `.milestone-config/visualcapture-notice`, with no older fallback location. |

### Consumer notes (upgrading from v1.12.0)

- **You'll see a one-time note if you have UI screens but haven't set up visual capture yet.** The next time the driver runs in such a repo, it tells you the optional screenshots feature exists and how to opt in. It prints at most once per checkout; after that a small marker file silences it for good. It's purely a heads-up — skip it and nothing about your run changes.
- **It stays silent when there's nothing to say:** repos that already have a `visualCapture` block, repos that declare no UI screens (`uiSurfaceGlobs`), and any checkout that already saw the note once.
- **New per-checkout marker file `.milestone-config/visualcapture-notice`** records that the note was shown. It's git-ignored (added to the committed scratch-ignore list), so it never shows up in your `git status` and never gets committed.
- **No schema changes** to `.milestone-config/driver.json` — purely a discovery notice; no new or changed profile keys.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.12.0 — Opt-in screenshots on your UI pull requests

_Released 2026-06-23._

**Theme:** When the driver finishes a UI issue, it holds the pull request open for you to look at the rendered screen yourself — code that passes its tests can still look wrong. Until now, "look at it yourself" meant you started the app, signed in, and navigated to the changed screen by hand. This release lets the driver do that legwork for you and attach the screenshots to the PR, so you open it and just *see* the change. It is strictly opt-in: you tell the driver how to boot your app once, and from then on UI PRs carry before-your-eyes evidence. Leave it unconfigured and nothing changes — no app is booted, no screenshot is taken, and the PR still waits for your manual look exactly as it does today. The screenshots are a convenience, never a gate: a UI issue is still never merged automatically, and if anything in the capture goes wrong the run quietly falls back to the "please test this by hand" note instead of failing.

### ✨ Opt-in visual capture for UI pull requests

| Issue | PR | What |
|---|---|---|
| #208 Render-daemon lifecycle seam — one-per-run app-server boot/reuse | #212 | New `scripts/render-daemon.{sh,ps1}` (a bash + PowerShell 7+ twin), called as `start | status | stop`. It reads `visualCapture.serverCmd` and `visualCapture.readyUrl` straight from your profile, and on `start` either reuses an already-running daemon or boots your app server **once per run** — spawned detached in its own process group, then polled at a `/health`-style ready URL until it answers before returning. `stop` is idempotent and tears down the whole process group (so a compound `cd app && npm run dev`-style command's children die with it, not just the wrapper); a stale or dead state file is cleaned and treated as down, never reused, never an error. State lives in `.milestone-config/.runtime/render-daemon.json`. Dependency-free beyond `jq` (already permitted) and `curl`/`wget` for the probe. CI-gated on both the bash and pwsh shell-test legs. |
| #209 Optional `visualCapture` profile block — schema, validation, setup tier | #213 | Documents the new optional `visualCapture` block in `docs/profile-schema.md` — keys `serverCmd`, `readyUrl`, `signInPath` (all three required when the block is present), plus optional `persona` (default `"super-admin"`), `viewports` (default desktop-only `{ "desktop": { "width": 1440, "height": 900 } }`), and `appearances` (default `["light"]`). Present-with-all-three-required = enabled; a block missing any required key is treated as absent and logged; **absent = behavior byte-unchanged** (absent-means-skip, the same convention as `unitTestCmd` / `integrations.trello`). Adds a Phase-2 **Visual Capture** tier to `setup` that surfaces only when a visual-capture signal is detected, prompts each key with its detected default and skip-consequence, and writes a sparse object (omitted optional keys resolve to defaults at runtime). |
| #210 Capture per-surface visual evidence for UI-issue PRs | #214 | Wires capture into `solve-issue` step 7. For a UI issue on a serial run with a complete `visualCapture` block, the driver boots the render daemon, signs in through your test sign-in seam as the configured persona (substituting `{persona}` into `signInPath`), and — for each surface the building agent reports it changed × each viewport × each appearance — drives **Playwright MCP** to capture a screenshot. The shots are pushed to an orphan `visual-review-assets` branch (so binary blobs never land on your integration branch) and embedded in a single **"👁️ Visual evidence"** PR comment. Hard degradation invariant: absent / incomplete block, or **any** failure along the way (daemon won't boot, sign-in fails, a screen won't render, push fails) → it posts the human-visual-test note instead, never fails the run, and never auto-merges a UI issue. Under `--parallel`, capture is deferred to the serial merge tail (one fixed-port daemon can't safely serve concurrent worktrees). |
| #211 Document the visualCapture seam; retire dead `screenshotCmd` prose | #215 | Removes the never-built, prose-only `screenshotCmd` render-capability language from `docs/profile-schema.md` and `docs/consumer-setup.md`, replacing it with the real `visualCapture` seam. Adds a "One render daemon per run" section and the **three invariants** to `docs/architecture.md`: (1) opt-in / byte-unchanged when absent, (2) never fail the run, (3) never auto-merge a UI issue. |

### Consumer notes (upgrading from v1.11.2)

- **New optional profile block `visualCapture`** in `.milestone-config/driver.json`. Leave it out and **nothing changes** — no app is booted, no screenshot is attempted, no new gate, no prompt, no error. Your UI PRs still open and wait for your manual visual test exactly as before. The feature is invisible until you opt in.
- **Opting in needs two things on your side:** a render capability (a browser driven through Playwright MCP) and a seeded/persona app server the driver can boot — a local instance of your app preloaded with test data and reachable via a passwordless test sign-in. You declare it with three required keys: `serverCmd` (the command that boots your test app server), `readyUrl` (a `/health`-style URL the driver polls until the server is up), and `signInPath` (your persona-templated test sign-in path, e.g. `/dev/sign_in/{persona}`). Optional `persona`, `viewports`, and `appearances` refine which persona, screen sizes, and light/dark appearances get captured; omit them and they default to super-admin, desktop-only, light. If you skip any one of the three required keys, no block is written — the gate just stays at PR-open-for-your-manual-test.
- **New artifact:** `scripts/render-daemon.{sh,ps1}` — boots your app server once per run and reuses it, then tears it down at run end. Dependency-free beyond `jq` (already required) and `curl` or `wget` for the ready probe.
- **New `setup` tier:** when you re-run `milestone-driver:setup` (or first-run bootstrap) and the repo shows a visual-capture signal, setup now offers a **Visual Capture** tier that walks you through the keys. No signal detected → the tier is skipped silently, just like the E2E tier.
- **The three invariants — what opting in can and can't do.** It can only *add* evidence; it can never change a run's outcome. (1) **Opt-in / byte-unchanged:** absent block = today's behavior, exactly. (2) **Never fails the run:** any capture failure degrades to the human-visual-test note. (3) **Never auto-merges a UI issue:** the screenshots are convenience evidence — the PR is still held open with `needs review` for you to test-render and merge yourself. Logic-only PRs still auto-merge on green; a repo with no `uiSurfaceGlobs` has no UI issues and is unaffected.
- **Under `--parallel`:** render capture defers to the serial merge tail — a parallel UI-issue worker opens the PR and applies `needs review` but attaches no screenshots; the serial tail or you capture before merge. (You can inject a per-worktree `PORT` to opt capture back into the parallel phase.)
- **No changes to any existing profile key.** `visualCapture` is purely additive.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.11.2 — Ground the release tail in docs, and make the auto-merge gate real

_Released 2026-06-23._

**Theme:** The driver hands the last step of a release back to you — merging your integration branch into your protected branch, tagging it, and closing the milestone. Two things about that handoff were shaky. The written runbook didn't warn you which way to merge, so a wrong choice quietly broke the *next* release. And on the driver's own repo, the safety net that's supposed to stop a failing change from merging wasn't actually wired up — "green" meant nothing because no tests ran before a merge. This release fixes both halves of the same trust gap: the release process is now documented correctly (so you don't get bitten on the next cut), and the driver now runs its own test suite as a real check before anything merges (so it practices the gate it provisions for you).

### 📖 Document the release tail correctly (`--merge`, not `--squash`)

| Issue | PR | What |
|---|---|---|
| #160 Adopt `--merge` for the release PR + harden the release tail | #204 | Rewrites `docs/consumer-setup.md` § "Releasing to your protected branch" into the complete ordered runbook. **Merge the integration→protected release PR with `--merge`, never `--squash`:** a squash puts a commit on your protected branch that the integration branch never sees, so the two diverge and the *next* release PR conflicts (typically on `.claude-plugin/plugin.json` + `CHANGELOG.md`) — and if your integration branch is PR-locked, you can't just resolve-and-push to fix it; it forces a separate history-only back-merge PR. `--merge` keeps the branches permanently synced instead. The runbook now spells out the full ordered tail — **open + merge the release PR with `--merge` *before* tagging → tag and cut the Release after the merge → close the milestone object → deploy** — with the `--notes`-from-CHANGELOG form (this plugin carries one) and `--generate-notes` as the no-CHANGELOG fallback. Two footguns are called out: **(a)** don't run a bare `gh release create` before the PR merges — it tags the old tip with empty/wrong notes (happened in v1.9.2); **(b)** a PR-locked integration branch blocks direct pushes even for admins. The `solve-milestone` SKILL's "🔴 Your move" recap and Final-summary "next human step" now both name `--merge` + merge-before-tag and point at the runbook. |

### 🧪 Make the driver's own auto-merge gate real

| Issue | PR | What |
|---|---|---|
| #179 Add a CI check on develop so auto-merge gates on tests | #205 | Adds `.github/workflows/ci.yml` (new) — a GitHub Actions workflow that runs the repo's shell test suites on every PR into `develop`. Two `ubuntu-latest` jobs, `shell-tests (bash)` and `shell-tests (pwsh)`, run `tests/extract-version.test` and `tests/ci-preflight-steps.test` (the `.sh` legs and their PowerShell 7+ `.ps1` twins). In the 1.11.0 wave the driver auto-merged PRs to `develop` on "green CI" — but the repo had **no required status check**, so green was vacuous: nothing ran the suite before the merge. This closes that hole on the driver's own repo, dogfooding the gate the suite already provisions for consumer repos. |

### Consumer notes (upgrading from v1.11.1)

- **Documentation-only behavior clarification for #160** — no change to how the driver runs. After it merges every issue and authors the CHANGELOG, the release tail now tells you the correct *way* to merge: `--merge`, not `--squash`. If you've been squash-merging your integration→protected release PRs and hitting recurring conflicts on the next cut, that's the cause — switch to `--merge` and the branches stay synced. The full ordered runbook (merge → tag → close milestone → deploy) lives in `docs/consumer-setup.md` § "Releasing to your protected branch".
- **The CI workflow (#179) is the driver's own dogfooding, not a consumer artifact.** `.github/workflows/ci.yml` gates *this* repo's `develop`; it doesn't change the installed plugin or your repo. The suite still provisions a CI gate for *your* consumer repo separately.
- 🔴 **Operator follow-up (not shipped in this release):** making the two CI checks actually *required* on `develop` is a one-time branch-protection step — adding the check contexts `shell-tests (bash)` and `shell-tests (pwsh)` to the branch's required-checks list (a `gh api -X PUT .../branches/develop/protection` call, preserving `enforce_admins`). The workflow file alone makes the checks *run*; the protection PUT makes a red PR *unmergeable*. This is operator config on the driver's own repo, not part of the installed plugin.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.11.1 — Ground the builder in your project's house docs (anchored retrieval)

_Released 2026-06-22._

**Theme:** The driver writes the code; the feeder plans it. Until now only the feeder read your project's standing docs (your `.project/` house docs — conventions, design system, glossary), so the plugin that *wrote* the code never saw the same source of truth the plugin that *planned* it used. This release closes that gap: the driver's builder and its two pre-build reviewers now receive the exact `.project/` sections an issue cites — pulled **section by section** (anchored retrieval), not whole files — so grounding stays consistent with the plan without ballooning token cost. When you have no `.project/` docs, nothing changes; the feature is invisible until you add them. This is part 2 of 3 of the suite-wide grounding seam.

### ✨ Project-docs grounding via anchored retrieval

| Issue | PR | What |
|---|---|---|
| #183 Add the projectDocs profile key | #190 | New optional `projectDocs` profile key (default `.project/`, absent-means-default), mirroring the feeder; resolved at the solve-issue and triage profile reads. |
| #184 Ship the read-doc-section primitive | #191 | New dependency-free `scripts/read-doc-section.{sh,ps1}` twin: given a doc + a `## anchor`, prints only that section; **fails loud** (non-zero exit) on a missing/renamed anchor — never silent empty grounding. Ships a 5-case test twin. |
| #185 Resolve cited sections once in solve-issue | #192 | solve-issue resolves the issue's cited `.project/<doc>#<section>` anchors once, pulls a superset via the primitive, and passes the sections into the implementer brief. |
| #186 Resolve cited sections once in triage | #193 | triage resolves the cited sections once per issue and passes the **same** sections into both the triage-reviewer and design-reviewer briefs. |
| #187 Wire the implementer | #194 | The implementer's "What you receive" now consumes the provided `.project/` sections; keeps Read/grep for on-demand additional anchors. |
| #188 Wire the triage-reviewer | #195 | The triage-reviewer grounds its five-criteria assessment in the provided `.project/` sections; on-demand reads retained. |
| #189 Wire the design-reviewer | #196 | The design-reviewer grounds its assessment in the provided `.project/` sections; on-demand reads retained. |

### 🧹 Scratch hygiene

| Issue | What |
|---|---|
| #199 Self-ignore per-clone scratch | The driver now ships a **committed** `.milestone-config/.gitignore` that makes its per-clone runtime scratch (`preflight-notice`, `trello-notice`, `triage-cache.json`, `tests-stamp`, plus the `.runtime/` and `worktrees/` dirs) git-invisible in **any** repo the plugin runs in, from the first write, with zero user setup — while the tracked config (`driver.json`, `feeder.json`) stays tracked. The `tests-green` hook (`.sh` + `.ps1`) and the scratch-write steps in `solve-issue` / `solve-milestone` / `triage` self-heal this file when absent, so existing consumer repos pick it up on their next run. Fixes scratch cluttering the consumer's `git status`. |

### Consumer notes (upgrading from v1.11.0)

- **New optional profile key `projectDocs`** in `.milestone-config/driver.json` — a string naming where your project's standing docs live. Default `.project/`; absent-means-default. You do not need to set it unless your house docs live elsewhere.
- **No grounding without docs.** If your repo has no `.project/` directory (or an issue cites no `.project/#section` anchors), every grounding step is a clean no-op — the run proceeds exactly as before, with no error. The feature only activates once you keep house docs under `.project/` and cite their sections in issue bodies.
- **Anchored, never whole-file.** Grounding pulls only the cited `## sections` (plus plausibly-relevant siblings), so per-dispatch token cost scales with cited-section size, not total doc size. A drifted/renamed anchor surfaces as a **loud failure**, not silent empty grounding.
- **New artifact:** `scripts/read-doc-section.{sh,ps1}` (+ `tests/read-doc-section.test.{sh,ps1}`). Dependency-free (POSIX bash / PowerShell 7+ built-ins; no new tooling).
- **Additive to existing gates.** Grounding raises consistency; it changes no gate logic, no five-criteria assessment, and no existing profile key.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.11.0 — Right model for each job: a stronger builder, leaner reviewers

_Released 2026-06-22._

**Theme:** The driver runs several specialized helpers as it works an issue — one that writes the code, and two that check the plan before any code is written. Until now every helper used whatever model the parent session happened to be on. This release assigns each helper to the model tier that fits its job: the **builder** runs on the strongest tier so the code it writes holds up, and the two **pre-build reviewers** run on a leaner, faster tier that an A/B test proved catches the same blocking problems. The result is steadier build quality and less wasted work, at no loss of review rigor.

### ⚙️ Efficiency & quality — model assigned per helper

| Issue | PR | What |
|---|---|---|
| #173 Pin the implementer (code-writer) to the strong tier | #177 | The implementer is the only helper that writes production + test code (test-first, version-correct citations, hard STOP if the approved design doesn't hold). Its model frontmatter changes `inherit` → `opus`, so your code is written by the strong tier regardless of the session model — protecting quality and cutting first-try misses against the driver's ≤2-per-gate retry caps. Also bumps the plugin version to 1.11.0. |
| #176 Pin both pre-build reviewers to the mid tier | #178 | The triage-reviewer and design-reviewer only read and check an issue against five fixed criteria before any code is written; they author nothing. They are the highest-fan-out helpers in a run (~20× triage, ~17× design across a milestone). Both change `inherit` → `sonnet`, so the most-frequent checks run faster and cheaper without weakening the gate. The "genuinely unsure → escalate to Blocker" fail-safe is untouched. |

### 🧪 How we know the leaner reviewers are safe

An A/B test (recorded on the tracking issue) compared models on the reviewers' real job — catching blocking problems before an issue is built:

- **Mid tier (Sonnet): 9 / 9 blocking problems caught — identical to the top tier (Opus 9 / 9).** No real defect slipped through.
- The only cost was one extra false flag on an otherwise-clean issue (a quick human glance, never a missed defect).
- The fastest tier (Haiku) was **disqualified** — it missed a real blocking problem.
- Caveat carried forward: the A/B used text-only fixtures, so the reviewers' repo-grounded dependency/pattern checks weren't exercised. Live-run Blocker recall is being monitored; the reviewers revert to `inherit` if a real Blocker is ever missed.

### 📖 Docs — simpler install

The Quickstart now leads with the **milestone-suite** install path — one marketplace cataloging all three milestone plugins — as the recommended way to install, keeping the per-repo install as a clearly labeled, still-supported alternative. ([#167](https://github.com/kenmulford/milestone-driver/issues/167))

### Consumer notes (upgrading from v1.10.0)

- **No config changes and no schema changes.** Your `.milestone-config/driver.json` is untouched. The only changes are which model each built-in helper uses, plus a README edit.
- **The model pins take effect on your next run automatically** — nothing to set. If you previously relied on the helpers all following your session's model, note the code-writer now always uses the top tier and the two pre-build reviewers always use the mid tier.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v1.10.0 — Deterministic, tested semver extraction for milestone version detection

**Theme:** `solve-milestone` step 3 no longer parses the milestone version by model judgment. A behavior-identical `scripts/extract-version.{sh,ps1}` pair — driven by a shared golden test matrix (`tests/extract-version.cases.tsv`) and two thin runners — deterministically extracts the version from the milestone title (description as fallback) and reports `none` / `ambiguous:<candidates>` on a miss. Step 3 maps that outcome against `versioning` to versioned / version-free / prompt, splitting the previously-identical `absent` vs `true` semantics.

### Consumer notes

- **Behavior change (default `versioning`):** `solve-milestone` now uses a deterministic version extractor. With `versioning` absent (the default), a milestone whose title has no parseable version now **silently runs version-free** instead of parsing-by-judgment/prompting — a consumer relying on the default bump should confirm their milestone titles carry a version, or set `versioning: true` to be prompted on a miss.

### ✨ CI-aware preflight (`preflightCmd: "github-ci"`)

`preflightCmd` now accepts the reserved sentinel `"github-ci"` (alongside today's literal-command mode, unchanged). It auto-derives the preflight gate from the repo's GitHub Actions CI so a cheap CI check (e.g. `npm audit --omit=dev --audit-level=high`) is front-run locally **before** the PR instead of being hand-transcribed and forgotten — closing the gap where an un-transcribed CI check only fails after the PR opens. A behavior-identical `scripts/ci-preflight-steps.{sh,ps1}` pair (golden matrix `tests/fixtures/ci-preflight/` + two runners) parses the local `.github/workflows/*.yml` with a constrained line parser — **no new tool dependency** (no `yq`/`act`/`python`), no network — discovers the PR-gating workflows, and emits each job's `run:` steps in order. `solve-issue` step 6.1 runs them through the existing tool-presence-guard → re-dispatch (cap 2) → park machinery. Skip-rules drop `uses:` steps, secrets / services / deploy, `${{ }}`-interpolated and step-`if:` steps; `working-directory` is honored and `continue-on-error` steps never park. **Loud coverage logging** ("mirrored N, skipped M") and a **silent-under-run guard** (a PR-gating workflow yielding zero runnable steps — e.g. checks behind a `uses:` reusable workflow — is a visible warning, not a clean pass). One optional `ciWorkflow` override narrows discovery to a single workflow. Documented limitations (CI stays the authority): no `uses:`-recursion, no `matrix` expansion, no `act` fidelity, GitHub Actions only. See [#162](https://github.com/kenmulford/milestone-driver/issues/162).

- **No schema break:** `preflightCmd` keeps its literal-command and absent behavior byte-for-byte; `"github-ci"` and the optional `ciWorkflow` key are purely additive.

## v1.9.2 — Make the manual close-the-milestone step explicit

**Theme:** The driver closes a milestone's issues and authors the CHANGELOG, but never closes the GitHub milestone object itself — that stays in the human-owned release tail alongside the `integrationBranch` → `protectedBranch` merge and deploy. This release spells that boundary out and surfaces the exact command, so an operator finishing a clean run isn't left to look up a REST call GitHub gives no first-class command for.

### ✨ Release-tail clarity

| Issue | PR | What |
|---|---|---|
| #153 make the manual close-the-milestone step explicit | #154 | Names closing the GitHub milestone object as a manual, human-only step in both blast-radius statements (`solve-milestone` SKILL + `docs/architecture.md`), and surfaces the `gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed` command in the `🔴 Your move` block and the Final-summary "next human step" bullet — with the caveat that the driver closes the milestone's issues and authors the CHANGELOG but never the milestone itself. |

### Consumer notes (upgrading from v1.9.1)

- **Documentation-only behavior clarification** — no change to how the driver runs. After it merges every issue and authors the CHANGELOG, the release tail now explicitly tells you to close the GitHub milestone object (`gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed`) as part of the manual, human-owned release step.
- **No schema changes** to `.milestone-config/driver.json`.
- Milestone #16 also included #152 — locking this repository's own `develop` branch to PR-only to match the governance baseline. That is a change to the author's repo configuration with **no effect on the installed plugin**; it is noted here only for milestone completeness.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.9.1 — Finish the `.milestone-config/` relocation: the per-clone runtime markers move out of the repo root

**Theme:** v1.9.0 relocated the **committed** driver profile to `.milestone-config/driver.json`
but left five **per-clone runtime artifacts** still written into the target repo root. This
release moves all five under `.milestone-config/`, dropping the redundant `milestone-driver-`
prefix (the directory already namespaces them), so a fresh run no longer litters the repo
root. Each marker is read **transitionally** — new path first, legacy root as fallback —
and the stale root file is **auto-cleaned on the first write to the new path**, mirroring
the commit-clean two-step read the gate hooks already use for the profile. Existing clones
upgrade silently: no duplicate notice, no cache rebuild, no re-run of an already-green suite.

### ✨ Per-clone runtime markers move under `.milestone-config/`

| Issue | PR | What |
|---|---|---|
| #148 Relocate the 5 remaining root-litter runtime markers | #149 | Move all five per-clone runtime artifacts out of the repo root and under `.milestone-config/`, dropping the `milestone-driver-` prefix: `tests-stamp`, `preflight-notice`, `trello-notice`, `triage-cache.json`, and the `worktrees/` scratch dir. Each persistent marker is read new-path-first with a legacy-root fallback and writes only to the new path (`mkdir -p .milestone-config` / `New-Item -Force` before every write — no writer assumes the dir exists), removing the stale root file on the first new write. The `tests-green` hook (`.sh` + `.ps1`) skips the suite on either path's matching `branch:treeSHA` and clears **both** stamps on red; `triage` reads/writes the cache transitionally on both the `jq` and `ConvertFrom-Json` paths with degradation rules intact; the `preflight-notice` / `trello-notice` one-time markers stay silent if **either** marker exists and clean up the stale root marker when suppressing; the `worktrees/` fleet is a pure path relocation (ephemeral per-run scratch — no fallback read needed). `.sh`/`.ps1` parity preserved. |

### Consumer notes (upgrading from v1.9.0)

- **The five runtime markers now live under `.milestone-config/`.** Existing repos keep working with **no action** — each marker is read from the new `.milestone-config/<marker>` path first and falls back **transitionally** to the legacy root `.milestone-driver-<marker>` so an in-flight clone behaves identically on upgrade (no duplicate preflight/Trello notice, no triage-cache rebuild, no re-run of an already-green unit suite). On the first write to the new path, the stale legacy root file is **automatically removed**.
- **No schema change** and **no config action required.** These markers are per-clone and gitignored — they were never committed. The `.gitignore` adds the five new `.milestone-config/<marker>` paths and **keeps** the legacy root ignores (commented as transitional) so any leftover root file in an existing clone stays ignored until it is cleaned up. The committed `.milestone-config/driver.json` is **not** ignored.
- **Leftover root files self-clean.** A pre-existing `.milestone-driver-tests-stamp` / `-preflight-notice` / `-trello-notice` / `-triage-cache.json` is read once (as the fallback), then removed when the new-path file is first written. A leftover `.milestone-driver-worktrees/` dir is harmless — gitignored and simply unused by the new `.milestone-config/worktrees/` path; remove it at leisure.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v1.9.0 — Suite-wide `.milestone-config/` profile location

**Theme:** The driver profile moves to a canonical `<repo>/.milestone-config/driver.json`,
read transitionally from the legacy root and auto-migrated on the first build — the
precondition the sibling `milestone-feeder` plugin assumes when it reads the driver's
shared keys (`sourceGlobs`, `uiSurfaceGlobs`, `integrationBranch`) from the same directory.
Migration is **commit-clean**: only the commands with a PR path to the integration branch
move the file, so the relocation always lands durably instead of stranding an uncommitted
move on the orchestrator's tree.

### ✨ Canonical `.milestone-config/` profile location

| Issue | PR | What |
|---|---|---|
| #144 Resolve profile from `.milestone-config/driver.json` first | #145 | Resolve the driver profile from `<repo>/.milestone-config/driver.json`, falling back **transitionally** to the legacy root `milestone-driver.json` so gates keep firing on un-migrated repos. All eight gate hooks (`.sh` + `.ps1`) do the two-step read and never mutate (`.ps1` uses the portable multi-arg `Join-Path`). Migration is **commit-clean**: `setup` and `solve-issue` perform the `git mv` (solve-issue on the feature branch at step 3.5, riding the issue PR), `solve-milestone` migrates via its first dispatched build, and `triage` stays read-only — it surfaces a "legacy profile detected" note but never moves the file. Idempotent everywhere; when both files exist `.milestone-config/driver.json` wins (no overwrite, no deletion of the leftover root file). New projects always create at `.milestone-config/driver.json`. |

### Consumer notes (upgrading from v1.8.1)

- **Canonical profile location is now `.milestone-config/driver.json`.** Existing repos keep working with **no action** — the legacy root `milestone-driver.json` is still read transitionally. On the first `setup` or `solve-issue` build, a legacy root profile is automatically **moved** (`git mv`) to `.milestone-config/driver.json`; `solve-milestone` migrates via its first dispatched build, and `triage` is read-only (it only surfaces the detection). When both files exist, `.milestone-config/driver.json` wins and the leftover root file is left untouched for you to remove (no `.gitignore` change is made).
- **No schema change** to the profile — the keys are identical; only the file location moved (and the canonical filename inside the directory is `driver.json`). Add new keys like `preflightCmd` / `integrations.trello` to `.milestone-config/driver.json` going forward.
- **PowerShell gate hooks** now resolve the new path with the portable multi-arg `Join-Path` form (PowerShell 7+).

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v1.8.1 — Surface what the engine already does (and fix the capture defect underneath)

**Theme:** Most of this milestone is making existing capability *visible* — fewer
false triage Blockers, a triage cache that says when it skips, the wave trade-off
surfaced at the setup decision point — sitting on one real reliability repair: the
parallel barrier now reads git/gh ground truth instead of trusting a worker's
free-text handback. Plus a cross-platform gate fix reported from the field.

### ✨ Surfacing the engine's existing behavior

| Issue | PR | What |
|---|---|---|
| #135 setup Integration tier | #141 | Adds an optional **Integration tier** to `/milestone-driver:setup` for `integrationGranularity` (an already-existing schema key that was never prompted), defaulting to `issue`. Choosing `wave` fires a non-blocking precondition prompt — *is `preflightCmd` set? is `unitTestCmd` your full suite?* — surfacing the "one red wave-PR CI blocks the whole Wave" trade-off where the choice is actually made. Default stays `issue`; `"full suite?"` is a human question, not a machine check. |
| #134 visible cache writes | #139 | The best-effort triage cache write no longer fails **silently**: the Bash path emits a stderr line on `jq`-absent and on write-fail, the PowerShell `catch` surfaces a `Write-Warning`, and the Step 5 output line gains a conditional `; cache write skipped this run` clause. The never-gating contract is unchanged — only silence became a visible warning. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #132 barrier reads ground truth | #137 | The `--parallel` Phase 1 barrier now **re-derives each worker's terminal state from git/gh** (the `solve-issue` step-3 probe) instead of trusting the worker's free-text final-message handback — fixing the ~37% handback **tail-drop** and the hand-finish **race**. The handback is demoted to an optimization hint; the happy-path partition is byte-identical. |
| #133 fewer false triage Blockers | #138 | `triage-reviewer` downgrades a choice an established repo convention or sibling pattern already answers from **Blocker** to **Advisory** (criterion 2 carve-out + a severity-rule row), so routine calls no longer trip a manual filtering pass. Genuine ambiguity still escalates to Blocker; no new mechanism (Advisory is already non-gating). |
| #136 Unix gate exec bit | #140 | `hooks/run-hook.cmd` was committed mode `100644`, so on macOS/Linux `/bin/sh -c` couldn't `exec` it (`EACCES`, exit 126) and **every PreToolUse gate was silently inert on Unix**. Now committed `0755`. Cross-platform safe (Unix no-shebang → `ENOEXEC` → `sh` fallback; Windows unchanged). Reported and verified by @gcpeacock-npm. |

### Consumer notes (upgrading from v1.8.0)

- **🔴 macOS/Linux: all gates now actually run.** Before this release, `hooks/run-hook.cmd` shipped non-executable, so every milestone-driver PreToolUse gate (`force-subagent`, `no-bom`, `tests-green`, `no-push`, `no-pr-to-protected`) died with "Permission denied" on Unix and was silently inert. After updating to 1.8.1 the packaged launcher is `0755` and the gates fire. If you applied the `chmod +x` cache workaround, it is no longer needed.
- **New `/milestone-driver:setup` Integration tier** offers `integrationGranularity`. **No schema change** — the key already existed; setup just prompts for it now (default `issue`, absent-means-issue). Existing profiles need no migration.
- **Triage: fewer false Blockers.** Choices an established convention/sibling pattern answers are now Advisory (logged, non-gating) rather than parking the issue — expect fewer manual clarifications.
- **Triage cache writes are now observable** — a skipped/failed write prints a one-line warning instead of nothing; the run is otherwise unchanged (still best-effort, never-gating).
- **`--parallel` is more robust to dropped worker handbacks** — no behavior change on the happy path; the barrier just no longer strands a built branch when a worker's final message drifts off-format.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v1.8.0 — Optional Trello board sync + auto-authored release notes

**Theme:** milestone progress optionally mirrors to a Trello board — a card per
milestone that moves through Queue → In Progress → In Review with a per-issue
checklist — and the release notes you are reading now author themselves at
milestone completion. Both are opt-in and best-effort; absent their config, the
loop is byte-unchanged.

### ✨ Trello integration (the #99–#104 family)

| Issue | PR | What |
|---|---|---|
| #99 Profile node + setup tier | #123 | New optional `integrations.trello` profile node (`boardId` required when present; `lists.queue`/`inProgress`/`inReview` default independently to `Queue`/`In Progress`/`In Review`) and an "External integrations" tier added last in `/milestone-driver:setup` (suppressed on auto-bootstrap). Presence enables; absence skips silently. |
| #100 trello-sync.md + run-start resolution | #125 | New `skills/solve-milestone/trello-sync.md` reference (read only when `integrations.trello` is present — zero token cost otherwise) holding all ten sync conventions: best-effort wrapper, availability probe, ensure-list auto-create, card-resolution order (back-link anchor → name-match → create), idempotent `<!-- trello: … -->` back-link, card state machine, and main-thread-only thread safety. Adds the run-start card resolution (SKILL.md step 3.5) and the one-time upgrade notice (step 1.2). |
| #101 Phase 0 hooks | #128 | After triage, posts the triage summary (all-clear or gap table + Wave graph) as a card comment and moves Queue → In Progress when ≥1 issue is buildable; all-parked leaves the card in Queue with an explanatory comment. |
| #102 Loop hooks | #126 | Ticks the card's `#<n>` checklist item when an issue merges (visual-gate holds excluded), under both issue and wave granularity; in `--parallel`, ticks fire in the serial merge tail on the main thread. Per-item best-effort. |
| #103 Finish hooks | #127 | Posts the final-summary card comment (merged / parked / open `needs review` PRs / skipped Trello updates) and moves In Progress → In Review only when zero open issues carry a blocker label; parks-remaining stays In Progress with a comment; a systemic halt posts the comment but does not move. |
| #104 Docs + dogfood | #129 | README "Optional integrations" paragraph and a `docs/consumer-setup.md` "Trello integration (optional)" section: the MCP-prerequisite distinction, both enablement paths, the tracked lifecycle, and the four known limitations — cross-linked to `profile-schema.md` and `trello-sync.md` with no duplication. Dogfood recorded as a manual lifecycle walkthrough on the issue. |

### ✨ Release automation

| Issue | PR | What |
|---|---|---|
| #121 Auto-author the CHANGELOG | #124 | When a `solve-milestone` run ends with every issue merged (no parks, no holds), the orchestrator authors a `## v<version>` CHANGELOG entry as a final doc-only PR to the integration branch — themed `\| Issue \| PR \| What \|` tables (the "What" distilled from each merged PR's summary, title fallback), Consumer notes, and a Post-run audit trail. Idempotent (heading-prefix match), skips on any park/hold, and headed by the milestone title in version-free mode. This entry is the first one it produced. |

### Consumer notes (upgrading from 1.7.0)

- **New optional profile node `integrations.trello`** (additive — no migration).
  Absent → every Trello step skips silently and the loop is byte-unchanged.
  Present → requires the `@delorenj/mcp-server-trello` MCP server loaded in your
  Claude Code session; the plugin itself has no Trello dependency.
- **Enable it** by re-running `/milestone-driver:setup` (the External
  integrations tier is last; existing values pre-fill) or by hand-adding the
  node — see `docs/consumer-setup.md`.
- **New gitignored marker:** `.milestone-driver-trello-notice` at the repo root
  (drives the one-time upgrade notice). Safe to delete.
- **Release notes now author themselves.** A fully-completed milestone run ends
  with a CHANGELOG PR; a run with any park or hold authors nothing (a later
  completing re-run authors them then).

### ⚖️ Post-run audit trail

No `judgment call` PRs this release. All seven PRs (#123–#129) carry a
`## Code Review` section with their findings and resolutions.

## v1.7.0 — Interactive background orchestration, scannable output, triage reuse

**Theme:** the orchestrator no longer clogs the main conversation line, the run is
human-scannable at a glance, and repeat runs stop paying the re-triage tax.
Includes the 1.7.1 triage-reuse milestone, rolled in.

### ✨ Background orchestration (the #89 family)

| Issue | PR | What |
|---|---|---|
| #89 Chunked background dispatch | #112 | The milestone loop dispatches each issue (sequential) or each Wave's workers (`--parallel`) via `Agent(run_in_background: true)`. The main line stays interactive; the operator can redirect between chunks. Standalone `solve-issue` gains an opt-in `--async` token (full pipeline unchanged except the version-bump confirm defaults to patch, logged as a judgment call). |
| #95 Permission pre-flight gate | #109 | Background subagents auto-deny any tool call that would prompt — so before the first background dispatch, the gate verifies the union of readable `permissions.allow` layers (user + project + local) covers the pipeline's tool surface. Gap → 🔴 gap table + synchronous fallback. Workers convert mid-chunk auto-denies to parks. |
| #97 Main-line push notifications | #113 | One notification per event that matters: `⏸️ #N parked — <reason>`, `🌊 Wave N done` (suppressed on the final Wave), `🏁` run complete / `🚨` systemic halt. Emitted by the main line only — a live probe confirmed `PushNotification` does not exist in subagent registries. |

### ✨ Scannable output

| Issue | PR | What |
|---|---|---|
| #96 Output spec | #105 | Shared icon legend + three structured templates: run-start plan board, chunk-boundary status update, final results board. Tables and icons replace free-form narration at every reporting point. |
| #116 Output-spec polish | #118 | The six accepted findings from #105, operator-decided: PR-cell emit rule ("show the PR number if the issue has one, else —"), one `[..]` placeholder convention, `🔴 Your move` casing, definition-before-reference section order, continuous example cast (#201/#202/#203) across all three templates. |

### ✨ Triage reuse (1.7.1, rolled in)

| Issue | PR | What |
|---|---|---|
| #106 Step-0 context handoff | #111 | `solve-issue` step 0 reuses the milestone run's Phase 0 triage result when the caller explicitly supplies it (named-value fields in worker briefs; inline restatement sequentially) — eliminating the intra-run N+1 re-triage. Anything not explicitly supplied falls back to fresh single-issue triage. |
| #107 Per-issue result cache | #110 | `.milestone-driver-triage-cache.json` (gitignored) caches per-issue triage results keyed on change signals (labels, body edit time, comment count, milestone description). Unchanged issues skip agent dispatch across invocations; any change — including upstream edges closing unmerged — forces fresh triage. Absent/corrupt cache degrades to full re-triage. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #98 Milestone ID or name | #108 | `solve-milestone 10` and `solve-milestone "1.7.0"` now both resolve (number-first for numeric input, paginated title lookup otherwise, fail-fast table of available milestones). |
| #114 Contradictory gate paragraphs | #117 | Deleted two stale STOP-flavored duplicates left by the 1.6.0 autonomy rewrite — park-don't-prompt is now the single directive at the red-suite cap and the `/code-review`-omission gate. |
| #115 Park-reason lookup + park anchor | #119 | Build-park comments now open with the canonical `🔴 Parked — ` anchor (joining `🔴 Triage` and `🔴 Blocked`), making the final summary's park-reason lookup a pure prefix match: last matching comment, any run (cache hits post no fresh comment). No match → "park reason not recorded" — never a guess. |

### Consumer notes (upgrading from 1.6.0)

- **Allowlist before backgrounding.** Background dispatch activates only when the
  pre-flight gate passes. Run `/fewer-permission-prompts` (or allowlist your
  git/gh/test commands) to enable it; otherwise runs fall back to today's
  synchronous behavior.
- **New gitignored artifact:** `.milestone-driver-triage-cache.json` at the repo
  root. Safe to delete at any time (next run re-triages fresh).
- **Park comments changed shape.** New parks open with `🔴 Parked — `. Issues
  parked by pre-1.7.0 runs report "park reason not recorded (pre-1.7.0 park
  format)" in final summaries — read the issue directly for those.
- **No schema changes** to `milestone-driver.json`. All 1.7.0 behavior works with
  an existing profile.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: #105, #109, #110, #113, #119 (#115). Each
carries its accepted findings and rationale in its Code Review section.
