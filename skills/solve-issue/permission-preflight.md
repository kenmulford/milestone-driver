## Permission pre-flight — tool surface and gap response

The branch that reaches this file belongs to the caller, which evaluates the gate only when background dispatch is about to be used and reads the merged allowlist itself (`skills/solve-issue/SKILL.md (Background subagents auto-deny any)`). Reaching this file therefore means a leaf is about to be dispatched as `Agent(run_in_background: true)` and the union of the three settings layers has been read. A fully synchronous run never reaches it. `### Tool surface and response` below is what that union is tested against, and what happens when it falls short.

### Tool surface and response

<!-- KEEP THIS BLOCK IN SYNC with skills/solve-milestone/SKILL.md § Permission pre-flight gate, its second copy. -->
**Pipeline tool surface.** The allowlist must cover, at minimum:

| Tool category | Required grants |
|---|---|
| Read-only gh ops | `gh pr list`, `gh issue view`, `gh issue list` |
| Git | `git commit`, `git push` |
| PR / issue writes | `gh pr create`, `gh pr merge`, `gh pr edit`, `gh pr comment` |
| Issue management | `gh issue edit`, `gh issue comment`, `gh issue close` |
| Label management | `gh label create` |
| Profile-defined commands | Each command in `unitTestCmd`, `preflightCmd`, `e2eTestCmd` (skip if absent) |

**Gap detection and response.**

- **No gaps:** proceed with background dispatch as planned.
- **Gap detected (union does not cover the required surface, or no layer is readable):** do **not** dispatch in the background. Instead:
  1. Surface a 🔴 gap table listing each missing grant and which settings layer(s) could supply it.
  2. **Fall back to synchronous dispatch for this run.** The run completes; it just does not use background concurrency.
  3. Recommend the consumer run `/fewer-permission-prompts` to establish a stable allowlist (see `docs/consumer-setup.md`).

After the first background-dispatch decision point, the result (proceed / fallback) is held for the rest of the run — do not re-read settings on every issue.

**Auto-deny handling.** When a leaf (implementer, reviewer) reports an auto-deny it could not work around, treat it as a **park**: `🔴 Parked — auto-deny on <tool>`, label `blocked`, per the caller's park action. The park itself is the durable record: the orchestrator runs on the main line, so the label and comment it just wrote are what the milestone loop reads back, and no separate return payload carries the park.
