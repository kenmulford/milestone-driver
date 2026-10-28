#!/usr/bin/env pwsh
# milestone-driver - every gate against payloads captured from codex-cli
# 0.163.0 (tests/fixtures/codex/). Codex ignores exit 2, so a Codex payload
# (it carries turn_id) is denied by stdout JSON with exit 0. The same payload
# without turn_id is the Claude path: exit 2, reason on stderr, stdout empty.
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1'); Set-Leg $Leg
$root = Split-Path $PSScriptRoot -Parent
$fixtures = Join-Path $PSScriptRoot 'fixtures' 'codex'
$utf8 = [Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('milestone-driver-codex-fixtures-' + [guid]::NewGuid())
foreach ($v in 'FORCE_SUBAGENT', 'NO_BOM', 'TESTS_GREEN', 'NO_PUSH', 'CODE_REVIEW_GATE', 'DISPATCH_CAP') { [Environment]::SetEnvironmentVariable("CLAUDE_HOOK_DISABLE_$v", $null) }

function New-Workspace {
  $w = Join-Path $tmp ([guid]::NewGuid())
  New-Item -ItemType Directory -Path "$w/.milestone-config" -Force | Out-Null
  git -C $w init -q -b main
  git -C $w config user.email codex-fixtures@example.invalid
  git -C $w config user.name codex-fixtures
  git -C $w config core.hooksPath "$w/.git/no-such-hooks"
  git -C $w commit -q --allow-empty -m base
  git -C $w checkout -q -b issue/7-x
  [IO.File]::WriteAllText("$w/.milestone-config/driver.json", '{"protectedBranch":"main","integrationBranch":"develop","sourceGlobs":["*.txt"]}', $utf8)
  return $w
}
function Fixture([string]$name, [string]$cwd) {
  $p = Get-Content -LiteralPath (Join-Path $fixtures "$name.json") -Raw | ConvertFrom-Json -AsHashtable
  $p.cwd = $cwd
  return $p
}
function Run([string]$gate, [hashtable]$payload) {
  return Invoke-Spawn -Script "$root/hooks/$gate" -Stdin ($payload | ConvertTo-Json -Depth 10 -Compress) -Cwd $tmp
}
function Expect-Deny([string]$name, $r) {
  $ok = $false
  try {
    $o = $r.out | ConvertFrom-Json -ErrorAction Stop
    $h = $o.hookSpecificOutput
    # ASCII-only: a console-less pwsh writes stdout in the OEM code page, where a raw non-ASCII byte breaks the JSON.
    $ok = $r.rc -eq 0 -and $r.out -cmatch '^[\x00-\x7F]*$' -and $h.hookEventName -eq 'PreToolUse' -and $h.permissionDecision -eq 'deny' -and $h.permissionDecisionReason -match '^milestone-driver: '
  } catch { }
  if ($ok) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name (codex deny): rc=$($r.rc) out=[$($r.out)] err=[$($r.err)]" }
}
function Expect-ClaudeDeny([string]$name, $r) {
  if ($r.rc -eq 2 -and $r.err -match 'milestone-driver: ' -and $r.out -eq '') { $script:pass++ }
  else { $script:fail++; Write-Host "FAIL $name (claude deny): rc=$($r.rc) out=[$($r.out)] err=[$($r.err)]" }
}
function Expect-Allow([string]$name, $r) {
  if ($r.rc -eq 0 -and $r.out -eq '') { $script:pass++ }
  else { $script:fail++; Write-Host "FAIL $name (allow): rc=$($r.rc) out=[$($r.out)] err=[$($r.err)]" }
}
function Both([string]$name, [string]$gate, [hashtable]$payload) {
  Expect-Deny $name (Run $gate $payload)
  $claude = $payload.Clone(); $claude.Remove('turn_id')
  Expect-ClaudeDeny $name (Run $gate $claude)
}

New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $w = New-Workspace

  # force-subagent: the main thread has no agent_id; a spawn_agent child does.
  Both 'main apply_patch to source' force-subagent (Fixture pretooluse-main-apply_patch $w)
  Expect-Allow 'child apply_patch to source' (Run force-subagent (Fixture pretooluse-child-apply_patch $w))

  $p = Fixture pretooluse-main-apply_patch $w
  $p.tool_input.command = "*** Begin Patch`n*** Add File: notes.md`n+$([char]0xfeff)bad`n*** End Patch"
  Both 'apply_patch leading BOM' no-bom $p

  # Bash gates: the captured command passes, a matching one is denied.
  foreach ($gate in 'tests-green', 'no-push', 'no-pr-to-protected', 'code-review-gate') {
    Expect-Allow "$gate captured echo" (Run $gate (Fixture pretooluse-main-bash $w))
  }
  $p = Fixture pretooluse-main-bash $w; $p.tool_input.command = 'git push origin main'
  Both 'push to protected' no-push $p
  $p = Fixture pretooluse-main-bash $w; $p.tool_input.command = 'gh pr create --base main --title x'
  Both 'PR to protected' no-pr-to-protected $p
  $p = Fixture pretooluse-main-bash $w; $p.tool_input.command = 'gh pr create --base develop --title x'
  Both 'PR without review' code-review-gate $p
  $wt = New-Workspace
  [IO.File]::WriteAllText("$wt/.milestone-config/driver.json", '{"sourceGlobs":["*.txt"],"unitTestCmd":"git not-a-real-subcommand","integrationGranularity":"issue"}', $utf8)
  [IO.File]::WriteAllText("$wt/a.txt", "x`n", $utf8); git -C $wt add a.txt
  $p = Fixture pretooluse-main-bash $wt; $p.tool_input.command = 'git commit -m x'
  Both 'commit on red suite' tests-green $p

  # dispatch-cap: Codex encrypts the spawn message, so the agent and issue come
  # from task_name `<agent>_issue_<n>_<attempt>`. Captured tool_name is
  # `collaborationspawn_agent`; the bare `spawn_agent` is accepted too.
  $wd = New-Workspace
  git -C $wd checkout -q -b milestone-work   # no issue branch: the key comes from task_name
  function Spawn([string]$task, [string]$tool = 'collaborationspawn_agent') {
    $p = Fixture pretooluse-main-spawn_agent $wd; $p.tool_input.task_name = $task; $p.tool_name = $tool
    return $p
  }
  foreach ($i in 1..3) { Expect-Allow "implementer spawn $i" (Run dispatch-cap (Spawn "implementer_issue_7_$i")) }
  Expect-Deny 'implementer spawn 4, agent-path form' (Run dispatch-cap (Spawn '/root/implementer_issue_7_4'))
  foreach ($i in 1..2) { Expect-Allow "planner spawn $i" (Run dispatch-cap (Spawn "planner_issue_8_$i" 'spawn_agent')) }
  $r = Run dispatch-cap (Spawn 'planner_issue_8_3' 'spawn_agent')
  Expect-Deny 'planner spawn 3' $r
  if ($r.out -match 'planner dispatch 3 of at most 2 for issue 8') { $pass++ } else { $fail++; Write-Host "FAIL planner deny names issue 8: out=[$($r.out)]" }
  foreach ($i in 1..5) { Expect-Allow "uncapped task_name $i" (Run dispatch-cap (Spawn 'child')) }
  $p = Spawn 'implementer_issue_7_5'; $p.agent_id = 'child-thread'; $p.agent_type = 'default'
  Expect-Allow 'spawn from a child is not counted' (Run dispatch-cap $p)
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force
}
Write-Host "codex-fixtures ($Leg): $pass passed, $fail failed"
if ($fail) { exit 1 }
