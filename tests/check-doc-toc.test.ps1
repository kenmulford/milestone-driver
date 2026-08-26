#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for check-doc-toc.ps1 (issue #490).
# Asserts the pwsh checker against the SAME
# tests/fixtures/check-doc-toc/_expected/*.txt golden files the .sh runner
# uses - cross-impl parity. See that runner's header for what each of the five
# cases proves, and for the documented fence limitation the
# fenced-pseudo-heading case does and does not cover.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/check-doc-toc.ps1'
$fix = 'tests/fixtures/check-doc-toc'
$gold = Join-Path $root "$fix/_expected"
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

# name|wantExit
$cases = @(
  'compliant|0',
  'fenced-pseudo-heading|0',
  'missing-heading|1',
  'heading-not-first|1',
  'missing-file|1'
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
    # Capture stdout AND stderr to temp files and read them back as UTF-8 bytes,
    # mirroring the check-size-budgets runner. check-doc-toc emits only OK/FAIL,
    # a path from its own ASCII GOVERNED_PATHS table, MISSING, and SUMMARY, so no
    # fixture content can reach stdout and no byte-parity vector is possible here;
    # the UTF-8 read-back is defensive, not asserted. stderr is appended to stdout to
    # mirror the .sh runner's `2>&1`, so a case that starts emitting on stderr
    # fails on BOTH twins instead of only the bash one. Every case here writes
    # nothing to stderr, so the concatenation order is unobservable.
    $tmp = New-TemporaryFile
    $tmpErr = New-TemporaryFile
    $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $script, "$fix/$name") -NoNewWindow -Wait -RedirectStandardOutput $tmp.FullName -RedirectStandardError $tmpErr.FullName -PassThru
    $rc = $p.ExitCode
    $gotOut = [System.IO.File]::ReadAllText($tmp.FullName, [System.Text.UTF8Encoding]::new($false))
    $gotErr = [System.IO.File]::ReadAllText($tmpErr.FullName, [System.Text.UTF8Encoding]::new($false))
    $got = $gotOut + $gotErr
    Remove-Item $tmp.FullName, $tmpErr.FullName -Force
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
Write-Host "check-doc-toc.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
