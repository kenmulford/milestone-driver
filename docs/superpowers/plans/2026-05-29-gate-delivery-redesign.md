# Gate-Delivery Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace milestone-driver's native git hooks + installer with plugin `PreToolUse` hooks invoked through one cross-platform (bash-first/pwsh-fallback) launcher, and move the consumer profile to the repo root.

**Architecture:** All four gates become `PreToolUse` hooks in `hooks/hooks.json`, each invoked via `hooks/run-hook.cmd <gate>` (a cmd/sh polyglot that runs `<gate>.sh`, else `<gate>.ps1`, else exits 0). Gate scripts read the tool-input JSON from stdin (for `cwd` and `command`) and resolve the profile at `<cwd>/milestone-driver.json`. The native-hook installer is deleted.

**Tech Stack:** Bash + PowerShell hook scripts, `jq` (bash) / `ConvertFrom-Json` (pwsh), Claude Code plugin `hooks.json`, `gh`, `git`.

**Reference:** [design spec](../specs/2026-05-29-gate-delivery-redesign-design.md). Work on `develop`; commits go straight to `develop` (no branch protection yet).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `hooks/run-hook.cmd` | create | Polyglot launcher: pick bash (`<gate>.sh`) → pwsh (`<gate>.ps1`) → exit 0 |
| `hooks/force-subagent.{sh,ps1}` | modify | Profile path → repo root |
| `hooks/tests-green.{sh,ps1}` | rewrite | PreToolUse: read stdin cwd; staged-source check; `unitTestCmd`; exit 2 on red |
| `hooks/no-push.{sh,ps1}` | rewrite | PreToolUse: parse `git push` command + current branch vs `protectedBranch`; exit 2 |
| `hooks/no-pr-to-protected.{sh,ps1}` | modify | Profile path → repo root |
| `hooks/hooks.json` | rewrite | Register all 4 gates via the launcher with `if` predicates |
| `scripts/install-git-hooks.{ps1,sh}` | delete | Native-hook installer no longer needed |
| `docs/profile-schema.md` | modify | Profile location → repo root |
| `docs/consumer-setup.md` | rewrite | Drop install-git-hooks step; root profile; plugin-hook gates |
| `README.md` | modify | Gate table + profile path + requirements |
| `C:/repos/PracticingPrayer/milestone-driver.json` | create | PP profile at root |
| `C:/repos/PracticingPrayer/.claude/milestone-driver.json` | delete | Old location |
| `C:/repos/PracticingPrayer/.gitignore` | modify | Revert the `.claude` un-ignore edit |
| `C:/repos/PracticingPrayer/.git/hooks/{pre-commit,pre-push}` | delete | Remove installed native hooks |
| `C:/repos/PracticingPrayer/CLAUDE.md` | modify | Gates are plugin hooks; no native install |

All hook-test verification uses the in-repo matrices (temp fixture profile + stdin JSON), the same pattern already proven for these scripts.

---

### Task 1: Cross-platform launcher

**Files:**
- Create: `hooks/run-hook.cmd`

- [ ] **Step 1: Create the launcher**

```bat
: << 'CMDBLOCK'
@echo off
REM milestone-driver cross-platform polyglot launcher.
REM Windows: cmd runs this batch half (bash first, then pwsh, else exit 0).
REM Unix: bash runs the sh half below ( : is a no-op; heredoc swallows the batch ).
REM Usage: run-hook.cmd <gate>   (gate = base name, e.g. force-subagent)
if "%~1"=="" (echo run-hook.cmd: missing gate name>&2& exit /b 1)
set "HOOK_DIR=%~dp0"
set "GATE=%~1"
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%GATE%.sh"
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%GATE%.sh"
    exit /b %ERRORLEVEL%
)
where bash >nul 2>nul && (
    bash "%HOOK_DIR%%GATE%.sh"
    exit /b %ERRORLEVEL%
)
where pwsh >nul 2>nul && (
    pwsh -NoProfile -File "%HOOK_DIR%%GATE%.ps1"
    exit /b %ERRORLEVEL%
)
exit /b 0
CMDBLOCK

# Unix: bash ran this file, so bash exists -> run the gate's .sh.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${HOOK_DIR}/$1.sh"
```

