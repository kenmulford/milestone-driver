# Simplify pass: solve-milestone reference

Loaded once per run from core `SKILL.md`'s `### Simplify pass`, after step 4's loop exhausts and before `### 5. Finish`. Both execution modes converge there and reach it exactly once, so the pass runs once per run: never per Wave, never per issue. A systemic-halt run never reaches it. **The pass never gates, blocks, or reverts.** Every failure below logs one line and the run proceeds (`.project/design-philosophy.md#Error & failure philosophy`), this file being missing or unreadable included.

## Contents

The ordered sequence · Resolve the target, and re-sync it · Run it on this main line, apply its fixes through a subagent · Land the findings · The Code Review block · Surface it

---

## The ordered sequence

**Every branch operation precedes the first write.** Run these in this order and no other.

| # | Step | Detail |
|---|---|---|
| 1 | Resolve `<target>` | from the granularity resolved at run start, per the next section |
| 2 | Re-run guard | milestone path: `git log <target> --grep='^Simplify-Pass: ' --format=%H`. PR path: `gh pr list --head "chore/simplify-<milestone-slug>" --state all --json number --jq '.[0].number // empty'`. Either one hitting: log one line, end the pass |
| 3 | Re-sync `<target>` | `integrationBranch` only; a failure ends the pass here |
| 4 | Diff | `git diff <milestoneBaseCommit>...<target>`, read-only |
| 5 | Findings | `/simplify` on this main line, taken only as far as its review output |
| 6 | Zero findings, or a failure | log one line, end the pass |
| 7 | Cut the branch | PR path only: `git checkout -b chore/simplify-<milestone-slug> <integrationBranch>`. **The last branch operation** |
| 8 | Apply the fixes | dispatch the `implementerAgent`. **The first write** |
| 9 | Review | `/code-review` over the resulting working tree, at the classifier's own verdict, per `## The Code Review block` |
| 10 | Stage | one Bash call |
| 11 | Commit | the next Bash call |
| 12 | Publish | PR path: push, `gh pr create`, merge on green. Milestone path: neither, that commit is the whole footprint |

**The guard precedes the re-sync.** It is read-only on both paths and needs no synced local branch: `gh pr list` is a remote query, and step 3 does not run at all on the milestone path.

## Resolve the target, and re-sync it

**Resolve `<target>` once, at step 1.** It is the branch the milestone's work has accumulated on: the same parameter the merge tail already carries, whose third value milestone granularity supplies (`skills/solve-milestone/milestone-granularity.md (milestone granularity adds the)`).

| `integrationGranularity` | `<target>` |
|---|---|
| `"issue"` (default) | `integrationBranch` |
| `"wave"` | `integrationBranch` (`skills/solve-milestone/integration-granularity.md (Wave-branch disposition + re-sync)`) |
| `"milestone"` | the milestone branch `milestone-<number>-<slug>` (`skills/solve-milestone/milestone-granularity.md § Branch model`) |

**Step 3 applies only when `<target>` is `integrationBranch`.** The loop re-syncs that branch before the next issue (`skills/solve-milestone/sequential-loop.md (Ensure the local build target is current)`) and before the next Wave (`skills/solve-milestone/integration-granularity.md (re-sync the local)`), so the run's **last** merge is on `origin` and not yet local. Diffing without this misses the most recently written code in the milestone, and on a single-issue milestone misses all of it. Under `"milestone"` run none of the three: that branch is local-only and already current, nothing having been pushed (`skills/solve-milestone/sequential-loop.md (already current because nothing is pushed)`).

```bash
git checkout <integrationBranch>
git fetch
git merge --ff-only origin/<integrationBranch>
```

**A non-zero exit on any of the three ends the pass at step 3**, with its own log line naming the re-sync as the reason. The range cannot be trusted after a failed re-sync, and step 6's line would report a clean pass over a stale diff: that is the one failure here which must not share a log line with zero findings.

**Step 4 takes three dots, never two.**

## Run it on this main line, apply its fixes through a subagent

Run `/simplify` on the orchestrator's own main line, **never as a dispatched agent**, mirroring `skills/solve-issue/SKILL.md (The orchestrator runs this review itself, dispatching the reviewers directly as leaves)`. It fans out four cleanup agents concurrently, so a dispatched pass seats all four at depth 2, where a completion notification never arrives and the pass strands (`docs/architecture.md` → `## Dispatch topology`).

**Step 5 stops at that review output; step 8 does the applying.** `/simplify` has its **caller** apply each finding, and those edits are main-thread writes: `hooks/force-subagent.sh` is `PreToolUse` on `Write|Edit|MultiEdit|NotebookEdit`, exits 0 only for input carrying an agent identity, and so denies every one landing under `sourceGlobs` at exit 2 (`hooks/force-subagent.sh (main-thread edits to source)`). The command exposes no findings-only flag, so **the stopping point is a rule here, not an argument there**: do not carry out its apply phase on this line, and do not collapse steps 5 and 8 back together. A collapsed pass takes that denial into step 6's failure line and logs a dead feature as a failed run.

