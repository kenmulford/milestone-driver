#!/usr/bin/env pwsh
# milestone-driver - runner for the dispatch-cap.ps1 hook; the pwsh twin of
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here '_lib.ps1'); Set-Leg $Leg
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Hook = Join-Path $Root 'hooks' 'dispatch-cap'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }
$env:CLAUDE_HOOK_DISABLE_DISPATCH_CAP = $null

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Ok { $script:pass++ }
function No([string]$msg) { $script:fail++; Write-Host "FAIL $msg" }
function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

$Impl = 'milestone-driver:implementer'

function New-Workspace([string]$branch = 'issue/7-x', [string]$profileJson = '{"sourceGlobs":["src/**"]}') {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $w | Out-Null
  & git -C $w init -q 2>$null | Out-Null
  & git -C $w config core.hooksPath (Join-Path $w '.git' 'no-such-hooks') 2>$null | Out-Null
  & git -C $w config commit.gpgsign false 2>$null | Out-Null
  & git -C $w config user.email 'tests@milestone-driver.invalid' 2>$null | Out-Null
  & git -C $w config user.name 'dispatch-cap tests' 2>$null | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $w 'README.md'), "seed`n", $utf8)
  & git -C $w add -A 2>$null | Out-Null
  & git -C $w commit -q -m base 2>$null | Out-Null
  & git -C $w checkout -q -b $branch 2>$null | Out-Null
  if ($profileJson -ne '-') {
    New-Item -ItemType Directory -Path (Join-Path $w '.milestone-config') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $w '.milestone-config' 'driver.json'), $profileJson + "`n", $utf8)
  }
  return $w
}

function Invoke-Hook([string]$root, [string]$tool, [string]$who, [string]$text, [string]$agentId = '', [bool]$envOff = $false, [bool]$noType = $false) {
  if ($tool -eq 'Skill') { $ti = @{ skill = $who; args = $text } }
  elseif ($noType) { $ti = @{ prompt = $text } }
  else { $ti = @{ subagent_type = $who; prompt = $text } }
  $obj = @{ tool_name = $tool; tool_input = $ti; cwd = $root }
  if ($agentId) { $obj['agent_id'] = $agentId }
  $payload = $obj | ConvertTo-Json -Compress
  $envs = @{}
  if ($envOff) { $envs['CLAUDE_HOOK_DISABLE_DISPATCH_CAP'] = '1' }
  return Invoke-Leg -Script $Hook -Stdin $payload -Cwd $Tmp -Env $envs
}

function Expect([string]$label, $r, [int]$want) {
  if ($r.rc -eq $want) { Ok } else { No "${label}: rc=$($r.rc) (want $want) err=[$(Show-Escaped $r.err)]" }
}

# ---- implementer: 3 dispatches allowed, the 4th denied --------------------
$W = New-Workspace
foreach ($i in 1..3) { Expect "implementer-allow-$i" (Invoke-Hook $W 'Agent' $Impl 'Build issue #7') 0 }
$r = Invoke-Hook $W 'Agent' $Impl 'Build issue #7'
Expect 'implementer-deny-4th' $r 2
if ($r.err -match 'dispatch cap' -and $r.err -match 'implementer dispatch 4 of at most 3 for issue 7') { Ok }
else { No "implementer-deny-message: err=[$(Show-Escaped $r.err)]" }

# ---- the counter file -------------------------------------------------------
$f = Join-Path $W '.git' 'milestone-driver' 'dispatch-cap' 'implementer-7'
if ((Test-Path -LiteralPath $f) -and ((Get-Content -LiteralPath $f -Raw).Trim() -split ' ')[1] -eq '3') { Ok }
else { No "counter-file: [$f]" }

