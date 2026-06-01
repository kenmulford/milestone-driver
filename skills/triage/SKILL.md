---
name: triage
description: This skill should be used when the user invokes "/milestone-driver:triage <milestone-name | issue-number>", or asks to "triage the milestone/issue", "triage the milestone", "review for gaps", or "review this issue for gaps". Reviews issues for design gaps and dependency ordering before building — the Layer 0 pre-build phase. Authors no code; opens no PRs.
---

# triage — pre-build review phase

Review issues for design gaps and dependency ordering. Emit an all-clear or a gap table. Post a blocker summary on each affected issue. Return the validated dependency graph. **Authors nothing; opens no PRs.**

## Announce first

Say this to the user before doing any work:

> Standing by while I review the issue(s) for gaps and dependencies that would need your input before building.

## Modes

| Argument | Mode | Scope |
|---|---|---|
| Milestone name (string) | **Batch** | All open issues in that milestone |
| Issue number (integer) | **Single** | That one issue |

## Procedure

### Step 1 — Read the profile

Read `milestone-driver.json` at the repo root. If absent or missing a required Core key, invoke `milestone-driver:setup` to bootstrap it, then continue.

Extract:

| Key | Default |
|---|---|
| `triageAgent` | `milestone-driver:triage-reviewer` |
| `designReviewAgent` | `milestone-driver:design-reviewer` |
| `uiSurfaceGlobs` | *(absent → no design-lens review)* |
| `sourceGlobs` | *(pass through to the agent brief in Step 3)* |
| `nonNegotiables` | *(pass through to the agent brief in Step 3)* |

### Step 2 — Gather issues

**Batch mode** (argument is a milestone name):

1. Read the milestone description to extract the declared Wave/dependency order — the same source `solve-milestone` uses:

   ```
   gh api "repos/{owner}/{repo}/milestones" \
     --jq '.[] | select(.title=="<milestone-name>") | .description'
   ```

2. List all open issues in the milestone:

   ```
   gh issue list --milestone "<milestone-name>" --state open --json number,title,body,labels
   ```

3. For EACH issue number returned, fetch its comments (recorded design decisions / `design-cleared` notes):

   ```
   gh issue view <n> --json comments --jq '.comments[].body'
   ```

   Note: `gh issue list` does not return comment bodies, so this per-issue `gh issue view` is required.

**Single mode** (argument is an issue number):

- Fetch the one issue with its comments in one call:

  ```
  gh issue view <n> --json number,title,body,labels,comments
  ```

Both modes end with the same inputs for Step 3: each issue's number, title, body, labels, AND its comments — because the Step 3 agent brief requires "all comments and any design-cleared notes."

### Step 3 — Dispatch `triageAgent` per issue

Dispatch the agent named in `triageAgent` (default `milestone-driver:triage-reviewer`) for each issue. Dispatches are **parallelizable** — run them concurrently when the tool environment supports it.

**Brief each agent with:**

- The issue: number, title, body, acceptance criteria, labels.
- Its recorded design decisions: all comments and any `design-cleared` notes fetched in Step 2.
- The milestone description (the declared Wave/dependency order) — batch mode only; pass an empty string in single mode.
- The profile: `sourceGlobs`, `uiSurfaceGlobs`, `nonNegotiables`.

**Each agent returns:**

```
ISSUE: <n>
DEPENDS_ON: [<issue numbers>]   # validated edges, with one-line reasons
NEEDS_DESIGN_REVIEW: yes | no
GAPS:
  - lens: architect
    severity: Blocker | Advisory
    type: contradiction | not-buildable | missing-criteria | undeclared-dependency | risky-design
    description: <one line>
    to_clear: <what the human must decide/record to clear it>
  - … (or "none")
```

For each issue whose `triageAgent` return carries `NEEDS_DESIGN_REVIEW: yes`, dispatch `designReviewAgent` (default `milestone-driver:design-reviewer`).

**Brief the design agent with:**

- The issue: number, title, body, acceptance criteria.
- Its recorded design decisions: all comments and any `design-cleared` notes.
- Pointers to existing UI surfaces the issue neighbors — via `uiSurfaceGlobs` from the profile.

**The design agent returns:**

```
ISSUE: <n>
GAPS:
  - lens: design
    severity: Blocker | Advisory
    type: scalability | pattern-inconsistency | missing-state | missing-affordance | accessibility
    description: <one line>
    to_clear: <suggested resolution or reference pattern (e.g. "group under collection headers like ConfirmImportPage")>
  - … (or "none")
```

### Step 4 — Aggregate findings

Collect all GAPS across all agent returns for each issue. Aggregate by `lens` / `severity` / `description` / `to_clear` — the `type` tokens differ between the two agents by design; match on the other fields, not `type`.

Build the **validated dependency graph** from all `DEPENDS_ON` edges:

- Merge agent-returned edges with the milestone's declared Wave order.
- Where an agent finds an undeclared dependency, add it to the graph (and it surfaces as a Blocker in the gap table).
- Produce the Wave-ordered graph for output.

### Step 5 — Output to the user

**All clear** (no Blocker gaps across all issues):

```
✅ All clear

Wave-ordered dependency graph:
  Wave 1 (parallel): #A, #B, #C
  Wave 2: #D (depends on #A, #B)
  Wave 3: #E (depends on #D)

Advisory notes:
  #B — <one-line advisory>
```

Omit the "Advisory notes" section when there are none.

**Gaps present** (any issue has one or more Blocker gaps) — emit a table, Blockers first:

