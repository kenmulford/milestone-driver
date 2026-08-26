#!/usr/bin/env pwsh
# milestone-driver - runner for the force-subagent.ps1 hook (issue #571).
# The pwsh twin of tests/force-subagent.test.sh: same four cases, same
# workspace recipe, same expected exit codes. The hook takes no arguments and
# emits no stdout record, so there is no case table to drive - every assertion
# is bespoke, against a fresh temp workspace, exactly like
# tests/tests-green.test.ps1, the sibling hook runner this file is modelled on.
#
# Twin parity is asserted on BEHAVIOR (exit codes for the same payloads), never
# on the two hooks' source bytes: the .sh and .ps1 twins legitimately differ in
# source through quote escaping (milestone-feeder #207). The bash leg carries
# the bash-3.2 venue that motivated the pair; this leg carries the pwsh venue,
# where the same four payloads must produce the same four exit codes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Hook = Join-Path $Root 'hooks' 'force-subagent.ps1'
if (-not (Test-Path -LiteralPath $Hook)) { Write-Error "FATAL: missing $Hook"; exit 3 }
$Hook = (Resolve-Path $Hook).Path
$pwshBin = (Get-Command pwsh).Source
# The escape hatch is inherited by the child and would allow EVERY case
# vacuously, turning a broken gate green. Clear it for this runner's children.
$env:CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT = $null

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

# New-Workspace - the driver.json is the whole ingredient list: an absent
# profile (or absent sourceGlobs) exits 0, so that file is what makes the gate
# live at all. No git repo is needed - this hook never shells out to git.
# 'docs/**' sits in sourceGlobs on purpose: it makes the docs/ case assert that
# the always-exempt list wins over a matching glob, instead of passing because
# nothing matched.
function New-Workspace {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $w | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $w '.milestone-config') | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $w 'skills' 'foo') | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $w 'docs') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $w '.milestone-config' 'driver.json'),
    '{"sourceGlobs":["skills/**","docs/**"]}' + "`n", $utf8)
  return $w
}

# Invoke-Hook - feed the hook the PreToolUse payload a Write/Edit carries and
# capture its exit code. An $agentId models the dispatched implementer: the
# hook's subagent-context allow reads agent_id / agent_type / parent_session_id
# off the payload, not the environment. Both streams are read asynchronously
# BEFORE WaitForExit so a full pipe buffer cannot deadlock the child (same
# idiom as tests/tests-green.test.ps1 (function Invoke-Hook)).
function Invoke-Hook([string]$root, [string]$filePath, [string]$agentId) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $pwshBin
  foreach ($a in @('-NoProfile', '-File', $Hook)) { [void]$psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $Tmp
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardInputEncoding = $utf8
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $obj = @{ tool_input = @{ file_path = $filePath }; cwd = $root }
  if ($agentId) { $obj['agent_id'] = $agentId }
  $payload = $obj | ConvertTo-Json -Compress
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($payload)
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{
    out = $outTask.GetAwaiter().GetResult()
    err = $errTask.GetAwaiter().GetResult()
    rc  = $p.ExitCode
  }
}

$W = New-Workspace
# The hook normalizes '\' to '/' before matching, so the payload carries the
# path in the shape the tool would hand it on this platform.
$src  = Join-Path $W 'skills' 'foo' 'bar.md'
$doc  = Join-Path $W 'docs' 'smoke.md'
$free = Join-Path $W 'README.md'

# ---- deny: a '**' sourceGlob blocks a nested main-thread source edit --------
# skills/foo/bar.md sits two segments deep, so this asserts the flattened '*'
# still crosses '/' - the whole point of the '**' -> '*' rewrite.
$r = Invoke-Hook $W $src ''
if ($r.rc -eq 2 -and $r.err -match 'are blocked') { Ok }
else { No "deny-doublestar: rc=$($r.rc) (want 2) err=[$(Show-Escaped $r.err)]" }

# ---- allow: a path no sourceGlob matches ------------------------------------
# The non-vacuity control for the case above: a hook that denied everything
# would pass that one and fail this one.
$r = Invoke-Hook $W $free ''
if ($r.rc -eq 0) { Ok }
else { No "allow-unmatched: rc=$($r.rc) (want 0) err=[$(Show-Escaped $r.err)]" }

# ---- allow: docs/ is always exempt, ahead of the globs ----------------------
# docs/** IS a sourceGlob in this workspace, so an rc=0 here can only come from
# the always-exempt list running first.
$r = Invoke-Hook $W $doc ''
if ($r.rc -eq 0) { Ok }
else { No "allow-docs: rc=$($r.rc) (want 0) err=[$(Show-Escaped $r.err)]" }

# ---- allow: subagent context on the SAME path the deny case blocked ---------
$r = Invoke-Hook $W $src 'agent-571'
if ($r.rc -eq 0) { Ok }
else { No "allow-subagent-context: rc=$($r.rc) (want 0) err=[$(Show-Escaped $r.err)]" }

Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
Write-Host "force-subagent.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
