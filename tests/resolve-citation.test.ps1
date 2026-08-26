#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for resolve-citation.ps1 (issue #417).
# Twin of resolve-citation.test.sh: drives the SAME resolve-citation.cases.tsv
# table and asserts against the SAME fixtures/resolve-citation/_expected/*.out
# golden files, so the bash and pwsh legs stay byte-identical. See that runner's
# header for what each column means and what each case proves.
#
# RAW vs NORMALIZED - the distinction this runner turns on (same rule as the
# bash leg):
#   * The ACTUAL stdout/stderr is captured RAW, via ProcessStartInfo +
#     StreamReader.ReadToEnd, which performs NO newline translation. This is
#     load-bearing: joining PowerShell's line-split array (or piping through
#     `>`) normalizes line endings, and a runner that does so cannot observe
#     CRLF creep or a missing trailing newline AT ALL - on the very leg that
#     runs on Windows, where CRLF creep is the natural failure mode.
#   * The GOLDEN file gets ONE normalization, CRLF -> LF, for a CRLF checkout.
#     Deliberately \r\n-scoped, so a golden holding a LONE CR keeps it.
# ProcessStartInfo also gives EXACT argument passing (ArgumentList, no shell
# quoting) and an explicit WorkingDirectory, so the empty-anchor and multi-line
# anchor cases reach the child intact and relative fixture paths resolve the way
# the bash leg's subshell cd resolves them.
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script = (Join-Path $Here '..' 'scripts' 'resolve-citation.ps1')
$Cases = Join-Path $Here 'resolve-citation.cases.tsv'
$Fix = Join-Path $Here 'fixtures' 'resolve-citation'
$Gold = Join-Path $Fix '_expected'
$ScriptName = 'resolve-citation.ps1'
if (-not (Test-Path $Script)) { Write-Error "FATAL: missing $Script"; exit 3 }
if (-not (Test-Path $Cases)) { Write-Error "FATAL: missing $Cases"; exit 3 }
if (-not (Test-Path $Fix)) { Write-Error "FATAL: missing $Fix"; exit 3 }
$Script = (Resolve-Path $Script).Path
$Fix = (Resolve-Path $Fix).Path
$pwshBin = (Get-Command pwsh).Source

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$ExpectCols = 7
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

# Unescape - turns the TSV's literal \n / \t 2-char sequences into real
# characters (parity with the bash leg's `printf '%b'`).
function Unescape([string]$s) {
  if ($null -eq $s) { return '' }
  return (($s -replace '\\n', "`n") -replace '\\t', "`t")
}

# Eq-Exact - BYTE-EXACT string comparison, the assertion this runner's contract
# requires ("asserts stdout and stderr exactly"). PowerShell's `-eq` on strings
# is case-INSENSITIVE and culture-sensitive, so it is not that assertion:
# measured on this host, 'PRIMARY' -eq 'primary' is True, and so is a comparison
# of NFC vs NFD 'café' or of "a" against "a"+U+200B. `-ceq` fixes only the case
# half - it still reports True for both Unicode cases. StringComparison.Ordinal
# is False for all three. The record kind is the FIRST field of the TAB contract
# issue #418 parses, so a case-only divergence would otherwise ship silently on
# the leg that runs on Windows.
# NOTE: this deliberately diverges from the eight sibling pwsh runners, which
# all use bare `-eq` (tests/build-file-index.test.ps1 (if ($out -eq $expOut -and $err -eq $expErr) {) and friends). Migrating
# the house idiom is a separate sweep; this issue's acceptance criteria require
# exact assertion here.
function Eq-Exact([string]$a, [string]$b) {
  return [string]::Equals($a, $b, [System.StringComparison]::Ordinal)
}

# Show-Escaped - render CR / LF / TAB visibly in a failure report, so a
# line-ending or missing-newline mismatch does not print identically to what it
# was compared against.
function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

# Read-Golden - a NAMED-BUT-MISSING golden is FATAL. Returning '' here would
# silently turn such a case into "expect empty stdout", i.e. a green run that
# asserts nothing.
function Read-Golden([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Error "FATAL: names a missing golden: $path"
    exit 3
  }
  # CRLF -> LF only; never a blanket \r strip (see RAW vs NORMALIZED).
  return ([System.IO.File]::ReadAllText($path, $utf8) -replace "`r`n", "`n")
}