# ---- planner: its own counter, 2 allowed, the 3rd denied --------------------
$Plan = 'milestone-driver:planner'
$fp = Join-Path $W '.git' 'milestone-driver' 'dispatch-cap' 'planner-7'
if (-not (Test-Path -LiteralPath $fp)) { Ok } else { No "planner-counter-absent: [$fp]" }
Expect 'planner-allow-1' (Invoke-Hook $W 'Agent' $Plan 'Plan issue #7') 0
if (Test-Path -LiteralPath $fp) { Ok } else { No "planner-counter-created: [$fp]" }
Expect 'planner-allow-2' (Invoke-Hook $W 'Agent' $Plan 'Plan issue #7') 0
$r = Invoke-Hook $W 'Agent' $Plan 'Plan issue #7'
Expect 'planner-deny-3rd' $r 2
if ($r.err -match 'dispatch cap' -and $r.err -match 'planner dispatch 3 of at most 2 for issue 7') { Ok }
else { No "planner-deny-message: err=[$(Show-Escaped $r.err)]" }
Expect 'planner-task-deny' (Invoke-Hook $W 'Task' $Plan 'Plan issue #7') 2
Expect 'planner-escape-hatch' (Invoke-Hook $W 'Agent' $Plan 'x' '' $true) 0

# ---- review: its own counter, 3 allowed, the 4th denied --------------------
foreach ($i in 1..3) { Expect "review-allow-$i" (Invoke-Hook $W 'Skill' 'code-review' '') 0 }
Expect 'review-deny-4th' (Invoke-Hook $W 'Skill' 'code-review' '') 2
Expect 'review-deny-namespaced' (Invoke-Hook $W 'Skill' 'code-review:code-review' '') 2

# ---- never counted: other agents and other skills, even on a capped key ---
Expect 'deny-other-agent' (Invoke-Hook $W 'Agent' 'general-purpose' 'Review #7') 2
Expect 'allow-other-skill' (Invoke-Hook $W 'Skill' 'superpowers:brainstorming' '') 0
Expect 'allow-other-tool' (Invoke-Hook $W 'Bash' '' '') 0

# ---- dispatch contract: a main-thread general-purpose or untyped Agent dispatch is denied on issue/*, wave/*, milestone-*
$GP = 'general-purpose'
$Named = @('milestone-driver:planner', 'milestone-driver:reviewer', 'milestone-driver:triage-reviewer', 'milestone-driver:design-reviewer',
  'milestone-driver:blocker-resolver', 'milestone-driver:process-auditor', 'milestone-coherence-reviewer:coherence-reviewer')
function Get-DenyReason([string]$subject, [string]$branch, [string]$impl = $Impl) {
  return "milestone-driver: dispatch contract - a main-thread Agent dispatch with $subject is denied on branch $branch. Dispatch a named agent: $impl, $($Named -join ', '). Operator override: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1."
}
function Expect-Reason([string]$label, $r, [string]$want) {
  $got = ([string]$r.err).TrimEnd("`r", "`n")
  if ($got -ceq $want) { Ok } else { No "${label}: reason=[$(Show-Escaped $got)] (want [$(Show-Escaped $want)])" }
}
function Test-CapDirEmpty([string]$ws) {
  $d = Join-Path $ws '.git' 'milestone-driver' 'dispatch-cap'
  return (-not (Test-Path -LiteralPath $d)) -or (@(Get-ChildItem -LiteralPath $d -Force).Count -eq 0)
}
foreach ($b in 'issue/7-x', 'wave/5-w2', 'milestone-5-x') {
  $wg = New-Workspace $b
  $r = Invoke-Hook $wg 'Agent' $GP 'Review #7'
  Expect "deny-gp-$b" $r 2
  Expect-Reason "deny-gp-reason-$b" $r (Get-DenyReason 'subagent_type general-purpose' $b)
  if (Test-CapDirEmpty $wg) { Ok } else { No "deny-gp-writes-no-counter-${b}" }
}
$WG = New-Workspace 'milestone-5-x'
$r = Invoke-Hook $WG 'Task' $GP 'Review #7'
Expect 'deny-gp-task' $r 2
Expect-Reason 'deny-gp-task-reason' $r (Get-DenyReason 'subagent_type general-purpose' 'milestone-5-x')
$r = Invoke-Hook $WG 'Agent' '' 'Review #7' '' $false $true
Expect 'deny-no-subagent-type-key' $r 2
Expect-Reason 'deny-no-subagent-type-key-reason' $r (Get-DenyReason 'no subagent_type' 'milestone-5-x')
$r = Invoke-Hook $WG 'Agent' '' 'Review #7'
Expect 'deny-empty-subagent-type' $r 2
Expect-Reason 'deny-empty-subagent-type-reason' $r (Get-DenyReason 'no subagent_type' 'milestone-5-x')
foreach ($t in 'General-Purpose', 'claude', 'Claude', 'fork') {
  $r = Invoke-Hook $WG 'Agent' $t 'Review #7'
  Expect "deny-catch-all-$t" $r 2
  Expect-Reason "deny-catch-all-reason-$t" $r (Get-DenyReason "subagent_type $t" 'milestone-5-x')
}
if (Test-CapDirEmpty $WG) { Ok } else { No 'deny-catch-all-writes-no-counter' }
$WB = New-Workspace 'issue/7-x' '{"implementerAgent":"acme:builder"}'
$r = Invoke-Hook $WB 'Agent' $GP 'Review #7'
Expect 'deny-gp-custom-implementer' $r 2
Expect-Reason 'deny-gp-custom-implementer-reason' $r (Get-DenyReason 'subagent_type general-purpose' 'issue/7-x' 'acme:builder')
if (Test-CapDirEmpty $WB) { Ok } else { No 'deny-gp-custom-implementer-writes-no-counter' }

