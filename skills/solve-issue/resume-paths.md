## Resume paths (interrupted run)

The branch that reaches this file belongs to the caller, which runs the probe and classifies the run into (a), (b), (c) or (d) before reading it (`skills/solve-issue/SKILL.md (Branch-state probe)`). Reaching this file therefore means the probe matched **(a), (b) or (c)** — prior work exists. Cold-start path (d), the normal first-pass state, runs inline in the caller and never reads this file.

### Resume paths

**(a) A PR exists for `issue/<n>-*`.**
- **merged** → the work is already integrated; do **not** re-implement or open a new PR; **resume at step 6.9** (confirm the issue is closed / close it). A merged PR means the branch was deleted; this state follows an interrupt between merge and close.
- **open** → check out that branch; **resume at the visual-review gate / auto-merge (steps 6.7–6.8)** — do **not** re-implement and do **not** open a second PR. The open PR is the authoritative "work is built and submitted" signal.

**(b) No PR; the branch exists with commits ahead.** Check both local and remote refs (`git branch -a --list "*issue/<n>-*"` or `git ls-remote --heads origin "issue/<n>-*"`); with no local branch, track the remote (`git checkout --track origin/issue/<n>-<slug>`) and compute commits ahead against the remote-tracking ref. **Skip re-implementation.** **Re-verify first** — if `unitTestCmd` is defined, run it and confirm green; if absent (no test layer), confirm the branch diff is non-empty and based on `integrationBranch` (`git diff <integrationBranch>...HEAD --stat`). Then **resume at step 6.1 (`/code-review`)** and follow step 6's normal flow (commit only if there are uncommitted changes, push, open PR). A red re-verify, or a diff that is empty / clearly on the wrong base, falls into the normal step-4 red-suite path (re-dispatch the implementer, the "at most 2" cap; park if non-converging).

**(c) No PR; no commits ahead; the branch is checked out with uncommitted changes.** Do **not** clobber; re-verify and resume exactly as (b), from step 6.1. Best-effort: it only recovers when the working tree is preserved in-place (in-place re-dispatch); a fresh clone has no uncommitted changes and falls to (d).

**Under `"milestone"` granularity** (`skills/solve-issue/milestone-clauses.md`) path (b)'s commits-ahead computation and its `git diff` re-verify take the milestone branch in place of `integrationBranch`, and the resumed step-6 flow commits without pushing and opens no PR (step 6.6).

**Under `"wave"` granularity** a built non-UI issue opens no per-issue PR (step 6.6), so path (a) matches nothing. Evaluate before (b): a non-empty `git ls-remote --heads origin "issue/<n>-*"` is the terminal exit (`skills/solve-issue/wave-clauses.md (The pushed built-green branch is the terminal exit)`); no re-verify, no new PR. The signal is that branch, not a trailer (contrast `skills/solve-issue/milestone-clauses.md (3, trailer query)`).
