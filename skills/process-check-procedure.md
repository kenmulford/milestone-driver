# Process-check procedure - shared reference

What a run does when `scripts/process-check.{sh,ps1} --status` prints `due`, and later with the findings taken, against the contract in `skills/process-check.md`. It is a separate file because those scripts hash the contract, so a wording edit here changes no marker. It is read only when a check is due or a pending file exists, so it joins no skill's unconditional load closure (`scripts/check-size-budgets.sh (MEMBERSHIP RULE, and the only one)`).

## Contents

Run-start procedure · Apply path

## Run-start procedure

Runs at `skills/solve-issue/SKILL.md` step 3.4 or `skills/solve-milestone/SKILL.md` step 4.1, once the run's `<runId>` is known: the feature branch, or the milestone id. It edits no file. The findings taken go to the pending file `<main-repo-root>/.milestone-config/.runtime/process-check-pending.json` (`<main-repo-root>` is the parent of `git rev-parse --path-format=absolute --git-common-dir`, so every worktree shares it), and `solve-issue` step 3.5 applies them on the feature branch.

Callers run `--status` first. On `due`, read `<main-repo-root>/.milestone-config/.runtime/process-check-pending.json` before step 1. Absent: go on to step 1.
- `"issue": <n>`: read `gh issue view <n> --json state,stateReason`.
  - `CLOSED`, any `stateReason`: delete the file, keep its `declined` list, and go on to step 1. A hand-closed issue or an unlanded edit must not read as done, so the audit runs.
  - `OPEN`, or `gh` fails: log one line naming the issue and the file (delete it to re-check), hold `skipped`, and end the procedure.
- `"issue": null`: hold `updated`, and end the procedure; step 3.5 applies the file.

1. Dispatch `milestone-driver:process-auditor`, tier `sonnet`, with the absolute repo root, the absolute path of `skills/process-check.md` and `integrationGranularity: <the run's resolved value>`, nothing else.
2. Record the dispatch as `skills/solve-issue/SKILL.md § Run-end cost record (additive, never-gating)` does (`skills/solve-milestone/SKILL.md (Append, per dispatch, as it returns)` in a milestone run), with `agent: process-auditor` and `tier: sonnet`. When this is the run's first dispatch, that section's `--start` runs before it.
3. Drop each finding whose `file` and `quote` match a kept `declined` entry; none left is `FINDINGS: none`. Branch on the return or the answer; the last column is the held `processCheck:`.

| Return or answer | Action | Hold |
|---|---|---|
| Dispatch fails, or no `FINDINGS` block (`CONTRACT NOT FOUND:` included) | One log line | `skipped` |
| `FINDINGS: none` | `--record clean`, silent | `clean` |
| Findings, `MILESTONE_DRIVER_NONINTERACTIVE=1` or a `--driven` run | One notice: the question's first sentence, then each `change` line | `noticed` |
| Findings, interactive | One AskUserQuestion: the question in a `text` fence, each `change` line above its options `Update all (Recommended)` · `Choose which` · `Not now`; Codex: gate rule in `skills/runtime-codex.md` | Per answer |
| `Not now` | `--record declined` | `declined` |
| `Update all` | Write every finding to the pending file. | `updated` |
| `Choose which` | Take the findings selected below. At least one: write them to the pending file. None, across every batch or by `Skip it`: `--record declined`. | `updated`, or `declined` for none |
| Codex not-approved | Nothing | `noticed` |
| `--record` exits nonzero | One log line | The attempted outcome |

`--record <outcome>` means `${CLAUDE_PLUGIN_ROOT}/scripts/process-check.{sh,ps1} --record <outcome> <repo-root>`. The question, verbatim:

```text
This project's docs replace part of milestone-driver's current process, which can make builds much slower. Can I update them?
```

**Choose which.** One multi-select AskUserQuestion per batch, option label `<k>. <file>` with `<k>` the finding's position in the auditor's return, counted from 1, so two findings in one file stay distinct, and description the `change` line. Answers map back by `<k>`. n findings split into ceil(n/4) batches whose sizes differ by at most one (5 is 3+2, never 4+1), because a question takes 2 to 4 options. Only n=1 makes a one-finding batch, and that question adds a second option, `Skip it`.

**The pending file** is written with the Write tool, after `mkdir -p` of its directory, at `<main-repo-root>/.milestone-config/.runtime/process-check-pending.json`, as one JSON object with JSON-escaped strings: `{"findings":[{"file":"<repo-relative path>","quote":"<line>","replacement":"<line | DELETE>"}],"declined":[{"file":"<path>","quote":"<line>"}],"issue":null}`. `declined` holds every finding of the auditor's return that `findings` lacks, so no later audit asks again.

## Apply path

Runs at `skills/solve-issue/SKILL.md` step 3.5, on the feature branch, when the pending file exists with `"issue"` `null` or equal to the issue being built, so a rebuilt issue re-applies. It commits nothing: the edits ride the issue's own commit, as the profile migration rides its PR. Each edit is made at `<worktree>/<file>`, or `<repo-root>/<file>` when there is no worktree. A non-interactive run writes no file but applies a `null` one an earlier run left.

Per finding, one log line and a skip for each failed test:

1. Read the file at its absolute edit path before the Edit.
2. Skip when `file` matches `sourceGlobs`: the hook denies the edit (`hooks/force-subagent.sh (main-thread edits to source)`).
3. Skip unless `tr -d '\r' < <edit-path> | grep -cxF -f <quote-file>` prints 1 (the auditor's own test, `agents/process-auditor.md (grep -cxF)`). `<quote-file>` is under `<main-repo-root>/.milestone-config/.runtime/process-check/`, holds the quote, and is written by quoted heredoc, as a quote can hold `'`. `tr` makes a CRLF file match.
4. One Edit. A break is the file's own line ending. `old_string` is the break before the quoted line, the line and the break after it; line 1 has no break before it, and an unterminated last line has none after it, so the match cannot start inside a longer line. `new_string` keeps the same breaks around `replacement`. On `DELETE` it is the one break that joined the line to its neighbors, empty when the line had only one.

A failed Edit is logged and skipped like the rest. After the last finding, set `"issue": <n>` in the pending file. Delete the file and run `--record declined` only when `"issue"` was `null` and every finding was skipped: a re-apply on the same issue whose quotes are already gone keeps the file.
