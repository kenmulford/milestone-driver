# Process-check contract - shared reference

The single source of truth for what each step milestone-driver owns does in
this version, so a later check can tell when a project's instruction files
restate or replace one. It sits here beside `skills/notices.md`, a peer of the
skill folders, because both run skills read it. It is read only when a check is
due, so it joins no skill's unconditional load closure
(`scripts/check-size-budgets.sh (MEMBERSHIP RULE, and the only one)`).

## Contents

Scanned files · What is never a finding · The contract · Run-start procedure · Apply path

## Scanned files

Scanned files: `CLAUDE.md`, `AGENTS.md` and `.claude/CLAUDE.md` at the repo root, every `.project/*.md`, and every `projectDocs` and `standingDocs` path in `.milestone-config/driver.json`.

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

## Run-start procedure

Runs when `--status` prints `due`. Nothing here edits a file.

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/write-cost-record.{sh,ps1} --start <runId>` just before the dispatch: `<runId>` in `solve-issue`, `<milestone id>` in `solve-milestone`.
2. Dispatch `milestone-driver:process-auditor`, tier `sonnet`, with the absolute repo root and this file's absolute path only.
3. Pipe `{"agent":"process-auditor","tier":"sonnet","totalTokens":<subagent_tokens>,"durationMs":<duration_ms>}` to `${CLAUDE_PLUGIN_ROOT}/scripts/write-cost-record.{sh,ps1} --append <runId>`.
4. Branch on the return or the answer; the last column is the value the run holds as `processCheck:`.

| Return or answer | Action | Hold |
|---|---|---|
| Dispatch fails, or no `FINDINGS` block (`CONTRACT NOT FOUND:` included) | One log line | `skipped` |
| `FINDINGS: none` | `--record clean`, silent | `clean` |
| Findings, `MILESTONE_DRIVER_NONINTERACTIVE=1` | One notice: the question's first sentence, then each `change` line | `noticed` |
| Findings, interactive | The question in a `text` fence, each `change` line above `Update all (Recommended)` · `Choose which` · `Not now`; Codex: gate rule in `skills/runtime-codex.md` | Per answer |
| `Not now` | `--record declined` | `declined` |
| `Update all`, or `Choose which` with findings | Hand the findings to the apply path | `updated` |
| `Choose which` with none | Nothing | `declined` |
| Codex not-approved | Nothing | `noticed` |
| `--record` exits nonzero | One log line | The attempted outcome |

`--record <outcome>` means `${CLAUDE_PLUGIN_ROOT}/scripts/process-check.{sh,ps1} --record <outcome> <repo-root>`. Only `Not now` and `FINDINGS: none` record. The question, verbatim:

```text
This project's docs replace part of milestone-driver's current process, which can make builds much slower. Can I update them?
```

## Apply path

Runs when step 4 hands over findings. The run holds each taken finding as `file`, `quote`, `replacement` and edits no file before this session's answer, so a halted run records nothing and the next interactive run asks again. `MILESTONE_DRIVER_NONINTERACTIVE=1` never enters it.

| Answer | Taken |
|---|---|
| `Update all` | Every finding. |
| `Choose which` | One multi-select AskUserQuestion per batch, option label `file`, description the `change` line. n findings split into ceil(n/4) batches whose sizes differ by at most one (5 is 3+2, never 4+1), because a question takes 2 to 4 options. Only n=1 makes a one-finding batch, and that question adds a second option, `Skip it`. Zero selected: `--record declined`, and nothing is edited, committed or opened. |

The path follows the run: `solve-milestone` under `integrationGranularity: "milestone"` takes the milestone path, every other run, a standalone `solve-issue` included, takes the PR path.

Per taken finding, one log line and a skip when `file` matches `sourceGlobs` (the hook denies the edit, `hooks/force-subagent.sh (main-thread edits to source)`), or when `grep -nxF -- '<quote>' <file>` does not match exactly one line (the auditor's own test, `agents/process-auditor.md (grep -nxF)`). Otherwise the Edit tool replaces the quoted line with `replacement`, or removes it with its newline on `DELETE`. No other line is edited. When none lands, nothing is committed, opened or recorded.

**Milestone path.** Runs once `skills/solve-milestone/milestone-granularity.md § Creating the milestone branch: resume-safe pre-clean guard` leaves the milestone branch checked out. Stage the edited paths in one Bash call, commit in the next with subject `chore: update project docs to milestone-driver's current process`, the co-author trailer and no `Issue:` line, push nothing (`skills/solve-milestone/milestone-granularity.md (Push count)`), then `--record updated`.

**PR path.** Runs right after `skills/solve-issue/SKILL.md (Require a clean working tree)` or `skills/solve-milestone/SKILL.md (Confirm the working tree is clean)` passes, before the first issue branch is cut.

1. Require an empty `git status --porcelain` and, after `git fetch`, `git rev-parse <integrationBranch>` equal to `git rev-parse origin/<integrationBranch>`; otherwise one log line, nothing recorded.
2. `git show-ref --verify --quiet refs/heads/chore/driver-process` hit: `git checkout chore/driver-process`; else `git checkout -b chore/driver-process <integrationBranch>`. Make the edits.
3. Stage the edited paths in one Bash call, then `git diff --cached --quiet || git commit -m "chore: update project docs to milestone-driver's current process" -m "<co-author trailer>"` in the next.
4. Zero landed and no open PR: `git checkout <integrationBranch>`, stop before the push, nothing recorded.
5. `git push -u origin chore/driver-process`, then `gh pr list --head "chore/driver-process" --json number --jq '.[0].number // empty'`: a hit reuses that PR, else `gh pr create --base <integrationBranch>` with the same title and body `## Code Review` plus `/code-review run: n/a - no sourceGlobs change`.
6. Wait for CI as `skills/solve-milestone/changelog-authoring.md § 6.8 Handle CI result` does. Green: `body="Code Review: PR #<pr-number>" && title="$(gh pr view <pr-number> --json title --jq .title)" && [ -n "$title" ] && gh pr merge <pr-number> --squash --delete-branch --subject "$title (#<pr-number>)" --body "$body"` in one call (`skills/solve-milestone/simplify-pass.md § Land the findings`), then `git checkout <integrationBranch>`, `git fetch`, `git merge --ff-only origin/<integrationBranch>`, `git branch -d chore/driver-process`, then `--record updated`.
7. Red: apply `needs review` through `skills/setup/SKILL.md (canonical apply-time label helper)`, hold the PR open, keep the local branch, `git checkout <integrationBranch>`, record nothing, and the run continues.

A nonzero `--record` exit logs one line and the run continues.
