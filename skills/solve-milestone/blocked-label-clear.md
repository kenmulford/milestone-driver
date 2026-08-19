# Dependency-hold label clear: solve-milestone reference

Loaded by core `SKILL.md`'s `### 4. Loop over issues in dependency-graph order` **only where condition (a) already holds for an issue with a non-empty `dependencyGraph.edges["<n>"]`** — the one shape a spent `blocked` label can hold back. An issue with no upstream never reaches it. Both modes share it: `parallel-waves.md § Parallelizable-set selection (parallel mode)` reuses the same (a)/(b)/(c) definition rather than re-deriving one. **Missing or unreadable** once an issue has reached it is a **systemic failure** (core `SKILL.md`'s `## Autonomy`).

---

Runs on ONE issue, BEFORE condition (b) reads that issue's live labels.

1. **Read the live labels** — `gh issue view <n> --json labels --jq '[.labels[].name]'`. Condition (b) makes the same read; one call serves both, and where step 2 removes `blocked`, (b) evaluates the post-removal label set, never this snapshot.

2. **Clear iff the hold is spent** — `gh issue edit <n> --remove-label "blocked"`, iff BOTH hold:

   - `blocked` is the issue's ONLY blocker label. A `needs design` or `needs decision` alongside it means the root block is a triage or design park, which this file never clears and never touches (`skills/solve-milestone/not-buildable.md (One blocker label per issue)`; `skills/triage/blocker-resolver-dispatch.md (Unparking)` owns those two).
   - EVERY issue in `dependencyGraph.edges["<n>"]` passes condition (a) — merged to `integrationBranch`, or carrying its `Issue: #<n>` trailer on the milestone branch under `integrationGranularity: "milestone"`. That is condition (a)'s own evaluation, reused: do not re-derive it, and never read the `🔴 Blocked` comment to decide. The graph is the authority; the comment is prose.

3. **Otherwise touch nothing.** A single unmerged upstream leaves the `blocked` label AND the `🔴 Blocked` comment exactly as they stand; the issue fails (b) as before and takes `not-buildable.md` again.

A cleared issue KEEPS its `🔴 Blocked` comment — it is the run record of why the hold existed, and (b) reads labels, never comments. Each transitive dependent `not-buildable.md` held clears on its OWN pass through this file, against its OWN edges; nothing cascades from here.