- [ ] **Step 2: Probe test — bash branch runs `.sh` and forwards stdin**

Create temp probes and run the launcher:

```bash
d="C:/repos/milestone-driver/hooks"
printf '#!/usr/bin/env bash\nread x; echo "SH:$x"\n' > "$d/probe.sh"
printf '$i = [Console]::In.ReadToEnd(); Write-Output "PS:$i"\n' > "$d/probe.ps1"
echo "HELLO" | bash "$d/run-hook.cmd" probe
```
Expected: `SH:HELLO` (bash branch chosen, stdin forwarded).

- [ ] **Step 3: Probe test — fail-open with no interpreter is logically correct**

Confirm by reading: with neither bash nor pwsh, the batch half reaches `exit /b 0`. (No clean way to remove bash on this machine; verify by inspection that the final batch line is `exit /b 0` and the Unix half only runs under bash.)

- [ ] **Step 4: Clean up probes**

```bash
git -C C:/repos/milestone-driver rm -f --ignore-unmatch hooks/probe.sh hooks/probe.ps1 >/dev/null 2>&1; rm -f C:/repos/milestone-driver/hooks/probe.sh C:/repos/milestone-driver/hooks/probe.ps1
```

- [ ] **Step 5: Commit**

```bash
cd /c/repos/milestone-driver && git add hooks/run-hook.cmd
git commit -m "feat: add cross-platform polyglot hook launcher (bash-first, pwsh-fallback)"
```

---

### Task 2: force-subagent — repo-root profile

**Files:**
- Modify: `hooks/force-subagent.ps1`, `hooks/force-subagent.sh`

- [ ] **Step 1: Update the profile path (.ps1)**

Replace:
```powershell
$profilePath = Join-Path $projectDir '.claude/milestone-driver.json'
```
with:
```powershell
$profilePath = Join-Path $projectDir 'milestone-driver.json'
```

- [ ] **Step 2: Update the profile path (.sh)**

Replace:
```bash
profile="$project_dir/.claude/milestone-driver.json"
```
with:
```bash
profile="$project_dir/milestone-driver.json"
```

- [ ] **Step 3: Re-run the force-subagent matrix (root profile)**

Run the proven force-subagent matrix but write the fixture profile to `<fix>/milestone-driver.json` (not `<fix>/.claude/...`). Expected: ALL PASS (8/8: main+source→2, subagent→0, .md→0, .claude→0, non-source→0, nested→2, no-profile→0, disable→0). Run the `.sh` matrix the same way.

- [ ] **Step 4: Commit**

```bash
cd /c/repos/milestone-driver && git add hooks/force-subagent.ps1 hooks/force-subagent.sh
git commit -m "refactor: force-subagent reads profile from repo root"
```

---

### Task 3: tests-green — PreToolUse plugin hook

**Files:**
- Rewrite: `hooks/tests-green.sh`, `hooks/tests-green.ps1`

- [ ] **Step 1: Rewrite `tests-green.sh`**

