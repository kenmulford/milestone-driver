#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for resolve-citation.ps1 (issue #417).
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script = (Join-Path $Here '..' 'scripts' 'resolve-citation.ps1')
$Cases = Join-Path $Here 'resolve-citation.cases.tsv'
$Fix = Join-Path $Here 'fixtures' 'resolve-citation'
$Gold = Join-Path $Fix '_expected'
$ScriptName = 'resolve-citation.ps1'
if (-not (Test-Path $Script)) { Write-Error "FATAL: missing $Script"; exit 3 }
if (-not (Test-Path $Cases)) { Write-Error "FATAL: missing $Cases"; exit 3 }
if (-not (Test-Path $Fix)) { Write-Error "FATAL: missing $Fix"; exit 3 }
$Script = (Resolve-Path $Script).Path
$Fix = (Resolve-Path $Fix).Path
$pwshBin = (Get-Command pwsh).Source

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$ExpectCols = 7
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Unescape([string]$s) {
  if ($null -eq $s) { return '' }
  return (($s -replace '\\n', "`n") -replace '\\t', "`t")
}

# requires ("asserts stdout and stderr exactly"). PowerShell's `-eq` on strings
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

function Invoke-Resolver([string[]]$scriptArgs, [string]$workDir) {
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
  $name = $cols[0]; $file = $cols[1]; $nargs = $cols[2]; $anchorRaw = $cols[3]
  $stdoutFile = $cols[4]; $wantExit = [int]$cols[5]; $wantStderrRaw = $cols[6]

  $anchor = Unescape $anchorRaw
  $wantErr = Unescape ($wantStderrRaw -replace '__SCRIPT__', $ScriptName)
  if ($wantErr -ne '') { $wantErr = $wantErr + "`n" }
  $expOut = if ($stdoutFile -ne '') { Read-Golden (Join-Path $Gold $stdoutFile) } else { '' }

  $runArgs = switch ($nargs) {
    '0' { @() }
    '1' { @($file) }
    '2' { @($file, $anchor) }
    '3' { @($file, $anchor, 'extra') }
    default { Write-Error "FATAL: unsupported nargs '$nargs' in case $name"; exit 1 }
  }

  $r = Invoke-Resolver $runArgs $Fix

  if ($r.rc -eq $wantExit -and (Eq-Exact $r.out $expOut) -and (Eq-Exact $r.err $wantErr)) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL ${name}: rc=$($r.rc) (want $wantExit)"
    Write-Host "  out got  [$(Show-Escaped $r.out)]"
    Write-Host "  out want [$(Show-Escaped $expOut)]"
    Write-Host "  err got  [$(Show-Escaped $r.err)]"
    Write-Host "  err want [$(Show-Escaped $wantErr)]"
  }
}

if ($caseCount -eq 0) {
  Write-Error "FATAL: parsed 0 cases from $Cases - this run tested nothing"
  exit 1
}

# ---- bespoke case: a CRLF input file. See the bash leg's matching case: git
$crlf = Join-Path $Tmp 'crlf.md'
[System.IO.File]::WriteAllText($crlf, "alpha line`r`nbeta anchor here`r`ngamma line`r`n", $utf8)
$r = Invoke-Resolver @($crlf, 'beta anchor') $Tmp
$want = "PRIMARY`t2`tbeta anchor here`n"
if ($r.rc -eq 0 -and (Eq-Exact $r.out $want) -and (Eq-Exact $r.err '')) { $pass++ }
else {
  $fail++
  Write-Host "FAIL crlf_no_stray_cr: rc=$($r.rc) (want 0)"
  Write-Host "  out got  [$(Show-Escaped $r.out)]"
  Write-Host "  out want [$(Show-Escaped $want)]"
  Write-Host "  err got  [$(Show-Escaped $r.err)]"
}

Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
Write-Host "resolve-citation.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + 1 bespoke)"
if ($fail -ne 0) { exit 1 }
