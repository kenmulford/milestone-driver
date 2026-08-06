#!/usr/bin/env pwsh
# milestone-driver — repo-wide citation gate (issue #432).
#
# Twin of check-citations.sh: SAME walk, SAME discriminator, SAME resolution
# model, BYTE-IDENTICAL stdout and stderr. See that file's header for the full
# contract — what a green run does and does not verify, the four discriminator
# rules and the measurements behind them, the six edge cases and the choice made
# for each, and why docs/superpowers/**, docs/briefs/**, CHANGELOG.md and
# tests/fixtures/** are excluded from the walk. This header records only what is
# specific to THIS leg.
#
# Usage:   check-citations.ps1 [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# A GREEN RUN VERIFIES ONLY `path (anchor)` CITATIONS. `path:line`,
# `path:start-end`, `path#Heading` and `path § Heading` are counted and reported
# as UNVERIFIED records, never resolved — `failed=0` means "every anchor still
# points at its string", NOT "every citation in this repo is good".
#
# TWIN-PARITY NOTES — where this leg had to be written differently to produce
# the same bytes:
#   - CHARS vs BYTES. The bash leg runs under LC_ALL=C and indexes BYTES; .NET
#     strings are UTF-16 and index CHARS. Every class test here is an explicit
#     ASCII range, and no UTF-8 continuation byte is ever `(`, `)`, `#` or a
#     path-class byte, so a multibyte line yields the same runs, the same paren
#     balance and the same extracted text on both legs. Only the internal
#     offsets differ, and no offset is ever emitted.
#   - THE WALK. `find` is replaced by a hand-rolled recursive enumeration that
#     prunes `.git` and SKIPS REPARSE POINTS, because `find -type f` (no -L)
#     lists neither a symlink nor anything under one. Paths are then sorted with
#     StringComparer.Ordinal to match the bash leg's `LC_ALL=C sort`. The two
#     orders can only diverge on a path holding an astral character, where
#     UTF-8 byte order and UTF-16 code-unit order disagree; no such path exists
#     in this repo.
#   - THE MATCH COUNT. The bash leg counts matching lines with `grep -a -c -F`.
#     This leg hand-rolls it: read raw, split on LF ONLY, count the lines
#     containing the anchor ORDINALLY. Ordinal is load-bearing — PowerShell's
#     default string comparison is culture-sensitive and case-insensitive, which
#     would count matches `grep` does not. Same call as
#     scripts/resolve-citation.ps1 (Ordinal comparison keeps this).
#   - LINE ENDINGS. Records are joined with LF and written through
#     [Console]::Out.Write, never Write-Output, so a Windows host cannot turn
#     the stream into CRLF and diverge from the bash leg.
#
# Dependency-free: PowerShell 7+ built-ins only — no jq, no yq, no python, no
# YAML or markdown parser
# (.project/library-manifest.md#Adding a dependency (the gate)).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# LF, not Environment.NewLine — see the twin-parity note on line endings.
function Err([string]$msg) { [Console]::Error.Write($msg + "`n") }

$Root = if ($args.Count -ge 1) { [string]$args[0] } else { (Get-Location).Path }
if ($Root.EndsWith('/')) { $Root = $Root.Substring(0, $Root.Length - 1) }
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
  Err "ERROR check-citations: not a directory: $Root"
  exit 1
}
$RootFull = (Resolve-Path -LiteralPath $Root).Path
if ($RootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
  $RootFull = $RootFull.Substring(0, $RootFull.Length - 1)
}

# Walk exclusions, in report order. A trailing '/' means "this prefix"; anything
# else is an exact repo-relative path.
$Ex1 = 'docs/superpowers/'; $ExN1 = 0
$Ex2 = 'docs/briefs/';      $ExN2 = 0
$Ex3 = 'CHANGELOG.md';      $ExN3 = 0
$Ex4 = 'tests/fixtures/';   $ExN4 = 0

$ok = 0
$failed = 0
$unverified = 0
$out = [System.Collections.Generic.List[string]]::new()

# The path-class run, as the maximal-munch regex equivalent of the bash leg's
# `${rest%%[!A-Za-z0-9._/-]*}` peel. Compiled once; explicit ASCII ranges, so it
# never widens to Unicode letters the way \w would.
$RunRx = [regex]::new('[A-Za-z0-9._/-]+', [System.Text.RegularExpressions.RegexOptions]::Compiled)

