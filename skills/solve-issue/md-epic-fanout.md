## Parent-issue detection (`md-epic`)

Reaching this file means the caller read `#n`'s labels and found `md-epic` (`skills/solve-issue/SKILL.md (Runs before anything else)`): `#n` is a **parent issue**, a pure orchestration node carrying no code. `### Parent path` replaces the rest of that pipeline for this invocation.

### Parent path

A parent issue's body carries an ordered list of milestones — the build order for a feature too large for one milestone (the read-contract in `docs/superpowers/specs/2026-07-04-md-epic-driver-fanout-design.md`). This path drives that list to completion.

1. **Profile read only.** Run SKILL.md's `## Before starting` step 1 (profile read) — the fan-out loop needs `integrationBranch` to re-sync between milestones, and `integrationGranularity` for step 6. **Skip SKILL.md steps 2 and 3** (the clean-tree check and the branch-state probe): a parent issue authors no code, so it has no feature branch and no branch state to probe.

2. **Parse the ordered milestone list** from `#n`'s raw body (pwsh on Windows, bash elsewhere — same host selection as `${CLAUDE_PLUGIN_ROOT}/scripts/ci-preflight-steps.{sh,ps1}` at SKILL.md step 6.1):

   ```bash
   gh issue view <n> --json body --jq .body | bash "${CLAUDE_PLUGIN_ROOT}/scripts/parse-md-epic-order.sh"
   # pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/parse-md-epic-order.ps1" on pwsh-only hosts
   ```

   The parser emits one `<kind>\t<raw>` record per entry on stdout (`kind` = `number`|`title`), or exits nonzero with the failure named on stderr — it never calls `gh` and never resolves an entry itself (`${CLAUDE_PLUGIN_ROOT}/scripts/parse-md-epic-order.sh`).

   **Two triggers park the PARENT issue `#n` — the fan-out never starts.** Park action for both: post a comment on `#n` in the park-comment shape (`skills/output-style.md`) opening `🔴 Parked — ` with the reason below (`gh issue comment <n>`), apply `blocked` via the apply-time helper (`gh label create --force` then `gh issue edit <n> --add-label blocked`), leave `#n` open, and return. No milestone in the list is driven this run.

   - **A nonzero exit.** No `md-epic-order` block, an unterminated fence, or one malformed line all invalidate the whole list — a half-parsed build order is unsafe to act on. Reason: quote the parser's stderr.
   - **A zero exit with ZERO entries (empty stdout) — not a silent success.** A well-formed `md-epic-order` block with no interior entries parses cleanly but has nothing to drive; treat it as an authoring mistake, not a valid empty run. Reason: "empty md-epic-order block — no milestones to drive".

3. **Resolve each `{kind, raw}` entry to a live milestone**, mirroring `solve-milestone`'s own number/title resolution (`skills/solve-milestone/SKILL.md (Resolve the milestone argument)`):
   - `number: <raw>` → `gh api repos/{owner}/{repo}/milestones/<raw> --jq '{number, title}'`. A non-2xx response means "does not resolve."
   - `title: <raw>` → `gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --paginate --jq '.[] | select(.title=="<raw>") | {number, title}'`. Zero or multiple matches both mean "does not resolve" — never guess between two same-titled milestones.
   - **Does not resolve, OR resolves but has zero total issues** (`open_issues + closed_issues == 0`) → **skip only that entry** — not a park. Log a warning line in the aggregate summary (step 6) and continue.

