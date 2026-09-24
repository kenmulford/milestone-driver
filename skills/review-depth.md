# Review depth - shared reference

The single source of truth for what `scripts/classify-review-depth.{sh,ps1}`'s
verdict decides: the reviewer's effort level, the review→fix cycle cap, and
what a second cycle does. Five sites read it - `solve-issue` step 6.1 and its
`post-fix-commit.md`, `solve-milestone`'s `parallel-waves.md` step 7,
`simplify-pass.md`, and `milestone-end-gates.md` step 4.

## Contents

Two axes, never collapsed · Running the classifier · The ladder · Re-classify before a second cycle · The second-cycle park · Which findings get fixed · What stays at each call site

## Two axes, never collapsed

**The verdict sets the cycle cap. The build profile sets which findings get
fixed.** The verdict comes from the diff, the profile from triage's `risk`
(`skills/solve-issue/SKILL.md (### Build profile resolution)`). `standard` is
not `Light` - a `Heavy` issue under a `standard` verdict still fixes every
in-scope finding, and a `Light` issue under a `deep` verdict still accepts a
Minor one.

## Running the classifier

Run `${CLAUDE_PLUGIN_ROOT}/scripts/classify-review-depth.<sh|ps1> <root>`
(pwsh on Windows, bash elsewhere) once the implementer's diff exists: before
the coherence pass (`solve-issue` section 6 skips that pass on `shallow`), and
again immediately before each `/code-review` dispatch, since a fix changes
the diff. **Take the printed verdict verbatim: never re-derived or
overridden.**

A caller classifying a committed range instead of the working tree passes a
second argument, `<root> <base_ref>`, classifying `git diff <base_ref>...HEAD`
(`scripts/classify-review-depth.sh (Usage:)`).

**Fail-open.** Every failure prints `standard` on stdout with one reason token
on stderr, at exit 0 (`scripts/classify-review-depth.sh (THE SAFE DIRECTION IS MORE REVIEW)`).
Its effort and cap apply unchanged: no crash, no park, no
override (`.project/design-philosophy.md#Error & failure philosophy`).

## The ladder

| Verdict | First-run effort | Cycle cap |
|---|---|---|
| `deep` | `medium` | 2 cycles. Any in-scope finding surviving the 2nd fix parks - a fresh conventional-fix finding on the 2nd review is not a survivor, per the second-cycle park below |
| `standard` | `medium` | 1 cycle, a 2nd **only** when the most recent review returned a Critical or Important finding |
| `shallow` | `low` | 1 cycle, a 2nd impossible |

`medium` is the ceiling, and the column is a first run's effort only: every
later `/code-review` on the issue - the re-review a `code-changed` fix owes, a
2nd cycle's - runs at `low`, whatever the verdict says (`simplify-pass.md`'s
step 9 run is its own pass's first). **A resumed issue starts fresh**:
holding no record of the earlier run, its next review takes the verdict's
effort again. A cycle is one `/code-review` run plus its fix,
so a review returning no in-scope finding spends none, and on a `code-changed`
delta the fresh review is the last action before commit. `shallow` is no
`sourceGlobs` path, or
`scripts/classify-review-depth.sh (THE SMALL-DIFF DEMOTION)`.

## Re-classify before a second cycle

**Before a 2nd cycle, re-run the classifier against the post-fix diff.**
It decides whether that cycle happens: `shallow`
ends the loop; `deep` runs the already-granted 2nd cycle but
grants no 3rd. The cap stays the first verdict's.

## The second-cycle park

**The park keys on the finding's resolvability, not its severity alone.** A
second cycle's Critical or Important finding parks `needs design` only when it
needs a decision the record cannot make - the park triggers
`skills/solve-issue/SKILL.md (Autonomy model (Balanced))` already names. A
finding with a conventional fix (a repo precedent, a `.project/` convention,
or a shell/quoting idiom) instead takes one more fix dispatch and one final
review at the same effort - the last action before commit, never a fourth.
**Non-convergence still parks**: a finding surviving its own fix parks
regardless of how it was classified going in.

No third cycle runs beyond that: `hooks/dispatch-cap.sh` denies the 4th
`/code-review` run and the 4th implementer dispatch per issue (first build
plus 2 fixes, across every gate and this loop). A denied dispatch is the park.

## Which findings get fixed

The **build profile** decides, never the verdict:

- **Light** fixes only a Critical or Important finding. A Minor one is
  accepted, not fixed - disposed `accepted (rationale: <…>)` in the Code Review
  section (`skills/solve-issue/SKILL.md (Assemble the Code Review section)`).
  Accepting changes no code: no re-review, no further cycle.
- **Heavy** (the default) fixes every in-scope finding.

Severities are the reviewer template's
(`skills/solve-milestone/parallel-waves.md (Critical / Important / Minor)`); a
finding carrying none counts as Important. **Non-convergence parks only a finding the profile fixes** -
the park-trigger bullet fires at any severity.

## What stays at each call site

The `<root>` argument, and nothing else:

| Caller | `<root>` |
|---|---|
| `solve-issue` step 6.1, sequential | `<repo-root>` |
| `parallel-waves.md` step 7, parallel | `<worktree-path>`. `git diff HEAD` inside that worktree is still against `<base>` |
| `milestone-end-gates.md` step 4, milestone end | `<repo-root>` (the milestone branch's checkout); `<base_ref>` `integrationBranch` |
