#!/usr/bin/env pwsh
# milestone-driver - runner for the tests-green.ps1 hook (issue #499).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here '_lib.ps1'); Set-Leg $Leg
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Hook = Join-Path $Root 'hooks' 'tests-green'
$RepoGitignore = Join-Path $Root '.milestone-config' '.gitignore'
if (-not (Test-Path -LiteralPath $RepoGitignore)) { Write-Error "FATAL: missing $RepoGitignore"; exit 3 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Ok { $script:pass++ }
function No([string]$msg) { $script:fail++; Write-Host "FAIL $msg" }

function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

function New-Workspace([string]$globsJson = '["src/**"]', [string]$stagedPath = 'src/a.txt', [string]$granularity = $null, [string]$branchName = $null, [string]$extraBranch = $null) {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $w | Out-Null
  git -C $w init -q
  git -C $w config user.email tests-green@example.invalid
  git -C $w config user.name tests-green
  if ($branchName) {
    # An unborn HEAD (no commit yet) makes `rev-parse --abbrev-ref HEAD` print
    # the literal string "HEAD", not the checked-out branch name - so a branch
    # a test wants to assert against needs one real commit underneath it.
    [System.IO.File]::WriteAllText((Join-Path $w '.gitkeep'), '', $utf8)
    git -C $w add .gitkeep
    git -C $w commit -q -m init
    git -C $w checkout -q -b $branchName
  }
  if ($extraBranch) {
    # A second local ref, never checked out - proves the milestone-* probe
    # scans refs/heads, not just the current branch.
    git -C $w branch $extraBranch
  }
  New-Item -ItemType Directory -Path (Join-Path $w '.milestone-config') | Out-Null
  $staged = Join-Path $w $stagedPath
  New-Item -ItemType Directory -Path (Split-Path -Parent $staged) -Force | Out-Null
  $driverJson = '{"unitTestCmd":"git --version","sourceGlobs":' + $globsJson
  if ($granularity) { $driverJson += ',"integrationGranularity":"' + $granularity + '"' }
  $driverJson += '}'
  [System.IO.File]::WriteAllText((Join-Path $w '.milestone-config' 'driver.json'), $driverJson + "`n", $utf8)
  [System.IO.File]::WriteAllText($staged, "x`n", $utf8)
  git -C $w add $stagedPath
  return $w
}

function Invoke-Hook([string]$root, [string]$command = 'git commit -m x') {
  $payload = @{ tool_input = @{ command = $command }; cwd = $root } | ConvertTo-Json -Compress
  return Invoke-Leg -Script $Hook -Stdin $payload -Cwd $Tmp
}

# ---- self-healed .gitignore is byte-identical to the committed one ----------
$W = New-Workspace
$r = Invoke-Hook $W
$emitted = Join-Path $W '.milestone-config' '.gitignore'
if ($r.rc -ne 0) { No "gitignore-emitted: hook rc=$($r.rc) err=[$(Show-Escaped $r.err)]" }
elseif (-not (Test-Path -LiteralPath $emitted)) {
  No "gitignore-emitted: hook wrote no $emitted (err=[$(Show-Escaped $r.err)])"
}
else {
  $a = [System.IO.File]::ReadAllBytes($emitted)
  $b = [System.IO.File]::ReadAllBytes($RepoGitignore)
  if ([System.Linq.Enumerable]::SequenceEqual($a, $b)) { Ok }
  else { No "gitignore-emitted: differs from $RepoGitignore ($($a.Length) vs $($b.Length) bytes)" }
}

# ---- an EXISTING .gitignore is never rewritten ------------------------------
$W = New-Workspace
[System.IO.File]::WriteAllBytes((Join-Path $W '.milestone-config' '.gitignore'), $utf8.GetBytes("sentinel`n"))
$r = Invoke-Hook $W
$kept = [System.IO.File]::ReadAllText((Join-Path $W '.milestone-config' '.gitignore'), $utf8)
if ($r.rc -eq 0 -and [string]::Equals($kept, "sentinel`n", [System.StringComparison]::Ordinal)) { Ok }
else { No "gitignore-preserved: rc=$($r.rc) content=[$(Show-Escaped $kept)] err=[$(Show-Escaped $r.err)]" }

# ---- a globstar-prefix glob does not match a root-level staged path --------
$W = New-Workspace '["**/*.md"]' 'x.md'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "globstar-root: rc=$($r.rc) (want 0) and the hook must not reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- milestone granularity skips the suite on an issue/* branch ------------
$W = New-Workspace -granularity 'milestone' -branchName 'issue/9-slug'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "milestone-skip-issue-branch: rc=$($r.rc) (want 0) and the hook must not reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- milestone granularity skips the suite on a milestone-* branch ---------
$W = New-Workspace -granularity 'milestone' -branchName 'milestone-12-slug'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "milestone-skip-milestone-branch: rc=$($r.rc) (want 0) and the hook must not reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- absent integrationGranularity, no local milestone-* branch, runs ------
$W = New-Workspace -branchName 'issue/9-slug'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "absent-granularity-no-milestone-branch-runs: rc=$($r.rc) (want 0) and the hook must reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- absent integrationGranularity, a local milestone-* branch exists, skips
$W = New-Workspace -branchName 'issue/9-slug' -extraBranch 'milestone-12-slug'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "absent-granularity-milestone-branch-exists-skips: rc=$($r.rc) (want 0) and the hook must not reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- an out-of-enum integrationGranularity degrades to "milestone" and skips
$W = New-Workspace -granularity 'bogus' -branchName 'milestone-12-slug'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "milestone-skip-out-of-enum-granularity: rc=$($r.rc) (want 0) and the hook must not reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- "issue" granularity runs the suite even on an issue/* branch ----------
$W = New-Workspace -granularity 'issue' -branchName 'issue/9-slug'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "issue-granularity-runs: rc=$($r.rc) (want 0) and the hook must reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- "wave" granularity runs the suite even on a milestone-* branch --------
$W = New-Workspace -granularity 'wave' -branchName 'milestone-12-slug'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "wave-granularity-runs: rc=$($r.rc) (want 0) and the hook must reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- milestone granularity runs the suite on a non-matching branch ---------
$W = New-Workspace -granularity 'milestone' -branchName 'develop'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "milestone-granularity-other-branch-runs: rc=$($r.rc) (want 0) and the hook must reach its post-green write, err=[$(Show-Escaped $r.err)]" }