4. **Drive each resolved milestone sequentially, in listed order** — never concurrently; a later milestone may depend on an earlier one's merged code:
   - **Resume-skip, no local checkpoint.** Before driving, re-read the milestone's counts: `gh api repos/{owner}/{repo}/milestones/<number> --jq '{open_issues, closed_issues}'`. `open_issues == 0` AND `closed_issues > 0` → already complete — skip **silently**, count it done in the summary.
   - **Numeric-title guard (skip-with-warning).** Before driving a milestone that is not already complete, check its resolved title from step 3. If the title is **purely numeric** (digits only), do **not** drive it: `solve-milestone`'s own purely-numeric-title halt (`skills/solve-milestone/SKILL.md (a purely-numeric milestone)`) is a human-prompt halt **not** suppressed by `--driven` (`skills/solve-milestone/SKILL.md (interpreted token, not a parsed CLI flag)`), so driving it would stall the unattended fan-out forever. **Skip it with a warning** in the aggregate summary (step 6) — the human must rename it to a non-numeric title first — and continue with the next entry.
   - **Otherwise, drive it:** invoke `/milestone-driver:solve-milestone <number> --driven` — the skill-invokes-skill pattern `solve-milestone` already uses to invoke `/milestone-driver:triage` (`skills/solve-milestone/SKILL.md § Phase 0 — Triage`) — and await completion. `--driven` suppresses the DB-hazard interview (`skills/solve-milestone/SKILL.md (same as row 4 but)`, `skills/solve-milestone/SKILL.md (DB-hazard interview (row 4).**)`, `skills/solve-milestone/SKILL.md (with a loud note)`) so the fan-out never blocks on a prompt nobody is watching for.
   - **Re-sync `integrationBranch`** (`git fetch`, fast-forward) after each milestone, so the next builds on the prior one's merged work.
   - **A systemic failure inside a driven `solve-milestone`** (`gh auth`, a broken `integrationBranch`, missing tooling — `skills/solve-milestone/SKILL.md § Autonomy` → "Systemic failures that halt the run") halts the **whole fan-out loop**: later milestones cannot be driven safely either.

5. **`#n` itself is never built.** It carries no code, so it never goes through SKILL.md's `### 0. Triage`, root-cause-or-park, or implementer dispatch. Its label state changes only via the park path in step 2.

6. **Aggregate summary**, one row per milestone — mirroring `solve-milestone`'s own run-complete reporting shape (Template 3, `skills/solve-milestone/SKILL.md § Template 3 — Final results`; the content requirements, `skills/solve-milestone/SKILL.md § Final summary`). Classify each driven milestone from ground truth after driving, never from the driven run's own narrative (`skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 1: concurrent stage dispatch`):

   | Milestone | Outcome | Note |
   |---|---|---|
   | #<number> — <title> | done already \| built this run \| open, PR unmerged \| parked with opens | warning text for a skipped entry, or — |

   - **done already** — the resume-skip in step 4 fired before driving (`open_issues == 0`, `closed_issues > 0`, never dispatched this run).
   - **built this run** — after driving, `open_issues == 0` and `closed_issues > 0`.
   - **open, PR unmerged**: after driving, `open_issues > 0` and the milestone PR carries `needs review`. `gh pr list --head "milestone-<number>-<slug>" --label "needs review" --json number --jq '.[0].number // empty'` returns a number; only the red-CI handler applies that label (`skills/solve-milestone/milestone-granularity.md (### Red CI on the milestone PR)`), and nothing ever clears it, so the PR was parked unmerged whatever its checks say now. `gh pr checks <pr-number> --json bucket --jq '[.[].bucket]'` splits the Note, first match winning over the five buckets `gh` emits (`pass`, `fail`, `pending`, `skipping`, `cancel`), `--json` skipping gh's exit 8: any `fail` names the failing check; else any `cancel` is a cancelled workflow, never a green build; else any `pending` is a run in flight since the park; otherwise every check passed or was skipped, a no-CI repo's `no checks reported` error included, and the PR waits on a human to merge it.
   - **parked with opens** — after driving, `open_issues > 0` and at least one remaining open issue carries a blocker label (`needs design` / `needs decision` / `blocked`).
   - **Both at once → `parked with opens` wins.** A blocker label is the root block and takes precedence (`skills/solve-milestone/not-buildable.md (the root block and takes precedence)`). The Note still reports both facts.
   - Each **skipped entry** from step 3 gets its own row (raw reference + why it didn't resolve, or "0 issues") rather than being silently dropped.
   - A milestone **skipped by the numeric-title guard** (step 4) also gets its own row — `#<number> — <title>` — the Note stating it cannot be driven unattended until the human renames it.