Brief the `implementerAgent` once with the findings, the diff range, and the expected file scope; it returns an uncommitted working tree, commits nothing, pushes nothing, opens nothing. Route **every** fix through that one dispatch, including a fix landing outside `sourceGlobs` where the gate would have allowed a main-line edit: one rule, not two.

## Land the findings

**Steps 10 and 11 are two Bash calls, never one.** Never `git add … && git commit …` together (`skills/solve-issue/post-fix-commit.md (stage in one Bash call, then)`).

**Name the window, and do not overstate it.** The commit subject and the PR title are both `chore: /simplify pass over the integration window`, and the body's `## Simplify pass` block opens with the exact range `<milestoneBaseCommit>...<target>`.

**PR path (`<target>` is `integrationBranch`).** Branch `chore/simplify-<milestone-slug>`, the slug rule of `skills/solve-milestone/changelog-authoring.md § 6.6 Determine the branch name`. Step 2's `gh pr list --head` probe is that section's re-run check, hoisted ahead of every write; step 3 is its inline re-sync, likewise hoisted. Take nothing else from `§ 6.7 Open the doc-only PR`: its staging and its titles name the CHANGELOG (`skills/solve-milestone/changelog-authoring.md (git add CHANGELOG.md)`). Stage the paths the fixer touched, commit, then `gh pr create --base <integrationBranch>` (never `protectedBranch`). **Merge on green**, then clean up as `§ 6.8 Handle CI result` does for its docs branch: step 8's one-call shape (`skills/solve-issue/SKILL.md (passes an explicit subject and body)`), `<pr-number>` this PR's and, it carrying no Decision Log, the Code-Review-only body: `body="Code Review: PR #<pr-number>" && title="$(gh pr view <pr-number> --json title --jq .title)" && [ -n "$title" ] && gh pr merge <pr-number> --squash --delete-branch --subject "$title (#<pr-number>)" --body "$body"`, then `git checkout <integrationBranch>`, `git fetch`, fast-forward, `git branch -d chore/simplify-<milestone-slug>`. **CI red** → that section's shape unchanged: apply `needs review` through the apply-time label helper (`skills/setup/SKILL.md (canonical apply-time label helper)`), hold the PR open, preserve the local branch, do not re-attempt.

**Milestone path (`<target>` is the milestone branch).** No branch is cut and nothing is pushed: its push count is one, at milestone end, unconditionally (`skills/solve-milestone/milestone-granularity.md (Push count)`), so a PR against it is unopenable here. The commit lands on `<target>` itself, the same suppression that granularity already applies to the merge tail's on-green step (`skills/solve-milestone/integration-granularity.md (and the re-sync do not run, unconditionally)`). Subject as above, then the commit rendering of the Code Review block below, then a final paragraph of exactly one line:

```text
Simplify-Pass: <milestone-number>
```

**No `Issue:` line appears anywhere in that commit**, so the trailer query that resumes buildability and builds the milestone PR's per-issue sub-entries cannot match it (`skills/solve-milestone/milestone-granularity.md § Resume and buildability from the trailer`). Its own key is what `§ Milestone end` enumerates it by, and what step 2's guard probes: a hit there means a prior invocation already landed the pass on this preserved branch, the idempotency shape of `skills/solve-milestone/changelog-authoring.md § 6.1 Idempotency check`, which likewise runs first in its own sequence.

## The Code Review block

**Review the pass like any other source change, on both paths.** A `/simplify` diff changes source, so step 9 runs `/code-review` over the working tree and records that run truthfully.

**Resolve the effort from the diff, never hardcode it.** Immediately before the dispatch, read `${CLAUDE_PLUGIN_ROOT}/skills/review-depth.md` and follow it against the post-fix tree, passing `<repo-root>` as the classifier's root. A simplify diff touching no `sourceGlobs` path classifies `shallow`.

Render the two blocks from their existing definitions; this section adds only the deltas.

| Where | Render per | Delta |
|---|---|---|
| PR body, beneath the `## Simplify pass` block | `skills/solve-issue/SKILL.md` step 6.3 | effort is the verdict's, not a fixed `medium` |
| Commit message | `skills/solve-milestone/milestone-granularity.md § The integration commit` | no `Issue: #<n>` trailer |

**No Decision Log** on either path, the same non-issue-PR exemption the CHANGELOG PR carries (`skills/solve-milestone/changelog-authoring.md (doc-only CHANGELOG entry, no executable surface)`).

## Surface it

Add one line to Template 3's `🔴 Your move:` list, beside the CHANGELOG PR's (`skills/solve-milestone/changelog-authoring.md § 6.9 Surface in the final summary "Your move" section`):

- **Merged:** `Simplify pass merged (#P)`
- **Held open (CI red):** `🔴 Simplify PR needs human merge (CI red): #P`
- **Committed to the milestone branch:** `Simplify pass folded into the milestone PR`

Any pass ending at step 2, 3 or 6 adds no line. A simplify PR is not one of this run's issues, so it never appears in Template 3's issue rows.
