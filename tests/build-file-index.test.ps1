#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for build-file-index.ps1 (issue #318).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'build-file-index.ps1'
$cases = Join-Path $here 'build-file-index.cases.tsv'
$fix = Join-Path $here 'fixtures' 'build-file-index'
$gold = Join-Path $fix '_expected'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }
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

  $inFile = New-TemporaryFile
  $outFile = New-TemporaryFile
  $errFile = New-TemporaryFile
  [System.IO.File]::WriteAllText($inFile.FullName, $caseInput, $utf8)
  Start-Process -FilePath 'pwsh' `
    -ArgumentList @('-NoProfile', '-File', $script) `
    -WorkingDirectory (Join-Path $fix $fixture) `
    -RedirectStandardInput $inFile.FullName `
    -RedirectStandardOutput $outFile.FullName `
    -RedirectStandardError $errFile.FullName `
    -NoNewWindow -Wait | Out-Null
  $out = Read-Text $outFile.FullName
  $err = Read-Text $errFile.FullName
  Remove-Item $inFile.FullName, $outFile.FullName, $errFile.FullName -Force -ErrorAction SilentlyContinue

  if ($out -eq $expOut -and $err -eq $expErr) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL $name"
    Write-Host "  out got  [$out]"
    Write-Host "  out want [$expOut]"
    Write-Host "  err got[$err] want[$expErr]"
  }
}
Write-Host "build-file-index.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
