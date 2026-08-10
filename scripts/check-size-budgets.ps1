#!/usr/bin/env pwsh
# milestone-driver — CI size-budget ratchet (issue #295).
# Byte ceiling added by issue #399. Word ceiling added by issue #489.
# Behavior-identical pwsh sibling of scripts/check-size-budgets.sh — see its
# header for the full ceiling-ratchet discipline and design rationale (all
# three ceilings only go down; BYTES is authoritative for cost and governs
# prose appended to an existing line; LINES is kept for the `file:line`
# citations; WORDS track the load an agent reads and move under a flat byte
# total; a missing/renamed governed file is a FAILURE). Raising a ceiling
# requires a recorded decision in the Decision Log of the PR body that grows
# the file.
#
# Usage:   check-size-budgets.ps1 [REPO_ROOT]
# Output:  the same TAB-separated OK/FAIL/SUMMARY record stream as the .sh
#          sibling, all three counts on every record:
#            OK/FAIL  <path>  <lines>/<lineCeiling>  <bytes>/<byteCeiling>  <words>/<wordCeiling>
#          Exit 0 when every governed file is present and at/under ALL THREE
#          ceilings; exit 1 when any file is missing or over any one.
param(
  [string]$Root = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout (no BOM) so output is byte-identical to the .sh sibling.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Root = ($Root -replace '[\\/]+$', '')

# The governed set, ONE ROW PER FILE: <path> <lineCeiling> <byteCeiling>
# <wordCeiling>, all four columns of a file on the same line so a file's three
# ceilings can no longer be MOVED apart from their path (issue #428 — see the
# .sh sibling's table comment for what free-standing parallel arrays cost, and
# for what this shape does and does not remove). MUST stay in sync with
# scripts/check-size-budgets.sh's GOVERNED_TABLE, row for row.
$governedTable = @'
skills/setup/SKILL.md                             280    30000     4300
skills/solve-issue/SKILL.md                       375    69500    10500
skills/solve-issue/async-mode.md                   40     4500      700
skills/solve-issue/md-epic-fanout.md               60     9000     1300
skills/solve-milestone/SKILL.md                   635    69000    10100
skills/solve-milestone/parallel-waves.md          205    68000    10600
skills/solve-milestone/trello-sync.md             400    20500     3200
skills/solve-milestone/milestone-granularity.md   165    25000     3600
skills/triage/SKILL.md                            390    37000     5600
skills/notices.md                                 250    11500     1600
skills/output-style.md                             90     9500     1600
skills/citation-format.md                         230    13000     2000
agents/design-reviewer.md                         120    16500     2700
agents/implementer.md                             130    15000     2300
agents/triage-reviewer.md                         120    17000     2700
'@

# Parse into four index-aligned lists. A row contributes a ceiling only when
# that column is present AND all digits — the same rule the .sh twin applies,
# so a malformed row yields the same four counts and the same refusal on both.
#
# $c1/$c2/$c3 fold columns the way the .sh twin's
# `read -r f line_ceiling byte_ceiling word_ceiling` does, and that fold is
# load-bearing for the parity guard below: `read` fills columns 2 and 3
# whatever the row's width, and folds every surplus column into column 4. So a
# SHORT row (word column dropped) still contributes its LINE and BYTE ceilings
# on both twins, and a LONG row (surplus 5th column) contributes a column 4
# that is non-numeric on both. Gating every add on an exact 4-column row
# instead dropped the earlier ceilings too, and the two twins then printed
# DIFFERENT counts in the refusal below for the same malformed table —
# tests/check-size-budgets.test.{sh,ps1} cover both shapes.
#
# [long], not [int]: the digit check accepts any number of digits, so a ceiling
# past int32 max (2147483647) threw on the cast under
# $ErrorActionPreference = 'Stop' while the .sh twin, whose arithmetic is
# 64-bit, treated it as a very loose ceiling and printed a clean OK stream.
$files = New-Object System.Collections.Generic.List[string]
$ceilings = New-Object System.Collections.Generic.List[long]
$byteCeilings = New-Object System.Collections.Generic.List[long]
$wordCeilings = New-Object System.Collections.Generic.List[long]
foreach ($row in ($governedTable -split "`n")) {
  $cols = $row.Trim() -split '\s+'
  if ($cols[0] -eq '' -or $cols[0].StartsWith('#')) { continue }
  $files.Add($cols[0])
  $c1 = if ($cols.Count -ge 2) { $cols[1] } else { '' }
  $c2 = if ($cols.Count -ge 3) { $cols[2] } else { '' }
  $c3 = if ($cols.Count -ge 4) { ($cols[3..($cols.Count - 1)] -join ' ') } else { '' }
  if ($c1 -match '^[0-9]+$') { $ceilings.Add([long]$c1) }
  if ($c2 -match '^[0-9]+$') { $byteCeilings.Add([long]$c2) }
  if ($c3 -match '^[0-9]+$') { $wordCeilings.Add([long]$c3) }
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
if ($files.Count -ne $ceilings.Count -or $files.Count -ne $byteCeilings.Count -or $files.Count -ne $wordCeilings.Count) {
  [Console]::Error.Write("ERROR check-size-budgets: FILES($($files.Count)), CEILINGS($($ceilings.Count)), BYTE_CEILINGS($($byteCeilings.Count)) and WORD_CEILINGS($($wordCeilings.Count)) length mismatch, fix the table`n")
  exit 1
}

$ok = 0
$failed = 0
$out = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $files.Count; $i++) {
  $f = $files[$i]
  $ceiling = $ceilings[$i]
  $byteCeiling = $byteCeilings[$i]
  $wordCeiling = $wordCeilings[$i]
  $path = "$Root/$f"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $out.Add("FAIL`t$f`tMISSING/$ceiling`tMISSING/$byteCeiling`tMISSING/$wordCeiling")
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
  # Word count off the SAME byte array, never a decoded string: `wc -w` counts
  # maximal runs of non-whitespace, and under the .sh twin's LC_ALL=C that
  # whitespace set is exactly C isspace() — space (0x20), \t (0x09), \n (0x0A),
  # \v (0x0B), \f (0x0C), \r (0x0D). Splitting a .NET string on `\s` instead
  # would also break on NBSP and the other Unicode spaces, which are word
  # CONTENT to `wc -w`, and the twins would disagree on non-ASCII content the
  # same way $text.Length would on bytes. Counting run STARTS over the bytes is
  # locale-free and identical on both sides by construction.
  $actualWords = 0
  $inWord = $false
  foreach ($b in $bytes) {
    $isSpace = ($b -eq 0x20 -or ($b -ge 0x09 -and $b -le 0x0D))
    if ($isSpace) { $inWord = $false }
    elseif (-not $inWord) { $inWord = $true; $actualWords++ }
  }
  if ($actual -gt $ceiling -or $actualBytes -gt $byteCeiling -or $actualWords -gt $wordCeiling) {
    $out.Add("FAIL`t$f`t$actual/$ceiling`t$actualBytes/$byteCeiling`t$actualWords/$wordCeiling")
    $failed++
  } else {
    $out.Add("OK`t$f`t$actual/$ceiling`t$actualBytes/$byteCeiling`t$actualWords/$wordCeiling")
    $ok++
  }
}

$out.Add("SUMMARY`tok=$ok`tfailed=$failed")
$sb = New-Object System.Text.StringBuilder
foreach ($l in $out) { [void]$sb.Append($l); [void]$sb.Append("`n") }
[Console]::Out.Write($sb.ToString())
if ($failed -ne 0) { exit 1 } else { exit 0 }