# ---- dispatch contract: every other named agent is allowed on those branches
foreach ($a in (@($Impl) + $Named + @('Explore'))) {
  Expect "allow-named-$a" (Invoke-Hook $WG 'Agent' $a 'Review #7') 0
}
Expect 'allow-reviewer-simplify-angle' (Invoke-Hook $WG 'Agent' 'milestone-driver:reviewer' 'Simplify review: reuse') 0
Expect 'deny-gp-simplify-angle' (Invoke-Hook $WG 'Agent' $GP 'Simplify review: reuse') 2
Expect 'allow-gp-subagent-context-ms' (Invoke-Hook $WG 'Agent' $GP 'Review #7' 'agent-1') 0
# A forked skill's leaf (`/code-review` runs forked) carries an agent_id, so it is not main-thread.
Expect 'allow-gp-forked-leaf-issue' (Invoke-Hook (New-Workspace 'issue/7-x') 'Agent' $GP 'Review #7' 'agent-fork-1') 0
Expect 'allow-gp-forked-leaf-ms' (Invoke-Hook (New-Workspace 'milestone-54-x') 'Agent' $GP 'Review #7' 'agent-fork-1') 0
Expect 'allow-gp-escape-hatch' (Invoke-Hook $WG 'Agent' $GP 'Review #7' '' $true) 0
Expect 'allow-gp-develop' (Invoke-Hook (New-Workspace 'develop') 'Agent' $GP 'Review #7') 0
Expect 'allow-gp-no-profile' (Invoke-Hook (New-Workspace 'issue/7-x' '-') 'Agent' $GP 'Review #7') 0
$NoGit = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path (Join-Path $NoGit '.milestone-config') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $NoGit '.milestone-config' 'driver.json'), "{}`n", $utf8)
Expect 'allow-gp-not-a-git-repo' (Invoke-Hook $NoGit 'Agent' $GP 'Review #7') 0
Expect 'allow-code-review-skill-ms' (Invoke-Hook $WG 'Skill' 'code-review' '') 0

# ---- allow: subagent context on the capped key ----------------------------
Expect 'allow-subagent-context' (Invoke-Hook $W 'Agent' $Impl 'Build issue #7' 'agent-1') 0

# ---- allow: the escape hatch on the capped key -----------------------------
Expect 'allow-escape-hatch' (Invoke-Hook $W 'Agent' $Impl 'x' '' $true) 0

# ---- a moved HEAD resets the budget ----------------------------------------
[System.IO.File]::AppendAllText((Join-Path $W 'README.md'), "more`n", $utf8)
& git -C $W commit -q -am step 2>$null | Out-Null
Expect 'reset-on-new-head' (Invoke-Hook $W 'Agent' $Impl 'Build issue #7') 0

