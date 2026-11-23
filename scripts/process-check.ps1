#!/usr/bin/env pwsh
# milestone-driver - process-check status and record (issue #791).
# Usage: process-check.ps1 --status <repo-root>
#        process-check.ps1 --record <clean|declined> <repo-root>
# Every rule, the digest, and the marker format mirror the .sh twin, which states
# them. Stdout, stderr, exit codes and marker bytes match it: UTF-8 without BOM,
# LF line endings, written through [Console]::Out / [Console]::Error and
# [IO.File], never the pipeline.
# A marker or profile is parsed by JsonDocument first (MaxDepth 10000, jq's limit):
# RFC 8259 whitespace only, one value, an object root. A leading U+00A0, trailing
# content or a top-level array is rejected as jq's length == 1 check does, where
# ConvertFrom-Json alone would skip the U+00A0.
# JSON keys are matched case-sensitively, as jq does, so the members are read
# from JsonDocument by exact name; paths differing only by case stay distinct.
# Sorting uses the byte-order idiom of scripts/check-citations.ps1 (function
# ToByteChars): Latin1 over UTF-8 bytes compared with StringComparer.Ordinal
# equals the bash leg's LC_ALL=C order.
# The manifest is written as raw bytes to a temp file and hashed by path, since
# piping a string would re-encode it and append a newline; `git hash-object
# --no-filters -- <file>` gives `--stdin`'s id. One call hashes the contract and
# every scanned file. The profile joins only as `key <name> <raw string value>` lines
# for its contract keys, which the .sh twin lists: the auditor judges keyed rows against them,
# then `declined <blob>` when process-check-declined.json under <main-repo-root> is a readable file.
# The marker sits under <main-repo-root>: `git -C <repo-root> rev-parse --show-toplevel` when
# `--git-dir` and `--git-common-dir` agree, else the first `worktree ` entry of `git -C
# <repo-root> worktree list --porcelain`, as the .sh twin states; a failing rev-parse,
# rev-parse output of other than two lines, or no entry uses <repo-root>. Scanned files and the profile are read from <repo-root>.
# Exit codes: 0 ok · 1 unreadable profile or contract / write failure · 2 bad usage.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$L1 = [System.Text.Encoding]::Latin1
$U8 = [System.Text.UTF8Encoding]::new($false)
function ToByteChars([string]$s) { return $L1.GetString($U8.GetBytes($s)) }

function Die([int]$rc, [string]$msg) { [Console]::Error.Write("process-check: $msg`n"); exit $rc }
function Usage { Die 2 'usage: process-check (--status | --record <clean|declined>) <repo-root>' }

$outcome = ''
$mode = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
if ($mode -ceq '--status') {
  if ($args.Count -ne 2) { Usage }
  $root = [string]$args[1]
} elseif ($mode -ceq '--record') {
  if ($args.Count -ne 3) { Usage }
  $outcome = [string]$args[1]; $root = [string]$args[2]
  if ($outcome -cnotin @('clean', 'declined')) { Usage }
} else { Usage }
if ([string]::IsNullOrEmpty($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) { Usage }
# .NET and git resolve a relative path against the process cwd, which
# Set-Location does not move; resolve against the PowerShell location instead.
$root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($root)

$plugin = Split-Path -Parent $PSScriptRoot
$profilePath = "$root/.milestone-config/driver.json"; $profileName = '.milestone-config/driver.json'
if (-not (Test-Path -LiteralPath $profilePath) -and (Test-Path -LiteralPath "$root/milestone-driver.json")) {
  $profilePath = "$root/milestone-driver.json"; $profileName = 'milestone-driver.json'
}

$jsonOpts = [System.Text.Json.JsonDocumentOptions]::new()
$jsonOpts.MaxDepth = 10000
# Returns the named root members, looked up by exact case (ConvertFrom-Json throws on keys that differ only
# by case, which jq accepts): a string as [string], an array as the object[] of its string elements.
function Read-JsonObject([string]$path, [string[]]$names) {
  $text = [System.IO.File]::ReadAllText($path, $U8)
  $doc = [System.Text.Json.JsonDocument]::Parse($text, $jsonOpts)
  try {
    if ($doc.RootElement.ValueKind -ne 'Object') { throw 'not one JSON object' }
    $out = @{}
    foreach ($n in $names) {
      $v = [System.Text.Json.JsonElement]::new()
      if (-not $doc.RootElement.TryGetProperty($n, [ref]$v)) { continue }
      if ($v.ValueKind -eq 'String') { $out[$n] = $v.GetString() }
      elseif ($v.ValueKind -eq 'Array') {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($e in $v.EnumerateArray()) { if ($e.ValueKind -eq 'String') { $items.Add($e.GetString()) } }
        $out[$n] = $items.ToArray()
      }
    }
    return $out
  } finally { $doc.Dispose() }
}

# A value holding any code point below U+0020 is omitted, as the .sh twin's jq `explode | any(. < 32)` does.
$ctl = '[\x00-\x1f]'
$pd = ''; $docs = @(); $prof = @{}
$contractKeys = @('integrationGranularity', 'implementerAgent', 'unitTestCmd', 'e2eTestCmd', 'preflightCmd', 'coherenceReviewAgent')
if (Test-Path -LiteralPath $profilePath) {
  try {
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) { throw 'not a file' }
    $prof = Read-JsonObject $profilePath (@('projectDocs', 'standingDocs') + $contractKeys)
  } catch { Die 1 "cannot read $profileName" }
  if ($prof['projectDocs'] -is [string] -and $prof['projectDocs'] -cnotmatch $ctl) { $pd = $prof['projectDocs'] }
  if ($prof['standingDocs'] -is [object[]]) { foreach ($e in $prof['standingDocs']) { if ($e -cnotmatch $ctl) { $docs += $e.Split('#')[0] } } }
}
while ($pd.StartsWith('./', [StringComparison]::Ordinal)) { $pd = $pd.Substring(2) }
while ($pd.EndsWith('/', [StringComparison]::Ordinal)) { $pd = $pd.Substring(0, $pd.Length - 1) }
if ($pd -eq '') { $pd = '.project' }

