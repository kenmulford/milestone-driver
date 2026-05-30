# milestone-driver — consumer setup

Adopt milestone-driver in a repository in four steps. The whole point is that the
discipline is mechanical, so most of this is one-time wiring.

## 1. Install the plugin (and its dependency)

Install `milestone-driver` and the required [`superpowers`](#requirements) plugin
in Claude Code (dev-install via `claude --plugin-dir`, or from a marketplace once
published). Confirm both are enabled with `/plugin`.

## 2. Add the project profile

The first time you run `/milestone-driver:solve-issue` or `/milestone-driver:solve-milestone`,
the plugin **auto-invokes `/milestone-driver:setup`** if `milestone-driver.json` is absent
or missing a Core key. The bootstrap infers every key it can from repo signals (default branch,
gitflow layout, project type, test scripts) and presents detected defaults — you accept, edit,
or skip. After writing the file it returns control so the original task continues immediately.

You can also run `/milestone-driver:setup` directly at any time to create or repair the profile.

**Manual authoring (fallback):** Create `milestone-driver.json` at the repo root. Only the
Core keys are required. See [`profile-schema.md`](profile-schema.md) for the full schema.
Minimal example (Core keys only):

```json
{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["src/**", "tests/**"]
}
```

Commit it — the gates read this file, so it must be present in every clone and on CI.

## 3. Restart Claude Code

All four gates (`force-subagent`, `tests-green`, `no-push`, `no-pr-to-protected`)
are plugin `PreToolUse` hooks registered in `hooks/hooks.json`. They **load at
session start** — restart Claude Code after installing or updating the plugin so
the hooks take effect. No separate native-hook installation step is required.

## 4. Add GitHub branch protection (server-side backstop)

The plugin hooks are local gates; protect the `protectedBranch` on the server too
(require PRs, block direct pushes). This is the authoritative backstop if a local
hook is bypassed or absent.

## 5. Point CLAUDE.md at the plugin

Add a short section to the consuming repo's `CLAUDE.md` summarizing the per-issue
flow and the non-negotiables, and pointing at `milestone-driver.json`, so a fresh
session knows the repo is milestone-driver–driven.

## Verify the gates

| Test | Expected |
|---|---|
| Main-thread `Edit` to a `sourceGlobs` file | **blocked** (force-subagent) — dispatch the implementer instead |
| The same edit from a dispatched subagent | allowed |
| `git commit` with the unit suite red (staged source) — **when `unitTestCmd` is defined** | **blocked** (tests-green) |
| `git push` to `protectedBranch` | **blocked** (no-push) |
| `gh pr create --base <protectedBranch>` | **blocked** (no-pr-to-protected) |

When `unitTestCmd` is absent, `tests-green` is a no-op — there is no unit gate to verify.

Each gate honors a `CLAUDE_HOOK_DISABLE_*` environment escape hatch for deliberate
human override.

## Requirements

- The `superpowers` plugin (the per-issue inner loop depends on it).
- `gh` (authenticated), `git`.
- `bash` (preferred) or `pwsh` 7+ for the hooks; `jq` is required for the bash path.