# ---- milestone end: the marker keys `milestone-<n>`, 3 implementer + 1 planner, HEAD-proof
$WS = New-Workspace 'milestone-53-x'
$CapDir = Join-Path $WS '.git' 'milestone-driver' 'dispatch-cap'
$Mark = "Milestone-End-Fix: 53`nFix the finding."
Expect 'ms-implementer-allow-1' (Invoke-Hook $WS 'Agent' $Impl $Mark) 0
$fm = Join-Path $CapDir 'implementer-milestone-53'
if ((Test-Path -LiteralPath $fm) -and (Get-Content -LiteralPath $fm -Raw) -ceq "milestone-53-x 1`n") { Ok }
else { No "ms-counter-first: [$fm]" }
foreach ($i in 2..3) { Expect "ms-implementer-allow-$i" (Invoke-Hook $WS 'Agent' $Impl $Mark) 0 }
$PluginRoot = if ($env:CLAUDE_PLUGIN_ROOT) { "$($env:CLAUDE_PLUGIN_ROOT)/" } else { '' }
function Get-MsDenyReason([string]$kind, [int]$n, [int]$cap, [string]$ms) {
  return "milestone-driver: dispatch cap - this would be $kind dispatch $n of at most $cap for milestone end $ms. Follow the cap-spent path of ${PluginRoot}skills/solve-milestone/milestone-end-gates.md; its Halt runs ${PluginRoot}scripts/reset-dispatch-cap.<sh|ps1> <repo-root> milestone-$ms, so a resumed milestone end starts a fresh budget. Operator override: CLAUDE_HOOK_DISABLE_DISPATCH_CAP=1."
}
$r = Invoke-Hook $WS 'Agent' $Impl $Mark
Expect 'ms-implementer-deny-4th' $r 2
Expect-Reason 'ms-implementer-deny-reason' $r (Get-MsDenyReason 'implementer' 4 3 '53')
Expect 'ms-planner-allow-1' (Invoke-Hook $WS 'Agent' $Plan $Mark) 0
if (Test-Path -LiteralPath (Join-Path $CapDir 'planner-milestone-53')) { Ok } else { No 'ms-planner-counter-created' }
$r = Invoke-Hook $WS 'Agent' $Plan $Mark
Expect 'ms-planner-deny-2nd' $r 2
Expect-Reason 'ms-planner-deny-reason' $r (Get-MsDenyReason 'planner' 2 1 '53')
[System.IO.File]::AppendAllText((Join-Path $WS 'README.md'), "fix`n", $utf8)
& git -C $WS commit -q -am fix 2>$null | Out-Null
Expect 'ms-deny-after-head-move' (Invoke-Hook $WS 'Agent' $Impl $Mark) 2
Expect 'ms-subagent-context-allowed' (Invoke-Hook $WS 'Agent' $Impl $Mark 'agent-1') 0
Expect 'ms-escape-hatch-allowed' (Invoke-Hook $WS 'Agent' $Impl $Mark '' $true) 0
if ((Get-Content -LiteralPath $fm -Raw) -ceq "milestone-53-x 3`n") { Ok } else { No "ms-counter-unchanged: [$((Get-Content -LiteralPath $fm -Raw))]" }

# ---- milestone branch, no matching marker: today's issue key, milestone counter untouched
Expect 'ms-no-marker-issue-key' (Invoke-Hook $WS 'Agent' $Impl 'Build issue #7') 0
Expect 'ms-mid-prompt-marker-issue-key' (Invoke-Hook $WS 'Agent' $Impl "Build issue #8`nMilestone-End-Fix: 53") 0
Expect 'ms-mismatched-marker-issue-key' (Invoke-Hook $WS 'Agent' $Impl "Milestone-End-Fix: 54`nIssue #9") 0
Expect 'ms-longer-number-marker-issue-key' (Invoke-Hook $WS 'Agent' $Impl "Milestone-End-Fix: 530`nIssue #10") 0
foreach ($k in 7, 8, 9, 10) {
  if (Test-Path -LiteralPath (Join-Path $CapDir "implementer-$k")) { Ok } else { No "ms-issue-key-$k-counter" }
}
if (-not (Test-Path -LiteralPath (Join-Path $CapDir 'implementer-milestone-54'))) { Ok } else { No 'ms-54-counter-absent' }
if ((Get-Content -LiteralPath $fm -Raw) -ceq "milestone-53-x 3`n") { Ok } else { No 'ms-counter-untouched-by-unmarked' }

