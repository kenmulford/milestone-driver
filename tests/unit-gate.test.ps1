#!/usr/bin/env pwsh
# milestone-driver - runner for scripts/unit-gate.{sh,ps1} (the lean-loop change, L1).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here '_lib.ps1'); Set-Leg $Leg
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Script = Join-Path $Root 'scripts' 'unit-gate'
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

# unitTestCmd is a plain `git <verb>`: reliably 0 on --version, reliably
# nonzero on an unknown subcommand, on both bash `eval` and pwsh
# Invoke-Expression, with no dependency on PATH tools other than git.
function New-Workspace([string]$unitCmd = 'git --version', [bool]$withProfile = $true) {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $w | Out-Null
  git -C $w init -q
  git -C $w config user.email unit-gate@example.invalid
  git -C $w config user.name unit-gate
  New-Item -ItemType Directory -Path (Join-Path $w '.milestone-config') | Out-Null
  $tracked = Join-Path $w 'src' 'a.txt'
  New-Item -ItemType Directory -Path (Split-Path -Parent $tracked) -Force | Out-Null
  [System.IO.File]::WriteAllText($tracked, "seed`n", $utf8)
  git -C $w add 'src/a.txt' | Out-Null
  git -C $w commit -q -m seed | Out-Null
  if ($withProfile) {
    [System.IO.File]::WriteAllText((Join-Path $w '.milestone-config' 'driver.json'),
      '{"unitTestCmd":"' + $unitCmd + '"}' + "`n", $utf8)
  }
  return $w
}

function Invoke-Gate([string]$root, [switch]$StampOnly) {
  # Invoke-Spawn (a real subprocess for both legs), not Invoke-Leg: the ps1
  # leg's in-process `& $Path` invocation does not propagate a nested
  # script's `exit <n>` into the caller's $LASTEXITCODE the way an actual
  # subprocess does (verified: the identical script correctly reports its
  # exit code as a real `pwsh -File` child process, and incorrectly reports
  # 0 when invoked in-process). Production always runs this as a real
  # subprocess, so Invoke-Spawn is the faithful choice here regardless.
  $a = if ($StampOnly) { @('--stamp-only', $root) } else { @($root) }
  return Invoke-Spawn -Script $Script -Args $a -Cwd $Tmp
}

function Invoke-Hook([string]$root) {
  $payload = @{ tool_input = @{ command = 'git commit -m x' }; cwd = $root } | ConvertTo-Json -Compress
  return Invoke-Leg -Script $Hook -Stdin $payload -Cwd $Tmp
}

function Get-Stamp([string]$root) {
  $p = Join-Path $root '.milestone-config' 'tests-stamp'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return ([string](Get-Content -LiteralPath $p -Raw)) -replace '[\r\n]', ''
}

function Get-TreeKey([string]$root) {
  $branch = (git -C $root rev-parse --abbrev-ref HEAD).Trim()
  $tree = (git -C $root write-tree).Trim()
  return "${branch}:${tree}"
}

# ---- no profile at all: no-op, rc=0, no stamp -------------------------------
$W = New-Workspace -withProfile $false
$r = Invoke-Gate $W
if ($r.rc -eq 0 -and $null -eq (Get-Stamp $W)) { Ok }
else { No "no-profile: rc=$($r.rc) (want 0) stamp=[$(Get-Stamp $W)] err=[$(Show-Escaped $r.err)]" }

# ---- profile present, unitTestCmd absent: no-op, rc=0, no stamp ------------
$W = New-Workspace
[System.IO.File]::WriteAllText((Join-Path $W '.milestone-config' 'driver.json'), "{}`n", $utf8)
$r = Invoke-Gate $W
if ($r.rc -eq 0 -and $null -eq (Get-Stamp $W)) { Ok }
else { No "no-unittestcmd: rc=$($r.rc) (want 0) stamp=[$(Get-Stamp $W)] err=[$(Show-Escaped $r.err)]" }

# ---- green run: stages an untracked file, writes the branch:tree stamp -----
$W = New-Workspace
$untracked = Join-Path $W 'src' 'b.txt'
[System.IO.File]::WriteAllText($untracked, "new`n", $utf8)
$r = Invoke-Gate $W
$wantKey = Get-TreeKey $W
$staged = @(git -C $W diff --cached --name-only)
if ($r.rc -eq 0 -and (Get-Stamp $W) -eq $wantKey -and ($staged -contains 'src/b.txt')) { Ok }
else { No "green-writes-stamp: rc=$($r.rc) stamp=[$(Get-Stamp $W)] want=[$wantKey] staged=[$($staged -join ',')] err=[$(Show-Escaped $r.err)]" }

