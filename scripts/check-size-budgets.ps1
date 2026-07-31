#!/usr/bin/env pwsh
# milestone-driver — CI size-budget ratchet (issue #295).
# Byte ceiling added by issue #399.
# Behavior-identical pwsh sibling of scripts/check-size-budgets.sh — see its
# header for the full ceiling-ratchet discipline and design rationale (both
# ceilings only go down; BYTES is authoritative for cost and governs prose
# appended to an existing line; LINES is kept for the `file:line` citations;
# a missing/renamed governed file is a FAILURE). Raising a ceiling requires a
# recorded decision in the Decision Log of the PR body that grows the file.
#
# Usage:   check-size-budgets.ps1 [REPO_ROOT]
# Output:  the same TAB-separated OK/FAIL/SUMMARY record stream as the .sh
#          sibling, both counts on every record:
#            OK/FAIL  <path>  <lines>/<lineCeiling>  <bytes>/<byteCeiling>
#          Exit 0 when every governed file is present and at/under BOTH
#          ceilings; exit 1 when any file is missing or over either one.
param(
  [string]$Root = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout (no BOM) so output is byte-identical to the .sh sibling.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Root = ($Root -replace '[\\/]+$', '')

# Parallel arrays — index i in $files lines up with $ceilings[i]. MUST stay in
# sync with scripts/check-size-budgets.sh's FILES/CEILINGS, and with the
# $byteCeilings/BYTE_CEILINGS table paired alongside it (see that header for
# the ratchet discipline governing these numbers, and for why a byte ceiling
# rounds up to the next 500).
$files = @(
  'skills/setup/SKILL.md',
  'skills/solve-issue/SKILL.md',
  'skills/solve-issue/async-mode.md',
  'skills/solve-issue/md-epic-fanout.md',
  'skills/solve-milestone/SKILL.md',
  'skills/solve-milestone/parallel-waves.md',
  'skills/solve-milestone/trello-sync.md',
  'skills/solve-milestone/milestone-granularity.md',
  'skills/triage/SKILL.md',
  'skills/notices.md',
  'skills/output-style.md',
  'agents/design-reviewer.md',
  'agents/implementer.md',
  'agents/triage-reviewer.md'
)
$ceilings = @(280, 400, 40, 60, 680, 215, 400, 165, 460, 250, 100, 115, 130, 120)
$byteCeilings = @(33500, 78000, 5000, 9500, 80500, 68000, 21500, 25500, 42000, 13500, 10500, 16500, 15000, 16500)

# Length-parity guard: the three tables are hand-edited parallel arrays with no
# structural link between them — a dropped/added line in one and not the
# others must fail loud (same shape as the .sh sibling), not silently emit a
# malformed record or misattribute a ceiling to the wrong file.
if ($files.Count -ne $ceilings.Count -or $files.Count -ne $byteCeilings.Count) {
  [Console]::Error.WriteLine("ERROR check-size-budgets: FILES($($files.Count)), CEILINGS($($ceilings.Count)) and BYTE_CEILINGS($($byteCeilings.Count)) length mismatch, fix the table")
  exit 1
}

$ok = 0
$failed = 0
$out = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $files.Count; $i++) {
  $f = $files[$i]
  $ceiling = $ceilings[$i]
  $byteCeiling = $byteCeilings[$i]
  $path = "$Root/$f"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $out.Add("FAIL`t$f`tMISSING/$ceiling`tMISSING/$byteCeiling")
    $failed++
    continue
  }
  # Count newline (0x0A) bytes to match `wc -l` exactly, regardless of the
  # checkout's line-ending style (CRLF vs LF) — a trailing line with no final
  # newline is not counted, same as wc -l.
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $actual = 0
  foreach ($b in $bytes) { if ($b -eq 10) { $actual++ } }
  # Byte count off the SAME already-materialized array, which is what `wc -c`
  # reports on the .sh side. Never $text.Length: .NET strings are UTF-16, so an
  # astral char (most emoji) would count 2 there against 1 character / 4 bytes
  # here, and the twins would disagree on non-ASCII content.
  $actualBytes = $bytes.Length
  if ($actual -gt $ceiling -or $actualBytes -gt $byteCeiling) {
    $out.Add("FAIL`t$f`t$actual/$ceiling`t$actualBytes/$byteCeiling")
    $failed++
  } else {
    $out.Add("OK`t$f`t$actual/$ceiling`t$actualBytes/$byteCeiling")
    $ok++
  }
}

$out.Add("SUMMARY`tok=$ok`tfailed=$failed")
$sb = New-Object System.Text.StringBuilder
foreach ($l in $out) { [void]$sb.Append($l); [void]$sb.Append("`n") }
[Console]::Out.Write($sb.ToString())
if ($failed -ne 0) { exit 1 } else { exit 0 }
