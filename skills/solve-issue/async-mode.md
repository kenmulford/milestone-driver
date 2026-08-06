# Async mode (`--async`): retired

The retirement record for the `--async` token: why it is inert, what replaced it, and where the behavior it carried now lives. Token recognition and the inert-not-rejected rule are the caller's (`skills/solve-issue/SKILL.md (an interpreted token, not a parsed CLI flag)`).

---

## What `--async` meant, and why it is retired

`--async` told the caller to dispatch the whole `solve-issue` pipeline as `Agent(run_in_background: true)`.

That is exactly the shape the dispatch topology forbids (`docs/architecture.md` → `## Dispatch topology`): **no dispatched agent may dispatch a child whose result it needs.** The pipeline dispatches an implementer (step 3) and a `/code-review` fan-out (step 6.1), so inside a background agent both sit at depth 2, where a completion notification never arrives (anthropics/claude-code#75043). The agent's turn ends at the dispatch and nothing re-invokes it, so the run stops mid-pipeline with work uncommitted, no PR, and no park label. There is no flag that repairs this: nested children run async regardless of `run_in_background`.

## What replaces it

The pipeline runs on the **caller's own main line**, and that session fans out:

| Caller | What now happens |
|---|---|
| `solve-milestone`, sequential mode | Runs `solve-issue <n>` in-thread, one issue at a time (`skills/solve-milestone/SKILL.md`'s `### 4. Loop over issues in dependency-graph order`, step 2). It dispatches the implementer and the reviewers itself, as leaves. |
| `solve-milestone`, parallel mode | Fans out **by stage**, not by issue: concurrent implementer leaves, a barrier, then concurrent reviewer leaves (`skills/solve-milestone/parallel-waves.md § Parallel mode — Phase 1: concurrent stage dispatch`). |
| A user session | Invokes `solve-issue <n>` directly. The token, if typed, is ignored. |

## Delta A1 retired with it

Delta A1 suppressed the standalone patch-bump confirm (step 6.4), because a background agent auto-denies any tool call that would prompt. The pipeline is no longer dispatched into a background agent, so the **mechanism** that suppressed the confirm is gone. What that mechanism was protecting is not: a milestone run must never wait on a human, and removing the background agent removed the only thing physically preventing the prompt. That guard is **re-homed onto the caller** in `SKILL.md` step 6.4's standalone bullet, which now never fires inside a milestone run (it re-derives the target version instead, and failing that bumps non-interactively with a `judgment call` label). A genuinely standalone run still asks, and no `judgment call` label is owed for a bump the operator was actually asked about.

## Background-leaf constraints

These now bind the **orchestrator's own leaf dispatches**, not this skill:

- **Auto-deny.** A background leaf auto-denies any tool call that would otherwise prompt. The permission pre-flight gate guards the tool surface before dispatch, and an auto-deny a leaf could not work around parks (`SKILL.md`'s `## Permission pre-flight gate` → **Auto-deny handling**).
- **No PushNotification.** Dispatched leaves do not send notifications: PushNotification is confirmed absent from subagent tool registries (see issue #97 recorded decision). The orchestrator emits at its own chunk boundaries (parks, wave completions, run complete/halt), which it can do because it ran the gates itself.
- **SendMessage addressing.** A dispatched leaf CAN receive a mid-run message from the session that spawned it, delivered at the leaf's next tool-use round. An agent-TYPE name (e.g. `milestone-driver:implementer`) is **not** a reachable address; only the specific dispatched instance, by the agent ID/name its own dispatch returned, and only from the spawning session. Cross-agent traffic routes back through the orchestrator, which relays it or folds the finding into that leaf's next dispatch brief.
