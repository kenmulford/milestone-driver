#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for extract-version.ps1 (issue #158).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'extract-version.ps1'
$cases = Join-Path $here 'extract-version.cases.tsv'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }
$pass = 0; $fail = 0
foreach ($line in Get-Content $cases) {
  if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
  $f = $line -split "`t"
  $name = $f[0]; $title = $f[1]; $desc = $f[2]
  $expOut = if ($f.Count -gt 3) { $f[3] } else { '' }
  $expErr = if ($f.Count -gt 4) { $f[4] } else { '' }
  $json = @{ title = $title; description = $desc } | ConvertTo-Json -Compress
  $errFile = New-TemporaryFile
  $out = ($json | pwsh -NoProfile -File $script 2> $errFile.FullName)
  # Compare byte-exact like the bash runner (whose $(...) strips only a trailing
  # newline). Strip a single trailing CR/LF the pipeline may add — NOT a broad
  # .Trim(), which would mask leading/internal-whitespace divergence between impls.
  $out = ("$out") -replace '\r?\n$', ''
  $err = (Get-Content $errFile.FullName -Raw); $err = if ($null -eq $err) { '' } else { $err -replace '\r?\n$', '' }
  Remove-Item $errFile.FullName -Force
  if ($out -eq $expOut -and $err -eq $expErr) { $pass++ }
  else { $fail++; Write-Host "FAIL $name in[$title|$desc] got[out=$out err=$err] want[out=$expOut err=$expErr]" }
}
Write-Host "extract-version.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
