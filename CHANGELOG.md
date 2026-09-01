# Changelog

Release notes for milestone-driver. Versions before 1.7.0 are documented on the
[GitHub Releases page](https://github.com/kenmulford/milestone-driver/releases).

## v1.26.1 - review effort drops to `low` after the first run

**Theme:** The classifier verdict sets the **first** `/code-review` run's effort; every later run on the issue is `low`.

### 🔧 Changed

| Issue | PR | What |
|---|---|---|
| - | - | `skills/review-depth.md` § The ladder: the effort column is a first run's only. The re-review a `code-changed` fix owes, and a 2nd cycle's review, run at `low` whatever the verdict says at that point; the cycle cap, the re-classify rule, and the second-cycle park are unchanged and still keyed to the verdict. A resumed issue starts a fresh pass: holding no record of the earlier run, its next review takes the verdict's effort again. `simplify-pass.md`'s step 9 run is its own pass's first run. The file's placement rationale, the `shallow` trigger's small-diff half, and the worktree row's "because Phase 1 does not commit" clause were cut to pay for it, each stated at its own source. |
| - | - | `skills/solve-milestone/parallel-waves.md` step 7 briefs each reviewer with the effort the ladder sets for this run, resolved on the orchestrator's line, instead of "the verdict just computed" - so a re-review dispatched after a fix inherits `low` rather than the first run's `medium`. |
| - | - | The PR-body `## Code Review` template records `Findings, one line per run`, in `skills/solve-issue/SKILL.md` step 6.3 and the block `skills/solve-milestone/milestone-granularity.md` copies verbatim. A first run at `medium` and a re-review at `low` no longer have to share one effort slot. |
| - | - | `docs/consumer-setup.md`'s "Review depth is not the risk profile" block, the one place that restates the ladder for consumers, no longer publishes the verdict's effort as every review's. |

### Consumer notes (upgrading from v1.26.0)

- **A second review round is now shallower.** An issue whose first review ran at `medium` is re-reviewed at `low` after a fix. A finding the `medium` pass would have raised can survive the re-review; the cycle cap, the second-cycle park, and `hooks/dispatch-cap.sh`'s deny of the 4th run are all unchanged.
- **`shallow` is unaffected** - every run it makes was already `low`.
- **No schema changes** to `.milestone-config/driver.json`.
- Ceiling state a contributor's next edit hits: `skills/review-depth.md` measures 90/90 lines, 4467/4500 bytes, 656/700 words - at its line ceiling, with the advisory CRLF `WARN` (33 bytes free) it now carries, so the next edit there trims before it adds. No ceiling was raised. The informational `CLOSURE skills/solve-issue/SKILL.md 12583/12300` row, which never gates, was already over at 12568 before this change.

## v1.26.0 - grounded edges stay Advisory, the orchestrator keeps its context small

**Theme:** A dependency the triage reviewer grounds at `file:line` stays Advisory instead of parking the issue and dispatching the resolver (#639); the orchestrator's own context footprint gets the same discipline next (#640).

### ✨ Added

| Issue | PR | What |
|---|---|---|
| #640 The orchestrator's own context footprint gets read-discipline treatment | #644 | `hooks/session-resume.{sh,ps1}` (`SessionStart`, matcher `compact`): re-injects the milestone run's wave-state checkpoint (issue, wave, status, branch, PR - capped at 40 rows, then `… N more`) after Claude Code auto-compacts mid-run. Never gates; fail-open on no profile, no checkpoint, or unparsable JSON. Escape `CLAUDE_HOOK_DISABLE_SESSION_RESUME=1`. 12 cases per leg. |
| #640 The orchestrator's own context footprint gets read-discipline treatment | #644 | `autocompact` one-time notice (`skills/notices.md`): recommends `/autocompact 200k` (persists to user settings) or `CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000` for scripted runs, when the effective auto-compact window is absent or over 200000 across the same three settings layers the permission pre-flight gate reads. |

### 🔧 Changed

| Issue | PR | What |
|---|---|---|
| #640 The orchestrator's own context footprint gets read-discipline treatment | #644 | `skills/solve-milestone/SKILL.md`'s wave-boundary status template now states that every input the next wave needs is on disk at that point, so a mid-run compaction there loses nothing. |
| #640 The orchestrator's own context footprint gets read-discipline treatment | #644 | New `### Main-thread context` section (`solve-milestone`, cited by `solve-issue`): the orchestrator never `Read`s a persisted tool-result file or `cat`s a `.project/` doc, the consumer brief, or a plugin reference file whole - it takes a section with `read-doc-section.{sh,ps1}` or `sed -n`, and a truncated tool result is re-run narrower, never re-read. |
| #640 The orchestrator's own context footprint gets read-discipline treatment | #644 | `skills/triage/SKILL.md` Step 2 redirects each issue's full record and the milestone description straight to `.milestone-config/.runtime/triage/*.md` instead of returning them inline; Step 3's briefs pass those paths, read first by the dispatched agent. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #639 An undeclared dependency the reviewer grounds at `file:line` no longer parks the issue or dispatches the resolver | #642 | `agents/triage-reviewer.md`'s criterion 4 and severity table re-key an undeclared dependency's severity to groundability: grounded at `file:line` is Advisory (`type: undeclared-dependency`, its edge in `DEPENDS_ON`, `to_clear` the `Depends on #<n> - <reference>` line to add), Blocker only when it cannot be grounded once the source set is exhausted or would cycle with the declared Wave order or the other edges returned. The issue-#37 example re-keys to the same verdict. `skills/triage/SKILL.md` Step 4's graph note and Step 6's park-label row follow: only the Blocker variant surfaces as a Blocker or parks `needs decision` - an Advisory never parks. `agents/blocker-resolver.md`'s `undeclared-dependency` row now covers only the two cases that still reach it - ungrounded after the source set, or cyclic with the Wave order - and what resolving each means. |

### Consumer notes (upgrading from v1.25.0)

- **An issue whose only gap is a grounded missing `Depends on` line no longer parks or dispatches the resolver.** The edge lands in the validated dependency graph as an Advisory instead.
- **A new `SessionStart` hook loads at session start.** Restart Claude Code after updating so `session-resume` takes effect.
- **The `autocompact` notice fires once per clone**, only when no auto-compact window is configured above 200k across your three settings layers.

## v1.25.0 - the ladder's caps become a hook, and briefs carry paths

**Theme:** The caps the orchestrator overran were text. The review→fix cycle cap and the implementer re-dispatch cap are now a hook; a small diff classifies `shallow` and skips the coherence pass; briefs name the docs an agent reads instead of pasting them.

### ✨ Added

| Issue | PR | What |
|---|---|---|
| - | - | `hooks/dispatch-cap.{sh,ps1}` (PreToolUse `Agent`/`Task`/`Skill`): denies the 4th `/code-review` run and the 4th implementer dispatch per issue. Main thread only. Key: branch `issue/<n>-*`, else `issue <n>` / `#<n>` in the brief. Counter under `<git-common-dir>/milestone-driver/dispatch-cap/`, reset when HEAD moves. Escape `CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1`. 27 cases per leg. |

### 🔧 Changed

| Issue | PR | What |
|---|---|---|
| - | - | `scripts/classify-review-depth.{sh,ps1}`: no deep trigger, no rejected candidate, and at most 20 changed lines (`git diff --numstat HEAD`) is `shallow`, `small-diff:<n>` on stderr. Binary or failed reads stay `standard`. 7 rows plus a binary case per leg. |
| - | - | `solve-issue` section 6 runs the classifier before the coherence pass and skips it on `shallow`; `review-depth.md` allows that earlier run. |
| - | - | The per-gate "2 re-dispatches" budgets and the review loop's fixes share one budget: 3 implementer dispatches per issue. `solve-issue` step 4, `parallel-waves.md`, and `contingencies.md` point at the hook. |
| - | - | Briefs carry paths. `solve-issue` and `triage` name the prose-contract path and the cited `.project/` anchors (with the `read-doc-section` path) instead of pasting section text; the agent reads them. The code-comment rule is no longer quoted into the brief. Agent input lists updated. |

### Consumer notes (upgrading from v1.24.3)

- **A new gate loads at session start.** Restart Claude Code after updating. A repo with no profile is never gated.
- **A denied dispatch is the park signal.** To re-run one issue by hand, delete its counter file or set the escape variable.
- **Small diffs get one low-effort review and no coherence pass.** No knob; the deep triggers still win.
## v1.24.3 - squash commits and aggregate PR bodies stop carrying every issue's prose

**Theme:** The driver's squash merges pass an explicit subject and body, and the milestone and wave PR bodies carry a choice-only Decision Log with collapsed Code Review sub-entries, so a release PR pre-fills from a one-line commit instead of 41 KB of concatenated fold commits.

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #629 Squash merges pass an explicit subject and body; milestone and wave PR bodies shrink to a choice-only Decision Log and collapsed Code Review sub-entries | #632 | Every squash site in `skills/` (solve-issue step 8, parallel-waves Phase 2 step 2, changelog-authoring 6.8, milestone-granularity step 4, integration-granularity wave disposition, simplify-pass PR path) runs one `&&`-joined call: `title="$(gh pr view <pr-number> --json title --jq .title)" && [ -n "$title" ] && gh pr merge <pr-number> --squash --delete-branch --subject "$title (#<pr-number>)" --body "$body"`, the shape defined once at step 8. `$body` is `Decision Log and Code Review: PR #<pr-number>` (or `Code Review: PR #<pr-number>` for the CHANGELOG and simplify PRs); 6.8 owns the `CHANGELOG: <heading>` second line, conditional at milestone end. Step 6.2 posts the four-slot Decision Log on the issue as the `📋 Decision Log` comment (idempotent on resume); the milestone and wave PR bodies carry a choice-only Decision Log pointing at it and `<details>`-collapsed `### #<n>` Code Review sub-entries with `#<n>` alone as the summary, both shapes defined once in `skills/output-style.md`. `hooks/code-review-gate.{sh,ps1}` headers record that merge flags set the merge commit, not the PR body; four golden rows cover the one-call shape, a `<details>`-wrapped body, a `run: no` inside the wrapper, and a newline body. |
| #630 Every trailer query reads the milestone window, not the milestone branch's whole history | #633 | The four `git log --grep` trailer queries in `skills/` take a **guarded** merge-base window - `base="$(git merge-base <ref> <milestone-branch>)" && [ -n "$base" ] && git log "$base".."<milestone-branch>" --grep=...` - at the resume-and-buildability query, milestone end step 3's `Simplify-Pass:` sub-entry query, `simplify-pass.md` step 2's re-run guard, and `milestone-clauses.md` row 3. `skills/solve-milestone/milestone-granularity.md § Resume and buildability from the trailer` defines it once: `<ref>` is `origin/<integrationBranch>` where that ref resolves, else the local `<integrationBranch>`, and a failed `merge-base` or an empty `base` is a loud stop taking the pre-clean guard's leg-4 systemic-halt shape, never the empty state. `milestone-clauses.md` row 2 adds the ref-resolves check a standalone `solve-issue` run needs; `simplify-pass.md` step 2 scopes each path to its own granularity, the milestone query being inert where `<target>` is `integrationBranch`. `integration-granularity.md`'s buildable condition (a), its step 2 pre-clean guard, and its Step 9 `built-green` / `abandoned` rows name the window; `docs/architecture.md` cites the defining section instead of publishing the unbounded query. `^...$` anchoring on every pattern is unchanged. |

### Consumer notes (upgrading from v1.24.2)

- **Squash commits on your integration branch are now one subject line plus a pointer.** The Decision Log and Code Review live on the PR (and the Decision Log on the issue's `📋 Decision Log` comment), not in the commit message. A repo setting of `squash_merge_commit_message: COMMIT_MESSAGES` no longer matters to the driver's merges.
- **A new byte-fixed opener, `📋 Decision Log`**, on the per-issue comment step 6.2 posts. Anything parsing issue comments by opener sees one more.
- **Milestone and wave PR bodies changed shape.** The Decision Log section is one choice-only line per issue; each Code Review sub-entry is wrapped in `<details><summary>#<n></summary>`. The `## Code Review` heading and the `/code-review run:` slot the gate reads are unchanged.
- **A resumed milestone run no longer reads trailers from before the milestone.** An integration branch whose history already carries `Issue:` and `Simplify-Pass:` lines - a `COMMIT_MESSAGES` squash from before this release - no longer reports that work as already integrated on a later milestone branch, and no longer skips the simplify pass.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- Ceilings raised in `scripts/check-size-budgets.{sh,ps1}`, each derived by the script's own rule and recorded in its header: `skills/output-style.md` BYTE 9500 to 11500 and WORD 1600 to 1800, `skills/solve-milestone/changelog-authoring.md` BYTE 14000 to 15500 and WORD 2200 to 2400, and the `setup` / `solve-milestone` / `triage` closures.
- Ceiling state a contributor's next edit hits: `skills/output-style.md` 11260/11500 bytes and 1762/1800 words, `skills/solve-milestone/changelog-authoring.md` 14605/15500 and 2235/2400, `skills/solve-issue/SKILL.md` 43678/44000 bytes at 316/320 lines with its closure at 12256/12300. `skills/solve-issue/SKILL.md` took no raise; its added prose was traded back inside the file, which also cleared the advisory CRLF WARN that pass raised. No WARN row remains.
- `/code-review` ran four cycles on this issue against a two-cycle ladder (`skills/review-depth.md § The ladder`). Cycles 3 and 4 found only prose-level defects; the deterministic gates were green from cycle 2 onward. Filed as #631 alongside the park-rule defect.
- Fold commits on a milestone branch still carry the full Decision Log and `Code-Review:` block; they are deleted with the branch after the squash and never reach the integration branch.

## v1.24.2 - the comment-only fix branch becomes reachable

**Theme:** The post-fix classifier stops diffing against HEAD, which in the driver's own procedure is the state before the *issue*, and diffs the post-fix tree against a snapshot taken immediately before the fix.

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #625 classify-delta diffs against HEAD, so comment-only is unreachable in the driver | #626 | `scripts/classify-delta.{sh,ps1}` gain `--snapshot <root>`: the working tree (staged, unstaged, untracked; `.gitignore` honored) is written to a tree object through a throwaway index seeded from the real one (`git rev-parse --git-path index`, mtime preserved) and the hash is printed; the real index is never written. Classify mode is `<root> <pre-tree>`: it snapshots the post side and runs `git diff-tree -r -p -U0 -M` over the pair; the parser and every reason token are unchanged. Snapshot failure is loud: no hash, `snapshot-failed` on stderr, exit 1. Classify still exits 0 always and fails safe to `code-changed` with `no-pre`, `bad-pre:<tree>`, or `no-delta`. `untracked:<path>` is retired; a file the pre-tree does not hold is `added:<path>` whatever its content, symmetric with `deleted:`. `solve-issue` step 6.1 takes the snapshot before the fix re-dispatch; `post-fix-commit.md` and `parallel-waves.md` step 7 classify against the held hash, and a nonzero `--snapshot` takes the `code-changed` branch. 66 golden rows plus 19 bespoke cases per leg, byte-identical across legs. |

### Consumer notes (upgrading from v1.24.1)

- **The classifier's call shape changed.** `classify-delta.<sh|ps1> <repo-root>` with no second argument now prints `code-changed` with `no-pre` on stderr instead of classifying: the tree hash from `--snapshot`, taken before the fix is dispatched, is a required second argument. Both skills that call it were updated; a consumer or wrapper calling it directly must take the snapshot itself.
- **One reason token is retired.** `untracked:<path>` is gone: a new file reports `added:<path>` instead, staged or not, whatever its content. The bare `no-content` is no longer documented, having no reachable input; `no-content:<path>` is unchanged.
- **Under `core.splitIndex`, taking a snapshot can leave a new `sharedindex.*` file in `.git/`.** Git resolves the shared index against the real gitdir even when the index being written is a throwaway one. The real index still parses and still describes the same state; `git gc` removes the extra file.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- **The seed's mtime is pinned by a golden case, but only on the bash leg.** `racily_clean_same_size_edit` fixes the indexed mtime, the file's post-edit mtime, and the index file's own mtime to one instant and sets `core.checkStat minimal`, so the racily-clean rule is git's only remaining reason to re-read the content; removing `cp -p` reddens it on every run. The pwsh mutation does not redden on macOS, because `Copy-Item` preserves the timestamp there on its own: the explicit `LastWriteTimeUtc` restamp is what makes that guarantee platform-independent, and the bash mutation is what proves the property is load-bearing.
- **`unreadable_seed_is_loud` cannot run everywhere.** It needs a real index the process cannot read, which `chmod 000` gives on Unix and Windows does not, so the case skips on Windows and on any root user, and the rule is enforced there only by the bash leg. A `FileShare::None` handle was considered and rejected: it blocks a copy on Windows but not on macOS, so it moves the gap rather than closing it, and it could not be verified from here. Swallowing the pwsh copy error does not redden the case either, because `Copy-Item` leaves a zero-byte destination behind and git then rejects that index outright ("index file smaller than expected"), so the pwsh leg fails loud by a second route rather than by the rule under test.
- A snapshot failure on a healthy repo (an unwritable temp dir, a full disk) has no golden case: the two that exist reach the branch through a directory that is not a repo and through a bare one. Classify mode degrades to `code-changed` `no-delta` there, and snapshot mode exits 1, but neither path is exercised under a real write failure.
- The seed is deliberately a hard failure: a real index that exists and cannot be copied returns no hash rather than falling back to an empty index, because that fallback is exactly the tracked-and-ignored blind spot the release fixes.
- `CHANGELOG.md` carries no `## v1.24.1` section. 1.24.1 shipped in `3502b37` (#623) without one, and this entry does not invent one.
- Ceiling state a contributor's next edit hits: `skills/solve-issue/post-fix-commit.md` measures 4310/4500 bytes and 649/700 words, `skills/solve-issue/SKILL.md` 41983/44000 bytes and 5862/6200 words. No ceiling was raised on any axis. The advisory CRLF `WARN` on `skills/solve-milestone/changelog-authoring.md` (85 bytes free) predates this change and is untouched.

## v1.24.0 - diff-classified review depth, unconditional merge, /simplify at milestone end

**Theme:** Review effort stops being guessed from an issue's pre-build risk label and starts being classified from the diff the implementer actually returned. The visual-review hold is gone at every integration granularity, so a UI issue auto-merges on green CI exactly like a logic issue. `/simplify` runs once at milestone end. The code-review gate stops accepting a bare heading as proof a review happened.

### ✨ Review depth comes from the diff

| Issue | PR | What |
|---|---|---|
| #598 Add the classify-review-depth script twin | #612 | `scripts/classify-review-depth.{sh,ps1}` prints `deep`, `standard`, or `shallow` on stdout with a reason token on stderr, exit 0 always. Its step order is load-bearing: git probe, candidate set, emptiness, shape filter, then the `hooks/**` trigger, and only then the config and glob reads, so a repo with no profile keeps the highest-value trigger. Candidates come only from `git -C "$ROOT" diff --name-status HEAD` and `git -C "$ROOT" ls-files --others --exclude-standard --full-name`; matching is pure pattern-versus-string with no filesystem probe, and `find`, `ls -R`, and recursive expansion are forbidden outright. A shape-rejected path floors the verdict at `standard` rather than passing silently. 44 golden cases plus 4 bespoke, each proven to redden under its own mutation and no other. |
| #608 Resolve review depth from the diff at solve-issue step 6.1 | #617 | Step 6.1 invokes the classifier against the implementer's uncommitted diff immediately before `/code-review` dispatches, and takes its stdout verdict verbatim. `deep` sets `medium` effort and 2 cycles; `standard` sets `medium` and 1, a 2nd only on a Critical or Important finding; `shallow` sets `low` and 1, a 2nd impossible. `high` and `xhigh` are retired from the ladder and `medium` is the ceiling. The `### Build profile resolution` table loses its effort and cycle columns, so `risk` now drives only the `risk:light` brief token and the E2E gate's skip. |
| #609 Move parallel-mode review-depth resolution from Phase 1 step 4 to step 7 | #617 | Parallel mode had resolved effort at Phase 1 step 4, before Stage A dispatched any implementer, and Stage B passed that pre-build value through. The classifier needs a diff, so the resolution moves to step 7, run on the orchestrator's main line against that issue's worktree, immediately before the reviewer leaf. The two modes now agree on the same issue. |

Both modes carry the same second-cycle stopping condition, worded identically: a second cycle returning **any** Critical or Important finding parks the issue `needs design`, and no third cycle runs. The issues as filed asked for a finding "in the same rule as cycle 1's", which is unbuildable, because the review finding shape carries severity, a `file (anchor)` ref, and free text with no rule field. Severity alone is mechanically checkable and strictly more conservative.

### ✨ The visual-review hold is retired

| Issue | PR | What |
|---|---|---|
| #599 Remove the solve-issue visual-review hold and make auto-merge unconditional | #613 | `skills/solve-issue/visual-review-hold.md` is deleted and step 7 with it. `skills/solve-issue/SKILL.md` step 8 is now "Auto-merge on green": `gh pr merge --squash --delete-branch` runs for **every** issue, with no UI branch in front of it. Visual capture moves into step 6.8 as optional, never-gating evidence guarded on the PR's diff matching `uiSurfaceGlobs`, so a logic-only issue no longer boots a server to publish an empty comment. `skills/solve-issue/milestone-clauses.md` folds its 6.7 row into 6.8, and `resume-paths.md`'s open-PR resume path goes straight to auto-merge. |
| #600 Remove the needs-review hold from the solve-milestone waves and merge tail | #613 | The Phase 2 serial verified merge tail integrates **every** built-green branch, UI included, instead of excluding UI branches and leaving them labelled `needs review` for a human. One wave PR carries the whole assembled Wave and one milestone PR carries the whole milestone. |
| #601 Retire the `visualHold` key and sweep the docs | #613 | Every documentation and config-schema reference to the per-issue, per-wave, and per-milestone hold is gone. `docs/architecture.md` drops from three gating layers to two and from three `visualCapture` invariants to two. `docs/profile-schema.md` loses the `visualHold` row, its Integration-tier entry, and its note. `docs/consumer-setup.md` loses the visual-review-gate bullet and the whole `visualHold` section. |
| #607 Remove the remaining visual-hold call sites | #613 | `milestone-granularity.md` loses the whole `### The visualHold gate` section; milestone-end step 4 merges on green unconditionally. `trello-sync.md` drops the not-ticked caveat and the open-UI-PRs summary field. `md-epic-fanout.md`'s outcome table goes from five outcomes to four, rekeyed on the `needs review` label the red-CI handler applies rather than on a hold. Visual capture's one hard precondition, a live per-issue PR to comment on, is now stated once as a guard in `visual-capture.md` and cited by its five callers rather than re-derived per granularity: `wave-clauses.md` had derived it wrong, letting a sequential `"wave"` run boot the render daemon and reach Publish with no PR to post to. |

### ✨ The code-review gate parses the verdict

| Issue | PR | What |
|---|---|---|
| #604 Make the code-review gate parse the run verdict, not just the heading | #616 | `hooks/code-review-gate.{sh,ps1}` stop treating a present `## Code Review` heading as sufficient and read the `/code-review run:` value inside it. Matching is exact and case-sensitive. Two deviations are load-bearing: the token is bounded to the slot's own line, else an empty slot adopts the next bullet's text; and one wrapping quote is stripped per side, else `--body "...run: yes"` yields the token `yes"` and denies a correct body. The span walks anchored heading matches last to first and takes the first holding a slot, so a findings line citing the gate's own `heading='## Code Review'` variable, or a `--title` carrying the phrase, no longer false-denies. Every slot in the span is read, so an aggregated wave or milestone PR cannot pass on its first sub-entry while a later one denies. |
| #611 Document the accepted /code-review run values | #616 | `docs/consumer-setup.md`, `docs/profile-schema.md`, and both `docs/architecture.md` rows state the verdict parse rather than heading presence. The release-PR audit line no longer tells a reader to copy the CHANGELOG PR's `n/a`, since a release PR carries the milestone's `sourceGlobs` changes and `n/a` would be false. The gate exemption is re-attributed to the fetched `baseRefName` via `gh pr view` rather than to `--base`. |
| #606 Announce the removed hold and the verdict gate as one-time notices | #616 | `visual-hold-removed` and `code-review-run-no` in `skills/notices.md`, worded per granularity: whichever PR your `integrationGranularity` opens merges on CI green. |

### ✨ /simplify runs once at milestone end

| Issue | PR | What |
|---|---|---|
| #610 Run /simplify once after the milestone build loop completes | #615 | `skills/solve-milestone/simplify-pass.md`, read-directed from a new `### Simplify pass` between step 4's loop and step 5. One unguarded insertion at loop exhaustion, where both execution modes converge, so the pass runs exactly once per run: never per Wave, never per issue. The file opens with a 12-step ordered sequence whose invariant is stated as a rule: every branch operation precedes the first write. `/simplify` runs on the orchestrator's main line, because it fans out four cleanup agents concurrently and a dispatched pass would seat all four at depth 2; its apply phase does not, because those are main-thread writes `force-subagent` denies under `sourceGlobs`, so a dispatched `implementerAgent` applies. The commit carries a `Simplify-Pass: <milestone-number>` trailer, which cannot collide with the per-issue `Issue: #<n>` query. |

### 🧹 Code comments, and the conventions behind them

| Issue | PR | What |
|---|---|---|
| #602 Add a Code comments section to .project/conventions.md | #614 | A comment earns its place only by recording a non-obvious *why*: a constraint, an OS-specific hazard, an ordering requirement, or a rejected alternative. Comments that restate the code, narrate a change, carry editing history, or label a section are prohibited. `scripts/classify-delta.sh`'s header is the permitted exemplar. `skills/output-style.md`'s two anti-criteria stay scoped to GitHub-facing prose and are not widened. |
| #603 Revise Layering & boundaries and One-way doors | #614 | `## Layering & boundaries` drops Layer 2 and `## One-way doors` drops the never-auto-merge-a-UI-issue door, both retired by the hold removal. |
| #605 Carry the code-comment rule into the briefs | #617 | The rule rides the implementer's dispatch brief and `agents/implementer.md` contract item 8, so a directly dispatched implementer enforces it without the skill, identically under `risk:light`. Both reviewer briefs put comment text out of review scope at every severity, with one carve-out: a change to a machine-read directive stays reviewable, pointing at the enumeration `scripts/classify-delta.sh (is_directive <src>)` already enforces rather than a second copy. |

### 🧹 The /simplify pass over this release

The milestone's own `/simplify` pass ran over `8730ed9...a8ed210` and returned findings from four lenses. Sixteen were applied in this release; nine are filed as follow-ups. Six were shipped defects rather than cleanliness:

- **`classify-review-depth.{sh,ps1}` dropped the legacy profile read.** It looked only at `.milestone-config/driver.json`, unlike every other reader in the repo, so a repo still on the legacy layout emitted `no-config`, fell open to `standard`, and silently downgraded a `deep` diff to one review cycle. Because the `hooks/**` trigger fires above the config read, the failure was invisible in the exact case the header uses to justify that ordering.
- **The two execution modes had already drifted.** `post-fix-commit.md` said a verdict rising to `deep` runs the 2nd cycle "already granted"; `parallel-waves.md` dropped that qualifier and read as an unconditional grant under a first verdict of `standard` or `shallow`.
- **`deferred` was accepted with no legitimate producer.** Omitting `/code-review` is a park trigger and a parked issue opens no PR, so no state produced it, and nothing in the repo defined when to use it. It is retired from both legs and every documenting site. The accepted set is now `yes` and `n/a - <reason>`.
- **The 5000-word cap paragraph named a ceiling matching neither table**, old or new.
- **The "verbatim" code-comment rule was not verbatim**, differing by a separator across its three copies.
- **The ceiling header gained 57 lines of change narration** in the same window that shipped a rule against narrating changes, with the header's own text already saying that record belongs in the PR body.

The rest cuts prose that argues rather than states, replaces five hand-synced marker enumerations with one `*-notice` glob, drops two citations pointing at a rule they did not cover, and removes two branches the input cannot produce.

### Consumer notes (upgrading from v1.23.3)

- **Breaking: the `visualHold` profile key is retired.** It is removed from the schema, not deprecated. Delete it from `.milestone-config/driver.json`; a leftover key is inert and is read by nothing. There is no replacement, because there is no hold left to override.
- **Breaking: `/code-review run:` is now parsed.** A PR body carrying a `## Code Review` heading with no verdict, an empty verdict, or an unrecognized one is denied at both `gh pr create` and `gh pr merge`. Accepted values are `yes` and `n/a - <reason>`, matched exactly and case-sensitively, so `Yes` and `YES` deny. `CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1` and the `protectedBranch` base exemption are unchanged.
- **`risk:heavy` and `risk:light` no longer set review effort.** They keep their meaning for the implementer brief token, the E2E gate's skip, and the triage gap table. Review effort and the cycle cap come from the diff classifier at review time. If you relied on `risk:heavy` to force a deeper review, note that `medium` is now the ceiling in every case.
- **UI issues auto-merge.** A PR whose diff touches a `uiSurfaceGlobs` path merges on green CI like any other. If you relied on the hold as your review checkpoint, use branch protection or a required reviewer on `integrationBranch` instead.
- **`needs review` survives, with a new meaning.** The label keeps its name and its `0E8A16` colour, so it is not orphaned on your repo, but it now flags a PR whose CI came back red rather than a UI PR awaiting sign-off. It is applied to a PR, never to an issue, and it is still not a park.
- **A `/simplify` pass now runs at milestone end** and may open one `chore/simplify-<milestone-slug>` PR into `integrationBranch`, or fold a commit onto the milestone branch under `"milestone"` granularity. It never gates: every failure logs one line and the run proceeds.
- New gitignored artifact: none. New profile keys: none. Removed profile keys: `visualHold`.
- **Released entries below still name `visualHold` and `high`/`xhigh`.** Changelog history is not rewritten to scrub later-retired terms, so a repo-wide `grep` legitimately hits this file's pre-1.24.0 sections. Leave them.

### ⚖️ Post-run audit trail

Judgment-call PRs: #614, the only PR in this release held for human sign-off, since both its halves edit human-owned `.project/` files.

- **Ceilings: four raised, six ratcheted back down.** #605/#608/#609 raised `skills/solve-issue/SKILL.md` (BYTE, WORD), `post-fix-commit.md` (BYTE, WORD), `parallel-waves.md` (BYTE, WORD), and `agents/implementer.md` (BYTE), each with recorded arithmetic. #606 raised `skills/notices.md` (LINE, BYTE, WORD), the BYTE value a restore of what `a215feb` had tightened. The `/simplify` pass then ratcheted six rows down: `solve-issue/SKILL.md` LINE and BYTE, `wave-clauses.md` BYTE, and all three of `simplify-pass.md`. Net, the ratchet moved the wrong way this release before the pass corrected part of it, and `skills/solve-issue/SKILL.md` and `parallel-waves.md` both moved **further** from the 5000-word cap they are meant to be split toward.
- **Inherited discrepancy, not filed:** `CLOSURE skills/solve-milestone/SKILL.md` reads 9236/9200, over its ceiling. It was already over at 9242/9200 before the simplify pass, and #606's recorded raise claimed it "holds at 9167/9200", which was stale when it shipped. Closures are informational and gate nothing, so the run exits 0. Not re-seeded, because a raise here would contradict the same release's rule against narrating a change to justify one.
- **Gate gap found by the pass, filed as a follow-up:** `check-citations` records a `path#Heading` or `path § Heading` reference as UNVERIFIED rather than resolving it. Two dangling section references shipped inside this release and were caught by hand, not by the gate. It also scans gitignored files, so a per-clone `triage-cache.json` produces phantom FAIL rows locally that CI never sees.
- **Open defect, not filed and not widened here:** under `integrationGranularity` `"issue"` and `"wave"`, a red per-issue or wave PR leaves its issues open with no blocker label and no `milestone-<number>-<slug>` PR, so the md-epic fan-out matches none of its four outcomes. The retired `held for visual review` leg never covered it either, both being keyed on the same head filter.
- **Ceiling state a contributor's next edit hits:** `skills/solve-milestone/changelog-authoring.md` and `skills/output-style.md` both WARN that a CRLF checkout would fail the row. `skills/solve-issue/visual-capture.md` sits near its word ceiling after taking the shared capture guard.
- The `needs review` label survives the hold it was named for. Its name and `0E8A16` colour are byte-identical across `docs/architecture.md`, both `skills/setup/SKILL.md` sites, and the milestone-granularity handler that now creates it, so no consumer repo is left with an orphaned label.

## v1.23.3 - agent brief read scope, domainSkills invocation

**Theme:** A dispatched agent is now handed the absolute path of every plugin file it must read and a rule forbidding it to search above the repo root, and `domainSkills` finally resolves to names the Skill tool can invoke, with each agent reporting which it used.

### ✨ domainSkills becomes invocable and observable

| Issue | PR | What |
|---|---|---|
| #589 `domainSkills` is never invoked: wildcard values are not invocable and no return slot records consultation | #594 | The profile's `domainSkills` was briefed to every agent but never invoked: `plugin-dev:*` has no Skill-tool invocation, and no return block recorded whether the research-path step ran, so an agent that wanted the grounding walked the plugin cache on disk instead. A new `scripts/expand-domain-skills.{sh,ps1}` twin expands `<plugin>:*` against the cache, selecting the highest name matching `^[0-9]+(\.[0-9]+)+$` by component-wise numeric compare and falling back to the byte-last name, so a plugin whose only cache directory is `unknown` still resolves. `skills/triage/SKILL.md`, `skills/solve-issue/SKILL.md`, and `skills/setup/SKILL.md` expand at profile read and brief the expanded list; an expansion returning nothing is treated exactly as an absent key, and every dropped entry is named as `domainSkills unresolved: <entry>`. Setup takes and records exact names. All four agent briefs now mandate Skill-tool invocation and never a disk lookup, and `triage-reviewer`, `design-reviewer`, `implementer`, and `blocker-resolver` each return `DOMAIN_SKILLS_INVOKED`, which the orchestrator copies into the triage comment and the PR Decision Log. Ungated: a `none` value blocks nothing. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #588 Agent briefs give no read scope and cite `skills/citation-format.md` by a path that does not resolve; agents `find /` | #590 | Six sites across the four agent briefs cited `skills/citation-format.md` by a repo-relative path, which resolves against the consumer repo where the file does not exist, and no brief bounded reads, so a dispatched agent resolved the name by walking the filesystem: one recorded triage-reviewer ran `find / -iname "hook-development*"` and hit the 2-minute Bash timeout at exit 143. Orchestrators now hand in `citationFormatPath`, the absolute path of `${CLAUDE_PLUGIN_ROOT}/skills/citation-format.md`, at every site that composes an agent brief, and all four agent briefs carry a verbatim read-scope rule: the worktree or repo root named in the brief plus the handed-in absolute paths, never a search against `/`, `/c`, `~`, `$HOME`, `~/.claude`, or any directory above the repo root, and a file not found inside the scope is reported as not found. `skills/output-style.md`'s evidence-slot rows moved with them, since that section is threaded verbatim into every brief and each agent's `## Communication style` gives the contract precedence on conflict. |

### Consumer notes (upgrading from v1.23.2)

- **`domainSkills` now takes exact `plugin:skill` names.** A wildcard already in your `.milestone-config/driver.json` keeps working: the three profile-read callers expand it before briefing, and a setup re-run expands a pre-filled or inferred wildcard rather than rejecting it. A wildcard you type at the setup prompt is refused with `domainSkills entries are exact plugin:skill names; "<entry>" is not invocable`.
- **A `<plugin>:*` whose plugin is not installed locally expands to nothing and is currently refused by setup as a shape error.** Install the plugin before recording it, or write exact names. Tracked as #593.
- **Agents no longer search outside the repo.** A reviewer or implementer that cannot find a file inside its scope reports it as not found rather than locating it elsewhere, so an agent relying on a plugin file it was not handed will say so instead of walking the cache.
- New gitignored artifact: none. New profile keys: none.
- **`domainSkills` value semantics changed**; every other key in `.milestone-config/driver.json` is unchanged.

### ⚖️ Post-run audit trail

Judgment-call PRs: #590, #594.

- #588's acceptance criterion 4 requires transcripts from `/milestone-driver:triage` and `/milestone-driver:solve-issue` runs in a consumer repo. No gate in this repo evaluates it: the shipped checks verify that no `agents/` file cites `skills/citation-format.md` and that each of the four carries the read-scope rule, not that a dispatched agent obeys it.
- #588 requirement 1 also named `skills/solve-milestone/sequential-loop.md` as a leaf dispatch site. It was deliberately not edited: it runs `solve-issue` in-thread on the main line, so the brief it would amend is the one `skills/solve-issue/SKILL.md` composes, and its row has 48 free bytes with no trim authorization.
- Open defects with issue numbers: #591, the read-scope rule's closing sentence instructing three read-only agents to run `npm ci`, and the rule never reaching the reviewer and coherence leaf briefs, which are `general-purpose` and third-party agents this plugin does not own; #593, a cache miss reported as a shape error, the unbounded invoke-every-name mandate against a whole-plugin expansion (41 names for `maui-skills:*`), `docs/profile-schema.md`'s claim against this repo's own profile, and exact entries getting no existence check.
- Both issues' PRs were reviewed three times each. #589's third review found two defects that CI could not: `[long]::Parse` on an over-Int64 version component threw under StrictMode, exiting 1 with empty stdout against the script's fail-open contract, and the two legs picked different directories on a magnitude tie because `Directory.GetDirectories` order is unspecified. Both are fixed and pinned by golden rows.
- Ceiling state a contributor's next edit hits: no ceiling was raised on any axis this release. The advisory CRLF `WARN` fires for three files, all untouched here: `skills/solve-milestone/SKILL.md` 15 bytes free, `skills/solve-milestone/changelog-authoring.md` 11, `skills/output-style.md` 57. `agents/design-reviewer.md` sits at 119/120 lines, so the next edit there must trade a line.

## v1.23.2 - hook gate integrity, CI venue closure, margin restoration

**Theme:** The two bash hooks gate again under the `/bin/bash` macOS ships and now cover `scripts/` and `tests/`, the size-budget twins warn before a CRLF checkout fails a row, both shell-test legs run the same 17 runners, and the Blocked comment, CHANGELOG step 6.2, and the conventions table state what the shipped code actually does.

### ✨ Gate scope, margin, and recorded contracts

| Issue | PR | What |
|---|---|---|
| #573 sourceGlobs omits `scripts/**` and `tests/**`, so first-class source is ungated | #579 | This repo's tracked `.milestone-config/driver.json` listed three globs while `.project/conventions.md#File & folder layout` treats `scripts/` and `tests/` as first-class source, so `force-subagent` never gated a direct main-thread edit to either tree. The profile now carries five globs: a main-thread Write/Edit under `scripts/` or `tests/` denies at exit 2, while subagent writes and the `docs/` + `.claude/` exemptions are unchanged. The coded fallback in `scripts/build-file-index.{sh,ps1}` still ships three, so no consumer's behavior moves. |
| #574 md-epic-fanout has 13 bytes of headroom against a 52-byte CRLF cost, and nothing warns | #581 | `skills/solve-issue/md-epic-fanout.md` sat at 8487/8500 bytes over 52 lines, so a `core.autocrlf` clone read roughly 8539 and failed the gate on a fresh Windows checkout. Two cuts of provenance and restatement bring it to 8386/8500, headroom 114 against 52 lines. Both `check-size-budgets` twins now emit `WARN <path> <free> bytes free < <lines> lines (a CRLF checkout would FAIL this row)` after any OK row in that state; the row is advisory, and SUMMARY counts and exit codes are untouched. |
| #575 The 🔴 Blocked comment still instructs the manual label removal #516 automated | #578 | The Blocked comment's unblock line said "remove this `blocked` label and re-run" at three sites, though `skills/solve-milestone/blocked-label-clear.md` clears the label automatically on the next run once every upstream merges. All three sites now state the self-clear: `not-buildable.md`'s byte-fixed comment body, its transitive-dependent restatement, and `output-style.md`'s Blocked-comment row slot. The `🔴 Blocked - ` opener is byte-unchanged, so the downstream literal matches still hold. |
| #576 changelog 6.2 extracts a problem-only What; the shipped half lives in the Decision Log | #580 | Step 6.2 of `skills/solve-milestone/changelog-authoring.md` reads the PR body's opening prose block, which on 5 of milestone #40's 6 merged PRs states only the problem, leaving the shipped-behavior half in the PR's `## Decision Log`. 6.2 gains one conditional clause: where the block carries no shipped-behavior half, complete it from that Decision Log's choices, never their rationale. |
| #577 conventions.md lacks the pwsh byte-domain collation idiom #471 shipped at four sites | #583 | #471's byte-order collation idiom (respell each string as `Latin1.GetString(UTF8.GetBytes(s))`, then compare with `StringComparer.Ordinal`) shipped at four pwsh sites with nothing recording it, so the next twin author re-derives or diverges. One row appended to `## Canonical exemplars (mirror these)` names `scripts/check-citations.ps1 (function ToByteChars)` as the exemplar, its three sibling sites, and the two banned near-idioms: bare `Ordinal` is UTF-16 code-unit order, `Sort-Object` is culture order. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #571 hooks fail open under macOS /bin/bash 3.2: `**` sourceGlobs match nothing | #582 | Under the `/bin/bash` 3.2.57 macOS ships, `pat="${g//\*\*/\*}"` kept the backslash, so every `**` sourceGlob flattened to a literal `\*` and matched nothing: `hooks/force-subagent.sh` exited 0 on a main-thread source edit that must exit 2, and `hooks/tests-green.sh` never ran `unitTestCmd`. Both hooks now flatten through quoted variables, byte-identical on 3.2.57 and 5.3.15. A new `tests/force-subagent.test.{sh,ps1}` runner pair covers the deny path, both bash hook runners pin the hook child to `/bin/bash` on Darwin, and three CI steps register the pair. The pwsh hooks never carried the defect. |
| #572 shell-tests-pwsh runs every pwsh runner except read-doc-section | #584 | `tests/read-doc-section.test.ps1` was the one runner the pwsh job never ran, while the bash leg has carried its mirror step since #551. One step, `read-doc-section (pwsh)`, now sits between classify-delta and tests-green as it does on the bash leg; both legs run the same 17 runners in the same order. |

### Consumer notes (upgrading from v1.23.1)

- **The hooks gate again on stock macOS bash.** Under `/bin/bash` 3.2, `hooks/force-subagent.sh` now denies main-thread edits to paths matched by a `**` sourceGlob that it previously allowed, and `hooks/tests-green.sh` now runs `unitTestCmd`. A Mac repo that appeared to have no gate starts enforcing both on the next edit.
- **`check-size-budgets.{sh,ps1}` emit a new `WARN` line** for any governed file whose free bytes are fewer than its line count. Exit codes and the `SUMMARY ok=/failed=` counts are unchanged, but a parser assuming every non-`FAIL` row starts `OK` now sees a third first field.
- **`sourceGlobs` is unchanged for consumers.** The five-glob set is this repo's own profile; the coded fallback still ships `skills/**`, `agents/**`, `hooks/**`. Add `scripts/**` and `tests/**` to your `.milestone-config/driver.json` to gate those trees.
- A dependency-hold 🔴 Blocked comment no longer asks you to remove the `blocked` label by hand; re-running `solve-milestone` clears it.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- Both defects the v1.23.1 trail recorded as unfiled are now fixed: the bash 3.2 hooks fail-open (#571, here) and `tests/render-daemon.test.sh` on the macOS runner (#570, before this milestone). #582 merged on a green board, its new force-subagent deny step passing its first `/bin/bash` 3.2 CI outing.
- Triage did not run for this milestone by recorded decision: all seven issues were authored and fact-verified in one session with citations pre-resolved, so no issue was gap-checked by the triage lens before build.
- The new `WARN` row is advisory, so no gate fails on a thin margin: a CRLF checkout still discovers the overflow at `FAIL` time, and the three files below stay unrepaid by design.
- Ceiling state a contributor's next edit hits: no ceiling was raised on any axis this release, and both files that needed room (#576, #574) paid for it with byte trades. The advisory `WARN` fires today for exactly three files: `skills/solve-milestone/SKILL.md` 15 bytes free, `skills/solve-milestone/changelog-authoring.md` 11, `skills/output-style.md` 43. `skills/solve-issue/md-epic-fanout.md` is CRLF-safe again at 114.
- Open, no issue number: `skills/setup/SKILL.md`'s inference table still infers three sourceGlobs for "a Claude Code plugin", so a future bootstrap reproduces the gap #573 fixed (recorded as a candidate follow-up in #579's coherence pass).

## v1.23.1 - twin collation, gitignore self-heal, wave-PR review aggregation

**Theme:** The pwsh legs collate in byte order like their bash twins, every runner executes under the bash macOS ships, the tests-green self-heal writes the committed 12-entry set, and each wave, fan-out, and triage contract that previously left a run with no defined answer now states one.

### ✨ Wave, fan-out, and triage contracts

| Issue | PR | What |
|---|---|---|
| #518 resume-paths has no wave note, so a resumed run re-verifies an already-integrated issue | #553 | Under `"wave"` granularity step 6.6 opens no per-issue PR, so path (a) matched nothing and a resumed run fell to path (b), re-verifying shipped work and ending by opening a PR 6.6 forbids. A new note evaluated before (b) makes a non-empty `git ls-remote --heads origin "issue/<n>-*"` the terminal exit. |
| #509 Wave PR body names a Code Review section but not how per-issue reviews aggregate into it | #555 | The `Wave PR body` row now states the shape: exactly one anchored `## Code Review` heading, one `### #<n>` sub-entry per logic issue, a one-logic-issue Wave included, no special case. `integration-granularity.md` names each sub-entry's source and `wave-clauses.md` cites the row instead of restating it. |
| #520 wave-clauses states no home for a non-UI issue's Decision Log or judgment-call label | #556 | Two rows mirroring the milestone clauses: the Decision Log and Code Review section ride the step-6.5 commit trailer, the `judgment call` label goes on the issue, the post-run review is the single wave PR's. 6.7's visual-review gate is a no-op for these issues and defers nothing upward. |
| #511 md-epic fan-out: a held milestone PR plus a parked issue matches two Outcome bullets | #558 | A milestone PR held for visual review together with an issue carrying a blocker label left the single-valued Outcome cell undecided. `parked with opens` now wins, since a blocker label is the root block; the Note column still reports both facts. |
| #514 blocker-resolver: the agent and its enforcement row admit different evidence | #560 | The agent's Rigor gate permitted a sibling issue number that the dispatch table's per-verdict rows did not, so a compliant `RESOLVED` verdict was demoted to `NEEDS_HUMAN`. The Rigor gate now states the admissible set once (citation, recorded line, sibling issue number, or command output), and the dispatch table plus both `evidence:` templates cite it. |
| #515 clearLabel has no unconditional default in the contract that defines it | #559 | `clearLabel` defaults to `false` when a return omits it and only an explicit `true` removes a label. The default sits in the Step 7 `issueStates` contract rather than only in a branch-gated dispatch file unread on runs where no MISS issue carries a Blocker. |
| #516 A dependency hold never clears its own blocked label once the upstream merges | #561 | New governed `skills/solve-milestone/blocked-label-clear.md`, hooked from step 4 under condition (a) ahead of (b)'s live-label read: where every issue in `dependencyGraph.edges["<n>"]` passes the merged/trailer check and `blocked` is that issue's only blocker label, the run removes it. Clearing derives from the graph, never the comment text; an unmerged upstream keeps both label and 🔴 Blocked comment, and the one hook covers both execution modes. |
| #524 changelog-authoring's PR-summary and theme extraction do not match the artifacts this repo produces | #562 | Step 6.2 reads the PR body's opening prose block between the `Closes #N.` line and the first `##` heading, never looking for or adding a `## Summary` heading no merged PR carries. Step 6.4's no-`Theme:` fallback derives the theme sentence from the milestone description's own prose instead of restating the entry heading, and pins the heading theme to title-minus-version-prefix. |
| #512 md-epic fan-out: pending milestone-PR CI reports green, with no Note leg of its own | #563 | The milestone-PR Note probe returns the bucket list and reads three legs: any `fail` is red, else any `pending` is CI in flight with the Outcome staying **held for visual review**, otherwise green. A still-running CI no longer reports green; the no-CI vacuous-green case is unchanged. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #468 Three test runners use bash 4.3 namerefs and report 0 passed under the bash macOS ships | #551 | The `local -n` nameref in `split_tab()` made `extract-version`, `build-file-index` and `parse-md-epic-order` report 0 passed under the `/bin/bash` 3.2.57 macOS ships. Each now carries the global-`cols` shape four other runners already hold. CI closes the venue gap: `hook-smoke-macos` gains one explicit `/bin/bash` step per runner, all 15, and `shell-tests-bash` gains its missing `read-doc-section` step. |
| #471 The pwsh legs collate strings differently from the bash legs, so twin output diverges | #554 | `triage-cache.ps1`, `build-file-index.ps1` and `ci-preflight-steps.ps1` sorted in UTF-16 code-unit and culture order, both of which diverge from the bash legs' `LC_ALL=C`: astral characters sorted before `U+E000`–`FFFF`, and plain ASCII case was re-ranked. All three now sort a parallel UTF-8 byte-key array, the idiom `check-citations.ps1` already ships. Three new fixtures pin the parity on both legs. |
| #499 tests-green's .gitignore self-heal writes 6 entries where the committed authority carries 12 | #552 | The self-heal is create-only, so a consumer repo whose `.milestone-config/.gitignore` was written by tests-green never gained the six notice-marker names and those markers surfaced in `git status`. Both twins now emit the full set byte-identical to the committed authority, covered by a new `tests/tests-green.test.{sh,ps1}` pair registered in both shell-test CI jobs. |
| #517 check-citations.ps1 takes its root positionally while its two sibling checkers take -Root | #550 | `scripts/check-citations.ps1` now takes its root through `param([string]$Root = (Get-Location).Path)`, the shape `check-size-budgets.ps1` and `check-doc-toc.ps1` already use. `-Root .` works and the positional call sites, CI included, are byte-unchanged. |
| - `hook-smoke-macos` went red when #468's per-runner steps landed | #557 | The runners execute on the explicit `/bin/bash` 3.2 that is the job's venue, but launch the scripts under test through a PATH lookup that also resolves 3.2, and `scripts/extract-version.sh` and `scripts/build-file-index.sh` need bash 4+ for `mapfile`. One step after the hook-smoke fixtures prepends `$(brew --prefix)/bin` via `GITHUB_PATH`: runners keep executing on 3.2, their children resolve a modern bash. |

### Consumer notes (upgrading from v1.23.0)

- **A `.milestone-config/.gitignore` written by an earlier `tests-green` keeps its 6 entries.** The self-heal is create-only, so it will not repair an existing file: add the six notice-marker names by hand, or delete the file and let the hook rewrite the full 12.
- **A dependency hold now clears its own `blocked` label** once every upstream in `dependencyGraph.edges` has merged and `blocked` is the issue's only blocker label. An issue that previously stayed unbuildable until a human removed the label re-enters the build set on the next run.
- **pwsh script output ordering changes.** `triage-cache.ps1`, `build-file-index.ps1` and `ci-preflight-steps.ps1` now collate in byte order, matching their bash twins; output diffed against a pre-1.23.1 run reorders for non-ASCII and mixed-case names.
- `scripts/check-citations.ps1` accepts `-Root <path>`; positional invocation still works.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: #556 (recorded ceiling raise, `skills/solve-issue/wave-clauses.md` byte axis 3000 → 3500, arithmetic in the PR body), #561 (registered the new governed file in `check-doc-toc.{sh,ps1}` beyond the brief's named twins, per the one-governed-set definition).

- Unfiled defect, no issue number yet: `hooks/tests-green.sh:25` and `hooks/force-subagent.sh:50` fail open under bash 3.2, where `${g//\*\*/\*}` keeps the backslash, so every `**` sourceGlob matches nothing: force-subagent allows source edits it should block, and tests-green never fires. #557's PATH pin also masks the accidental 3.2-child coverage `tests-green.test.sh` had.
- Unfiled defect, no issue number yet: `tests/render-daemon.test.sh` is 8 passed / 5 failed on the macOS CI runner, its stub `python3 http.server` never becoming ready on 127.0.0.1. #557 unmasked it; the step had never executed there because the job died earlier at `extract-version`.
- Ceiling state a contributor's next edit hits: `skills/output-style.md` 48 bytes free, `skills/solve-milestone/changelog-authoring.md` 16 bytes free, `skills/solve-issue/md-epic-fanout.md` 13 bytes free, `skills/solve-milestone/SKILL.md` 15 bytes free. A Windows autocrlf clone measures md-epic-fanout at roughly 8539/8500, a known CRLF-margin exposure.
- The new governed `skills/solve-milestone/blocked-label-clear.md` ceilings 25/2500/400 were derived arithmetically per the documented discipline, not raised; #556's byte raise above is the run's only ceiling change.

## v1.23.0 - wire the driver's triage park to the feeder's remediate verb

**Theme:** The driver's triage park gains a hand-off to `/milestone-feeder:remediate`: solve-issue and solve-milestone ask once at run start whether to auto-remediate blocked issues, and the triage comment names the verb in every branch.

### ✨ Remediate handoff

| Issue | PR | What |
|---|---|---|
| #533 Add the shared remediate-handoff reference and register it in the governance tables | #541 | New `skills/remediate-handoff.md` carries the whole procedure once (gate, question, Auto loop with cap 1, park-for-good branches); registered on all four governance legs, excluded from every load closure. |
| #534 Name the remediate verb in the triage comment's closing line on both branches | #540 | The `🔴 Triage` closing line now names `/milestone-feeder:remediate <n>` at both Step-6 sites, byte-identical, with the literal embedded in the instruction bullet. |
| #535 Wire the remediate handoff into solve-issue's run start and Blocker park | #543 | Sub-step 1.1.2 asks the run-start question behind a feeder-resolvable probe (caller answers reused, never re-asked); a held Auto answer routes the step-0 Blocker park through the Auto loop. |
| #536 Wire the remediate handoff into solve-milestone's run start, Phase 0, and the not-buildable park | #544 | Before-starting sub-step 5.1 asks once (probe before read; `MILESTONE_DRIVER_NONINTERACTIVE=1` defaults to Leave-them-for-me; `--driven` does not gate it); Phase 0 parks and the not-buildable triage-park bullet route through the Auto loop, scoped to unspent `needs design`/`needs decision` parks. |
| #537 Document the remediate handoff as an optional integration in the architecture and consumer docs | #542 | `## Remediate handoff (optional)` sections in `docs/architecture.md` and `docs/consumer-setup.md`; installing the feeder is the only switch. |
| #538 Wire the remediate handoff into the parallel-mode per-issue park site | #546 | A held-Auto step-0 Blocker park in parallel mode enters the Auto loop before the drop; a clean re-triage keeps the issue in the parallelizable set, dispatching into Stage A on its existing worktree. |
| #539 Report auto-remediate outcomes on the run boards and the final summary | #545 | Note/Follow-up cells carry `remediated, cleared` / `remediated, still parked` / `NEEDS_HUMAN, parked`; icon legends untouched. |

### Consumer notes (upgrading from v1.22.1)

- With milestone-feeder installed, `solve-issue` and `solve-milestone` ask one new run-start question: auto-remediate blocked issues, or leave them for you. Feeder absent → no question, no behavior change; unattended runs default to Leave-them-for-me.
- The `🔴 Triage` comment's closing line now names `/milestone-feeder:remediate <n>` as the tool that applies its findings.
- **No schema changes** to `.milestone-config/driver.json` - feeder presence is the only switch.

### ⚖️ Post-run audit trail

Judgment-call PRs: #541.

- Note-cell precedence is unstated for a milestone/wave-granularity commit-only issue that also took the Auto loop: `skills/solve-issue/milestone-clauses.md` / `wave-clauses.md` and the new outcome vocabulary both claim the cell (follow-up; word-level fix in the two clause files).
- The Auto loop does not refresh `dependencyGraph.edges` after a remediation that adds an intra-set edge; the Phase 2 serial merge tail is the backstop in parallel mode.
- Ceiling state a contributor's next edit hits: `skills/solve-milestone/SKILL.md` has 43 words free; `skills/solve-milestone/not-buildable.md` has 2 words free.

## v1.22.1 - every governed file is writable again

**Theme:** Eleven governed markdown files were compressed and their ceilings ratcheted down in the same change, so no file in the repo sits at a size limit.

### 🔧 Maintenance

| Issue | PR | What |
|---|---|---|
| - eleven governed files sat at their size ceilings | #527 | Each was rewritten to state its requirements without restating the case for them - rationale, provenance and repeated cross-references cut, every gate, decision point, degradation branch, literal directive and citation kept. Headroom on the binding axis moved from 1–59 units to between 164 bytes and 1.3 KB. All three ceilings were lowered to the new actuals in the same change, per the ratchet discipline in `scripts/check-size-budgets.sh`. |
| - `skills/output-style.md` stated one prose rule three times | #527 | Its six GitHub-facing prose rules consolidate to three: the two that both said the citation carries the weight merge, and the three that all said a line filling no slot gets cut merge. The delete-on-sight vocabulary list is verbatim; the Guardrail and both anti-criteria are byte-identical, since three other files cite them by name. |
| #521 design-philosophy cites a solve-issue step that no longer exists | #527 | `.project/design-philosophy.md`'s Testing-philosophy section pointed at "steps 4-5"; step 5 merged into `### 4. Verification gates`. The pointer now reads `step 4`. |

### Consumer notes (upgrading from v1.22.0)

- **No behavior change.** Nothing a consumer types, configures, or expects has moved: no profile key added, removed or renamed, no command changed, no gate added or relaxed. Both a skill-quality review and a plugin-structure validation confirmed the diff carries no behavioral delta.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- **Six regressions were introduced by the compression pass and caught in review before merge**, three of them behavioral: `read-doc-section`'s invocation lost its `${CLAUDE_PLUGIN_ROOT}` prefix, leaving a bare basename that is not on `PATH` and diverging from its mirrored block in `skills/solve-issue/SKILL.md`; the `skills/output-style.md` degradation branch in triage narrowed from "missing, or unreadable" to "missing" inside a section headed "no error, ever"; and `skills/setup/SKILL.md`'s `preflightCmd` prompt lost its only Ruby/Rails example from a string shown verbatim to a consumer. All six were restored before commit.
- **One citation was dropped deliberately:** `docs/profile-schema.md (each built issue opens its own PR)` in `skills/triage/SKILL.md`, a source reference on a measured regex-failure example rather than a directive. `check-citations` reads 237 ok / 0 failed.
- **`## The two anti-criteria` was not consolidated.** It is enumerated by name in `skills/triage/SKILL.md`, `skills/solve-issue/SKILL.md` and `agents/implementer.md`, so folding it away is a four-file rename of a contract three files read, for roughly 100 bytes. Left deliberately undone.
- **`skills/output-style.md` is the weakest result** at 174 bytes free, up from 31. It is a rules file with almost no prose fat; further headroom there needs content relocation, not another scrub.
- Nine defects filed during milestone #40 remain open, none blocking: #509, #511, #512, #514, #515, #516, #517, #518, #520.

## v1.22.0 - finish the granularity matrix, resolve blockers instead of parking them

**Theme:** `integrationGranularity: "wave"` behaves as documented in both execution modes, and triage clears a Blocker it can resolve from the record instead of handing it back as work.

### ✨ Granularity matrix and blocker resolution

| Issue | PR | What |
|---|---|---|
| #502 Sequential runs with integrationGranularity "wave" have no defined behavior | #519 | Four shipped sites claimed `solve-issue` suppresses the per-issue PR under `"wave"`; no wave conditional existed in either execution mode. New `skills/solve-issue/wave-clauses.md` plus a `## Wave granularity` section supplies the per-step deltas, and the sequential loop is wired to them. |
| #503 solve-issue step numbering skips 5, and step 6 sub-steps are cited two ways | #522 | 15 sub-step references across 8 files re-keyed to the dotted key, and the skipped step 5 is explained inline at both places a reader meets it. |
| #506 Resolve a triage Blocker before parking it | #513 | A new bundled `blocker-resolver` agent runs at Step 3.5 and clears each Blocker resolvable from the record, posts a `🟢 Resolved` comment, and returns `clearLabel` so the caller removes the stale park label. The rest still park. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #384 Wave granularity closes no issues: gh issue close is given multiple #-prefixed args | #507 | `gh issue close` accepts exactly one issue argument and both call sites passed several, so a wave-granularity run closed nothing. Now one call per issue, with any failed close named in the final summary. |
| #391 md-epic fan-out cannot classify a milestone-granularity run | #510 | Outcome classification reads the single milestone PR when no per-issue PR exists, splitting the Note between a `visualHold` hold and red CI via `gh pr checks --json bucket`. A PR with no checks reads as vacuously green. |
| #396 solve-milestone step 6.7's CHANGELOG PR template is blocked by the code-review-gate hook | #508 | The CHANGELOG PR template and the wave PR body both carry a `## Code Review` section, so `hooks/code-review-gate.sh` no longer denies create and merge. A doc-only PR states `/code-review run: no` with its reason rather than claiming a run. |

### Consumer notes (upgrading from v1.21.0)

- **New default-filled Core profile key** `blockerResolverAgent`, defaulting to `milestone-driver:blocker-resolver`. Absent from `.milestone-config/driver.json` → the bundled default applies and nothing degrades.
- **`integrationGranularity: "wave"` now integrates at the Wave boundary in both execution modes.** A consumer already running `"wave"` with `parallel: false` was silently getting per-issue integration and now gets real wave integration.
- **Triage may clear a Blocker instead of parking it**, and removes the park label it cleared.

### ⚖️ Post-run audit trail

Judgment-call PRs: #507, #510, #513, #519.

- `skills/solve-milestone/SKILL.md` sits at 4,998 of 5,000 words and `skills/triage/SKILL.md` at 4,994. Both need a procedure split; another prose pass does not fit either one.
- Four more files are within bytes or lines of their ceilings: `skills/solve-issue/wave-clauses.md` 2,987/3,000 bytes, `skills/solve-milestone/sequential-loop.md` 7,495/7,500 bytes, `skills/solve-issue/md-epic-fanout.md` 8,985/9,000 bytes, `skills/solve-milestone/changelog-authoring.md` 209/210 lines.
- **`wave-clauses.md` states no home for a wave non-UI issue's Decision Log or `judgment call` label.** Its `6.7` and `Autonomy model` rows measured 179 and 314 bytes against 13 bytes free and were not written, so no shipped clause names where either lands. Filed as #520.
- Ten defects were filed during the run and remain open, none blocking: #509, #511, #512, #514, #515, #516, #517, #518, #520, #521.

## v1.21.0 - skill files meet the published authoring limits

**Theme:** The four SKILL.md files and the largest reference file come under Anthropic's published Agent Skills limits, and the CI size gate gains the axes that measure them.

### ✨ Authoring limits

| Issue | PR | What |
|---|---|---|
| #488 Normalize the seven existing contents blocks | #498 | Seven blocks conformed to `## Contents` as the file's first `##`-or-deeper heading - two heading renames, five bold-prose-row promotions, index bodies verbatim. |
| #489 Add a word column to the size-budget gate | #498 | `GOVERNED_TABLE` gains a fourth word-ceiling column across both `check-size-budgets` twins, both runners, every golden, and a new `byte-flat-word-over` fixture tree. |
| #490 Add the check-doc-toc twin, its runner, and both CI legs | #498 | New `scripts/check-doc-toc.{sh,ps1}` asserts `## Contents` is the first `##`-or-deeper heading in any governed file over 100 lines, with a golden-matrix runner and a fixture step on both CI legs. |
| #491 Print each skill's unconditional load closure | #500 | A `CLOSURE` row per governed skill sums its SKILL.md plus every file it read-directs on **every** run, by word. Informational - it never gates. |
| #492 Reduce `skills/solve-milestone/SKILL.md` | #500 | 608 → 305 lines, 9,619 → 4,996 words. Both limits met. |
| #493 Reduce `skills/solve-issue/SKILL.md` | #500 | 9,969 → 5,750 words. Still over 5,000. |
| #494 Reduce `skills/solve-milestone/parallel-waves.md` | #500 | 10,080 → 5,647 words. Still over 5,000. |
| #495 Trim `skills/triage/SKILL.md` and lower its ceilings | #500 | 5,296 → 4,938 words. Byte ceiling 37000 → 35500. |
| #496 Add `## Contents` to the four blockless governed files | #500 | Blocks added to `skills/citation-format.md`, `agents/design-reviewer.md`, `agents/implementer.md`, `agents/triage-reviewer.md`, each paid for by an equal-or-larger prose trim. Both CI legs gain a real-tree `check-doc-toc` step; previously only fixtures were checked. |
| #497 Add a direct citation-format read-directive to each SKILL.md | #501 | All four SKILL.md files read-direct `${CLAUDE_PLUGIN_ROOT}/skills/citation-format.md` from their own `## Output style` section - one hop from every skill entry point, not only through `skills/output-style.md`. |

### Consumer notes (upgrading from v1.20.3)

- **No schema changes** to `.milestone-config/driver.json`. No profile key added, removed or re-defaulted.
- **No behavior or procedure change.** Every gate, decision point, degradation branch, citation and literal directive survives verbatim. Reduction came from cutting unconditional prose or gating conditional bodies behind an observable branch whose condition stays inline in the SKILL.md.
- 18 new shipped reference files under `skills/solve-issue/` and `skills/solve-milestone/` carry the gated bodies.
- `check-doc-toc` and the widened `check-size-budgets` govern this repo's own files - `GOVERNED_TABLE` names milestone-driver paths and both gates run in this repo's CI. A consumer repo runs neither.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- `skills/solve-milestone/SKILL.md` is at 4,996 of its 5,000-word ceiling. The next prose addition fails the ratchet.
- `skills/solve-issue/SKILL.md` (5,750) and `skills/solve-milestone/parallel-waves.md` (5,647) stay over the 5,000-word standard. What remains is unconditional pipeline; reaching the limit would mean gating text behind branches that do not exist.
- `GOVERNED_TABLE` covers 33 files, up from 15. No ceiling was raised.
- `skills/solve-issue/version-bump.md` joined `solve-issue`'s closure: step 4 read-directs it in all three `versioning` modes with no branch in front.
- **No test asserts `check-doc-toc`'s `GOVERNED_PATHS` stays in sync with `GOVERNED_TABLE`'s path column.** A rename or deletion fails loud; adding a governed file to one table and not the other passes silently.
- Two pre-existing defects were found and filed, not fixed: sequential runs with `integrationGranularity: "wave"` have no defined behavior (#502), and `skills/solve-issue/SKILL.md`'s step numbering skips 5 with step 6's sub-steps cited both as `6.1–6.4` and as `7/8/9` (#503).

## v1.20.3 - the CHANGELOG's own prose contract

**Theme:** Release notes state what shipped and what a consumer must do; the slots that generate them are defined so the next entry cannot narrate how the work went.

### ✨ Prose contract

| Issue | PR | What |
|---|---|---|
| - apply the artifact prose contract to `CHANGELOG.md` | #483 | 789 → 717 lines with every issue and PR reference, release heading, release date and consumer-actionable note intact. Theme paragraphs become one line, a `What` cell states shipped behavior rather than build provenance, and each ⚖️ audit trail becomes the judgment-call line plus a fact list. |
| - define the CHANGELOG-entry slots in the generator | #483 | `skills/output-style.md`'s `## Evidence slots` row names four slots - theme, the per-bucket lines and their evidence, Consumer notes, the ⚖️ audit trail and its fact list - plus what is not one. `skills/solve-milestone/SKILL.md` step 6.5 reshapes its template to match and points at that row instead of restating it. |

### Consumer notes (upgrading from v1.20.2)

- **No schema changes** to `.milestone-config/driver.json`. No profile key added, removed or re-defaulted.
- **Behavior change, nothing to configure.** A completed `solve-milestone` run authors its CHANGELOG entry to the defined slots - shorter entries, the same facts. No skill gains or loses a step, and no gate changes.
- Both changed files are shipped plugin skills, so the contract governs your repo's CHANGELOG from the next completed milestone.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- `skills/output-style.md` is at 9412 of its 9500-byte ceiling and `skills/solve-issue/SKILL.md` at 69478 of 69500. The next edit to either fails the size ratchet until something is cut or the file is split.

## v1.20.2 - stop re-reviewing what cannot have broken

**Theme:** Two review-cycle costs removed - a comment-only fix no longer re-runs the suite or the review, and `risk:light` no longer pays for review rounds after a clean one.

### ✨ Review-cycle cost

| Issue | PR | What |
|---|---|---|
| #476 Comment-only deltas under sourceGlobs re-trigger the full review cycle | #478 | Step 6.1's post-fix split decides on delta content, not file path. New `scripts/classify-delta.{sh,ps1}` with a 66-row golden matrix per leg. |
| #477 risk:light relaxes review effort but not review cycle count | #479 | Light converges after one review cycle; a second runs only when the most recent review returned a Critical or Important finding. Heavy stays at two. |

### Consumer notes (upgrading from v1.20.1)

- **No schema changes** to `.milestone-config/driver.json`.
- New shipped scripts: `scripts/classify-delta.{sh,ps1}` plus `tests/classify-delta.{cases.tsv,test.sh,test.ps1}`. Both legs run in CI on every PR.
- The comment-only branch resolves every uncertainty to `code-changed`: unmapped extension, empty delta, untracked file, rename, mode change, deletion, a machine-read directive (`#!`, `// eslint-disable`, `//go:build`), a block comment followed by code on one line, and a heredoc payload line.
- The comment-only branch stages and commits in separate calls - `tests-green` is a `PreToolUse` hook that reads the index before the command runs. It is not a guaranteed second suite run: it no-ops when `unitTestCmd` is absent, when the staged tree matches the last green stamp, when `jq` is absent, or when `CLAUDE_HOOK_DISABLE_TESTS_GREEN=1` is set.
- Light reads the reviewer template's Critical / Important / Minor. A finding carrying no severity counts as Important, so Light degrades to Heavy rather than skipping a defect.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- `skills/solve-issue/SKILL.md` is at 69478 of its 69500-byte ceiling. The next edit to it fails the size ratchet until something is cut or the file is split.

## v1.20.1 - the cache that shipped switched off

**Theme:** v1.20.0's triage cache wrote entries with no usable key, so every lookup missed and the cache was inert in the release that introduced it; fixed here with three consistency defects a post-release coherence review found.

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #462 Triage Step 6.5 requires a cache key that Step 2.5 forbids deriving and triage-cache never prints | #473 | `write` takes the Step 2.5 GraphQL response as a fourth argument and stamps each entry's `key` from the same definition `lookup` compares against. The orchestrator never handles a key. |
| #466 Consumer docs say four gates where there are six, and three links point at a heading that moved | #469 | Four docs and one hook comment name all six shipped gates in one order; three dead links to `README.md#the-layered-gating-model` repointed to `docs/architecture.md`. |
| #464 The reviewer agent pair diverged | #470 | Restored `triage-reviewer.md`'s "you surface it, you don't design the fix" rule, plus five smaller divergences from `design-reviewer.md`. |
| #463 `docs/architecture.md:148` still calls implementation the sole concurrent stage, contradicting `:117` and `:145` after #400 | #467 | `:148` corrected to match `:117` and `:145` after #400 pipelined build and review. |

### Consumer notes (upgrading from v1.20.0)

- **Upgrade if you use `/milestone-driver:triage`.** On v1.20.0 the cache never matched, so every run re-dispatched a reviewer for every issue. Results were correct; you paid full triage cost each time. Existing `.milestone-config/triage-cache.json` files stay valid - the key format is unchanged, only which component computes it.
- `scripts/triage-cache.{sh,ps1}`'s `write` subcommand now takes **four** arguments (`write <repo-root> <entries.json> <graphql-response.json>`). Direct callers must add the response file. An absent or unreadable response is fail-open: entries are written without a key, exit 0, and those issues re-triage next run.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- Two ceilings in `scripts/check-size-budgets.{sh,ps1}` were raised by recorded decision: `agents/triage-reviewer.md` to 17000 bytes, `agents/design-reviewer.md` to 120 lines. That authorization is spent - the next edit to either re-derives downward as usual.
- **No gate catches a fix that reads correctly and no longer does the same thing.** Nine instances across this milestone, each caught by a reviewer opening the target and reading it, none by a gate - the result is valid, passes every check, and reads like it means what it used to. #466 corrected a gate count in a sentence and left the table 45 lines below still enumerating four; #464's ceiling raise would have collapsed the two rows `positional-desync` swaps to identical values, leaving the assertion passing while proving nothing.
- **v1.20.0 was tagged before #462 merged.** The fix was built, reviewed and green on an open PR at release time.
- **#465 was closed unbuilt** (eight tables of contents in four shapes). The inconsistency costs human navigation only: the model loads the whole file and cross-file references resolve against headings, not TOC labels. Its body also miscounted its own sites and cited `docs/plugin-features-reference.md`, which has never existed in the tree or in git history.
- Open, found here and not fixed: **#468** - `tests/build-file-index.test.sh`, `tests/extract-version.test.sh` and `tests/parse-md-epic-order.test.sh` use bash 4.3 namerefs (`local -n`) and report `0 passed` under the `/bin/bash 3.2.57` macOS ships; invisible in CI, which runs the bash suite on Ubuntu. **#471** - the bash and PowerShell legs sort labels differently outside the BMP, so an issue carrying both an emoji label and a `U+E000-FFFF` label gets a different cache key per platform.

## v1.20.0 - anchor every citation, then cut 20%

**Theme:** Every live line citation became a content anchor or heading reference, repo-root-relative became the only conforming path base, and `scripts/check-citations.{sh,ps1}` resolves them in CI so a reworded line fails the build. The second half trimmed the governed skill and agent files by 7.3% of bytes against a 20% target.

### ✨ Anchors, and the gate that keeps them true

| Issue | PR | What |
|---|---|---|
| #431 convert every live line citation to an anchor | #447 | 152 line citations converted, each verified by a resolver run (exit 0, exactly one `PRIMARY`, zero `MATCH`). Three line-style citations survive deliberately and are named in the PR: two illustrate the line form, one points into the sibling `milestone-feeder` repo. |
| #430 retarget 20 broken line citations and drop 2 to a file that never existed | #444 | Every line number re-derived against the real target. Three sites asserted a process-ID threshold of `<= 0` where `scripts/render-daemon.ps1` ships `<= 1`; the claim was corrected before #431 froze it into an anchor. Both citations to `docs/efficiency-grounding-plan.md` were dropped - no doc in this repo makes that claim. |
| #429 declare repo-root-relative the only conforming citation base | #445 | `skills/citation-format.md` named four citation forms but not what directory a `path` resolves from, and no resolver does repo-root discovery. Live citations used both bases: 132 repo-root, 47 citing-file-relative, 8 neither. Repo-root-relative is now the single conforming base, with no fallback. |
| #425 same-file citations must use a heading, not an anchor | #442 | An anchor citation written into its own target file reproduces the anchor on the citing line, which `resolve-citation.sh` labels `PRIMARY` at exit 0. Inside its own target file, write a heading citation - a citing line is not a heading. Live same-file count measured at 0. |
| #432 gate `path (anchor)` citations repo-wide | #456 | `scripts/check-citations.{sh,ps1}` walks the tree, resolves every `path (anchor)` citation byte-identically on both legs, and runs in CI as a runner plus a pass over this repo's real tree. Clean at merge: `SUMMARY ok=189 failed=0`. Catches both a broken anchor and an anchor that resolves twice, which exit status alone cannot see. |
| #427 govern `skills/citation-format.md` in the size ratchet | #448 | The shared citation reference loads into context like every other governed file and eight files point at it, but it was absent from the size check. Now governed at 230 lines / 13000 bytes, re-derived from a fresh measure. |
| #428 make the governed set one row per file so ceilings cannot drift | #446 | The parity guard compared only the lengths of three parallel arrays, so a positional desync measured files against other files' ceilings and exited 0. The governed set is now one row per file, `<path> <lineCeiling> <byteCeiling>`. Written RED first; twin equivalence reconstructed across 14 malformed row shapes. |

### ✂️ The 20% cut

| Issue | PR | What |
|---|---|---|
| #433 trim `skills/solve-milestone/SKILL.md` | #449 | 664 / 76470 → 602 / 65569, a 14.3% byte reduction across 129 edits. Two cuts that read as prose but were content were restored: step 6.5's literal `git show <commit>:CHANGELOG.md`, and versioned mode's leading-whitespace qualifier for a CHANGELOG heading match. |
| #434 trim `skills/solve-issue/SKILL.md` | #450 | 394 / 76940 → 357 / 66075, a 14.1% reduction across 64 hunks. A stale claim that the plugin ships no code-review hook was corrected - `hooks/code-review-gate.sh` exists. A park trigger that had survived only in a label-conditioned form was restored unconditional. |
| #441 extract the triage cache mechanics to `scripts/triage-cache.{sh,ps1}` | #451 | Steps 2.5 and 6.5 re-taught the cache mechanics in prose on every invocation; a script executes and costs zero context. `skills/triage/SKILL.md` goes 450 / 42130 → 368 / 36670. Building it RED found a real bug: PowerShell's `ConvertFrom-Json` coerces an ISO-8601 string to `[datetime]`, so the composed key came out in culture format - a permanent 100% cache miss at exit 0. |
| #435 trim `skills/triage/SKILL.md` | #452 | 368 / 36670 → 368 / 34789, a 5.1% reduction. #441 had already harvested this file. Review found 579 further cuttable bytes; they were left, because the residual is exact commands, two agent return contracts, a JSON shape and two measured findings. |
| #436 trim `skills/solve-milestone/parallel-waves.md` | #453 | Read in full on every run that does not hit a barrier. 205 / 64827 → 186 / 58981, a 9.0% reduction - the only issue in the cut whose byte and line targets both cleared. All 17 removed spans were traced to a surviving statement or classified as rationale. |
| #437 trim the user-facing trio | #454 | `skills/setup/SKILL.md`, `skills/notices.md`, `skills/output-style.md`: 620 / 54565 → 601 / 47894, a 12.2% reduction. The largest cut in `notices.md` had replaced each notice's literal marker-writing command with a generic template that does not compose (all eight marker values already carry the `.milestone-config/` prefix) - the composed `touch` would have failed and every one-time notice would have re-printed forever. Fixed; all eight verified by running the composed command. |
| #438 trim the four conditionally-loaded reference files | #457 | `trello-sync.md`, `milestone-granularity.md`, `async-mode.md`, `md-epic-fanout.md`: 625 / 59707 → 621 / 55475, a 7.1% reduction. This cleared the milestone's last ratchet failure - `milestone-granularity.md` had been 342 bytes over ceiling since #431, since anchors are longer than the line numbers they replaced. One requested cut was refused: the caller does not state what the cut text states, and what it does state contradicts it. |
| #439 trim the three agent briefs, and fix `implementer.md`'s return-shape examples | #455 | `design-reviewer.md` 15721 → 13929 (11.4%), `triage-reviewer.md` 16356 → 14216 (13.1%), `implementer.md` 14614 → 14147 (3.2%). Two examples in `agents/implementer.md` taught return tokens the consumer cannot parse - `PAUSE` where `skills/solve-issue/SKILL.md` matches `PAUSED-FOR-APPROVAL`, `STOP` where it matches `STATUS: STOPPED`. All eleven Blocker-producing rules re-probed by literal substring and confirmed intact. |

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
- **The gate verifies exactly one citation form.** `scripts/check-citations.{sh,ps1}` resolves `path (anchor)`. The other three forms are counted and reported `UNVERIFIED`, not checked, so `failed=0` says nothing about them. On this repo the gate reports `ok=194 failed=0` with `unverified=81` - 57 `path#Heading`, 21 `path § Heading`, 3 `path:line`.
- **The gate skips six trees**, each emitted as an `EXCLUDED` record with its skip count, including `.milestone-config/worktrees/` and `.milestone-feeder/`.
- **`.gitattributes` now pins `*.md` to `eol=lf`.** A checkout with `core.autocrlf=true` previously added a byte per line and failed the size gate on files a contributor had never touched.
- **A parallel `solve-milestone` run reviews as it goes (#400).** `parallel` and `maxParallelWorkers` keep their names, shapes and defaults. What changes is what the cap counts: one number covering build leaves and review leaves together, rather than a separate allowance per stage.
- **Triage parks fewer issues (#440).** A reviewer can still raise a Blocker on anything recorded in the issue. It can no longer raise one for being unsure without exhausting a named source set first, and a found, cited convention whose soundness it cannot certify is now Advisory. Nothing to configure. Expect the largest change in repos with thin `.project/` docs.
- **Contributors to this repo: the ceiling rule is `actual × 1.05`, not `target × 1.05`**, and the line axis has a minimum-headroom floor mirroring the byte axis's 500-byte rounding. Consumers are unaffected; the ratchet governs this repo's own skill and agent files.

### ⚖️ Post-run audit trail

Judgment-call PRs: none. All 18 issues in milestone #37 merged and closed, zero parked.

- **The 20% target was not met on any file.** Across the whole governed set (15 files) from base commit `c379bb3` to the end-of-milestone pass: 427611 → 396568 bytes, 3479 → 3313 lines - 7.3% of bytes, 4.8% of lines. Best single file is `skills/triage/SKILL.md` at 17.0% net, which is an extraction plus a trim. Per-issue byte yields ran 3.0% (`trello-sync.md`) to 15.2% (`notices.md`). Four files grew: `parallel-waves.md` +4.6% (#400's scheduler), both reviewer briefs (#440's source sets), and `skills/citation-format.md` 9536 → 12060 bytes (#427 brought a previously ungoverned file under the ratchet, and anchors cost bytes against the line numbers they replace).
- **#432 shipped with two acceptance criteria formally dropped**, recorded in the PR and in both script headers. (1) `path#Heading` and `path § Heading` resolution - a heading matcher produced 23 FAIL records against 23 correct citations. (2) A syntactic same-file rule - every skill file here is named `SKILL.md`, so a basename comparison flagged 3 cross-file citations as same-file; same-file citations are caught by match count instead.
- **#400's slot-allocation order contradicted a recorded decision.** `docs/briefs/2026-07-31-post-alienation-followups.md § Decision 1: the concurrency cap. SETTLED.` records build-first as settled on 2026-07-30; #400's acceptance criterion 2 says the opposite. Review-first was re-ratified 2026-08-06 and the brief is marked superseded in place, scoped to its two slot-preference statements.
- **Ceilings were re-derived once at the end of the milestone**, not per issue: 5 line ceilings and 10 byte ceilings lowered, 8 rows derived above their current value and held. Issue bodies assuming `target × 1.05` recorded numbers that would have failed three files.
- Fixed in the end pass: the citation gate walked `.milestone-config/worktrees/` (58 FAIL records from deliberately-broken fixture anchors, red only for the person running the driver), and governed `*.md` was not yet pinned to `eol=lf`.
- Open follow-ups: **#468** - three test runners use bash 4.3 namerefs and cannot run under real `/bin/bash 3.2.57` (`tests/build-file-index.test.sh`, `tests/extract-version.test.sh`, `tests/parse-md-epic-order.test.sh`, each `local -n _arr="$2"`). **`skills/solve-milestone/milestone-granularity.md`** documents a pre-clean-guard placement in Before-starting that `skills/solve-milestone/SKILL.md` contradicts by cutting the milestone branch inside the issue loop. **`agents/design-reviewer.md`** criterion 3 reads as "found pattern → never Blocker", conflicting with its own rendered-outcome row. **15 `path § Heading` citations use a bare filename** instead of the repo-root-relative path `skills/citation-format.md` requires - six in `skills/solve-milestone/SKILL.md`, nine in `parallel-waves.md`; the gate does not cover that form.

## v1.19.0 - citation anchors

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
- **New artifacts:** `scripts/resolve-citation.{sh,ps1}` (a runtime primitive, not a CI gate - it returns records at exit 0 and never fails a build), `tests/resolve-citation.test.{sh,ps1}` with its cases table and fixtures, and `skills/citation-format.md`.
- **CI grows one step per leg.**
- **Anchors are literal strings, never parsed symbols.** Resolution is a case-sensitive, line-scoped substring search - not a regex, not language-aware. Write the shortest string that uniquely names the region.
- **Extraction is model judgment, not pattern matching.** A parenthetical following a path is not automatically a citation.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- `tests/resolve-citation.test.ps1` asserts with `[string]::Equals(…, Ordinal)`, diverging from the bare `-eq` in its eight sibling pwsh runners, because `-eq` is case-insensitive and culture-sensitive and the issue required exact assertion. Migrating the house idiom is a separate sweep.

## v1.18.0 - milestone-scoped branching and dispatch topology

**Theme:** Two bodies of work. A whole milestone can build on one local branch and reach the integration branch through a single push, PR and CI run. And the worker layer is deleted: the orchestrator is the only session that fans out, every dispatched agent is a leaf at depth 1 where its completion notification arrives, and an issue outside the barrier partition is named and recovered rather than vanishing.

### ✨ Milestone-scoped branching

| Issue | PR | What |
|---|---|---|
| #368 add `milestone-granularity.md` with the branch model and local integration mechanics | #386 | New `skills/solve-milestone/milestone-granularity.md` holds the branch model, the local `git merge --squash` fold both the sequential loop and the parallel merge tail run, and the integration commit whose `Issue: #<n>` trailer carries that issue's Decision Log and Code Review block. Issue branches keep their `issue/<n>-<slug>` name, are cut from the milestone branch, and are never pushed. Read only under `"milestone"` granularity; missing there it halts rather than degrading to `"issue"`. |
| #371 add the milestone-end sequence and the red-CI handler | #388 | Replaces `solve-milestone` steps 6.6–6.8: commit the CHANGELOG onto the milestone branch, push once, open one PR into `integrationBranch`, merge on green, then close each issue with its own `gh issue close` - `Closes #n` fires only on a merge into the default branch. Red CI is run-scoped: label the PR `needs review`, name every issue on the branch in one 🔴 line, preserve the branch, close nothing. |
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
| #362 name the `abandoned` bucket, recover once, then park | #405 | The barrier partition ran on `built-green` and `parked`, which are not exhaustive: an issue in neither vanished with no label, comment or notification - the exact shape of an auto-denied background leaf, context exhaustion, or a killed run. `abandoned` is a named third bucket with its own probe legs (no PR, no pushed branch ahead of base, no park label), resolved by a recover-once ladder at cap 1 inside the same pass. |
| #363 `ort` auto-resolves non-adjacent same-file edits, not non-overlapping ones | #403 | Two edits on directly adjacent lines conflict; one unchanged line between them merges clean. So any file with a single shared append point (a changelog table, a barrel export, a DI registration list) conflicts by construction under concurrency. Swapped at five sites, and the two park-call sites now carry that this shape sits within bounded auto-resolve rather than triggering a park. |
| #365 tell every dispatched agent to namespace its own scratch | #404 | Concurrent agents shared one scratchpad directory and overwrote each other's probe files, producing a false cross-worktree-write alarm. One rule in two byte-identical families - seven dispatch sites state what the brief must carry, three agent contracts state what the agent honors: write scratch only under a path named for that issue or agent, and report what a probe printed rather than writing a file to read back. |
| #364 caveat the version-free CHANGELOG idempotency check against heading suffixes | #398 | Version-free mode compares the whole line, so a heading carrying `(partial)`, `(in progress)` or a date is not equal to `## <milestone title>`: the check reports no existing entry and prepends a duplicate section. Versioned mode is immune (its prefix ends in a trailing space). The caveat is appended byte-identically at both sites; strict equality stands, since widening the match would let `## Q3 Hardening` satisfy a milestone titled `Q3`. |
| #397 re-derive 18 stale cross-file citations | #409 | 18 citations re-derived: 6 into heading anchors that survive a line shift, 12 into corrected line numbers. Only 8 of the 12 had no heading to anchor to, their targets inside a 116-line heading-free stretch. The issue title's "5 of 8" does not reconcile with the PR's evidence table. |
| #399 the size-budget ratchet governs bytes as well as lines | #410 | Counting lines only meant prose appended to an existing line grew context cost at zero reported movement: PR #398 added 1,052 bytes at a flat 664 lines, and three later merges added 3,818 more the same way. Both twins hold a per-file byte ceiling beside the line ceiling, rounded up to the next 500 bytes. Lines stay as an independent second ceiling, because `file:line` citations pay a cost for line growth no byte count expresses. |

### Consumer notes (upgrading from v1.17.0)

- **Nothing to do on upgrade.** The default is still `"issue"`, and the `"issue"` and `"wave"` paths are byte-unchanged.
- **Schema change, both parts optional.** `integrationGranularity` now accepts `"milestone"` alongside `"issue"` and `"wave"`; `visualHold` is new. Both default to today's behavior when absent.
- **Opting in has one prereq.** Set `{ "integrationGranularity": "milestone" }`, then filter your own push-triggered workflows to ignore the `milestone-*` prefix: `branches-ignore: ['milestone-*']`, or `branches: ['**', '!milestone-*']` with the negation last. One form per event, never both. Skip the filter and the milestone-end push starts your push workflow while the PR run rebuilds the same commit.
- **The `milestone-` branch prefix is a stable, externally-consumed contract** - consumer CI filters are written against it.
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
- **`hooks/code-review-gate.sh` caught the orchestrator skipping review** on #399 - it denies a `gh pr create` whose body carries no `## Code Review` section. Worth recording because a backstop that has never fired cannot be told apart from one that does not work.
- Open follow-ups: **#402, #406, #407** - four more stale cross-file citations plus #407's durable fix (check heading anchors, not line numbers). **#408** - `skills/solve-milestone/SKILL.md` contradicts itself on whether the purely-numeric-title halt fires under `--driven`. **A twin divergence, deferred** - a governed file that is present but unreadable records `OK` and exits 0 on the bash side of `check-size-budgets` while the PowerShell twin throws; which way both should go was out of scope for #399.

## v1.17.0 - reviewer grounding & output style

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
- **`domainSkills` is optional and degrades cleanly** - absent, the step is skipped; it never makes the docs check optional. All three injected inputs are additive grounding whose absence is never a STOP condition.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

Open at this release:

- **Workers strand on nested sub-agent dispatch.** Four of eight workers ended their turn waiting on a child that never re-invoked them; completed work sat uncommitted until the orchestrator probed the worktree. Root cause is upstream: [anthropics/claude-code#75043](https://github.com/anthropics/claude-code/issues/75043). The workarounds that held were reviewing in-turn with no dispatch, or polling the artifact's file content rather than the child's transcript. (Fixed in v1.18.0 by #361.)
- **A ceiling-table edit can break the golden-matrix fixtures with no review lens catching it.** #341 added `skills/output-style.md` to `scripts/check-size-budgets.*` and broke `tests/check-size-budgets.test.sh` (0/3). Five `/code-review` lenses cleared it; the coherence pass caught it.
- **The repo's own `domainSkills` went unconsulted while authoring changes to its skills.** Three findings from that guidance remain unfiled: `skills/solve-milestone/SKILL.md` is 658 lines against a documented 500-line limit, all four frontmatter descriptions summarize workflow (which `writing-skills` shows causes agents to skip the skill body), and no skill edit in this milestone was preceded by the baseline pressure test its Iron Law requires.
- **`${CLAUDE_PLUGIN_ROOT}` prefixing has no machine enforcement.** #348 placed 28 substrings by hand; nothing stops the next skill edit from reintroducing a bare path.

## v1.16.1 - convention-search before parking as `needs design`

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

## v1.16.0 - run-efficiency grounding

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

## v1.15.2 - solve-milestone registration fix + config cleanup

_Released 2026-07-07._

**Theme:** `/milestone-driver:solve-milestone` did not register under a strict YAML parser; the frontmatter is fixed and a lint keeps an invalid one from silently dropping a skill again.

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #314 `solve-milestone`'s frontmatter `description:` is invalid YAML | #316 | The unquoted scalar contained `parallel: false`, and the `: ` sequence makes strict parsers (js-yaml) reject the whole frontmatter block, so the skill never registered in Claude Desktop while the lenient CLI loader masked it. `description:` is now a folded block scalar, round-tripping byte-exact with the `parallel: false` mention intact. Ships `scripts/check-skill-frontmatter.{sh,ps1}` - a dependency-free, line-oriented lint, no YAML library - wired into CI on every PR. |
| #248 remove the now-dead `allowCrossMarketplaceDependenciesOn` from `marketplace.json` | #315 | The key lived only in `.claude-plugin/marketplace.json`, added when the repo became an installable single-plugin marketplace. The cross-marketplace dependency it permitted was already removed from `plugin.json` in v1.13.1. |

### Consumer notes (upgrading from v1.15.1)

- **No schema changes** to `.milestone-config/driver.json`.
- `/milestone-driver:solve-milestone` registers in Claude Desktop once the plugin updates. The Claude Code CLI was unaffected either way.
- **New CI step per leg:** the frontmatter lint. It governs this repo's own skills; consumers of the plugin are unaffected.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

- #249 (native/non-web visual-capture seam) was parked at triage on three design blockers and is not in this release.

## v1.15.1 - audit remediation: progressive disclosure, wave checkpoint, mechanical gates

Patch release - the audit-remediation milestone, 15 issues, all merged CI-green.

- **Progressive disclosure**: solve-issue's worker-mode (#282), async-mode (#283), md-epic fan-out (#284) and solve-milestone's parallel-waves (#285) extracted into sibling reference docs loaded only when triggered; agent briefs trimmed (#286, #287, #288).
- **Reliability**: unified act→verify→retry gate loop (#290); `wave-state.json` checkpoint with trust-but-verify freshness for resumed runs (#291); triage stale-edge dedup - M fetches, not N×M (#293).
- **Mechanical enforcement**: `code-review-gate` hook - PRs must carry their `## Code Review` section (bash+pwsh twins, 22-case golden matrix) plus a macos-latest CI job running all six hooks under real /bin/bash 3.2 (#289); per-file ratcheted size budgets in CI, one-way tightening (#295).
- **Truth-ups**: one-time notices consolidated into `skills/notices.md` (#292); honesty pass on stale claims (#294); SendMessage/mid-run-redirect claims corrected and the background-wait pattern documented (#281).

## v1.15.0 - Parent-issue fan-out (md-epic)

**Theme:** A GitHub issue labeled `md-epic` can anchor a feature too big for one milestone: list the milestones in its body in build order, and `solve-issue` on that parent drives them one at a time. Entirely opt-in, gated on the label, off by default.

### ✨ A parent issue can anchor and drive a group of milestones

| Issue | PR | What |
|---|---|---|
| #266 Add the md-epic-order block parser | #271 | New `scripts/parse-md-epic-order.{sh,ps1}`: locates the fenced `md-epic-order` block, validates each `number:`/`title:` line, and reports the first malformed line by position. No `gh` calls, no network. |
| #267 Recognize `--driven` and suppress the DB-hazard interview | #272 | `solve-milestone` recognizes an internal `--driven` token, read the same way as `--worker` and `--async`. When present the DB-hazard interview degrades straight to its non-interactive sequential path - a driven run has no human to answer it. |
| #268 Detect md-epic parent issues and fan out over their milestones | #273 | `solve-issue` checks an issue's labels for `md-epic` before anything else. A parent parses the ordered milestone list from its body, resolves each entry to a real milestone, and drives them one at a time via `solve-milestone --driven`, resuming completed milestones and parking the parent itself when the list is missing or malformed. |
| #269 Add the human cherry-pick prompt for a directly-targeted milestone | #274 | `solve-milestone` on a milestone belonging to an `md-epic` parent asks first: build just this milestone, hand off to `solve-issue` on the parent, or pause. A driven run skips the prompt. |
| #270 Document md-epic in README, architecture, and this changelog | #275 | A `## Parent issues (md-epic)` README section and the mechanism writeup in `docs/architecture.md`. |

### Consumer notes (upgrading from v1.14.0)

- **Entirely opt-in.** No `md-epic` label anywhere in your repo means `solve-issue` and `solve-milestone` behave exactly as in v1.14.0.
- **New internal token `--driven`.** Like `--worker` and `--async`, recognized by string presence and never typed by a human; the parent-issue fan-out loop supplies it.
- **No schema changes** to `.milestone-config/driver.json`.
- **The other half ships later.** Creating a parent issue - applying the label, writing the ordered milestone list, linking each milestone's issues as sub-issues - is the feeder's and bootstrapper's job, specced separately and not yet built. Until then, hand-author a parent issue to the contract in `docs/architecture.md`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.14.0 - Parallel by default

**Theme:** `solve-milestone` builds a milestone's mutually-independent issues in parallel by default; a run-start barrier check drops to sequential only when something makes parallel unsafe. `maxParallelWorkers` tunes the width, and a one-time notice tells existing users the default changed.

### ✨ Parallel is the default, with a safety check instead of a flag

| Issue | PR | What |
|---|---|---|
| #250 Flip solve-milestone to parallel-by-default | #256 | The `--parallel` flag and the "in parallel" phrase are gone. Every run resolves the mode once through a barrier cascade: parallel unless `parallel: false`, a session permission the background workers need is not allow-listed, or the repo runs unit tests and the one-time test-database question is unanswered. A habit-typed `--parallel` is ignored. Wires the worker cap to `maxParallelWorkers` and adds the one-time notice. |
| #251 Add setup's conditional parallel question | #257 | First-run setup asks - only if the project runs unit tests - whether the test harness is isolated per worker, and records the answer as `parallel`. Projects with no unit tests are never asked and stay parallel. |
| #252 Document the parallel and maxParallelWorkers keys | #258 | Documents both keys, including the deliberately-opposite write rules: `parallel` always records an explicit yes/no, `maxParallelWorkers` follows the usual omit-for-default. |
| #253 Rewrite consumer-setup's parallel section | #259 | Rewrites the guide to the default-with-opt-out model, keeping the existing DB-isolation guidance. |
| #254 Reframe architecture.md's parallel-mode model | #260 | Reframes the section from opt-in to parallel-by-default with the barrier cascade. Worktree-fleet and serial-merge-tail mechanics are unchanged. |
| #255 Retire leftover --parallel wording | #261 | Retires the remaining `--parallel` framing across the other skills, scripts and docs. Wording only. |

### Consumer notes (upgrading from v1.13.0)

- **Parallel builds are the default.** To keep building one issue at a time, set `"parallel": false`. A passed `--parallel` is stripped and ignored.
- **New key `parallel` (boolean, optional).** Absent means "not yet decided": the run goes parallel unless the repo defines `unitTestCmd`, in which case the first run asks once whether the test harness is isolated per worker (a git worktree isolates files, not the DB) and records the answer here. `true` forces parallel; `false` forces sequential. A missing session permission still overrides `true` down to sequential.
- **New key `maxParallelWorkers` (integer, optional, default 4).** How many mutually-independent issues build at once within a Wave. An absent or invalid value falls back to 4.
- **Headless / CI runs** (`MILESTONE_DRIVER_NONINTERACTIVE=1`) never see the test-database prompt - they run sequentially with a loud note until the profile sets `"parallel": true`.
- **Schema change:** two new optional keys. An existing profile keeps working unchanged, and the first run seeds `parallel` when a test-DB hazard is present.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.13.1 - Claude Desktop slash-command fix

_Released 2026-06-26._

**Theme:** The cross-marketplace `superpowers` dependency stopped Claude Desktop registering the driver's skills as slash commands; `superpowers` is now a prerequisite you install yourself.

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| - drop the cross-marketplace `superpowers` dependency | #246 | The `dependencies` array is removed from `.claude-plugin/plugin.json`. Declaring `superpowers@claude-plugins-official` made Claude Desktop load the plugin but skip registering its skills as slash commands; the CLI was unaffected. Cross-plugin dependencies are an open upstream feature request ([anthropics/claude-code#9444](https://github.com/anthropics/claude-code/issues/9444)), so the declaration was dropped rather than worked around. `superpowers` is still required at runtime, documented as a prerequisite in the README and `.project/library-manifest.md`. |
| - note the bootstrapper-owned `driver.json` keys | #245 | `docs/profile-schema.md` records that `stack` and `stackVersionFile` are owned by milestone-bootstrapper. |

### Consumer notes (upgrading from v1.13.0)

- 🔴 **Install `superpowers` yourself.** It is no longer auto-installed with milestone-driver: add the `claude-plugins-official` marketplace and install `superpowers` alongside the plugin. It remains a runtime requirement.
- **Claude Desktop registers `setup`, `solve-issue` and `triage`** after upgrading and reloading. It does **not** register `solve-milestone`, which an unrelated invalid-YAML frontmatter defect kept out of the registry until v1.15.2 (#314). The CLI registered all four throughout.
- **No skill, hook, script or profile-schema contract changed** beyond the manifest field removal and the docs note.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.13.0 - An optional coherence check before the final review

- **The driver auto-runs an optional coherence pass before the final code review.** When the milestone-coherence-reviewer companion plugin is installed, `solve-issue` dispatches it read-only over the built change just before the final `/code-review`, as a never-gating post-build pass. Wired via a new default-filled `coherenceReviewAgent` profile key (`milestone-coherence-reviewer:coherence-reviewer`); silently skipped when the companion is absent. It heals via follow-ups and never blocks or changes a merge. (#231)
- **Fixed: flaky `shell-tests (bash)` render-daemon teardown.** The idempotent-teardown case asserted process liveness the instant `stop` returned, racing the asynchronous SIGTERM teardown sends best-effort, so a loaded CI runner could flake (`teardown: … alive=1`) and block green merges. The test now polls for process death with a bounded window and escalates to a guarded SIGKILL only as a diagnostic - which still fails the test if `stop` did not reap. Mirrored into the PowerShell twin. Test-infra only. (#240)

## v1.12.2 - Triage now catches changes that leave existing users in the dark

_Released 2026-06-23._

**Theme:** When an issue affects existing users or their config, triage now requires a discovery path - a one-time notice, a re-run-setup prompt, or a documented upgrade note - and flags the issue when there is none.

### ✨ Triage insists every existing-user-facing change has a way to be found

| Issue | PR | What |
|---|---|---|
| #224 Add an existing-user discovery/migration-path criterion to the driver's triage-reviewer | #226 | Triage checks whether an issue affects an already-set-up install (a new config key, a changed default, behavior an existing install would not surface on its own) and, if so, looks for a discovery path. Missing path → **Advisory**, pointing at the driver's one-time-notice pattern; escalates to **Blocker** only when the gap makes the issue undeliverable. A brand-new feature an existing install cannot reach is exempt. "It's non-breaking" is not a reason to skip the check. |
| #223 Extend the 3 KEEP-IN-SYNC markers to name the feeder's setup + plan write sites | #225 | The three hand-synced git-ignore scratch blocks carry comments listing where their siblings live; those comments now also name the two copies the companion milestone-feeder plugin writes. Comment text only. |

### Consumer notes (upgrading from v1.12.1)

- **Triage flags an existing-user-facing change that nobody can discover.** No discovery path and existing users affected → **Advisory** (**Blocker** only when the gap makes the issue undeliverable). Exempt: a brand-new feature an existing install cannot reach. The check fires on impact to an already-set-up user, not on whether a change is breaking.
- **#223 is internal maintenance only** - comment text on the driver's hand-synced git-ignore blocks. Nothing visible in your runs.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.12.1 - A one-time nudge so upgraders find the new screenshots feature

_Released 2026-06-23._

**Theme:** v1.12.0's opt-in screenshots were discoverable only at first-time setup, so an existing install never heard about them. A one-time note now surfaces the feature in repos that have UI screens and no visual-capture config.

### ✨ Discoverability

| Issue | PR | What |
|---|---|---|
| #219 Add one-time "New in 1.12.0 - optional visual capture" discovery notice to solve-issue + solve-milestone, gitignore the marker | #220 | Prints a one-time, opt-in-framed note only when all three hold: no `visualCapture` block, the repo declares `uiSurfaceGlobs`, and this checkout has not shown the note. Then it drops a marker and stays quiet. Same pattern as the 1.4.0 preflight and 1.8.0 Trello notices; the marker lives only at `.milestone-config/visualcapture-notice`, with no legacy fallback. |

### Consumer notes (upgrading from v1.12.0)

- **You will see a one-time note if you have UI screens but no visual-capture config.** It prints at most once per checkout; a marker file then silences it. Skipping it changes nothing about your run.
- **Silent when there is nothing to say:** repos with a `visualCapture` block, repos declaring no `uiSurfaceGlobs`, and any checkout that already saw it.
- **New per-checkout marker `.milestone-config/visualcapture-notice`**, git-ignored via the committed scratch-ignore list.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.12.0 - Opt-in screenshots on your UI pull requests

_Released 2026-06-23._

**Theme:** The driver can boot your app, drive it to each changed screen, and attach the screenshots to a UI issue's PR. Strictly opt-in; the screenshots are evidence, never a gate - a UI issue is still never auto-merged, and any capture failure degrades to the manual-visual-test note.

### ✨ Opt-in visual capture for UI pull requests

| Issue | PR | What |
|---|---|---|
| #208 Render-daemon lifecycle seam - one-per-run app-server boot/reuse | #212 | New `scripts/render-daemon.{sh,ps1}`, called as `start` / `status` / `stop`. Reads `visualCapture.serverCmd` and `readyUrl` from the profile; `start` reuses a running daemon or boots the app server once per run, spawned detached in its own process group and polled at the ready URL before returning. `stop` is idempotent and tears down the whole process group, so a compound `cd app && npm run dev` command's children die with it. A stale or dead state file is cleaned and treated as down, never reused, never an error. State lives in `.milestone-config/.runtime/render-daemon.json`. Dependency-free beyond `jq` and `curl`/`wget`. |
| #209 Optional `visualCapture` profile block - schema, validation, setup tier | #213 | Documents the block in `docs/profile-schema.md`: `serverCmd`, `readyUrl`, `signInPath` (all three required when the block is present), plus optional `persona` (default `"super-admin"`), `viewports` (default desktop-only `1440×900`) and `appearances` (default `["light"]`). A block missing any required key is treated as absent and logged; absent = behavior byte-unchanged. Adds a Phase-2 Visual Capture tier to `setup`, surfacing only on a detected signal and writing a sparse object. |
| #210 Capture per-surface visual evidence for UI-issue PRs | #214 | Wires capture into `solve-issue` step 7. For a UI issue on a serial run with a complete block: boot the daemon, sign in through the test seam as the configured persona (substituting `{persona}` into `signInPath`), then drive Playwright MCP once per changed surface × viewport × appearance. Shots are pushed to an orphan `visual-review-assets` branch and embedded in one "👁️ Visual evidence" PR comment. Any failure posts the human-visual-test note instead, never fails the run, never auto-merges. Under parallel runs, capture defers to the serial merge tail - one fixed-port daemon cannot serve concurrent worktrees. |
| #211 Document the visualCapture seam; retire dead `screenshotCmd` prose | #215 | Removes the never-built `screenshotCmd` language from `docs/profile-schema.md` and `docs/consumer-setup.md`, adds a "One render daemon per run" section and the three invariants to `docs/architecture.md`. |

### Consumer notes (upgrading from v1.11.2)

- **New optional profile block `visualCapture`.** Leave it out and nothing changes - no app booted, no screenshot attempted, no new gate, prompt or error.
- **Opting in needs two things on your side:** a browser driven through Playwright MCP, and a seeded app server the driver can boot with a passwordless test sign-in. Declare it with `serverCmd`, `readyUrl` and `signInPath` (e.g. `/dev/sign_in/{persona}`). Optional `persona`, `viewports` and `appearances` default to super-admin, desktop-only, light. Skip any one required key and no block is written.
- **New artifact:** `scripts/render-daemon.{sh,ps1}`. Dependency-free beyond `jq` and `curl` or `wget`.
- **New `setup` tier:** on a detected visual-capture signal, setup walks you through the keys. No signal → skipped silently, like the E2E tier.
- **The three invariants.** (1) Opt-in: absent block = today's behavior exactly. (2) Never fails the run: any capture failure degrades to the human-visual-test note. (3) Never auto-merges a UI issue: the PR is still held open with `needs review`. Logic-only PRs still auto-merge on green; a repo with no `uiSurfaceGlobs` is unaffected.
- **Under parallel runs:** a UI-issue worker opens the PR and applies `needs review` but attaches no screenshots; the serial tail or you capture before merge. Injecting a per-worktree `PORT` opts capture back into the parallel phase.
- **No changes to any existing profile key.**

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.11.2 - Ground the release tail in docs, and make the auto-merge gate real

_Released 2026-06-23._

**Theme:** The human-owned release tail is now documented correctly - merge the release PR with `--merge`, never `--squash` - and this repo's own auto-merge gate runs a real test suite instead of merging on a vacuous green.

### 📖 Document the release tail correctly (`--merge`, not `--squash`)

| Issue | PR | What |
|---|---|---|
| #160 Adopt `--merge` for the release PR + harden the release tail | #204 | Rewrites `docs/consumer-setup.md § Releasing to your protected branch` into the complete ordered runbook. **Merge the integration→protected release PR with `--merge`, never `--squash`:** a squash puts a commit on the protected branch the integration branch never sees, so the two diverge and the next release PR conflicts (typically on `.claude-plugin/plugin.json` + `CHANGELOG.md`) - and a PR-locked integration branch cannot be resolved by pushing, forcing a history-only back-merge PR. The runbook spells out the ordered tail: open and merge the release PR with `--merge` **before** tagging → tag and cut the Release after the merge → close the milestone object → deploy, with the `--notes`-from-CHANGELOG form and `--generate-notes` as the no-CHANGELOG fallback. Two footguns are called out: a bare `gh release create` before the PR merges tags the old tip with wrong notes (happened in v1.9.2), and a PR-locked integration branch blocks direct pushes even for admins. `solve-milestone`'s 🔴 Your move recap and Final-summary next-step both name `--merge` and merge-before-tag. |

### 🧪 Make the driver's own auto-merge gate real

| Issue | PR | What |
|---|---|---|
| #179 Add a CI check on develop so auto-merge gates on tests | #205 | New `.github/workflows/ci.yml` runs the repo's shell test suites on every PR into `develop`: two `ubuntu-latest` jobs, `shell-tests (bash)` and `shell-tests (pwsh)`, covering `tests/extract-version.test` and `tests/ci-preflight-steps.test` on both legs. In the 1.11.0 wave the driver auto-merged on "green CI" with no required status check, so green was vacuous. |

### Consumer notes (upgrading from v1.11.1)

- **#160 is documentation only** - no change to how the driver runs. If you have been squash-merging integration→protected release PRs and hitting recurring conflicts on the next cut, that is the cause; switch to `--merge`. Full runbook in `docs/consumer-setup.md § Releasing to your protected branch`.
- **The CI workflow (#179) gates this repo's `develop` only.** It does not change the installed plugin or your repo; the suite still provisions a CI gate for your repo separately.
- 🔴 **Operator follow-up, not shipped here:** making the two checks *required* on `develop` is a one-time branch-protection step - adding `shell-tests (bash)` and `shell-tests (pwsh)` to the required-checks list via `gh api -X PUT .../branches/develop/protection`, preserving `enforce_admins`. The workflow makes the checks run; the protection PUT makes a red PR unmergeable.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.11.1 - Ground the builder in your project's house docs (anchored retrieval)

_Released 2026-06-22._

**Theme:** The driver's builder and both pre-build reviewers now receive the exact `.project/` sections an issue cites, pulled section by section rather than whole-file, so the plugin that writes the code reads the same source of truth as the one that planned it. Part 2 of 3 of the suite-wide grounding seam.

### ✨ Project-docs grounding via anchored retrieval

| Issue | PR | What |
|---|---|---|
| #183 Add the projectDocs profile key | #190 | New optional `projectDocs` key (default `.project/`, absent-means-default), mirroring the feeder; resolved at the solve-issue and triage profile reads. |
| #184 Ship the read-doc-section primitive | #191 | New dependency-free `scripts/read-doc-section.{sh,ps1}`: given a doc and a `## anchor`, prints only that section and **fails loud** (non-zero exit) on a missing or renamed anchor - never silent empty grounding. Ships a 5-case test twin. |
| #185 Resolve cited sections once in solve-issue | #192 | Resolves the issue's cited `.project/<doc>#<section>` anchors once, pulls a superset via the primitive, and passes the sections into the implementer brief. |
| #186 Resolve cited sections once in triage | #193 | Resolves the cited sections once per issue and passes the same sections into both reviewer briefs. |
| #187 Wire the implementer | #194 | The implementer's "What you receive" consumes the provided sections; Read/grep for additional anchors is retained. |
| #188 Wire the triage-reviewer | #195 | Grounds its five-criteria assessment in the provided sections; on-demand reads retained. |
| #189 Wire the design-reviewer | #196 | Grounds its assessment in the provided sections; on-demand reads retained. |

### 🧹 Scratch hygiene

| Issue | What |
|---|---|
| #199 Self-ignore per-clone scratch | Ships a committed `.milestone-config/.gitignore` that makes per-clone runtime scratch (`preflight-notice`, `trello-notice`, `triage-cache.json`, `tests-stamp`, plus `.runtime/` and `worktrees/`) git-invisible in any repo the plugin runs in, from the first write, with zero user setup - while tracked config (`driver.json`, `feeder.json`) stays tracked. The `tests-green` hook and the scratch-write steps in `solve-issue` / `solve-milestone` / `triage` self-heal the file when absent, so existing repos pick it up on their next run. |

### Consumer notes (upgrading from v1.11.0)

- **New optional profile key `projectDocs`** - where your standing docs live. Default `.project/`; set it only if they live elsewhere.
- **No grounding without docs.** No `.project/` directory, or an issue citing no `.project/#section` anchors, is a clean no-op with no error.
- **Anchored, never whole-file.** Grounding pulls only the cited `## sections` plus plausibly-relevant siblings, so per-dispatch token cost scales with cited-section size, not doc size. A drifted or renamed anchor is a loud failure, not silent empty grounding.
- **New artifact:** `scripts/read-doc-section.{sh,ps1}` (+ its test twin). Dependency-free.
- **Additive to existing gates.** No gate logic, five-criteria assessment or existing profile key changes.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.11.0 - Right model for each job: a stronger builder, leaner reviewers

_Released 2026-06-22._

**Theme:** Each built-in helper is pinned to the model tier that fits its job - the builder to the strong tier, the two pre-build reviewers to a leaner tier an A/B test showed catches the same blocking problems.

### ⚙️ Efficiency & quality - model assigned per helper

| Issue | PR | What |
|---|---|---|
| #173 Pin the implementer (code-writer) to the strong tier | #177 | The implementer is the only helper that writes production and test code. Its model frontmatter goes `inherit` → `opus`, so code is written by the strong tier regardless of the session model, cutting first-try misses against the ≤2-per-gate retry caps. Also bumps the plugin version to 1.11.0. |
| #176 Pin both pre-build reviewers to the mid tier | #178 | The triage-reviewer and design-reviewer only read and check an issue against five fixed criteria; they author nothing, and they are the highest-fan-out helpers in a run (~20× triage, ~17× design per milestone). Both go `inherit` → `sonnet`. The "genuinely unsure → escalate to Blocker" fail-safe is untouched. |

An A/B test recorded on the tracking issue compared models on the reviewers' real job: **Sonnet caught 9 / 9 blocking problems, identical to Opus at 9 / 9**, at the cost of one extra false flag on a clean issue. Haiku was disqualified - it missed a real blocking problem. The fixtures were text-only, so the repo-grounded dependency and pattern checks were not exercised; live-run Blocker recall is monitored and the reviewers revert to `inherit` if a real Blocker is ever missed.

### 📖 Docs - simpler install

The Quickstart leads with the **milestone-suite** install path - one marketplace cataloging all three milestone plugins - keeping the per-repo install as a labeled alternative. ([#167](https://github.com/kenmulford/milestone-driver/issues/167))

### Consumer notes (upgrading from v1.10.0)

- **No config or schema changes.** Only which model each built-in helper uses, plus a README edit.
- **The pins take effect on your next run.** The code-writer always uses the top tier; the two pre-build reviewers always use the mid tier, regardless of your session model.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.10.0 - Deterministic, tested semver extraction for milestone version detection

**Theme:** `solve-milestone` step 3 extracts the milestone version deterministically instead of by model judgment, and `preflightCmd` gains a `"github-ci"` sentinel that derives the local preflight gate from the repo's own CI.

### ✨ Deterministic version extraction

`scripts/extract-version.{sh,ps1}` - a behavior-identical pair driven by the shared golden matrix `tests/extract-version.cases.tsv` - extracts the version from the milestone title (description as fallback) and reports `none` / `ambiguous:<candidates>` on a miss. Step 3 maps that outcome against `versioning` to versioned / version-free / prompt, splitting the previously-identical `absent` and `true` semantics.

### ✨ CI-aware preflight (`preflightCmd: "github-ci"`)

`preflightCmd` accepts the reserved sentinel `"github-ci"` alongside its literal-command mode, deriving the preflight gate from the repo's GitHub Actions CI so a cheap CI check (e.g. `npm audit --omit=dev --audit-level=high`) is front-run locally before the PR instead of being hand-transcribed and forgotten. `scripts/ci-preflight-steps.{sh,ps1}` (golden matrix `tests/fixtures/ci-preflight/`) parses local `.github/workflows/*.yml` with a constrained line parser - no new tool dependency, no network - discovers the PR-gating workflows and emits each job's `run:` steps in order. `solve-issue` step 6.1 runs them through the existing tool-presence-guard → re-dispatch (cap 2) → park machinery. Skip rules drop `uses:` steps, secrets / services / deploy, `${{ }}`-interpolated and step-`if:` steps; `working-directory` is honored and `continue-on-error` steps never park. Coverage is logged ("mirrored N, skipped M"), and a PR-gating workflow yielding zero runnable steps is a visible warning, not a clean pass. One optional `ciWorkflow` key narrows discovery to a single workflow. Documented limitations, with CI as the authority: no `uses:` recursion, no `matrix` expansion, no `act` fidelity, GitHub Actions only. ([#162](https://github.com/kenmulford/milestone-driver/issues/162))

### Consumer notes

- **Behavior change (default `versioning`):** with `versioning` absent (the default), a milestone whose title has no parseable version now **silently runs version-free** instead of parsing by judgment or prompting. Confirm your milestone titles carry a version, or set `versioning: true` to be prompted on a miss.
- **No schema break:** `preflightCmd` keeps its literal-command and absent behavior byte-for-byte; `"github-ci"` and the optional `ciWorkflow` key are additive.

## v1.9.2 - Make the manual close-the-milestone step explicit

**Theme:** Closing the GitHub milestone object is named as a manual, human-only step, with the exact command surfaced - the driver closes a milestone's issues and authors the CHANGELOG, but never the milestone itself.

### ✨ Release-tail clarity

| Issue | PR | What |
|---|---|---|
| #153 make the manual close-the-milestone step explicit | #154 | Names the step in both blast-radius statements (`solve-milestone` SKILL + `docs/architecture.md`) and surfaces `gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed` in the 🔴 Your move block and the Final-summary next-step bullet. |

### Consumer notes (upgrading from v1.9.1)

- **Documentation only** - no change to how the driver runs. After it merges every issue and authors the CHANGELOG, the release tail tells you to close the GitHub milestone object (`gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed`).
- **No schema changes** to `.milestone-config/driver.json`.
- Milestone #16 also included #152, locking this repo's own `develop` to PR-only. Author-repo configuration with **no effect on the installed plugin**; noted for milestone completeness.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.9.1 - Finish the `.milestone-config/` relocation: the per-clone runtime markers move out of the repo root

**Theme:** v1.9.0 relocated the committed profile but left five per-clone runtime artifacts in the target repo root. All five now live under `.milestone-config/` without the redundant `milestone-driver-` prefix, read transitionally (new path first, legacy root as fallback) with the stale root file auto-cleaned on the first new write.

### ✨ Per-clone runtime markers move under `.milestone-config/`

| Issue | PR | What |
|---|---|---|
| #148 Relocate the 5 remaining root-litter runtime markers | #149 | Moves `tests-stamp`, `preflight-notice`, `trello-notice`, `triage-cache.json` and the `worktrees/` scratch dir under `.milestone-config/`. Each persistent marker is read new-path-first with a legacy-root fallback and writes only to the new path (`mkdir -p` / `New-Item -Force` before every write), removing the stale root file on the first new write. The `tests-green` hook skips the suite on either path's matching `branch:treeSHA` and clears both stamps on red; `triage` reads and writes the cache transitionally on both the `jq` and `ConvertFrom-Json` paths; the one-time notice markers stay silent if either marker exists; `worktrees/` is a pure path relocation. `.sh`/`.ps1` parity preserved. |

### Consumer notes (upgrading from v1.9.0)

- **No action required.** Each marker is read from `.milestone-config/<marker>` first and falls back transitionally to the legacy root `.milestone-driver-<marker>`, so an in-flight clone behaves identically: no duplicate notice, no triage-cache rebuild, no re-run of an already-green suite. On the first write to the new path the stale legacy file is removed.
- **No schema change.** These markers are per-clone and gitignored. `.gitignore` adds the five new paths and keeps the legacy root ignores (commented as transitional). The committed `.milestone-config/driver.json` is not ignored.
- **Leftover root files self-clean.** A pre-existing `.milestone-driver-tests-stamp` / `-preflight-notice` / `-trello-notice` / `-triage-cache.json` is read once as the fallback, then removed when the new-path file is first written. A leftover `.milestone-driver-worktrees/` dir is harmless - gitignored and unused; remove it at leisure.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.9.0 - Suite-wide `.milestone-config/` profile location

**Theme:** The driver profile moves to a canonical `<repo>/.milestone-config/driver.json`, read transitionally from the legacy root and auto-migrated on the first build - the precondition the sibling `milestone-feeder` assumes when it reads the driver's shared keys from the same directory.

### ✨ Canonical `.milestone-config/` profile location

| Issue | PR | What |
|---|---|---|
| #144 Resolve profile from `.milestone-config/driver.json` first | #145 | Resolves the profile from `.milestone-config/driver.json`, falling back transitionally to the legacy root `milestone-driver.json` so gates keep firing on un-migrated repos. All eight gate hooks do the two-step read and never mutate (`.ps1` uses the portable multi-arg `Join-Path`). Migration is commit-clean: `setup` and `solve-issue` perform the `git mv` (solve-issue on the feature branch at step 3.5, riding the issue PR), `solve-milestone` migrates via its first dispatched build, and `triage` stays read-only - it surfaces a "legacy profile detected" note but never moves the file. Idempotent everywhere; when both files exist `.milestone-config/driver.json` wins, with no overwrite and no deletion of the leftover root file. |

### Consumer notes (upgrading from v1.8.1)

- **No action required.** The legacy root `milestone-driver.json` is still read transitionally. On the first `setup` or `solve-issue` build a legacy root profile is `git mv`'d to `.milestone-config/driver.json`; `solve-milestone` migrates via its first dispatched build; `triage` is read-only. When both exist, `.milestone-config/driver.json` wins and the leftover root file is left for you to remove.
- **No schema change** - the keys are identical; only the location moved. Add new keys to `.milestone-config/driver.json` going forward.
- **PowerShell gate hooks** resolve the new path with the portable multi-arg `Join-Path` form (PowerShell 7+).

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.8.1 - Surface what the engine already does (and fix the capture defect underneath)

**Theme:** Existing capability made visible - fewer false triage Blockers, a triage cache that says when it skips, the wave trade-off surfaced at the setup decision point - on one reliability repair: the parallel barrier reads git/gh ground truth instead of a worker's free-text handback. Plus a cross-platform gate fix reported from the field.

### ✨ Surfacing the engine's existing behavior

| Issue | PR | What |
|---|---|---|
| #135 setup Integration tier | #141 | Adds an optional Integration tier to `/milestone-driver:setup` for `integrationGranularity`, an existing schema key that was never prompted, defaulting to `issue`. Choosing `wave` fires a non-blocking precondition prompt - is `preflightCmd` set? is `unitTestCmd` your full suite? - surfacing the "one red wave-PR CI blocks the whole Wave" trade-off where the choice is made. |
| #134 visible cache writes | #139 | The best-effort triage cache write no longer fails silently: the Bash path emits a stderr line on `jq`-absent and on write-fail, the PowerShell `catch` surfaces a `Write-Warning`, and the Step 5 output line gains a conditional `; cache write skipped this run` clause. The never-gating contract is unchanged. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #132 barrier reads ground truth | #137 | The parallel Phase 1 barrier re-derives each worker's terminal state from git/gh (the `solve-issue` step-3 probe) instead of trusting the worker's free-text handback, fixing the ~37% handback tail-drop and the hand-finish race. The handback is demoted to an optimization hint; the happy-path partition is byte-identical. |
| #133 fewer false triage Blockers | #138 | `triage-reviewer` downgrades a choice an established repo convention or sibling pattern already answers from Blocker to Advisory (criterion 2 carve-out plus a severity-rule row). Genuine ambiguity still escalates. |
| #136 Unix gate exec bit | #140 | `hooks/run-hook.cmd` was committed mode `100644`, so on macOS/Linux `/bin/sh -c` could not `exec` it (`EACCES`, exit 126) and **every PreToolUse gate was silently inert on Unix**. Now committed `0755`. Cross-platform safe. Reported and verified by @gcpeacock-npm. |

### Consumer notes (upgrading from v1.8.0)

- **🔴 macOS/Linux: all gates now actually run.** Before this release `hooks/run-hook.cmd` shipped non-executable, so every PreToolUse gate died with "Permission denied" and was silently inert. If you applied the `chmod +x` cache workaround, it is no longer needed.
- **New `setup` Integration tier** offers `integrationGranularity`. **No schema change** - the key already existed. Existing profiles need no migration.
- **Triage: fewer false Blockers.** Choices an established convention answers are Advisory rather than parking the issue.
- **Triage cache writes are observable** - a skipped or failed write prints a one-line warning. Still best-effort, never gating.
- **Parallel runs are more robust to dropped worker handbacks** - no happy-path change; the barrier no longer strands a built branch when a worker's final message drifts off-format.

### ⚖️ Post-run audit trail

Judgment-call PRs: none.

## v1.8.0 - Optional Trello board sync + auto-authored release notes

**Theme:** Milestone progress optionally mirrors to a Trello board - a card per milestone moving Queue → In Progress → In Review with a per-issue checklist - and the release notes author themselves at milestone completion. Both opt-in and best-effort; absent their config the loop is byte-unchanged.

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
- **Enable it** by re-running `/milestone-driver:setup` (the External integrations tier is last; existing values pre-fill) or by hand-adding the node - see `docs/consumer-setup.md`.
- **New gitignored marker:** `.milestone-driver-trello-notice` at the repo root. Safe to delete.
- **Release notes author themselves.** A fully-completed run ends with a CHANGELOG PR; a run with any park or hold authors nothing.

### ⚖️ Post-run audit trail

Judgment-call PRs: none. All seven PRs (#123–#129) carry a `## Code Review` section with their findings and resolutions.

## v1.7.0 - Interactive background orchestration, scannable output, triage reuse

**Theme:** The orchestrator no longer clogs the main conversation line, the run is scannable at a glance, and repeat runs stop paying the re-triage tax. Includes the 1.7.1 triage-reuse milestone, rolled in.

### ✨ Background orchestration (the #89 family)

| Issue | PR | What |
|---|---|---|
| #89 Chunked background dispatch | #112 | The milestone loop dispatches each issue (sequential) or each Wave's workers (parallel) via `Agent(run_in_background: true)`. The main line stays interactive; the operator can redirect between chunks. Standalone `solve-issue` gains an opt-in `--async` token (pipeline unchanged except the version-bump confirm defaults to patch, logged as a judgment call). |
| #95 Permission pre-flight gate | #109 | Background subagents auto-deny any tool call that would prompt, so before the first background dispatch the gate verifies the union of readable `permissions.allow` layers (user + project + local) covers the pipeline's tool surface. Gap → 🔴 gap table + synchronous fallback. Workers convert mid-chunk auto-denies to parks. |
| #97 Main-line push notifications | #113 | One notification per event that matters: `⏸️ #N parked - <reason>`, `🌊 Wave N done` (suppressed on the final Wave), `🏁` run complete / `🚨` systemic halt. Main line only - `PushNotification` does not exist in subagent registries. |

### ✨ Scannable output

| Issue | PR | What |
|---|---|---|
| #96 Output spec | #105 | Shared icon legend plus three structured templates: run-start plan board, chunk-boundary status update, final results board. Tables and icons replace free-form narration at every reporting point. |
| #116 Output-spec polish | #118 | The six accepted findings from #105: PR-cell emit rule, one `[..]` placeholder convention, `🔴 Your move` casing, definition-before-reference section order, continuous example cast (#201/#202/#203) across all three templates. |

### ✨ Triage reuse (1.7.1, rolled in)

| Issue | PR | What |
|---|---|---|
| #106 Step-0 context handoff | #111 | `solve-issue` step 0 reuses the milestone run's Phase 0 triage result when the caller explicitly supplies it, eliminating the intra-run N+1 re-triage. Anything not explicitly supplied falls back to fresh single-issue triage. |
| #107 Per-issue result cache | #110 | `.milestone-driver-triage-cache.json` (gitignored) caches per-issue triage results keyed on change signals (labels, body edit time, comment count, milestone description). Unchanged issues skip agent dispatch across invocations; any change - including upstream edges closing unmerged - forces fresh triage. Absent or corrupt cache degrades to full re-triage. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #98 Milestone ID or name | #108 | `solve-milestone 10` and `solve-milestone "1.7.0"` both resolve: number-first for numeric input, paginated title lookup otherwise, fail-fast table of available milestones. |
| #114 Contradictory gate paragraphs | #117 | Deleted two stale STOP-flavored duplicates left by the 1.6.0 autonomy rewrite. Park-don't-prompt is the single directive at the red-suite cap and the `/code-review`-omission gate. |
| #115 Park-reason lookup + park anchor | #119 | Build-park comments open with the canonical `🔴 Parked - ` anchor, joining `🔴 Triage` and `🔴 Blocked`, making the final summary's park-reason lookup a pure prefix match (last matching comment, any run). No match → "park reason not recorded", never a guess. |

### Consumer notes (upgrading from 1.6.0)

- **Allowlist before backgrounding.** Background dispatch activates only when the pre-flight gate passes. Run `/fewer-permission-prompts` or allowlist your git/gh/test commands to enable it; otherwise runs fall back to synchronous behavior.
- **New gitignored artifact:** `.milestone-driver-triage-cache.json` at the repo root. Safe to delete at any time.
- **Park comments changed shape.** New parks open with `🔴 Parked - `. Issues parked by pre-1.7.0 runs report "park reason not recorded (pre-1.7.0 park format)" - read the issue directly for those.
- **No schema changes** to `milestone-driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs: #105, #109, #110, #113, #119 (#115). Each carries its accepted findings and rationale in its Code Review section.
