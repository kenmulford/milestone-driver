# Driver support for a parent issue spanning multiple milestones — design

- **Issue:** TBD (to be filed)
- **Milestone:** TBD
- **Status:** design — pending review, then an implementation plan
- **Date:** 2026-07-04
- **Modifies:** `skills/solve-issue/SKILL.md`, `skills/solve-milestone/SKILL.md`
- **Does NOT modify:** any file in this pass (design only, no code/skill edits)

## Overview / goal

The milestone suite is feeder (plans + creates GitHub milestones/issues) plus driver (builds
them). A feature can be too large for one milestone. GitHub has no primitive that groups
milestones — there is no "milestone of milestones." The chosen solution is a **parent issue**:
an ordinary GitHub issue that anchors the group. Each milestone's own issues become GitHub
**sub-issues** of that parent issue (a native parent↔child link). The parent issue's **body**
carries the ordered list of milestones — the build order across the whole feature. A label,
**`md-epic`**, marks the issue as a parent issue so the driver can recognize it.

**This spec covers only the driver's half: how `solve-issue` and `solve-milestone` detect and
drive a parent issue.** The feeder half (creating the parent issue, applying the label, writing
the ordered list, linking sub-issues) and the bootstrapper half (adding the label to the standard
taxonomy) are separate specs, written later. This document defines the **contract** the driver
reads — the feeder must write to this contract when its own spec is authored.

Vocabulary used throughout this document, deliberately: **parent issue**, **issue body**, **issue
comment**, **the ordered milestone list** (never "manifest"). "Epic" is not a GitHub entity and is
used nowhere in this document except as the literal label name `md-epic`.

## Precondition

The parent issue already exists, fully formed, before any driver run touches it:

- It carries the `md-epic` label.
- Its body contains the ordered milestone list (grammar below).
- Each milestone's issues are linked to it as native GitHub sub-issues.

All three are **feeder/bootstrapper responsibilities, specced later**. The driver is a **reader
only** — it never creates the label, never applies it, never writes the ordered list, and never
links a sub-issue. Nothing in the design below performs a write against the parent issue itself
(comments/labels the driver posts land on the *milestones' own issues* or, in one park case, on
the parent issue purely to report a contract violation the driver can't safely proceed past — see
Error handling).

## Verified GitHub facts

Researched directly against current GitHub REST docs (fetched 2026-07-04) rather than assumed from
training data, per the currency requirement for platform/API claims:

