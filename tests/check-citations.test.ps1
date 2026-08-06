#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for check-citations.ps1 (issue #432).
# Twin of check-citations.test.sh: drives the SAME check-citations.cases.tsv
# table and asserts against the SAME fixtures/check-citations/_expected/*.txt
# golden files, so the bash and pwsh legs of the gate stay byte-identical. See
# that runner's header for what each column means and what each of the nine
# cases plus two bespoke cases proves.
#
# RAW vs NORMALIZED — same rule as the bash leg:
#   * ACTUAL stdout/stderr is captured RAW, via ProcessStartInfo +
#     StreamReader.ReadToEnd, which performs NO newline translation. Load-
#     bearing: joining PowerShell's line-split array (or piping through `>`)
#     normalizes line endings, and a runner that does so cannot observe CRLF
#     creep or a missing trailing newline AT ALL — on the very leg that runs on
#     Windows, where CRLF creep is the natural failure mode.
#   * The GOLDEN gets ONE normalization, CRLF -> LF, for a CRLF checkout.
# ProcessStartInfo also gives EXACT argument passing (ArgumentList, no shell
# quoting) and an explicit WorkingDirectory, so the relative fixture roots
# resolve the way the bash leg's `cd "$ROOT"` resolves them and the no-argument
# bespoke case reaches the child with a genuinely empty argument list.
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Script = Join-Path $Root 'scripts' 'check-citations.ps1'
$Cases = Join-Path $Here 'check-citations.cases.tsv'
$Fix = 'tests/fixtures/check-citations'
$Gold = Join-Path $Root $Fix '_expected'
if (-not (Test-Path $Script)) { Write-Error "FATAL: missing $Script"; exit 3 }
if (-not (Test-Path $Cases)) { Write-Error "FATAL: missing $Cases"; exit 3 }
if (-not (Test-Path (Join-Path $Root $Fix))) { Write-Error "FATAL: missing $Root/$Fix"; exit 3 }
$pwshBin = (Get-Command pwsh).Source

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$ExpectCols = 3

# Eq-Exact — BYTE-EXACT comparison, the assertion this runner's contract
# requires. PowerShell's `-eq` on strings is case-INSENSITIVE and
# culture-sensitive, so it is not that assertion; StringComparison.Ordinal is.
# Same call as tests/resolve-citation.test.ps1 (function Eq-Exact).
function Eq-Exact([string]$a, [string]$b) {
  return [string]::Equals($a, $b, [System.StringComparison]::Ordinal)
}

# Show-Escaped — render CR / LF / TAB visibly in a failure report, so a
# line-ending or missing-newline mismatch does not print identically to what it
# was compared against.
function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

# Read-Golden — a NAMED-BUT-MISSING golden is FATAL. Returning '' would silently
# turn such a case into "expect empty stdout", i.e. a green run that asserts
# nothing. CRLF -> LF only; never a blanket \r strip.
function Read-Golden([string]$name) {
  $path = Join-Path $Gold $name
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Error "FATAL: case names a missing golden: $path"
    exit 3
  }
  return ([System.IO.File]::ReadAllText($path, $utf8) -replace "`r`n", "`n")
}

# Invoke-Checker — run the script under test with exact arguments and an
# explicit working directory, returning RAW stdout/stderr text plus the exit
# code. Both streams are read asynchronously BEFORE WaitForExit so a full pipe
# buffer cannot deadlock the child.
function Invoke-Checker([string[]]$scriptArgs, [string]$workDir) {
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
  # the bash leg applies: empty row, or '#' at COLUMN 0.
  $row = $rawRow -replace "`r$", ''
  if ($row -eq '' -or $row.StartsWith('#')) { continue }
  $cols = $row -split "`t"
  if ($cols.Count -ne $ExpectCols) {
    Write-Error "FATAL: row failed to parse (got $($cols.Count) fields, want $ExpectCols): [$row]"
    exit 1
  }
  $caseCount++
  $name = $cols[0]; $golden = $cols[1]; $wantExit = [int]$cols[2]

  $expOut = Read-Golden $golden
  $r = Invoke-Checker @("$Fix/$name") $Root

  if ($r.rc -eq $wantExit -and (Eq-Exact $r.out $expOut) -and (Eq-Exact $r.err '')) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL ${name}: rc=$($r.rc) (want $wantExit)"
    Write-Host "  out got  [$(Show-Escaped $r.out)]"
    Write-Host "  out want [$(Show-Escaped $expOut)]"
    Write-Host "  err got  [$(Show-Escaped $r.err)] (want empty)"
  }
}

if ($caseCount -eq 0) {
  Write-Error "FATAL: parsed 0 cases from $Cases — this run tested nothing"
  exit 1
}

# ---- bespoke: a REPO_ROOT that is not a directory. The stderr golden is SHARED
# with the .sh runner, so the two twins' refusal messages are held byte-identical
# the way the record-stream goldens are.
$wantErr = Read-Golden 'missing-root.stderr.txt'
$r = Invoke-Checker @("$Fix/no-such-root") $Root
if ($r.rc -eq 1 -and (Eq-Exact $r.out '') -and (Eq-Exact $r.err $wantErr)) { $pass++ }
else {
  $fail++
  Write-Host "FAIL missing-root: rc=$($r.rc) (want 1)"
  Write-Host "  out got  [$(Show-Escaped $r.out)] (want empty)"
  Write-Host "  err got  [$(Show-Escaped $r.err)]"
  Write-Host "  err want [$(Show-Escaped $wantErr)]"
}

# ---- bespoke: NO argument at all, run from inside the fixture root. The table
# always passes a root explicitly, so this is the only exercise of the default
# root — `(Get-Location).Path` here, `${1:-$PWD}` on the bash leg.
$expOut = Read-Golden 'resolves-once.txt'
$r = Invoke-Checker @() (Join-Path $Root $Fix 'resolves-once')
if ($r.rc -eq 0 -and (Eq-Exact $r.out $expOut) -and (Eq-Exact $r.err '')) { $pass++ }
else {
  $fail++
  Write-Host "FAIL default-root: rc=$($r.rc) (want 0)"
  Write-Host "  out got  [$(Show-Escaped $r.out)]"
  Write-Host "  out want [$(Show-Escaped $expOut)]"
  Write-Host "  err got  [$(Show-Escaped $r.err)] (want empty)"
}

Write-Host "check-citations.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + 2 bespoke)"
if ($fail -ne 0) { exit 1 }
