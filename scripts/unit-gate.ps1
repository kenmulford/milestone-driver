#!/usr/bin/env pwsh
# milestone-driver - unit gate: stage, run unitTestCmd, stamp on green (the
# lean-loop change, L1). See scripts/unit-gate.sh for the full contract note.
# Usage: unit-gate.ps1 [--stamp-only] <repo-root>
#   --stamp-only  stage and write the stamp without running unitTestCmd,
#                 for a caller that already proved the staged tree green
#                 elsewhere (`scripts/unit-gate.sh` carries the full note).
# Exit:  0 no-op or green (suite-run or --stamp-only), 1 the suite failed,
#        2 bad usage.
$stampOnly = $false
$rootIndex = 0
# Index $args directly by a computed offset rather than slicing a sub-array
# out of it: `$args[1..($args.Count-1)]` assigned through an `if` expression
# unwraps a single-element array result to a bare scalar (a PowerShell
# script-block-output quirk), which then turned `$root = $cliArgs[0]` into
# STRING character-indexing ("C:\..." -> "C") instead of array indexing.
# Direct indexing has no such collapse.
if ($args.Count -gt 0 -and $args[0] -eq '--stamp-only') { $stampOnly = $true; $rootIndex = 1 }
$root = if ($args.Count -gt $rootIndex) { $args[$rootIndex] } else { $null }
if (-not $root) { [Console]::Error.WriteLine('usage: unit-gate.ps1 [--stamp-only] <repo-root>'); exit 2 }
$profilePath = Join-Path $root '.milestone-config' 'driver.json'
if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $root 'milestone-driver.json' }
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$unitCmd = $cfg.unitTestCmd
if (-not $unitCmd) { exit 0 }

$stampPath = Join-Path $root '.milestone-config' 'tests-stamp'
$oldStampPath = Join-Path $root '.milestone-driver-tests-stamp'

# Self-heal the scratch-ignore BEFORE staging: a newly-created .gitignore
# must be part of the tree `git add -A` below stages and this stamp keys on,
# or a caller's own later `git add -A` (right before `git commit`) would pick
# it up as a fresh change and the commit-time hook would see a tree that no
# longer matches this stamp - one spurious re-run on a fresh consumer clone's
# first-ever green run. KEEP THIS BLOCK IN SYNC with hooks/tests-green.ps1's
# own copy, with the committed .milestone-config/.gitignore in this repo, and
# with solve-issue / solve-milestone / scripts/triage-cache.{sh,ps1}, feeder
# setup / plan. tests/tests-green.test.{sh,ps1} and
# tests/unit-gate.test.{sh,ps1} pin the EMITTED bytes against that file, so a
# name added there and not here fails CI. Joined with an explicit LF rather
# than a here-string, so a CRLF checkout of THIS file cannot leak CRLF into
# the emitted .gitignore.
New-Item -ItemType Directory -Force -Path (Join-Path $root '.milestone-config') -ErrorAction SilentlyContinue | Out-Null
$ignorePath = Join-Path $root '.milestone-config' '.gitignore'
if (-not (Test-Path $ignorePath)) {
    $ignoreBody = @(
        '# milestone-driver / milestone-feeder per-clone scratch - git-invisible by default.'
        '# Committed so per-run scratch stays out of `git status` with zero user setup.'
        '# Patterns are relative to this .milestone-config/ directory. Tracked config'
        '# (driver.json, feeder.json) is intentionally NOT listed, so it stays tracked.'
        '*-notice'; 'triage-cache.json'
        'tests-stamp'; '.runtime/'; 'worktrees/'
    ) -join "`n"
    [System.IO.File]::WriteAllText($ignorePath, $ignoreBody + "`n", [System.Text.UTF8Encoding]::new($false))
}

git -C $root add -A 2>$null | Out-Null

$branch = (git -C $root rev-parse --abbrev-ref HEAD 2>$null)
$treeSHA = (git -C $root write-tree 2>$null)
$key = $null
if (-not [string]::IsNullOrWhiteSpace($treeSHA)) {
    $branch = ([string]$branch).Trim(); $treeSHA = ([string]$treeSHA).Trim()
    $key = "${branch}:${treeSHA}"
}

if ($stampOnly) {
    [Console]::Error.WriteLine('milestone-driver: unit gate - staged tree already proven green elsewhere, stamping without a suite run.')
} else {
    [Console]::Error.WriteLine("milestone-driver: unit gate - running unit suite ($unitCmd) ...")
    $LASTEXITCODE = 0
    Push-Location $root
    try {
        $testOutput = Invoke-Expression $unitCmd 2>&1
        $testCode = $LASTEXITCODE
        $testOutput | ForEach-Object { [Console]::Out.WriteLine($_) }
    } finally { Pop-Location }
    if ($testCode -ne 0) {
        if (Test-Path $stampPath) { Remove-Item $stampPath -ErrorAction SilentlyContinue }
        if (Test-Path $oldStampPath) { Remove-Item $oldStampPath -ErrorAction SilentlyContinue }
        [Console]::Error.WriteLine('milestone-driver: unit gate - unit tests failed.')
        exit 1
    }
}

if ($null -ne $key) {
    try {
        [System.IO.File]::WriteAllText($stampPath, $key, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path $oldStampPath) { Remove-Item $oldStampPath -ErrorAction SilentlyContinue }
        [Console]::Error.WriteLine("milestone-driver: unit gate - suite green, stamp written for $key.")
    } catch {}
}
exit 0
