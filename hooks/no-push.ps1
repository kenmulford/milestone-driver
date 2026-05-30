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