# Invoke-Resolver - run the script under test with exact arguments and an
# explicit working directory, returning RAW stdout/stderr text plus the exit
# code. Both streams are read asynchronously BEFORE WaitForExit so a full pipe
# buffer cannot deadlock the child.
function Invoke-Resolver([string[]]$scriptArgs, [string]$workDir) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $pwshBin
  foreach ($a in @('-NoProfile', '-File', $Script)) { [void]$psi.ArgumentList.Add($a) }
  foreach ($a in $scriptArgs) { [void]$psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $workDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $p = [System.Diagnostics.Process]::Start($psi)
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{
    out = $outTask.GetAwaiter().GetResult()
    err = $errTask.GetAwaiter().GetResult()
    rc  = $p.ExitCode
  }
}

$caseCount = 0
foreach ($rawRow in Get-Content -LiteralPath $Cases) {
  # Strip the CRLF checkout's CR FIRST, then apply the SAME blank/comment skip
  # the bash leg applies: empty row, or '#' at COLUMN 0. An earlier '^\s*#'
  # here meant an indented '#' row was silently skipped on this leg while the
  # bash leg FATAL'd on it.
  $row = $rawRow -replace "`r$", ''
  if ($row -eq '' -or $row.StartsWith('#')) { continue }
  $cols = $row -split "`t"
  # Self-guard: a row that doesn't parse into exactly the expected column count
  # is a runner bug (or a corrupt fixture), not a silently-defaulted pass.
  if ($cols.Count -ne $ExpectCols) {
    Write-Error "FATAL: row failed to parse (got $($cols.Count) fields, want $ExpectCols): [$row]"
    exit 1
  }
  $caseCount++
  $name = $cols[0]; $file = $cols[1]; $nargs = $cols[2]; $anchorRaw = $cols[3]
  $stdoutFile = $cols[4]; $wantExit = [int]$cols[5]; $wantStderrRaw = $cols[6]

  $anchor = Unescape $anchorRaw
  # Expected stderr carries its single trailing newline when non-empty, so a
  # host that emitted CRLF there (or dropped the newline) fails.
  $wantErr = Unescape ($wantStderrRaw -replace '__SCRIPT__', $ScriptName)
  if ($wantErr -ne '') { $wantErr = $wantErr + "`n" }
  $expOut = if ($stdoutFile -ne '') { Read-Golden (Join-Path $Gold $stdoutFile) } else { '' }

  $runArgs = switch ($nargs) {
    '0' { @() }
    '1' { @($file) }
    '2' { @($file, $anchor) }
    '3' { @($file, $anchor, 'extra') }
    default { Write-Error "FATAL: unsupported nargs '$nargs' in case $name"; exit 1 }
  }

  $r = Invoke-Resolver $runArgs $Fix

  if ($r.rc -eq $wantExit -and (Eq-Exact $r.out $expOut) -and (Eq-Exact $r.err $wantErr)) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL ${name}: rc=$($r.rc) (want $wantExit)"
    # Escaped rendering so a CR / missing-newline mismatch is visible rather
    # than printing identically to the expected text.
    Write-Host "  out got  [$(Show-Escaped $r.out)]"
    Write-Host "  out want [$(Show-Escaped $expOut)]"
    Write-Host "  err got  [$(Show-Escaped $r.err)]"
    Write-Host "  err want [$(Show-Escaped $wantErr)]"
  }
}

# Self-guard: zero parsed cases means every row was skipped or the table is
# empty - the suite would otherwise report "0 passed, 0 failed" as a clean,
# misleadingly-green exit.
if ($caseCount -eq 0) {
  Write-Error "FATAL: parsed 0 cases from $Cases - this run tested nothing"
  exit 1
}

# ---- bespoke case: a CRLF input file. See the bash leg's matching case: git
# renormalizes a committed CRLF fixture, so it is generated at run time.
$crlf = Join-Path $Tmp 'crlf.md'
[System.IO.File]::WriteAllText($crlf, "alpha line`r`nbeta anchor here`r`ngamma line`r`n", $utf8)
$r = Invoke-Resolver @($crlf, 'beta anchor') $Tmp
$want = "PRIMARY`t2`tbeta anchor here`n"
if ($r.rc -eq 0 -and (Eq-Exact $r.out $want) -and (Eq-Exact $r.err '')) { $pass++ }
else {
  $fail++
  Write-Host "FAIL crlf_no_stray_cr: rc=$($r.rc) (want 0)"
  Write-Host "  out got  [$(Show-Escaped $r.out)]"
  Write-Host "  out want [$(Show-Escaped $want)]"
  Write-Host "  err got  [$(Show-Escaped $r.err)]"
}

Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
Write-Host "resolve-citation.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + 1 bespoke)"
if ($fail -ne 0) { exit 1 }
