#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for ci-preflight-steps.ps1 (issue #162).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/ci-preflight-steps'
$fix = 'tests/fixtures/ci-preflight'
$gold = Join-Path $root "$fix/_expected"

$cases = @(
  'clean-run||',
  'skip-rules||',
  'working-dir||',
  'silent-under-run||',
  'not-gating||',
  'block-scalar||',
  'inline-comment||',
  'multi-workflow||',
  'sort-order||',
  'services||',
  'no-workflows-dir||',
  'multi-workflow|zeta.yml|multi-workflow__zeta'
)

$pass = 0; $fail = 0
Push-Location $root
try {
  foreach ($spec in $cases) {
    $parts = $spec -split '\|'
    $name = $parts[0]; $only = $parts[1]; $goldName = $parts[2]
    if ([string]::IsNullOrEmpty($goldName)) { $goldName = $name }
    $exp = Join-Path $gold "$goldName.txt"
    if (-not (Test-Path $exp)) { Write-Host "FAIL ${name}: missing golden $exp"; $fail++; continue }
    $argv = @("$fix/$name"); if ($only -ne '') { $argv += $only }
    $got = (Invoke-Leg -Script $script -Args $argv).out
    $gotN = ($got -replace "`r`n", "`n").TrimEnd("`n")
    $want = ([System.IO.File]::ReadAllText($exp, [System.Text.UTF8Encoding]::new($false)) -replace "`r`n", "`n").TrimEnd("`n")
    if ($gotN -eq $want) { $pass++ }
    else {
      $fail++
      Write-Host "FAIL $name"
      Write-Host "--- want ---"; Write-Host $want
      Write-Host "--- got ----"; Write-Host $gotN
    }
  }
} finally { Pop-Location }
Write-Host "ci-preflight-steps ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