- **Sub-issues are native and generally available.** A parent↔child link between two issues. A
  sub-issue is a full, standalone issue — it keeps its own milestone, labels, and assignees; the
  parent link is an overlay on top of an otherwise ordinary issue. Limits: up to 100 sub-issues
  per parent, up to 8 levels of nesting (confirmed against
  [docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)).
  REST endpoints (confirmed against
  [docs.github.com/en/rest/issues/sub-issues](https://docs.github.com/en/rest/issues/sub-issues)):
  `GET /repos/{owner}/{repo}/issues/{issue_number}/parent`,
  `GET`/`POST /repos/{owner}/{repo}/issues/{issue_number}/sub_issues`, and — note the singular,
  which differs from the plural GET/POST paths —
  `DELETE /repos/{owner}/{repo}/issues/{issue_number}/sub_issue`. GraphQL exposes
  `subIssuesSummary { total completed }` and `parent { number }` on `Issue`.
  - **One caveat worth flagging for the feeder spec, not resolved here:** GitHub's September 2025
    changelog states sub-issues "now inherit the Project and Milestone of their parent issue by
    default" ([github.blog/changelog/2025-09-11](https://github.blog/changelog/2025-09-11-a-rest-api-for-github-projects-sub-issues-improvements-and-more/)).
    Neither that changelog nor the docs pages above say whether this is a one-time creation-time
    default or an enforced sync. This design's read-contract does not depend on the answer — the
    driver never reads a sub-issue's inherited milestone, only the ordered list in the parent
    body (below) — but the feeder spec must confirm each sub-issue ends up on **its own**
    milestone (not the parent's, since the parent carries no milestone at all) when it authors the
    link.
- **Issue dependencies (blocked-by/blocking) are also native and generally available**, but this
  design does not use them for ordering. The ordered milestone list in the parent issue's body is
  the sole ordering source of truth. Dependencies are available, not required, by this design.
- **Issue types are organization-only** — unavailable on personal accounts. This is why the
  parent-issue marker is a label (`md-epic`), not an issue type: an issue-type-based marker would
  not work for every consumer of this plugin.

## The read-contract

This is the artifact the feeder must produce and the driver consumes. The driver is the reader, so
this section is authoritative for the format; the feeder spec must match it, not the reverse.

### The label

`md-epic`, applied to the parent issue only. Exact, case-sensitive match against
`.labels[].name`. Not applied to the milestones' own issues, not to be confused with any of the
existing park labels (`in progress` / `blocked` / `needs design` / `needs decision` / `needs
review` / `judgment call`, `docs/architecture.md:39-52`). No new profile key is introduced for the
label name — it is a fixed literal, exactly like every other label in the existing taxonomy is a
fixed literal (`docs/profile-schema.md:68`: "new keys are added only when a real second consumer
needs them — never speculatively"; a configurable label name has no second consumer today).

### The ordered milestone list block

A fenced code block in the parent issue's body, info-string `md-epic-order` (three backticks
immediately followed by the string, no leading space — standard GitHub-Flavored-Markdown fence
syntax). The driver locates it with a plain-text scan of the body for that exact opening fence
line, then reads forward to the next line that is exactly a closing fence.

**Grammar.** Inside the block, one milestone reference per non-blank line. **Line order is build
order** — top to bottom, no separate ordinal column to keep in sync (a numbered-prefix variant was
considered and rejected: a numeral that duplicates the line's own position is a second field that
can drift from the truth and buys nothing). Each non-blank line matches exactly one of:

| Line form | Meaning |
|---|---|
| `number: <integer>` | The milestone's own number (its `/milestones/<number>` value) — **not** an issue number |
| `title: <text>` | The milestone's exact title, verbatim, case-sensitive |

Blank lines inside the block are permitted (ignored) for readability. No other line shape is
valid inside the block.

**Why not `#<n>`.** Milestones are identified by number, but a bare `#42` in a GitHub issue body
is autolinked to **issue** #42 — a completely different numbering namespace. Writing `#42` to mean
"milestone 42" collides with that autolink and misleads any human or tool reading the body. The
`number:` / `title:` line prefixes never use `#`, so the collision cannot occur by construction.

This also sidesteps a second, unrelated ambiguity that already exists elsewhere in this plugin:
`solve-milestone`'s own `$ARGUMENTS` routing treats a purely-numeric milestone **title** as
indistinguishable from a milestone **number** typed by a human, and has to halt and prompt when it
detects that collision (`skills/solve-milestone/SKILL.md:105`). Because every line in this block
is explicitly tagged `number:` or `title:`, that ambiguity never arises here — a milestone titled
`"2027"` referenced as `title: 2027` is unambiguous at parse time.

**Worked example.** Parent issue #501, titled "Contacts module (parent)", carries the `md-epic`
label. Its body:

````markdown
This issue anchors the contacts module rollout across three milestones. See the linked
sub-issues below for the individual work items; the build order is:

```md-epic-order
number: 42
title: Contacts sync engine
number: 51
```

Do not build any of these milestones out of the order above — the sync engine depends on
the import work landing first.
````

Parsed to three ordered entries: `{kind: number, raw: 42}`, `{kind: title, raw: "Contacts sync
engine"}`, `{kind: number, raw: 51}`.

**Resolution.** Reusing the two lookups `solve-milestone` already performs when a human types a
milestone argument (`skills/solve-milestone/SKILL.md:102-106`), applied per line instead of to a
single CLI argument:

- A `number:` line resolves via `gh api repos/{owner}/{repo}/milestones/<number> --jq '{number,
  title}'` (mirrors `skills/solve-milestone/SKILL.md:103`). A non-2xx response means "does not
  resolve."
- A `title:` line resolves via `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100"
  --paginate --jq '.[] | select(.title=="<text>") | {number, title}'` (mirrors
  `skills/solve-milestone/SKILL.md:104`). Zero matches, or more than one match, both mean "does
  not resolve" — the driver never guesses between two same-titled milestones.

Every entry — however it was written — resolves to a canonical `{number, title}` pair. The
fan-out loop (U3, below) always drives the resolved **number** downstream, never the title, which
is what keeps it clear of the purely-numeric-title collision noted above.

**Note on the native sub-issue links.** The parent issue's sub-issue links (the GitHub-native
parent↔child relationship) are **not** read by this contract at all. They exist for GitHub's own
UI progress tracking (`subIssuesSummary`) and are a *passive reflection* of the same underlying
per-issue state the driver already tracks by other means — closed issues close, and GitHub updates
the summary automatically. The driver's own resumability signal (U3) reads each milestone's
`open_issues` count directly; it never queries the parent's sub-issue graph.

### Error handling for the contract

| Condition | Handling |
|---|---|
| `md-epic` present, no `md-epic-order` block found in the body (including an unterminated fence) | Park the **parent issue**: comment opening `🔴 Parked — ` naming the missing/unterminated block, apply `blocked`. Do not silently build nothing. |
| A line inside the block does not match `number: <integer>` or `title: <text>` | Same as above — treat the **whole block** as untrustworthy once one line fails to parse (a bad line invalidates position-by-line-order for everything after it), park the parent issue `blocked`, quote the exact offending line and its position in the comment. |
| A `number:`/`title:` line is well-formed but resolves to no milestone (bad number, or zero/multiple title matches) | Not a park. Skip **only that entry**, log a warning in the run's aggregate summary, continue with the remaining entries. |
| A resolved milestone has **zero total issues** (`open_issues + closed_issues == 0`) | Skip **only that entry** with a warning (misconfigured/empty milestone) — do **not** count it as done. |
| A resolved milestone has **zero open issues but at least one closed issue** | Already complete — skip silently, count as done. This is the ordinary resume-skip case, not a warning. |
| The same milestone number appears twice in the list | Not specially detected. Harmless: the second pass re-checks completion and is a no-op if the first pass already finished it; wasteful but not incorrect if it hasn't. |

The distinction in the middle two rows (skip-with-warning vs. skip-silently) both key off the same
`open_issues`/`closed_issues` pair from `gh api repos/{owner}/{repo}/milestones/<number>` — GitHub's
milestone resource carries both counts, so "never had any issues" and "finished" are
distinguishable even though both show `open_issues == 0`.

## Driver behavior

### `solve-issue <n>` — the parent path

**Detection (U1) runs before anything else** — before today's `## Before starting` step 1
(`skills/solve-issue/SKILL.md:12-14`), and before `### 0. Triage` (`skills/solve-issue/SKILL.md:96`).
Read `#n`'s labels (`gh issue view <n> --json labels`). No `md-epic` → **today's behavior is
unchanged, byte-for-byte** — the same framing this plugin already uses for its other two internal
tokens: "when the `--worker` token is absent, none of this section applies and the entire
sequential pipeline above runs byte-unchanged" (`skills/solve-issue/SKILL.md:327`); "when the
`--async` token is absent, none of this section applies" (`skills/solve-issue/SKILL.md:390`). The
parent path is the same shape of opt-in fork, gated on a label read instead of a dispatch token.

`md-epic` present → the **parent path**, which replaces the rest of `solve-issue`'s pipeline
entirely for this invocation:

1. Today's Before-starting **step 1 (profile read) still runs** — the fan-out loop needs
   `integrationBranch` to re-sync between milestones. Steps 2 and 3 (clean-tree check,
   branch-state probe) do **not** apply — there is no per-issue feature branch for a parent issue,
   because a parent issue authors no code.
2. Parse the ordered milestone list from `#n`'s body (U2).
3. Drive each resolved milestone in listed order, **sequentially** — a later milestone may depend
   on an earlier one's code landing first — re-syncing `integrationBranch` between milestones (U3).
4. The parent issue itself is **never built**. It has no code, so it never goes through
   `### 0. Triage` or root-cause-or-park. It is a pure orchestration node; its native sub-issue
   progress reflects completion passively, as noted above.
5. **Resumable with no local state.** Re-running `solve-issue <n>` re-checks each listed
   milestone's `open_issues`/`closed_issues` from GitHub and skips whatever is already complete —
   the same no-checkpoint-file philosophy already stated for the per-issue branch-state probe:
   "there is no checkpoint file to maintain, drift, or delete" (`skills/solve-issue/SKILL.md:77`).
6. On completion, emit an aggregate summary (milestones done / parked / held for visual review),
   mirroring `solve-milestone`'s own run-complete reporting shape (`skills/solve-milestone/SKILL.md:453`,
   `:528`) — one row per **milestone** instead of one row per **issue**.

### `solve-milestone <ms>` — human-typed vs. driven (U4 + U5)

**Human-typed invocation** gets a new check inserted into Before-starting, after today's step 3.5
(Trello card resolution, `skills/solve-milestone/SKILL.md:109`) and before today's step 4
(clean-tree check, `skills/solve-milestone/SKILL.md:110`) — call it **step 3.6**. It fires only
when the `--driven` token (below) is absent:

1. Find the resolved milestone's first issue (lowest issue number currently assigned to the
   milestone, `--state all` so a fully-built milestone is still inspectable —
   `gh issue list --milestone "<resolved-title>" --state all --json number --jq 'sort_by(.number) |
   .[0].number'`).
