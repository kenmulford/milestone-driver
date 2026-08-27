#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for build-file-index.ps1 (issue #318).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$script = Join-Path $here '..' 'scripts' 'build-file-index'
$cases = Join-Path $here 'build-file-index.cases.tsv'
$fix = Join-Path $here 'fixtures' 'build-file-index'
$gold = Join-Path $fix '_expected'
if (-not (Test-Path $cases)) { Write-Error "FATAL: missing $cases"; exit 3 }

$utf8 = [System.Text.UTF8Encoding]::new($false)
function Read-Text([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return '' }
  $t = [System.IO.File]::ReadAllText($path, $utf8)
  ($t -replace "`r", '') -replace "`n$", ''
}

$pass = 0; $fail = 0
foreach ($line in Get-Content -LiteralPath $cases) {
  if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
  $f = $line -split "`t"
  $name = $f[0]; $fixture = $f[1]; $caseInput = $f[2]
  $stdoutFile = if ($f.Count -gt 3) { $f[3] } else { '' }
  $expErr = if ($f.Count -gt 4) { $f[4] } else { '' }
  $expOut = if ($stdoutFile -ne '') { Read-Text (Join-Path $gold $stdoutFile) } else { '' }

  $r = Invoke-Spawn -Script $script -Stdin $caseInput -Cwd (Join-Path $fix $fixture)
  $out = ($r.out -replace "`r", '') -replace "`n$", ''
  $err = ($r.err -replace "`r", '') -replace "`n$", ''

  if ($out -eq $expOut -and $err -eq $expErr) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL $name"
    Write-Host "  out got  [$out]"
    Write-Host "  out want [$expOut]"
    Write-Host "  err got[$err] want[$expErr]"
  }
}
Write-Host "build-file-index ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
