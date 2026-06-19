#!/usr/bin/env pwsh
# milestone-driver — CI-aware preflight step discovery (issue #162).
#
# Behavior-identical pwsh sibling of scripts/ci-preflight-steps.sh. Discovers the
# runnable shell steps of a repo's PR-gating GitHub Actions workflows so
# `preflightCmd: "github-ci"` can front-run CI's cheap checks locally. Reads the
# workflows from disk; NEVER calls the network. A constrained, line-oriented
# parser handles the NARROW surface only (jobs -> steps -> run/
# working-directory/if/uses/continue-on-error + the workflow `on:` trigger). NO
# YAML library, NO new dependency — see the design spec's "Build decision".
#
# Usage:   ci-preflight-steps.ps1 [REPO_ROOT] [CI_WORKFLOW]
# Output:  the same TAB-separated STEP/SKIP/CHECK/WARN/SUMMARY record stream as
#          the .sh sibling (see its header). Fail-open, exit 0 always.
param(
  [string]$Root = (Get-Location).Path,
  [string]$OnlyWorkflow = ''
)
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout so the em-dash in WARN messages matches the .sh byte output.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Root = ($Root -replace '[\\/]+$', '')

$script:mirrored = 0
$script:skipped = 0
$script:out = New-Object System.Collections.Generic.List[string]
function Emit([string]$s) { $script:out.Add($s) }
function Flush {
  $sb = New-Object System.Text.StringBuilder
  foreach ($l in $script:out) { if ($l -ne '') { [void]$sb.Append($l); [void]$sb.Append("`n") } }
  [void]$sb.Append("SUMMARY`tmirrored=$($script:mirrored)`tskipped=$($script:skipped)`n")
  [Console]::Out.Write($sb.ToString())
}

# Use a forward-slash path string in all output so WARN messages are byte-identical
# to the .sh sibling on every host (Join-Path yields backslashes on Windows).
$wfdir = "$Root/.github/workflows"
if (-not (Test-Path -LiteralPath $wfdir -PathType Container)) {
  Emit "WARN`tno .github/workflows directory found at $Root — nothing to mirror"
  Flush; exit 0
}

# Collect *.yml + *.yaml, sorted by basename ascending for determinism.
$wfiles = @(Get-ChildItem -LiteralPath $wfdir -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '\.(yml|yaml)$' } |
  Sort-Object Name)
if ($wfiles.Count -eq 0) {
  Emit "WARN`tno workflow files in $wfdir — nothing to mirror"
  Flush; exit 0
}

$script:integrationBranch = ''
$profilePath = Join-Path $Root '.milestone-config/driver.json'
if (-not (Test-Path -LiteralPath $profilePath)) { $profilePath = Join-Path $Root 'milestone-driver.json' }
if (Test-Path -LiteralPath $profilePath) {
  try { $cfg = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json -ErrorAction Stop; if ($cfg.integrationBranch) { $script:integrationBranch = [string]$cfg.integrationBranch } } catch {}
}

