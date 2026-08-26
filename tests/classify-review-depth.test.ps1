#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for classify-review-depth.ps1 (issue #598).
# Behavior-identical pwsh sibling of tests/classify-review-depth.test.sh: same
# tests/classify-review-depth.cases.tsv table (including its `|`-separated
# multi-value cells, its working-tree `ops` column and that column's `R:` run
# root), then three bespoke cases rather than the bash leg's four: this leg
# reads sourceGlobs with ConvertFrom-Json, so it has no jq dependency to strip
# and no `no-jq` to assert.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'classify-review-depth.ps1'
$cases = Join-Path $here 'classify-review-depth.cases.tsv'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }

$pass = 0; $fail = 0
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("crd-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$errFile = Join-Path $tmp 'err'

# Byte-exact writes: UTF-8 without a BOM and LF line endings, so the fixture
# tree the classifier sees is identical to what the bash runner builds.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Fixture([string]$path, [string]$content) {
  $dir = Split-Path -Parent $path
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

# New-Repo <dir> - a throwaway repo pinned against the developer's global git
# config: no hooks, no signing, no CRLF translation, fixed identity.
# core.quotePath is deliberately left at its default, because the classifier has
# to pin it itself and a pre-pinned fixture would hide that.
function New-Repo([string]$d) {
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  & git -C $d init -q 2>$null | Out-Null
  & git -C $d config core.hooksPath (Join-Path $d '.git/no-such-hooks') 2>$null | Out-Null
  & git -C $d config commit.gpgsign false 2>$null | Out-Null
  & git -C $d config core.autocrlf false 2>$null | Out-Null
  & git -C $d config core.safecrlf false 2>$null | Out-Null
  & git -C $d config core.filemode false 2>$null | Out-Null
  & git -C $d config user.email 'tests@milestone-driver.invalid' 2>$null | Out-Null
  & git -C $d config user.name 'classify-review-depth tests' 2>$null | Out-Null
}
function Commit-All([string]$d, [string]$msg) {
  & git -C $d add -A 2>$null | Out-Null
  & git -C $d commit -q -m $msg 2>$null | Out-Null
}

# The row's driver config. No glob in the table carries a character JSON
# escapes, so the array is assembled by hand rather than through a serializer.
function Write-Config([string]$repo, [string]$cell) {
  if ($cell -ceq '-') { return }
  $target = Join-Path $repo '.milestone-config/driver.json'
  if ($cell -ceq '@EMPTY@') { Write-Fixture $target "{}`n"; return }
  # A JSON scalar where the schema says array. Spelled as a sentinel because the
  # cell's `|` split can only ever build an array.
  if ($cell -ceq '@SCALAR@') { Write-Fixture $target "{`"sourceGlobs`":`"scripts/**`"}`n"; return }
  # The legacy root layout, with NO .milestone-config/driver.json beside it, so
  # the row exercises the fallback and not the canonical read.
  if ($cell -ceq '@LEGACY@') {
    Write-Fixture (Join-Path $repo 'milestone-driver.json') "{`"sourceGlobs`":[`"scripts/**`"]}`n"
    return
  }
  $quoted = @()
  foreach ($g in ($cell -split '\|')) { $quoted += ('"' + $g + '"') }
  Write-Fixture $target ('{"sourceGlobs":[' + ($quoted -join ',') + "]}`n")
}

# The row's `R:<subdir>` argument, or ''. Read BEFORE the repo is populated,
# because the run root is where driver.json has to land.
function Get-RootSub([string]$cell) {
  if ($cell -ceq '-') { return '' }
  foreach ($op in ($cell -split '\|')) {
    if ($op.StartsWith('R:', [StringComparison]::Ordinal)) { return $op.Substring(2) }
  }
  return ''
}

# The row's working-tree operations, applied after the base commit. Paths are
# relative to the REPO root, never to the run root, so a row reads the same
# whether or not it carries an `R:` op.
function Invoke-Ops([string]$repo, [string]$cell) {
  if ($cell -ceq '-') { return }
  foreach ($op in ($cell -split '\|')) {
    $i = $op.IndexOf(':', [StringComparison]::Ordinal)
    $kind = $op.Substring(0, $i)
    $p = $op.Substring($i + 1)
    $full = Join-Path $repo $p
    switch -CaseSensitive ($kind) {
      'M' { Write-Fixture $full "changed`n" }
      'N' { Write-Fixture $full "changed`n" }
      'E' { Write-Fixture $full "changed`n"; & git -C $repo add $p 2>$null | Out-Null }
      'S' { Write-Fixture $full "changed`n"; & git -C $repo add $p 2>$null | Out-Null }
      'D' { Remove-Item -LiteralPath $full -Force }
      'R' { }
      default { Write-Error "FATAL: unknown op [$op]"; exit 1 }
    }
  }
}

# $PwshBin is the resolved absolute path, so a stripped PATH override still
# launches the child (`tests/code-review-gate.test.sh (restricted PATH)`).
$PwshBin = (Get-Command pwsh).Source
# $pathOverride is deliberately UNTYPED: a [string] parameter coerces a $null
# default to '', which reads as "override PATH with nothing" on every
# ordinary call.
function Invoke-Case([string]$name, [string]$repo, [string]$wantOut, [string]$wantErr, $pathOverride = $null) {
  $savedPath = $env:PATH
  if ($null -ne $pathOverride) { $env:PATH = $pathOverride }
  try {
    $out = (& $PwshBin -NoProfile -File $script $repo 2> $errFile)
    $rc = $LASTEXITCODE
  } finally {
    $env:PATH = $savedPath
  }
  # Match the bash runner's $(...) capture, which strips only a trailing
  # newline - NOT a broad .Trim(), which would mask a whitespace divergence.
  $out = ("$out") -replace '\r?\n$', ''
  $err = (Get-Content $errFile -Raw)
  $err = if ($null -eq $err) { '' } else { $err -replace '\r?\n$', '' }
  if ($rc -eq 0 -and $out -ceq $wantOut -and $err -ceq $wantErr) {
    $script:pass++
  } else {
    $script:fail++
    Write-Host ("FAIL {0,-38} rc={1} got[out={2} err={3}] want[out={4} err={5}]" -f $name, $rc, $out, $err, $wantOut, $wantErr)
  }
}

$expectCols = 6
$caseCount = 0
foreach ($row in (Get-Content $cases)) {
  if ($row -match '^\s*#' -or $row.Trim() -eq '') { continue }
  $r = $row -replace "`r$", ''
  $cols = $r -split "`t"
  # A row that does not parse into exactly $expectCols fields is a corrupt
  # fixture, not a silently-defaulted pass.
  if ($cols.Count -ne $expectCols) {
    Write-Error "FATAL: row failed to parse (got $($cols.Count) fields, want $expectCols): [$r]"
    exit 1
  }
  $caseCount++
  $name = $cols[0]; $globs = $cols[1]; $base = $cols[2]
  $ops = $cols[3]; $wantOut = $cols[4]; $wantErr = $cols[5]

  $repo = Join-Path $tmp "r$caseCount"
  New-Repo $repo
  $sub = Get-RootSub $ops
  $runRoot = $repo
  if ($sub -cne '') {
    $runRoot = Join-Path $repo $sub
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
  }
  Write-Config $runRoot $globs
  # A committed seed, so HEAD exists even for a row naming no base file.
  Write-Fixture (Join-Path $repo 'README.md') "seed`n"
  if ($base -cne '-') {
    foreach ($bp in ($base -split '\|')) { Write-Fixture (Join-Path $repo $bp) "seed`n" }
  }
  Commit-All $repo 'base'
  Invoke-Ops $repo $ops

  Invoke-Case $name $runRoot $wantOut $wantErr
}

if ($caseCount -eq 0) {
  Write-Error "FATAL: parsed 0 cases from $cases - this run tested nothing"
  exit 1
}

# ---- bespoke: a root that is not a git repo at all. Fail open to standard,
# never a crash.
$b1 = Join-Path $tmp 'b-notrepo'; New-Item -ItemType Directory -Path $b1 -Force | Out-Null
Invoke-Case 'not_a_git_repo' $b1 'standard' 'no-diff'

# ---- bespoke: an initialized repo with no commit. `git diff HEAD` has no HEAD
# to name and fails, so the candidate set is unreadable even though the tree
# holds files.
$b2 = Join-Path $tmp 'b-nohead'; New-Repo $b2
Write-Fixture (Join-Path $b2 '.milestone-config/driver.json') "{`"sourceGlobs`":[`"scripts/**`"]}`n"
Write-Fixture (Join-Path $b2 'scripts/a.sh') "seed`n"
Invoke-Case 'repo_without_commits' $b2 'standard' 'no-diff'

# ---- bespoke: git absent from PATH. There is no jq sibling to this case: this
# leg reads sourceGlobs with ConvertFrom-Json, so it has no jq to lose and never
# emits `no-jq`. That is the one token the two legs do not share.
$b3 = Join-Path $tmp 'b-nogit'; New-Repo $b3
Write-Fixture (Join-Path $b3 'scripts/a.sh') "seed`n"
Commit-All $b3 'base'
Write-Fixture (Join-Path $b3 'scripts/a.sh') "changed`n"
Invoke-Case 'git_absent_from_path' $b3 'standard' 'no-git' ''

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "classify-review-depth.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + 3 bespoke)"
if ($fail -ne 0) { exit 1 }
