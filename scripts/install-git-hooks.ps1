#!/usr/bin/env pwsh
# milestone-driver — install native git hooks into a consuming repo.
#
# Writes <repo>/.git/hooks/pre-commit and pre-push as POSIX-sh shims that invoke
# the plugin's tests-green / no-push scripts (pwsh if available, else bash+jq).
# Git runs hooks via sh on every platform, so the installed shim is sh; it then
# prefers pwsh. The plugin's hooks dir is baked into the shim, so re-run this
# after the plugin moves (e.g. a version-bumped install path).
#
# Usage: pwsh -File scripts/install-git-hooks.ps1 [-RepoPath <path>]

[CmdletBinding()]
param([string]$RepoPath = (Get-Location).Path)

$ErrorActionPreference = 'Stop'

$hooksDir = (Resolve-Path (Join-Path $PSScriptRoot '..' 'hooks')).Path -replace '\\', '/'
$repo = (Resolve-Path $RepoPath).Path
if (-not (Test-Path (Join-Path $repo '.git'))) { Write-Error "Not a git repository: $repo"; exit 1 }
$gitHooks = Join-Path $repo '.git/hooks'
New-Item -ItemType Directory -Force -Path $gitHooks | Out-Null

if (-not (Test-Path (Join-Path $repo '.claude/milestone-driver.json'))) {
    Write-Warning "No .claude/milestone-driver.json in $repo — the hooks no-op until you add the profile."
}

function Install-Shim([string]$Name, [string]$Script) {
    $target = Join-Path $gitHooks $Name
    if (Test-Path $target) {
        $existing = Get-Content $target -Raw -ErrorAction SilentlyContinue
        if ($existing -notmatch 'milestone-driver-managed') {
            $bak = "$target.pre-milestone-driver.bak"
            Move-Item $target $bak -Force
            Write-Warning "Existing $Name backed up to $bak — chain it manually if you still need it."
        }
    }
    $lines = @(
        '#!/bin/sh',
        '# milestone-driver-managed',
        "HOOK_DIR=`"$hooksDir`"",
        'if command -v pwsh >/dev/null 2>&1; then',
        "  exec pwsh -NoProfile -File `"`$HOOK_DIR/$Script.ps1`" `"`$@`"",
        'else',
        "  exec bash `"`$HOOK_DIR/$Script.sh`" `"`$@`"",
        'fi',
        ''
    )
    [System.IO.File]::WriteAllText($target, ($lines -join "`n"))
    if ($IsLinux -or $IsMacOS) { chmod +x $target }
    Write-Host "installed .git/hooks/$Name -> $Script"
}

Install-Shim 'pre-commit' 'tests-green'
Install-Shim 'pre-push'   'no-push'
Write-Host "milestone-driver native hooks installed into $gitHooks (HOOK_DIR=$hooksDir)"