```bash
#!/usr/bin/env bash
# milestone-driver — tests-green gate (Claude PreToolUse: Bash, if: Bash(git commit *)).
# Runs unitTestCmd when staged files touch sourceGlobs; blocks the commit on red.
# Deny: exit 2. Requires jq. Escape: CLAUDE_HOOK_DISABLE_TESTS_GREEN=1. Fail-open.
[ "${CLAUDE_HOOK_DISABLE_TESTS_GREEN:-}" = "1" ] && exit 0
input="$(cat)"; [ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"
profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0
unit_cmd="$(jq -r '.unitTestCmd // empty' "$profile" 2>/dev/null)"; unit_cmd="${unit_cmd%$'\r'}"
[ -z "$unit_cmd" ] && exit 0
globs=(); while IFS= read -r g; do g="${g%$'\r'}"; [ -n "$g" ] && globs+=("$g"); done \
  < <(jq -r '.sourceGlobs[]? // empty' "$profile" 2>/dev/null)
touched=0; [ ${#globs[@]} -eq 0 ] && touched=1
while IFS= read -r f; do
  [ -z "$f" ] && continue
  for g in "${globs[@]}"; do pat="${g//\*\*/\*}"; case "$f" in $pat) touched=1; break;; esac; done
  [ "$touched" = "1" ] && break
done < <(git -C "$project_dir" diff --cached --name-only 2>/dev/null)
[ "$touched" = "0" ] && exit 0
echo "milestone-driver: staged source changed — running unit suite ($unit_cmd) ..." >&2
if ! ( cd "$project_dir" && eval "$unit_cmd" ) >&2; then
  echo "milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override." >&2
  exit 2
fi
exit 0
```

- [ ] **Step 2: Rewrite `tests-green.ps1`**

```powershell
#!/usr/bin/env pwsh
# milestone-driver — tests-green gate (Claude PreToolUse: Bash, if: Bash(git commit *)).
if ($env:CLAUDE_HOOK_DISABLE_TESTS_GREEN -eq '1') { exit 0 }
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'
$profilePath = Join-Path $projectDir 'milestone-driver.json'
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$unitCmd = $cfg.unitTestCmd
if (-not $unitCmd) { exit 0 }
$globs = $cfg.sourceGlobs
$staged = @(git -C $projectDir diff --cached --name-only)
$touched = $false
if (-not $globs) { $touched = $true } else {
    foreach ($f in $staged) {
        $rel = ([string]$f) -replace '\\', '/'
        foreach ($g in $globs) { $pat = ([string]$g) -replace '\*\*', '*'; if ($rel -like $pat) { $touched = $true; break } }
        if ($touched) { break }
    }
}
if (-not $touched) { exit 0 }
[Console]::Error.WriteLine("milestone-driver: staged source changed — running unit suite ($unitCmd) ...")
Push-Location $projectDir
try { Invoke-Expression $unitCmd } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override.")
    exit 2
}
exit 0
```

- [ ] **Step 3: Test matrix (real git fixture, stdin JSON)**

Create a temp git repo with `<repo>/milestone-driver.json` (`sourceGlobs:["src/**"]`), stage files, and pipe `{"cwd":"<repo>","tool_input":{"command":"git commit -m x"}}` to each script. Expected (both `.sh` and `.ps1`):

| Case | unitTestCmd | staged | Exit |
|---|---|---|---|
| src + pass | `cmd /c exit 0` (ps1) / `true` (sh) | `src/Foo.cs` | 0 |
| src + fail | `cmd /c exit 1` / `false` | `src/Foo.cs` | 2 |
| doc-only | (fail) | `docs/x.md` | 0 |
| disabled | (fail) | `src/Foo.cs` + `CLAUDE_HOOK_DISABLE_TESTS_GREEN=1` | 0 |

- [ ] **Step 4: Commit**

```bash
cd /c/repos/milestone-driver && git add hooks/tests-green.sh hooks/tests-green.ps1
git commit -m "refactor: tests-green becomes a PreToolUse(Bash) gate reading stdin"
```

---

### Task 4: no-push — PreToolUse plugin hook

**Files:**
- Rewrite: `hooks/no-push.sh`, `hooks/no-push.ps1`

- [ ] **Step 1: Rewrite `no-push.sh`**

