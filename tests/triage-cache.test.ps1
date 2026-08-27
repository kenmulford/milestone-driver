#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for triage-cache.ps1 (issue #441).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Script = Join-Path $Root 'scripts' 'triage-cache.ps1'
$Cases = Join-Path $Here 'triage-cache.cases.tsv'
$Fix = Join-Path $Here 'fixtures' 'triage-cache'
$Gold = Join-Path $Fix '_expected'
$ScriptName = 'triage-cache.ps1'
$RepoGitignore = Join-Path $Root '.milestone-config' '.gitignore'
if (-not (Test-Path $Script)) { Write-Error "FATAL: missing $Script"; exit 3 }
if (-not (Test-Path $Cases)) { Write-Error "FATAL: missing $Cases"; exit 3 }
if (-not (Test-Path $Fix)) { Write-Error "FATAL: missing $Fix"; exit 3 }
$Script = (Resolve-Path $Script).Path
$Fix = (Resolve-Path $Fix).Path
$pwshBin = (Get-Command pwsh).Source

$utf8 = [System.Text.UTF8Encoding]::new($false)
$TAB = "`t"
$pass = 0; $fail = 0
$ExpectCols = 5
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Eq-Exact([string]$a, [string]$b) {
  return [string]::Equals($a, $b, [System.StringComparison]::Ordinal)
}

function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

function Read-Golden([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Error "FATAL: names a missing golden: $path"
    exit 3
  }
  return ([System.IO.File]::ReadAllText($path, $utf8) -replace "`r`n", "`n")
}

function Ok { $script:pass++ }
function No([string]$msg) { $script:fail++; Write-Host "FAIL $msg" }

function Invoke-Tc([string[]]$scriptArgs, [string]$workDir, [string]$envPath = $null) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $pwshBin
  foreach ($a in @('-NoProfile', '-File', $Script)) { [void]$psi.ArgumentList.Add($a) }
  foreach ($a in $scriptArgs) { [void]$psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $workDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  if ($null -ne $envPath) { $psi.Environment['PATH'] = $envPath }
  $p = [System.Diagnostics.Process]::Start($psi)
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{
    out = $outTask.GetAwaiter().GetResult()
    err = $errTask.GetAwaiter().GetResult()
    rc  = $p.ExitCode
  }
}

$caseCount = 0
foreach ($rawRow in Get-Content -LiteralPath $Cases) {
  $row = $rawRow -replace "`r$", ''
  if ($row -eq '' -or $row.StartsWith('#')) { continue }
  $cols = $row -split "`t"
  if ($cols.Count -ne $ExpectCols) {
    Write-Error "FATAL: row failed to parse (got $($cols.Count) fields, want $ExpectCols): [$row]"
    exit 1
  }
  $caseCount++
  $name = $cols[0]; $argsCell = $cols[1]; $stdoutFile = $cols[2]
  $wantExit = [int]$cols[3]; $stderrFile = $cols[4]

  $expOut = if ($stdoutFile -ne '') { Read-Golden (Join-Path $Gold $stdoutFile) } else { '' }
  $expErr = ''
  if ($stderrFile -ne '') {
    $expErr = (Read-Golden (Join-Path $Gold $stderrFile)) -replace '__SCRIPT__', $ScriptName
  }

  $runArgs = @($argsCell -split ' ')
  $r = Invoke-Tc $runArgs $Fix

  if ($r.rc -eq $wantExit -and (Eq-Exact $r.out $expOut) -and (Eq-Exact $r.err $expErr)) { Ok }
  else {
    No "${name}: rc=$($r.rc) (want $wantExit)"
    Write-Host "  out got  [$(Show-Escaped $r.out)]"
    Write-Host "  out want [$(Show-Escaped $expOut)]"
    Write-Host "  err got  [$(Show-Escaped $r.err)]"
    Write-Host "  err want [$(Show-Escaped $expErr)]"
  }
}

if ($caseCount -eq 0) {
  Write-Error "FATAL: parsed 0 cases from $Cases - this run tested nothing"
  exit 1
}

$wsSeq = 0
function New-Workspace {
  $script:wsSeq++
  $p = Join-Path $Tmp "ws$($script:wsSeq)"
  New-Item -ItemType Directory -Path $p | Out-Null
  return $p
}
function Get-Json([string]$path) {
  return ([System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($path, $utf8))).RootElement
}

