# Review depth - shared reference

The single source of truth for what `scripts/classify-review-depth.{sh,ps1}`'s
verdict decides: the reviewer's effort level, the review→fix cycle cap, and
what a second cycle does. Four sites read it - `solve-issue` step 6.1 and its
`post-fix-commit.md`, `solve-milestone`'s `parallel-waves.md` step 7, and
`simplify-pass.md`.

## Two axes, never collapsed

**The verdict sets the cycle cap. The build profile sets which findings get
fixed.** The verdict comes from the diff, the profile from triage's `risk`
(`skills/solve-issue/SKILL.md (### Build profile resolution)`). **`standard` is
not `Light`** - a `Heavy` issue under a `standard` verdict still fixes every
in-scope finding, and a `Light` issue under a `deep` verdict still accepts a
Minor one.

## Running the classifier

Run `${CLAUDE_PLUGIN_ROOT}/scripts/classify-review-depth.<sh|ps1> <root>`
(pwsh on Windows, bash elsewhere) once the implementer's diff exists: before
the coherence pass (`solve-issue` section 6 skips that pass on `shallow`), and
again **immediately before each `/code-review` dispatch**, since a fix changes
the diff. **Take the printed verdict verbatim: never re-derived, never
overridden.**

**Fail-open.** Every failure prints `standard` on stdout with one reason token
on stderr, at exit 0 (`scripts/classify-review-depth.sh (THE SAFE DIRECTION IS MORE REVIEW)`).
`standard`'s effort and cap then apply unchanged: no crash, no park, no manual
override (`.project/design-philosophy.md#Error & failure philosophy`).

## The ladder

| Verdict | First-run effort | Cycle cap |
|---|---|---|
| `deep` | `medium` | 2 cycles. Any in-scope finding surviving the 2nd fix parks |
| `standard` | `medium` | 1 cycle, a 2nd **only** when the most recent review returned a Critical or Important finding |
| `shallow` | `low` | 1 cycle, a 2nd impossible |

`medium` is the ceiling, and the column is a **first** run's effort only: every
later `/code-review` on the issue - the re-review a `code-changed` fix owes, a
2nd cycle's - runs at `low`, whatever the verdict says (`simplify-pass.md`'s
step 9 run is its own pass's first). **A resumed issue starts a fresh pass**:
holding no record of the earlier run, its next review takes the verdict's
effort again. A cycle is one `/code-review` run **plus the fix it triggers**,
so a review returning no in-scope finding spends none, and on a `code-changed`
delta the fresh review is the last action before commit. `shallow` is no
`sourceGlobs` path, or
`scripts/classify-review-depth.sh (THE SMALL-DIFF DEMOTION)`.

## Re-classify before a second cycle

**Before a 2nd cycle starts, re-run the classifier against the post-fix diff.**
It decides whether that cycle happens at all: a verdict dropping to `shallow`
ends the loop, one rising to `deep` runs the 2nd cycle **already granted** but
grants no 3rd. **The cap stays whatever the first verdict set.**

## The second-cycle park

**A second cycle returning any Critical or Important finding parks the issue
`needs design`**, the park comment stating that a second review round returned
a Critical or Important finding. **No third cycle runs**: `hooks/dispatch-cap.sh`
denies the 4th `/code-review` run and the 4th implementer dispatch per issue
(the first build plus 2 fixes, across every gate and this loop), so the cap
holds whatever the orchestrator concludes. A denied dispatch is the park.

## Which findings get fixed

The **build profile** decides, never the verdict:

- **Light** fixes only a **Critical or Important** finding. A Minor one is
  accepted, not fixed - disposed `accepted (rationale: <…>)` in the Code Review
  section (`skills/solve-issue/SKILL.md (Assemble the Code Review section)`).
  Accepting changes no code, so no re-review and no further cycle fire.
- **Heavy** (the default) fixes **every** in-scope finding.

Severities are the reviewer template's
(`skills/solve-milestone/parallel-waves.md (Critical / Important / Minor)`); a
finding carrying none, including from a reviewer scoring by confidence, counts
as **Important**. **Non-convergence parks only a finding the profile fixes** -
the caller's park-trigger bullet fires at any severity.

## What stays at each call site

The `<root>` argument, and nothing else:

| Caller | `<root>` |
|---|---|
| `solve-issue` step 6.1, sequential | `<repo-root>` |
| `parallel-waves.md` step 7, parallel | `<worktree-path>`. `git diff HEAD` inside that worktree is still against `<base>` |
