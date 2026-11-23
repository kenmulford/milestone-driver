# Process-check procedure - shared reference

What a run does when `scripts/process-check.{sh,ps1} --status` prints `due`, against the contract in `skills/process-check.md`. It is a separate file because those scripts hash the contract, so a wording edit here changes no marker. It is read only when a check is due, so it joins no skill's unconditional load closure (`scripts/check-size-budgets.sh (MEMBERSHIP RULE, and the only one)`).

## Contents

Run-start procedure · Apply path

## Run-start procedure

Nothing here edits a file. A run that takes the PR path (`## Apply path`) first runs `gh pr list --head chore/driver-process --state open --json url`. A hit means an earlier run's PR awaits a human merge: log one line naming it, hold `skipped`, and leave this procedure with no dispatch, no question and nothing recorded, so the run continues. No hit, or a failed `gh`, goes on to step 1.

1. Dispatch `milestone-driver:process-auditor`, tier `sonnet`, with the absolute repo root and the absolute path of `skills/process-check.md` only.
2. Record the dispatch as `skills/solve-issue/SKILL.md § Run-end cost record (additive, never-gating)` does (`skills/solve-milestone/SKILL.md (Append, per dispatch, as it returns)` in a milestone run), with `agent: process-auditor` and `tier: sonnet`. When this is the run's first dispatch, that section's `--start` runs before it.
3. Branch on the return or the answer; the last column is the value the run holds as `processCheck:`.

| Return or answer | Action | Hold |
|---|---|---|
| Dispatch fails, or no `FINDINGS` block (`CONTRACT NOT FOUND:` included) | One log line | `skipped` |
| `FINDINGS: none` | `--record clean`, silent | `clean` |
| Findings, `MILESTONE_DRIVER_NONINTERACTIVE=1` | One notice: the question's first sentence, then each `change` line | `noticed` |
| Findings, interactive | The question in a `text` fence, each `change` line above `Update all (Recommended)` · `Choose which` · `Not now`; Codex: gate rule in `skills/runtime-codex.md` | Per answer |
| `Not now` | `--record declined` | `declined` |
| `Update all`, or `Choose which` | Hand the findings to the apply path | `updated`, or `declined` when the apply path's zero-selected row applies |
| Codex not-approved | Nothing | `noticed` |
| `--record` exits nonzero | One log line | The attempted outcome |

`--record <outcome>` means `${CLAUDE_PLUGIN_ROOT}/scripts/process-check.{sh,ps1} --record <outcome> <repo-root>`. The question, verbatim:

```text
This project's docs replace part of milestone-driver's current process, which can make builds much slower. Can I update them?
```

## Apply path

Runs when step 3 hands over findings. The run holds each taken finding as `file`, `quote`, `replacement` and edits no file before this session's answer, so a halted run records nothing and the next interactive run asks again. `MILESTONE_DRIVER_NONINTERACTIVE=1` never enters it.

| Answer | Taken |
|---|---|
| `Update all` | Every finding. |
| `Choose which` | One multi-select AskUserQuestion per batch, option label `file`, description the `change` line. n findings split into ceil(n/4) batches whose sizes differ by at most one (5 is 3+2, never 4+1), because a question takes 2 to 4 options. Only n=1 makes a one-finding batch, and that question adds a second option, `Skip it`. Zero selected: `--record declined`, and nothing is edited, committed or opened. |

The path follows the run: `solve-milestone` under `integrationGranularity: "milestone"` takes the milestone path, every other run takes the PR path, a `solve-milestone` hand-off to an `md-epic` parent included (no milestone branch exists then).

Per taken finding, one log line and a skip when `file` matches `sourceGlobs` (the hook denies the edit, `hooks/force-subagent.sh (main-thread edits to source)`), or when `tr -d '\r' < <file> | grep -cxF -f <quote-file>` does not print 1 (the auditor's own test, `agents/process-auditor.md (grep -cxF)`). `<quote-file>` holds the quote, written by quoted heredoc as it can hold `'`; `tr` makes a CRLF file match. Otherwise one Edit: `old_string` is the quoted line plus its own trailing line break, so it cannot match inside a longer line, and `new_string` is `replacement` plus that same break, empty on `DELETE`, so the file keeps its line ending. A failed Edit is logged and skipped like the other skips. When none lands, nothing is committed, opened or recorded.

**Milestone path.** Runs once `skills/solve-milestone/milestone-granularity.md § Creating the milestone branch: resume-safe pre-clean guard` leaves the milestone branch checked out. Stage the edited paths in one Bash call, commit in the next with subject `chore: update project docs to milestone-driver's current process`, the co-author trailer and no `Issue:` line, push nothing (`skills/solve-milestone/milestone-granularity.md (Push count)`), then `--record updated`.

**PR path.** Runs right after `skills/solve-issue/SKILL.md (Require a clean working tree)` or `skills/solve-milestone/SKILL.md (Confirm the working tree is clean)` passes, before the first issue branch is cut; on an `md-epic` parent path, where neither runs, at the point `skills/solve-issue/md-epic-fanout.md` or `skills/solve-milestone/md-epic-parent-check.md` names. `git status --porcelain` must print nothing before 6.7's first checkout, as a resumed `issue/<n>-*` branch skips that check; otherwise log one line and record nothing. Land it as `skills/solve-milestone/changelog-authoring.md § 6.7 Open the doc-only PR` and `§ 6.8 Handle CI result` land the docs branch, the way `skills/solve-milestone/simplify-pass.md § Land the findings` does for `chore/simplify-<slug>`, with these differences:

- The branch is `chore/driver-process`, and the edits are made on it after 6.7's branch step.
- An already-open `chore/driver-process` PR ends the run-start procedure before the question, so this path never opens a second PR.
- Stage only the edited paths in one Bash call, never `CHANGELOG.md`: 6.7's `git add CHANGELOG.md` stages nothing and `gh pr create` fails (`skills/solve-milestone/simplify-pass.md § Land the findings`). Commit in the next call. The commit and the PR title carry the subject `chore: update project docs to milestone-driver's current process`, and the commit the co-author trailer.
- The PR body is `## Code Review` plus `/code-review run: n/a - no sourceGlobs change`, and the merge body the Code-Review-only line.
- No edit landed and no PR open: `git checkout <integrationBranch>`, no push, nothing recorded.
- Green: log `Process-check PR merged.`, and after 6.8's cleanup `--record updated`.
- Red: 6.8's red leg with its 🔴 line replaced by `🔴 Process-check PR needs human merge (CI red): #P - <pr-url>`, nothing recorded.
- Either way the run continues to its next run-start step, never to 6.9.
