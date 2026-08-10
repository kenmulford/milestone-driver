# Abandoned-issue recovery — solve-milestone reference

Loaded when `parallel-waves.md` Phase 1 step 9's partition put **at least one** dispatched issue in the `abandoned` bucket. A Wave whose partition yields an empty `abandoned` set **never reads this file**, and step 9 proceeds straight to its wave-state checkpoint write. The condition is fully observable before the read: step 9 partitions from git + gh ground truth first, and only a non-empty bucket reaches here.

**Missing or unreadable** with a non-empty `abandoned` bucket is a **systemic failure** — surface it and halt the run per core `SKILL.md`'s `## Autonomy` → "Systemic failures that halt the run". Do **not** skip the ladder and do **not** park the issues instead: step 9 requires every dispatched issue to leave it as `built-green` or `parked`, and this file is the only path from `abandoned` to either.

---

## The three sub-shapes the ladder tells apart

Step 9's classifier does not distinguish these; the ladder below does. Read the worktree with `git -C .milestone-config/worktrees/issue-<n> status --porcelain` — **a path that does not exist reads as no uncommitted work**, and the ladder recreates the worktree per `parallel-waves.md` step 2 before dispatching.

| Sub-shape | Reading | Where the ladder takes it |
|---|---|---|
| A worktree carrying an **uncommitted diff** | `status --porcelain` non-empty, 0 commits ahead of `<base>` | Dispatch the one recovery leaf; it resumes from the partial diff |
| A worktree carrying **none** | `status --porcelain` empty, 0 commits ahead | Dispatch the one recovery leaf; the leaf died before writing anything, so recovery starts from zero |
| A branch carrying **local commits ahead of `<base>` that were never pushed** | probe path b non-zero, `git ls-remote --heads origin issue/<n>-<slug>` empty | **No leaf.** The state an interrupt inside step 8's commit-then-push seam leaves — which step 2's carries-work leg and `solve-issue`'s resume path (b) both treat as first-class. Skip straight to the review + tail resume below |

## Recover an `abandoned` issue exactly once, then park (cap 1)

**Check the branch first.** Already carrying commits ahead of `<base>` (probe path b non-zero) → the implementation is present: **skip the recovery leaf entirely** and re-run the orchestrator's own Stage B review (`parallel-waves.md` step 7) and per-issue tail (step 8), where the interrupted commit-then-push seam left off.

Otherwise dispatch **ONE** `implementerAgent` leaf into that issue's **existing worktree** as `Agent(run_in_background: true)`, **no more than `maxParallelWorkers` LEAVES in flight at once across the whole abandoned set** (step 3's same cap; step 6's ladder does not run here, every Stage A/B chain having returned).

**The cap counts every leaf this ladder causes, not the recovery leaves alone, and the refill trigger is a SLOT FREEING, never a recovery leaf returning:** a returning recovery leaf **HOLDS its slot** for the step-7 leaf its resume dispatches (step 6's carve-out shape), and the skip-the-recovery-leaf branch above **takes a slot from the same cap** before dispatching its step-7 leaf. The slot frees when that **step-7** leaf returns, and **that** is when the next abandoned issue is dispatched, so a set wider than the cap still drains.

Brief the recovery leaf exactly as step 5 briefs an implementer leaf — including the **expected file scope** and the **`risk:light` token** when step 4 resolved this issue's build profile to light, neither of which this ladder may drop — plus an **implementation-only finish-list** naming what is left to build. **Scope that finish-list to implementation only:** it must not name step 8's tail (version bump, commit, push, PR), a leaf returning an uncommitted diff and dispatching nothing (step 5). **The leaf dispatches nothing, and the cap is 1, not 2** (unlike step 6's unit-retry loop): this is a dropped baton, not a non-converging loop.

## On return

Confirm from **ground truth, never from its report**, that the worktree now carries an uncommitted diff (`git -C .milestone-config/worktrees/issue-<n> status --porcelain` non-empty), then resume Stage B review (step 7) and the per-issue tail (step 8) for that issue; step 9 then re-derives that issue's terminal state after step 8, as for every other issue.

**Do not re-run step 9's partition at this point** — a just-returned leaf holds an uncommitted diff and zero commits, the `abandoned` bucket's own shape, so re-partitioning would classify a **successful** recovery as `abandoned` again with its cap already spent.

## Park path

**Recovery fails, the diff confirmation still finds nothing, or a gate comes back red** → park **`blocked`**, post its `🔴 Parked — ` comment in `skills/output-style.md`'s park-comment shape, whose **evidence** slot names the stage the issue was abandoned at (the stage it was last dispatched into) plus the probe output that classified it, **preserve both the branch and the worktree** (step 10's cleanup carves this park out of its remove-on-park trigger), drop the issue from Stage B, the per-issue tail, and Phase 2, and **let the Wave continue**. `blocked` is the label: `needs design` and `needs decision` each assert a gap that has not been shown to exist.
