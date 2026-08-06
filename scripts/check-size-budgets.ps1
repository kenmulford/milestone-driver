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

# The governed set, ONE ROW PER FILE: <path> <lineCeiling> <byteCeiling>, all
# three columns of a file on the same line so a file's two ceilings can no
# longer be MOVED apart from their path (issue #428 — see the .sh sibling's
# table comment for what three free-standing parallel arrays cost, and for what
# this shape does and does not remove). MUST stay in sync with
# scripts/check-size-budgets.sh's GOVERNED_TABLE, row for row.
$governedTable = @'
skills/setup/SKILL.md                             280    33500
skills/solve-issue/SKILL.md                       400    78000
skills/solve-issue/async-mode.md                   40     5000
skills/solve-issue/md-epic-fanout.md               60     9500
skills/solve-milestone/SKILL.md                   680    80500
skills/solve-milestone/parallel-waves.md          215    68000
skills/solve-milestone/trello-sync.md             400    21500
skills/solve-milestone/milestone-granularity.md   165    25500
skills/triage/SKILL.md                            460    42000
skills/notices.md                                 250    13500
skills/output-style.md                            100    10500
agents/design-reviewer.md                         115    16500
agents/implementer.md                             130    15000
agents/triage-reviewer.md                         120    16500
'@

# Parse into three index-aligned lists. A row contributes a ceiling only when
# that column is present AND all digits — the same rule the .sh twin applies,
# so a malformed row yields the same three counts and the same refusal on both.
#
# $c1/$c2 fold columns the way the .sh twin's
# `read -r f line_ceiling byte_ceiling` does, and that fold is load-bearing for
# the parity guard below: `read` fills column 2 whatever the row's width, and
# folds every surplus column into column 3. So a SHORT row (byte column
# dropped) still contributes its LINE ceiling on both twins, and a LONG row
# (surplus 4th column) contributes a column 3 that is non-numeric on both.
# Gating both adds on an exact 3-column row instead dropped the line ceiling
# too, and the two twins then printed DIFFERENT counts in the refusal below for
# the same malformed table — tests/check-size-budgets.test.{sh,ps1} cover both
# shapes.
#
# [long], not [int]: the digit check accepts any number of digits, so a ceiling
# past int32 max (2147483647) threw on the cast under
# $ErrorActionPreference = 'Stop' while the .sh twin, whose arithmetic is
# 64-bit, treated it as a very loose ceiling and printed a clean OK stream.
$files = New-Object System.Collections.Generic.List[string]
$ceilings = New-Object System.Collections.Generic.List[long]
$byteCeilings = New-Object System.Collections.Generic.List[long]
foreach ($row in ($governedTable -split "`n")) {
  $cols = $row.Trim() -split '\s+'
  if ($cols[0] -eq '' -or $cols[0].StartsWith('#')) { continue }
  $files.Add($cols[0])
  $c1 = if ($cols.Count -ge 2) { $cols[1] } else { '' }
  $c2 = if ($cols.Count -ge 3) { ($cols[2..($cols.Count - 1)] -join ' ') } else { '' }
  if ($c1 -match '^[0-9]+$') { $ceilings.Add([long]$c1) }
  if ($c2 -match '^[0-9]+$') { $byteCeilings.Add([long]$c2) }
}

# Length-parity guard: the parse above appends a path unconditionally and each
# ceiling only when its column is present and numeric, so a malformed row shows
# up here as unequal counts. That must fail loud (same shape as the .sh
# sibling), not silently emit a malformed record or misattribute a ceiling to
# the wrong file.
# Write, not WriteLine: WriteLine terminates with [Environment]::NewLine, which
# is CRLF on Windows, and the .sh sibling's printf emits a bare LF there too.
# An explicit "`n" keeps the two stderr streams byte-identical on every host,
# the same reason stdout below is assembled with explicit "`n" and written with
# [Console]::Out.Write. tests/check-size-budgets.test.{sh,ps1} assert this exact
# line against one shared golden.
if ($files.Count -ne $ceilings.Count -or $files.Count -ne $byteCeilings.Count) {
  [Console]::Error.Write("ERROR check-size-budgets: FILES($($files.Count)), CEILINGS($($ceilings.Count)) and BYTE_CEILINGS($($byteCeilings.Count)) length mismatch, fix the table`n")
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
