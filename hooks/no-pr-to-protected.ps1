#!/usr/bin/env pwsh
# milestone-driver — no-PR-to-protected gate (Claude PreToolUse: Bash)
#
# Companion to the no-push gate: blocks `gh pr create --base <protected>`
# so the loop never opens a PR targeting the protected branch. (no-push blocks
# pushing to protected; this blocks PRs that target it.)
#
# Deny: exit 2 + stderr. Escape: CLAUDE_HOOK_DISABLE_NO_PUSH=1 (shared with the
# no-push gate). Fail-open on parse/missing-profile.
#
# Residual risk: a bare `gh pr create` with no --base targets the repo's default
# branch; the /milestone-driver:solve-issue skill always passes --base explicitly, and GitHub
# branch protection is the server-side backstop.

if ($env:CLAUDE_HOOK_DISABLE_NO_PUSH -eq '1') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$cmd = $hook.tool_input.command
if (-not $cmd) { exit 0 }
if ($cmd -notmatch 'gh\s+pr\s+create') { exit 0 }

$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'
$profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$protected = $cfg.protectedBranch
if (-not $protected) { exit 0 }

# Extract the --base / -B value and compare exactly.
if ($cmd -match '(?:--base[=\s]+|-B\s+)["'']?([^\s"'']+)') {
    if ($matches[1] -eq $protected) {
        [Console]::Error.WriteLine("milestone-driver: opening a PR to protected branch '$protected' is blocked. Target the integration branch instead, or set CLAUDE_HOOK_DISABLE_NO_PUSH=1 to override.")
        exit 2
    }
}
exit 0
