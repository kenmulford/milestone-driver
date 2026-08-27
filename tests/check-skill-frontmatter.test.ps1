#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for check-skill-frontmatter.ps1 (issue #314).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/check-skill-frontmatter'
$fix = 'tests/fixtures/check-skill-frontmatter'
$gold = Join-Path $root "$fix/_expected"

$cases = @(
  'clean|0',
  'defect|1',
  'missing-file|1',
  'no-frontmatter|1'
)

$pass = 0; $fail = 0
Push-Location $root
try {
  foreach ($spec in $cases) {
    $parts = $spec -split '\|'
    $name = $parts[0]; $wantExit = [int]$parts[1]
    $exp = Join-Path $gold "$name.txt"
    if (-not (Test-Path $exp)) { Write-Host "FAIL ${name}: missing golden $exp"; $fail++; continue }
    $r = Invoke-Leg -Script $script -Args @("$fix/$name")
    $rc = $r.rc
    $got = $r.out
    $gotN = ($got -replace "`r`n", "`n").TrimEnd("`n")
    $want = ([System.IO.File]::ReadAllText($exp, [System.Text.UTF8Encoding]::new($false)) -replace "`r`n", "`n").TrimEnd("`n")
    if ($gotN -eq $want -and $rc -eq $wantExit) { $pass++ }
    else {
      $fail++
      Write-Host "FAIL $name`: rc=$rc (want $wantExit)"
      Write-Host "--- want ---"; Write-Host $want
      Write-Host "--- got ----"; Write-Host $gotN
    }
  }
} finally { Pop-Location }
Write-Host "check-skill-frontmatter ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