```bash
#!/usr/bin/env bash
# milestone-driver — no-push gate (Claude PreToolUse: Bash, if: Bash(git push *)).
# Blocks a push targeting protectedBranch. Deny: exit 2. Requires jq.
# Escape: CLAUDE_HOOK_DISABLE_NO_PUSH=1. Fail-open.
[ "${CLAUDE_HOOK_DISABLE_NO_PUSH:-}" = "1" ] && exit 0
input="$(cat)"; [ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0
[[ "$cmd" =~ git[[:space:]]+push ]] || exit 0
project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"
profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0
protected="$(jq -r '.protectedBranch // empty' "$profile" 2>/dev/null)"; protected="${protected%$'\r'}"
[ -z "$protected" ] && exit 0
blocked=0
# explicit refspec naming the protected branch (e.g. "git push origin master", "HEAD:master", ":refs/heads/master")
if [[ "$cmd" =~ (^|[[:space:]:/])"$protected"([[:space:]]|$) ]]; then blocked=1; fi
# no explicit refspec but currently on the protected branch
cur="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
[ "$cur" = "$protected" ] && blocked=1
if [ "$blocked" = "1" ]; then
  echo "milestone-driver: pushing to protected branch '$protected' is blocked. Push the integration branch and open a PR, or set CLAUDE_HOOK_DISABLE_NO_PUSH=1 to override. (GitHub branch protection is the server-side backstop.)" >&2
  exit 2
fi
exit 0
```

- [ ] **Step 2: Rewrite `no-push.ps1`**

```powershell
#!/usr/bin/env pwsh
# milestone-driver — no-push gate (Claude PreToolUse: Bash, if: Bash(git push *)).
if ($env:CLAUDE_HOOK_DISABLE_NO_PUSH -eq '1') { exit 0 }
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$cmd = $hook.tool_input.command
if (-not $cmd) { exit 0 }
if ($cmd -notmatch 'git\s+push') { exit 0 }
$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'
$profilePath = Join-Path $projectDir 'milestone-driver.json'
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$protected = $cfg.protectedBranch
if (-not $protected) { exit 0 }
$blocked = $false
$p = [regex]::Escape($protected)
if ($cmd -match "(^|[\s:/])$p(\s|`$)") { $blocked = $true }
$cur = (git -C $projectDir rev-parse --abbrev-ref HEAD 2>$null); $cur = "$cur".Trim()
if ($cur -eq $protected) { $blocked = $true }
if ($blocked) {
    [Console]::Error.WriteLine("milestone-driver: pushing to protected branch '$protected' is blocked. Push the integration branch and open a PR, or set CLAUDE_HOOK_DISABLE_NO_PUSH=1 to override. (GitHub branch protection is the server-side backstop.)")
    exit 2
}
exit 0
```

- [ ] **Step 3: Test matrix (git fixture, stdin JSON)**

Temp git repo with `milestone-driver.json` (`protectedBranch:"master"`), checked out on a feature branch. Pipe `{"cwd":"<repo>","tool_input":{"command":"<cmd>"}}`. Expected (both variants):

| Command | Current branch | Exit |
|---|---|---|
| `git push origin master` | feature | 2 |
| `git push origin dev` | feature | 0 |
| `git push` | master | 2 |
| `git push` | feature | 0 |
| `git push origin master` + `CLAUDE_HOOK_DISABLE_NO_PUSH=1` | feature | 0 |

- [ ] **Step 4: Commit**

```bash
cd /c/repos/milestone-driver && git add hooks/no-push.sh hooks/no-push.ps1
git commit -m "refactor: no-push becomes a PreToolUse(Bash) gate parsing git push"
```

---

### Task 5: no-pr-to-protected — repo-root profile

**Files:**
- Modify: `hooks/no-pr-to-protected.ps1`, `hooks/no-pr-to-protected.sh`

- [ ] **Step 1: Update the profile path (.ps1)**

Replace `Join-Path (([string]$projectDir) -replace '\\','/') '.claude/milestone-driver.json'` with `Join-Path (([string]$projectDir) -replace '\\','/') 'milestone-driver.json'`.

- [ ] **Step 2: Update the profile path (.sh)**

Replace `profile="$project_dir/.claude/milestone-driver.json"` with `profile="$project_dir/milestone-driver.json"`.

- [ ] **Step 3: Re-run the no-pr-to-protected matrix (root profile)**

Fixture profile at `<fix>/milestone-driver.json` (`protectedBranch:"master"`). Pipe `{"cwd":"<fix>","tool_input":{"command":"<cmd>"}}`. Expected (both): `--base master`→2, `--base dev`→0, `--base=master`→2, `-B master`→2, no base→0, non-gh→0, `--base master-foo`→0, disabled→0.

- [ ] **Step 4: Commit**

```bash
cd /c/repos/milestone-driver && git add hooks/no-pr-to-protected.ps1 hooks/no-pr-to-protected.sh
git commit -m "refactor: no-pr-to-protected reads profile from repo root"
```

---

### Task 6: Register all gates via the launcher

**Files:**
- Rewrite: `hooks/hooks.json`

- [ ] **Step 1: Rewrite `hooks/hooks.json`**

```json
{
  "description": "milestone-driver mechanical gates (per <repo>/milestone-driver.json), all PreToolUse and invoked via the bash-first/pwsh-fallback launcher run-hook.cmd. force-subagent: main-thread source edits must go through the implementer subagent. tests-green: block git commit when the staged unit suite is red. no-push: block pushes to the protected branch. no-pr-to-protected: block gh pr create against the protected branch.",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" force-subagent", "timeout": 15 }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "if": "Bash(git commit *)", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" tests-green", "timeout": 600 },
          { "type": "command", "if": "Bash(git push *)", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" no-push", "timeout": 15 },
          { "type": "command", "if": "Bash(gh pr create *)", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" no-pr-to-protected", "timeout": 15 }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate**