# Test-CitablePath — discriminator rules 2 and 3 (see the .sh header).
function Test-CitablePath([string]$p) {
  if ($p.IndexOf('/') -lt 0) { return $false }
  if ($p.StartsWith('/')) { return $false }
  $b = $p.Substring($p.LastIndexOf('/') + 1)
  $dot = $b.LastIndexOf('.')
  if ($dot -lt 0) { return $false }
  $e = $b.Substring($dot + 1)
  if ($e.Length -lt 1 -or $e.Length -gt 4) { return $false }
  $hasLetter = $false
  foreach ($c in $e.ToCharArray()) {
    if (($c -ge 'a' -and $c -le 'z') -or ($c -ge 'A' -and $c -le 'Z')) { $hasLetter = $true }
    elseif ($c -ge '0' -and $c -le '9') { }
    else { return $false }
  }
  return $hasLetter
}

# Get-BalancedEnd — index of the ')' closing a paren opened just before $t, or
# -1 when the parens never balance on this line.
function Get-BalancedEnd([string]$t) {
  $d = 1
  for ($i = 0; $i -lt $t.Length; $i++) {
    $c = $t[$i]
    if ($c -eq '(') { $d++ }
    elseif ($c -eq ')') { $d--; if ($d -eq 0) { return $i } }
  }
  return -1
}

# Get-HeadingEnd — where a heading citation's text stops: the first backtick,
# comma, semicolon, double quote, or UNMATCHED ')', else end of line.
function Get-HeadingEnd([string]$t) {
  $d = 0
  for ($i = 0; $i -lt $t.Length; $i++) {
    $c = $t[$i]
    if ($c -eq '(') { $d++ }
    elseif ($c -eq ')') { if ($d -eq 0) { return $i }; $d-- }
    elseif ($c -eq '`' -or $c -eq ',' -or $c -eq ';' -or $c -eq '"') { return $i }
  }
  return $t.Length
}

# Read-Lines — the bash leg's `while IFS= read -r line` model: split on LF ONLY
# (a lone CR is ordinary text), strip ONE trailing CR per line, and treat a
# trailing LF as a terminator rather than the start of an empty line. Mirrors
# scripts/resolve-citation.ps1 (LINE MODEL).
function Read-Lines([string]$path) {
  try { $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop } catch { return $null }
  if ($null -eq $raw) { $raw = '' }
  if ($raw.Length -eq 0) { return @() }
  $lines = [System.Collections.Generic.List[string]]::new($raw.Split([char]10))
  if ($raw.EndsWith("`n")) { $lines.RemoveAt($lines.Count - 1) }
  return $lines
}

# Get-MatchCount — matching LINE count, resolve-citation's model. Split on LF
# only; a trailing CR and a line-1 BOM can change a PREFIX-ANCHORED match but
# never a SUBSTRING one, so this returns what `grep -a -c -F` returns.
function Get-MatchCount([string]$path, [string]$anchor) {
  try { $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop } catch { return 0 }
  if ($null -eq $raw -or $raw.Length -eq 0) { return 0 }
  $n = 0
  foreach ($l in $raw.Split([char]10)) {
    if ($l.Contains($anchor, [System.StringComparison]::Ordinal)) { $n++ }
  }
  return $n
}

# Get-TreeFiles — `find <root> -name .git -prune -o -type f -print`, expressed
# in .NET. A reparse point is skipped whether it points at a file or a
# directory, because `find -type f` without -L lists neither.
function Get-TreeFiles([string]$dir, [string]$prefix, $acc) {
  foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($dir)) {
    $name = [System.IO.Path]::GetFileName($entry)
    if ($name -eq '.git') { continue }
    $rel = if ($prefix -eq '') { $name } else { "$prefix/$name" }
    try { $attrs = [System.IO.File]::GetAttributes($entry) } catch { continue }
    if ($attrs -band [System.IO.FileAttributes]::ReparsePoint) { continue }
    if ($attrs -band [System.IO.FileAttributes]::Directory) {
      Get-TreeFiles $entry $rel $acc
    } else {
      $acc.Add($rel)
    }
  }
}

$all = [System.Collections.Generic.List[string]]::new()
Get-TreeFiles $RootFull '' $all
$sorted = $all.ToArray()
[array]::Sort($sorted, [System.StringComparer]::Ordinal)

$kept = [System.Collections.Generic.List[string]]::new()
foreach ($rel in $sorted) {
  if ($rel.StartsWith($Ex1, [System.StringComparison]::Ordinal)) { $ExN1++; continue }
  if ($rel.StartsWith($Ex2, [System.StringComparison]::Ordinal)) { $ExN2++; continue }
  if ($rel -ceq $Ex3) { $ExN3++; continue }
  if ($rel.StartsWith($Ex4, [System.StringComparison]::Ordinal)) { $ExN4++; continue }
  $kept.Add($rel)
}

