#!/usr/bin/env pwsh
# milestone-driver — force-subagent gate (Claude PreToolUse: Write|Edit|MultiEdit|NotebookEdit)
#
# Blocks main-thread edits to the consuming repo's source/test globs so that
# application and test code is authored only by the dispatched implementer
# subagent. The orchestrator keeps /docs/, /.claude/, and /Obsidian/ paths (plus any file outside sourceGlobs) editable; files matching sourceGlobs are gated even when markdown.
#
# Deny mechanism: exit 2 + stderr (stable across current Claude Code).
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

# Subagent context -> allow (the implementer is the legitimate author).
foreach ($field in @($hook.agent_id, $hook.agent_type, $hook.parent_session_id)) {
    if ($field -and "$field".Length -gt 0) { exit 0 }
}

# Target file (Edit/Write/MultiEdit use file_path; NotebookEdit uses notebook_path).
$filePath = $hook.tool_input.file_path
if (-not $filePath) { $filePath = $hook.tool_input.notebook_path }
if (-not $filePath) { exit 0 }
$norm = ([string]$filePath) -replace '\\', '/'

# Always-exempt: docs, .claude config, Obsidian vaults. Source globs are gated even when markdown.
if ($norm -match '/docs/')    { exit 0 }
if ($norm -match '/\.claude/'){ exit 0 }
if ($norm -match '/Obsidian/'){ exit 0 }

# Resolve project dir + profile.
$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'

$profilePath = Join-Path $projectDir '.milestone-config' 'driver.json'
if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
if (-not (Test-Path $profilePath)) { exit 0 }   # not a milestone-driver repo -> don't interfere
try { $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$globs = $cfg.sourceGlobs
if (-not $globs) { exit 0 }

# Repo-relative path for matching.
$rel = $norm
if ($norm.StartsWith("$projectDir/")) { $rel = $norm.Substring($projectDir.Length + 1) }

foreach ($g in $globs) {
    $pattern = ([string]$g) -replace '\\', '/'
    $pattern = $pattern -replace '\*\*', '*'   # ** -> * ; PowerShell -like '*' already crosses '/'
    if (($rel -like $pattern) -or ($norm -like "*/$pattern")) {
        [Console]::Error.WriteLine("milestone-driver: main-thread edits to source ('$rel') are blocked. Dispatch the implementer subagent to author application/test code, or set CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT=1 to override.")
        exit 2
    }
}

exit 0
