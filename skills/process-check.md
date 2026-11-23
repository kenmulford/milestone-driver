# Process-check contract - shared reference

The single source of truth for what each step milestone-driver owns does in
this version, so a later check can tell when a project's instruction files
restate or replace one. It sits here beside `skills/notices.md`, a peer of the
skill folders, because both run skills read it. It is read only when a check is
due, so it joins no skill's unconditional load closure
(`scripts/check-size-budgets.sh (MEMBERSHIP RULE, and the only one)`).
`scripts/process-check.{sh,ps1}` hash this file, so the procedure that runs it
lives in `skills/process-check-procedure.md`: a wording edit there must not mark
every consumer repo `due`.

## Contents

Scanned files · What is never a finding · The contract

## Scanned files

Scanned files: every non-hidden `*.md` directly in `.project/` and in the `projectDocs` directory (default `.project`), each `standingDocs` entry's path before `#` under the `projectDocs` directory, and `CLAUDE.md`, `AGENTS.md` and `.claude/CLAUDE.md` at the repo root. A file that does not exist is skipped. The profile is `.milestone-config/driver.json`, else the legacy root `milestone-driver.json`; with neither, the defaults apply.

## What is never a finding

A repo choice the driver already exposes as a profile key, or one the contract doesn't cover, is never a finding, since that is the project's policy and not stale process.

Examples: a subagent cap, or "testing at milestone end" under `integrationGranularity: milestone`.

## The contract

One row per step the driver owns. The key column names the profile key that makes the step project policy, or `none`.

| Step | What this version does | Defined at | Key |
|---|---|---|---|
| Planning | A planner leaf is dispatched, or the issue record is the packet when its body carries an `Edit points:` list item and a `Tests:` list item, and the orchestrator never writes the plan on the main thread. | `skills/solve-issue/SKILL.md (Under every build profile, when the step 1 issue record)` | `none` |
| Packet content | The packet holds pointers and quoted declarations only, with no function bodies and no test code, under a 12288-byte cap. | `skills/solve-issue/build-packet.md (The build packet is the file an implementer builds one issue from.)` | `none` |
| Implementer verify | The implementer is a leaf that verifies its own scoped work and returns an uncommitted diff. | `skills/solve-issue/SKILL.md (The implementer is a leaf.)` | `implementerAgent` |
| Integration and build cadence | Under milestone granularity a fold squash-merges onto the milestone branch with no re-verify, and the milestone lands as one push, one PR and one CI run. | `skills/solve-milestone/milestone-granularity.md (There is no step 2.)`; `skills/solve-milestone/milestone-granularity.md (Runs once, after the loop finishes.)` | `integrationGranularity` |
| Test gates | Unit, E2E and preflight run as act, verify, retry, park with a shared cap, and at milestone end they run once over the whole range. | `skills/solve-issue/SKILL.md (Unit, E2E, and preflight share one shape)`; `skills/solve-milestone/milestone-end-gates.md (Run these once over)` | `unitTestCmd`, `e2eTestCmd`, `preflightCmd` |
| Review cadence | The verdict sets the review cycle cap and the build profile sets which findings get fixed. | `skills/review-depth.md (The verdict sets the cycle cap.)` | `coherenceReviewAgent`, for the coherence pass only |
| Park labels | Every park posts a `🔴 Parked - ` comment and applies one of `needs design`, `needs decision` or `blocked`. | `skills/solve-issue/SKILL.md (The park action, referenced by every park below.)` | `none` |
