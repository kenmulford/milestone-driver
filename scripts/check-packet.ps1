#!/usr/bin/env pwsh
# milestone-driver - mechanical build-packet approval (issue #722).
# Usage: check-packet.ps1 <packet> <worktree> [light]
# Checks the packet skills/solve-issue/build-packet.md defines, reading only the
# lines outside fenced blocks: a packet is mostly byte-exact quotes, and a quoted
# markdown file carries `## ` and `### x (y)` lines that are not the packet's own.
# A line starting with three backticks toggles the fence.
#   size      the packet file is at or under the byte cap at
#             skills/solve-issue/build-packet.md#Omission
#   header    the Issue:, Base: and Worktree: lines are present
#   base      Base: equals `git -C <worktree> rev-parse HEAD`
#   worktree  Worktree: equals <worktree>, one trailing '/' stripped from each
#   section   the required subset at skills/solve-issue/build-packet.md#Omission
#             is present (`## Tests` optional under `light`); a `## ` heading
#             outside the ten sections at skills/solve-issue/build-packet.md#Sections
#             fails too, as does the same `## ` heading appearing twice
#   citation  each `### <path> (<anchor>)` line, <path> holding no space,
#             resolves through resolve-citation.ps1 against <worktree>/<path>;
#             the anchor `new` marks a file absent at Base and is skipped
# Output: one FAIL<TAB><check><TAB><detail> line per failure, in the order above,
# then SUMMARY<TAB>ok=<n><TAB>failed=<m>. Output bytes match the .sh twin.
# Line model as resolve-citation.ps1: the file is read -Raw and split on LF only,
# one trailing CR is stripped, a line-1 BOM is stripped.
# Exit codes: 0 failed=0 · 1 any failure · 2 bad usage, an unreadable packet, or
# a worktree that is not a directory.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# LF, not Environment.NewLine, so stderr matches the bash twin on Windows.
function Err([string]$msg) { [Console]::Error.Write($msg + "`n") }
$usage = 'usage: check-packet.ps1 <packet> <worktree> [light]'

if ($args.Count -lt 2 -or $args.Count -gt 3) { Err $usage; exit 2 }
$packet = [string]$args[0]
$wt = [string]$args[1]
if ($wt.EndsWith('/')) { $wt = $wt.Substring(0, $wt.Length - 1) }
$light = $false
if ($args.Count -eq 3) {
  if ([string]$args[2] -cne 'light') { Err $usage; exit 2 }
  $light = $true
}
if (-not (Test-Path -LiteralPath $packet -PathType Leaf)) { Err "check-packet: packet not found or not readable: $packet"; exit 2 }
try { $raw = Get-Content -LiteralPath $packet -Raw -ErrorAction Stop }
catch { Err "check-packet: packet not found or not readable: $packet"; exit 2 }
if (-not (Test-Path -LiteralPath $wt -PathType Container)) { Err "check-packet: worktree is not a directory: $wt"; exit 2 }

if ($null -eq $raw) { $raw = '' }
if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
$lines = [System.Collections.Generic.List[string]]::new($raw.Split([char]10))
if ($raw.Length -eq 0) { $lines.Clear() }
elseif ($raw.EndsWith("`n")) { $lines.RemoveAt($lines.Count - 1) }

$ok = 0
$fails = [System.Collections.Generic.List[string]]::new()
function Pass { $script:ok++ }
function Fail([string]$check, [string]$detail) { $script:fails.Add("FAIL`t$check`t$detail") }

# [System.IO.File]::ReadAllBytes(...).Length, never $raw.Length: .NET strings are
# UTF-16, so a byte cap measured against the string length would drift from the
# bytes-on-disk count the .sh twin's `wc -c` reports (mirrors
# scripts/check-size-budgets.ps1's own byte-count convention).
$sizeBytes = [System.IO.File]::ReadAllBytes($packet).Length
if ($sizeBytes -le 12288) { Pass } else { Fail 'size' "$sizeBytes > 12288" }