2. Read that issue's parent in one call: `gh api repos/{owner}/{repo}/issues/<first-issue>/parent`
   returns the full parent issue object (or 404 if there is no parent) — its `.labels` are already
   present in that response, so no second call is needed to check for `md-epic`.
3. **No parent, or a parent without `md-epic`** → today's behavior, unchanged: build just this
   milestone, autonomously, no prompt.
4. **A parent carrying `md-epic`** → PROMPT the human with exactly three options: **[build just
   this milestone]** / **[hand off to `solve-issue #<parent>` to drive the whole parent issue in
   build order]** / **[pause for clarification]**. This wording is a starting proposal, not
   locked — see Open questions. Selecting the hand-off option invokes
   `/milestone-driver:solve-issue <parent-number>` directly (the same skill-invokes-skill pattern
   `solve-milestone` already uses for `/milestone-driver:triage`,
   `skills/solve-milestone/SKILL.md:191`) and this run's own Before-starting sequence stops here.

**Internal/driven invocation** — the fan-out loop (U3) never types `solve-milestone <name>`
verbatim; it invokes `/milestone-driver:solve-milestone <resolved-number> --driven`. `--driven` is
an **interpreted token, not a parsed CLI flag** — recognized exactly the way `--worker` and
`--async` already are ("`--worker` is an interpreted token, not a parsed CLI flag,"
`skills/solve-issue/SKILL.md:327`; "`--async` is an interpreted token,"
`skills/solve-issue/SKILL.md:390`) — never typed by a human, proposed here for naming symmetry with
those two. When present, **step 3.6 above does not execute at all** — not merely "answered
silently," the parent-lookup query itself is skipped, which also prevents a driven milestone from
ever re-detecting its own dispatching parent and re-prompting. This is what preserves
`solve-milestone`'s existing unattended contract: "the loop never waits on a human... only a
systemic failure ends the run early" (`skills/solve-milestone/SKILL.md:256`).