# ---- write: merge onto an existing canonical cache --------------------------
$W = New-Workspace
Copy-Item -Path (Join-Path $Fix 'roots' 'hit' '.milestone-config') -Destination $W -Recurse
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$cachePath = Join-Path $W '.milestone-config' 'triage-cache.json'
$okMerge = $false
if ($r.rc -eq 0 -and (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n") -and (Eq-Exact $r.err '')) {
  $c = Get-Json $cachePath
  $names = @($c.EnumerateObject() | ForEach-Object { $_.Name } | Sort-Object)
  $okMerge = ((($names -join ',') -ceq '11,7,9') -and
    ($c.GetProperty('7').GetProperty('key').GetString() -ceq '7:2026-08-01T00:00:00Z:3:alpha,zeta') -and
    ($c.GetProperty('11').GetProperty('key').GetString() -ceq '11:2026-08-02T00:00:00Z:0:') -and
    ($c.GetProperty('9').GetProperty('key').GetString() -ceq '9:STALE-KEY') -and
    ($c.GetProperty('9').GetProperty('triaged_at').GetString() -ceq '2026-08-01T01:00:00Z') -and
    ($c.GetProperty('9').GetProperty('result').GetProperty('edges').GetRawText() -replace '\s', '') -ceq '[100]' -and
    ($c.GetProperty('11').GetProperty('result').GetProperty('risk').GetString() -ceq 'heavy'))
}
if ($okMerge) { Ok } else { No "write-merge: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

# ---- write: self-healed .gitignore is byte-identical to the committed one ----
if (-not (Test-Path -LiteralPath $RepoGitignore)) { No "write-gitignore: missing $RepoGitignore" }
else {
  $a = [System.IO.File]::ReadAllBytes((Join-Path $W '.milestone-config' '.gitignore'))
  $b = [System.IO.File]::ReadAllBytes($RepoGitignore)
  if ([System.Linq.Enumerable]::SequenceEqual($a, $b)) { Ok }
  else { No "write-gitignore: differs from $RepoGitignore ($($a.Length) vs $($b.Length) bytes)" }
}

# ---- write: an EXISTING .gitignore is never rewritten ------------------------
$W = New-Workspace
New-Item -ItemType Directory -Path (Join-Path $W '.milestone-config') | Out-Null
[System.IO.File]::WriteAllBytes((Join-Path $W '.milestone-config' '.gitignore'), $utf8.GetBytes("sentinel`n"))
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$kept = [System.IO.File]::ReadAllText((Join-Path $W '.milestone-config' '.gitignore'), $utf8)
if ($r.rc -eq 0 -and (Eq-Exact $kept "sentinel`n")) { Ok }
else { No "write-gitignore-preserved: rc=$($r.rc) content=[$(Show-Escaped $kept)]" }

# ---- write: legacy root cache is READ, then REMOVED --------------------------
$W = New-Workspace
Copy-Item -Path (Join-Path $Fix 'roots' 'legacy-only' '.milestone-driver-triage-cache.json') -Destination $W
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$legacyGone = -not (Test-Path -LiteralPath (Join-Path $W '.milestone-driver-triage-cache.json'))
$merged = @()
if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' 'triage-cache.json'))) {
  $merged = @((Get-Json (Join-Path $W '.milestone-config' 'triage-cache.json')).EnumerateObject() |
              ForEach-Object { $_.Name } | Sort-Object)
}
if ($r.rc -eq 0 -and $legacyGone -and (($merged -join ',') -ceq '11,7,9')) { Ok }
else { No "write-legacy-cleanup: rc=$($r.rc) legacyGone=$legacyGone keys=$($merged -join ',')" }

# ---- write: every failure path is exit 0 + one SKIP record -------------------
$W = New-Workspace
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-bad.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
if ($r.rc -eq 0 -and (Eq-Exact $r.out "SKIP${TAB}bad-entries`n") -and (Eq-Exact $r.err '') -and
    -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' 'triage-cache.json'))) { Ok }
else { No "write-bad-entries: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

$W = New-Workspace
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'does-not-exist.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
if ($r.rc -eq 0 -and (Eq-Exact $r.out "SKIP${TAB}bad-entries`n") -and (Eq-Exact $r.err '')) { Ok }
else { No "write-missing-entries: rc=$($r.rc) out=[$(Show-Escaped $r.out)]" }

$W = New-Workspace
[System.IO.File]::WriteAllBytes((Join-Path $W '.milestone-config'), $utf8.GetBytes(''))
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
if ($r.rc -eq 0 -and (Eq-Exact $r.out "SKIP${TAB}mkdir-failed`n") -and (Eq-Exact $r.err '')) { Ok }
else { No "write-mkdir-failed: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

$W = New-Workspace
$ro = Join-Path $W '.milestone-config'
New-Item -ItemType Directory -Path $ro | Out-Null
if ($IsWindows) { $chmodOk = $false } else { chmod 555 $ro; $chmodOk = $true }
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
if (-not $chmodOk -or (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n")) { Ok }
elseif ($r.rc -eq 0 -and (Eq-Exact $r.out "SKIP${TAB}write-failed`n") -and (Eq-Exact $r.err '')) { Ok }
else { No "write-failed: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }
if ($chmodOk) { chmod 755 $ro }

# ---- write -> lookup round trip: what write stores is what lookup compares ---
$W = New-Workspace
Copy-Item -Path (Join-Path $Fix 'roots' 'hit' '.milestone-config') -Destination $W -Recurse
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$rt = Invoke-Tc @('lookup', $W, (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$rtWant = "HIT${TAB}7`nMISS${TAB}9${TAB}key-mismatch`nEDGES${TAB}100`nSUMMARY${TAB}hits=1${TAB}misses=1`n"
if ($r.rc -eq 0 -and (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n") -and
    $rt.rc -eq 0 -and (Eq-Exact $rt.out $rtWant) -and (Eq-Exact $rt.err '')) { Ok }
else { No "write-lookup-roundtrip: rc=$($r.rc) out=[$(Show-Escaped $r.out)] lookup_rc=$($rt.rc) lookup=[$(Show-Escaped $rt.out)] err=[$(Show-Escaped $rt.err)]" }

# ---- write: the KEY-LESS entries object Step 6.5 actually builds -------------
$W = New-Workspace
Copy-Item -Path (Join-Path $Fix 'roots' 'hit' '.milestone-config') -Destination $W -Recurse
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-keyless.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$kl = Invoke-Tc @('lookup', $W, (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$okKeyless = $false
if ($r.rc -eq 0 -and (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n") -and (Eq-Exact $r.err '')) {
  $c = Get-Json (Join-Path $W '.milestone-config' 'triage-cache.json')
  $has11Key = @($c.GetProperty('11').EnumerateObject() | ForEach-Object { $_.Name }) -ccontains 'key'
  $key7 = ''
  if (@($c.GetProperty('7').EnumerateObject() | ForEach-Object { $_.Name }) -ccontains 'key') {
    $key7 = $c.GetProperty('7').GetProperty('key').GetString()
  }
  $okKeyless = (($key7 -ceq '7:2026-08-01T00:00:00Z:3:alpha,zeta') -and
    (-not $has11Key) -and
    ($c.GetProperty('11').GetProperty('result').GetProperty('risk').GetString() -ceq 'heavy') -and
    ($c.GetProperty('9').GetProperty('triaged_at').GetString() -ceq '2026-08-01T01:00:00Z') -and
    $kl.out.StartsWith("HIT${TAB}7`n"))
}
if ($okKeyless) { Ok }
else { No "write-keyless-entries: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)] lookup=[$(Show-Escaped $kl.out)]" }

# ---- write with THREE arguments is usage/exit 2, never a 3-arg write ---------
$W = New-Workspace
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json')) $Tmp
$wantErr = (Read-Golden (Join-Path $Gold 'usage.err')) -replace '__SCRIPT__', $ScriptName
if ($r.rc -eq 2 -and (Eq-Exact $r.out '') -and (Eq-Exact $r.err $wantErr) -and
    -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config'))) { Ok }
else { No "write-wrong-argc: rc=$($r.rc) (want 2) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

# ---- write: an ABSENT response is the fail-open degradation, not a failure ----
$W = New-Workspace
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'absent.json')) $Tmp
$keptKey = ''
if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' 'triage-cache.json'))) {
  $keptKey = (Get-Json (Join-Path $W '.milestone-config' 'triage-cache.json')).GetProperty('7').GetProperty('key').GetString()
}
if ($r.rc -eq 0 -and (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n") -and (Eq-Exact $r.err '') -and
    ($keptKey -ceq '7:2026-08-02T00:00:00Z:4:alpha,zeta')) { Ok }
else { No "write-absent-response: rc=$($r.rc) out=[$(Show-Escaped $r.out)] key=[$keptKey]" }

# ---- pwsh-only: no external tool is consulted --------------------------------
$r = Invoke-Tc @('lookup', (Join-Path $Fix 'roots' 'hit'), (Join-Path $Fix 'resp' 'ts-two.json')) $Fix ''
$expOut = Read-Golden (Join-Path $Gold 'lookup-hit.out')
if ($r.rc -eq 0 -and (Eq-Exact $r.out $expOut) -and (Eq-Exact $r.err '')) { Ok }
else { No "empty-PATH-lookup: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

if (-not $IsWindows) { chmod -R u+w $Tmp 2>$null }
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
$bespoke = $pass + $fail - $caseCount
Write-Host "triage-cache.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + $bespoke bespoke)"
if ($fail -ne 0) { exit 1 }
