#!/usr/bin/env pwsh
# milestone-driver - runner for the force-subagent.ps1 hook (issue #571).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Hook = Join-Path $Root 'hooks' 'force-subagent.ps1'
if (-not (Test-Path -LiteralPath $Hook)) { Write-Error "FATAL: missing $Hook"; exit 3 }
$Hook = (Resolve-Path $Hook).Path
$pwshBin = (Get-Command pwsh).Source
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

function New-Workspace([string]$globsJson = '["skills/**","docs/**"]') {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $w | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $w '.milestone-config') | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $w 'skills' 'foo') | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $w 'docs') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $w '.milestone-config' 'driver.json'),
    '{"sourceGlobs":' + $globsJson + '}' + "`n", $utf8)
  return $w
}

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
$src  = Join-Path $W 'skills' 'foo' 'bar.md'
$doc  = Join-Path $W 'docs' 'smoke.md'
$free = Join-Path $W 'README.md'

# ---- deny: a '**' sourceGlob blocks a nested main-thread source edit --------
$r = Invoke-Hook $W $src ''
if ($r.rc -eq 2 -and $r.err -match 'are blocked') { Ok }
else { No "deny-doublestar: rc=$($r.rc) (want 2) err=[$(Show-Escaped $r.err)]" }

# ---- allow: a path no sourceGlob matches ------------------------------------
$r = Invoke-Hook $W $free ''
if ($r.rc -eq 0) { Ok }
else { No "allow-unmatched: rc=$($r.rc) (want 0) err=[$(Show-Escaped $r.err)]" }

# ---- allow: docs/ is always exempt, ahead of the globs ----------------------
$r = Invoke-Hook $W $doc ''
if ($r.rc -eq 0) { Ok }
else { No "allow-docs: rc=$($r.rc) (want 0) err=[$(Show-Escaped $r.err)]" }

# ---- allow: subagent context on the SAME path the deny case blocked ---------
$r = Invoke-Hook $W $src 'agent-571'
if ($r.rc -eq 0) { Ok }
else { No "allow-subagent-context: rc=$($r.rc) (want 0) err=[$(Show-Escaped $r.err)]" }

# ---- deny: a globstar-prefix glob blocks a root-level path -----------------
$WG = New-Workspace '["**/*.md"]'
$r = Invoke-Hook $WG (Join-Path $WG 'x.md') ''
if ($r.rc -eq 2) { Ok }
else { No "globstar-root: rc=$($r.rc) (want 2) err=[$(Show-Escaped $r.err)]" }

Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
Write-Host "force-subagent.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
