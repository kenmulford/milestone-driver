# Async mode (`--async`) — solve-issue reference

This file is loaded by `solve-issue` when the invocation text contains an `--async` token (see `skills/solve-issue/SKILL.md`'s `## Async mode (`--async`)` stub, which carries only the token-recognition rule and this pointer). It carries the full `--async` background-dispatch contract: how the caller dispatches, the pre-dispatch permission pre-flight gate, the byte-unchanged in-agent pipeline, Delta A1 (the suppressed version-bump confirm), and the background-agent constraints.

---

## How the caller dispatches

When the caller invokes `solve-issue <n> --async`, it dispatches the full pipeline as `Agent(run_in_background: true)`. The main line (or user session) **awaits the completion notification** from the Agent tool when the background agent finishes — it should **end its turn** while waiting rather than poll; the harness automatically re-invokes the caller when the background agent completes, and a long-interval background `until`-loop is acceptable only as a safety net against a hung worker, never as the primary wait mechanism. The caller CAN still send the background agent a mid-run redirect message before it completes, delivered at the agent's next tool-use round — see **Background agent constraints** below for the addressing rule. **No PushNotification is sent by the background agent** — PushNotification is confirmed absent from subagent tool registries (see issue #97 recorded decision). The main line (caller) emits the park or wave-boundary notification at this chunk boundary, after receiving the Agent tool completion notification and re-deriving terminal state from live `gh` queries.

## Pre-dispatch: permission pre-flight gate

Before the caller dispatches any background agent, run the **permission pre-flight gate** per `## Permission pre-flight gate` above.

- **No gaps:** proceed — dispatch `solve-issue <n>` as `Agent(run_in_background: true)`.
- **Gap detected:** do **not** dispatch as a background agent. Surface the 🔴 gap table and recommend `/fewer-permission-prompts`. **Fall back to synchronous dispatch** — invoke `solve-issue <n>` (no `--async`) as the normal sequential pipeline. The run completes; it just does not use background concurrency.

## Inside the background agent: the pipeline runs byte-unchanged

The full sequential pipeline (steps 0–9) runs **byte-unchanged** inside the background agent — all gates, park-don't-prompt, PR, auto-merge on green for non-UI issues, visual-review hold for UI issues, close — **except Delta A1**.

## Delta A1 — Version-bump confirm suppressed

The standalone-run patch-bump confirm (the interactive "ask whether it should be minor or major" in step 6.4 standalone runs) cannot prompt from a background context — background subagents auto-deny any tool call that would otherwise prompt (documented Claude Code behavior).

Under `--async`, the bump **defaults to patch** (`x.y.Z` → `x.y.(Z+1)`). This default is **logged in the Decision Log** and the PR carries a `judgment call` label so the call is auditable post-run. Milestone runs are **unaffected** — the milestone-derived target version already replaces the confirm entirely (step 6.4 milestone-run path).

Delta A1 is the **only** behavioral delta because it is the only step in the sequential pipeline that would interactively prompt in a standalone run. All other gates, caps, and park-don't-prompt behavior are unchanged.

## Background agent constraints

- **Auto-deny:** background subagents auto-deny any tool call that would otherwise prompt. The permission pre-flight gate (run before dispatch) guards against un-allowlisted tool calls; Delta A1 eliminates the only remaining interactive confirm. Any unexpected auto-deny mid-run is treated as a park — same park-don't-prompt contract as every other gate.
- **No PushNotification:** the background agent does not send notifications — PushNotification is confirmed absent from subagent tool registries (see issue #97 recorded decision). The main-line caller emits at chunk boundaries (parks + wave completions + run complete/halt).
- **Caller obligation on completion** *(applies to the calling session, not the background agent)*. When the background chunk's completion notification arrives, the calling session re-derives terminal state from live `gh` queries and emits **one notification per dispatched issue**: `⏸️ #N parked — <reason>` if the issue was parked (park reason = the last comment on the issue opening with `🔴 Triage`, `🔴 Blocked`, or `🔴 Parked` — gh returns comments oldest-first, take the LAST match; if none, report "park reason not recorded"), or a `🏁`-style one-liner (e.g. `🏁 #N merged` or `🏁 #N open — awaiting visual review`) if the issue completed (PR merged or held for visual review). This mirrors the handback facts for `--worker` mode; one emit per run, always by the calling session, never by the background agent. (When `--async` is dispatched by `solve-milestone`, solve-milestone's own emit rules govern — per-issue completion notifications are suppressed in sequential mode in favor of the aggregate `🏁` run-complete signal; this per-issue obligation applies to standalone callers outside solve-milestone's orchestration.)
- **SendMessage addressing:** a dispatched background agent CAN receive a mid-run message from the session that spawned it — delivered at the agent's next tool-use round, not instantaneously mid-tool-call. An agent-TYPE name (e.g. `milestone-driver:implementer`) is **not** a reachable address — only the specific dispatched instance, addressed by the agent ID/name its own dispatch returned, can receive one, and only from the session that spawned it. Cross-agent traffic (e.g. a reviewer subagent handing a finding to an implementer subagent) is not peer-to-peer: it routes back through the dispatching orchestrator, which relays it to the correct child by that agent's actual ID — or, more simply, folds the finding into that child's own dispatch brief.
