#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for check-size-budgets.ps1 (issue #295).
# Asserts the pwsh checker against the SAME
# tests/fixtures/check-size-budgets/_expected/*.txt golden files the .sh
# runner uses — cross-impl parity. See that runner's header for what each
# case proves.
#
# Fixture-prose caveat: the line-flat-byte-over tree is a BYTE-FOR-BYTE COPY of
# the at-ceiling tree with one sentence appended to an existing line. Its
# inherited prose therefore describes the at-ceiling copy, not itself: that
# file says it "stands at exactly 5000 bytes", that "both report 5000 here",
# and that its padding line is "sized so this fixture lands on exactly 5000
# bytes", while the file it sits in is 5106 bytes and is the deliberately-over
# case; it also names line-flat-byte-over/ as the sibling from inside
# line-flat-byte-over/. Do not "fix" that prose. The byte-for-byte-copy
# property is what the case rests on, and rewording a byte-pinned fixture moves
# its totals and forces a golden regeneration for no test value.
#
# parity-guard is the fifth case and the only one with no fixture tree: the
# script's FILES/CEILINGS/BYTE_CEILINGS tables are hand-edited parallel arrays
# and no fixture can desync them, so that case builds a desynced COPY of the
# script instead and asserts the refusal. See the block below the loop.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/check-size-budgets.ps1'
$fix = 'tests/fixtures/check-size-budgets'
$gold = Join-Path $root "$fix/_expected"
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

# name|wantExit
$cases = @(
  'at-ceiling|0',
  'one-over|1',
  'line-flat-byte-over|1',
  'missing-file|1'
)

$pass = 0; $fail = 0
# Run from the repo root so any path text in the output is checkout-independent
# (matches golden). Mirrors tests/ci-preflight-steps.test.ps1.
Push-Location $root
try {
  foreach ($spec in $cases) {
    $parts = $spec -split '\|'
    $name = $parts[0]; $wantExit = [int]$parts[1]
    $exp = Join-Path $gold "$name.txt"
    if (-not (Test-Path $exp)) { Write-Host "FAIL ${name}: missing golden $exp"; $fail++; continue }
    # Capture stdout AND stderr to temp files and read them back as UTF-8 bytes
    # so a multibyte char survives byte-exact, mirroring the ci-preflight-steps
    # runner. stderr is appended to stdout to mirror the .sh runner's `2>&1`,
    # so a case that starts emitting on stderr fails on BOTH twins instead of
    # only the bash one. Every fixture case here writes nothing to stderr, so
    # the concatenation order is unobservable and these four comparisons are
    # unchanged; the parity-guard case below reads the two streams separately,
    # because it has to assert stdout is empty.
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

  # --- parity-guard: the length-parity refusal (issue #399) ----------------
  # Same case the .sh runner runs, against the same golden: desync a COPY of
  # the checker (drop the first $ceilings entry, leaving 14/13/14) and assert
  # all three halves of the refusal, EMPTY stdout, exit 1, and the exact stderr
  # line. No fixture tree can reach this path, because a fixture is input and
  # the tables are the script's own source. If a table rewrite ever makes the
  # edit a no-op the case still fails loud: the unmodified copy prints its OK
  # records and stdout is then not empty.
  $guardGold = Join-Path $gold 'parity-guard.stderr.txt'
  if (-not (Test-Path $guardGold)) { Write-Host "FAIL parity-guard: missing golden $guardGold"; $fail++ }
  else {
    $src = [System.IO.File]::ReadAllText($script, [System.Text.UTF8Encoding]::new($false))
    # '$$' is a literal '$' in a .NET replacement string.
    $desynced = $src -replace '(?m)^\$ceilings = @\(\d+, ', '$$ceilings = @('
    $guardScript = Join-Path ([System.IO.Path]::GetTempPath()) ("csb_guard_" + [System.Guid]::NewGuid().ToString('N') + ".ps1")
    # UTF-8 no BOM, and a .ps1 name: pwsh -File rejects any other extension.
    [System.IO.File]::WriteAllText($guardScript, $desynced, [System.Text.UTF8Encoding]::new($false))
    $gOut = New-TemporaryFile
    $gErr = New-TemporaryFile
    $gp = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $guardScript, "$fix/at-ceiling") -NoNewWindow -Wait -RedirectStandardOutput $gOut.FullName -RedirectStandardError $gErr.FullName -PassThru
    $grc = $gp.ExitCode
    $guardOut = [System.IO.File]::ReadAllText($gOut.FullName, [System.Text.UTF8Encoding]::new($false))
    $guardErr = ([System.IO.File]::ReadAllText($gErr.FullName, [System.Text.UTF8Encoding]::new($false)) -replace "`r`n", "`n").TrimEnd("`n")
    Remove-Item $gOut.FullName, $gErr.FullName, $guardScript -Force
    $guardWant = ([System.IO.File]::ReadAllText($guardGold, [System.Text.UTF8Encoding]::new($false)) -replace "`r`n", "`n").TrimEnd("`n")
    if ($guardOut -eq '' -and $grc -eq 1 -and $guardErr -eq $guardWant) { $pass++ }
    else {
      $fail++
      Write-Host "FAIL parity-guard: rc=$grc (want 1), stdout=[$guardOut] (want empty)"
      Write-Host "--- want err ---"; Write-Host $guardWant
      Write-Host "--- got err ----"; Write-Host $guardErr
    }
  }
} finally { Pop-Location }
Write-Host "check-size-budgets.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