**Out-of-order safety.** If a human picks "build just this milestone" and one of its issues
depends on unmerged work from an earlier not-yet-built milestone, that issue parks on "unmerged
upstream" through the **existing** park-and-continue machinery
(`skills/solve-milestone/SKILL.md:252-254`) exactly as it already does for an intra-milestone
dependency. No new mechanism. This also covers the equivalent case inside a driven run: triage's
`dependencyGraph` is scoped to one milestone's own issues (it has no notion of a prior milestone in
the same parent-issue group), so a genuine cross-milestone dependency is not caught proactively —
it surfaces reactively, through whatever build-time signal it naturally trips (the root-cause gate,
a red suite, or an implementer-declared architecture conflict), the same as any other unforeseen
build-time problem. See Open questions — the resulting park's reason will be less specific than
the existing same-milestone "held by unmerged upstream #N" comment.

## The 5 units

**(U1) Parent detection**
- **Purpose:** decide whether a given issue is a driver parent issue.
- **Interface:** in — an issue number; out — boolean (does it carry `md-epic`).
- **Mechanism:** `gh issue view <n> --json labels`, exact match against `.labels[].name`.
- **Dependencies:** none. Consumed at the very start of `solve-issue` (before Before-starting step
  1) and, in a different call shape, inside U5 (which gets the parent's labels for free from the
  `.../parent` response rather than calling U1's exact command a second time).

**(U2) Ordered-list parse**
- **Purpose:** turn the parent issue's body into an ordered array of resolved `{number, title}`
  milestones, or a parse-failure signal.
- **Interface:** in — the parent issue's raw body text; out — either an ordered list of resolved
  milestones plus zero or more "entry did not resolve" warnings, or a whole-block parse failure
  (no block found / unterminated / a malformed line, naming the line and position).
- **Mechanism:** locate the `md-epic-order` fence, split into lines, validate each non-blank line
  against `number: <integer>` / `title: <text>`, resolve each per the read-contract's Resolution
  rules above.
- **Dependencies:** none upstream. Feeds U3.

**(U3) Fan-out loop**
- **Purpose:** drive the resolved milestone list to completion, in order, resumably, with an
  aggregate report.
- **Interface:** in — U2's ordered resolved list; out — per-milestone outcome (done already /
  built this run / parked-with-opens / held for visual review) plus the aggregate summary.
