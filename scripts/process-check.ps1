#!/usr/bin/env pwsh
# milestone-driver - process-check status and record (issue #791).
# Usage: process-check.ps1 --status <repo-root>
#        process-check.ps1 --record <clean|updated|declined> <repo-root>
# Every rule, the digest, and the marker format mirror the .sh twin, which states
# them. Stdout, stderr, exit codes and marker bytes match it: UTF-8 without BOM,
# LF line endings, written through [Console]::Out / [Console]::Error and
# [IO.File], never the pipeline.
# ConvertFrom-Json -NoEnumerate keeps a top-level array an array, so a marker or
# profile that is not one JSON object is rejected as jq's length == 1 check does.
# JSON keys are matched case-sensitively, as jq does.
# Sorting uses the byte-order idiom of scripts/check-citations.ps1 (function
# ToByteChars): Latin1 over UTF-8 bytes compared with StringComparer.Ordinal
# equals the bash leg's LC_ALL=C order.
# The manifest goes to `git hash-object --stdin` as raw bytes, since piping a
# string would re-encode it and append a newline.
# Exit codes: 0 ok · 1 unreadable profile or contract / write failure · 2 bad usage.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$L1 = [System.Text.Encoding]::Latin1
$U8 = [System.Text.UTF8Encoding]::new($false)
function ToByteChars([string]$s) { return $L1.GetString($U8.GetBytes($s)) }

function Die([int]$rc, [string]$msg) { [Console]::Error.Write("process-check: $msg`n"); exit $rc }
function Usage { Die 2 'usage: process-check (--status | --record <clean|updated|declined>) <repo-root>' }

$outcome = ''
$mode = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
if ($mode -ceq '--status') {
  if ($args.Count -ne 2) { Usage }
  $root = [string]$args[1]
} elseif ($mode -ceq '--record') {
  if ($args.Count -ne 3) { Usage }
  $outcome = [string]$args[1]; $root = [string]$args[2]
  if ($outcome -cnotin @('clean', 'updated', 'declined')) { Usage }
} else { Usage }
if ([string]::IsNullOrEmpty($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) { Usage }
# .NET and git resolve a relative path against the process cwd, which
# Set-Location does not move; resolve against the PowerShell location instead.
$root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($root)

$plugin = Split-Path -Parent $PSScriptRoot
$profilePath = "$root/.milestone-config/driver.json"

function Get-Prop($obj, [string]$name) {
  foreach ($p in $obj.PSObject.Properties) { if ($p.Name -ceq $name) { return $p } }
  return $null
}
function Read-JsonObject([string]$path) {
  $o = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($path, $U8)) -NoEnumerate -ErrorAction Stop
  if ($o -isnot [System.Management.Automation.PSCustomObject]) { throw 'not one JSON object' }
  return $o
}

$pd = ''; $docs = @()
if (Test-Path -LiteralPath $profilePath) {
  try {
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw 'not a file' }
    $prof = Read-JsonObject $profilePath
  } catch { Die 1 'cannot read .milestone-config/driver.json' }
  $p = Get-Prop $prof 'projectDocs'
  if ($p -and $p.Value -is [string]) { $pd = $p.Value }
  $p = Get-Prop $prof 'standingDocs'
  if ($p -and $p.Value -is [object[]]) {
    foreach ($e in $p.Value) { if ($e -is [string]) { $docs += $e.Split('#')[0] } }
  }
}
while ($pd.StartsWith('./', [StringComparison]::Ordinal)) { $pd = $pd.Substring(2) }
while ($pd.EndsWith('/', [StringComparison]::Ordinal)) { $pd = $pd.Substring(0, $pd.Length - 1) }
if ($pd -eq '') { $pd = '.project' }

function Get-Blob([string]$path) {
  try { $o = & git hash-object --no-filters -- $path 2>$null } catch { return $null }
  if ($LASTEXITCODE -ne 0 -or -not $o) { return $null }
  return ([string]$o).Trim()
}

$contract = "$plugin/skills/process-check.md"
$c = $null
if (Test-Path -LiteralPath $contract -PathType Leaf) { $c = Get-Blob $contract }
if (-not $c) { Die 1 'cannot read skills/process-check.md' }

$cands = [System.Collections.Generic.List[string]]::new()
foreach ($r in @('CLAUDE.md', 'AGENTS.md', '.claude/CLAUDE.md')) { $cands.Add($r) }
foreach ($d in @('.project', $pd)) {
  if (-not (Test-Path -LiteralPath "$root/$d" -PathType Container)) { continue }
  try { $files = [System.IO.Directory]::GetFiles("$root/$d") } catch { continue }
  foreach ($f in $files) {
    $n = [System.IO.Path]::GetFileName($f)
    if ($n.EndsWith('.md', [StringComparison]::Ordinal) -and -not $n.StartsWith('.', [StringComparison]::Ordinal)) { $cands.Add("$d/$n") }
  }
}
foreach ($doc in $docs) {
  while ($doc.StartsWith('./', [StringComparison]::Ordinal)) { $doc = $doc.Substring(2) }
  if ($doc -ne '') { $cands.Add("$pd/$doc") }
}

$byKey = @{}
foreach ($rel in $cands) { $byKey[(ToByteChars $rel)] = $rel }
$keys = [string[]]@($byKey.Keys)
[Array]::Sort($keys, [StringComparer]::Ordinal)

$manifest = [System.Text.StringBuilder]::new()
[void]$manifest.Append("contract $c`n")
foreach ($k in $keys) {
  $rel = $byKey[$k]
  if (-not (Test-Path -LiteralPath "$root/$rel" -PathType Leaf)) { continue }
  $h = Get-Blob "$root/$rel"
  if ($h) { [void]$manifest.Append("$h $rel`n") }
}

$digest = $null
try {
  $psi = [System.Diagnostics.ProcessStartInfo]::new('git')
  [void]$psi.ArgumentList.Add('hash-object'); [void]$psi.ArgumentList.Add('--stdin')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  $errTask = $proc.StandardError.ReadToEndAsync()
  $bytes = $U8.GetBytes($manifest.ToString())
  $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
  $proc.StandardInput.Close()
  $digest = $proc.StandardOutput.ReadToEnd().Trim()
  $proc.WaitForExit()
  if ($proc.ExitCode -ne 0) { $digest = $null }
} catch { $digest = $null }
if (-not $digest) { Die 1 'cannot read skills/process-check.md' }

$rt = "$root/.milestone-config/.runtime"
$marker = "$rt/process-check.json"

if ($mode -ceq '--status') {
  $current = $false
  if (Test-Path -LiteralPath $marker -PathType Leaf) {
    try {
      $hp = Get-Prop (Read-JsonObject $marker) 'hash'
      if ($hp -and $hp.Value -is [string] -and $hp.Value -ceq $digest) { $current = $true }
    } catch { $current = $false }
  }
  [Console]::Out.Write($(if ($current) { "current`n" } else { "due`n" }))
  exit 0
}

$tmp = "$marker.tmp.$PID"
try {
  [void][System.IO.Directory]::CreateDirectory($rt)
  if (Test-Path -LiteralPath $marker -PathType Container) { throw 'marker path is a directory' }
  [System.IO.File]::WriteAllText($tmp, "{`"hash`":`"$digest`",`"outcome`":`"$outcome`"}`n", $U8)
  [System.IO.File]::Move($tmp, $marker, $true)
} catch {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Die 1 'cannot write .milestone-config/.runtime/process-check.json'
}
exit 0
