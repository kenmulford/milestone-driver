#!/usr/bin/env pwsh
# milestone-driver - force-subagent gate (Claude PreToolUse: Write|Edit|MultiEdit|NotebookEdit|apply_patch)
#
# Blocks main-thread edits to the consuming repo's source/test globs so that
# application and test code is authored only by the dispatched implementer
# subagent. The orchestrator keeps /docs/, /.claude/, and /Obsidian/ paths (plus any file outside sourceGlobs) editable; files matching sourceGlobs are gated even when markdown.
#
# Deny mechanism: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON).
# Subagent detection: presence of agent_id / agent_type / parent_session_id on
#   the hook input (Claude Code docs + npm-claude-config Test-SubagentContext).
# Profile: <repo>/.milestone-config/driver.json (root milestone-driver.json fallback) -> sourceGlobs.
# Escape hatch: CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT=1
#
# Fail-open: any parse/IO error exits 0 so a hook bug never bricks editing.

if ($env:CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT -eq '1') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
. (Join-Path $PSScriptRoot 'hook-deny.ps1')

# Subagent context -> allow (the implementer is the legitimate author).
foreach ($field in @($hook.agent_id, $hook.agent_type, $hook.parent_session_id)) {
    if ($field -and "$field".Length -gt 0) { exit 0 }
}

. (Join-Path $PSScriptRoot 'patch-input.ps1')
$paths = @()
if ($hook.tool_name -eq 'apply_patch') {
    $paths = @((Read-CodexPatch $hook.tool_input.command).Paths)
} else {
    $filePath = $hook.tool_input.file_path
    if (-not $filePath) { $filePath = $hook.tool_input.notebook_path }
    if ($filePath) { $paths = @($filePath) }
}
if (-not $paths.Count) { exit 0 }

# Resolve project dir + profile.
$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ConvertTo-HookPath ([string]$projectDir) ((Get-Location).Path.Replace('\', '/'))

$profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
if (-not (Test-Path $profilePath)) { exit 0 }   # not a milestone-driver repo -> don't interfere
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$globs = $cfg.sourceGlobs
if (-not $globs) { exit 0 }

# GLOB DIALECT, and where the repo's three sourceGlobs matchers part. This gate
# and `hooks/tests-green.ps1` collapse `**` to `*` and match with `-like`;
# `scripts/classify-review-depth.ps1` translates the same glob to a regex, `**/`
# to `(.*/)?`. All three agree on `dir/**`, the shape every sourceGlobs entry in
# this repo takes. They part on `**/*.ext`: the regex matches a ROOT-level `x.md`
# and tests-green's collapsed `*/*.md` does not. This gate lands on the regex's
# answer anyway, through the SECOND test below - the ABSOLUTE path against
# `*/<pat>`, which supplies the leading segment tests-green has no source for.
# Pinned as behavior, not endorsed as a contract:
# `tests/force-subagent.test.ps1 (a globstar-prefix glob blocks a root-level path)`.
# Aligning the three is its own issue: this gate decides whether a source edit
# is blocked at all.
foreach ($filePath in $paths) {
    $norm = ConvertTo-HookPath ([string]$filePath) $projectDir
    if ($norm -match '/(docs|\.claude|Obsidian)/') { continue }
    $rel = $norm
    if ($norm.StartsWith("$projectDir/")) { $rel = $norm.Substring($projectDir.Length + 1) }
    foreach ($g in $globs) {
        $pattern = ([string]$g) -replace '\\', '/'
        $pattern = $pattern -replace '\*\*', '*'   # ** -> * ; PowerShell -like '*' already crosses '/'
        if (($rel -like $pattern) -or ($norm -like "*/$pattern")) {
            Invoke-HookDeny $hook ("milestone-driver: main-thread edits to source ('$rel') are blocked. Dispatch the implementer subagent to author application/test code, or set CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT=1 to override.")
        }
    }
}

exit 0
