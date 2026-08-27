#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for classify-review-depth.ps1 (issue #598).
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

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Get-SeedBlock { return (((1..24) | ForEach-Object { "seed $_" }) -join "`n") + "`n" }
function Get-ChangedBlock { return (((1..24) | ForEach-Object { "changed $_" }) -join "`n") + "`n" }
function Get-MixedBlock([int]$k) {
  return (((1..24) | ForEach-Object { if ($_ -le $k) { "changed $_" } else { "seed $_" } }) -join "`n") + "`n"
}

function Write-Fixture([string]$path, [string]$content) {
  $dir = Split-Path -Parent $path
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

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

function Write-Config([string]$repo, [string]$cell) {
  if ($cell -ceq '-') { return }
  $target = Join-Path $repo '.milestone-config/driver.json'
  if ($cell -ceq '@EMPTY@') { Write-Fixture $target "{}`n"; return }
  if ($cell -ceq '@SCALAR@') { Write-Fixture $target "{`"sourceGlobs`":`"scripts/**`"}`n"; return }
  if ($cell -ceq '@LEGACY@') {
    Write-Fixture (Join-Path $repo 'milestone-driver.json') "{`"sourceGlobs`":[`"scripts/**`"]}`n"
    return
  }
  $quoted = @()
  foreach ($g in ($cell -split '\|')) { $quoted += ('"' + $g + '"') }
  Write-Fixture $target ('{"sourceGlobs":[' + ($quoted -join ',') + "]}`n")
}

function Get-RootSub([string]$cell) {
  if ($cell -ceq '-') { return '' }
  foreach ($op in ($cell -split '\|')) {
    if ($op.StartsWith('R:', [StringComparison]::Ordinal)) { return $op.Substring(2) }
  }
  return ''
}

function Invoke-Ops([string]$repo, [string]$cell) {
  if ($cell -ceq '-') { return }
  foreach ($op in ($cell -split '\|')) {
    $i = $op.IndexOf(':', [StringComparison]::Ordinal)
    $kind = $op.Substring(0, $i)
    $p = $op.Substring($i + 1)
    $full = Join-Path $repo $p
    switch -CaseSensitive ($kind) {
      'M' { Write-Fixture $full (Get-ChangedBlock) }
      'N' { Write-Fixture $full (Get-ChangedBlock) }
      'E' { Write-Fixture $full (Get-ChangedBlock); & git -C $repo add $p 2>$null | Out-Null }
      'S' { Write-Fixture $full (Get-ChangedBlock); & git -C $repo add $p 2>$null | Out-Null }
      'D' { Remove-Item -LiteralPath $full -Force }
      'R' { }
      default {
        if ($kind -cmatch '^m(\d+)$') { Write-Fixture $full (Get-MixedBlock ([int]$Matches[1])) }
        else { Write-Error "FATAL: unknown op [$op]"; exit 1 }
      }
    }
  }
}

$PwshBin = (Get-Command pwsh).Source
function Invoke-Case([string]$name, [string]$repo, [string]$wantOut, [string]$wantErr, $pathOverride = $null) {
  $savedPath = $env:PATH
  if ($null -ne $pathOverride) { $env:PATH = $pathOverride }
  try {
    $out = (& $PwshBin -NoProfile -File $script $repo 2> $errFile)
    $rc = $LASTEXITCODE
  } finally {
    $env:PATH = $savedPath
  }
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
  Write-Fixture (Join-Path $repo 'README.md') "seed`n"
  if ($base -cne '-') {
    foreach ($bp in ($base -split '\|')) { Write-Fixture (Join-Path $repo $bp) (Get-SeedBlock) }
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
$b1 = Join-Path $tmp 'b-notrepo'; New-Item -ItemType Directory -Path $b1 -Force | Out-Null
Invoke-Case 'not_a_git_repo' $b1 'standard' 'no-diff'

# ---- bespoke: an initialized repo with no commit. `git diff HEAD` has no HEAD
$b2 = Join-Path $tmp 'b-nohead'; New-Repo $b2
Write-Fixture (Join-Path $b2 '.milestone-config/driver.json') "{`"sourceGlobs`":[`"scripts/**`"]}`n"
Write-Fixture (Join-Path $b2 'scripts/a.sh') "seed`n"
Invoke-Case 'repo_without_commits' $b2 'standard' 'no-diff'

# ---- bespoke: git absent from PATH. There is no jq sibling to this case: this
$b3 = Join-Path $tmp 'b-nogit'; New-Repo $b3
Write-Fixture (Join-Path $b3 'scripts/a.sh') "seed`n"
Commit-All $b3 'base'
Write-Fixture (Join-Path $b3 'scripts/a.sh') "changed`n"
Invoke-Case 'git_absent_from_path' $b3 'standard' 'no-git' ''

# ---- bespoke: a binary change, `-` in numstat, is never small.
$b5 = Join-Path $tmp 'b-binary'; New-Repo $b5
Write-Fixture (Join-Path $b5 '.milestone-config/driver.json') "{`"sourceGlobs`":[`"scripts/**`"]}`n"
New-Item -ItemType Directory -Path (Join-Path $b5 'scripts') -Force | Out-Null
[System.IO.File]::WriteAllBytes((Join-Path $b5 'scripts/blob.bin'), [byte[]](0x73, 0x65, 0x65, 0x64, 0x00, 0x01))
Commit-All $b5 'base'
[System.IO.File]::WriteAllBytes((Join-Path $b5 'scripts/blob.bin'), [byte[]](0x63, 0x68, 0x61, 0x6E, 0x67, 0x65, 0x64, 0x00, 0x01))
Invoke-Case 'binary_diff_is_not_small' $b5 'standard' ''

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "classify-review-depth.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + 4 bespoke)"
if ($fail -ne 0) { exit 1 }