# ---- the marker may follow leading whitespace, a blank first line included
$WL = New-Workspace 'milestone-53-x'
$fl = Join-Path $WL '.git' 'milestone-driver' 'dispatch-cap' 'implementer-milestone-53'
Expect 'ms-indented-marker' (Invoke-Hook $WL 'Agent' $Impl "  Milestone-End-Fix: 53`nFix the finding.") 0
Expect 'ms-blank-line-marker' (Invoke-Hook $WL 'Agent' $Impl "`nMilestone-End-Fix: 53`nFix the finding.") 0
if ((Test-Path -LiteralPath $fl) -and (Get-Content -LiteralPath $fl -Raw) -ceq "milestone-53-x 2`n") { Ok } else { No "ms-leading-space-counter: [$fl]" }

# ---- Codex: the milestone end keys on task_name `<agent>_milestone_<n>_<attempt>`
function Invoke-CodexSpawn([string]$root, [string]$task) {
  $payload = @{ tool_name = 'spawn_agent'; tool_input = @{ task_name = $task }; cwd = $root } | ConvertTo-Json -Compress
  return Invoke-Leg -Script $Hook -Stdin $payload -Cwd $Tmp
}
$WX = New-Workspace 'milestone-53-x'
$CapX = Join-Path $WX '.git' 'milestone-driver' 'dispatch-cap'
foreach ($i in 1..3) { Expect "codex-ms-implementer-allow-$i" (Invoke-CodexSpawn $WX "implementer_milestone_53_$i") 0 }
if ((Get-Content -LiteralPath (Join-Path $CapX 'implementer-milestone-53') -Raw -ErrorAction SilentlyContinue) -ceq "milestone-53-x 3`n") { Ok } else { No 'codex-ms-counter' }
$r = Invoke-CodexSpawn $WX '/root/implementer_milestone_53_4'
Expect 'codex-ms-implementer-deny-4th' $r 2
Expect-Reason 'codex-ms-implementer-deny-reason' $r (Get-MsDenyReason 'implementer' 4 3 '53')
Expect 'codex-ms-planner-allow-1' (Invoke-CodexSpawn $WX 'planner_milestone_53_1') 0
$r = Invoke-CodexSpawn $WX 'planner_milestone_53_2'
Expect 'codex-ms-planner-deny-2nd' $r 2
Expect-Reason 'codex-ms-planner-deny-reason' $r (Get-MsDenyReason 'planner' 2 1 '53')
Expect 'codex-ms-mismatched-number' (Invoke-CodexSpawn $WX 'implementer_milestone_54_1') 0
if (Test-Path -LiteralPath (Join-Path $CapX 'implementer-milestone-53-x')) { Ok } else { No 'codex-ms-mismatched-branch-key' }

# ---- Codex: the task_name strip is case-sensitive on both legs, so `_ISSUE_` maps to no row
$WU = New-Workspace 'issue/7-x'
foreach ($i in 1..4) { Expect "codex-uppercase-suffix-uncounted-$i" (Invoke-CodexSpawn $WU "implementer_ISSUE_7_$i") 0 }
if (Test-CapDirEmpty $WU) { Ok } else { No 'codex-uppercase-suffix-writes-no-counter' }

# ---- sh leg: a CRLF-emitting jq (Windows jq.exe) still reads subagent_type and the other fields
if ($Leg -eq 'sh') {
  $CrDir = Join-Path $Tmp 'crlf-jq'
  New-Item -ItemType Directory -Path $CrDir | Out-Null
  $realJq = (Get-Command jq -CommandType Application | Select-Object -First 1).Source
  [System.IO.File]::WriteAllText((Join-Path $CrDir 'jq'), "#!/usr/bin/env bash`n'$realJq' `"`$@`" | awk '{ printf `"%s\r\n`", `$0 }'`n", $utf8)
  & chmod +x (Join-Path $CrDir 'jq')
  $WR = New-Workspace 'issue/7-x'
  $payload = @{ tool_name = 'Agent'; tool_input = @{ subagent_type = $GP; prompt = 'Review #7' }; cwd = $WR } | ConvertTo-Json -Compress
  $r = Invoke-Leg -Script $Hook -Stdin $payload -Cwd $Tmp -Env @{ PATH = "$CrDir$([System.IO.Path]::PathSeparator)$env:PATH" }
  Expect 'crlf-jq-deny-gp' $r 2
  Expect-Reason 'crlf-jq-deny-gp-reason' $r (Get-DenyReason 'subagent_type general-purpose' 'issue/7-x')
}