```bash
cd /c/repos/milestone-driver && node -e "JSON.parse(require('fs').readFileSync('hooks/hooks.json','utf8')); console.log('hooks.json OK')"
claude plugin validate . --strict
```
Expected: `hooks.json OK` and `Validation passed`.

- [ ] **Step 3: Commit**

```bash
cd /c/repos/milestone-driver && git add hooks/hooks.json
git commit -m "feat: register all 4 gates as PreToolUse hooks via the launcher"
```

---

### Task 7: Delete the native-hook installer

**Files:**
- Delete: `scripts/install-git-hooks.ps1`, `scripts/install-git-hooks.sh`

- [ ] **Step 1: Remove the installer (and re-add a scripts/.gitkeep if the dir empties)**

```bash
cd /c/repos/milestone-driver
git rm scripts/install-git-hooks.ps1 scripts/install-git-hooks.sh
[ -z "$(ls -A scripts 2>/dev/null)" ] && : > scripts/.gitkeep && git add scripts/.gitkeep
```

- [ ] **Step 2: Confirm nothing references it**

```bash
grep -rn --exclude-dir=.git "install-git-hooks" . || echo "no references (good)"
```
Expected: only `docs/` matches remain (fixed in Task 8) or "no references".

- [ ] **Step 3: Commit**

```bash
cd /c/repos/milestone-driver && git add -A scripts
git commit -m "chore: remove native-hook installer (gates are plugin hooks now)"
```

---

### Task 8: Update docs

**Files:**
- Modify: `docs/profile-schema.md`, `docs/consumer-setup.md`, `README.md`

- [ ] **Step 1: profile-schema.md — location section**

Replace the `## Location` body:
```
<repo-root>/.claude/milestone-driver.json
```
with:
```
<repo-root>/milestone-driver.json
```
and update the "Commit it" paragraph to drop the `.claude/`-gitignore caveat (root path is always committable).

- [ ] **Step 2: consumer-setup.md — rewrite steps 2–4**

- Step 2 (profile): path is `<repo>/milestone-driver.json`; remove the un-ignore-`.claude` guidance.
- Remove the old Step 3 ("Install the native git hooks" + `install-git-hooks`).
- Renumber: Step 3 = restart Claude Code so hooks load; Step 4 = GitHub branch protection; Step 5 = CLAUDE.md. State all four gates are plugin hooks active after install + restart.
- Verify-the-gates table stays (still accurate).

