#!/usr/bin/env pwsh
# milestone-driver — tests-green gate (native git pre-commit)
#
# When staged changes touch the profile's sourceGlobs, runs unitTestCmd and
# blocks the commit if it fails. Harness-independent: guards human commits too.
#
# Install: wire this into <repo>/.git/hooks/pre-commit (see the plugin's
# consumer-setup docs). Escape: CLAUDE_HOOK_DISABLE_TESTS_GREEN=1
# Fail-open on missing profile so a non-milestone-driver repo is unaffected.

if ($env:CLAUDE_HOOK_DISABLE_TESTS_GREEN -eq '1') { exit 0 }

$repo = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $repo) { exit 0 }
$repo = "$repo".Trim()

$profilePath = Join-Path $repo '.claude/milestone-driver.json'
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$unitCmd = $cfg.unitTestCmd
if (-not $unitCmd) { exit 0 }
$globs = $cfg.sourceGlobs

# Run tests only when staged files touch source/test globs (skip doc/config-only
# commits). With no globs declared, run unconditionally (safe default).
$staged = @(git diff --cached --name-only)
$touched = $false
if (-not $globs) {
    $touched = $true
} else {
    foreach ($f in $staged) {
        $rel = ([string]$f) -replace '\\', '/'
        foreach ($g in $globs) {
            $pat = ([string]$g) -replace '\*\*', '*'
            if ($rel -like $pat) { $touched = $true; break }
        }
        if ($touched) { break }
    }
}
if (-not $touched) { exit 0 }

[Console]::Error.WriteLine("milestone-driver: staged source changed — running unit suite ($unitCmd) ...")
Push-Location $repo
try { Invoke-Expression $unitCmd } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override.")
    exit 1
}
exit 0