$issue = $false; $base = $null; $tree = $null
$sections = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$headingOrder = [System.Collections.Generic.List[string]]::new()
$seenHeadings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$dupHeadings = [System.Collections.Generic.List[string]]::new()
$cites = [System.Collections.Generic.List[string[]]]::new()
$fence = $false
foreach ($line in $lines) {
  if ($line.EndsWith("`r")) { $line = $line.Substring(0, $line.Length - 1) }
  if ($line.StartsWith('```', [System.StringComparison]::Ordinal)) { $fence = -not $fence; continue }
  if ($fence) { continue }
  if ($line.StartsWith('Issue: ', [System.StringComparison]::Ordinal)) { $issue = $true }
  elseif ($line.StartsWith('Base: ', [System.StringComparison]::Ordinal)) { if ($null -eq $base) { $base = $line.Substring(6) } }
  elseif ($line.StartsWith('Worktree: ', [System.StringComparison]::Ordinal)) { if ($null -eq $tree) { $tree = $line.Substring(10) } }
  elseif ($line.StartsWith('## ', [System.StringComparison]::Ordinal)) {
    $h = $line.Substring(3)
    if (-not $seenHeadings.Add($h)) { $dupHeadings.Add($h) }
    [void]$sections.Add($h); $headingOrder.Add($h)
  }
  elseif ($line.StartsWith('### ', [System.StringComparison]::Ordinal) -and $line.EndsWith(')', [System.StringComparison]::Ordinal)) {
    $rest = $line.Substring(4)
    $sp = $rest.IndexOf(' ')
    if ($sp -lt 1) { continue }
    $path = $rest.Substring(0, $sp)
    $tail = $rest.Substring($sp)
    if (-not $tail.StartsWith(' (', [System.StringComparison]::Ordinal) -or $tail.Length -lt 4) { continue }
    $cites.Add(@($path, $tail.Substring(2, $tail.Length - 3)))
  }
}

foreach ($h in @(@('Issue', $issue), @('Base', ($null -ne $base)), @('Worktree', ($null -ne $tree)))) {
  if ($h[1]) { Pass } else { Fail 'header' "missing $($h[0]): line" }
}

if ($null -ne $base) {
  $headSha = 'unknown'
  try {
    $o = & git -C $wt rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $o) { $headSha = ([string]($o | Select-Object -First 1)).Trim() }
  } catch { $headSha = 'unknown' }
  if ($base -ceq $headSha) { Pass } else { Fail 'base' "Base: $base != HEAD $headSha" }
}
if ($null -ne $tree) {
  $t = if ($tree.EndsWith('/')) { $tree.Substring(0, $tree.Length - 1) } else { $tree }
  if ($t -ceq $wt) { Pass } else { Fail 'worktree' "Worktree: $tree != $wt" }
}

$requiredSections = @('Files', 'Edit points', 'Tests', 'Verify', 'Out of scope')
$contractSections = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]@('Files', 'Edit points', 'Calls', 'Tests', 'Design', 'Rules', 'Verified facts', 'Decisions', 'Verify', 'Out of scope'),
  [System.StringComparer]::Ordinal)

foreach ($s in $requiredSections) {
  if ($s -ceq 'Tests' -and $light) { continue }
  if ($sections.Contains($s)) { Pass } else { Fail 'section' "missing ## $s" }
}

foreach ($h in $headingOrder) {
  if ($requiredSections -ccontains $h) { continue }
  if ($contractSections.Contains($h)) { Pass } else { Fail 'section' "unexpected ## $h" }
}

foreach ($h in $dupHeadings) { Fail 'section' "duplicate ## $h" }

# resolve-citation.ps1 writes through [Console]::Out and [Console]::Error, not the
# pipeline, so both are captured by swapping the console writers around the call.
$resolver = Join-Path $PSScriptRoot 'resolve-citation.ps1'
foreach ($c in $cites) {
  if ($c[1] -ceq 'new') { continue }
  $oldOut = [Console]::Out; $oldErr = [Console]::Error
  $so = [System.IO.StringWriter]::new(); $se = [System.IO.StringWriter]::new()
  $global:LASTEXITCODE = 0
  try {
    [Console]::SetOut($so); [Console]::SetError($se)
    $null = & $resolver "$wt/$($c[0])" $c[1]
    $rc = $LASTEXITCODE
  } catch { $rc = 1 }
  finally { [Console]::SetOut($oldOut); [Console]::SetError($oldErr) }
  if ($rc -eq 0) { Pass } else { Fail 'citation' "$($c[0]) ($($c[1])): $($se.ToString().TrimEnd("`n"))" }
}

$outText = ''
foreach ($f in $fails) { $outText += "$f`n" }
$outText += "SUMMARY`tok=$ok`tfailed=$($fails.Count)`n"
[Console]::Out.Write($outText)
if ($fails.Count -eq 0) { exit 0 } else { exit 1 }
