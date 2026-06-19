#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for ci-preflight-steps.ps1 (issue #162).
# Asserts the pwsh discovery against the SAME tests/fixtures/ci-preflight/_expected/*.txt
# golden files the .sh runner uses — cross-impl parity.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/ci-preflight-steps.ps1'
$fix = 'tests/fixtures/ci-preflight'
$gold = Join-Path $root "$fix/_expected"
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

# name | ciWorkflow | goldenBasename  (blank ciWorkflow/golden -> defaults)
$cases = @(
  'clean-run||',
  'skip-rules||',
  'working-dir||',
  'silent-under-run||',
  'not-gating||',
  'block-scalar||',
  'inline-comment||',
  'multi-workflow||',
  'services||',
  'no-workflows-dir||',
  'multi-workflow|zeta.yml|multi-workflow__zeta'
)

$pass = 0; $fail = 0
# Run from the repo root so the WARN path text is checkout-independent (matches golden).
Push-Location $root
try {
  foreach ($spec in $cases) {
    $parts = $spec -split '\|'
    $name = $parts[0]; $only = $parts[1]; $goldName = $parts[2]
    if ([string]::IsNullOrEmpty($goldName)) { $goldName = $name }
    $exp = Join-Path $gold "$goldName.txt"
    if (-not (Test-Path $exp)) { Write-Host "FAIL ${name}: missing golden $exp"; $fail++; continue }
    # Capture stdout to a temp file and read it back as UTF-8 bytes so a multibyte
    # char (the em-dash in WARN messages) survives byte-exact — the console-pipeline
    # capture (`| Out-String`) re-encodes it and breaks parity on some hosts.
    $tmp = New-TemporaryFile
    if ($only -ne '') {
      Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $script, "$fix/$name", $only) -NoNewWindow -Wait -RedirectStandardOutput $tmp.FullName | Out-Null
    } else {
      Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $script, "$fix/$name") -NoNewWindow -Wait -RedirectStandardOutput $tmp.FullName | Out-Null
    }
    $got = [System.IO.File]::ReadAllText($tmp.FullName, [System.Text.UTF8Encoding]::new($false))
    Remove-Item $tmp.FullName -Force
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
Write-Host "ci-preflight-steps.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
