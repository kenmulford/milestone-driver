# Process-check procedure - shared reference

What a run does around `scripts/process-check.{sh,ps1} --status`, and when it prints `due`, against the contract in `skills/process-check.md`. It is a separate file because those scripts hash the contract, so a wording edit here changes no marker. It is read only when a check is due, so it joins no skill's unconditional load closure (`scripts/check-size-budgets.sh (MEMBERSHIP RULE, and the only one)`).

## Contents

Lifecycle · Run-start procedure · Filing the issue

## Lifecycle

The check edits no file. An accepted answer files one GitHub issue that carries the selected findings as its edit points, and the driver builds that issue like any other, so every instruction-file change goes through the issue pipeline. `<main-repo-root>` is `git -C <repo-root> rev-parse --show-toplevel` when `--git-dir` and `--git-common-dir` agree else the first `worktree ` entry of `git -C <repo-root> worktree list --porcelain` (a linked worktree); git failing, rev-parse output of other than two lines, or no entry → `<repo-root>`. A linked worktree and the main checkout share both files under `<main-repo-root>/.milestone-config/.runtime/`: the marker `process-check.json`, written only by `--record`, and `process-check-declined.json`, findings turned down, which the scripts hash. `--record <outcome>` means `${CLAUDE_PLUGIN_ROOT}/scripts/process-check.{sh,ps1} --record <outcome> <repo-root>`, outcome `clean` or `declined`. The last column is the held `processCheck:` (`current`, `clean`, `noticed`, `declined`, `skipped`, `filed #<n>`); "no hold" is none held. Filing records nothing, so the marker stays `due`: while the issue is open the check skips (L3), and once it closes the next `due` run re-audits, where landed lines audit clean.

