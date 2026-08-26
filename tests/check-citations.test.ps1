#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for check-citations.ps1 (issue #432).
# Twin of check-citations.test.sh: drives the SAME check-citations.cases.tsv
# table and asserts against the SAME fixtures/check-citations/_expected/*.txt
# golden files, so the bash and pwsh legs of the gate stay byte-identical. See
# that runner's header for what each column means and what each of the nine
# cases plus the bespoke cases prove.
#
# RAW vs NORMALIZED - same rule as the bash leg:
#   * ACTUAL stdout/stderr is captured RAW, via ProcessStartInfo +
#     StreamReader.ReadToEnd, which performs NO newline translation. Load-
#     bearing: joining PowerShell's line-split array (or piping through `>`)
#     normalizes line endings, and a runner that does so cannot observe CRLF
#     creep or a missing trailing newline AT ALL - on the very leg that runs on
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

# HERMETIC GIT EXCLUDES, for every case below - the twin of the .sh runner's
# block, and it must stay identical to it. `--exclude-standard` inside the gate
# under test honors the developer's personal excludes, so a `docs/` line in
# ~/.config/git/ignore reddened gen-ignored locally while CI stayed green.
# GIT_CONFIG_GLOBAL and GIT_CONFIG_NOSYSTEM alone do NOT close it: they drop the
# config FILES, while `core.excludesFile` defaults to $XDG_CONFIG_HOME/git/ignore
# exactly when no config sets it, so the third layer overrides that key outright.
# Neither path is ever created, and git ignores a missing excludes file. The
# tree's own .gitignore and .git/info/exclude are untouched.
$env:GIT_CONFIG_GLOBAL = Join-Path ([System.IO.Path]::GetTempPath()) 'absent-global-gitconfig'
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'core.excludesFile'
$env:GIT_CONFIG_VALUE_0 = Join-Path ([System.IO.Path]::GetTempPath()) 'absent-global-gitexcludes'
$Fix = 'tests/fixtures/check-citations'
$Gold = Join-Path $Root $Fix '_expected'
if (-not (Test-Path $Script)) { Write-Error "FATAL: missing $Script"; exit 3 }
if (-not (Test-Path $Cases)) { Write-Error "FATAL: missing $Cases"; exit 3 }
if (-not (Test-Path (Join-Path $Root $Fix))) { Write-Error "FATAL: missing $Root/$Fix"; exit 3 }
$pwshBin = (Get-Command pwsh).Source

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$ExpectCols = 3

# Eq-Exact - BYTE-EXACT comparison, the assertion this runner's contract
# requires. PowerShell's `-eq` on strings is case-INSENSITIVE and
# culture-sensitive, so it is not that assertion; StringComparison.Ordinal is.
# Same call as tests/resolve-citation.test.ps1 (function Eq-Exact).
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

# Read-Golden - a NAMED-BUT-MISSING golden is FATAL. Returning '' would silently
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

# Invoke-Checker - run the script under test with exact arguments and an
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
  Write-Error "FATAL: parsed 0 cases from $Cases - this run tested nothing"
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
# root - `(Get-Location).Path` here, `${1:-$PWD}` on the bash leg.
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

# ---- bespoke: GENERATED byte-level trees ------------------------------------
# See the .sh runner's matching block for why these cannot be git-tracked
# fixtures (.gitattributes pins tests/fixtures/** to `text eol=lf`, and a FIFO,
# a symlink target and a chmod-000 directory are not git-storable at all) and
# for what each file defeats. Both runners build BYTE-IDENTICAL trees and assert
# the SAME committed goldens, which is what holds the two legs' decoders and
# walks together.
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
$Latin1 = [System.Text.Encoding]::Latin1

# Write-Raw - exact bytes, via the Latin-1 byte<->char bijection the script
# under test uses. Never Set-Content: it would re-encode and add a newline.
function Write-Raw([string]$path, [string]$byteChars) {
  [System.IO.File]::WriteAllBytes($path, $Latin1.GetBytes($byteChars))
}

# Cite - assembles "<n> `<path> (<anchor>)`" plus a newline. Never spelled out
# literally: see the .sh runner's cite_line for why (tests/ is scanned by the
# gate under test, and a literal citation here fails the repo-wide run).
function Cite([int]$n, [string]$path, [string]$anchor) { return "$n ``$path ($anchor)```n" }

function Build-GenBytes([string]$b) {
  New-Item -ItemType Directory -Path (Join-Path $b 'gen' 'docs') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $b 'gen' 'src') -Force | Out-Null
  $e9 = [string][char]0xE9
  Write-Raw (Join-Path $b 'outside.md') "secret string`n"
  Write-Raw (Join-Path $b 'gen' 'docs' 'citing.md') (
    "# Citing`n`n" +
    (Cite 1 'src/crlf.md'      'crlf anchor here') +
    (Cite 2 'src/bom.md'       'bom anchor') +
    (Cite 3 'src/nonewline.md' 'tail anchor') +
    (Cite 4 'src/highbyte.md'  "caf$e9 anchor") +
    (Cite 5 'src/utf16.md'     'utf16 anchor') +
    (Cite 6 '../outside.md'    'secret string'))
  Write-Raw (Join-Path $b 'gen' 'src' 'crlf.md') "# Crlf`r`ncrlf anchor here`r`n"
  $bom = [string][char]0xEF + [string][char]0xBB + [string][char]0xBF
  Write-Raw (Join-Path $b 'gen' 'src' 'bom.md') ($bom + "bom anchor on line one`n")
  Write-Raw (Join-Path $b 'gen' 'src' 'nonewline.md') "# Tail`ntail anchor"
  Write-Raw (Join-Path $b 'gen' 'src' 'highbyte.md') "# High`ncaf$e9 anchor lives here`n"
  $u16 = [string][char]0xFF + [string][char]0xFE
  foreach ($c in "utf16 anchor`n".ToCharArray()) { $u16 += [string]$c + [string][char]0 }
  Write-Raw (Join-Path $b 'gen' 'src' 'utf16.md') $u16
}

