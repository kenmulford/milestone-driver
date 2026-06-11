# Trello sync — solve-milestone reference

This file is loaded by solve-milestone when `integrations.trello` is present in the profile. All Trello operations described here are best-effort: a failure never blocks a run, never parks an issue, and never halts the loop. The orchestrator main thread owns every call; solve-issue (including `--worker` mode) makes zero Trello calls.

---

## Run-start execution order (invoked by SKILL.md step 3.5)

When step 3.5 invokes this file's run-start card resolution, execute in this order:

1. Convention 2 — Availability probe (first, before any other Trello call)
2. Convention 3 — Misconfiguration guard
3. Convention 4 — Ensure-list (provision the three managed lists)
4. Convention 5 — Card resolution (back-link anchor → name-match → create)
5. Convention 7 — Card content (on creation/adoption)
6. Convention 8 — State machine (apply card state transition)

Conventions 1 (best-effort wrapper) and 9 (thread safety) apply throughout.

---

## Convention 1 — Best-effort wrapper (never a gate)

Every Trello operation is wrapped best-effort. On any failure, log one line:

```
Trello: <operation> skipped — <error>
```

and continue. Trello failures are NEVER a systemic failure. They never park an issue. They never halt the run. All skipped updates are collected and listed in the final summary.

---

## Convention 2 — Availability probe

Before the first Trello call of a run, probe `mcp__trello__get_health`. If the `mcp__trello__*` tools are unavailable (server not loaded in this session), log once:

```
Trello MCP tools not available in this session — all Trello steps skipped
```

and skip every Trello operation for the rest of the run. This one-time log distinguishes "configured but tools absent" (log line) from "not configured" (profile node absent → silent, per Convention 3).

---

## Convention 3 — Misconfiguration guard

If `integrations.trello` is present in the profile but `boardId` is missing, treat it as not configured: log one line and skip all Trello operations for the rest of the run:

```
Trello: integrations.trello.boardId missing — Trello steps skipped
```

---

## Convention 4 — Ensure-list (auto-create)

Resolve each needed list by **case-sensitive name** on the configured board:

1. Call `mcp__trello__get_lists` with the configured `boardId`.
2. Match by exact name (case-sensitive).
3. If the list is absent, create it via `mcp__trello__add_list_to_board`.

This is idempotent provisioning — the same spirit as setup Phase 4's `gh label create --force`. Running multiple times is safe.

The three list names resolve from the profile's `integrations.trello.lists` object:

| Profile key | Default name |
|---|---|
| `lists.queue` | `Queue` |
| `lists.inProgress` | `In Progress` |
| `lists.inReview` | `In Review` |

---

## Convention 5 — Card resolution order (run start)

Run these steps in order; stop at the first **valid** match (step 1 is a valid match only when the card ID is found in a managed list; the not-found sub-bullet falls through to step 2):

1. **Back-link anchor.** Read the GitHub milestone description. If it contains `<!-- trello: <card-url> -->`, that card URL is authoritative — extract the card ID from the URL. Do NOT call `mcp__trello__get_card`; the URL is trusted as-is.

   After extracting the card ID, scan the three managed lists (queue, inProgress, inReview — each resolved per Convention 4) via `mcp__trello__get_cards_by_list_id` in that order to determine which list the card is currently in. If the card ID is found in a managed list, proceed to Convention 8 with that list context.

   - **Card not found in managed lists:** if the card ID is NOT found in any of the three managed lists, the card may have been moved to an unmanaged list (e.g., "Done") or was deleted. Fall through to step 2 to search by name. Log one line:
     ```
     Trello: back-link card not found in managed lists — searching by name
     ```
     When step 2 or step 3 resolves a new card, call Convention 6 in **replace mode**: remove any existing `<!-- trello: ... -->` line from the description before appending the new back-link (replace, not append).

