#!/usr/bin/env pwsh
# milestone-driver - session-resume hook (Claude SessionStart, matcher: compact)
#
# pwsh twin of session-resume.sh (rules, input field, and table shape
# documented there). Escape: CLAUDE_HOOK_DISABLE_SESSION_RESUME=1. Exit 0
# always - context-injection only, never a gate.

if ($env:CLAUDE_HOOK_DISABLE_SESSION_RESUME -eq '1') { exit 0 }

# Force UTF-8 stdout (no BOM): the header line carries a non-ASCII arrow, and
# Windows PowerShell's default console encoding is the system codepage, which
# silently substitutes '?' for it (scripts/check-doc-toc.ps1, same fix).
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$raw = [Console]::In.ReadToEnd()
$hook = $null
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $hook = $null }

$projectDir = if ($hook) { [string]$hook.cwd } else { $null }
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'

$profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
if (-not (Test-Path -LiteralPath $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
if (-not (Test-Path -LiteralPath $profilePath)) { exit 0 }

$statePath = Join-Path $projectDir '.milestone-config' '.runtime' 'wave-state.json'
if (-not (Test-Path -LiteralPath $statePath)) { exit 0 }

try { $state = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$entries = @($state.PSObject.Properties | ForEach-Object { $_.Value } | Where-Object { $_ -and $_.issue })
if ($entries.Count -eq 0) { exit 0 }
$entries = $entries | Sort-Object { [int]$_.issue }

$cap = 40
$rows = @()
$more = 0
$i = 0
foreach ($e in $entries) {
    $i++
    if ($i -le $cap) {
        $status = if ($e.status) { $e.status } else { '-' }
        $branch = if ($e.branch) { $e.branch } else { '-' }
        $pr = if ($e.pr) { $e.pr } else { '-' }
        $rows += "| $($e.issue) | $($e.wave) | $status | $branch | $pr |"
    } else {
        $more++
    }
}

$lines = @()
$lines += '▶ milestone-driver: context was compacted during a milestone run. Resume from the checkpoint.'
$lines += ''
$lines += '| Issue | Wave | Status | Branch | PR |'
$lines += '|---|---|---|---|---|'
$lines += $rows
if ($more -gt 0) { $lines += "… $more more" }
$lines += ''
$lines += 'skills/solve-milestone/parallel-waves.md (Wave-state checkpoint - consult before probing)'

[Console]::Out.Write(($lines -join "`n") + "`n")
exit 0
