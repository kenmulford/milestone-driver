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

## Convention 10 — Section stubs for later waves

## Phase 0 hooks

Placeholder: Trello Phase 0 hook logic added by #101.

## Loop hooks

Placeholder: Trello loop hook logic added by #102.

## Finish hooks

Finish hooks fire after the run's issue loop completes (SKILL.md `### 5. Finish`), before or alongside the `## Final summary` output — specifically, fire the summary card comment and move evaluation immediately after the loop, so the comment content matches the final run state. On the clean-completion path the `## Final summary` Template 3 output is deferred to step 6.9; the Finish hooks fire before step 6 (the CHANGELOG step). On a normal completion, post the summary card comment and (if the move condition is met) move the card to *inReview*. On a systemic-failure halt, post the summary card comment if Trello is reachable (per Convention 2 probe result), but do NOT move the card — the run did not finish cleanly.

If no card was resolved at run start (Convention 5 found or created no card), skip all Finish hooks.

### Final summary card comment

Post a card comment that mirrors the canonical Final summary fields, condensed for a Trello card comment. Use `mcp__trello__add_comment` on the resolved card. Best-effort: failure is logged per Convention 1 and the run is unaffected.

**Fields to include in the comment:**

- **Issues built and merged** — list each issue number and title with its PR link (e.g. `#12 Add login page — PR #45`)
- **Issues parked** — for each parked issue: number, title, park label (one of `needs design`, `needs decision`, `blocked`), and a one-line blocker reason
- **Open `needs review` UI PRs** — list any PRs awaiting human visual sign-off (these are built issues held at the visual gate, not parked issues)
- **Trello updates skipped this run** — any Trello operations that failed and were skipped, from the best-effort log accumulated per Convention 1

### Move condition: inProgress → inReview

Move the card from *inProgress* to *inReview* if and only if **zero open milestone issues carry any of the three blocker labels**: `needs design`, `needs decision`, `blocked`.

Check this live at finish time:

```bash
gh issue list --milestone "<milestone-name>" --state open --json labels
```

Inspect the returned labels array for each open issue. If any open issue carries `needs design`, `needs decision`, or `blocked`, the move condition fails.

**`needs review` issues are NOT parked.** Issues held at the visual gate — a UI issue with an open `needs review` PR awaiting human visual sign-off — are built work awaiting human review, not blocked work. They do not carry a blocker label and do NOT prevent the move.

On move condition met: call `mcp__trello__move_card` to the `inReview` list (list ID resolved per Convention 4 at run start). Best-effort: move failure is logged per Convention 1.

### Parks remaining (move condition fails)

When one or more open issues carry a blocker label, the card STAYS in *inProgress* — no move call is made. Post an additional card comment (best-effort):

```
Card remains In Progress — N issue(s) parked: #a Title A, #b Title B. Resolve the parks and re-run to advance to In Review.
```

Post via `mcp__trello__add_comment` on the resolved card (best-effort per Convention 1).

### Systemic-halt path

When the run ends due to a systemic failure, post summary comment if Trello was reachable at run start (per Convention 2 probe result) but do NOT move the card. The move is skipped regardless of label state — the run did not finish cleanly.

### Out-of-scope: Completed list

Moving the card to a Completed or Done list is a **manual human step** after the `integrationBranch` → `protectedBranch` release merge. No `lists.completed` key exists in the profile. The finish hooks do not touch a completed list.

### Edge cases

**Stale blocked label.** The move condition checks `--state open` issues only — a closed (merged) issue's labels are not visible to the check. A stale `blocked` label on a **closed** issue does not block the move. A stale `blocked` label on an **open** issue (e.g., an issue not built this run) does block the move, even if no code work remains — the stays-in-Progress comment surfaces it for the human to clear.

**Card manually moved mid-run.** At finish, a successful run (move condition met) moves the card to *inReview* regardless of which list the card is currently in. The Convention 8 "any other list → leave-and-log" rule applies only at run START (to avoid overriding a human decision before the run begins), not at finish (where the run result justifies the transition).
