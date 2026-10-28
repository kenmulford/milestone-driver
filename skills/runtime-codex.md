# Running on OpenAI Codex CLI

Applies to skill and agent text only when the runtime is Codex. On Claude Code nothing here changes behavior. The skill body is never forked per runtime.

## Tool names

| Claude Code | Codex |
|---|---|
| `Agent` / `Task` dispatch | `spawn_agent`, then `wait_agent` (see `## Dispatching an agent`) |
| `run_in_background: true` | `spawn_agent` is already non-blocking. Collect with `wait_agent` |
| `SendMessage` to a dispatched leaf | `send_input` to that leaf |
| `AskUserQuestion` | `request_user_input` or `request_user_input_async`, whichever the turn lists. Ask only where a skill step says to ask. Park product gaps, never ask about them (see `## Human gates`) |
| `TodoWrite` | `update_plan` |
| `Skill` tool, `/plugin:skill` | namespaced mention, `$<plugin>:<skill>` (e.g. `$milestone-driver:solve-issue`) |
| `PushNotification` | none. Print the notification text to chat |
| `Workflow`, Artifacts | none. Skip, print to chat |

## Dispatching an agent

Dispatching `<plugin>:<name>`:

1. Call `spawn_agent` with no `agent_type` (an unknown type is a hard error) and `task_name` set to `<name>_issue_<n>_<attempt>` (e.g. `implementer_issue_58_2` for the second implementer dispatch on issue 58). Codex rejects a reused `task_name`. The dispatch-cap hook counts dispatches by `task_name` because Codex encrypts the message.
2. The message's first line is `Your role instructions are in <abs plugin root>/agents/<name>.md. Read that file first and follow it. Ignore its YAML frontmatter.`
3. Second line: `Map tool names per <abs plugin root>/skills/runtime-codex.md.`
4. The rest is the brief the Claude dispatch carries. Every path in it is the resolved absolute path, never `${CLAUDE_PLUGIN_ROOT}`.
5. Call `wait_agent` for the return.

Profile keys defaulting to `<plugin>:<name>` (`implementerAgent`, `triageAgent`, `coherenceReviewAgent`, and the rest) resolve to that file. `<abs plugin root>` is the root of the plugin that ships the agent. For another plugin it is `<this root>/../../<plugin>/<highest version>/agents/<name>.md`. A file not found takes the existing absent-means-skip path.

`model:` and `tools:` frontmatter have no Codex effect. Read-only agents are bound by their body text.

## Human gates

A mandatory gate is an approval, review, or confirm-before-write step that needs a human. On Codex:

1. Call `request_user_input` or `request_user_input_async` only when the turn lists it.
2. Both absent, or the call returns no answer: the verdict is not approved. End the turn with a `🔴` pending line naming the gate. Print no handoff and take no gated action.
3. Accept approval in the next chat turn.
4. Never continue past a gate on best judgment.

Unattended runs (`MILESTONE_DRIVER_NONINTERACTIVE=1` and equivalents) keep their documented non-interactive defaults. This section covers only gates that require a human.
