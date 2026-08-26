#!/usr/bin/env pwsh
# milestone-driver - dependency-free citation anchor resolver (issue #417).
# Usage: resolve-citation.ps1 <file-path> <anchor-text>
# Reports EVERY occurrence of <anchor-text> in <file-path>, one TAB-separated
# record per line, in FILE ORDER:
#   PRIMARY<TAB><line><TAB><text>   the FIRST occurrence in the file
#   MATCH<TAB><line><TAB><text>     every further occurrence
# <line> is 1-based. <text> is the ENTIRE matched line, VERBATIM - leading
# whitespace and any embedded literal TAB included - so a consumer splits on the
# FIRST TWO tabs only and takes the whole remainder as the text. Same TAB-record
# convention as scripts/parse-md-epic-order.ps1 and
# scripts/check-skill-frontmatter.ps1.
# Match rule: LITERAL SUBSTRING, CASE-SENSITIVE, ORDINAL. NOT a regex - a '.' or
# '*' in the anchor matches only itself. Matching is LINE-SCOPED - the per-line
# scan loop mirrors scripts/read-doc-section.ps1 (foreach ($line in $lines))
# - so an anchor containing a real newline can never match: no line holds one.
# PRIMARY is a LABEL, NOT A FILTER. A bare method-name anchor legitimately hits
# its declaration and its call sites, and every hit is reported, so a
# poorly-chosen anchor costs a scan rather than a wrong answer. The fix for a
# multi-match anchor is a better anchor at authoring time, not machinery here.
# First-occurrence-wins mirrors scripts/read-doc-section.ps1 (Duplicate anchors); there is no hint-line
# argument and no nearest-match logic.
# One citation per invocation: no stdin, no batch mode - the caller loops.
#
# LINE MODEL - identical on both legs by construction, because a <line> that
# differs between the twins is the worst answer a citation resolver can give:
#   - Lines split on LF ONLY. A lone CR is ORDINARY TEXT, never a terminator:
#     it stays inside <text> and never shifts a line number. This is why the
#     file is read with -Raw and split by hand: Get-Content's DEFAULT line
#     splitting also breaks on a lone CR, which would report a different line
#     number than the bash leg's `read` loop for the same bytes.
#   - A single trailing CR per line is stripped, so a CRLF working tree
#     (Windows core.autocrlf) yields the same <text> as an LF one - the -Raw
#     read means this leg must do it explicitly, exactly as the bash leg does.
#   - A leading UTF-8 BOM is stripped from line 1 explicitly rather than left to
#     the reader's BOM detection, so line-1 <text> matches the bash twin's by
#     construction. Issue #418 points this at arbitrary repo files, where a BOM
#     is a real possibility.
# OUT OF CONTRACT: files containing NUL bytes. This leg KEEPS them while the
#   bash twin's `read` discards them, so <text> differs and the two legs can
#   return DIFFERENT EXIT CODES for the same binary input - measured: on a line
#   reading "before<NUL>after", the anchor "beforeafter" matches on the bash leg
#   (exit 0) and not here (exit 1). Binary files are not citation targets; this
#   divergence is documented, not aligned.
#
# Fail-loud (fail-CLOSED), mirroring scripts/read-doc-section.ps1 (Fail-loud (fail-CLOSED)): a missing anchor,
#   a missing/unreadable file, or bad usage writes a clear message to stderr
#   (naming the anchor and/or the file) and exits NONZERO with NO stdout -
#   never silent empty output, and never a partial record set.
# Dependency-free: PowerShell 7+ built-ins only - no yq/python/jq. Adding a tool
#   dependency is a STOP-and-ask gate, and this plugin's stated non-negotiable
#   is "no new tool dependency" - the same posture check-size-budgets.ps1 and
#   the CI-preflight parser take over their own narrow surfaces
#   (.project/library-manifest.md#Adding a dependency (the gate);
#   docs/architecture.md#Preflight (optional)).
# Exit codes: 0 at least one match · 1 missing/unreadable file, or anchor not
#   found · 2 bad usage - an argument count other than 2, or a present-but-EMPTY
#   anchor (an empty substring matches every line, so it is a usage error rather
#   than a whole-file answer; same exit code scripts/read-doc-section.ps1 (if ($args.Count -ne 2) {) uses).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# LF, not Environment.NewLine: [Console]::Error.WriteLine would emit CRLF on
# Windows while the bash twin emits LF, so stderr would diverge by host. The
# stdout writer at the bottom hard-codes LF for the same reason.
function Err([string]$msg) { [Console]::Error.Write($msg + "`n") }

if ($args.Count -ne 2) {
  Err 'usage: resolve-citation.ps1 <file-path> <anchor-text>'
  exit 2
}
$file = $args[0]; $anchor = $args[1]

if ([string]::IsNullOrEmpty($anchor)) {
  Err 'resolve-citation: empty anchor-text: an empty anchor matches every line'
  exit 2
}

if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
  Err "resolve-citation: file not found or not readable: $file"
  exit 1
}

# -Raw: read the file as ONE string and do the line splitting here (see LINE
# MODEL). -ErrorAction Stop turns an unreadable file into the fail-loud path
# rather than silent empty output.
try {
  $raw = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
} catch {
  Err "resolve-citation: file not found or not readable: $file"
  exit 1
}
# Get-Content -Raw returns $null for a zero-byte file.
if ($null -eq $raw) { $raw = '' }
if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }

# Split on LF (0x0A) ONLY - never on CR.
$lines = [System.Collections.Generic.List[string]]::new($raw.Split([char]10))
if ($raw.Length -eq 0) {
  # A zero-byte file has no lines at all; Split returns one empty element.
  $lines.Clear()
} elseif ($raw.EndsWith("`n")) {
  # A trailing LF TERMINATES the last line, it does not start an empty one -
  # the bash leg's `read` loop yields nothing after a final newline either.
  $lines.RemoveAt($lines.Count - 1)
}

# Collect the records and emit once at the end, so a miss leaves stdout empty
# (fail-CLOSED contract).
$out = [System.Collections.Generic.List[string]]::new()
$lineno = 0

foreach ($line in $lines) {
  $lineno++
  if ($line.EndsWith("`r")) { $line = $line.Substring(0, $line.Length - 1) }
  # Ordinal comparison keeps this byte-for-byte equivalent to the bash leg's
  # LC_ALL=C `case` test; the default culture-sensitive compare would not be.
  if (-not $line.Contains($anchor, [System.StringComparison]::Ordinal)) { continue }
  $kind = if ($out.Count -eq 0) { 'PRIMARY' } else { 'MATCH' }
  $out.Add("$kind`t$lineno`t$line")
}

if ($out.Count -eq 0) {
  Err "resolve-citation: anchor not found: '$anchor' in $file"
  exit 1
}

# Join with LF and append a single trailing newline - byte-parity with the .sh
# (printf '%s\n'), independent of the host's default line ending.
[Console]::Out.Write(($out -join "`n") + "`n")