# Build-GenIgnored - a REAL git work tree, the only place the gitignore
# exclusion can be exercised: `git ls-files --others --ignored` reports UNTRACKED
# ignored files only, so a committed fixture is never ignored however its own
# .gitignore reads. `scratch.md` is ignored AND carries an anchor that resolves
# nowhere, so the run is green only because the exclusion holds. Returns $false
# when `git init` fails, and the case then reports SKIPPED.
function Build-GenIgnored([string]$b) {
  New-Item -ItemType Directory -Path (Join-Path $b 'gen' 'docs') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $b 'gen' 'src') -Force | Out-Null
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($null -eq $git) { return $false }
  & $git.Source 'init' '-q' (Join-Path $b 'gen') 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { return $false }
  Write-Raw (Join-Path $b 'gen' '.gitignore') "scratch.md`n"
  Write-Raw (Join-Path $b 'gen' 'docs' 'citing.md') (
    "# Citing`n`n" + (Cite 1 'src/target.md' 'live anchor'))
  Write-Raw (Join-Path $b 'gen' 'scratch.md') (
    "# Scratch`n`n" + (Cite 1 'src/target.md' 'anchor that was reworded away'))
  Write-Raw (Join-Path $b 'gen' 'src' 'target.md') "# Target`nlive anchor lives here`n"
  return $true
}

# Unix-only: a FIFO and an unprivileged symlink do not exist on Windows, so the
# case reports SKIPPED there rather than failing. CI runs both legs on Linux.
function Build-GenUnix([string]$b) {
  if ($IsWindows) { return $false }
  New-Item -ItemType Directory -Path (Join-Path $b 'gen' 'docs') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $b 'gen' 'src') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $b 'gen' 'locked') -Force | Out-Null
  Write-Raw (Join-Path $b 'gen' 'docs' 'citing.md') (
    "# Citing`n`n" +
    (Cite 1 'src/real.md' 'real anchor') +
    (Cite 2 'src/link.md' 'real anchor') +
    (Cite 3 'src/pipe.md' 'any anchor'))
  Write-Raw (Join-Path $b 'gen' 'src' 'real.md') "# Real`nreal anchor lives here`n"
  Write-Raw (Join-Path $b 'gen' 'locked' 'plain.md') "# Plain`nNothing worth citing.`n"
  try {
    New-Item -ItemType SymbolicLink -Path (Join-Path $b 'gen' 'src' 'link.md') -Target 'real.md' -ErrorAction Stop | Out-Null
    $mk = Get-Command mkfifo -ErrorAction SilentlyContinue
    if ($null -eq $mk) { return $false }
    & $mk.Source (Join-Path $b 'gen' 'src' 'pipe.md')
    if ($LASTEXITCODE -ne 0) { return $false }
    [System.IO.File]::SetUnixFileMode((Join-Path $b 'gen' 'locked'), [System.IO.UnixFileMode]::None)
  } catch { return $false }
  return $true
}

function Invoke-Generated([string]$gname, [string]$groot, [string]$ggold, [int]$gwant) {
  $gexp = Read-Golden $ggold
  $r = Invoke-Checker @($groot) $Root
  if ($r.rc -eq $gwant -and (Eq-Exact $r.out $gexp) -and (Eq-Exact $r.err '')) {
    $script:pass++
  } else {
    $script:fail++
    Write-Host "FAIL ${gname}: rc=$($r.rc) (want $gwant)"
    Write-Host "  out got  [$(Show-Escaped $r.out)]"
    Write-Host "  out want [$(Show-Escaped $gexp)]"
    Write-Host "  err got  [$(Show-Escaped $r.err)] (want empty)"
  }
}

Build-GenBytes $Tmp
Invoke-Generated 'gen-bytes' (Join-Path $Tmp 'gen') 'gen-bytes.txt' 1

$unixTmp = Join-Path $Tmp 'u'
New-Item -ItemType Directory -Path $unixTmp -Force | Out-Null
$genUnixRan = Build-GenUnix $unixTmp
if ($genUnixRan) {
  Invoke-Generated 'gen-unix' (Join-Path $unixTmp 'gen') 'gen-unix.txt' 1
}
$ignTmp = Join-Path $Tmp 'i'
New-Item -ItemType Directory -Path $ignTmp -Force | Out-Null
$genIgnoredRan = Build-GenIgnored $ignTmp
if ($genIgnoredRan) {
  Invoke-Generated 'gen-ignored' (Join-Path $ignTmp 'gen') 'gen-ignored.txt' 0
}

# Restore the locked directory so the temp tree can be removed.
try {
  $lk = Join-Path $unixTmp 'gen' 'locked'
  if (Test-Path -LiteralPath $lk) {
    [System.IO.File]::SetUnixFileMode($lk, [System.IO.UnixFileMode]'UserRead,UserWrite,UserExecute')
  }
} catch { }
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue

$bespoke = 5
$skipNote = ''
if (-not $genUnixRan) { $bespoke--; $skipNote += ', gen-unix SKIPPED on this platform' }
if (-not $genIgnoredRan) { $bespoke--; $skipNote += ', gen-ignored SKIPPED (no usable git)' }
Write-Host "check-citations.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + $bespoke bespoke$skipNote)"
if ($fail -ne 0) { exit 1 }