- **Mechanism:** for each entry in order — check `open_issues`/`closed_issues` via `gh api
  repos/{owner}/{repo}/milestones/<number>`; if already complete (open 0, closed > 0), record done
  and continue; otherwise invoke `/milestone-driver:solve-milestone <number> --driven`, await
  completion, re-derive the outcome from `gh` ground truth rather than trusting the invoked run's
  own final narrative (the same re-derive-over-handback posture already used at the
  worker/barrier boundary, `skills/solve-milestone/SKILL.md:367`), re-sync `integrationBranch`
  (`git fetch`, fast-forward), then continue to the next entry regardless of whether this one
  fully completed — per the locked out-of-order-safety design, a partially-parked milestone does
  not block the loop from proceeding to the next one.
- **Dependencies:** U2 (the list to drive), U4 (the driven-mode gate on the invoked
  `solve-milestone`).

**(U4) `solve-milestone` caller-mode gate**
- **Purpose:** decide whether an invocation of `solve-milestone` should run its human cherry-pick
  check (U5) or skip straight to autonomous behavior.
- **Interface:** in — presence/absence of the `--driven` token in the invocation text; out — which
  branch of Before-starting step 3.6 executes (full check, or none at all).
- **Mechanism:** token recognition identical to `--worker` / `--async`
  (`skills/solve-issue/SKILL.md:327`, `:390`) — string presence in the dispatch text, not argument
  parsing.
- **Dependencies:** none upstream (a pure gate). Gates U5.

**(U5) `solve-milestone` human cherry-pick prompt**
- **Purpose:** when a human directly targets one milestone that turns out to belong to a
  parent-issue group, offer a real choice instead of silently building only a slice of a larger,
  ordered feature.
- **Interface:** in — the resolved `{number, title}` of the milestone a human typed; out — one of
  three outcomes (build just this one / hand off to the parent's `solve-issue`, which stops this
  run / pause for clarification).
