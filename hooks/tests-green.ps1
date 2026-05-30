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
$profilePath = Join-Path $projectDir 'milestone-driver.json'
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
    [Console]::Error.WriteLine("milestone-driver: unit tests failed — commit blocked. Fix the suite, or set CLAUDE_HOOK_DISABLE_TESTS_GREEN=1 to override.")
    exit 2
}
exit 0