| # | State and event | Action | Files written | Hold |
|---|---|---|---|---|
| L1 | Step 3.4 or 4.1, a `processCheck:` already held | Skip the check | none | unchanged |
| L2 | Step 3.4 or 4.1, no hold, and a resume path (a) to (c), `git rev-parse HEAD` differing from `git rev-parse <integrationBranch>`, or a non-empty `git status --porcelain` (path (d) cuts a clean tip) | One log line; no audit | none | `skipped` |
| L3 | The open-issue lookup prints a number | One log line naming it; no audit | none | `skipped` |
| L4 | The open-issue lookup fails | One log line; go on to `--status` | none | no hold |
| L5 | `--status` exits nonzero | One log line | none | `skipped` |
| L6 | `--status` prints `current` | Nothing | none | `current` |
| L7 | `--status` prints `due`, this file is unreadable | One log line | none | `skipped` |
| L8 | `due`, the dispatch fails or returns no `FINDINGS` block (`CONTRACT NOT FOUND:` included) | One log line | none | `skipped` |
| L9 | `due`, `FINDINGS: none` or none left after step 3's filter | `--record clean`, silent | marker | `clean` |
| L10 | `due`, findings left, `MILESTONE_DRIVER_NONINTERACTIVE=1` or a `--driven` run | One notice: the question's first sentence, then each `change` line | none | `noticed` |
| L11 | `due`, findings left, interactive, Codex gate not approved | Step 4.1: one notice, as L10. Step 3.4: end the turn with a `🔴` pending line (`skills/runtime-codex.md § Human gates`); approval next turn takes L12 to L15 | none | Step 4.1 `noticed`; step 3.4 no hold |
| L12 | Question asked: `Update all`, or `Choose which` with at least one finding selected, and `gh issue create` exits 0 | File the issue (`## Filing the issue`); `Choose which` appends the unselected to the declined file; `--record` is not called | declined, when findings were unselected | `filed #<n>` |
| L13 | Question asked, as L12, and `gh issue create` exits nonzero | One log line; `Choose which` still appends the unselected | declined, when findings were unselected | `skipped` |
| L14 | `Choose which`, none selected | Append every finding to the declined file; `--record declined` | declined, marker | `declined` |
| L15 | `Not now` or any other answer (free text, dismissed) | `--record declined`; appends nothing, so a changed scanned file asks again | marker | `declined` |
| L16 | Any `--record` call exits nonzero (L9, L14, L15) | One log line | none | the attempted outcome |
| L17 | The declined-file Write or `mkdir -p` fails (L12, L13, L14) | One log line; skip the append | none | L12's `filed #<n>`, L13's `skipped`, L14's `declined` |
| L18 | The declined file is not `{"declined":[...]}` (step 3's read, an append) | Reads as empty; an append rewrites it from empty | declined | the base row's hold stands |

## Run-start procedure

Runs at `skills/solve-issue/SKILL.md` step 3.4 or `skills/solve-milestone/SKILL.md` step 4.1, once the run's `<runId>` is known: the feature branch, or the milestone id. L2 makes the working tree at `<repo-root>`, which the audit reads, a clean checkout of the tip of `<integrationBranch>`. The caller has run the open-issue lookup and `--status` (L3 to L6) and reads this file on `due`; take steps 1 to 3.

1. Dispatch `milestone-driver:process-auditor`, tier `sonnet`, with the absolute repo root and the absolute path of `skills/process-check.md`, nothing else.
2. Record the dispatch as `skills/solve-issue/SKILL.md § Run-end cost record (additive, never-gating)` does (`skills/solve-milestone/SKILL.md (Append, per dispatch, as it returns)` in a milestone run), with `agent: process-auditor` and `tier: sonnet`. When this is the run's first dispatch, that section's `--start` runs before it.
3. Drop each finding whose `file` matches `sourceGlobs` (the project's code, not an instruction file) and each whose `file` and `quote` match a declined-file entry (absent or malformed, L18, is empty). Take the L row for what is left. Interactive findings go in one AskUserQuestion: the question in a `text` fence, each `change` line above its options `Update all (Recommended)` · `Choose which` · `Not now`; Codex: L11.

The question, verbatim:

```text
This project's docs replace part of milestone-driver's current process, which can make builds much slower. Can I update them?
```

**Choose which.** One multi-select AskUserQuestion per batch, option label `<k>. <file>` with `<k>` the finding's position in the auditor's return, counted from 1 and description the `change` line. n findings split into ceil(n/4) batches whose sizes differ by at most one (5 is 3+2, never 4+1), because a question takes 2 to 4 options. Only n=1 makes a one-finding batch, and that question adds a second option, `Skip it`; selected beside the finding, the finding wins. A dismissed or free-text batch counts as nothing selected from it, and a finding no batch selected is unselected (L12, L14).

**The declined file** is `{"declined":[{"file":"<path>","quote":"<line>"}]}`, written with the Write tool as the whole file after `mkdir -p` of its directory: read it, add each `file` and `quote` pair it lacks, write it back. `file` and `quote` are JSON-escaped strings: quote, backslash and control characters escaped. Nothing deletes it; deleting it makes declined findings eligible again.

## Filing the issue

L12 runs `gh issue create` once, for the selected findings in the auditor's order:

| Part | Value |
|---|---|
| Title | `Update the project's process docs to match milestone-driver <plugin version>`, the version from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` |
| Label | `process-check` only; run `gh label create "process-check" --color C5DEF5 --description "Instruction-file edits the driver's process check proposed" --force` first (`skills/setup/SKILL.md (Apply-time label helper (for consuming skills))`) |
| Milestone | Under `solve-milestone`, `--milestone "<resolved title>"`: filed before `solve-milestone` step 1 lists open issues, so triage and the build take it this run. Standalone `solve-issue`, `gh api repos/{owner}/{repo}/issues/<n> --jq 'select(.milestone.state == "open").milestone.title'` for the current issue; a title → `--milestone` that title, none (no milestone or a closed one) → no flag. The standalone run builds nothing from it |
| Body | Written with the Write tool to `<main-repo-root>/.milestone-config/.runtime/process-check/issue-body.md` after `mkdir -p` of that directory, passed as `--body-file` |

The body is a one-line purpose, then `Edit points:`, then `Tests:`, each a top-level list item whose first line has text after the colon, which the skip rule requires, and one sub-item per finding. A quote or replacement holding a backtick sits in a code span fenced by one more backtick than its longest run, padded with one space on each side when the content begins or ends with a backtick. `solve-issue` step 2 reads the two items and dispatches no planner (`skills/solve-issue/SKILL.md` step 2's `Edit points:` and `Tests:` rule).

```text
Replace or delete the lines in this project's instruction files that restate or replace a milestone-driver step.

- Edit points: one edit per finding
  - `<file>`: replace the line `<quote>` with `<replacement>`
- Tests: one check per finding, its files scratch under `<main-repo-root>/.milestone-config/.runtime/process-check/` (gitignored, not committed)
  - `<file>`: write the quote to `quote-<k>.txt` and the replacement to `replacement-<k>.txt` there (Write tool), then Bash `tr -d '\r' < "<file>" | grep -cxF -f "<quote-file>"` or PowerShell `@([IO.File]::ReadAllLines("<file>") | Where-Object { [string]::Equals($_.TrimEnd([char]13), $q, 'Ordinal') }).Count` with `$q = [IO.File]::ReadAllText("<quote-file>").TrimEnd([char]13,[char]10)` prints 0, and the same with the replacement file prints at least 1
```

`<k>` is as in **Choose which**, and `<main-repo-root>` is written as its absolute path. A `DELETE` finding reads `<file>`: delete the line `<quote>`, and its test ends after `prints 0`. On exit 0, hold `filed #<n>` from the printed URL; a standalone run also prints `Filed #<n>; this run does not build it.` On nonzero, L13.
