# Parallel-wave contingencies — solve-milestone reference

Four procedures `parallel-waves.md` reaches **only in a named, observable state**. Each section below states the condition that sends a run here; a Wave in none of those states never reads this file. `parallel-waves.md` keeps every condition inline, so a reader always knows the branch exists before deciding to follow it.

**Missing or unreadable** once one of those conditions has fired is a **systemic failure** — surface it and halt the run per core `SKILL.md`'s `## Autonomy` → "Systemic failures that halt the run". Do **not** improvise a substitute: each procedure below carries a cap or a discard rule whose omission loses work.

## Contents

Pre-clean guard · Wave-state checkpoint freshness · Red unit suite retry loop · Merge-conflict bounded auto-resolve.

---

## Pre-clean guard

**Condition:** `parallel-waves.md` step 2 is about to run `git worktree add` and the path `.milestone-config/worktrees/issue-<n>` or the branch `issue/<n>-<slug>` is a **leftover** from a prior or interrupted run. A cold run has no leftover and skips this section.

`git worktree add` hard-fails on such a leftover (`fatal: '…' already exists`; `fatal: a branch named '…' already exists`), and `git worktree prune` does **not** remove an intact leftover directory. `git branch -D` force-deletes unpushed work silently, so the guard is **preserve-don't-clobber**. Per leftover branch `issue/<n>-<slug>`:

| Leftover state | Test | Action |
|---|---|---|
| **No leftover at all (cold case)** | — | The plain `git worktree add … -b issue/<n>-<slug> <base>` form of step 2 |
| **Leftover branch carries commits ahead of `<base>` that are not yet pushed/merged** | `git rev-list --count <base>..issue/<n>-<slug>` non-zero, those commits absent from `origin/issue/<n>-<slug>` | Never `git branch -D`. **Attach a worktree to the existing branch:** `git worktree add .milestone-config/worktrees/issue-<n> issue/<n>-<slug>` (no `-b`), and drive that issue against it; the `solve-issue` branch-state probe (resume paths (a)/(b)/(c)), run on the main line, **resumes** that work. A stale worktree **directory** registered at that path → `git worktree remove --force .milestone-config/worktrees/issue-<n>` / `git worktree prune` the directory entry first; the **branch and its commits are preserved** |
| **Leftover is provably safe to discard** | **0 commits ahead** of `<base>`, **or** already merged, **or** already pushed | Clear it fully — `git worktree remove --force .milestone-config/worktrees/issue-<n>` (if present), `git worktree prune`, `git branch -D issue/<n>-<slug>` — **then** create fresh with the `-b` form |

---

## Wave-state checkpoint freshness

**Condition:** `parallel-waves.md` step 9 read `.milestone-config/.runtime/wave-state.json` and it holds an **entry for the issue being derived**. A first pass, or a file that is absent, unreadable, or invalid JSON, degrades to empty at step 9 and never reaches this section.

**Trust only if not older than the artifact it names, and ONLY for `built-green` entries** (mirrors the triage cache's stale-edge trust-but-verify posture, `scripts/triage-cache.sh (check-edges: closed but not merged)`):

- **Scope: `built-green` only — a `parked` or `abandoned` entry is NEVER trusted from the checkpoint, at any freshness.** Park/unpark is a **label change** (`gh issue edit --add-label` / `--remove-label`), not a commit, so a stale `parked` entry could never self-invalidate and would exclude that issue from Phase 2 **forever**; an `abandoned` entry names the one state the recover-once ladder exists to resolve. Both fall through to step 9's full probe (live labels plus the `🔴 Parked` / `🔴 Triage` / `🔴 Blocked` comment), exactly as if no entry existed.
- For a `built-green` entry, convert **both sides to epoch seconds and compare as integers** — never a raw ISO-string compare:
  - Entry's `pr` present: `derived_epoch=$(jq -rn --arg d "<derivedAt>" '$d | fromdateiso8601')`; `updated_epoch=$(jq -rn --arg u "$(gh pr view <pr> --json updatedAt --jq .updatedAt)" '$u | fromdateiso8601')` (confirmed valid `--json` field; `gh` always returns a `Z`-suffixed UTC timestamp). Fresh iff `[ "$derived_epoch" -ge "$updated_epoch" ]`.
  - Entry's `pr` absent: `derived_epoch=$(jq -rn --arg d "<derivedAt>" '$d | fromdateiso8601')`; `branch_epoch=$(git for-each-ref --format='%(committerdate:unix)' "refs/heads/<branch>")` against the entry's own **concrete** `branch` field — `committerdate:unix` is already epoch. Fresh iff `[ "$derived_epoch" -ge "$branch_epoch" ]`. **Never** a bare glob revision — `git log -1 --format=%cI 'issue/<n>-*'` is not a valid `git log` revision and silently returns empty output at exit 0 (verified). **`for-each-ref` returning empty** (branch deleted, e.g. merged-and-pruned since capture) → treat the entry as **stale**: fall through to the full live re-probe.
- Fresh (`derived_epoch -ge` the reference epoch, entry is `built-green`) → **trust the entry directly**: use its `{issue, wave, status, branch, pr, isUI}` in place of the probe — a **checkable predicate**, not a self-report.
- Stale, **any `parked` or `abandoned` entry**, or **no entry for this issue** → fall through to step 9's probe.

---

## Red unit suite retry loop

**Condition:** a returned implementer leaf's report shows `unitTestCmd` **red** in its own worktree (`parallel-waves.md` step 6). Every leaf returning green skips this section.

The leaf ran `unitTestCmd` as its TDD green step (step 5) but cannot loop on a red result — it may not start a second suite while one is running (`agents/implementer.md`'s antipatterns), and re-dispatching itself is the depth-2 shape `parallel-waves.md` exists to avoid. **The orchestrator owns the loop.** Run the **Unit** row of `solve-issue` `### 4. Verification gates` for that issue: re-dispatch its implementer leaf into the same worktree with the failure attached, **at most 2 re-dispatches**, invoking `superpowers:verification-before-completion` on each result and reporting real output. Each re-dispatch is a row-1 claim on step 6's shared-slot ladder.

Still red after the second re-dispatch: park **`blocked`** (`needs design` instead when the failure shows the plan is wrong), comment, preserve the branch, and drop the issue from Stage B and the per-issue tail. The `tests-green` hook at the orchestrator's own commit (step 8) is the backstop, not this loop: it blocks rather than retries, and fires after review and version bump.

---

## Merge-conflict bounded auto-resolve

**Condition:** `parallel-waves.md` Phase 2 step 1's `git merge <target>` **conflicted**. A clean merge goes to that section's step 2, and a clean merge with a red re-verify to its step 4; neither reads this section.

Attempt resolution with full-milestone context (git's `ort` strategy already auto-resolves **non-adjacent** same-file edits), then re-verify. **Two edits on directly adjacent lines conflict**, so a file with one shared append point (a changelog table, a barrel export, a DI registration list) conflicts by construction under concurrency. **That shape is *within* bounded auto-resolve, not a park trigger:** both hunks are additive and order is not semantically load-bearing. Park stays for genuinely ambiguous semantics, a conflict still non-trivial after the attempt, or a red re-verify.

**Do not recommend `merge=union`** as the fix in a park comment: it never reports a conflict, removing the only signal you would get, and it interleaves multi-line changes into structurally broken output.

- **Resolvable AND green** → proceed to Phase 2 step 2's merge.
- **Non-trivial / ambiguous OR red** → `git merge --abort`, **park `blocked`** (comment + label + preserve branch), continue with the next branch.
