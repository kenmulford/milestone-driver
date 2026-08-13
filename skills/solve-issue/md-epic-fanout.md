## Parent-issue detection (`md-epic`)

Detection runs before anything else and belongs to the caller, which reads `#n`'s labels and only then reads this file (`skills/solve-issue/SKILL.md (Runs before anything else)`). Reaching this file therefore means `#n` carries `md-epic`: it is a **parent issue**, a pure orchestration node that carries no code, and `### Parent path` below replaces the rest of that pipeline for this invocation.

### Parent path

A parent issue's body carries an ordered list of milestones — the build order for a feature too large for one milestone (the read-contract in `docs/superpowers/specs/2026-07-04-md-epic-driver-fanout-design.md`). This path drives that list to completion; it never authors code for `#n` itself.

1. **Profile read only.** Run SKILL.md's `## Before starting` step 1 (profile read) — the fan-out loop needs `integrationBranch` to re-sync between milestones, and `integrationGranularity` for step 6. **Skip SKILL.md steps 2 and 3** (the clean-tree check and the branch-state probe) — a parent issue authors no code, so it has no feature branch and no branch state to probe.

2. **Parse the ordered milestone list** from `#n`'s raw body with the #266 parser (pwsh on Windows, bash elsewhere — same host selection as `${CLAUDE_PLUGIN_ROOT}/scripts/ci-preflight-steps.{sh,ps1}` at SKILL.md step 6.1):

   ```bash
   gh issue view <n> --json body --jq .body | bash "${CLAUDE_PLUGIN_ROOT}/scripts/parse-md-epic-order.sh"
   # pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/parse-md-epic-order.ps1" on pwsh-only hosts
   ```

   The parser emits one `<kind>\t<raw>` record per entry on stdout (`kind` = `number`|`title`), or exits nonzero with the failure named on stderr — it never calls `gh` and never resolves an entry itself (`${CLAUDE_PLUGIN_ROOT}/scripts/parse-md-epic-order.sh`, issue #266).

   **Two triggers park the PARENT issue `#n` — the fan-out never starts.** Park action for both: post a comment on `#n` in the park-comment shape (`skills/output-style.md`) opening `🔴 Parked — ` with the reason below (`gh issue comment <n>`), apply `blocked` via the apply-time helper (`gh label create --force` then `gh issue edit <n> --add-label blocked`), leave `#n` open, and return. No milestone in the list is driven this run.

   - **A nonzero exit.** No `md-epic-order` block, an unterminated fence, or one malformed line all invalidate the whole list (a half-parsed build order is unsafe to act on). Reason: quote the parser's stderr.
   - **A zero exit with ZERO entries (empty stdout) — this is not a silent success.** A well-formed `md-epic-order` block with no interior entries parses cleanly (exit 0) but has nothing to drive; treat it the same class as an authoring mistake, not a valid empty run. Reason: "empty md-epic-order block — no milestones to drive".

3. **Resolve each `{kind, raw}` entry to a live milestone**, mirroring `solve-milestone`'s own number/title resolution (`skills/solve-milestone/SKILL.md (Resolve the milestone argument)`):
   - `number: <raw>` → `gh api repos/{owner}/{repo}/milestones/<raw> --jq '{number, title}'`. A non-2xx response means "does not resolve."
   - `title: <raw>` → `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | select(.title=="<raw>") | {number, title}'`. Zero or multiple matches both mean "does not resolve" — never guess between two same-titled milestones.
   - **Does not resolve, OR resolves but has zero total issues** (`open_issues + closed_issues == 0`) → **skip only that entry** — not a park. Log a warning line in the aggregate summary (step 6) and continue with the next entry.

4. **Drive each resolved milestone sequentially, in listed order** — never concurrently; a later milestone may depend on an earlier one's merged code:
   - **Resume-skip, no local checkpoint** (mirrors the no-checkpoint-file philosophy already stated for the branch-state probe, SKILL.md's `## Before starting` step 3). Before driving, re-read the milestone's counts: `gh api repos/{owner}/{repo}/milestones/<number> --jq '{open_issues, closed_issues}'`. `open_issues == 0` AND `closed_issues > 0` → already complete — skip **silently**, count it done in the summary. This makes re-running the parent idempotent with no state file to maintain.
   - **Numeric-title guard (skip-with-warning).** Before driving a milestone that is not already complete, check its resolved title from step 3's `{number, title}`. If the title is **purely numeric** (digits only), do **not** drive it: `solve-milestone`'s own purely-numeric-title halt (`skills/solve-milestone/SKILL.md (a purely-numeric milestone)`) is a human-prompt halt that is **not** suppressed by `--driven` (`skills/solve-milestone/SKILL.md (interpreted token, not a parsed CLI flag)`), so driving it would stall the unattended fan-out forever waiting on a human. **Skip that milestone with a warning** in the aggregate summary (step 6) instead — the human must rename it to a non-numeric title before it can be driven unattended — and continue with the next entry.
   - **Otherwise, drive it:** invoke `/milestone-driver:solve-milestone <number> --driven` — the skill-invokes-skill pattern `solve-milestone` already uses to invoke `/milestone-driver:triage` (`skills/solve-milestone/SKILL.md § Phase 0 — Triage`) — and await completion. `--driven` suppresses the DB-hazard interview (`skills/solve-milestone/SKILL.md (same as row 4 but)`, `skills/solve-milestone/SKILL.md (DB-hazard interview (row 4).**)`, `skills/solve-milestone/SKILL.md (with a loud note)`) so the fan-out never blocks on a prompt nobody is watching for.
   - **Re-sync `integrationBranch`** (`git fetch`, fast-forward) after each milestone, before advancing to the next, so the next milestone builds on the prior one's merged work.
   - **A systemic failure inside a driven `solve-milestone`** (`gh auth`, a broken `integrationBranch`, missing tooling — `skills/solve-milestone/SKILL.md § Autonomy` → "Systemic failures that halt the run") halts the **whole fan-out loop**, not just the current milestone — later milestones cannot be driven safely either.

5. **`#n` itself is never built.** It carries no code, so it never goes through SKILL.md's `### 0. Triage`, SKILL.md's root-cause-or-park, or SKILL.md's implementer dispatch — it is a pure orchestration node. Its label state changes only via the park path in step 2 above.

6. **Aggregate summary**, one row per milestone — mirroring `solve-milestone`'s own run-complete reporting shape (Template 3, `skills/solve-milestone/SKILL.md § Template 3 — Final results`; the Final summary content requirements, `skills/solve-milestone/SKILL.md § Final summary`). Classify each driven milestone from ground truth after driving, not from the driven run's own narrative (the same derive-from-artifacts posture the Wave barrier uses, `skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 1: concurrent stage dispatch`, and the Final summary's park-reason read, `skills/solve-milestone/SKILL.md § Final summary` → "Issues parked"):

   | Milestone | Outcome | Note |
   |---|---|---|
   | #<number> — <title> | done already \| built this run \| held for visual review \| parked with opens | warning text for a skipped entry, or — |

   - **done already** — the resume-skip in step 4 fired before driving (`open_issues == 0`, `closed_issues > 0`, never dispatched this run).
   - **built this run** — after driving, `open_issues == 0` and `closed_issues > 0`.
   - **held for visual review** — after driving, `open_issues > 0` and every remaining open issue is a UI issue with an open PR carrying `needs review`.
   - **held for visual review**, under `integrationGranularity: "milestone"` — the milestone PR decides it. `gh pr list --head "milestone-<number>-<slug>" --label "needs review" --json number --jq '.[0].number // empty'` returning a number is the hold (`docs/profile-schema.md (Should the single milestone PR wait)`). `gh pr checks <pr-number> --json bucket --jq 'any(.bucket=="fail")'` splits the Note: `true` is a failed build; `false`, and a no-CI repo's `no checks reported` error, is a `visualHold` hold (`skills/solve-milestone/integration-granularity.md (is **vacuously green**)`).
   - **parked with opens** — after driving, `open_issues > 0` and at least one remaining open issue carries a blocker label (`needs design` / `needs decision` / `blocked`).
   - A milestone with both open `needs review` PRs and parked issues reports both facts in its Note column.
   - Each **skipped entry** from step 3 gets its own row (raw reference + why it didn't resolve, or "0 issues") rather than being silently dropped from the summary.
   - A milestone **skipped by the numeric-title guard** (step 4) also gets its own row — `#<number> — <title>` — with the Note column stating it cannot be driven unattended until the human renames it to a non-numeric title.