# --- helpers (mirror the .sh string ops) ------------------------------------
function Get-Indent([string]$s) { return ([regex]::Match($s, '^[ ]*')).Length }
function Trim2([string]$s) { return $s.Trim() }
function Strip-Inline([string]$v) { return ([regex]::Replace($v, '\s+#.*$', '')) }
function Unquote([string]$s) {
  if ($s.Length -ge 2 -and $s[0] -eq '"' -and $s[-1] -eq '"') { return $s.Substring(1, $s.Length - 2) }
  if ($s.Length -ge 2 -and $s[0] -eq "'" -and $s[-1] -eq "'") { return $s.Substring(1, $s.Length - 2) }
  return $s
}
function Encode-Cmd([string]$s) {
  $s = $s.Replace('\', '\\')
  return $s.Replace("`n", '\n')
}

# --- PR-gating detection ----------------------------------------------------
function Test-PrGating([string]$file) {
  $hasPr = $false; $hasPush = $false; $pushSubkeys = $false; $pushBranchesKey = $false; $pushBranchOk = $false
  $inOn = $false; $onIndent = -1; $curTrigger = ''; $triggerIndent = -1; $inBranches = $false
  foreach ($raw in [System.IO.File]::ReadLines($file)) {
    $line = $raw -replace "`r$", ''
    if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
    $indent = Get-Indent $line
    $content = Trim2 $line
    if (-not $inOn) {
      if ($content -match '^(on:|"on":|''on'':)') {
        $onIndent = $indent; $inOn = $true
        $val = Trim2 ($content -replace '^[^:]*:', '')
        if ($val -match 'pull_request') { $hasPr = $true }
        if ($val -match 'push') { $hasPush = $true; $pushSubkeys = $false }
        if ($val -ne '') { $inOn = $false }
      }
      continue
    }
    if ($indent -le $onIndent) { break }
    if ($indent -gt $triggerIndent -and $triggerIndent -ge 0) {
      if ($curTrigger -eq 'push') {
        $pushSubkeys = $true
        if ($content -match '^branches(:|$)') { $pushBranchesKey = $true; $inBranches = $true }
        if ($pushBranchesKey -and $inBranches) {
          if ($content -match '^branches:') {
            $val = Trim2 ($content -replace '^branches:', '')
            if ($val -match '^\[.*\]$') {
              $inner = $val.Substring(1, $val.Length - 2)
              foreach ($b in ($inner -split ',')) { $bb = Unquote (Trim2 $b); if ($script:integrationBranch -ne '' -and $bb -eq $script:integrationBranch) { $pushBranchOk = $true } }
            }
          }
          if ($content -match '^-') {
            $val = Unquote (Trim2 ($content -replace '^-', ''))
            if ($script:integrationBranch -ne '' -and $val -eq $script:integrationBranch) { $pushBranchOk = $true }
          }
        }
      }
      continue
    }
    if ($content -match '^pull_request(:|$)' -or $content -match '^pull_request_target(:|$)') { $hasPr = $true; $curTrigger = 'pull_request'; $triggerIndent = $indent; $inBranches = $false }
    elseif ($content -match '^push(:|$)') { $hasPush = $true; $curTrigger = 'push'; $triggerIndent = $indent; $pushSubkeys = $false; $inBranches = $false }
    else { $curTrigger = 'other'; $triggerIndent = $indent; $inBranches = $false }
  }
  if ($hasPr) { return $true }
  if ($hasPush) {
    if (-not $pushSubkeys) { return $true }
    if ($pushBranchesKey -and $pushBranchOk) { return $true }
  }
  return $false
}

# --- step extraction --------------------------------------------------------
# Shared mutable state ($p_*) lives at script scope so the inline finalize/reset
# blocks and the main loop read & write the same cells (a literal port of the
# .sh function-local accumulators). Reset at function entry for re-entrancy.
function Get-WorkflowSteps([string]$file) {
  $script:wfname = Split-Path -Leaf $file
  $script:inJobs = $false; $script:jobsIndent = -1
  $script:curJob = ''; $script:jobIndent = -1
  $script:inSteps = $false; $script:stepsIndent = -1
  $script:stepIdx = 0
  $script:jobUses = ''; $script:jobServices = $false; $script:jobEmitted = $false
  Reset-Step
  Reset-Job

  foreach ($raw in [System.IO.File]::ReadLines($file)) {
    $line = $raw -replace "`r$", ''
    if ($script:sRunActive -and $script:sRunBlock) {
      $indent = Get-Indent $line
      if ((Trim2 $line) -eq '') {
        if ($script:sRun -ne '') { $script:sRun = $script:sRun + "`n" }
        continue
      }
      if ($indent -gt $script:sRunIndent) {
        if ($script:blockBase -lt 0) { $script:blockBase = $indent }
        $body = if ($line.Length -ge $script:blockBase) { $line.Substring($script:blockBase) } else { '' }
        if ($script:sRun -ne '') { $script:sRun = $script:sRun + "`n" + $body } else { $script:sRun = $body }
        continue
      } else {
        $script:sRunActive = $false; $script:sRunBlock = $false; $script:blockBase = -1
      }
    }
    if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
    $indent = Get-Indent $line
    $content = Trim2 $line

    if (-not $script:inJobs) {
      if ($content -eq 'jobs:') { $script:inJobs = $true; $script:jobsIndent = $indent }
      continue
    }
    if ($indent -le $script:jobsIndent -and $script:inJobs) {
      Finalize-Step; Finalize-Job; $script:curJob = ''
      if ($content -eq 'jobs:') { $script:inJobs = $true; $script:jobsIndent = $indent; $script:inSteps = $false } else { $script:inJobs = $false }
      continue
    }

    if (-not $script:inSteps -and $indent -gt $script:jobsIndent) {
      if ($script:curJob -eq '' -or $indent -le $script:jobIndent) {
        if ($content -match ':') {
          Finalize-Step; Finalize-Job
          $script:curJob = (Trim2 ($content -replace ':.*$', ''))
          $script:jobIndent = $indent; $script:inSteps = $false; $script:stepIdx = 0; Reset-Job
          continue
        }
      }
      if ($content -match '^uses:') { $script:jobUses = Unquote (Trim2 (Strip-Inline ($content -replace '^uses:', ''))); continue }
      if ($content -match '^services(:|$)') { $script:jobServices = $true; continue }
    }

    if ($content -eq 'steps:') { Finalize-Step; $script:inSteps = $true; $script:stepsIndent = $indent; continue }

    if ($script:inSteps) {
      if ($indent -le $script:jobIndent -and $indent -le $script:stepsIndent) {
        Finalize-Step; $script:inSteps = $false
        if ($indent -le $script:jobsIndent) { Finalize-Job; $script:curJob = ''; $script:inJobs = $false; continue }
        if ($content -match ':') {
          Finalize-Job
          $script:curJob = (Trim2 ($content -replace ':.*$', ''))
          $script:jobIndent = $indent; $script:stepIdx = 0; Reset-Job
          continue
        }
        continue
      }
      if ($content -match '^-') {
        Finalize-Step
        $script:hasStep = $true
        $content = Trim2 ($content -replace '^-', '')
        if ($content -eq '') { continue }
      }
      if ($content -match '^run:') {
        $v = Trim2 ($content -replace '^run:', '')
        if ($v -match '^[|>]' -or $v -eq '') {
          $script:sRunActive = $true; $script:sRunBlock = $true; $script:sRunIndent = $indent; $script:sRun = ''
        } else {
          $script:sRun = Unquote (Strip-Inline $v)
        }
      }
      elseif ($content -match '^working-directory:') { $script:sWdir = Unquote (Trim2 (Strip-Inline ($content -replace '^working-directory:', ''))) }
      elseif ($content -match '^if:') { $script:sIf = Trim2 ($content -replace '^if:', '') }
      elseif ($content -match '^uses:') { $script:sUses = Unquote (Trim2 (Strip-Inline ($content -replace '^uses:', ''))) }
      elseif ($content -match '^continue-on-error:') { $v = Trim2 (Strip-Inline ($content -replace '^continue-on-error:', '')); if ($v -eq 'true') { $script:sCoe = 1 } }
      if ($content -match 'secrets\.' -or $content -match 'secrets\[') { $script:sSecrets = $true }
      if ($content -match '^services:') { $script:sServicesRef = $true }
    }
  }
  Finalize-Step
  Finalize-Job
}

function Reset-Step {
  $script:sRun = ''; $script:sRunActive = $false; $script:sRunIndent = -1; $script:sRunBlock = $false; $script:blockBase = -1
  $script:sWdir = ''; $script:sIf = ''; $script:sUses = ''; $script:sCoe = 0; $script:sSecrets = $false; $script:sServicesRef = $false
  $script:hasStep = $false
}
function Reset-Job { $script:jobUses = ''; $script:jobServices = $false; $script:jobEmitted = $false }

function Finalize-Step {
  if (-not $script:hasStep) { return }
  $script:jobEmitted = $true
  $script:stepIdx++
  $label = "$($script:wfname)/$($script:curJob)/step$($script:stepIdx)"
  if ($script:sUses -ne '') { Emit "SKIP`t$($script:wfname)`t$($script:curJob)`tuses-step`t$($script:sUses)"; $script:skipped++; Reset-Step; return }
  if ($script:sRun -eq '') { Emit "SKIP`t$($script:wfname)`t$($script:curJob)`tno-run`tstep has no run: command"; $script:skipped++; Reset-Step; return }
  if ($script:sSecrets) { Emit "SKIP`t$($script:wfname)`t$($script:curJob)`tsecrets`treferences secrets"; $script:skipped++; Reset-Step; return }
  if ($script:sServicesRef -or $script:jobServices) { Emit "SKIP`t$($script:wfname)`t$($script:curJob)`tservices-or-deploy`tjob/step uses a service container or deploy/publish"; $script:skipped++; Reset-Step; return }
  if ($script:sRun -match '\$\{\{') { Emit "SKIP`t$($script:wfname)`t$($script:curJob)`tinterpolation`trun: contains `${{ }} expression"; $script:skipped++; Reset-Step; return }
  if ($script:sIf -ne '') { Emit "SKIP`t$($script:wfname)`t$($script:curJob)`tstep-if`tstep-level if: ($($script:sIf))"; $script:skipped++; Reset-Step; return }
  $enc = Encode-Cmd $script:sRun
  Emit "STEP`t$($script:wfname)`t$($script:curJob)`t$($script:sCoe)`t$($script:sWdir)`t$enc"
  Emit "CHECK`t$label"
  $script:mirrored++
  Reset-Step
}
function Finalize-Job {
  if ($script:curJob -eq '') { return }
  if ($script:jobUses -ne '' -and -not $script:jobEmitted) {
    Emit "SKIP`t$($script:wfname)`t$($script:curJob)`tuses-reusable-workflow`t$($script:jobUses)"; $script:skipped++
  }
  Reset-Job
}

$anyGating = $false
foreach ($wf in $wfiles) {
  $base = $wf.Name
  if ($OnlyWorkflow -ne '' -and $base -ne $OnlyWorkflow) { continue }
  if (-not (Test-PrGating $wf.FullName)) {
    Emit "SKIP`t$base`t-`tnot-pr-gating`tworkflow not triggered on pull_request or push to integration branch"
    continue
  }
  $anyGating = $true
  $before = $script:mirrored
  Get-WorkflowSteps $wf.FullName
  if ($script:mirrored -eq $before) {
    Emit "WARN`tPR-gating workflow '$base' produced ZERO runnable steps (real checks may live behind a uses: reusable/composite workflow) — this is NOT a clean pass"
  }
}

if ($OnlyWorkflow -ne '' -and -not $anyGating) {
  Emit "WARN`tciWorkflow '$OnlyWorkflow' matched no PR-gating workflow in $wfdir"
}
if (-not $anyGating -and $OnlyWorkflow -eq '') {
  Emit "WARN`tno PR-gating workflow found in $wfdir (none triggered on pull_request or push to integration branch) — nothing to mirror"
}

Flush
exit 0