# ---- red run: clears an existing stamp (new and legacy paths), rc<>0 -------
$W = New-Workspace 'git bogus-nonexistent-subcommand'
[System.IO.File]::WriteAllText((Join-Path $W '.milestone-config' 'tests-stamp'), 'stale:deadbeef', $utf8)
[System.IO.File]::WriteAllText((Join-Path $W '.milestone-driver-tests-stamp'), 'stale:deadbeef', $utf8)
$r = Invoke-Gate $W
if ($r.rc -ne 0 -and $null -eq (Get-Stamp $W) -and -not (Test-Path -LiteralPath (Join-Path $W '.milestone-driver-tests-stamp'))) { Ok }
else { No "red-clears-stamp: rc=$($r.rc) (want nonzero) stamp=[$(Get-Stamp $W)] legacy-exists=$(Test-Path -LiteralPath (Join-Path $W '.milestone-driver-tests-stamp')) err=[$(Show-Escaped $r.err)]" }

# ---- --stamp-only: stages and stamps, never runs unitTestCmd --------------
$W = New-Workspace 'git bogus-nonexistent-subcommand'
$untracked = Join-Path $W 'src' 'c.txt'
[System.IO.File]::WriteAllText($untracked, "new`n", $utf8)
$r = Invoke-Gate $W -StampOnly
$wantKey = Get-TreeKey $W
$staged = @(git -C $W diff --cached --name-only)
if ($r.rc -eq 0 -and (Get-Stamp $W) -eq $wantKey -and ($staged -contains 'src/c.txt')) { Ok }
else { No "stamp-only-writes-stamp: rc=$($r.rc) (want 0, and unitTestCmd never ran) stamp=[$(Get-Stamp $W)] want=[$wantKey] err=[$(Show-Escaped $r.err)]" }

# ---- --stamp-only, unitTestCmd absent: no-op, no stamp ---------------------
$W = New-Workspace
[System.IO.File]::WriteAllText((Join-Path $W '.milestone-config' 'driver.json'), "{}`n", $utf8)
$r = Invoke-Gate $W -StampOnly
if ($r.rc -eq 0 -and $null -eq (Get-Stamp $W)) { Ok }
else { No "stamp-only-no-unittestcmd: rc=$($r.rc) (want 0) stamp=[$(Get-Stamp $W)] err=[$(Show-Escaped $r.err)]" }

# ---- green run self-heals .gitignore, byte-identical to the repo's own -----
$W = New-Workspace
$r = Invoke-Gate $W
$emitted = Join-Path $W '.milestone-config' '.gitignore'
if ($r.rc -eq 0 -and (Test-Path -LiteralPath $emitted)) {
  $a = [System.IO.File]::ReadAllBytes($emitted)
  $b = [System.IO.File]::ReadAllBytes($RepoGitignore)
  if ([System.Linq.Enumerable]::SequenceEqual($a, $b)) { Ok }
  else { No "gitignore-emitted: differs from $RepoGitignore ($($a.Length) vs $($b.Length) bytes)" }
} else { No "gitignore-emitted: rc=$($r.rc) wrote no $emitted (err=[$(Show-Escaped $r.err)])" }

# ---- an EXISTING .gitignore is never rewritten ------------------------------
$W = New-Workspace
[System.IO.File]::WriteAllBytes((Join-Path $W '.milestone-config' '.gitignore'), $utf8.GetBytes("sentinel`n"))
$r = Invoke-Gate $W
$kept = [System.IO.File]::ReadAllText((Join-Path $W '.milestone-config' '.gitignore'), $utf8)
if ($r.rc -eq 0 -and [string]::Equals($kept, "sentinel`n", [System.StringComparison]::Ordinal)) { Ok }
else { No "gitignore-preserved: rc=$($r.rc) content=[$(Show-Escaped $kept)] err=[$(Show-Escaped $r.err)]" }

# ---- integration: a stamp the gate wrote makes the commit-time hook skip ---
$W = New-Workspace
$gr = Invoke-Gate $W
git -C $W add -A | Out-Null
$hr = Invoke-Hook $W
if ($gr.rc -eq 0 -and $hr.rc -eq 0 -and $hr.err -match 'skipping unit suite') { Ok }
else { No "gate-then-hook-skips: gate.rc=$($gr.rc) hook.rc=$($hr.rc) hook.err=[$(Show-Escaped $hr.err)]" }

# ---- integration: a staged tree change after the gate makes the hook run --
[System.IO.File]::AppendAllText((Join-Path $W 'src' 'a.txt'), "more`n", $utf8)
git -C $W add -A | Out-Null
$hr2 = Invoke-Hook $W
if ($hr2.rc -eq 0 -and $hr2.err -match 'running unit suite' -and -not ($hr2.err -match 'skipping unit suite')) { Ok }
else { No "changed-tree-hook-runs: rc=$($hr2.rc) err=[$(Show-Escaped $hr2.err)]" }

if (-not $IsWindows) { chmod -R u+w $Tmp 2>$null }
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
Write-Host "unit-gate ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