# ---- global options before `commit` do not skip the gate (issue #813) -------
foreach ($cmd in @('git -C __W__ commit -m x', 'git -c user.name=x commit -m x', 'git --no-pager -C __W__ commit -m x')) {
  $W = New-Workspace -branchName 'develop'
  $r = Invoke-Hook $W $cmd.Replace('__W__', $W)
  if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
  else { No "global-option-commit-gated [$cmd]: rc=$($r.rc) (want 0) and the hook must reach its post-green write, err=[$(Show-Escaped $r.err)]" }
}
# ---- `git -C <dir> commit` reads the staged tree and runs the suite in <dir> -
# The cwd repo stages nothing; <dir> stages src/a.txt, so `git diff --cached
# --quiet` (the suite) is red only when it runs in <dir>. Out of process: in
# process, the hook's script-scope $LASTEXITCODE reset shadows the native code.
$Cwd = New-Workspace -branchName 'develop'
git -C $Cwd rm -q --cached src/a.txt
[System.IO.File]::WriteAllText((Join-Path $Cwd '.milestone-config' 'driver.json'), '{"unitTestCmd":"git diff --cached --quiet","sourceGlobs":["src/**"]}' + "`n", $utf8)
$Other = New-Workspace -branchName 'develop'
$payload = @{ tool_input = @{ command = "git -C $Other commit -m x" }; cwd = $Cwd } | ConvertTo-Json -Compress
$r = Invoke-Spawn -Script $Hook -Stdin $payload -Cwd $Tmp
if ($r.rc -eq 2) { Ok }
else { No "C-dir-commit-red-suite-denies: rc=$($r.rc) (want 2), err=[$(Show-Escaped $r.err)]" }

# ---- a green `git -C <dir> commit` writes nothing into a <dir> with no profile
$Cwd = New-Workspace -branchName 'develop'
$Other = New-Workspace -branchName 'develop'
Remove-Item -Recurse -Force (Join-Path $Other '.milestone-config')
$r = Invoke-Hook $Cwd "git -C $Other commit -m x"
if ($r.rc -eq 0 -and $r.err -like '*running unit suite*' -and -not (Test-Path -LiteralPath (Join-Path $Other '.milestone-config'))) { Ok }
else { No "C-dir-no-profile-no-writes: rc=$($r.rc) (want 0), the suite must run and $Other/.milestone-config must stay absent, err=[$(Show-Escaped $r.err)]" }

$W = New-Workspace -branchName 'develop'
$r = Invoke-Hook $W 'git -C x status'
if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "global-option-non-commit-passes: rc=$($r.rc) (want 0) and the hook must not reach its post-green write, err=[$(Show-Escaped $r.err)]" }

if (-not $IsWindows) { chmod -R u+w $Tmp 2>$null }
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
Write-Host "tests-green ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
