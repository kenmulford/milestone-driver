---
type: design-spec
project: milestone-driver
topic: gate-delivery-redesign
date: 2026-05-29
status: approved (design) — pending implementation plan
---

# milestone-driver — gate-delivery redesign

## Scope

How the four mechanical gates are **delivered**, **where the consumer profile lives**, and the **cross-platform interpreter strategy**. This does **not** change the gate *logic*, the two skills, the implementer agent, or the autonomy model.

## Problem

The initial build delivered gates `(a) tests-green` and `(b) no-push` as **native git hooks** installed by a script, kept the profile at `.claude/milestone-driver.json`, and registered hooks via `pwsh -File` directly. A design review found three issues that are not tenable for real-world consumers:

- **A — Baked-path fragility.** `install-git-hooks` bakes an absolute path to the plugin's `hooks/` dir into `<repo>/.git/hooks`. Plugin installs live in a **versioned cache** (plugins-reference: a tag-resolved cache dir "includes a 12-character commit-SHA suffix"; discover-plugins troubleshooting: "Plugins are copied to a cache, so paths referencing files outside the plugin directory won't work"; discover-plugins: Claude Code "automatically update[s] … installed plugins at startup"). After any plugin update the baked path is stale → the pre-commit shim's `exec pwsh -File <stale>` fails non-zero → **commits are blocked until the user re-runs the installer.** The local dev test masked this by baking the dev-repo path.
- **B — `.claude/` gitignore collision.** Many repos gitignore `.claude/` (PracticingPrayer: `.gitignore:367` `/.claude`, because `.claude/settings.local.json` is machine-local). A profile there is not reliably committable, and the "commit it" guidance fights the convention.
- **C — pwsh-only invocation.** `hooks.json` ran `pwsh -File …` with no per-OS launcher. pwsh is not the dev-circle default; bash is.

## Decisions (brainstorming, 2026-05-29)

1. **Gate scope:** blocking **Claude-driven** commands is sufficient. GitHub branch protection + required CI backstop human/terminal actions server-side. → native git hooks are unnecessary.
2. **Profile location:** repo root `milestone-driver.json`.
3. **Interpreter:** bash-first, pwsh-fallback, via a polyglot launcher.

## Enabling facts (verified)

- **Plugin `PreToolUse` hooks can block `git commit` / `git push`.** The hooks reference: the `if` field holds one permission rule (e.g. `Bash(git commit *)`), is "Only evaluated on tool events: `PreToolUse`, `PostToolUse`, …", is matched against each subcommand after stripping `VAR=value` ("matches both `FOO=bar git push` and `npm test && git push`"), "runs … always … when the command is too complex to parse", and a `PreToolUse` hook blocks via exit 2 / `permissionDecision: "deny"` — with "no known limitations." This supersedes the original native-hook rationale (`anthropics/claude-code#36389`, "matcher unreliable").
- **Cross-platform launcher precedent:** superpowers `hooks/run-hook.cmd` — a `cmd`/`sh` polyglot (`: << 'CMDBLOCK'` makes bash skip the batch half) that locates bash (Git-for-Windows paths, then PATH), runs the hook, and **fails open** (exit 0) if none. It uses extensionless script names because "Claude Code's Windows auto-detection … prepends `bash` to any command containing `.sh`."

## Design

### 1. All four gates are plugin `PreToolUse` hooks

Registered in `hooks/hooks.json`, each invoked through the launcher:

| Gate | Matcher | `if` predicate | Behavior |
|---|---|---|---|
| `force-subagent` | `Write\|Edit\|MultiEdit\|NotebookEdit` | — | block main-thread edits to `sourceGlobs` |
| `tests-green` | `Bash` | `Bash(git commit *)` | run `unitTestCmd` when staged files touch `sourceGlobs`; block on red |
| `no-push` | `Bash` | `Bash(git push *)` | block a push targeting `protectedBranch` |
| `no-pr-to-protected` | `Bash` | `Bash(gh pr create *)` | block `gh pr create --base <protectedBranch>` |

