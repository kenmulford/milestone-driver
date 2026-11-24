#!/usr/bin/env pwsh
# milestone-driver - dispatch-cap gate (Claude PreToolUse: Agent|Task|Skill, Codex: spawn_agent)
#
# pwsh twin of dispatch-cap.sh (rules and key/counter shape documented there).
# Deny: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON). Escape: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1. Fail-open.

if ($env:CLAUDE_HOOK_DISABLE_DISPATCH_CAP -eq '1') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
. (Join-Path $PSScriptRoot 'hook-deny.ps1')
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

$mainAgent = $false; $branch = $null
if ($tool -ceq 'Skill') {
    $who = [string]$hook.tool_input.skill
    $who = $who.Substring($who.LastIndexOf(':') + 1)
    $field = 'args'
} elseif ($tool -ceq 'Agent' -or $tool -ceq 'Task') {
    $tool = 'Agent'; $field = 'prompt'; $mainAgent = $true   # the raw name: Codex spawn_agent also rewrites tool to Agent
    $who = [string]$hook.tool_input.subagent_type
} elseif ($tool -clike '*spawn_agent') {
    # Codex encrypts the spawn message, so runtime-codex.md names the child
    # `<agent>_issue_<n>_<attempt>` or `<agent>_milestone_<n>_<attempt>` in task_name;
    # the bare name maps back to the row.
    $tool = 'Agent'; $field = 'task_name'
    $who = ([string]$hook.tool_input.task_name) -creplace '^.*/', '' -creplace '_(issue|milestone).*$', ''
    $who = if ($who -ceq $implementer.Substring($implementer.LastIndexOf(':') + 1)) { $implementer } else { "milestone-driver:$who" }
} else {
    exit 0
}

# Dispatch contract: runs before the table, so a denied dispatch never reads or writes a counter.
# A failing branch read or a detached HEAD (`HEAD`) allows.
if ($mainAgent -and (-not $who -or $who -in @('general-purpose', 'claude', 'fork'))) {
    $branch = & git -C $projectDir rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { exit 0 }
    $branch = [string]$branch
    if ($branch -clike 'issue/*' -or $branch -clike 'wave/*' -or $branch -clike 'milestone-*') {
        $subject = if ($who) { "subagent_type $who" } else { 'no subagent_type' }
        $roster = "$implementer, milestone-driver:planner, milestone-driver:reviewer, milestone-driver:triage-reviewer, milestone-driver:design-reviewer, milestone-driver:blocker-resolver, milestone-driver:process-auditor, milestone-coherence-reviewer:coherence-reviewer"
        Invoke-HookDeny $hook "milestone-driver: dispatch contract - a main-thread Agent dispatch with $subject is denied on branch $branch. Dispatch a named agent: $roster. Operator override: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1."
    }
}

$table = @(
    @('Skill', 'code-review', 'review', 3),
    @('Agent', $implementer, 'implementer', 3),
    @('Agent', 'milestone-driver:planner', 'planner', 2)
)
$kind = ''
$Cap = 0
foreach ($row in $table) {
    if ($row[0] -ceq $tool -and $row[1] -ceq $who) { $kind = $row[2]; $Cap = $row[3]; break }
}
if (-not $kind) { exit 0 }
$text = [string]$hook.tool_input.$field

if ($null -eq $branch) {
    $branch = & git -C $projectDir rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { exit 0 }
    $branch = [string]$branch
}
$key = ''
$token = ''
$msKey = $false
$mb = [regex]::Match($branch, '^milestone-(\d+)-')
if ($kind -cne 'review' -and $mb.Success) {
    $reMarker = if ($field -ceq 'task_name') { '_milestone_(\d+)_' } else { '^\s*Milestone-End-Fix:\s*(\d+)' }
    $mk = [regex]::Match($text, $reMarker)
    if ($mk.Success -and $mk.Groups[1].Value -ceq $mb.Groups[1].Value) {
        $key = "milestone-$($mb.Groups[1].Value)"; $token = $branch; $msKey = $true
        if ($kind -ceq 'planner') { $Cap = 1 }
    }
}
$m = [regex]::Match($branch, '^issue/(\d+)')
if (-not $key -and $m.Success) { $key = $m.Groups[1].Value }
if (-not $key) { $m = [regex]::Match($text, '[Ii]ssue[\s#:/_-]*(\d+)'); if ($m.Success) { $key = $m.Groups[1].Value } }
if (-not $key) { $m = [regex]::Match($text, '#(\d+)'); if ($m.Success) { $key = $m.Groups[1].Value } }
if (-not $key) { $key = $branch -replace '[^A-Za-z0-9._-]', '_' }
if (-not $key) { $key = 'default' }

$common = & git -C $projectDir rev-parse --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0) { exit 0 }
$common = ([string]$common) -replace '\\', '/'
if (-not [System.IO.Path]::IsPathRooted($common)) { $common = Join-Path $projectDir $common }
if (-not $token) {
    $token = & git -C $projectDir rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { $token = 'none' }
    $token = [string]$token
}

$dir = Join-Path $common 'milestone-driver' 'dispatch-cap'
try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { exit 0 }
$file = Join-Path $dir "$kind-$key"

$count = 0
if (Test-Path -LiteralPath $file) {
    try {
        $parts = ((Get-Content -LiteralPath $file -Raw -ErrorAction Stop).Trim()) -split ' '
        if ($parts.Count -ge 2 -and $parts[0] -ceq $token -and $parts[1] -match '^\d+$') { $count = [int]$parts[1] }
    } catch { $count = 0 }
}

if ($count -ge $Cap) {
    $root = if ($env:CLAUDE_PLUGIN_ROOT) { "$($env:CLAUDE_PLUGIN_ROOT)/" } else { '' }
    if ($msKey) {
        Invoke-HookDeny $hook ("milestone-driver: dispatch cap - this would be $kind dispatch $($count + 1) of at most $Cap for milestone end $($mb.Groups[1].Value). Follow the cap-spent path of ${root}skills/solve-milestone/milestone-end-gates.md; its Halt runs ${root}scripts/reset-dispatch-cap.<sh|ps1> <repo-root> $key, so a resumed milestone end starts a fresh budget. Operator override: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1.")
    }
    $what = if ($key -match '^[0-9]+$') { "issue $key" } else { "branch $key" }
    Invoke-HookDeny $hook ("milestone-driver: dispatch cap - this would be $kind dispatch $($count + 1) of at most $Cap for $what (${root}skills/review-depth.md § The ladder). Park the issue; the park action clears this counter. Operator override: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1.")
}

try { [System.IO.File]::WriteAllText($file, "$token $($count + 1)`n", [System.Text.UTF8Encoding]::new($false)) } catch { }
exit 0
