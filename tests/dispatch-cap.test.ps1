#!/usr/bin/env pwsh
# milestone-driver - runner for the dispatch-cap.ps1 hook; the pwsh twin of
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Hook = Join-Path $Root 'hooks' 'dispatch-cap.ps1'
if (-not (Test-Path -LiteralPath $Hook)) { Write-Error "FATAL: missing $Hook"; exit 3 }
$Hook = (Resolve-Path $Hook).Path
$pwshBin = (Get-Command pwsh).Source
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }
$env:CLAUDE_HOOK_DISABLE_DISPATCH_CAP = $null

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Ok { $script:pass++ }
function No([string]$msg) { $script:fail++; Write-Host "FAIL $msg" }
function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

$Impl = 'milestone-driver:implementer'

function New-Workspace([string]$branch = 'issue/7-x', [string]$profileJson = '{"sourceGlobs":["src/**"]}') {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $w | Out-Null
  & git -C $w init -q 2>$null | Out-Null
  & git -C $w config core.hooksPath (Join-Path $w '.git' 'no-such-hooks') 2>$null | Out-Null
  & git -C $w config commit.gpgsign false 2>$null | Out-Null
  & git -C $w config user.email 'tests@milestone-driver.invalid' 2>$null | Out-Null
  & git -C $w config user.name 'dispatch-cap tests' 2>$null | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $w 'README.md'), "seed`n", $utf8)
  & git -C $w add -A 2>$null | Out-Null
  & git -C $w commit -q -m base 2>$null | Out-Null
  & git -C $w checkout -q -b $branch 2>$null | Out-Null
  if ($profileJson -ne '-') {
    New-Item -ItemType Directory -Path (Join-Path $w '.milestone-config') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $w '.milestone-config' 'driver.json'), $profileJson + "`n", $utf8)
  }
  return $w
}

function Invoke-Hook([string]$root, [string]$tool, [string]$who, [string]$text, [string]$agentId = '', [bool]$envOff = $false) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $pwshBin
  foreach ($a in @('-NoProfile', '-File', $Hook)) { [void]$psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $Tmp
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardInputEncoding = $utf8
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  if ($envOff) { $psi.Environment['CLAUDE_HOOK_DISABLE_DISPATCH_CAP'] = '1' }
  if ($tool -eq 'Skill') { $ti = @{ skill = $who; args = $text } }
  else { $ti = @{ subagent_type = $who; prompt = $text } }
  $obj = @{ tool_name = $tool; tool_input = $ti; cwd = $root }
  if ($agentId) { $obj['agent_id'] = $agentId }
  $payload = $obj | ConvertTo-Json -Compress
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($payload)
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{
    out = $outTask.GetAwaiter().GetResult()
    err = $errTask.GetAwaiter().GetResult()
    rc  = $p.ExitCode
  }
}

function Expect([string]$label, $r, [int]$want) {
  if ($r.rc -eq $want) { Ok } else { No "${label}: rc=$($r.rc) (want $want) err=[$(Show-Escaped $r.err)]" }
}

# ---- implementer: 3 dispatches allowed, the 4th denied --------------------
$W = New-Workspace
foreach ($i in 1..3) { Expect "implementer-allow-$i" (Invoke-Hook $W 'Agent' $Impl 'Build issue #7') 0 }
$r = Invoke-Hook $W 'Agent' $Impl 'Build issue #7'
Expect 'implementer-deny-4th' $r 2
if ($r.err -match 'dispatch cap' -and $r.err -match 'implementer dispatch 4 of at most 3 for issue 7') { Ok }
else { No "implementer-deny-message: err=[$(Show-Escaped $r.err)]" }

# ---- the counter file -------------------------------------------------------
$f = Join-Path $W '.git' 'milestone-driver' 'dispatch-cap' 'implementer-7'
if ((Test-Path -LiteralPath $f) -and ((Get-Content -LiteralPath $f -Raw).Trim() -split ' ')[1] -eq '3') { Ok }
else { No "counter-file: [$f]" }

# ---- review: its own counter, 3 allowed, the 4th denied --------------------
foreach ($i in 1..3) { Expect "review-allow-$i" (Invoke-Hook $W 'Skill' 'code-review' '') 0 }
Expect 'review-deny-4th' (Invoke-Hook $W 'Skill' 'code-review' '') 2
Expect 'review-deny-namespaced' (Invoke-Hook $W 'Skill' 'code-review:code-review' '') 2