- [ ] **Step 3: README.md — gate table + profile + requirements**

- Architecture "Hooks" row: "all `PreToolUse`, via `run-hook.cmd` (bash-first, pwsh-fallback)".
- Profile table caption / examples: `<repo>/milestone-driver.json`.
- The mechanical-gates table: note all four are plugin hooks; drop "native `.git/hooks`" wording.
- Requirements: "bash (preferred) or PowerShell 7+; `jq` for the bash path"; drop the install-git-hooks mention.

- [ ] **Step 4: Confirm no stale references**

```bash
cd /c/repos/milestone-driver && grep -rn --exclude-dir=.git -E "install-git-hooks|\.claude/milestone-driver\.json|native .*git hook|pre-commit|pre-push" docs README.md || echo "clean"
```
Expected: no functional stale references (the design spec under docs/superpowers may mention them historically — that's fine).

- [ ] **Step 5: Commit**

```bash
cd /c/repos/milestone-driver && git add docs/profile-schema.md docs/consumer-setup.md README.md
git commit -m "docs: root profile + plugin-hook gates; drop native-hook installer"
```

---

### Task 9: Re-wire PracticingPrayer

**Files:**
- Create: `C:/repos/PracticingPrayer/milestone-driver.json`
- Delete: `C:/repos/PracticingPrayer/.claude/milestone-driver.json`, PP `.git/hooks/{pre-commit,pre-push}`
- Modify: `C:/repos/PracticingPrayer/.gitignore`, `C:/repos/PracticingPrayer/CLAUDE.md`

- [ ] **Step 1: Move the profile to the repo root**

```bash
cd /c/repos/PracticingPrayer
git mv .claude/milestone-driver.json milestone-driver.json 2>/dev/null || { mv .claude/milestone-driver.json milestone-driver.json; }
```
(The profile content is unchanged.)

- [ ] **Step 2: Revert the `.gitignore` un-ignore edit**

Restore the original single line in `C:/repos/PracticingPrayer/.gitignore`:
```
/.claude
```
(remove the `/.claude/*` + `!/.claude/milestone-driver.json` + comment lines added earlier).

- [ ] **Step 3: Remove the installed native hooks**

```bash
cd /c/repos/PracticingPrayer
rm -f .git/hooks/pre-commit .git/hooks/pre-push
[ -f .git/hooks/pre-commit.pre-milestone-driver.bak ] && mv .git/hooks/pre-commit.pre-milestone-driver.bak .git/hooks/pre-commit
[ -f .git/hooks/pre-push.pre-milestone-driver.bak ] && mv .git/hooks/pre-push.pre-milestone-driver.bak .git/hooks/pre-push
```

- [ ] **Step 4: Update PP CLAUDE.md**

In the "Solving a GitHub issue (milestone-driver)" section, change "its profile is `.claude/milestone-driver.json`" → "`milestone-driver.json`", and the gates bullet to note all four are plugin hooks active after install + restart (no native install step).

- [ ] **Step 5: Show the staged PP diff for review (do not commit PP)**

```bash
cd /c/repos/PracticingPrayer && git status --short && git diff --stat
```
PP changes stay uncommitted for the user to land on a feature branch per PP gitflow.

---

### Task 10: Final validation

- [ ] **Step 1: Full gate re-verification**

Re-run the four matrices (Tasks 2–5) once more end-to-end; expected ALL PASS.

- [ ] **Step 2: Plugin validation**

```bash
cd /c/repos/milestone-driver && claude plugin validate . --strict
```
Expected: `Validation passed`.

- [ ] **Step 3: /code-review, then push**

Run `/code-review`; address findings; then:
```bash
cd /c/repos/milestone-driver && git push origin develop
```

- [ ] **Step 4: Resume the dry-run path**

milestone-driver is now wild-tenable. Hand back to the consumer flow: user installs from `develop`, restarts, runs `/solve-issue 27`.
