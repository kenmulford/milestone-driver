#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for parse-md-epic-order.ps1 (issue #266).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$script = Join-Path $here '..' 'scripts' 'parse-md-epic-order'
$cases = Join-Path $here 'parse-md-epic-order.cases.tsv'

function Decode([string]$s) {
  [regex]::Replace($s, '\\(.)', {
    param($m)
    switch ($m.Groups[1].Value) {
      'n' { "`n" }
      't' { "`t" }
      'r' { "`r" }
      '\' { '\' }
      default { $m.Value }
    }
  })
}

$pass = 0; $fail = 0
foreach ($line in Get-Content $cases) {
  if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
  $f = $line -split "`t"
  $name = $f[0]
  $body = Decode $f[1]
  $expOut = if ($f.Count -gt 2) { Decode $f[2] } else { '' }
  $expErr = if ($f.Count -gt 3) { Decode $f[3] } else { '' }
  $expExit = if ($f.Count -gt 4) { [int]$f[4] } else { 0 }

  $r = Invoke-Leg -Script $script -Stdin ($body + "`n")
  $gotExit = $r.rc
  $out = $r.out -replace '\r?\n$', ''
  $err = $r.err -replace '\r?\n$', ''

  if ($out -eq $expOut -and $err -eq $expErr -and $gotExit -eq $expExit) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL $name got[exit=$gotExit out=$out err=$err] want[exit=$expExit out=$expOut err=$expErr]"
  }
}
Write-Host "parse-md-epic-order ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
