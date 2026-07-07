#!/usr/bin/env pwsh
# milestone-driver — CI SKILL.md frontmatter YAML-validity lint (issue #314).
# Behavior-identical pwsh sibling of scripts/check-skill-frontmatter.sh — see
# its header for the full defect-class rationale and the narrow, line-oriented,
# dependency-free heuristic (no YAML library; block/quoted scalars are skipped;
# only an unquoted colon+space in a plain scalar fails).
#
# Usage:   check-skill-frontmatter.ps1 [REPO_ROOT]
# Output:  the same TAB-separated OK/FAIL/SUMMARY record stream as the .sh
#          sibling. Exit 0 when every governed file is present, has frontmatter,
#          and is clean; exit 1 when any file is missing, lacks frontmatter, or
#          carries the defect.
param(
  [string]$Root = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout (no BOM) so output is byte-identical to the .sh sibling.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Root = ($Root -replace '[\\/]+$', '')

# Governed set — MUST stay in sync with scripts/check-skill-frontmatter.sh's
# FILES. Fixed list: a renamed/deleted governed file is a FAILURE (MISSING).
$files = @(
  'skills/setup/SKILL.md',
  'skills/solve-issue/SKILL.md',
  'skills/solve-milestone/SKILL.md',
  'skills/triage/SKILL.md'
)

# Scan one file's frontmatter. Returns a reason string on the FIRST defect
# ('' => clean, 'NO-FRONTMATTER' => no opening fence on line 1).
function Scan-Frontmatter([string]$path) {
  # Read as UTF-8 bytes and split on LF so a multibyte char and CRLF/LF both
  # survive byte-exact; TrimEnd `r normalizes a CRLF checkout.
  $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
  $lines = $text -split "`n"
  $inFm = $false
  $hadFm = $false
  $lineno = 0
  foreach ($raw in $lines) {
    $line = $raw.TrimEnd("`r")
    $lineno++
    if ($lineno -eq 1) {
      if ($line -eq '---') { $inFm = $true; $hadFm = $true; continue }
      break   # no opening fence on line 1 -> no frontmatter (do not hunt body)
    }
    if ($inFm -and $line -eq '---') { break }   # closing fence -> done
    if (-not $inFm) { continue }
    # Only TOP-LEVEL key lines: `key:` at column 0 (no leading whitespace).
    if ($line -notmatch '^[A-Za-z_]') { continue }
    $ci = $line.IndexOf(':')
    if ($ci -lt 0) { continue }                 # no colon -> not a key line
    $key = $line.Substring(0, $ci)
    if ($key -match '[^A-Za-z0-9_-]') { continue }   # non-key char -> not a key
    $val = $line.Substring($ci + 1)
    if ($val.StartsWith(' ')) { $val = $val.Substring(1) }   # drop one lead space
    if ($val.Length -eq 0) { continue }         # empty -> value on later lines
    $c0 = $val[0]
    if ($c0 -eq '|' -or $c0 -eq '>') { continue }    # block scalar -> colons safe
    if ($c0 -eq '"' -or $c0 -eq "'") { continue }    # quoted scalar -> colons safe
    if ($c0 -eq '[' -or $c0 -eq '{') { continue }    # flow collection -> out of scope
    if ($val.Contains(': ')) {                       # plain scalar with colon+space
      return "$key`: unquoted colon-space in plain scalar (breaks strict YAML)"
    }
  }
  if (-not $hadFm) { return 'NO-FRONTMATTER' }
  return ''
}

$ok = 0
$failed = 0
$out = New-Object System.Collections.Generic.List[string]

foreach ($f in $files) {
  $path = "$Root/$f"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $out.Add("FAIL`t$f`tMISSING")
    $failed++
    continue
  }
  $reason = Scan-Frontmatter $path
  if ($reason -ne '') {
    $out.Add("FAIL`t$f`t$reason")
    $failed++
  } else {
    $out.Add("OK`t$f`tclean")
    $ok++
  }
}

$out.Add("SUMMARY`tok=$ok`tfailed=$failed")
$sb = New-Object System.Text.StringBuilder
foreach ($l in $out) { [void]$sb.Append($l); [void]$sb.Append("`n") }
[Console]::Out.Write($sb.ToString())
if ($failed -ne 0) { exit 1 } else { exit 0 }
