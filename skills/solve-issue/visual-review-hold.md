## Visual-review hold (UI issue)

The branch that reaches this file belongs to the caller, which tests the diff against `uiSurfaceGlobs` and only then reads it (`skills/solve-issue/SKILL.md (Visual-review gate)`). Reaching this file therefore means the issue **does** touch a UI surface: it is not auto-merged, and its terminal state is *PR open, awaiting human visual sign-off*. A non-UI issue proceeds straight to auto-merge (step 6.8) and never reads this file.

### The hold

Apply the `needs review` label **to the PR** via the apply-time helper (idempotent `gh label create --force` then `gh pr edit <pr> --add-label "needs review"`) and leave the PR open for a human to test-render and merge. `solve-milestone`'s final summary lists all open `needs review` PRs.

- **`visualCapture` configured** (the profile carries a `visualCapture` block with all three required keys — `serverCmd`, `readyUrl`, `signInPath`) **and this is a sequential run** (a parallel run defers the capture to the serial merge tail: `skills/solve-milestone/parallel-waves.md (Deferred to the serial tail)`): capture convenience evidence inline — read `${CLAUDE_PLUGIN_ROOT}/skills/solve-issue/visual-capture.md` and follow its `### Capture flow`. Any failure in that flow degrades to the human-test note below — it never fails the run and never auto-merges.
- **Degradation — `visualCapture` absent or incomplete (missing a required key), OR any capture failure** (daemon will not boot/reuse, sign-in fails, a surface will not render, push fails): do **not** fail and do **not** auto-merge — post a note on the PR (`gh pr comment <pr>`) that visual evidence is unavailable and a **human visual test is required before the merge to `integrationBranch`**. The `needs review` label keeps the PR held open for human sign-off regardless.

The issue itself **stays open** while the hold is in force; it closes when the human merges the PR (step 6.9). **Under `"milestone"` granularity** this whole hold is bypassed (`skills/solve-issue/milestone-clauses.md`).
