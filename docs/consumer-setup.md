# milestone-driver — consumer setup

Adopt milestone-driver in a repository in five steps. The whole point is that the
discipline is mechanical, so most of this is one-time wiring.

## 1. Install the plugin (and its dependency)

Install `milestone-driver` and the required [`superpowers`](#requirements) plugin
in Claude Code (dev-install via `claude --plugin-dir`, or from a marketplace once
published). Confirm both are enabled with `/plugin`.

## 2. Add the project profile

Create a committed `.claude/milestone-driver.json` at the repo root describing your
stack and branch model. See [`profile-schema.md`](profile-schema.md) for the full
schema. Minimal example:

```json
{
  "integrationBranch": "dev",
  "protectedBranch": "main",
  "sourceGlobs": ["src/**", "tests/**"],
  "unitTestCmd": "npm test"
}
```

Commit it — the gates read this file, so it must be present in every clone and on CI.

## 3. Install the native git hooks

From the consuming repo, run the installer shipped with the plugin. It writes
`.git/hooks/pre-commit` (tests-green) and `.git/hooks/pre-push` (no-push) as sh
shims that call the plugin's scripts (preferring `pwsh`, falling back to `bash`+`jq`):

```bash
# PowerShell
pwsh -File <plugin>/scripts/install-git-hooks.ps1

# or bash
bash <plugin>/scripts/install-git-hooks.sh
```

Re-run it after the plugin's install path changes (e.g. a version bump). An existing
non-milestone-driver hook is backed up to `<hook>.pre-milestone-driver.bak` — chain
it manually if you still need it. `.git/hooks` is not committed, so each clone runs
the installer once.

## 4. Restart Claude Code

The Claude-side hooks (`force-subagent`, `no-pr-to-protected`) are registered in the
plugin's `hooks/hooks.json` and **load at session start** — restart Claude Code after
installing or updating the plugin so they take effect.

## 5. Add GitHub branch protection (server-side backstop)

The native pre-push hook and the `no-pr-to-protected` scan are local gates; protect
the `protectedBranch` on the server too (require PRs, block direct pushes). This is
the authoritative backstop if a local hook is bypassed or absent.

## 6. Point CLAUDE.md at the plugin

Add a short section to the consuming repo's `CLAUDE.md` summarizing the per-issue
flow and the non-negotiables, and pointing at `.claude/milestone-driver.json`, so a
fresh session knows the repo is milestone-driver–driven.

## Verify the gates

| Test | Expected |
|---|---|
| Main-thread `Edit` to a `sourceGlobs` file | **blocked** (force-subagent) — dispatch the implementer instead |
| The same edit from a dispatched subagent | allowed |
| `git commit` with the unit suite red (staged source) | **blocked** (tests-green) |
| `git push` to `protectedBranch` | **blocked** (no-push) |
| `gh pr create --base <protectedBranch>` | **blocked** (no-pr-to-protected) |

Each gate honors a `CLAUDE_HOOK_DISABLE_*` environment escape hatch for deliberate
human override.

## Requirements

- The `superpowers` plugin (the per-issue inner loop depends on it).
- `gh` (authenticated), `git`.
- `pwsh` 7+ **or** `bash` + `jq` for the hooks.
