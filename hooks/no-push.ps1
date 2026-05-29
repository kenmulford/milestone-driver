#!/usr/bin/env pwsh
# milestone-driver — no-push-to-protected gate (native git pre-push)
#
# Rejects any push whose remote ref is the profile's protectedBranch. The loop
# integrates to integrationBranch only; release to protectedBranch stays manual.
# GitHub branch protection is the server-side backstop.
#
# Install: wire this into <repo>/.git/hooks/pre-push (see the plugin's
# consumer-setup docs). Escape: CLAUDE_HOOK_DISABLE_NO_PUSH=1
#
# git passes ref updates on stdin: "<local ref> <local sha> <remote ref> <remote sha>"

if ($env:CLAUDE_HOOK_DISABLE_NO_PUSH -eq '1') { exit 0 }

$repo = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $repo) { exit 0 }
$profilePath = Join-Path "$repo".Trim() '.claude/milestone-driver.json'
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$protected = $cfg.protectedBranch
if (-not $protected) { exit 0 }

$blocked = $false
$stdin = [Console]::In.ReadToEnd()
foreach ($line in ($stdin -split "`r?`n")) {
    if (-not $line.Trim()) { continue }
    $parts = $line.Trim() -split '\s+'
    if ($parts.Count -ge 3 -and $parts[2] -eq "refs/heads/$protected") { $blocked = $true }
}

if ($blocked) {
    [Console]::Error.WriteLine("milestone-driver: pushing to protected branch '$protected' is blocked. Push the integration branch and open a PR instead, or set CLAUDE_HOOK_DISABLE_NO_PUSH=1 to override. (GitHub branch protection is the server-side backstop.)")
    exit 1
}
exit 0
