# Brief: post-alienation follow-ups (milestone-driver)

## What this brief is

Two bodies of work left over after milestone 34, "Fix Subagent Alienation", closed seven of its eight issues on 2026-07-31.

Body 1 is that milestone's one remaining open issue, #400, parked `needs design`. It owes two decisions before anyone can write acceptance criteria for it. One decision is settled. The other is a recommendation that still needs Ken's call.

Body 2 is a defect class the milestone surfaced repeatedly but never fixed at the root: cross-file citations of the form `path:NNN` that go stale silently as cited files grow. Four open issues touch it (#402, #406, #407, #408), and #407 proposes a durable fix whose reach depends on an unresolved structural question about one file.

Neither body is designed here. This brief records the problem, what has already been decided and by whom, what is still open, and the verified repo facts an issue author needs so they do not have to re-derive any of it.

## Vocabulary

| Term | What it means in this repo |
|---|---|
| Wave | A group of issues triage found mutually independent, built together in one pass (`skills/solve-milestone/parallel-waves.md:18`). |
| Stage A / Stage B | Inside a Wave, the concurrent implementer dispatch and the concurrent reviewer dispatch (`skills/solve-milestone/parallel-waves.md:61`, `:75`). |
| Leaf | A dispatched agent that does its own work and dispatches nothing, so its completion notification actually reaches the orchestrator (`docs/architecture.md § Dispatch topology`). |
| `maxParallelWorkers` | Profile key capping how many agents run at once. Absent or invalid resolves to 4 (`skills/solve-milestone/parallel-waves.md:57`, `docs/profile-schema.md:193-197`). |
| built-green / parked / abandoned | The three buckets step 9 sorts every dispatched issue into (`skills/solve-milestone/parallel-waves.md:107-110`). |
| Citation | A cross-file pointer written either as `path:NNN` (a line number) or as `path § Heading` (an anchor). |

---

# Body 1: #400, and the two decisions it owes

## The problem #400 reports

Phase 1 puts a hard barrier between Stage A and Stage B: every dispatched implementer leaf must return before any reviewer leaf is dispatched (`skills/solve-milestone/parallel-waves.md:67`). So a five-minute build's review waits on a twenty-nine-minute build in the same Wave. #400's body records those real timings from a milestone 34 run and asks for each issue's reviewer to be dispatched the moment that issue's implementer returns.

The per-issue tail after review is already unbarriered, so issues already finish out of order once they are past review (`skills/solve-milestone/parallel-waves.md:83`). Only the Stage A to Stage B boundary is synchronized.

## Why it is parked

#400 was filed at 03:34Z on 2026-07-31. #362 merged at 12:03Z the same day (PR #405). #362 made the barrier load-bearing in a way #400 could not have accounted for.

Step 9 now partitions the whole dispatched set into `built-green`, `parked`, and `abandoned` (`skills/solve-milestone/parallel-waves.md:107`), and the `abandoned` bucket keys on the absence of artifacts: no PR, no pushed branch carrying commits ahead of the base, no park label (`:110`). An issue still mid-build presents exactly that ground truth. The barrier is the only thing guaranteeing every implementer has already returned when step 9 runs, so nothing else separates a leaf that is still working from one that silently died.

The consequence of removing the barrier with no replacement is not lost time. Step 9's recover-once ladder dispatches a second implementer leaf into the existing worktree (`skills/solve-milestone/parallel-waves.md:112`), so a healthy in-flight issue would get a second implementer writing into a worktree the first one is still writing to.

#400's own technical claim holds and is not in dispute: nothing in Stage B reads cross-issue state, and each reviewer sees exactly one worktree's diff. The problem is what landed after #400 was written.

## Decision 1: the concurrency cap. SETTLED.

> **PARTLY SUPERSEDED 2026-08-06 (#400 implementation).** The shared-counter half below still holds and shipped as written. The **slot-preference half did not**: the shipped rule is **review-first**, not build-first. When a slot frees, the orchestrator gives it to the **oldest review-ready issue** and dispatches a new implementer **only when none is waiting** ("oldest" = the order implementer leaves returned). That is #400's acceptance criterion 2, re-ratified by the repo owner on 2026-08-06. So the second bullet under "Ken elected" and the third consequence bullet ("Build progress is preferred over review progress") are **superseded**; read them as the record of the 2026-07-30 interview, not as current behavior. The paragraph below is also now **out of date on its own terms**: `parallel-waves.md`, `docs/architecture.md` and `docs/profile-schema.md` no longer document the cap as strictly per-stage — all three were changed to the shared counter in the same pass, and its line numbers have drifted. Nothing here is deleted or rewritten; this note is the amendment.

Decided by Ken, the repo owner, in an interview on 2026-07-30.

Once builds and reviews overlap, `maxParallelWorkers` has to account for two kinds of agent at the same time. Today it is documented as strictly per-stage in three places, which is only safe because the stages never overlap: `skills/solve-milestone/parallel-waves.md:57`, `docs/architecture.md:117` and `:145`, and `docs/profile-schema.md:193-197`.

Ken elected:

- **One shared counter across both stages.** Implementer leaves and reviewer leaves draw from the same pool of slots, not from one pool each.
- **When a slot frees, an implementer takes it before a waiting reviewer.**

The consequences, stated plainly so an issue author does not have to infer them:

- Throughput stays bounded by the same number the operator already configured. A run with `maxParallelWorkers: 4` never has more than four leaves in flight, whatever mix of stages they are.
- No profile key changes shape. `maxParallelWorkers` keeps its name, its integer type, its default of 4, and its fail-open resolution (`docs/profile-schema.md:193-197`). This is not a schema change.
- Build progress is preferred over review progress when the two compete for the same slot, which keeps the Wave's critical path moving. The Wave cannot end before its slowest build ends, so starving builds to run reviews would trade a slot for nothing.

## Decision 2: a step-9 readiness gate. RECOMMENDED, NOT DECIDED.

Ken has not elected this. What follows is the recommendation and its grounding, presented so he can accept, reject, or replace it. An issue author must not treat it as settled.

The recommendation has two parts:

1. **A per-issue readiness gate that step 9 can trust.** Step 9 consults, per dispatched issue, whether that issue's Stage A leaf has returned. An issue whose leaf has not returned is not probed and not classified this pass. This replaces what the barrier currently guarantees for free.
2. **A Wave-level sweep so no issue leaves the Wave unclassified.** At the Wave's existing handoff point, run step 9's classification over any dispatched issue the gate deferred, so every issue still ends the Wave in a bucket.

### Grounding

Ken asked for this by name when he pushed back on the recommendation, in these words: "is there anything you can ground this against to know we aren't just creating ceremonial complexity?" Four findings, verified against the tree:

| Finding | Where | What it supports |
|---|---|---|
| Step 9's checkpoint text is already written per issue: it consults the wave-state cache "for a given dispatched issue" before probing. | `skills/solve-milestone/parallel-waves.md:91` | A per-issue readiness gate matches the shape step 9 already has. It is not a new axis. |
| Step 11 already hands off per Wave and emits one cost record per Wave. | `skills/solve-milestone/parallel-waves.md:149` | A Wave-level sweep point already exists in the procedure. The sweep has somewhere to live. |
| `grep -c sweep skills/solve-milestone/parallel-waves.md` returns 0. | verified 2026-07-31 | No sweep mechanism exists today. This is the honest counterweight: the sweep IS new machinery, and the brief does not pretend otherwise. |
| #362's guarantee is that every dispatched issue leaves step 9 as `built-green` or `parked`. | `skills/solve-milestone/parallel-waves.md:110` | Without a sweep, that guarantee becomes false the moment the barrier comes out, and it is the entire reason #362 exists. |

### The alternatives already considered, with their costs

Recorded in #400's park comment so they are not re-litigated from scratch:

- **An in-flight registry.** Adds durable state that a killed run must reconcile on resume.
- **A dispatch timestamp plus a timeout.** Reintroduces liveness guessing. The skill deliberately keeps a long-interval polling loop as a last-resort safety net against a hung leaf, never as the primary wait mechanism (`skills/solve-milestone/parallel-waves.md:67`).
- **Deferring step 9 entirely to a Wave-level gather.** Correct, but gives back much of the idle time #400 exists to recover.

## Honest scoping: #400's payoff is narrower than its issue body claims

#400's body presents a diagram showing 45 minutes of idle time recovered. That number is reviewer idle time, not wall-clock time saved.

The Wave still cannot finish before its slowest build finishes. Pipelining a fast issue's review into the slow issue's build window recovers the reviewer's waiting, and it frees a slot sooner when the Wave is wider than `maxParallelWorkers`, which is the real gain. It does not shorten the Wave.

#400's own body concedes this in one sentence ("Worst-case wall clock is the same when one issue dominates"), then the diagram beside it invites the opposite reading. **An issue author must not write an acceptance criterion promising a wall-clock win.** The measurable claims available are: reviewer idle time, and time-to-first-slot-free in a Wave wider than the cap.

## Scope notes that ride along when #400 unparks

- The file scope needs `docs/architecture.md` and `docs/profile-schema.md` added alongside `skills/solve-milestone/parallel-waves.md`. #361 set that convention: a dispatch-shape change moves all three together. The cap is described in all three (`docs/architecture.md:117`, `:145`, `docs/profile-schema.md:193-197`), so a shared-counter change that edits only the skill leaves two documents contradicting it.
- #400's "What makes this safe to change" section says only the Stage A to Stage B boundary is synchronized. There is also a Wave-level gather: Phase 2 runs to completion before the next Wave's fleet is cut (`skills/solve-milestone/parallel-waves.md:38`). An implementer should not read #400's sentence as license to loosen that wait too.
- Do not copy line numbers out of #400's park comment. Two of them have already drifted, which is Body 2's subject. Details in the next section.

---

# Body 2: citation drift

## The problem

This repo cross-references itself heavily, and a `path:NNN` citation breaks silently whenever the cited file's line count shifts above the target. Nothing mechanical catches it. An agent following a stale citation to ground a decision reads a blank line, a table separator row, a code fence, or an unrelated heading, and then either proceeds ungrounded or burns a cycle searching.

#397 re-derived 18 stale citations in one pass (PR #409). Four more are filed rather than folded in, because they sit in files #397 did not touch.

## The four open issues

| Issue | Site | What the citation resolves to today | Verified |
|---|---|---|---|
| #402 | `.project/conventions.md:38` cites `docs/consumer-setup.md:232` for the release-merge rule ("`--merge`, never `--squash`"). | A fenced code block opener. The rule is at `docs/consumer-setup.md:296` today. The issue reported `:232` as a JSON example line and `:292` as the rule, so both numbers have moved again since filing. | 2026-07-31 |
| #406 | `skills/setup/SKILL.md:90` cites `docs/profile-schema.md:135` for the `visualCapture` note. | A blank line. The note is at `docs/profile-schema.md:134`. | 2026-07-31 |
| #407 (defect 1) | `skills/solve-milestone/milestone-granularity.md:64` cites `skills/solve-issue/SKILL.md:202-206` for the five-line PR-body Code Review template. | Line 202 is blank. The five template lines are `:203-207`, so the range is off by one at both ends and captures four template lines plus a blank. | 2026-07-31 |
| #407 (defect 2) | `skills/solve-milestone/parallel-waves.md:92` cites `skills/triage/SKILL.md:77-81` for the degrade-to-empty-on-absent-or-corrupt pattern. | Line 77 is blank. The pattern runs `:80-82`: the degradation-rules lead-in, the Bash path, and the PowerShell path. The cited range stops one line short of the PowerShell half, which matters because the claim is specifically about bash and pwsh parity. | 2026-07-31 |

#408 is adjacent but is a different defect and should not be folded in with the others. It is a prose contradiction inside one file: `skills/solve-milestone/SKILL.md:66` asserts by analogy that the purely-numeric-title halt never fires under `--driven`, and `:99` states directly that it still halts and prompts even on a driven run. `:99` is authoritative. Both lines verified 2026-07-31. Nothing about it is a stale line number.

## The class is still producing defects right now

#400's own park comment, written 2026-07-31, already carries two stale citations of exactly this class:

| The comment's claim | Its citation | Where the claim actually lives today |
|---|---|---|
| Step 9 partitions the whole dispatched set | `parallel-waves.md:105` | `:107`. Line 105 is the sentence about mirroring the `solve-issue` step-3 probe. |
| The reasoning for deriving terminal state from artifacts | `parallel-waves.md:87` | `:89`. Line 87 is the Phase-2-before-next-Wave guarantee. |

The comment's other five citations resolve correctly (`:67`, `:83`, `:110`, `:112`, `:57`, plus the three cap sites). Both stale ones land on non-blank but wrong content, which is precisely the sub-class no content-free checker can detect.

There is a third, smaller instance in the same comment: it attributes the hung-leaf polling note to `parallel-waves.md:73`, but that line is the red-unit-suite retry loop. The hung-leaf note is at `:67`.

## The measurement that decides the shape of any fix

From PR #409's Decision Log, measured across #397's change plus a repo-wide sweep:

| Quantity | Count |
|---|---|
| Stale citations #397 corrected | 18 |
| Of those, landing on a blank line, the only class a content-free check can decide | 3 |
| Landing on non-blank but wrong content (separator row, code fence, unrelated heading) | 15 |
| `path:NNN` citations in the repo | 83 |
| `path § Heading` citations in the repo | 26 |
| Anchor citations resolving to other than exactly one heading | 0 |

What follows from it:

- A blank-line checker catches roughly a sixth of the real defect class. Worse, a green run from it would falsely imply the other five sixths are sound, which is worse than having no check at all.
- Making line numbers properly checkable means annotating all 83 with an author-supplied expected token and binding every future author to it. That is a format migration, not a check.
- Anchor uniqueness is decidable with `grep -cx`, needs no author annotation, and survives line shifts by construction.

I re-counted anchor citations on 2026-07-31 and got 26, matching. I did not independently re-run the resolution check behind the 0 and the 83; both are carried from PR #409's measurement.

## What #407 proposes

An anchor-resolution check joining the `scripts/check-*.{sh,ps1}` family, with bash and PowerShell 7 twins producing byte-identical output, mirroring `check-size-budgets`. It resolves every `path § Heading` citation in tracked markdown and fails when a cited heading matches zero or more than one heading line in its target. It reports, and does not fail on, `path:NNN` citations landing on a blank line, with the script header stating plainly that non-blank is not evidence of correctness. `docs/superpowers/` is excluded as frozen records.

Alongside the check: convert heading-targeted citations to anchors opportunistically, whenever one is already being touched. Not a bulk migration.

That family exists today and has fourteen members, all bash and pwsh pairs: `build-file-index`, `check-size-budgets`, `check-skill-frontmatter`, `ci-preflight-steps`, `extract-version`, `parse-md-epic-order`, `read-doc-section`, `render-daemon`, `write-cost-record`.

## The open question: you cannot anchor to a heading that does not exist

This is the question to answer, not one this brief answers.

Converting a citation to an anchor is only possible where a heading exists to anchor to. #397 hit this directly. Of its 18 corrections, 6 were converted to anchors and 12 stayed as line numbers. **Eight of those twelve point into a stretch of `skills/solve-milestone/SKILL.md` that carries no heading at any level.**

Verified 2026-07-31: `## Before starting` is at `skills/solve-milestone/SKILL.md:18` and the next heading of any level, `## The procedure`, is at `:135`. Lines 19 to 134, 116 lines, contain no heading. The eight citations are `skills/solve-issue/md-epic-fanout.md`'s six into that region (`:58-60`, `:61`, `:99`, `:107`, `:114`, `:129`) and `skills/solve-milestone/milestone-granularity.md`'s two (`:96`, `:97`).

Making those anchorable means adding subheadings inside `## Before starting`. Nobody has authorized that structural edit, and it has its own cost, described next.

## The size-budget interaction

`skills/solve-milestone/SKILL.md` is the largest governed file in the repo by both measures: 664 lines and 76,264 bytes, ahead of `skills/solve-issue/SKILL.md` at 382 lines and 73,999 bytes (verified 2026-07-31 with `wc -lc`). Its line ceiling in the ratchet is 680 (`scripts/check-size-budgets.sh:102`), so it has 16 lines of headroom.

#399 (closed) added a byte ceiling beside the line ceiling in `scripts/check-size-budgets.{sh,ps1}`, so every governed file is now guarded against two ceilings rather than one (`scripts/check-size-budgets.sh:3`, `:5-8`). Adding subheadings to that file pays against both. The script's own header records why the line ceiling was kept rather than replaced: this repo's `file:line` citations anchor to line numbers, so line growth carries a cost a byte count cannot express, and it cites #397's 18 re-derived citations as the evidence (`scripts/check-size-budgets.sh:23-26`).

The same script family is where #407's anchor-resolution check would live, so the two changes land in the same place.

---

# What this brief does not decide

- Whether to accept the per-issue readiness gate plus Wave-level sweep for #400, or one of the three alternatives. Ken's call.
- Whether to add subheadings to `skills/solve-milestone/SKILL.md`'s `## Before starting` region so its eight inbound citations become anchorable. A structural edit to the largest governed file, unauthorized today.
- Sequencing between the two bodies. They touch disjoint files and neither depends on the other.
- Acceptance criteria for anything above. Those belong to the issues, not to this brief.