- **Mechanism:** first-issue lookup → `.../issues/<n>/parent` → label check on the returned parent
  object (reuses U1's label-check logic, not a second live call).
- **Dependencies:** U4 (only runs when `--driven` is absent), U1 (the label check it performs on
  the parent).

## Error handling & edge cases

Beyond the read-contract table above:

- **Systemic failure inside a driven `solve-milestone` run** (auth broken, `integrationBranch`
  gone, required tooling missing) halts that run per its own existing Autonomy contract
  (`skills/solve-milestone/SKILL.md:448-449`). U3 propagates this as a halt of the **whole
  fan-out loop**, not just the current entry — a systemic failure means later milestones cannot be
  driven safely either.
- **`--driven` also needs to suppress the pre-existing DB-hazard interview**, not only the new
  cherry-pick prompt. `solve-milestone`'s execution-mode cascade already has an interactive gate
  unrelated to this design — row 4, "`unitTestCmd` set AND `parallel` absent AND interactive"
  (`skills/solve-milestone/SKILL.md:118`) — with a non-interactive degradation already defined for
  headless/cron callers (row 4′, `skills/solve-milestone/SKILL.md:119`, `:141`). A driven
  invocation has no human watching, by the same logic that already degrades row 4 under
  `MILESTONE_DRIVER_NONINTERACTIVE=1`. `--driven` must make row 4's "interactive" condition read
  false, the same way the env var already does, or the fan-out loop can still block on an
  unrelated prompt — defeating the whole point of driven mode. This was not stated in the original
  request; flagged in Open questions.
- **`--driven` is trusted, not defended against misuse** — consistent with `--worker` and
  `--async`, which are also internal-only tokens with no validation that the caller was
  legitimate. Nothing new here.
- **No cycle detection.** Nothing stops a malformed ordered list from referencing a milestone whose
  own first issue's parent is *also* `md-epic`-labeled (a nested structure this design does not
  anticipate). The driven-mode short-circuit in U4 prevents an infinite **prompt** loop (a driven
  run never re-checks U5 at all), but does not detect or reject a genuinely cyclical authoring
  mistake. Out of scope for this pass — flag if the feeder's design could ever produce nesting.
- **Duplicate milestone entries** in the ordered list are not rejected (see the read-contract
  table) — naturally idempotent-safe, not specially guarded.

## Non-goals

- The feeder half: creating the parent issue, applying `md-epic`, writing the ordered milestone
  list, linking sub-issues. Specced separately, later.
- The bootstrapper half: adding `md-epic` to the standard create-if-missing label taxonomy.
  Specced separately, later.
- Using GitHub's native issue-dependencies (blocked-by/blocking) for enforcement. Available, not
  used — the ordered list in the parent body is the sole ordering source of truth.
- Parallelizing **across** milestones. The fan-out loop (U3) is sequential by design; only the
  existing within-milestone Wave parallelism is unaffected.
- Final prompt-UX wording for U5's three-option prompt. The wording above is a starting proposal,
  explicitly refinable.

## Feeder → driver integration: verification gate

This driver design assumes a well-formed parent issue produced by the feeder. **Before the feeder
is wired to the driver and the two halves are deployed together, both checks below MUST pass — this
is a required gate, not optional.** The feeder's own spec (written later) must carry this gate
forward as an explicit acceptance criterion; it must not be skipped when work crosses from the
feeder phase to the driver phase.

1. **Milestone-inheritance behavior** (the Sept-2025 GitHub risk recorded under *Verified GitHub
   facts*). On a throwaway repo, confirm that linking an existing, already-milestoned issue as a
   sub-issue of a **milestone-less** parent issue **preserves the sub-issue's own milestone** — i.e.
   GitHub's "inherit the parent's Milestone by default" does not clear it to the parent's (null)
   milestone. If GitHub does overwrite it, the feeder **must** re-set each sub-issue's milestone
   after linking, and that becomes a required feeder step. This gate is what catches it before the
   driver ever relies on the arrangement.
