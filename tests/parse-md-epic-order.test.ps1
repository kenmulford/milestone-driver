#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for parse-md-epic-order.ps1 (issue #266).
# Each row's body/expected_stdout/expected_stderr carry real newlines/tabs
# encoded as literal "\n"/"\t" (backslashes as "\\"), decoded here with a single
# regex pass before piping to the script under test — mirrors the .sh runner's
# printf '%b' decode (tests/parse-md-epic-order.test.sh) so both legs assert the
# SAME case table (cross-impl parity).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'parse-md-epic-order.ps1'
$cases = Join-Path $here 'parse-md-epic-order.cases.tsv'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

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

  $outFile = New-TemporaryFile
  $errFile = New-TemporaryFile
  $body | pwsh -NoProfile -File $script > $outFile.FullName 2> $errFile.FullName
  $gotExit = $LASTEXITCODE
  # Read the captured stdout via -Raw (whole file as ONE string, no line
  # splitting) rather than `$out = ($body | pwsh ... )` pipeline capture. .NET's
  # line-reader (which backs that capture form) treats a lone \r as a line
  # terminator exactly like \n — it would silently split and drop an embedded
  # CR (e.g. the title_embeds_lone_cr case), corrupting the very byte the CR
  # golden case exists to check. -Raw mirrors the bash runner's $(...), which
  # only strips a trailing newline and never touches an interior \r.
  $out = (Get-Content $outFile.FullName -Raw); $out = if ($null -eq $out) { '' } else { $out -replace '\r?\n$', '' }
  $err = (Get-Content $errFile.FullName -Raw); $err = if ($null -eq $err) { '' } else { $err -replace '\r?\n$', '' }
  Remove-Item $outFile.FullName, $errFile.FullName -Force

  if ($out -eq $expOut -and $err -eq $expErr -and $gotExit -eq $expExit) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL $name got[exit=$gotExit out=$out err=$err] want[exit=$expExit out=$expOut err=$expErr]"
  }
}
Write-Host "parse-md-epic-order.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
