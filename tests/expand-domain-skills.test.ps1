#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for expand-domain-skills.ps1 (issue #589).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$script = Join-Path $here '..' 'scripts' 'expand-domain-skills'
$cases = Join-Path $here 'expand-domain-skills.cases.tsv'
$fix = Join-Path $here 'fixtures' 'expand-domain-skills'
if (-not (Test-Path $cases)) { Write-Error "FATAL: missing $cases"; exit 3 }
if (-not (Test-Path $fix)) { Write-Error "FATAL: missing $fix"; exit 3 }
$pass = 0; $fail = 0
$tmpHome = Join-Path ([System.IO.Path]::GetTempPath()) ('eds-' + [System.Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tmpHome)
Copy-Item -Path (Join-Path $fix '*') -Destination $tmpHome -Recurse
function Strip-Trailing([string]$s) { if ($null -eq $s) { return '' } return ($s -replace '(\r?\n)+$', '') }
function Unesc([string]$s) { if ($null -eq $s) { return '' } return ($s -replace '\\n', "`n") }
foreach ($line in Get-Content $cases) {
  if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
  $f = $line -split "`t"
  $name = $f[0]
  $rootname = if ($f.Count -gt 1) { $f[1] } else { '' }
  $entries = if ($f.Count -gt 2) { $f[2] } else { '' }
  $rawOut = if ($f.Count -gt 3) { $f[3] } else { '' }
  $rawErr = if ($f.Count -gt 4) { $f[4] } else { '' }
  $expOut = Unesc $rawOut
  $expErr = Unesc $rawErr
  $root = if ($rootname -ceq '__EMPTY__') { '' }
    elseif ($rootname.StartsWith('~/', [System.StringComparison]::Ordinal)) { $rootname }
    else { Join-Path $fix $rootname }
  $argv = @($entries -split ' ' | Where-Object { $_ -ne '' })
  $r = Invoke-Spawn -Script $script -Args (@($root) + $argv) -Env @{ HOME = $tmpHome }
  $out = Strip-Trailing $r.out
  $err = Strip-Trailing $r.err
  $rc = $r.rc
  $okOut = [System.StringComparer]::Ordinal.Compare($out, $expOut) -eq 0
  $okErr = [System.StringComparer]::Ordinal.Compare($err, $expErr) -eq 0
  if ($rc -eq 0 -and $okOut -and $okErr) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL $name root[$rootname] entries[$entries] got[rc=$rc out=$out err=$err] want[rc=0 out=$expOut err=$expErr]"
  }
}
Remove-Item -LiteralPath $tmpHome -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "expand-domain-skills ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