2. **Name-match adoption.** Call `mcp__trello__get_cards_by_list_id` on the *queue*, *inProgress*, and *inReview* lists in order (each resolved per Convention 4), stopping at the first match. Search each list for a card whose name exactly matches the milestone name. If found in any list, adopt it, write the back-link via Convention 6 (use replace mode if arriving here from the step-1 fallthrough — step 1's not-found sub-bullet sets replace mode for this path), then run Convention 7 (adoption path), then apply Convention 8 (state machine).

   - **Ambiguity edge case:** if two or more cards in the matched list share the milestone name, adopt the first returned and log:
     ```
     Trello: multiple cards named "<milestone-name>" in <list-name> list — adopted first returned; back-link will disambiguate future runs
     ```

3. **Create.** Create the card in the *queue* list via `mcp__trello__add_card_to_list`, populate it per Convention 7, then write the back-link via Convention 6.

**Milestone description empty edge case:** if the milestone description is empty, the back-link becomes its only content. The PATCH sets the description to `<!-- trello: <card-url> -->`.

---

## Convention 6 — Back-link format and idempotency

**Format:** append `<!-- trello: <card-url> -->` as the **final line, on its own line** of the milestone description. This is an HTML comment — invisible in GitHub's rendered description — and placed at the trailing position so it does not interfere with Wave-order parsing (which reads leading content).

**Idempotency:** before PATCHing, check whether the description already contains `<!-- trello:`. If it does, skip the PATCH — the back-link is already present. Never insert inside or above the Wave block. Never append a second back-link.

**Replace mode (called from the step-1 not-found-in-managed-lists fallthrough):** if the description already contains `<!-- trello: ... -->`, remove that line before appending the new URL (replace, not append). This is distinct from the normal idempotency skip: the normal skip applies when the back-link IS the current card; replace mode applies when the back-link is a stale URL that needs updating.

**Command shape (read-modify-write):**

```
# 1. Fetch the current description
CURRENT=$(gh api repos/{owner}/{repo}/milestones/<number> --jq '.description')

# 2. PATCH with the back-link appended
gh api -X PATCH repos/{owner}/{repo}/milestones/<number> \
  -f description="${CURRENT}

<!-- trello: <card-url> -->"
```

PowerShell 7+ here-string variant is equally acceptable. This is a procedural instruction executed by the orchestrator, not a shipped hook script.

---

## Convention 7 — Card content at creation/adoption

Populate the card as follows (best-effort on each sub-step). The create and adoption paths differ for the checklist:

**Card description:**
- **Creation path:** set the card description (via the `mcp__trello__add_card_to_list` content parameter) to the GitHub milestone URL followed by the milestone description text.
- **Adoption path:** do NOT update the existing card's Trello description — no `update_card_details` call is made. The adopted card's description is left as-is. This is a known limitation: the existing card's description may be stale if the milestone description changed since the card was created.

**On CREATION (new card via step 3 of Convention 5):**

**Checklist "Issues":**
1. Create the checklist via `mcp__trello__create_checklist` on the card.
2. For each **open** issue in the milestone at card-creation time, add one item via `mcp__trello__add_checklist_item` with text format: `#<n> — <issue title>`.

**On ADOPTION (existing card adopted via step 2 of Convention 5):**

Skip checklist creation and population entirely. The existing checklist from the original creation run is preserved as-is — no reconciliation is performed.

**Recorded limitation (no reconciliation on re-runs):** issues added to the milestone after card creation do not appear in the checklist automatically. Manually closed issues are not auto-ticked. On adoption, the existing checklist is preserved as-is (no reconciliation). This is a known, accepted limitation — reconciliation is deferred to a future wave.

---

## Convention 8 — Card state machine (existing card found at run start)

When a card is resolved at run start, apply the following state transition:

| Card currently in | Action |
|---|---|
| *queue* list | Leave in place; proceed |
| *inProgress* list | Leave in place; proceed (re-run mid-work) |
| *inReview* list | Move back to *inProgress* via `mcp__trello__move_card` (re-run picking up new or reopened work) |
| any other list | Leave in place; log one line (`Trello: card in unrecognized list "<name>" — not moved; human may have repositioned it`) and proceed |

---

## Convention 9 — Thread safety / parallel mode

ALL Trello calls are made by the **solve-milestone orchestrator main thread only**. `solve-issue` — including `--worker` mode in parallel runs — makes **zero** Trello calls. This is enforced by placement: every call site lives in solve-milestone's orchestration steps, not inside solve-issue or any worker agent.

---

## Convention 10 — Phase hooks

## Phase 0 hooks

Invoked by SKILL.md Phase 0 after step 2 (apply park labels) and before step 3 (seed the build queue). All operations follow Convention 1 (best-effort). The orchestrator main thread makes all calls.

### Edge case: no card handle

If the run-start card resolution (earlier in the run) failed and no card handle exists, skip BOTH Phase 0 operations with a single log line and return:

```
Trello: Phase 0 hooks skipped — no card handle (run-start resolution failed)
```

No retry is attempted.

### Step 1 — Post triage summary comment

Call `mcp__trello__add_comment` on the milestone card. Compose the comment body from triage's output:

**All-clear case** (no issues have `blockers == true`):

```
✅ All clear — triage found no blocking gaps.

<Wave-ordered dependency graph from triage Step 5 output>
```

> If triage returned advisory notes, append them after the dependency graph. Omit this section entirely when there are no advisories.

**Gaps case** (one or more issues have `blockers == true`):

```
<Gap table — Blockers first, then Advisories>

| Issue | Lens | Severity | Gap | What's needed |
|-------|------|----------|-----|---------------|
| ...   | ...  | Blocker  | ... | ...           |
| ...   | ...  | Advisory | ... | ...           |

<Wave-ordered dependency graph from triage Step 5 output>
```

**Truncation edge case:** if the triage output exceeds Trello's comment character limit:

- **Gaps case:** truncate the table body (keep the table header row) and append:
  ```
  (truncated — full table in the run output / GitHub issues)
  ```
- **All-clear case:** truncate the dependency graph text (keep the `✅ All clear` header line) and append:
  ```
  (truncated — full dependency graph in the run output / GitHub issues)
  ```

Wrap this entire operation best-effort. On failure, log:

```
Trello: triage summary comment skipped — <error>
```

and continue to Step 2.

### Step 2 — Move card (Queue → inProgress) or stay

Evaluate the move condition using `issueStates` from triage:

- **Move condition:** `issueStates` contains at least one entry where `blockers == false` (at least one issue is buildable — partial-clear counts).
- **All-parked condition:** every entry in `issueStates` has `blockers == true` (zero buildable issues).

**If card is already in inProgress:** the move is a no-op regardless of condition — skip silently (re-run case; card already advanced).

**If move condition is met and card is in queue list:** call `mcp__trello__move_card` to move the card to the inProgress list. Wrap best-effort. On failure, log:

```
Trello: card move (Queue → In Progress) skipped — <error>
```

**If move condition is met and card is in any other list** (unmanaged, e.g., "Done"): leave the card in place and log one line:

```
Trello: card in unmanaged list — not moved; human may have repositioned it
```

**If all-parked condition:** do NOT move the card regardless of which list it is in. Post one additional comment via `mcp__trello__add_comment`:

```
All issues are parked — see triage summary above. Card remains in Queue.
```

Wrap this comment best-effort. On failure, log:

```
Trello: all-parked comment skipped — <error>
```

## Loop hooks

Two call sites fire checklist ticks during the solve-milestone loop. Both are main-thread only (Convention 9). Both are no-ops when `integrations.trello` is absent from the profile.

### Issue granularity

**Call site:** step 4 "On success" in SKILL.md, immediately after squash-merge and issue close, before `integrationBranch` re-sync. Fires once per merged non-UI issue.

**When a card handle is available:**

1. Call `mcp__trello__get_checklist_items` with the card ID and checklist name `"Issues"`.
2. Find the item whose text **starts with `#<n>`** (match on the leading `#<n>` token only — titles may have been edited after checklist creation).
3. Call `mcp__trello__update_checklist_item` with `complete: true` on the matched item.

**What is NOT ticked:** UI issues held at the visual-review gate (PR open with `needs review`, issue not yet closed) are never ticked at this call site — they have not been merged and closed.

**Parallel mode (`--parallel`):** ticks fire in the serial verified merge tail (main thread, Phase 2) as each issue's branch is squash-merged. The merge tail's per-branch squash-merge loop passes through the same on-success tick logic as the sequential step 4 path — no separate call site is needed.

**Best-effort per item:** any failure logs one line and the loop continues:

```
Trello: checklist tick #<n> skipped — <error>
```

**Edge case — item not found:** the issue was added to the milestone after card creation (known non-reconciliation limitation per Convention 7). Log:

```
Trello: checklist tick #<n> skipped — item not found
```

Do NOT add a new item. Continue.

**Edge case — no card handle:** if run-start card resolution failed (no handle available for this run), skip silently. The single run-start log was already emitted (Convention 2 if tools are absent, Convention 3 if boardId is missing, or Convention 1 if card resolution itself failed); no per-issue log spam.

---

### Wave granularity

**Call site:** SKILL.md `integrationGranularity: "wave"` path, immediately after `gh issue close #a #b #c --reason completed`. There is no per-issue merge event in this path — the wave PR merges once, then all logic issues are closed together.

**When a card handle is available:**

For each issue `#<n>` closed in the wave:

1. Call `mcp__trello__get_checklist_items` with the card ID and checklist name `"Issues"`.
2. Find the item whose text starts with `#<n>`.
3. Call `mcp__trello__update_checklist_item` with `complete: true` on the matched item.

Execute as a sequence of calls — one tick per closed issue. (The checklist items call may be shared/cached across the sequence if the implementation prefers, but each item update is a separate call.)

**Best-effort per item:** each tick failure logs one line and the sequence continues to the next issue:

```
Trello: checklist tick #<n> skipped — <error>
```

**Edge case — item not found** and **edge case — no card handle:** same rules as issue granularity above.

## Finish hooks

Placeholder: Trello finish hook logic added by #103.