# ---- the marker on a non-milestone branch keeps the issue key; review is never milestone-keyed
$WI = New-Workspace 'issue/7-x'
Expect 'marker-on-issue-branch' (Invoke-Hook $WI 'Agent' $Impl $Mark) 0
if ((Test-Path -LiteralPath (Join-Path $WI '.git' 'milestone-driver' 'dispatch-cap' 'implementer-7')) -and
    -not (Test-Path -LiteralPath (Join-Path $WI '.git' 'milestone-driver' 'dispatch-cap' 'implementer-milestone-53'))) { Ok }
else { No 'marker-on-issue-branch-key' }
Expect 'ms-review-skill-branch-key' (Invoke-Hook $WS 'Skill' 'code-review' $Mark) 0
if ((Test-Path -LiteralPath (Join-Path $CapDir 'review-milestone-53-x')) -and
    -not (Test-Path -LiteralPath (Join-Path $CapDir 'review-milestone-53'))) { Ok }
else { No 'ms-review-skill-key' }

# ---- allow: no profile means not a milestone-driver repo -------------------
$WN = New-Workspace 'issue/7-x' '-'
$r = $null
foreach ($i in 1..4) { $r = Invoke-Hook $WN 'Agent' $Impl 'x' }
Expect 'allow-no-profile' $r 0

# ---- legacy Task tool name is counted like Agent ---------------------------
$WT = New-Workspace
foreach ($i in 1..3) { [void](Invoke-Hook $WT 'Task' $Impl 'x') }
Expect 'task-deny-4th' (Invoke-Hook $WT 'Task' $Impl 'x') 2

# ---- a profile's implementerAgent override is what gets counted ------------
$WC = New-Workspace 'issue/7-x' '{"implementerAgent":"acme:builder"}'
foreach ($i in 1..4) { $r = Invoke-Hook $WC 'Agent' $Impl 'x' }
Expect 'custom-agent-default-name-uncounted' $r 0
foreach ($i in 1..3) { [void](Invoke-Hook $WC 'Agent' 'acme:builder' 'x') }
Expect 'custom-agent-deny-4th' (Invoke-Hook $WC 'Agent' 'acme:builder' 'x') 2

# ---- off an issue branch, the brief names the issue ------------------------
$WP = New-Workspace 'develop'
foreach ($i in 1..3) { [void](Invoke-Hook $WP 'Agent' $Impl 'Issue #11: add the thing. Depends on #3.') }
$r = Invoke-Hook $WP 'Agent' $Impl 'Issue #11: add the thing. Depends on #3.'
Expect 'brief-key-deny-4th' $r 2
if ($r.err -match 'for issue 11 ') { Ok } else { No "brief-key-is-11: err=[$(Show-Escaped $r.err)]" }
Expect 'brief-key-other-issue-allowed' (Invoke-Hook $WP 'Agent' $Impl 'issue 12 - the other thing') 0
if (Test-Path -LiteralPath (Join-Path $WP '.git' 'milestone-driver' 'dispatch-cap' 'implementer-12')) { Ok } else { No 'brief-key-12-counter' }
Expect 'branch-key-fallback' (Invoke-Hook $WP 'Skill' 'code-review' '') 0
if (Test-Path -LiteralPath (Join-Path $WP '.git' 'milestone-driver' 'dispatch-cap' 'review-develop')) { Ok } else { No 'branch-key-counter' }
foreach ($i in 1..2) { [void](Invoke-Hook $WP 'Skill' 'code-review' '') }
$r = Invoke-Hook $WP 'Skill' 'code-review' ''
Expect 'branch-key-deny-4th' $r 2
if ($r.err -match 'for branch develop ') { Ok } else { No "branch-key-message: err=[$(Show-Escaped $r.err)]" }

# ---- a malformed profile still gates, with the default implementer name -----
$WM = New-Workspace 'issue/7-x' '{ not json'
foreach ($i in 1..3) { [void](Invoke-Hook $WM 'Agent' $Impl 'x') }
Expect 'malformed-profile-deny-4th' (Invoke-Hook $WM 'Agent' $Impl 'x') 2

Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "dispatch-cap ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