# ---- never counted: other agents and other skills, even on a capped key ---
Expect 'allow-other-agent' (Invoke-Hook $W 'Agent' 'general-purpose' 'Review #7') 0
Expect 'allow-other-skill' (Invoke-Hook $W 'Skill' 'superpowers:brainstorming' '') 0
Expect 'allow-other-tool' (Invoke-Hook $W 'Bash' '' '') 0

# ---- allow: subagent context on the capped key ----------------------------
Expect 'allow-subagent-context' (Invoke-Hook $W 'Agent' $Impl 'Build issue #7' 'agent-1') 0

# ---- allow: the escape hatch on the capped key -----------------------------
Expect 'allow-escape-hatch' (Invoke-Hook $W 'Agent' $Impl 'x' '' $true) 0

# ---- a moved HEAD resets the budget ----------------------------------------
[System.IO.File]::AppendAllText((Join-Path $W 'README.md'), "more`n", $utf8)
& git -C $W commit -q -am step 2>$null | Out-Null
Expect 'reset-on-new-head' (Invoke-Hook $W 'Agent' $Impl 'Build issue #7') 0

# ---- allow: no profile means not a milestone-driver repo -------------------
$WN = New-Workspace 'issue/7-x' '-'
$r = $null
foreach ($i in 1..4) { $r = Invoke-Hook $WN 'Agent' $Impl 'x' }
Expect 'allow-no-profile' $r 0

# ---- legacy Task tool name is counted like Agent ---------------------------
$WT = New-Workspace
foreach ($i in 1..3) { [void](Invoke-Hook $WT 'Task' $Impl 'x') }
Expect 'task-deny-4th' (Invoke-Hook $WT 'Task' $Impl 'x') 2

# ---- a profile's implementerAgent override is what gets counted ------------
$WC = New-Workspace 'issue/7-x' '{"implementerAgent":"acme:builder"}'
foreach ($i in 1..4) { $r = Invoke-Hook $WC 'Agent' $Impl 'x' }
Expect 'custom-agent-default-name-uncounted' $r 0
foreach ($i in 1..3) { [void](Invoke-Hook $WC 'Agent' 'acme:builder' 'x') }
Expect 'custom-agent-deny-4th' (Invoke-Hook $WC 'Agent' 'acme:builder' 'x') 2

# ---- off an issue branch, the brief names the issue ------------------------
$WP = New-Workspace 'develop'
foreach ($i in 1..3) { [void](Invoke-Hook $WP 'Agent' $Impl 'Issue #11: add the thing. Depends on #3.') }
$r = Invoke-Hook $WP 'Agent' $Impl 'Issue #11: add the thing. Depends on #3.'
Expect 'brief-key-deny-4th' $r 2
if ($r.err -match 'for issue 11 ') { Ok } else { No "brief-key-is-11: err=[$(Show-Escaped $r.err)]" }
Expect 'brief-key-other-issue-allowed' (Invoke-Hook $WP 'Agent' $Impl 'issue 12 - the other thing') 0
if (Test-Path -LiteralPath (Join-Path $WP '.git' 'milestone-driver' 'dispatch-cap' 'implementer-12')) { Ok } else { No 'brief-key-12-counter' }
Expect 'branch-key-fallback' (Invoke-Hook $WP 'Skill' 'code-review' '') 0
if (Test-Path -LiteralPath (Join-Path $WP '.git' 'milestone-driver' 'dispatch-cap' 'review-develop')) { Ok } else { No 'branch-key-counter' }
foreach ($i in 1..2) { [void](Invoke-Hook $WP 'Skill' 'code-review' '') }
$r = Invoke-Hook $WP 'Skill' 'code-review' ''
Expect 'branch-key-deny-4th' $r 2
if ($r.err -match 'for branch develop ') { Ok } else { No "branch-key-message: err=[$(Show-Escaped $r.err)]" }

# ---- a malformed profile still gates, with the default implementer name -----
$WM = New-Workspace 'issue/7-x' '{ not json'
foreach ($i in 1..3) { [void](Invoke-Hook $WM 'Agent' $Impl 'x') }
Expect 'malformed-profile-deny-4th' (Invoke-Hook $WM 'Agent' $Impl 'x') 2

Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "dispatch-cap.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