| Issue | Lens | Severity | Gap | What's needed |
|---|---|---|---|---|
| #43 | architect | Blocker | Recorded design is internally contradictory: "mirror ConfirmImportPage grouping" vs "flat list, no collection picker" | Record the authoritative grouping decision on the issue |
| #43 | design | Blocker | Flat 16-row list at realistic volume will produce a poor result vs established grouped-card pattern | Group under collection headers as in ConfirmImportPage |
| #37 | architect | Advisory | No empty-state criterion specified | Record expected empty-state behavior |

Blockers sort before Advisories within each issue. Issues sort by number ascending.

Include the Wave-ordered dependency graph after the table (even when gaps are present — the graph still informs which clean issues can build immediately).

### Step 6 — Comment on each affected issue and recommend its park label

For every issue that has **Blocker** gaps:

1. **Post a triage comment** (`gh issue comment <n> --body "..."`). The comment body must:
   - Open with `🔴 Triage`
   - List each Blocker gap (one line per gap: lens, description, what's needed to clear it)
   - Close with what must be recorded on this issue before it can build

   Example:

   ```
   🔴 Triage

   This issue has design gaps that block building:

   - **[architect / contradiction]** Recorded design is internally contradictory: "mirror ConfirmImportPage grouping" (comment #1) vs "flat list, no collection picker" (comment #3). Record the authoritative grouping decision before building.
   - **[design / scalability]** Flat 16-row list at realistic volume will produce a poor result vs the established grouped-card pattern in `Views/ConfirmImportPage.xaml`. Group under collection headers like ConfirmImportPage, or record a justified divergence.

   This is a durable async note — no reply needed now. Record the decision on this issue and re-run triage or solve-issue when ready.
   ```

2. **Recommended-label routing** — the label triage RECOMMENDS for this gap (returned in `issueStates`; the caller applies it):

   | Gap type | Recommended label |
   |---|---|
   | Any design/spec gap — architect `contradiction` / `not-buildable` / `missing-criteria` / `risky-design`, or any design-lens type (`scalability`, `pattern-inconsistency`, `missing-state`, `missing-affordance`, `accessibility`) | `needs design` |
   | A new dependency / non-design decision — architect `undeclared-dependency` | `needs decision` |

   Each parked issue carries exactly **one** *triage-recommended* label. When an issue has gaps of multiple types, select the single label by precedence: **`needs design`** (any design or spec gap — the common case) takes precedence; otherwise **`needs decision`** (a non-design decision with no design gap). Return that one label in `issueStates.label` (Step 7).

   `blocked` is NOT a triage recommendation: the calling skill `solve-milestone` computes it at loop time from the dependency graph (Step 7) — an issue is `blocked` when an issue it depends on is not yet merged. Triage returns the graph; the caller derives and applies `blocked` itself (and any transitive-dependent holds).

   `skills/setup/SKILL.md` Phase 4 is the source of truth for the label colors and descriptions the caller uses when applying these labels.

**triage does NOT apply labels, create branches, or open PRs.** It posts the comment and returns the recommended label per blocked issue in `issueStates` (Step 7). The calling skill (`solve-milestone` / `solve-issue`) applies that label using the apply-time label helper documented in `skills/setup/SKILL.md` Phase 4 (`gh label create --force` then `gh issue edit --add-label`), and leaves the issue open.

A Blocker **parks** the issue — triage posts the comment (Step 6) and returns the recommended label in `issueStates` (Step 7); the calling skill applies that label (via setup Phase 4's apply-time helper) and leaves the issue open. The loop continues with clean issues. This is a durable async handoff — never an interactive prompt.

### Step 7 — Return to the calling skill

Return to the invoking skill (e.g. `solve-milestone`, `solve-issue`) the following:

```
{
  dependencyGraph: {
    waves: [
      { wave: 1, issues: [A, B, C], parallel: true },
      { wave: 2, issues: [D], dependsOn: [A, B] },
      …
    ]
  },
  issueStates: {
    "<n>": { blockers: true | false, label: "needs design" | "needs decision" | null, advisories: ["<one-line advisory>", …] },
    …
  }
}
```

`blockers: true` means the issue has at least one Blocker gap and is parked. `label` is the triage-recommended park label (`"needs design"` or `"needs decision"`) when `blockers: true`; `null` when `blockers: false`. `blockers: false` means it is all-clear (Advisories are logged but not gating). The calling skill uses `issueStates` to decide which issues to build and which to hold, uses the `label` field to apply the park label via setup Phase 4's apply-time helper, and separately derives `blocked` (and any transitive-dependent holds) from `dependencyGraph`.

## Severity → effect

| Severity | Effect |
|---|---|
| **Blocker** | Parks the issue (triage comments + recommends the label; the caller applies it via setup Phase 4 and leaves it open); the loop continues with clean issues |
| **Advisory** | Logged in the gap table and output; not gating; build proceeds |

## Non-negotiables

- **Authors no code.** Never edits a source file, never creates a branch, never opens a PR.
- **Opens no PRs.** The triage phase is read-only except for posting issue comments — it applies no labels, creates no branches, and opens no PRs.
- **No interactive prompts.** Blocker comments are durable async handoffs on the originating issue — never a mid-run pause waiting for a human reply.
- **No fabricated findings.** Every gap cites its grounding (the exact recorded line, or `file:line` for a dependency). A claim that cannot be grounded in the actual artifact is emitted as a Blocker ("cannot verify X from the issue/code"), never as a confident guess. If an issue cannot be retrieved, STOP — do not fabricate a stand-in.
