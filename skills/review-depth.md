# Review depth - shared reference

The single source of truth for what `scripts/classify-review-depth.{sh,ps1}`'s
verdict decides: the reviewer's effort level, the review→fix cycle cap, and
what a second cycle does. Four sites read it - `solve-issue` step 6.1 and its
`post-fix-commit.md`, `solve-milestone`'s `parallel-waves.md` step 7, and
`simplify-pass.md` - and it sits a level up because none of them owns it
(`skills/notices.md (a peer of the skill folders)`).

## Two axes, never collapsed

**The verdict sets the cycle cap. The build profile sets which findings get
fixed.** Orthogonal axes, read from different places: the verdict from the
diff, the profile from triage's `risk`
(`skills/solve-issue/SKILL.md (### Build profile resolution)`). **`standard` is
not `Light`** - a `Heavy` issue under a `standard` verdict still fixes every
in-scope finding, and a `Light` issue under a `deep` verdict still accepts a
Minor one.

## Running the classifier

Run `${CLAUDE_PLUGIN_ROOT}/scripts/classify-review-depth.<sh|ps1> <root>`
(pwsh on Windows, bash elsewhere) **immediately before each `/code-review`
dispatch and never earlier**, since it reads the diff the implementer just
returned. **Take the printed verdict verbatim: never re-derived, never
overridden.**

**Fail-open.** Every failure prints `standard` on stdout with one reason token
on stderr, at exit 0 (`scripts/classify-review-depth.sh (THE SAFE DIRECTION IS MORE REVIEW)`).
`standard`'s effort and cap then apply unchanged: no crash, no park, no manual
override (`.project/design-philosophy.md#Error & failure philosophy`).

## The ladder

| Verdict | Reviewer effort | Cycle cap |
|---|---|---|
| `deep` | `medium` | 2 cycles. Any in-scope finding surviving the 2nd fix parks |
| `standard` | `medium` | 1 cycle, a 2nd **only** when the most recent review returned a Critical or Important finding |
| `shallow` | `low` | 1 cycle, a 2nd impossible |

`medium` is the ceiling. A cycle is one `/code-review` run **plus the fix it
triggers**, so a review returning no in-scope finding spends none, and on a
`code-changed` delta the fresh review is the last action before commit.

## Re-classify before a second cycle

**Before a 2nd cycle starts, re-run the classifier against the post-fix diff.**
It decides whether that cycle happens at all: a verdict dropping to `shallow`
ends the loop, one rising to `deep` runs the 2nd cycle **already granted** but
grants no 3rd. **The cap stays whatever the first verdict set.**

The re-run is reachable: the candidate set is **not monotone**. A fix restoring
a file to its HEAD content drops it out of `git diff HEAD`, so a partial revert
leaving a non-source path changed reaches `shallow`.

## The second-cycle park

**A second cycle returning any Critical or Important finding parks the issue
`needs design`**, the park comment stating that a second review round returned
a Critical or Important finding. **No third cycle runs.**

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
| `parallel-waves.md` step 7, parallel | `<worktree-path>`. `git diff HEAD` inside that worktree is still against `<base>`, because Phase 1 does not commit until step 8 |
