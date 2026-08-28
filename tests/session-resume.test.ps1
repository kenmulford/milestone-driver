#!/usr/bin/env pwsh
# milestone-driver - runner for the session-resume.ps1 hook; the pwsh twin of
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here '_lib.ps1'); Set-Leg $Leg
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Hook = Join-Path $Root 'hooks' 'session-resume'
$env:CLAUDE_HOOK_DISABLE_SESSION_RESUME = $null

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

function New-Workspace([string]$profileJson = '{"sourceGlobs":["src/**"]}') {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $w | Out-Null
  if ($profileJson -ne '-') {
    New-Item -ItemType Directory -Path (Join-Path $w '.milestone-config') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $w '.milestone-config' 'driver.json'), $profileJson + "`n", $utf8)
  }
  return $w
}

function Write-State([string]$w, [string]$json) {
  $dir = Join-Path $w '.milestone-config' '.runtime'
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'wave-state.json'), $json, $utf8)
}

function Invoke-Hook([string]$root, [bool]$envOff = $false, [string]$stdinOverride = '') {
  # A [string] param defaults $null to "", so the comparison must be truthiness
  # (empty string is falsy), never `$null -ne $stdinOverride` (always true).
  $payload = if ($stdinOverride) { $stdinOverride } else { (@{ cwd = $root; hook_event_name = 'SessionStart' } | ConvertTo-Json -Compress) }
  $envs = @{}
  if ($envOff) { $envs['CLAUDE_HOOK_DISABLE_SESSION_RESUME'] = '1' }
  return Invoke-Leg -Script $Hook -Stdin $payload -Cwd $Tmp -Env $envs
}

function Expect-Empty([string]$label, $r) {
  if ($r.rc -eq 0 -and [string]::IsNullOrEmpty($r.out.Trim())) { Ok }
  else { No "${label}: rc=$($r.rc) out=[$(Show-Escaped $r.out)]" }
}

# ---- no profile -> silent -------------------------------------------------
$WNP = New-Workspace '-'
Expect-Empty 'no-profile' (Invoke-Hook $WNP)

# ---- profile, no state -> silent -------------------------------------------
$WNS = New-Workspace
Expect-Empty 'profile-no-state' (Invoke-Hook $WNS)

# ---- state with 3 entries: built-green w/PR, parked null PR, abandoned ----
$W3 = New-Workspace
$state3 = @'
{
  "201": {"issue":201,"wave":1,"status":"built-green","branch":"issue/201-x","pr":"https://github.com/o/r/pull/301","isUI":false,"derivedAt":"2026-08-27T10:00:00Z"},
  "202": {"issue":202,"wave":1,"status":"parked","branch":"issue/202-y","pr":null,"isUI":false,"derivedAt":"2026-08-27T10:01:00Z"},
  "203": {"issue":203,"wave":2,"status":"abandoned","branch":"issue/203-z","pr":null,"isUI":true,"derivedAt":"2026-08-27T10:02:00Z"}
}
'@
Write-State $W3 $state3
$r3 = Invoke-Hook $W3
if ($r3.rc -eq 0) { Ok } else { No "three-entries-rc: rc=$($r3.rc) err=[$(Show-Escaped $r3.err)]" }
if ($r3.out -match '201' -and $r3.out -match '202' -and $r3.out -match '203') { Ok }
else { No "three-entries-issues-present: out=[$(Show-Escaped $r3.out)]" }
if ($r3.out -match [regex]::Escape('milestone-driver: context was compacted during a milestone run')) { Ok }
else { No "three-entries-header: out=[$(Show-Escaped $r3.out)]" }
if ($r3.out -match [regex]::Escape('parallel-waves.md (Wave-state checkpoint - consult before probing)')) { Ok }
else { No "three-entries-citation: out=[$(Show-Escaped $r3.out)]" }

# ---- 45 entries -> capped at 40 rows + "... 5 more" ------------------------
$W45 = New-Workspace
$entries = 1..45 | ForEach-Object {
  $n = $_
  "  `"$n`": {`"issue`":$n,`"wave`":1,`"status`":`"built-green`",`"branch`":`"issue/$n-x`",`"pr`":null,`"isUI`":false,`"derivedAt`":`"2026-08-27T10:00:00Z`"}"
}
$state45 = "{`n" + ($entries -join ",`n") + "`n}`n"
Write-State $W45 $state45
$r45 = Invoke-Hook $W45
if ($r45.rc -eq 0) { Ok } else { No "45-entries-rc: rc=$($r45.rc)" }
$rowCount = ([regex]::Matches($r45.out, '(?m)^\|\s*\d+\s*\|')).Count
if ($rowCount -eq 40) { Ok } else { No "45-entries-row-count: got $rowCount want 40, out=[$(Show-Escaped $r45.out)]" }
if ($r45.out -match [regex]::Escape('5 more')) { Ok } else { No "45-entries-more-line: out=[$(Show-Escaped $r45.out)]" }

# ---- malformed state file -> silent ----------------------------------------
$WM = New-Workspace
Write-State $WM '{ not json'
Expect-Empty 'malformed-state' (Invoke-Hook $WM)

# ---- escape env set -> silent, even with a real 3-entry state -------------
Expect-Empty 'escape-hatch' (Invoke-Hook $W3 $true)

# ---- garbage stdin -> silent ------------------------------------------------
Expect-Empty 'garbage-stdin' (Invoke-Hook $Tmp $false 'not json at all {{{')

Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "session-resume ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
