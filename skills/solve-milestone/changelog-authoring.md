# CHANGELOG authoring: solve-milestone reference

Loaded only when core `SKILL.md`'s `### 6. Author the CHANGELOG entry` guard passes — clean completion path, zero parked issues. A systemic halt or any park skips step 6 whole and never reads this file. Missing or unreadable once the guard has passed is a **systemic failure**: surface it and halt per core `SKILL.md`'s `## Autonomy` → "Systemic failures that halt the run".

## Contents

6.1 Idempotency check · 6.2 Fetch PR summaries · 6.3 Categorize issues · 6.4 Determine the milestone theme · 6.5 Author the CHANGELOG entry · 6.6 Determine the branch name · 6.7 Open the doc-only PR · 6.8 Handle CI result · 6.9 Surface in the final summary "Your move" section

---

## 6.1 Idempotency check

Match rule by versioning mode:

- **Versioned mode** (`versioning: true` or absent): heading prefix `## v<target-version> ` (with a trailing space).
- **Version-free mode** (`versioning: false`): full-line equality on the trimmed line — strip leading and trailing whitespace (including `\r` on Windows), then require `trim(line) == '## <milestone title>'` with no additional characters. **Suffix caveat, version-free mode only.** A heading carrying any suffix (`## <milestone title> (partial)`, `(in progress)`, a date) is not equal to `## <milestone title>`, so the equality match fails, this check reports no existing entry, and steps 6.2 to 6.5 prepend a second section beside the one already there. Versioned mode is unaffected: its prefix ends in a trailing space, so `## v<target-version> ` still matches `## v1.18.0 (partial)`. Do not widen the match to compensate; the strict equality rule is deliberate.

If `CHANGELOG.md` exists on `integrationBranch`, read it (`git show <integrationBranch>:CHANGELOG.md` or read the working-tree copy after re-sync) and scan each line, from the start of the trimmed line, with the mode's match rule above. Match → log _"CHANGELOG entry for `<version/title>` already exists — skipping."_ and proceed to core `SKILL.md`'s `## Run-complete notification` section. No match → continue. `CHANGELOG.md` absent → treat as "no existing entry" and continue.

## 6.2 Fetch PR summaries

For each issue merged in this run, look up its PR number from the **run's in-context issue→PR tracking table**. If that PR number is not in active context, fall back to the issue's closing PR references:

```bash
gh issue view <n> --json closedByPullRequestsReferences --jq '.closedByPullRequestsReferences | map(select(.state == "MERGED")) | .[0].number // empty'
```

Before calling `gh pr view`, verify the PR number returned by the query is non-null and non-empty. Null or empty (no linked PR) → use the issue title as that issue's What-column content, skip `gh pr view`, and record the gap in the run output: _"No merged PR found for issue #N — using issue title as summary."_

With a valid PR number confirmed:

```bash
gh pr view <pr-number> --json title,body
```

Extract the summary line:

1. Look for a `## Summary` heading in the body (case-insensitive match on the heading text).
2. Take the **first non-blank line** immediately following that heading.
3. No `## Summary` section → fall back to the PR title.

Record a triple per issue: `{ issue: #N, pr: #P, summary: "<extracted line>" }`.

## 6.3 Categorize issues

Group the merged issues into two buckets by label and title prefix:

- **✨ Features / enhancements:** label `enhancement` or `feature`, or title prefix `feat(` / `polish(`. An issue matching neither bucket defaults here.
- **🔧 Fixes:** label `bug` or `fix`, or title prefix `fix(`. An issue belongs to exactly one bucket; matching both prefers this one.

## 6.4 Determine the milestone theme

1. Read the milestone description: `gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '.description'`.
2. Look for a dedicated theme line (starting `Theme:` or `**Theme:**`); the text after the prefix is the one-sentence theme description.
3. No theme line → use the milestone title as both the heading theme and the theme description.

## 6.5 Author the CHANGELOG entry

Construct the block below, mirroring the v1.7.0 entry in `CHANGELOG.md` exactly — same heading format, same table schema, same section names. **Versioned mode entry:**