2. **End-to-end contract conformance.** A real feeder-produced parent issue must satisfy every
   clause of *The read-contract* above — `md-epic` label present; the `md-epic-order` block parses;
   every entry resolves to a real milestone; each milestone's issues are linked as sub-issues and
   sit on their own (correct) milestone — and drive to completion through the fan-out loop (U3).
   This is the integration test that gates deploying the two halves together.

Neither the feeder phase nor the joint deployment is "done" until both pass.

## Resolved decisions

The questions raised during design review were decided by Ken on 2026-07-04:

1. **Park label for "no parseable ordered list": `blocked`.** A malformed parent issue is a
   contract/authoring gap the human clears, not an app design gap (`needs design` was the
   alternative).
2. **Malformed-line severity: park the whole parent issue.** Any line that fails to parse
   invalidates the entire ordered list — a half-parsed build order is unsafe to act on. Skip-just-
   the-line is reserved only for well-formed-but-unresolvable entries.
3. **`--driven` must also suppress the pre-existing DB-hazard interview (row 4,
   `skills/solve-milestone/SKILL.md:118-119`) — IN SCOPE.** A driven run has no human watching; if
   the interview still fired, the fan-out loop would block, defeating driven mode. The
   implementation makes `--driven` force row 4's "interactive" condition false, the same way
   `MILESTONE_DRIVER_NONINTERACTIVE=1` already does.
4. **"First issue" for the U5 check: the numerically lowest issue number assigned to the milestone
   (`--state all`).** Deterministic; GitHub offers no reliable creation-order query.
5. **Cross-milestone dependency parks are reactive-only for v1.** Honors "no new mechanism" — a
   genuine cross-milestone dependency surfaces through whatever build-time signal it trips, with a
   less specific park reason than the same-milestone "held by unmerged upstream #N" comment.
   Revisit a dedicated comment wording only if it proves common.
6. **`--driven` flag name: accepted** (symmetry with `--worker` / `--async`).

## Cross-references

- `skills/solve-issue/SKILL.md:12-14` — Before-starting step 1 (profile read), still run on the
  parent path.
- `skills/solve-issue/SKILL.md:77` — no-checkpoint-file resumability philosophy, reused for U3.
- `skills/solve-issue/SKILL.md:96` — `### 0. Triage`, skipped entirely for a parent issue.
- `skills/solve-issue/SKILL.md:323-330`, `:388-421` — `--worker` / `--async` internal-token
  precedent for `--driven`.
- `skills/solve-milestone/SKILL.md:102-108` — dual number/title milestone resolution, reused by U2.
- `skills/solve-milestone/SKILL.md:109-145` — Before-starting steps 3.5–5, where the new step 3.6
  (U5) slots in.
- `skills/solve-milestone/SKILL.md:118-119`, `:141` — the pre-existing DB-hazard interview and its
  non-interactive degradation, which `--driven` must also suppress (Open question 3).
- `skills/solve-milestone/SKILL.md:150` — `gh issue list --milestone ... --state open`, the
  existing per-milestone issue-listing query U3's completion check is independent of.
- `skills/solve-milestone/SKILL.md:191` — `solve-milestone` invoking `/milestone-driver:triage` as
  a sibling skill, the precedent for `solve-milestone` invoking `/milestone-driver:solve-issue` on
  hand-off.
- `skills/solve-milestone/SKILL.md:218` — the live-label-check `gh issue view` pattern reused by
  U1.
- `skills/solve-milestone/SKILL.md:252-254` — existing "held by unmerged upstream" park machinery,
  reused unchanged for out-of-order safety.
- `skills/solve-milestone/SKILL.md:256` — "the loop never waits on a human," the contract
  `--driven` preserves.
- `skills/solve-milestone/SKILL.md:367` — re-derive-from-ground-truth-over-handback precedent,
  reused by U3.
- `skills/solve-milestone/SKILL.md:448-449` — systemic-halt contract, propagated by U3.
- `docs/architecture.md:39-52` — the existing label taxonomy `md-epic` sits alongside.
- `docs/profile-schema.md:68` — "new keys only when a real second consumer needs them," why
  `md-epic` is a fixed literal and not a profile key.
