## Wave-granularity clauses (`integrationGranularity: "wave"`)

Reaching this file means the caller resolved `integrationGranularity` to `"wave"` from the profile at step 1 (`skills/solve-issue/SKILL.md (Resolved from the profile at step)`). `### Clauses` is the complete set of per-step deltas that mode applies, and every one applies to a **non-UI** issue only — settle that **before 6.2** from `git diff <integrationBranch>...HEAD --name-only` ∩ `uiSurfaceGlobs` (`skills/solve-milestone/parallel-waves.md (independently from)`), never from a PR's changed files, 6.6 having opened none: a UI issue runs the pipeline byte-unchanged, held per-issue for visual sign-off (`skills/solve-milestone/integration-granularity.md (Logic-only carve-out)`). The wave branch, the one wave PR, the explicit close, and its disposition belong to `${CLAUDE_PLUGIN_ROOT}/skills/solve-milestone/integration-granularity.md § "wave"`.

### Clauses

| Step | Clause |
|---|---|
| 6.2 | No per-issue PR body: the Decision Log is written into the step-6.5 commit in the trailer shape `skills/solve-milestone/milestone-granularity.md (Subject line, a blank line, the Decision Log summary)` defines. The citation post to the issue (`gh issue comment <n>`) is unchanged. |
| 6.3 | The Code Review section travels in that commit's indented `Code-Review:` block instead, as `skills/solve-milestone/milestone-granularity.md (The Code Review block is copied)` defines. The wave PR aggregates them under **exactly one** `## Code Review` heading, one `### #<n>` sub-entry per logic issue, de-indented to column 0 (`skills/solve-milestone/milestone-granularity.md (de-indented back to column 0)`) — the shape `hooks/code-review-gate.sh (heading='## Code Review')` requires at `gh pr create` and `gh pr merge`. |
| 6.5 | Commit in the shape 6.2 and 6.3 import whole, `Issue: #<n>` trailer included: no wave-path probe reads it — the resume signal is 6.6's pushed branch — but it leaves **one** commit shape for both non-default granularities. |
| 6.6 | Push the feature branch as written, and open **no** per-issue PR. A `judgment call` label earned this issue goes on the **issue** instead. |
| 6.8 | **Skipped whole**: there is no per-issue PR to merge, auto-merge-on-green having moved from per-issue to per-wave. |
| 6.9 | **Skipped whole**: the close is the Wave boundary's explicit `gh issue close` (`skills/solve-milestone/integration-granularity.md (Explicit issue close)`), never a `Closes #n` keyword. |
| Run-end cost record | The pushed built-green branch is the terminal exit that replaces the step-6.9 close. |
| Output Template 2 | No PR is opened, so a completed issue emits the `✅ committed` row: the same completed-successfully ✅ the legend carries, an empty PR cell, and the issue's own terminal state in the Note cell. |