```markdown
## v<target-version> — <milestone theme>

**Theme:** <one-sentence theme description>

### ✨ <Feature category label>

| Issue | PR | What |
|---|---|---|
| #N <issue title> | #P | <summary line> |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #N <issue title> | #P | <summary line> |

### Consumer notes (upgrading from <prev version>)

- <upgrade-relevant behavior changes, new artifacts, schema impact>
- **No schema changes** to `.milestone-config/driver.json` (include this line only when true)

### ⚖️ Post-run audit trail

Judgment-call PRs: <comma-separated list of PRs with `judgment call` label, or "none">.

- <open defect with its issue number>
- <what a shipped gate does not verify>
- <ceiling or budget state the next edit hits>
```

**Version-free mode entry:** the block above with exactly two lines changed — the entry heading becomes `## <milestone title>` (no version, no ` — <milestone theme>` suffix) and the Consumer notes heading becomes `### Consumer notes` (no prev-version parenthetical). Every other line, including both tables and the ⚖️ Post-run audit trail section, is identical.

Rules for authoring the entry:

- **Shape.** This entry becomes the GitHub release body, so it is GitHub-facing prose: author it to the CHANGELOG-entry row of `skills/output-style.md § Evidence slots`, which defines every slot — theme, the per-bucket lines and their evidence, Consumer notes, the ⚖️ audit trail — and names what is not one. That row is authoritative for both lists; the bullets below say where they apply, never what they contain. A bucket line with no issue/PR reference is an unfilled slot, not a tighter entry.
- **The non-slot list applies hardest to the `What` cell.** That cell states what shipped and how it behaves; a fact the row excludes as a non-slot survives into it only when a reader's next action depends on it.
- **Cut pass before writing.** Delete every sentence that changes nothing a reader would type, configure, or expect.
- Omit the `### 🔧 Fixes` section entirely if there are no fix-bucket issues.
- Omit the `### ✨` section entirely if there are no feature-bucket issues (unusual, but possible).
- Feature category label: derive from the milestone theme or title (e.g. "Background orchestration", "Scannable output"). If none is obvious, use "Features / enhancements".
- Consumer notes: summarize new profile keys, changed behavior, new gitignored artifacts, schema changes — authored from what was actually built. Include the "No schema changes" line only when confirmed true.
- Post-run audit trail: list PRs carrying the `judgment call` label **from this run's in-context issue→PR tracking set** (do NOT re-query `gh pr list`; read from context); write "none" if the list is empty. Then the fact list, one bullet each: an open or unfixed defect with its issue number, a dropped acceptance criterion stated as what the shipped gate does NOT verify, a ceiling or budget state a contributor's next edit hits. Omit the fact list entirely when there are none of those facts.
- Prev version for the Consumer notes header: derive from the most recent `## v...` heading already in `CHANGELOG.md`. If CHANGELOG is absent or contains no `## v...` heading, use `git log --oneline --all -- CHANGELOG.md` to find the most recent commit that touched CHANGELOG.md, then run `git show <commit>:CHANGELOG.md | grep '^## v' | head -1` to extract the most recent version heading from history. If no prior CHANGELOG exists in history, omit the prev-version parenthetical and use simply `### Consumer notes`. Do NOT use `plugin.json` as a fallback — `plugin.json` holds the target version, not the previous one.

**Prepend the entry** into `CHANGELOG.md` after the file header (the `# Changelog` line and any intro prose preceding the first `## v...` entry) but before that first `## v...` entry. Preserve the file header verbatim. If `CHANGELOG.md` is absent on `integrationBranch`, create one with a standard `# Changelog` header and intro paragraph, then append the new entry below. To retrieve an existing structure as a template, find the most recent commit that touched the file with the `git log` command in the prev-version rule above, then run `git show <commit>:CHANGELOG.md`. If no prior version exists in history, use a minimal header (`# Changelog` followed by a blank line).

- **Milestone granularity: steps 6.6 to 6.8 do not run.** Under `integrationGranularity: "milestone"` the entry authored above is committed onto the milestone branch instead: no `docs/changelog-<slug>` branch is cut and no second PR is opened. Run `milestone-granularity.md § Milestone end: one push, one PR, one CI run` in their place (it also owns the red-CI handler), then continue at step 6.9 below.

## 6.6 Determine the branch name

- **Versioned mode:** `docs/changelog-v<target-version>` (e.g. `docs/changelog-v1.8.0`)
- **Version-free mode:** `docs/changelog-<milestone-slug>`, where slug = milestone title lowercased, spaces replaced by hyphens, non-alphanumeric characters (except hyphens) removed (e.g. milestone "Q3 Hardening" → `docs/changelog-q3-hardening`)

## 6.7 Open the doc-only PR

