---
name: triage
description: This skill should be used when the user invokes "/milestone-driver:triage <milestone-name | issue-number>", or asks to "triage the milestone/issue", "triage the milestone", "review for gaps", or "review this issue for gaps". Reviews issues for design gaps and dependency ordering before building — the Layer 0 pre-build phase. Authors no code; opens no PRs.
---

# triage — pre-build review phase

Review issues for design gaps and dependency ordering. Emit an all-clear or a gap table. Post a blocker summary on each affected issue. Return the validated dependency graph. **Authors nothing; opens no PRs.**

## Contents

[1 Profile](#step-1--read-the-profile) · [2 Gather](#step-2--gather-issues) · [2.5 Cache lookup](#step-25--cache-lookup-before-dispatching-agents) · [Resolve docs](#resolve-cited-project-docs-sections-once-per-issue-before-dispatch) · [Resolve citations](#resolve-cited-path-anchor-citations-once-per-issue-before-dispatch) · [3 Dispatch](#step-3--dispatch-triageagent-per-issue) · [3.5 Resolve](#step-35--resolve-blockers-before-they-park) · [4 Aggregate](#step-4--aggregate-findings) · [5 Output](#step-5--output-to-the-user) · [6 Comment](#step-6--comment-on-each-affected-issue-and-recommend-its-park-label) · [6.5 Cache write](#step-65--cache-write-best-effort) · [7 Return](#step-7--return-to-the-calling-skill)

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

Read the profile (`docs/profile-schema.md`). **Resolution (transitional READ only — triage performs no migration move):** `<repo>/.milestone-config/driver.json` first, else the legacy root `<repo>/milestone-driver.json`. Both present → `.milestone-config/driver.json` wins; no move, no overwrite, no deletion of the leftover. On the legacy layout, triage may surface a one-line note — "legacy profile detected — will migrate on the next build/setup". If neither file exists or a required Core key is missing, invoke `milestone-driver:setup`, then continue.

Extract:

| Key | Default |
|---|---|
| `triageAgent` | `milestone-driver:triage-reviewer` |
| `designReviewAgent` | `milestone-driver:design-reviewer` |
| `blockerResolverAgent` | `milestone-driver:blocker-resolver` |
| `uiSurfaceGlobs` | *(absent → no design-lens review)* |
| `sourceGlobs` | *(pass through to the agent brief in Step 3)* |
| `nonNegotiables` | *(pass through to the agent brief in Step 3)* |
| `domainSkills` | *(pass through to the agent brief in Step 3)* |
| `projectDocs` | `.project/` |

### Step 2 — Gather issues

**Batch mode** (argument is a milestone name):

1. Read the milestone description for the declared Wave/dependency order — the same source `solve-milestone` uses:

   ```
   gh api "repos/{owner}/{repo}/milestones" \
     --jq '.[] | select(.title=="<milestone-name>") | .description'
   ```

2. List all open issues in the milestone:

   ```
   gh issue list --milestone "<milestone-name>" --state open --json number,title,body,labels
   ```

3. For EACH issue number returned, fetch its comments (recorded design decisions / `design-cleared` notes) — `gh issue list` returns no comment bodies, so this per-issue call is required:

   ```
   gh issue view <n> --json comments --jq '.comments[].body'
   ```

**Single mode** (argument is an issue number) — fetch the one issue with its comments in one call:

```
gh issue view <n> --json number,title,body,labels,comments
```

Both modes end with the same inputs for Step 3: each issue's number, title, body, labels, AND its comments.

### Step 2.5 — Cache lookup (before dispatching agents)

The cache mechanics — path resolution, the change-signal key, and the batched GraphQL text — live in `${CLAUDE_PLUGIN_ROOT}/scripts/triage-cache.{sh,ps1}` (pwsh on Windows, bash elsewhere — same host selection as the two resolvers below). Do **not** re-derive them here. The script never runs `gh`: it prints the query for you to run, and parses the response you hand back. It never errors the run — an absent, unreadable, or invalid cache file is an **empty cache**, and every degraded path exits 0.

1. **Fetch the change signals.** `triage-cache.<sh|ps1> query keys <owner> <repo> <n>…` prints one batched, aliased GraphQL query covering every issue gathered in Step 2. Run it (`gh api graphql -f query="$(…)"`) and save the response — **keep that file for Step 6.5**, which recomputes the cache keys from it. Fall back to per-issue `gh issue view <n> --json …` calls only if the batch call fails — and, as item 3 does for `check-edges`, collect those results into the same `issue_<n>` alias shape the batch returns (`{"issue_<n>": {"issue": {"createdAt": …, "comments": {"totalCount": …}, "labels": {"nodes": [{"name": …}]}}}, …}`) and **save that assembled file**: `lookup` here and `write` at Step 6.5 must read the same one. If even the fallback produces no file, still pass its path at Step 6.5: `write` treats an absent response as fail-open (entries stored with no key, exit 0) and those issues re-triage next run. **Note:** `bodyLastEditedAt` is NOT a valid field for `gh issue view --json` — use `lastEditedAt` via GraphQL only, so an assembled fallback file omits it and `createdAt` supplies the timestamp on both legs.
2. **Partition.** `triage-cache.<sh|ps1> lookup <repo-root> <response.json>` prints TAB-separated records: `HIT<TAB><n>`; `MISS<TAB><n><TAB><reason>` (`no-entry`, `key-mismatch`, `no-live-key`); `EDGES<TAB><n>…`, the deduplicated union of every HIT candidate's cached `result.edges`; and `SUMMARY<TAB>hits=<h><TAB>misses=<m>`. A single `SKIP<TAB><reason>` record replaces the whole set when no cache information is available (`no-jq`, `bad-response`) — treat **every** issue as a MISS.
3. **Check the edges.** When the `EDGES` record carries at least one number, run `triage-cache.<sh|ps1> query edges <owner> <repo> <those numbers>` through `gh api graphql`, then `triage-cache.<sh|ps1> check-edges <repo-root> <response.json>`. Fall back to per-issue `gh issue view <n> --json state,stateReason` only when the batch query fails — collect those results into the same `issue_<n>` alias shape (`{"issue_<n>": {"issue": {"state": …, "stateReason": …}}, …}`) and hand that file to `check-edges`, so a failed batch costs extra fetches instead of re-triaging every cached issue. Each `MISS<TAB><n><TAB>stale-edge` it prints **downgrades that HIT to a MISS**; `SUMMARY<TAB>stale=<k>` closes the set. Its own `SKIP<TAB>bad-response` — reached only once the per-issue fallback has also failed — means the downgrade could not be computed; downgrade every HIT, because an unverifiable edge is the case this check exists for.

The partition contract those records implement:

| Result | Condition | Action |
|---|---|---|
| **HIT** | Cached entry exists AND `key` matches the live key AND no stale-edge condition (see below) | Reuse cached `result`; do NOT dispatch `triageAgent`; do NOT dispatch `designReviewAgent` |
| **MISS** | No entry OR key mismatch OR stale-edge condition | Proceed to Step 3 dispatch normally |

**Stale-edge states are run-scoped:** `check-edges` reads them from the response file you pass it, and nothing about them is ever written to the cache.

**Stale-edge invalidation rule (why a HIT can still be downgraded):** a dependency closed without merging would leave its dependents permanently blocked on a cached edge. `check-edges` is that rule — `state == "CLOSED"` with `stateReason != "COMPLETED"` forces re-triage.

Partition issues into **HIT set** (cache-reused) and **MISS set** (fresh dispatch needed). Carry both sets forward.

**Single mode:** cache lookup, key comparison, and the stale-edge invalidation check all apply identically for the one issue.

### Resolve cited project-docs sections (once per issue, before dispatch)

Resolve each issue's cited `.project/` sections **once, here in the triage skill**, for every issue in the **MISS set** (HIT issues skip dispatch). It is **additive grounding**: it changes no gate, no cap, and no existing step's logic — it only adds an input to the two dispatch briefs (Step 3).

1. **Source the docs root.** Use `projectDocs` already resolved at Step 1 (defaults to `.project/`). Do **not** re-resolve the profile here.
2. **Parse the cited anchors.** From each MISS issue's body + its acceptance criteria (gathered in Step 2), collect the `.project/<doc>#<section>` anchors the issue cites — `<doc>` is the path under the docs root, `<section>` is the heading text (e.g. `design-system.md#data-tables`).
3. **Pull a superset via the primitive.** For each cited anchor — plus its plausibly-relevant **sibling** sections — invoke `${CLAUDE_PLUGIN_ROOT}/scripts/read-doc-section.{sh,ps1}` (pwsh on Windows, bash elsewhere) once per section: `${CLAUDE_PLUGIN_ROOT}/scripts/read-doc-section.<sh|ps1> <doc-path> <anchor-text>`, where `<doc-path>` is the doc under the docs root and `<anchor-text>` is the heading text **without** leading `#`s. It prints **only** that section to stdout. **Bias toward over-inclusion** — **under-retrieval is the real risk** — but never inline a whole file. The reviewers keep their own `Read`/grep tools for any **additional** on-demand anchor.
4. **Feed the result into both dispatch briefs.** Collect the printed sections per MISS issue and pass the **same** resolved sections into BOTH the `triageAgent` and `designReviewAgent` briefs composed in Step 3 as **the resolved `.project/` sections**. Resolve once per issue, not once per reviewer.
5. **Resolve the prose contract (once per run).** Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` **once per run** — not once per issue, not once per reviewer — and pass its `## GitHub-facing prose`, `## When prose is the correct form`, `## Evidence slots`, and `## The two anti-criteria` sections into **BOTH** Step 3 briefs as **the resolved prose contract**. It governs each reviewer's returned `description` and `to_clear` lines — the text this skill renders verbatim into the `🔴 Triage` comment at Step 6 — and each agent's own `## Communication style` may specialize it but never replace it.

**Degradation (no error, ever):**
- **Absent `projectDocs`** → defaults to `.project/` (resolved at Step 1).
- **Absent `.project/` directory** (or no cited anchors on an issue) → **no-op** for that issue: dispatch proceeds with no project grounding and **no error**.
- **Missing/renamed cited anchor** → the primitive **fails loud** (non-zero exit, naming the anchor + file on stderr) so a drifted heading surfaces rather than returning silent empty grounding. Do not swallow it.
- **Absent `skills/output-style.md`** (missing, or unreadable) → **no-op**: both dispatches proceed with **no prose contract** and **no error**, leaving each reviewer's own `## Communication style` as its only prose rule.

### Resolve cited `path (anchor)` citations (once per issue, before dispatch)

Resolve each MISS issue's `path (anchor)` citations (`skills/citation-format.md`) **once here** — a HIT issue skips dispatch and makes **no** resolver call. Paths are repo-root-relative; no multi-base fallback.

1. **Extract by model judgment over the `path (anchor)` shape — never a regex.** Apply its span and position tests to the issue body + acceptance criteria: a parenthetical after a path is **not** automatically a citation. Both regex failure modes, measured on prose whose span closes before the parenthesis: `` `agents/triage-reviewer.md` (architect lens) `` exits 1 — a **false drift report**; `` `skills/setup/SKILL.md` (Phase 2) `` returns `PRIMARY 54` + `MATCH 197` — a **confident wrong answer**.
2. **Resolve, then feed BOTH briefs.** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-citation.{sh,ps1}` (pwsh on Windows, bash elsewhere) once per citation, with `<file-path> <anchor-text>` as arguments. Exit 0 prints a `PRIMARY` row then zero or more `MATCH` rows, TAB-delimited, file order. Pass those rows into **BOTH** Step 3 briefs as **the resolved citations** — once per issue, not once per reviewer — in the printed-output shape `read-doc-section`'s result uses above; no new format.

**Degradation:**
- **No `path (anchor)` citation on an issue** → **no-op**: no resolver call, no error.
- **A cited anchor not found**, or an unreadable file → `resolve-citation` **fails loud** (nonzero; anchor + file on stderr, stdout empty). Surface it; never swallow it.

### Step 3 — Dispatch `triageAgent` per issue

Dispatch the agent named in `triageAgent` (default `milestone-driver:triage-reviewer`) for each issue **in the MISS set only**. Dispatches are **parallelizable** — run them concurrently when the tool environment supports it. **The brief MUST also carry this scratch-hygiene rule:** write scratch only under a path named for that issue or that agent, never the shared scratchpad directory, and report what a probe printed rather than writing a probe file to read back later.

**Brief each agent with:**

- The issue: number, title, body, acceptance criteria, labels.
- Its recorded design decisions: all comments and any `design-cleared` notes fetched in Step 2.
- The milestone description (the declared Wave/dependency order) — batch mode only; pass an empty string in single mode.
- The profile: `sourceGlobs`, `uiSurfaceGlobs`, `nonNegotiables`, `domainSkills` (one step — after the framework's own docs, before repo patterns — in the agent's research path for verifying a found convention is a genuine framework idiom; omit when absent from the profile).
- The resolved `.project/` sections for this issue — omit when that block was a no-op for this issue.
- The resolved prose contract (the `skills/output-style.md` sections resolved once per run); omit when that resolution was a no-op.
- The resolved citations for this issue; omit when that block was a no-op.
- `citationFormatPath` — the absolute path of `${CLAUDE_PLUGIN_ROOT}/skills/citation-format.md`; always passed, never omitted.
- The repo root — it bounds the agent's read scope; a re-triage running inside an issue worktree names that worktree instead.

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
    to_clear: <the ONE decision or artifact the human must record, as an instruction they can act on without reading the rest of the block, plus its evidence reference (per `citationFormatPath`) when one exists — structural, not a word count; two decisions here is two gaps (skills/output-style.md, "to_clear field" row)>
  - … (or "none")
```

For each **MISS** issue whose `triageAgent` return carries `NEEDS_DESIGN_REVIEW: yes`, dispatch `designReviewAgent` (default `milestone-driver:design-reviewer`). **The brief MUST also carry the same scratch-hygiene rule as above.**

**Brief the design agent with:**

- The issue: number, title, body, acceptance criteria.
- Its recorded design decisions: all comments and any `design-cleared` notes.
- Pointers to existing UI surfaces the issue neighbors — via `uiSurfaceGlobs` from the profile.
- The profile: `uiSurfaceGlobs`, `domainSkills` (one step — after the framework's own docs, before repo patterns — in the agent's research path for verifying a found pattern is a genuine framework idiom; omit when absent from the profile).
- The resolved `.project/` sections, prose contract, and citations — the **same** ones passed to the `triageAgent` above; omit each when its block was a no-op. Plus `citationFormatPath`, never omitted.
- The repo root — it bounds the agent's read scope; a re-triage running inside an issue worktree names that worktree instead.

**The design agent returns:**

```
ISSUE: <n>
GAPS:
  - lens: design
    severity: Blocker | Advisory
    type: spec-insufficiency | scalability | pattern-inconsistency | missing-state | missing-affordance | accessibility
    description: <one line>
    to_clear: <the ONE suggested resolution or reference pattern (e.g. "group under collection headers like ConfirmImportPage"), as an instruction the human can act on without reading the rest of the block, plus its evidence reference (per `citationFormatPath`) when one exists — structural, not a word count; two resolutions here is two gaps (skills/output-style.md, "to_clear field" row)>
  - … (or "none")
```

### Step 3.5 — Resolve Blockers before they park

A MISS issue with ≥1 `severity: Blocker` gap → read `${CLAUDE_PLUGIN_ROOT}/skills/triage/blocker-resolver-dispatch.md` and run it. Nothing else reaches it.

### Step 4 — Aggregate findings

**Merge cached and fresh results first.** Combine the HIT set's cached `result` objects (Step 2.5) with the fresh agent returns (Step 3) into one unified result set covering all issues.

- HIT issues: the cached `result` carries `blockers`, `label`, `advisories`, `risk`, and `edges` — use them directly. Risk comes from the cached `risk` value (the cache key's label component guarantees override labels have not changed).
- MISS issues: use the fresh agent returns as normal.

Collect all GAPS across all results for each issue. Aggregate by `lens` / `severity` / `description` / `to_clear` — the `type` tokens differ between the two agents; match on the other fields, not `type`.

#### Risk classification

After aggregating gaps for each issue, classify it as **`light`** or **`heavy`** (default **`heavy`** when inconclusive). Store the result in `issueStates[n].risk` (returned at Step 7).

**Operator override labels (checked first).** A `risk:heavy` or `risk:light` label sets the profile directly — skip the rubric below. When **both** are present, **`risk:heavy` wins**.

**Observable rubric (runs only when no override label is present, over the pre-resolution gap set).**

**Classify as `heavy` when ANY of the following is true:**
- A triage gap of type `contradiction` or `not-buildable` is present.
- The `triageAgent` adds an undeclared `DEPENDS_ON` edge (one not declared in the milestone's Wave order).
- `NEEDS_DESIGN_REVIEW: yes` AND the issue names or touches a UI surface.
- The issue body names a shared interface, schema, auth path, or payment path.
- Classification is genuinely ambiguous (default heavy).

**Classify as `light`** only when ALL of the following hold:
- None of the `heavy` conditions above is triggered.
- All triage criteria are clean (no Blockers from either lens).
- The issue body names no shared interface, schema, auth path, or payment path.
- The `triageAgent` adds no undeclared `DEPENDS_ON` edges.
- NOT (`NEEDS_DESIGN_REVIEW: yes` AND UI surface).

Build the **validated dependency graph** from all `DEPENDS_ON` edges across the merged result set:

- Preserve the per-issue edges exactly as returned by each `triageAgent` (before any wave aggregation) — plus the `edges` carried in each HIT issue's cached `result` — these together form the `edges` map in the returned `dependencyGraph` (Step 7).
- Rebuild `dependencyGraph.waves` from the merged per-issue `edges` map plus the milestone's declared Wave order, using a pure in-context topological sort.
- Where an agent finds an undeclared dependency, add it to the graph (it surfaces as a Blocker in the gap table).
- Produce the Wave-ordered graph for output AND maintain the raw per-issue `edges` map alongside it.

### Step 5 — Output to the user

Open every output block with the cache split so reuse is never silent. Example:

```
Triage: 4 reused (cache), 2 fresh; 3 blockers resolved, 1 needs human
```

(Substitute the actual counts. All HIT: `Triage: N reused (cache), 0 fresh`. All MISS: `Triage: 0 reused (cache), N fresh`.) Append the resolve split only when Step 3.5 ran.

When the Step 6.5 cache write was **skipped or failed this run** (jq absent on the Bash path, or any write error on either path), append a single concise clause to that same line:

```
Triage: 4 reused (cache), 2 fresh; cache write skipped this run
```

Show the clause **only when a skip/failure actually occurred**.

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

Include the Wave-ordered dependency graph after the table — even when gaps are present, it still shows which clean issues can build immediately.

### Step 6 — Comment on each affected issue and recommend its park label

For every **freshly-triaged** (MISS) issue with surviving **Blocker** gaps or a Step 3.5 `RESOLVED` verdict:

> **Cache-hit Blocker issues do NOT receive a duplicate `🔴 Triage` comment.** Their original comment from the first run persists on the issue.
>
> **Previously-blockered issues that get a MISS always post a fresh comment.** When a cached entry shows `blockers: true` but the cache is invalidated, the re-triage is treated as a full MISS. If the result still has Blockers, post a fresh `🔴 Triage` comment — do NOT guard on the stale cached `blockers: true` to skip posting.
>
> **Accepted trade-off:** the `🔴 Triage` comment is posted AFTER the cache key is computed. Posting it increments the issue's comment count, self-invalidating the entry on the next run — a blockered issue re-triages fresh, which is desirable. Do NOT add a dedup guard for it; the `🟢 Resolved` comment has its own (`skills/triage/blocker-resolver-dispatch.md (Unparking)`).

For each qualifying MISS issue:

1. **Post a `🟢 Resolved` comment** on ≥1 Step 3.5 `RESOLVED`, in the shape at `skills/output-style.md (Resolved comment)`.

2. **Post a triage comment** (`gh issue comment <n> --body "..."`) in the triage-comment shape (`skills/output-style.md`) on ≥1 surviving Blocker. The comment body must:
   - Open with `🔴 Triage` — byte-fixed, parsed downstream at `skills/solve-milestone/SKILL.md (Issues parked)` and probed at `skills/solve-milestone/parallel-waves.md (the probe found a park label)`. Only what FOLLOWS the opener is structured here.
   - Render the surviving Blocker gaps as a **structured table**, one row per gap — lens/type · description · **evidence** · what clears it (the agent's `to_clear`) — not as prose bullets. A row with an empty evidence cell is an unfilled slot, not a shorter row.
   - Close with the durable-async instruction, verbatim: "This is a durable async note — no reply needed now. Record the decision on this issue — run `/milestone-feeder:remediate <n>` to apply these findings, then clear the label — or re-run triage or solve-issue when ready." That line stays **prose** because it qualifies every row at once and so has no cell to live in (`skills/output-style.md`, `## When prose is the correct form`), and it states what must be recorded before this issue can build. Name the remediate verb unconditionally: it reads as an optional tool, so do NOT probe whether the feeder plugin is installed, and do NOT run it from here (`skills/triage/SKILL.md#Non-negotiables`).

   Example:

   ```
   🔴 Triage

   | Lens / type | Blocker | Evidence | What clears it |
   |---|---|---|---|
   | architect / contradiction | Recorded design is internally contradictory. | "mirror ConfirmImportPage grouping" (comment #1) vs "flat list, no collection picker" (comment #3) | Record the authoritative grouping decision before building. |
   | design / scalability | Flat 16-row list at realistic volume will produce a poor result. | Established grouped-card pattern at `Views/ConfirmImportPage.xaml` | Group under collection headers like ConfirmImportPage, or record a justified divergence. |

   This is a durable async note — no reply needed now. Record the decision on this issue — run `/milestone-feeder:remediate <n>` to apply these findings, then clear the label — or re-run triage or solve-issue when ready.
   ```

3. **Recommended-label routing** — the label triage RECOMMENDS for this gap (returned in `issueStates`; the caller applies it):

   | Gap type | Recommended label |
   |---|---|
   | Any design/spec gap — architect `contradiction` / `not-buildable` / `missing-criteria` / `risky-design`, or any design-lens type (`spec-insufficiency`, `scalability`, `pattern-inconsistency`, `missing-state`, `missing-affordance`, `accessibility`) | `needs design` |
   | A new dependency / non-design decision — architect `undeclared-dependency` | `needs decision` |

   Each parked issue carries exactly **one** *triage-recommended* label. With gaps of multiple types, select by precedence: **`needs design`** (any design or spec gap) wins; otherwise **`needs decision`**. Return that one label in `issueStates.label` (Step 7).

   `blocked` is NOT a triage recommendation: `solve-milestone` computes it at loop time from the dependency graph (Step 7) — an issue is `blocked` when an issue it depends on is not yet merged. Triage returns the graph; the caller derives and applies `blocked` itself.

   `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` Phase 4 is the source of truth for the label colors and descriptions the caller uses.

**triage does NOT apply labels, create branches, or open PRs.** It posts the comment and returns the recommended label per blocked issue in `issueStates` (Step 7). The calling skill applies that label using the apply-time helper documented in `skills/setup/SKILL.md` Phase 4 (`gh label create --force` then `gh issue edit --add-label`), and leaves the issue open.

### Step 6.5 — Cache write (best-effort)

After posting Step 6's comments, write/update entries for every **freshly-triaged** (MISS) issue. This step is **best-effort: a write failure logs a warning and does not error the triage run.**

1. **Build the entries object.** One JSON object keyed by issue number; per freshly-triaged issue: `triaged_at` (this run's ISO 8601 timestamp) and `result` from the Step 4 aggregate. **No `key` field** — the script stamps it (item 2). The `result` object carries: `blockers` (boolean — `false` when Step 3.5 cleared them all; resolution text is never cached), `label` (`"needs design"` / `"needs decision"` / `null`), `advisories` (array of one-line strings), `risk` (`"light"` / `"heavy"`), and `edges` (the `dependencyGraph.edges["<n>"]` array for this issue).
2. **Hand it to the script.** `${CLAUDE_PLUGIN_ROOT}/scripts/triage-cache.<sh|ps1> write <repo-root> <entries.json> <response.json>` stamps each entry's change-signal key from that response using the same definition `lookup` compares against, re-reads the cache under the same resolution and degradation rules as Step 2.5, merges these entries over it one entry at a time, creates `.milestone-config/`, self-heals the committed `.milestone-config/.gitignore` so the cache is git-invisible from the first write, writes the canonical `.milestone-config/triage-cache.json` atomically, and removes the stale legacy root cache. **Why re-read rather than reuse the Step 2.5 parse:** it picks up a concurrent write instead of overwriting it. `<response.json>` is the **saved Step 2.5 `query keys` response, never a fresh fetch and never the `query edges` one**: that file predates the Blocker comments Step 6 just posted, and recomputing from it stores the pre-comment key — so the next run re-triages a blockered issue whose comment count has since changed ("Accepted trade-off" in Step 6). An absent or unparseable response is fail-open: the entries are written as supplied and the issue re-triages next run.
3. **Read the one record it prints.** `OK<TAB><path>` when the cache was written; `SKIP<TAB><reason>` (`no-jq`, `bad-entries`, `mkdir-failed`, `write-failed`) when it was not. It **always exits 0** — a `SKIP` sets the "cache write skipped this run" condition Step 5 reports, and never aborts the run.

**Single mode:** cache write applies identically — write the single issue's entry.

### Step 7 — Return to the calling skill

Return to the invoking skill (e.g. `solve-milestone`, `solve-issue`) the following:

```
{
  dependencyGraph: {
    waves: [
      { wave: 1, issues: [A, B, C], parallel: true },
      { wave: 2, issues: [D], dependsOn: [A, B] },
      …
    ],
    edges: {
      "<n>": [<issue numbers this issue directly DEPENDS_ON>],
      …
    }
  },
  issueStates: {
    // **`issueStates` covers all issues** — both cache-HIT issues (populated from cached `result` via the Step 4 merge) and freshly-triaged MISS issues. Do not return only MISS-derived results.
    "<n>": { blockers: true | false, label: "needs design" | "needs decision" | null, clearLabel: true | false, advisories: ["<one-line advisory>", …], risk: "light" | "heavy" },
    …
  }
}
```

`dependencyGraph.edges` is the per-issue map: each key is an issue number (as a string) and its value is the array of issue numbers that issue **directly depends on** — preserved from the `triageAgent` `DEPENDS_ON` returns before wave aggregation. An issue with no dependencies has an empty array or is absent. The calling skill uses `edges["<n>"]` for per-issue buildability checks, not wave-level `dependsOn`, which is shared across all wave siblings.

`blockers: true` means the issue has at least one Blocker gap and is parked. `label` is the triage-recommended park label (`"needs design"` or `"needs decision"`) when `blockers: true`; `null` when `blockers: false`, which means all-clear (Advisories are logged but not gating). The calling skill uses `issueStates` to decide which issues to build and which to hold, the `label` field to apply the park label via setup Phase 4's apply-time helper, `clearLabel` to remove one (`skills/triage/blocker-resolver-dispatch.md (Unparking)`), and separately derives `blocked` (and any transitive-dependent holds) from `dependencyGraph.edges`.

**`clearLabel` defaults to `false` when a return omits it** — only an explicit `true` removes a label, so an absent field is never an instruction to remove one.

`risk` is the per-issue classification computed in Step 4: `"light"` or `"heavy"`, defaulting to `"heavy"` when inconclusive. `solve-issue` reads `issueStates["<n>"].risk` to resolve the build profile for that issue.

## Severity → effect

| Severity | Effect |
|---|---|
| **Blocker** | Parks the issue (triage comments + recommends the label; the caller applies it via setup Phase 4 and leaves it open); the loop continues with clean issues |
| **Advisory** | Logged in the gap table and output; not gating; build proceeds |

## Output style

Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` — the single source of truth for this plugin's output contract. Its `## Terminal output` section governs what this skill prints; its `## GitHub-facing prose`, `## When prose is the correct form`, and `## Evidence slots` sections govern the `🔴 Triage` comment this skill posts (Step 6). The two surfaces are distinct — the terminal rules never reach GitHub.

Read `${CLAUDE_PLUGIN_ROOT}/skills/citation-format.md` — the one format every citation in those slots takes.

## Non-negotiables

- **Authors no code, opens no PRs.** The triage phase is read-only except for posting issue comments: it never edits a source file, creates no branch, opens no PR, applies no label, and moves no file. Triage **performs no migration move either** — it does not `git mv` a legacy root `milestone-driver.json` to `.milestone-config/driver.json`; the relocation is owned by `setup` and `solve-issue` (the commands with a commit path; `solve-milestone` migrates via its dispatched build). Triage does the transitional READ only (Step 1).
- **No interactive prompts.** Blocker comments are durable async handoffs on the originating issue — never a mid-run pause waiting for a human reply.
- **No fabricated findings.** Every gap cites its grounding (the exact recorded line, or `file:line` for a dependency). A claim that cannot be grounded in the actual artifact is emitted as a Blocker ("cannot verify X from the issue/code"), never as a confident guess. If an issue cannot be retrieved, STOP — do not fabricate a stand-in.
