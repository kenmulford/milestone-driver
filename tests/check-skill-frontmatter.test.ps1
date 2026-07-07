#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for check-skill-frontmatter.ps1 (issue #314).
# Asserts the pwsh checker against the SAME
# tests/fixtures/check-skill-frontmatter/_expected/*.txt golden files the .sh
# runner uses — cross-impl parity. See that runner's header for what each case
# proves.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/check-skill-frontmatter.ps1'
$fix = 'tests/fixtures/check-skill-frontmatter'
$gold = Join-Path $root "$fix/_expected"
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

# name|wantExit
$cases = @(
  'clean|0',
  'defect|1',
  'missing-file|1',
  'no-frontmatter|1'
)

$pass = 0; $fail = 0
# Run from the repo root so any path text in the output is checkout-independent
# (matches golden). Mirrors tests/check-size-budgets.test.ps1.
Push-Location $root
try {
  foreach ($spec in $cases) {
    $parts = $spec -split '\|'
    $name = $parts[0]; $wantExit = [int]$parts[1]
    $exp = Join-Path $gold "$name.txt"
    if (-not (Test-Path $exp)) { Write-Host "FAIL ${name}: missing golden $exp"; $fail++; continue }
    # Capture stdout to a temp file and read it back as UTF-8 bytes so a
    # multibyte char survives byte-exact — mirrors the check-size-budgets runner.
    $tmp = New-TemporaryFile
    $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $script, "$fix/$name") -NoNewWindow -Wait -RedirectStandardOutput $tmp.FullName -PassThru
    $rc = $p.ExitCode
    $got = [System.IO.File]::ReadAllText($tmp.FullName, [System.Text.UTF8Encoding]::new($false))
    Remove-Item $tmp.FullName -Force
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
Write-Host "check-skill-frontmatter.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
