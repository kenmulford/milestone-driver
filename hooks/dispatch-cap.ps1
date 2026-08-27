#!/usr/bin/env pwsh
# milestone-driver - dispatch-cap gate (Claude PreToolUse: Agent|Task|Skill)
#
# pwsh twin of dispatch-cap.sh (rules and key/counter shape documented there).
# Deny: exit 2 + stderr. Escape: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1. Fail-open.

if ($env:CLAUDE_HOOK_DISABLE_DISPATCH_CAP -eq '1') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { exit 0 }

foreach ($field in @($hook.agent_id, $hook.agent_type, $hook.parent_session_id)) {
    if ($field -and "$field".Length -gt 0) { exit 0 }
}

$tool = [string]$hook.tool_name
if (-not $tool) { exit 0 }

$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'

$profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
if (-not (Test-Path -LiteralPath $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
if (-not (Test-Path -LiteralPath $profilePath)) { exit 0 }
try { $cfg = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $cfg = $null }
$implementer = [string]$cfg.implementerAgent
if (-not $implementer) { $implementer = 'milestone-driver:implementer' }

$Cap = 3
$kind = ''
$text = ''
if ($tool -ceq 'Skill') {
    $skill = [string]$hook.tool_input.skill
    if ($skill -ceq 'code-review' -or $skill.EndsWith(':code-review', [StringComparison]::Ordinal)) { $kind = 'review' } else { exit 0 }
    $text = [string]$hook.tool_input.args
} elseif ($tool -ceq 'Agent' -or $tool -ceq 'Task') {
    $st = [string]$hook.tool_input.subagent_type
    if ($st -cne $implementer) { exit 0 }
    $kind = 'implementer'
    $text = [string]$hook.tool_input.prompt
} else {
    exit 0
}

$branch = & git -C $projectDir rev-parse --abbrev-ref HEAD 2>$null
if ($LASTEXITCODE -ne 0) { exit 0 }
$branch = [string]$branch
$key = ''
$m = [regex]::Match($branch, '^issue/(\d+)')
if ($m.Success) { $key = $m.Groups[1].Value }
if (-not $key) { $m = [regex]::Match($text, '[Ii]ssue[\s#:/_-]*(\d+)'); if ($m.Success) { $key = $m.Groups[1].Value } }
if (-not $key) { $m = [regex]::Match($text, '#(\d+)'); if ($m.Success) { $key = $m.Groups[1].Value } }
if (-not $key) { $key = $branch -replace '[^A-Za-z0-9._-]', '_' }
if (-not $key) { $key = 'default' }

$common = & git -C $projectDir rev-parse --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0) { exit 0 }
$common = ([string]$common) -replace '\\', '/'
if (-not [System.IO.Path]::IsPathRooted($common)) { $common = Join-Path $projectDir $common }
$head = & git -C $projectDir rev-parse HEAD 2>$null
if ($LASTEXITCODE -ne 0) { $head = 'none' }
$head = [string]$head

$dir = Join-Path $common 'milestone-driver' 'dispatch-cap'
try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { exit 0 }
$file = Join-Path $dir "$kind-$key"

$count = 0
if (Test-Path -LiteralPath $file) {
    try {
        $parts = ((Get-Content -LiteralPath $file -Raw -ErrorAction Stop).Trim()) -split ' '
        if ($parts.Count -ge 2 -and $parts[0] -ceq $head -and $parts[1] -match '^\d+$') { $count = [int]$parts[1] }
    } catch { $count = 0 }
}

if ($count -ge $Cap) {
    $what = if ($key -match '^[0-9]+$') { "issue $key" } else { "branch $key" }
    [Console]::Error.WriteLine("milestone-driver: dispatch cap - this would be $kind dispatch $($count + 1) of at most $Cap for $what (skills/review-depth.md § The ladder). Park the issue instead of dispatching again. Reset: delete '$file', or set CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1 to override.")
    exit 2
}

try { [System.IO.File]::WriteAllText($file, "$head $($count + 1)`n", [System.Text.UTF8Encoding]::new($false)) } catch { }
exit 0
