#!/usr/bin/env pwsh
# milestone-driver - no-PR-to-protected gate (Claude PreToolUse: Bash, if: Bash(gh pr create *);
# and the GitHub MCP matcher mcp__.*github.*__(merge_pull_request|create_pull_request|
# update_pull_request|push_files|create_or_update_file|delete_file)), twin of the sh leg.
#
# Bash: blocks `gh pr create --base <protected>`, a first, coarse text check (and the
# only one under Codex). The exact checks run at execution time on real arguments:
# shims/gh for every gh route, git-hooks/pre-push for every push.
# MCP: structured tool_input, so exact. A PR base is allowlisted to integrationBranch
# (a merge reads the PR's base through `gh pr view`; one that cannot be resolved
# denies); a push or file write denies a protected branch, the inline twin of
# shims/_protected.sh.
#
# Deny: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON). Escape: CLAUDE_HOOK_DISABLE_NO_PUSH=1 (shared with the
# no-push gate). Bash path: fail-open on parse/missing-profile.

if ($env:CLAUDE_HOOK_DISABLE_NO_PUSH -eq '1') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
. (Join-Path $PSScriptRoot 'hook-deny.ps1')

# GitHub MCP tools (matcher mcp__.*github.*__...): structured tool_input, so exact. PRs are
# allowlisted to integrationBranch; the push and file tools deny a protected branch (default
# names, protectedBranch, protectedBranches). No profile: integrationBranch resolves to develop,
# or dev when origin/develop is absent.
$tool = [string]$hook.tool_name
if ($tool -cmatch '^mcp__.*github.*__(merge_pull_request|create_pull_request|update_pull_request|push_files|create_or_update_file|delete_file)$') {
    $mcp = $matches[1]
    $projectDir = $hook.cwd
    if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
    if (-not $projectDir) { $projectDir = (Get-Location).Path }
    $projectDir = ([string]$projectDir) -replace '\\', '/'
    $profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
    if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
    $protected = $null; $integ = $null; $extra = @()
    if (Test-Path $profilePath) {
        try {
            $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $protected = $cfg.protectedBranch; $integ = $cfg.integrationBranch
            if ($cfg.protectedBranches -is [System.Collections.IEnumerable] -and $cfg.protectedBranches -isnot [string]) { $extra = @($cfg.protectedBranches | ForEach-Object { [string]$_ }) }
        } catch { }
    }
    if (-not $integ) {
        $integ = 'develop'
        git -C $projectDir rev-parse --verify --quiet refs/remotes/origin/develop *> $null
        if ($LASTEXITCODE -ne 0) { $integ = 'dev' }
    }
    $unres = 'unknown base'; $unresB = 'unknown branch'

    function Block([string]$action, [string]$branch) {
        Invoke-HookDeny $hook ("milestone-driver: $action into '$branch' is blocked. Agents stop at the integration branch '$integ'; anything past it is a human step.")
    }

    # Confirm-Base <action> <base>: the allowlist; a null or empty base is unresolved.
    function Confirm-Base([string]$action, [string]$b) {
        if ($b -cne $integ) { Block $action $(if ($b) { $b } else { $unres }) }
    }

    # Test-Protected <branch>: the push denylist; the integration branch never is.
    # -like's `*` crosses `/`, as a `case` glob's does.
    function Test-Protected([string]$name) {
        $n = $name -replace '^refs/heads/', ''
        if ($n -ceq $integ) { return $false }
        if ($protected -and $n -ceq $protected) { return $true }
        foreach ($p in @('main', 'master', 'production', 'prod', 'staging', 'stage', 'testing', 'test', 'qa', 'uat', 'release/*', 'hotfix/*') + $extra) {
            if ($n -clike $p) { return $true }
        }
        return $false
    }

    # Get-GhLine <args>: gh's single output line, $null when gh fails or prints nothing.
    function Get-GhLine([string[]]$a) {
        try {
            $global:LASTEXITCODE = 0
            $out = ((& gh @a 2>$null) -join "`n").Trim()
            if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
            return $out
        } catch { return $null }
    }

    # Get-ApiDefault <owner/repo>: the default branch a write naming no branch lands on.
    function Get-ApiDefault([string]$repo) { return Get-GhLine @('api', "repos/$repo", '--jq', '.default_branch') }

    # Get-PrBase <pr-or-empty> <owner/repo-or-empty>: the PR's base branch, $null
    # when gh or the lookup fails.
    function Get-PrBase([string]$pr, [string]$repo) {
        $a = @('pr', 'view')
        if ($pr) { $a += $pr }
        if ($repo) { $a += '-R', $repo }
        $a += '--json', 'baseRefName'
        try {
            $global:LASTEXITCODE = 0
            $out = (& gh @a 2>$null) -join "`n"
            if ($LASTEXITCODE -ne 0) { return $null }
            $b = [string]($out | ConvertFrom-Json -ErrorAction Stop).baseRefName
        } catch { return $null }
        if ([string]::IsNullOrWhiteSpace($b)) { return $null }
        return $b.Trim()
    }

    $ti = $hook.tool_input
    $base = [string]$ti.base; $branch = [string]$ti.branch
    switch ($mcp) {
        'merge_pull_request' {
            $b = Get-PrBase ([string]$ti.pullNumber) ("$($ti.owner)/$($ti.repo)")
            if ($null -eq $b) { Block 'merging a PR' $unres }
            Confirm-Base 'merging a PR' $b
        }
        'create_pull_request' { Confirm-Base 'opening a PR' $base }
        'update_pull_request' { if ($base) { Confirm-Base 'retargeting a PR' $base } }
        default {
            if (-not $branch) {
                $branch = Get-ApiDefault ("$($ti.owner)/$($ti.repo)")
                if ($null -eq $branch) { Block 'pushing' $unresB }
            }
            if (Test-Protected $branch) { Block 'pushing' $branch }
        }
    }
    exit 0
}

$cmd = $hook.tool_input.command
if (-not $cmd) { exit 0 }
if ($cmd -notmatch 'gh\s+pr\s+create') { exit 0 }

$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'
$profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
if (-not (Test-Path $profilePath)) { exit 0 }
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$protected = $cfg.protectedBranch
$integ = [string]$cfg.integrationBranch
if (-not $protected) { exit 0 }

# Extract the --base / -B value and compare exactly.
if ($cmd -match '(?:--base[=\s]+|-B\s+)["'']?([^\s"'']+)') {
    if ($matches[1] -eq $protected) {
        if (-not $integ) {
            $integ = 'develop'
            git -C $projectDir rev-parse --verify --quiet refs/remotes/origin/develop *> $null
            if ($LASTEXITCODE -ne 0) { $integ = 'dev' }
        }
        Invoke-HookDeny $hook ("milestone-driver: opening a PR into '$protected' is blocked. Agents stop at the integration branch '$integ'; anything past it is a human step.")
    }
}
exit 0
