#!/usr/bin/env pwsh
# milestone-driver - .codex-plugin/plugin.json parses, matches the Claude
# manifest, and every path it or hooks/codex-hooks.json references exists.
# Leg-agnostic: both legs run the same checks.
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok) {
  if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name" }
}
function Read-Json([string]$rel) {
  try { return Get-Content -LiteralPath (Join-Path $root $rel) -Raw | ConvertFrom-Json -AsHashtable }
  catch { Check "$rel parses" $false; return $null }
}

$codex = Read-Json '.codex-plugin/plugin.json'
$claude = Read-Json '.claude-plugin/plugin.json'
if ($codex -and $claude) {
  foreach ($k in 'name', 'version', 'description') { Check "$k equals .claude-plugin" ($codex[$k] -eq $claude[$k]) }
  foreach ($k in 'skills', 'hooks') {
    Check "$k path exists" ($codex.ContainsKey($k) -and (Test-Path -LiteralPath (Join-Path $root $codex[$k])))
  }
  foreach ($k in 'displayName', 'shortDescription', 'developerName', 'category') {
    Check "interface.$k set" ($codex.ContainsKey('interface') -and [bool]$codex.interface[$k])
  }
}

$hooks = Read-Json 'hooks/codex-hooks.json'
if ($hooks) {
  $handlers = @(foreach ($event in $hooks.hooks.Values) { foreach ($group in $event) {
    Check "matcher [$($group['matcher'])] fires on Codex" ($group['matcher'] -notmatch '(^|\|)(Agent|Task|Skill)(\||$)')
    $group.hooks
  } })
  foreach ($h in $handlers) {
    Check "no if field [$($h.command)]" (-not $h.ContainsKey('if'))
    foreach ($c in $h.command, $h.commandWindows) {
      foreach ($m in [regex]::Matches([string]$c, '\$\{CLAUDE_PLUGIN_ROOT\}/(?<p>[^"\s]+)')) {
        Check "path exists [$($m.Groups['p'].Value)]" (Test-Path -LiteralPath (Join-Path $root $m.Groups['p'].Value))
      }
    }
    if ($h.command -match 'run-hook\.cmd" (?<g>\S+)') {
      Check "gate pair exists [$($Matches.g)]" ((Test-Path (Join-Path $root "hooks/$($Matches.g).sh")) -and (Test-Path (Join-Path $root "hooks/$($Matches.g).ps1")))
    }
  }
}
# Live codex-cli 0.163.0 reports the spawn tool as collaborationspawn_agent; a bare spawn_agent matcher never fired.
$matchers = @(foreach ($group in $hooks.hooks.PreToolUse) { $group['matcher'] -split '\|' })
Check 'a PreToolUse matcher names collaborationspawn_agent' ($matchers -ccontains 'collaborationspawn_agent')
Check 'hooks/hooks.json stays Claude-only' ((Get-Content -LiteralPath (Join-Path $root 'hooks/hooks.json') -Raw) -notmatch 'apply_patch|spawn_agent')

Write-Host "codex-manifest ($Leg): $pass passed, $fail failed"
if ($fail) { exit 1 }