$out.Add("EXCLUDED`t$Ex1`tskipped=$ExN1")
$out.Add("EXCLUDED`t$Ex2`tskipped=$ExN2")
$out.Add("EXCLUDED`t$Ex3`tskipped=$ExN3")
$out.Add("EXCLUDED`t$Ex4`tskipped=$ExN4")

# ---------------------------------------------------------------------------
# Scan. One pass per line, left to right: take the next path-class run, test it
# as a path, then classify on the characters that FOLLOW it. `$consumedTo` is
# this leg's spelling of the bash loop's shrinking `$rest`: a run that starts
# inside an already-consumed citation is skipped, so an anchor's own inner
# tokens are never re-read as citations.
# ---------------------------------------------------------------------------
foreach ($rel in $kept) {
  $src = Join-Path $RootFull $rel
  $lines = Read-Lines $src
  if ($null -eq $lines) { continue }
  $lno = 0
  foreach ($rawLine in $lines) {
    $lno++
    $line = if ($rawLine.EndsWith("`r")) { $rawLine.Substring(0, $rawLine.Length - 1) } else { $rawLine }
    $consumedTo = 0
    foreach ($m in $RunRx.Matches($line)) {
      if ($m.Index -lt $consumedTo) { continue }
      $run = $m.Value
      if (-not (Test-CitablePath $run)) { continue }
      $after = $m.Index + $m.Length
      $rest = $line.Substring($after)
      if ($rest.StartsWith(' (', [System.StringComparison]::Ordinal)) {
        $body = $rest.Substring(2)
        $end = Get-BalancedEnd $body
        if ($end -le 0) { continue }
        $anchor = $body.Substring(0, $end)
        $consumedTo = $after + 2 + $end + 1
        $tgt = Join-Path $RootFull $run
        $n = if (Test-Path -LiteralPath $tgt -PathType Leaf) { Get-MatchCount $tgt $anchor } else { 0 }
        if ($n -eq 1) {
          $out.Add("OK`t${rel}:${lno}`t$run ($anchor)")
          $ok++
        } else {
          $out.Add("FAIL`t${rel}:${lno}`t$run ($anchor)`t$n matches")
          $failed++
        }
      }
      elseif ($rest.StartsWith('#', [System.StringComparison]::Ordinal)) {
        $h = $rest.Substring(1)
        $end = Get-HeadingEnd $h
        $head = $h.Substring(0, $end).TrimEnd(' ', "`t")
        $consumedTo = $after + 1 + $end
        $out.Add("UNVERIFIED`t${rel}:${lno}`t$run#$head`tpath#Heading — not verified")
        $unverified++
      }
      elseif ($rest.StartsWith(' § ', [System.StringComparison]::Ordinal)) {
        $h = $rest.Substring(3)
        $end = Get-HeadingEnd $h
        $head = $h.Substring(0, $end).TrimEnd(' ', "`t")
        $consumedTo = $after + 3 + $end
        $out.Add("UNVERIFIED`t${rel}:${lno}`t$run § $head`tpath § Heading — not verified")
        $unverified++
      }
      elseif ($rest.Length -ge 2 -and $rest[0] -eq ':' -and $rest[1] -ge '0' -and $rest[1] -le '9') {
        $j = 1
        while ($j -lt $rest.Length -and $rest[$j] -ge '0' -and $rest[$j] -le '9') { $j++ }
        $cite = $run + ':' + $rest.Substring(1, $j - 1)
        if (($j + 1) -lt $rest.Length -and $rest[$j] -eq '-' -and $rest[$j + 1] -ge '0' -and $rest[$j + 1] -le '9') {
          $k = $j + 1
          while ($k -lt $rest.Length -and $rest[$k] -ge '0' -and $rest[$k] -le '9') { $k++ }
          $cite = $cite + '-' + $rest.Substring($j + 1, $k - $j - 1)
          $j = $k
        }
        $consumedTo = $after + $j
        $out.Add("UNVERIFIED`t${rel}:${lno}`t$cite`tpath:line — not verified")
        $unverified++
      }
    }
  }
}

$out.Add("TOTALS`tunverified=$unverified`texcluded-files=$($ExN1 + $ExN2 + $ExN3 + $ExN4)")
$out.Add("SUMMARY`tok=$ok`tfailed=$failed")

# Join with LF and append a single trailing newline — byte-parity with the .sh
# leg's printf stream, independent of the host's default line ending.
[Console]::Out.Write(($out -join "`n") + "`n")
if ($failed -ne 0) { exit 1 }
