#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for extract-version.ps1 (issue #158).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$script = Join-Path $here '..' 'scripts' 'extract-version'
$cases = Join-Path $here 'extract-version.cases.tsv'
$pass = 0; $fail = 0
foreach ($line in Get-Content $cases) {
  if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
  $f = $line -split "`t"
  $name = $f[0]; $title = $f[1]; $desc = $f[2]
  $expOut = if ($f.Count -gt 3) { $f[3] } else { '' }
  $expErr = if ($f.Count -gt 4) { $f[4] } else { '' }
  $json = @{ title = $title; description = $desc } | ConvertTo-Json -Compress
  $r = Invoke-Leg -Script $script -Stdin $json
  $out = $r.out -replace '\r?\n$', ''
  $err = $r.err -replace '\r?\n$', ''
  if ($out -eq $expOut -and $err -eq $expErr) { $pass++ }
  else { $fail++; Write-Host "FAIL $name in[$title|$desc] got[out=$out err=$err] want[out=$expOut err=$expErr]" }
}
Write-Host "extract-version ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