All block via **exit 2 + stderr**, **fail open** on parse/IO error, and honor `CLAUDE_HOOK_DISABLE_<GATE>` escapes. The `if` predicate scopes which Bash commands spawn the hook; each script also self-checks (so behavior is correct even if `if` is absent).

### 2. Polyglot launcher — bash-first, pwsh-fallback

`hooks/run-hook.cmd` (modeled on superpowers). `hooks.json` invokes `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd" <gate>` (gate = base name, no extension). The launcher:

1. forwards stdin (the tool-input JSON) to the gate script,
2. locates bash (Git-for-Windows standard paths on Windows, then `bash` on PATH; native on Unix) → `bash <dir>/<gate>.sh`,
3. else locates pwsh → `pwsh -NoProfile -File <dir>/<gate>.ps1`,
4. else exits 0 (fail open).

`.sh` is primary; `.ps1` is the fallback. `${CLAUDE_PLUGIN_ROOT}` means it resolves correctly from the versioned install and auto-updates with the plugin. `.sh` extensions are safe here because they appear only **inside** the launcher, never in the `hooks.json` command string.

### 3. Profile at repo root

`<repo>/milestone-driver.json`. Gate scripts resolve `<projectDir>/milestone-driver.json` where `projectDir` = hook-input `cwd` (fallback `${CLAUDE_PROJECT_DIR}`, then `git rev-parse --show-toplevel`). Skills/implementer/docs reference the root path. Always committable; no `.claude/` collision.

### 4. Removed

Native `.git/hooks` gates; `scripts/install-git-hooks.{ps1,sh}`; the baked-path mechanism; the "install git hooks" consumer-setup step; PP's installed `.git/hooks`.

### 5. Kept

The four gates' logic (`.sh` + `.ps1`); the skills; the implementer; `marketplace.json`; the force-subagent matcher and exemptions.

## Trade-offs

- Gates fire only for **Claude-driven** commands (accepted). GitHub branch protection + required CI are the server-side backstop for human/terminal actions.
- `no-push` as a `PreToolUse` hook parses the `git push` command (less precise than a native pre-push's stdin ref list). Heuristic: block when the push targets `protectedBranch` via an explicit refspec **or** the current branch is `protectedBranch`. Server-side protection is the real backstop.
- `tests-green` runs the unit suite **before** the commit executes (equivalent gate, Claude-driven only).

## Verification

- Re-run each gate's input/exit matrix (`.sh` + `.ps1`) adapted to the root profile + launcher invocation.
- Launcher: bash present → runs `.sh`; bash absent + pwsh present → runs `.ps1`; neither → exit 0.
- `claude plugin validate --strict` passes.
- Re-wire PracticingPrayer per this design (profile at root, no `.git/hooks`); the `/solve-issue 27` dry-run validates end-to-end.

## Out of scope

- Gate logic, the skills' methodology, the autonomy model (unchanged).
- Guarding non-Claude / terminal commands (deferred to GitHub branch protection + CI by decision 1).

## Migration outline

1. Add `hooks/run-hook.cmd`; rewrite `hooks/hooks.json` to register the 4 gates via the launcher.
2. Adjust the 4 gate scripts: invoked via the launcher (tool-input JSON on stdin → `cwd`, `command`); resolve the root profile from `cwd`; `tests-green` checks staged files via `git diff --cached` in `cwd`; `no-push` derives the target branch from the `git push` command + current branch (not from a native pre-push's stdin ref list).
3. Update skills (`/solve-issue`, `/solve-milestone`), `implementer`, `consumer-setup.md`, README, and `profile-schema.md` for the root profile path and the "no install-git-hooks step" flow.
4. Delete `scripts/install-git-hooks.{ps1,sh}`.
5. Re-wire PracticingPrayer: move the profile to `<repo>/milestone-driver.json`, revert the `.gitignore` un-ignore edit, remove the installed `.git/hooks`.