Cut the branch from the current `integrationBranch` tip — this step re-syncs inline, so do not rely on a prior re-sync:

```bash
# Ensure integrationBranch is current before cutting the docs branch
git checkout <integrationBranch>
git fetch
git merge --ff-only origin/<integrationBranch>
# Guard: if the docs branch already exists from a prior interrupted run, check it out instead of creating a new one
if git show-ref --verify --quiet refs/heads/docs/changelog-<slug>; then
  git checkout docs/changelog-<slug>
elif git ls-remote --exit-code origin docs/changelog-<slug> > /dev/null 2>&1; then
  git checkout --track origin/docs/changelog-<slug>
else
  git checkout -b docs/changelog-<slug> <integrationBranch>
fi
# edit CHANGELOG.md as authored in step 6.5
git add CHANGELOG.md
# Run exactly ONE of the next two lines: the first when `versioning` is true or absent, the second (uncommented) when `versioning: false`.
git diff --cached --quiet || git commit -m "docs: v<version> release notes"           # VERSIONED MODE
# git diff --cached --quiet || git commit -m "docs: <milestone-title> release notes"  # VERSION-FREE MODE
git push -u origin docs/changelog-<slug>
# Check if a PR already exists for this branch (re-run safety)
existing_pr=$(gh pr list --head "docs/changelog-<slug>" --json number --jq '.[0].number // empty' 2>/dev/null)
if [ -n "$existing_pr" ]; then
  echo "CHANGELOG PR already open: #$existing_pr"
else
  # PR title: the same versioned / version-free form as the commit message above.
  gh pr create \
    --base <integrationBranch> \
    --title "docs: <title>" \
    --body "$(cat <<'EOF'
## CHANGELOG preview

<paste the authored CHANGELOG entry verbatim here>

---

_This entry doubles as the GitHub-release body for the human release step._

## Code Review

- /code-review run: no — doc-only CHANGELOG entry, no executable surface.
- Findings: 0
  - none
- Evidence: every entry row carries its issue and its merged PR, bucketing matches each issue's label and title prefix, structure matches the prior `## v...` entry, the ⚖️ audit-trail line is present.
- No park-triggering findings.
EOF
)"
fi
```

The `## Code Review` heading is required — without it `hooks/code-review-gate.sh` denies this `gh pr create` and step 6.8's `gh pr merge`. Confirm each evidence claim against the authored entry before pasting.

Record the PR number and URL — the newly created PR, or the existing one the re-run guard found.

## 6.8 Handle CI result

The PR is doc-only; CI is typically vacuously green. Immediately attempt:

```bash
gh pr merge <pr-number> --squash --delete-branch
```

- **Success (CI green or no CI):** record _"CHANGELOG entry merged."_ and record the merge for the final summary. Then clean up the working tree:

  ```bash
  git checkout <integrationBranch>
  git fetch
  git merge --ff-only origin/<integrationBranch>   # git fetch alone does not advance the local ref
  git branch -d docs/changelog-<slug>
  ```

- **CI red:** do **not** block or fail the run. Apply the `needs review` label to the CHANGELOG PR (`gh pr edit <pr-number> --add-label "needs review"`). Add a 🔴 item to the run output:

  > 🔴 CHANGELOG PR needs human merge (CI red): #P — <pr-url>

  Return to `integrationBranch` but preserve the local `docs/changelog-<slug>` branch:

  ```bash
  git checkout <integrationBranch>
  # do NOT delete the local docs/changelog-<slug> branch — remote PR is still open
  ```

  Do NOT re-attempt the merge. Proceed to step 6.9, exactly as the merged branch does.

## 6.9 Surface in the final summary "Your move" section

**Output ordering:** the Template 3 final summary MUST NOT be emitted until step 6 completes. Hold it in-context through steps 6.1–6.8, add one line to its `🔴 Your move:` list, then emit the complete Template 3:

- **Merged:** `CHANGELOG entry merged → use as GitHub release body (#P)`
- **Held open (CI red):** `🔴 CHANGELOG PR needs human merge (CI red): #P`

**Label collision note:** A CHANGELOG PR carrying the `needs review` label is surfaced in the `🔴 Your move:` list only — it must NOT appear in the `👁️ open` rows of Template 3. The Final summary's "Open UI PRs awaiting human merge" bullet is scoped to PRs opened for issues in this run's issue set (cross-referenced against the run's in-context issue→PR tracking table), not all `needs review` PRs in the repo.
