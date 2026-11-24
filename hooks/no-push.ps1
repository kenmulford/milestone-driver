#!/usr/bin/env pwsh
# milestone-driver - no-push gate (Claude PreToolUse: Bash, if: Bash(git push *)).
if ($env:CLAUDE_HOOK_DISABLE_NO_PUSH -eq '1') { exit 0 }
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
. (Join-Path $PSScriptRoot 'hook-deny.ps1')
$cmd = $hook.tool_input.command
if (-not $cmd) { exit 0 }
if ($cmd -notmatch 'git\s+push') { exit 0 }
$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'
$profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$protected = $cfg.protectedBranch
$integ = [string]$cfg.integrationBranch
if (-not $protected) { exit 0 }
$blocked = $false
$p = [regex]::Escape($protected)
if ($cmd -match "(^|[\s:/])$p(\s|`$)") { $blocked = $true }
$cur = (git -C $projectDir rev-parse --abbrev-ref HEAD 2>$null); $cur = "$cur".Trim()
if ($cur -eq $protected) { $blocked = $true }
if ($blocked) {
    if (-not $integ) {
        $integ = 'develop'
        git -C $projectDir rev-parse --verify --quiet refs/remotes/origin/develop *> $null
        if ($LASTEXITCODE -ne 0) { $integ = 'dev' }
    }
    Invoke-HookDeny $hook ("milestone-driver: pushing into '$protected' is blocked. Agents stop at the integration branch '$integ'; anything past it is a human step.")
}
exit 0