function Get-Blobs([string[]]$paths) {
  try { $o = & git hash-object --no-filters -- @paths 2>$null } catch { return $null }
  if ($LASTEXITCODE -ne 0 -or -not $o) { return $null }
  return , @($o | ForEach-Object { ([string]$_).Trim() })
}
function Test-Readable([string]$path) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
  try { [System.IO.File]::OpenRead($path).Dispose(); return $true } catch { return $false }
}

$contract = "$plugin/skills/process-check.md"
if (-not (Test-Readable $contract)) { Die 1 'cannot read skills/process-check.md' }

$cands = [System.Collections.Generic.List[string]]::new()
foreach ($r in @('CLAUDE.md', 'AGENTS.md', '.claude/CLAUDE.md')) { $cands.Add($r) }
foreach ($d in $(if ($pd -ceq '.project') { @('.project') } else { @('.project', $pd) })) {
  if (-not (Test-Path -LiteralPath "$root/$d" -PathType Container)) { continue }
  try { $files = [System.IO.Directory]::GetFiles("$root/$d") } catch { continue }
  foreach ($f in $files) {
    $n = [System.IO.Path]::GetFileName($f)
    if ($n -cmatch $ctl) { continue }
    if ($n.EndsWith('.md', [StringComparison]::Ordinal) -and -not $n.StartsWith('.', [StringComparison]::Ordinal)) { $cands.Add("$d/$n") }
  }
}
foreach ($doc in $docs) {
  while ($doc.StartsWith('./', [StringComparison]::Ordinal)) { $doc = $doc.Substring(2) }
  if ($doc -ne '') { $cands.Add("$pd/$doc") }
}

$byKey = [hashtable]::new([StringComparer]::Ordinal)
foreach ($rel in $cands) { $byKey[(ToByteChars $rel)] = $rel }
$keys = [string[]]@($byKey.Keys)
[Array]::Sort($keys, [StringComparer]::Ordinal)

$rels = @($keys | ForEach-Object { $byKey[$_] } | Where-Object { Test-Readable "$root/$_" })
$blobs = Get-Blobs (@($contract) + @($rels | ForEach-Object { "$root/$_" }))
if (-not $blobs -or $blobs.Count -ne $rels.Count + 1) { Die 1 'cannot hash the contract or a scanned file' }

$main = $root
try { $gits = @(& git -C $root rev-parse --path-format=absolute --git-dir --git-common-dir 2>$null) } catch { $gits = @() }
if ($LASTEXITCODE -eq 0 -and $gits.Count -eq 2) {
  $gd = (([string]$gits[0]) -replace '\\', '/').TrimEnd("`r", "`n"); $cd = (([string]$gits[1]) -replace '\\', '/').TrimEnd("`r", "`n")
  if ($gd -ceq $cd) {
    try { $top = & git -C $root rev-parse --show-toplevel 2>$null } catch { $top = $null }
    if ($LASTEXITCODE -eq 0 -and $top) { $main = (([string]$top) -replace '\\', '/').TrimEnd("`r", "`n") }
  } else {
    try { $wtl = @(& git -C $root worktree list --porcelain 2>$null) } catch { $wtl = @() }
    $first = if ($LASTEXITCODE -eq 0) { $wtl | Where-Object { ([string]$_).StartsWith('worktree ', [StringComparison]::Ordinal) } | Select-Object -First 1 } else { $null }
    if ($first) {
      $wt = (([string]$first).Substring(9) -replace '\\', '/').TrimEnd("`r", "`n")
      if ($wt.Length -gt 0) { $main = $wt }
    }
  }
}
if (-not $main) { $main = $root }
$rt = "$main/.milestone-config/.runtime"
$marker = "$rt/process-check.json"

$declinedPath = "$rt/process-check-declined.json"
$declinedBlob = $null
if (Test-Readable $declinedPath) {
  $db = Get-Blobs @($declinedPath)
  if (-not $db) { Die 1 'cannot hash the contract or a scanned file' }
  $declinedBlob = $db[0]
}

$manifest = [System.Text.StringBuilder]::new()
[void]$manifest.Append("contract $($blobs[0])`n")
foreach ($k in $contractKeys) { if ($prof[$k] -is [string] -and $prof[$k] -cnotmatch $ctl) { [void]$manifest.Append("key $k $($prof[$k])`n") } }
if ($declinedBlob) { [void]$manifest.Append("declined $declinedBlob`n") }
for ($i = 0; $i -lt $rels.Count; $i++) { [void]$manifest.Append("$($blobs[$i + 1]) $($rels[$i])`n") }

$digest = $null
$mf = $null
try {
  $mf = [System.IO.Path]::GetTempFileName()
  [System.IO.File]::WriteAllBytes($mf, $U8.GetBytes($manifest.ToString()))
  $d = Get-Blobs @($mf)
  if ($d) { $digest = $d[0] }
} catch { $digest = $null }
finally { if ($mf) { Remove-Item -LiteralPath $mf -Force -ErrorAction SilentlyContinue } }
if (-not $digest) { Die 1 'cannot hash the contract or a scanned file' }

if ($mode -ceq '--status') {
  $current = $false
  if (Test-Path -LiteralPath $marker -PathType Leaf) {
    try {
      $mh = (Read-JsonObject $marker @('hash'))['hash']
      if ($mh -is [string] -and $mh -ceq $digest) { $current = $true }
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
