#!/usr/bin/env pwsh
# milestone-driver — dependency-free anchored Markdown section reader (issue #184).
# Usage: read-doc-section.ps1 <doc-path> <anchor-text>
#   <anchor-text> is the heading text WITHOUT the leading #s (e.g. "Keys" matches
#   "## Keys"). Match rule: trim the leading #s and surrounding whitespace from a
#   heading line, compare the remainder to <anchor-text> CASE-SENSITIVE, exactly.
# Prints ONLY that section: the matched heading line through the line BEFORE the
# next heading whose level (count of leading #s) is <= the matched heading's
# level. If the matched heading is the last such section, prints through EOF.
# The matched heading line itself is included.
# Duplicate anchors (same heading text twice): match the FIRST occurrence.
# Fail-loud (fail-CLOSED): a missing/renamed anchor or a missing/unreadable file
#   writes a clear message to stderr (naming the anchor + file) and exits NONZERO
#   with NO stdout — never silent empty output. (This is an INTENTIONAL divergence
#   from extract-version.ps1, which fails OPEN on a version miss; silent empty
#   grounding is the drift this seam exists to surface.)
# Dependency-free: PowerShell 7+ built-ins only — no yq/python/jq.
# (docs/profile-schema.md:123 forbids new tool deps.)
# Exit codes: 0 ok · 1 missing file / missing anchor · 2 bad usage.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Err([string]$msg) { [Console]::Error.WriteLine($msg) }

if ($args.Count -ne 2) {
  Err 'usage: read-doc-section.ps1 <doc-path> <anchor-text>'
  exit 2
}
$doc = $args[0]; $anchor = $args[1]

if (-not (Test-Path -LiteralPath $doc -PathType Leaf)) {
  Err "read-doc-section: file not found or not readable: $doc"
  exit 1
}

# Read the file as lines. -ErrorAction Stop turns an unreadable file into the
# fail-loud path rather than silent empty output.
try {
  $lines = Get-Content -LiteralPath $doc -ErrorAction Stop
} catch {
  Err "read-doc-section: file not found or not readable: $doc"
  exit 1
}
# Get-Content on a single-line file returns a scalar; normalize to an array so
# the scan loop behaves identically regardless of file length.
if ($null -eq $lines) { $lines = @() }
elseif ($lines -isnot [array]) { $lines = @($lines) }

$matchedLevel = 0
$inSection = $false
$found = $false
# Accumulate the section body; emit only after a successful match so a miss
# leaves stdout empty (fail-CLOSED contract).
$out = [System.Collections.Generic.List[string]]::new()

foreach ($line in $lines) {
  # Is this an ATX heading? Leading #s then a space, or a bare line of only #s.
  $level = 0
  if ($line.StartsWith('#')) {
    $rest = $line
    while ($rest.StartsWith('#')) { $level++; $rest = $rest.Substring(1) }
    # ATX requires a space (or EOL) after the #s; otherwise it's not a heading
    # (e.g. "#hashtag"), so treat as body.
    if ($rest.Length -eq 0) { }                 # bare "###" — heading, empty text
    elseif ($rest.StartsWith(' ')) { }          # "## Keys" — standard ATX heading
    else { $level = 0 }                          # "#hashtag" — not a heading
  }

  if ($level -gt 0) {
    $text = $rest.Trim()
    if ($inSection -and $level -le $matchedLevel) {
      # A heading at equal-or-higher level closes the section.
      break
    }
    if ((-not $found) -and (-not $inSection) -and ($text -ceq $anchor)) {
      # First matching heading — open the section (first-match policy).
      $found = $true
      $inSection = $true
      $matchedLevel = $level
      $out.Add($line)
      continue
    }
  }

  if ($inSection) {
    $out.Add($line)
  }
}

if (-not $found) {
  Err "read-doc-section: anchor not found: '$anchor' in $doc"
  exit 1
}

# Join with LF and append a single trailing newline — byte-parity with the .sh
# (printf '%s\n'), independent of the host's default line ending.
[Console]::Out.Write(($out -join "`n") + "`n")
