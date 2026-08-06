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

Read the profile (see the plugin's `docs/profile-schema.md`). **Resolution (transitional READ only — triage performs no migration move):** read `<repo>/.milestone-config/driver.json` first; if absent, fall back to the legacy root `<repo>/milestone-driver.json`. When both files exist, `.milestone-config/driver.json` wins — no move, no overwrite, no deletion of the leftover root file. Triage authors no code, edits no source, and opens no PRs, so it **does not** perform the working-tree `git mv` — the relocation is owned by `setup` and `solve-issue` (the commands with a commit path; `solve-milestone` migrates via its dispatched build). On detecting the legacy layout (root `milestone-driver.json` present and `.milestone-config/driver.json` absent), triage may surface a one-line note — "legacy profile detected — will migrate on the next build/setup" — but does **not** move the file. The transitional READ above covers the gap until a building command performs the move. If neither file exists or a required Core key is missing, invoke `milestone-driver:setup` to bootstrap it, then continue.

Extract:

| Key | Default |
|---|---|
| `triageAgent` | `milestone-driver:triage-reviewer` |
| `designReviewAgent` | `milestone-driver:design-reviewer` |
| `uiSurfaceGlobs` | *(absent → no design-lens review)* |
| `sourceGlobs` | *(pass through to the agent brief in Step 3)* |
| `nonNegotiables` | *(pass through to the agent brief in Step 3)* |
| `domainSkills` | *(pass through to the agent brief in Step 3)* |
| `projectDocs` | `.project/` |

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

### Step 2.5 — Cache lookup (before dispatching agents)

The cache mechanics — path resolution, the change-signal key, and the batched GraphQL text — live in `${CLAUDE_PLUGIN_ROOT}/scripts/triage-cache.{sh,ps1}` (pwsh on Windows, bash elsewhere — same host selection as the two resolvers invoked below). Do **not** re-derive them here. The script never runs `gh`: it prints the query for you to run, and parses the response you hand back. It never errors the run — an absent, unreadable, or invalid cache file is an **empty cache**, and every degraded path exits 0.

1. **Fetch the change signals.** `triage-cache.<sh|ps1> query keys <owner> <repo> <n>…` prints one batched, aliased GraphQL query covering every issue gathered in Step 2 — one round-trip, not one per issue. Run it (`gh api graphql -f query="$(…)"`) and save the response. Fall back to per-issue `gh issue view <n> --json …` calls only if the batch call fails (graceful degradation). **Note:** `bodyLastEditedAt` is NOT a valid field for `gh issue view --json` (verified 2026-06-11) — use `lastEditedAt` via GraphQL only.
2. **Partition.** `triage-cache.<sh|ps1> lookup <repo-root> <response.json>` prints TAB-separated records: `HIT<TAB><n>`; `MISS<TAB><n><TAB><reason>` (`no-entry`, `key-mismatch`, `no-live-key`); `EDGES<TAB><n>…`, the deduplicated union of every HIT candidate's cached `result.edges`; and `SUMMARY<TAB>hits=<h><TAB>misses=<m>`. A single `SKIP<TAB><reason>` record replaces the whole set when no cache information is available (`no-jq`, `bad-response`) — treat **every** issue as a MISS.
3. **Check the edges.** When the `EDGES` record carries at least one number, run `triage-cache.<sh|ps1> query edges <owner> <repo> <those numbers>` through `gh api graphql`, then `triage-cache.<sh|ps1> check-edges <repo-root> <response.json>`. Fall back to per-issue `gh issue view <n> --json state,stateReason` only when the batch query fails, exactly as before — collect those per-issue results into the same `issue_<n>` alias shape the batch query returns (`{"issue_<n>": {"issue": {"state": …, "stateReason": …}}, …}`) and hand that file to `check-edges`, so a failed batch costs extra fetches instead of re-triaging every cached issue. Each `MISS<TAB><n><TAB>stale-edge` it prints **downgrades that HIT to a MISS**; `SUMMARY<TAB>stale=<k>` closes the set. Its own `SKIP<TAB>bad-response` — reached only once the per-issue fallback has also failed to produce a response — means the downgrade could not be computed; downgrade every HIT, because an unverifiable edge is the case this check exists for.

The partition contract those records implement:

| Result | Condition | Action |
|---|---|---|
| **HIT** | Cached entry exists AND `key` matches the live key AND no stale-edge condition (see below) | Reuse cached `result`; do NOT dispatch `triageAgent`; do NOT dispatch `designReviewAgent` |
| **MISS** | No entry OR key mismatch OR stale-edge condition | Proceed to Step 3 dispatch normally |

**Stale-edge memo (why the union, not per candidate):** the union is fetched once per run, so an issue number referenced by several HIT candidates costs one fetch, not one per candidate — a pass over N cached issues sharing M distinct dependencies makes M fetches, not up to N×M. The fetched states are run-scoped: `check-edges` reads them from the response file you pass it, and nothing about them is ever written to the cache.

**Stale-edge invalidation rule (why a HIT can still be downgraded):** a dependency closed without merging (e.g. abandoned) leaves its dependents permanently blocked on a cached edge claiming they are blocked by an issue nobody will merge. `check-edges` is that rule — `state == "CLOSED"` with `stateReason != "COMPLETED"` forces re-triage. The rule is unchanged; only where the values come from has moved.

**Risk staleness corollary (Fix 3):** A HIT returns cached `risk` only while its edge references remain valid. Any stale-edge condition (the closed-without-merge check above) forces a MISS, which causes `risk` to be re-derived from live data along with the edges. When the HIT is clean (no stale edges), the cached `risk` value is authoritative.

Partition issues into **HIT set** (cache-reused) and **MISS set** (fresh dispatch needed). Carry both sets forward.

**Single mode:** cache lookup, key comparison, and the stale-edge invalidation check all apply identically for the one issue. The memo is unaffected: with exactly one issue in the run, the union above has at most as many entries as that one issue's own `edges` array, so the memo receives at most one lookup per referenced dependency and is never consulted a second time. (A single issue with no edges makes the stale-edge check vacuous — it passes trivially.)

### Resolve cited project-docs sections (once per issue, before dispatch)

Resolve each issue's cited `.project/` sections **once, here in the triage skill** — so the `triageAgent` and the `designReviewAgent` receive the grounding text in their briefs rather than each reviewer re-reading whole docs. This block runs after Step 2.5's cache split and **before ### Step 3 — Dispatch `triageAgent` per issue**, for every issue in the **MISS set** (HIT issues skip dispatch entirely, so they need no resolution). It is **additive grounding**: it changes no gate, no cap, no existing step's logic, the cache logic, or the five-criteria assessment — it only adds an input to the two dispatch briefs (Step 3). This is an un-numbered headed block (not a numbered Step) so the integer Step ordinals that later steps cross-reference (Step 3 / 4 / 6 / 6.5 / 7) are unchanged. (Mirrors the same block in `skills/solve-issue/SKILL.md` — "Resolve cited project-docs sections (once, before dispatch)" — for consistency across the two skills.)

1. **Source the docs root.** Use `projectDocs` already resolved at Step 1 (defaults to `.project/` when the key is absent). Do **not** re-resolve the profile here.
2. **Parse the cited anchors.** From each MISS issue's body + its acceptance criteria (gathered in Step 2), collect the `.project/<doc>#<section>` anchors the issue cites — `<doc>` is the path under the docs root, `<section>` is the heading text (an anchor like `design-system.md#data-tables`).
3. **Pull a superset via the primitive.** For each cited anchor — plus its plausibly-relevant **sibling** sections — invoke the retrieval primitive `${CLAUDE_PLUGIN_ROOT}/scripts/read-doc-section.{sh,ps1}` (pwsh on Windows, bash elsewhere — same host selection as `${CLAUDE_PLUGIN_ROOT}/scripts/ci-preflight-steps.{sh,ps1}`) once per section: `${CLAUDE_PLUGIN_ROOT}/scripts/read-doc-section.<sh|ps1> <doc-path> <anchor-text>`, where `<doc-path>` is the doc under the docs root and `<anchor-text>` is the heading text **without** leading `#`s. It prints **only** that section to stdout. **Bias toward over-inclusion**: pull the cited sections and their siblings as a superset rather than the minimum, because **under-retrieval is the real risk**. The reviewers keep their own `Read`/grep tools for any **additional** on-demand anchor, so over-inclusion here never under-grounds a brief — but it also must never degrade into whole-file inlining (the do-NOT-do ceiling). Resolve **once per issue**; do **not** have the reviewers re-read whole files.
4. **Feed the result into both dispatch briefs.** Collect the printed sections for each MISS issue and pass the **same** resolved sections into BOTH the `triageAgent` brief and the `designReviewAgent` brief composed in Step 3 (below) as **the resolved `.project/` sections**. Resolve once per issue, not once per reviewer.
5. **Resolve the prose contract (once per run).** Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` **once per run** — not once per issue and not once per reviewer, mirroring the resolve-once posture above — and pass its `## GitHub-facing prose`, `## When prose is the correct form`, `## Evidence slots`, and `## The two anti-criteria` sections into **BOTH** the `triageAgent` brief and the `designReviewAgent` brief composed in Step 3 as **the resolved prose contract**. It governs each reviewer's returned `description` and `to_clear` lines — the text this skill renders verbatim into the `🔴 Triage` comment it posts in Step 6 — and each agent's own `## Communication style` may specialize it but never replace it.

**Degradation (no error, ever):**
- **Absent `projectDocs`** → defaults to `.project/` (resolved at Step 1).
- **Absent `.project/` directory** (or no cited anchors on an issue) → this block is a **no-op** for that issue: dispatch proceeds with no project grounding and **no error** (skipped cleanly when absent, exactly like the cache degradation in Step 2.5).
- **Missing/renamed cited anchor** → the primitive **fails loud** (non-zero exit, naming the anchor + file on stderr) so a drifted heading surfaces rather than returning silent empty grounding. Treat the loud failure as a signal that a cited anchor drifted — do not swallow it.
- **Absent `skills/output-style.md`** (the file is missing, or unreadable) → **no-op**: both dispatches proceed with **no prose contract** in their briefs and **no error**, leaving each reviewer's own `## Communication style` as its only prose rule. This mirrors the absent-`.project/` no-op branch above, **not** the fail-loud missing-anchor branch — the contract is additive grounding that no issue cites by name, so it never fails loud.
- **No `path (anchor)` citation on an issue** → the block below is a **no-op** for it: no resolver call, no error.
- **A cited anchor not found**, or an unreadable file → `resolve-citation` **fails loud** (nonzero; anchor + file on stderr, stdout empty). Surface it; never swallow it.

### Resolve cited `path (anchor)` citations (once per issue, before dispatch)

Resolve each MISS issue's `path (anchor)` citations (`skills/citation-format.md`) **once here** — a HIT issue skips dispatch and makes **no** resolver call. Paths are repo-root-relative; no multi-base fallback.

1. **Extract by model judgment over the `path (anchor)` shape — never a regex.** Apply its span and position tests to the issue body + acceptance criteria: a parenthetical after a path is **not** automatically a citation. Both regex failure modes, measured on prose whose span closes before the parenthesis: `` `agents/triage-reviewer.md` (architect lens) `` (`docs/superpowers/plans/2026-06-01-proactive-triage.md § New agent contract — `agents/triage-reviewer.md` (architect lens)`) exits 1 — a **false drift report**; `` `skills/setup/SKILL.md` (Phase 2) `` (`docs/profile-schema.md (each built issue opens its own PR)`) returns `PRIMARY 51` + `MATCH 196` — a **confident wrong answer**.
2. **Resolve, then feed BOTH briefs.** Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-citation.{sh,ps1}` (pwsh on Windows, bash elsewhere, as above) once per citation, with `<file-path> <anchor-text>` as arguments. Exit 0 prints a `PRIMARY` row then zero or more `MATCH` rows, TAB-delimited, file order. Pass those rows into **BOTH** Step 3 briefs (`triageAgent`, `designReviewAgent`) as **the resolved citations** — once per issue, not once per reviewer — in the printed-output shape `read-doc-section`'s result uses above; no new format.

### Step 3 — Dispatch `triageAgent` per issue

Dispatch the agent named in `triageAgent` (default `milestone-driver:triage-reviewer`) for each issue **in the MISS set only** (HIT issues are not re-dispatched). Dispatches are **parallelizable** — run them concurrently when the tool environment supports it. **The brief MUST also carry this scratch-hygiene rule:** write scratch only under a path named for that issue or that agent, never the shared scratchpad directory, and report what a probe printed rather than writing a probe file to read back later.

**Brief each agent with:**

- The issue: number, title, body, acceptance criteria, labels.
- Its recorded design decisions: all comments and any `design-cleared` notes fetched in Step 2.
- The milestone description (the declared Wave/dependency order) — batch mode only; pass an empty string in single mode.
- The profile: `sourceGlobs`, `uiSurfaceGlobs`, `nonNegotiables`, `domainSkills` (one step — after the framework's own docs, before repo patterns — in the agent's research path for verifying a found convention is a genuine framework idiom; omit when absent from the profile).
- The resolved `.project/` sections for this issue (from "Resolve cited project-docs sections (once per issue, before dispatch)" above — omit this input when that block was a no-op for this issue).
- The resolved prose contract (the `skills/output-style.md` sections resolved once per run in that same block) — the GitHub-facing prose rules and evidence-slot shapes governing the agent's returned `description` and `to_clear` lines; omit when that resolution was a no-op.
- The resolved citations for this issue (from the `path (anchor)` block above; omit when it was a no-op).

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
    to_clear: <the ONE decision or artifact the human must record, as an instruction they can act on without reading the rest of the block, plus its evidence reference (per skills/citation-format.md) when one exists — structural, not a word count; two decisions here is two gaps (skills/output-style.md, "to_clear field" row)>
  - … (or "none")
```

For each **MISS** issue whose `triageAgent` return carries `NEEDS_DESIGN_REVIEW: yes`, dispatch `designReviewAgent` (default `milestone-driver:design-reviewer`). HIT issues are excluded — their `designReviewAgent` dispatch was already done on the prior run; see Step 2.5 HIT table. **The brief MUST also carry this scratch-hygiene rule:** write scratch only under a path named for that issue or that agent, never the shared scratchpad directory, and report what a probe printed rather than writing a probe file to read back later.

**Brief the design agent with:**

- The issue: number, title, body, acceptance criteria.
- Its recorded design decisions: all comments and any `design-cleared` notes.
- Pointers to existing UI surfaces the issue neighbors — via `uiSurfaceGlobs` from the profile.
- The profile: `uiSurfaceGlobs`, `domainSkills` (one step — after the framework's own docs, before repo patterns — in the agent's research path for verifying a found pattern is a genuine framework idiom; omit when absent from the profile).
- The resolved `.project/` sections for this issue — the **same** sections resolved once and passed to the `triageAgent` above (from "Resolve cited project-docs sections (once per issue, before dispatch)"; omit when that block was a no-op for this issue).
- The resolved prose contract — the **same** `skills/output-style.md` sections resolved once per run and passed to the `triageAgent` above, governing this agent's returned `description` and `to_clear` lines; omit when that resolution was a no-op.
- The resolved citations — the **same** rows passed to the `triageAgent` above; omit when it was a no-op.

**The design agent returns:**

```
ISSUE: <n>
GAPS:
  - lens: design
    severity: Blocker | Advisory
    type: spec-insufficiency | scalability | pattern-inconsistency | missing-state | missing-affordance | accessibility
    description: <one line>
    to_clear: <the ONE suggested resolution or reference pattern (e.g. "group under collection headers like ConfirmImportPage"), as an instruction the human can act on without reading the rest of the block, plus its evidence reference (per skills/citation-format.md) when one exists — structural, not a word count; two resolutions here is two gaps (skills/output-style.md, "to_clear field" row)>
  - … (or "none")
```

### Step 4 — Aggregate findings

**Merge cached and fresh results first.** Combine the HIT set's cached `result` objects (from Step 2.5) with the fresh agent returns (from Step 3) into one unified result set covering all issues.

- For HIT issues: the cached `result` carries `blockers`, `label`, `advisories`, `risk`, and `edges` — use them directly. Risk classification for HIT issues comes from the cached `risk` value (the label component of the cache key guarantees that override labels have not changed since the entry was written).
- For MISS issues: use the fresh agent returns as normal.

Collect all GAPS across all results for each issue. Aggregate by `lens` / `severity` / `description` / `to_clear` — the `type` tokens differ between the two agents by design; match on the other fields, not `type`.

#### Risk classification

After aggregating gaps for each issue, classify it as **`light`** or **`heavy`** (default **`heavy`** when inconclusive). Store the result in `issueStates[n].risk` (returned at Step 7).

**Operator override labels (checked first).** If the issue carries a `risk:heavy` or `risk:light` label, that label sets the profile directly — skip the observable rubric below. When **both** labels are present, **`risk:heavy` wins** (safety-first).

**Observable rubric (runs only when no override label is present).** All inputs are available at Step 4: gap types from `triageAgent`, the validated `DEPENDS_ON` edges, the `NEEDS_DESIGN_REVIEW` signal, and the issue body.

**Classify as `heavy` when ANY of the following is true:**
- A triage gap of type `contradiction` or `not-buildable` is present.
- The `triageAgent` adds an undeclared `DEPENDS_ON` edge (i.e. an edge not declared in the milestone's Wave order).
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

- Preserve the per-issue edges exactly as returned by each `triageAgent` (before any wave aggregation) — plus the `edges` carried in each HIT issue's cached `result` — these together form the `edges` map in the returned `dependencyGraph` (see Step 7).
- Merge all edges (cached + fresh) with the milestone's declared Wave order. Rebuild `dependencyGraph.waves` from the merged per-issue `edges` map plus the milestone's declared Wave order using a pure in-context topological sort — no additional agent cost.
- Where an agent finds an undeclared dependency, add it to the graph (and it surfaces as a Blocker in the gap table).
- Produce the Wave-ordered graph for output AND maintain the raw per-issue `edges` map alongside it — the calling skill uses `edges` for per-issue buildability checks; `waves` gives ordering and presentation.

### Step 5 — Output to the user

Open every output block with the cache split so reuse is never silent. Example:

```
Triage: 4 reused (cache), 2 fresh
```

(Substitute the actual counts. When all issues are HIT: `Triage: N reused (cache), 0 fresh`. When all are MISS: `Triage: 0 reused (cache), N fresh`.)

When the Step 6.5 cache write was **skipped or failed this run** (jq absent on the Bash path, or any write error on either path — see Step 6.5), append a single concise clause to that same line so the operator knows the cache did not persist this run:

```
Triage: 4 reused (cache), 2 fresh; cache write skipped this run
```

Show the clause **only when a skip/failure actually occurred**. On a successful write, emit the plain "N reused, M fresh" line with no extra clause.

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

For every **freshly-triaged** (MISS) issue that has **Blocker** gaps:

> **Cache-hit Blocker issues do NOT receive a duplicate `🔴 Triage` comment.** Their original comment from the first run persists on the issue. Only MISS issues that have Blockers get a new comment this run.
>
> **Previously-blockered issues that get a MISS always post a fresh comment.** When a cached entry shows `blockers: true` (the issue was previously blockered) but the cache is invalidated (key mismatch or stale-edge condition), the re-triage is treated as a full MISS. If the re-triage result still has Blockers, post a fresh `🔴 Triage` comment — do NOT guard on the stale cached `blockers: true` to skip posting. The stale cached result is not authoritative for the current run; only the fresh re-triage result governs whether a comment is posted.
>
> **Accepted trade-off:** the `🔴 Triage` comment is posted AFTER the cache key is computed. Posting it increments the issue's comment count, which self-invalidates the cache entry on the next run. This is the recorded accepted behavior — a blockered issue re-triages fresh on the next run, which is desirable. Do NOT add a dedup guard; that would deviate from the recorded design.

For each qualifying MISS issue:

1. **Post a triage comment** (`gh issue comment <n> --body "..."`) in the triage-comment shape (`skills/output-style.md`). The comment body must:
   - Open with `🔴 Triage` — byte-fixed, parsed downstream at `skills/solve-milestone/SKILL.md (Issues parked)` and probed at `skills/solve-milestone/parallel-waves.md (the probe found a park label)`. Only what FOLLOWS the opener is structured here.
   - Render the Blocker gaps as a **structured table**, one row per gap — lens/type · description · **evidence** · what clears it (the agent's `to_clear`) — not as prose bullets. The evidence column is what makes a claim checkable; a row with an empty evidence cell is an unfilled slot, not a shorter row.
   - Close with the durable-async instruction. That line stays **prose** because it qualifies every row at once and so has no cell to live in (`skills/output-style.md`, `## When prose is the correct form`) — it is the one closing line the table cannot carry, and it still states what must be recorded before this issue can build.

   Example:

   ```
   🔴 Triage

   | Lens / type | Blocker | Evidence | What clears it |
   |---|---|---|---|
   | architect / contradiction | Recorded design is internally contradictory. | "mirror ConfirmImportPage grouping" (comment #1) vs "flat list, no collection picker" (comment #3) | Record the authoritative grouping decision before building. |
   | design / scalability | Flat 16-row list at realistic volume will produce a poor result. | Established grouped-card pattern at `Views/ConfirmImportPage.xaml` | Group under collection headers like ConfirmImportPage, or record a justified divergence. |

   This is a durable async note — no reply needed now. Record the decision on this issue and re-run triage or solve-issue when ready.
   ```

2. **Recommended-label routing** — the label triage RECOMMENDS for this gap (returned in `issueStates`; the caller applies it):

   | Gap type | Recommended label |
   |---|---|
   | Any design/spec gap — architect `contradiction` / `not-buildable` / `missing-criteria` / `risky-design`, or any design-lens type (`spec-insufficiency`, `scalability`, `pattern-inconsistency`, `missing-state`, `missing-affordance`, `accessibility`) | `needs design` |
   | A new dependency / non-design decision — architect `undeclared-dependency` | `needs decision` |

   Each parked issue carries exactly **one** *triage-recommended* label. When an issue has gaps of multiple types, select the single label by precedence: **`needs design`** (any design or spec gap — the common case) takes precedence; otherwise **`needs decision`** (a non-design decision with no design gap). Return that one label in `issueStates.label` (Step 7).

   `blocked` is NOT a triage recommendation: the calling skill `solve-milestone` computes it at loop time from the dependency graph (Step 7) — an issue is `blocked` when an issue it depends on is not yet merged. Triage returns the graph; the caller derives and applies `blocked` itself (and any transitive-dependent holds).

   `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` Phase 4 is the source of truth for the label colors and descriptions the caller uses when applying these labels.

**triage does NOT apply labels, create branches, or open PRs.** It posts the comment and returns the recommended label per blocked issue in `issueStates` (Step 7). The calling skill (`solve-milestone` / `solve-issue`) applies that label using the apply-time label helper documented in `skills/setup/SKILL.md` Phase 4 (`gh label create --force` then `gh issue edit --add-label`), and leaves the issue open.

A Blocker **parks** the issue — triage posts the comment (Step 6) and returns the recommended label in `issueStates` (Step 7); the calling skill applies that label (via setup Phase 4's apply-time helper) and leaves the issue open. The loop continues with clean issues. This is a durable async handoff — never an interactive prompt.

### Step 6.5 — Cache write (best-effort)

After posting Blocker comments in Step 6, write/update entries for every **freshly-triaged** (MISS) issue. This step is **best-effort: a write failure logs a warning and does not error the triage run.**

1. **Build the entries object.** One JSON object keyed by issue number; per freshly-triaged issue: `key` — **the key computed at Step 2.5** (the pre-comment key, intentionally, so the next run re-triages blockered issues whose comment count has since changed; see "Accepted trade-off" in Step 6) — `triaged_at` (this run's ISO 8601 timestamp), and `result` from the Step 4 aggregate. The `result` object carries: `blockers` (boolean), `label` (`"needs design"` / `"needs decision"` / `null`), `advisories` (array of one-line strings), `risk` (`"light"` / `"heavy"`), and `edges` (the `dependencyGraph.edges["<n>"]` array for this issue).
2. **Hand it to the script.** `${CLAUDE_PLUGIN_ROOT}/scripts/triage-cache.<sh|ps1> write <repo-root> <entries.json>` re-reads the cache under the same resolution and degradation rules as Step 2.5, merges these entries over it one entry at a time, creates `.milestone-config/`, self-heals the committed `.milestone-config/.gitignore` so the cache is git-invisible in the consumer repo from the first write, writes the canonical `.milestone-config/triage-cache.json` atomically, and removes the stale legacy root cache. **Why re-read rather than reuse the Step 2.5 parse:** Step 6 posts Blocker comments, which increments each blockered issue's comment count, and that count is part of the cache key. The re-read also picks up a concurrent write (e.g. from a parallel triage run) instead of overwriting it with the Step 2.5 snapshot.
3. **Read the one record it prints.** `OK<TAB><path>` when the cache was written; `SKIP<TAB><reason>` (`no-jq`, `bad-entries`, `mkdir-failed`, `write-failed`) when it was not. It **always exits 0** — a `SKIP` sets the "cache write skipped this run" condition the Step 5 output line reports, and never aborts the run.

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
    "<n>": { blockers: true | false, label: "needs design" | "needs decision" | null, advisories: ["<one-line advisory>", …], risk: "light" | "heavy" },
    …
  }
}
```

`dependencyGraph.waves` gives the Wave-ordered sequence for loop ordering and output presentation (unchanged). `dependencyGraph.edges` is the per-issue map: each key is an issue number (as a string) and its value is the array of issue numbers that issue **directly depends on** — preserved from the `triageAgent` `DEPENDS_ON` returns before wave aggregation. An issue with no dependencies has an empty array or is absent from the map. The calling skill uses `edges["<n>"]` for per-issue buildability checks (not wave-level `dependsOn`, which is shared across all wave siblings).

`blockers: true` means the issue has at least one Blocker gap and is parked. `label` is the triage-recommended park label (`"needs design"` or `"needs decision"`) when `blockers: true`; `null` when `blockers: false`. `blockers: false` means it is all-clear (Advisories are logged but not gating). The calling skill uses `issueStates` to decide which issues to build and which to hold, uses the `label` field to apply the park label via setup Phase 4's apply-time helper, and separately derives `blocked` (and any transitive-dependent holds) from `dependencyGraph.edges`.

`risk` is the per-issue risk classification computed in Step 4: `"light"` or `"heavy"`. Default is `"heavy"` when classification is inconclusive. The calling skill (`solve-issue`) reads `issueStates["<n>"].risk` to resolve the build profile for that issue.

## Severity → effect

| Severity | Effect |
|---|---|
| **Blocker** | Parks the issue (triage comments + recommends the label; the caller applies it via setup Phase 4 and leaves it open); the loop continues with clean issues |
| **Advisory** | Logged in the gap table and output; not gating; build proceeds |

## Output style

Read `${CLAUDE_PLUGIN_ROOT}/skills/output-style.md` — the single source of truth for this plugin's output contract, and the same file every other skill's `## Output style` and every agent's `## Communication style` points at. Its `## Terminal output` section governs what this skill prints; its `## GitHub-facing prose`, `## When prose is the correct form`, and `## Evidence slots` sections govern the `🔴 Triage` comment this skill posts (Step 6). The two surfaces are distinct — the terminal rules never reach GitHub.

## Non-negotiables

- **Authors no code.** Never edits a source file, never creates a branch, never opens a PR. Triage **performs no migration move either** — it does not `git mv` a legacy root `milestone-driver.json` to `.milestone-config/driver.json`; the config relocation is owned by `setup` and `solve-issue` (the commands with a commit path). Triage does the transitional READ only (Step 1) and may surface a one-line legacy-detected note.
- **Opens no PRs.** The triage phase is read-only except for posting issue comments — it applies no labels, creates no branches, opens no PRs, and moves no files.
- **No interactive prompts.** Blocker comments are durable async handoffs on the originating issue — never a mid-run pause waiting for a human reply.
- **No fabricated findings.** Every gap cites its grounding (the exact recorded line, or `file:line` for a dependency). A claim that cannot be grounded in the actual artifact is emitted as a Blocker ("cannot verify X from the issue/code"), never as a confident guess. If an issue cannot be retrieved, STOP — do not fabricate a stand-in.
