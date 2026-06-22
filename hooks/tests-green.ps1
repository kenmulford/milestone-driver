#!/usr/bin/env pwsh
# milestone-driver — tests-green gate (Claude PreToolUse: Bash, if: Bash(git commit *)).
if ($env:CLAUDE_HOOK_DISABLE_TESTS_GREEN -eq '1') { exit 0 }
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
# Self-scope to commits (parity with no-push; defends the "if predicate runs
# always when the command is too complex to parse" fallthrough).
$cmd = $hook.tool_input.command
if ($cmd -and ($cmd -notmatch 'git\s+commit')) { exit 0 }
$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'
$profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$unitCmd = $cfg.unitTestCmd
if (-not $unitCmd) { exit 0 }
$globs = $cfg.sourceGlobs
$staged = @(git -C $projectDir diff --cached --name-only)
$touched = $false
if (-not $globs) { $touched = $true } else {
    foreach ($f in $staged) {
        $rel = ([string]$f) -replace '\\', '/'
        foreach ($g in $globs) { $pat = ([string]$g) -replace '\*\*', '*'; if ($rel -like $pat) { $touched = $true; break } }
        if ($touched) { break }
    }
}
if (-not $touched) { exit 0 }
# --- stamp-skip: skip re-running the suite when staged tree is identical to last green run ---
# New canonical path under .milestone-config/; old root path read transitionally as a
# fallback (mirrors the profile two-step read above). Write always goes to the new path.
$stampPath = Join-Path $projectDir '.milestone-config' 'tests-stamp'
$oldStampPath = Join-Path $projectDir '.milestone-driver-tests-stamp'
$branch = git -C $projectDir rev-parse --abbrev-ref HEAD 2>$null
$treeSHA = git -C $projectDir write-tree 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($treeSHA)) {
    $branch = ([string]$branch).Trim(); $treeSHA = ([string]$treeSHA).Trim()
    $key = "${branch}:${treeSHA}"
    # Read the new path; if absent, fall back to the old root path. Skip on either match.
    $readStamp = $null
    if (Test-Path $stampPath) {
        $readStamp = ([string](Get-Content $stampPath -Raw -ErrorAction SilentlyContinue)) -replace '[\r\n]', ''
    } elseif (Test-Path $oldStampPath) {
        $readStamp = ([string](Get-Content $oldStampPath -Raw -ErrorAction SilentlyContinue)) -replace '[\r\n]', ''
    }
    if ($readStamp -eq $key) {
        [Console]::Error.WriteLine("milestone-driver: staged tree unchanged since last green run — skipping unit suite.")
        exit 0
    }
} else {
    $key = $null  # write-tree failed — fall through, no stamp read/write
}
# --- end stamp-skip ---
[Console]::Error.WriteLine("milestone-driver: staged source changed — running unit suite ($unitCmd) ...")
# Reset first so a pure-PowerShell unitTestCmd (no native exe) can't inherit a
# stale exit code; capture output and SNAPSHOT the exit code immediately (a
# trailing pipeline/try-finally would obscure $LASTEXITCODE); then surface the
# suite's output on stderr so Claude sees failures (parity with .sh's `>&2`).
$LASTEXITCODE = 0
Push-Location $projectDir
try {
    $testOutput = Invoke-Expression $unitCmd 2>&1
    $testCode = $LASTEXITCODE
    $testOutput | ForEach-Object { [Console]::Error.WriteLine($_) }
} finally { Pop-Location }
if ($testCode -ne 0) {
    # Clear stale green stamps (both new and legacy root) so a red run never grants a future skip.
    if (Test-Path $stampPath) { Remove-Item $stampPath -ErrorAction SilentlyContinue }
    if (Test-Path $oldStampPath) { Remove-Item $oldStampPath -ErrorAction SilentlyContinue }
    [Console]::Error.WriteLine("milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override.")
    exit 2
}
# Write stamp on green to the new path (best-effort — failure does not fail the hook).
# Ensure .milestone-config/ exists first; remove the stale legacy root stamp once the
# new one is written, so it stops shadowing future reads.
if ($null -ne $key) {
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $projectDir '.milestone-config') -ErrorAction SilentlyContinue | Out-Null
        # Self-heal the scratch-ignore: ensure a committed .milestone-config/.gitignore so
        # per-clone scratch (this stamp, preflight/trello notices, triage cache, worktrees)
        # is git-invisible in the consumer repo from the first write, while tracked config
        # (driver.json, feeder.json — intentionally NOT listed) stays tracked. Best-effort;
        # only created when absent, so a user-edited file is never clobbered.
        $ignorePath = Join-Path $projectDir '.milestone-config' '.gitignore'
        if (-not (Test-Path $ignorePath)) {
            $ignoreBody = @(
                '# milestone-driver / milestone-feeder per-clone scratch — git-invisible by default.'
                '# Committed so per-run scratch stays out of `git status` with zero user setup.'
                '# Patterns are relative to this .milestone-config/ directory. Tracked config'
                '# (driver.json, feeder.json) is intentionally NOT listed, so it stays tracked.'
                'preflight-notice'; 'trello-notice'; 'triage-cache.json'; 'tests-stamp'
                '.runtime/'; 'worktrees/'
            ) -join "`n"
            [System.IO.File]::WriteAllText($ignorePath, $ignoreBody + "`n", [System.Text.UTF8Encoding]::new($false))
        }
        [System.IO.File]::WriteAllText($stampPath, $key, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path $oldStampPath) { Remove-Item $oldStampPath -ErrorAction SilentlyContinue }
    } catch {}
}
exit 0
