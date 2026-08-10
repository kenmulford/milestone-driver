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
# CLOSURE record added by issue #491 — see the .sh sibling's header for the
# closure-ceiling ratchet (same `actual * 1.05` rounded UP to the next 100
# words, down freely, up only with a recorded decision, with the one documented
# difference that superpowers:writing-skills' 5000-word cap does NOT apply to a
# sum across several files).
#
# Usage:   check-size-budgets.ps1 [REPO_ROOT]
# Output:  the same TAB-separated record stream as the .sh sibling — one line
#          per governed file, then one line per governed SKILL's load closure,
#          then the trailing summary:
#            OK/FAIL  <path>  <lines>/<lineCeiling>  <bytes>/<byteCeiling>  <words>/<wordCeiling>
#            CLOSURE  <skillPath>  <wordSum>/<closureWordCeiling>
#            CLOSURE  <skillPath>  MISSING/<closureWordCeiling>
#            SUMMARY  ok=<N>  failed=<M>
#          Exit 0 when every governed file is present and at/under ALL THREE
#          ceilings; exit 1 when any file is missing or over any one.
#
# The CLOSURE record is INFORMATIONAL AND NEVER GATES, the same
# milestone-scoped choice the .sh sibling's header records: a sum over its
# ceiling changes NO exit code and is counted in NEITHER ok= nor failed=, and a
# closure whose sum cannot be computed (any member absent from disk) prints
# MISSING and still changes no exit code — that member is itself a governed
# file, so its own `FAIL <path> MISSING/...` row above has already failed the
# run, and failing twice for one deletion would double-count it in failed=.
# Its position, after every per-file row and before the trailing SUMMARY, is
# what keeps it additive to the existing stream.
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
skills/setup/SKILL.md                               280    30000     4300
skills/solve-issue/SKILL.md                         325    43000     6000
skills/solve-issue/async-mode.md                     40     4500      700
skills/solve-issue/md-epic-fanout.md                 60     9000     1300
skills/solve-issue/coherence-review.md               15     2500      300
skills/solve-issue/milestone-clauses.md              30     6000      900
skills/solve-issue/permission-preflight.md           35     2500      400
skills/solve-issue/post-fix-commit.md                25     4500      700
skills/solve-issue/preflight-github-ci.md            20     3000      400
skills/solve-issue/resume-paths.md                   20     3000      500
skills/solve-issue/version-bump.md                   20     4000      600
skills/solve-issue/visual-capture.md                 20     6000      800
skills/solve-issue/visual-review-hold.md             20     2500      400
skills/solve-milestone/SKILL.md                     320    38000     5000
skills/solve-milestone/parallel-waves.md            205    40500     6000
skills/solve-milestone/trello-sync.md               400    20500     3200
skills/solve-milestone/milestone-granularity.md     165    25000     3600
skills/solve-milestone/abandoned-recovery.md         45     6000      900
skills/solve-milestone/changelog-authoring.md       210    14000     2200
skills/solve-milestone/contingencies.md              70     8500     1200
skills/solve-milestone/db-hazard-interview.md        30     2500      400
skills/solve-milestone/integration-granularity.md    85    15500     2400
skills/solve-milestone/md-epic-parent-check.md       30     2500      400
skills/solve-milestone/not-buildable.md              20     3500      500
skills/solve-milestone/sequential-loop.md            35     7500     1100
skills/solve-milestone/version-target.md             30     3000      400
skills/triage/SKILL.md                              390    35500     5000
skills/notices.md                                   250    11500     1600
skills/output-style.md                               90     9500     1600
skills/citation-format.md                           230    13000     2000
agents/design-reviewer.md                           120    16500     2600
agents/implementer.md                               130    15000     2300
agents/triage-reviewer.md                           120    17000     2600
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

# The UNCONDITIONAL LOAD CLOSURE of each governed skill (issue #491), ONE ROW
# PER SKILL: <skillPath> <closureWordCeiling> <member> <member> ... — see the
# .sh sibling's CLOSURE_TABLE comment for why the record exists, for the
# membership rule (a file belongs to a closure when the skill reads it on EVERY
# run, with no branch in front of the read), for the branch-gated files that are
# deliberately EXCLUDED — the original five plus 17 of milestone #39's splits,
# each with the branch that gates it — for the 18th split
# (skills/solve-issue/version-bump.md), which is NOT branch-gated and IS summed
# into solve-issue's closure, carrying that closure's 11200 -> 11700
# re-derivation with it, and for why column 1 is both the record's
# label and the implicit first member of its own closure. MUST stay in sync
# with that table, row for row, the same requirement the governed set carries.
# An EMPTY table is legal and simply prints no CLOSURE records.
$closureTable = @'
skills/setup/SKILL.md              7800   skills/output-style.md skills/citation-format.md
skills/solve-issue/SKILL.md       11700   skills/notices.md skills/output-style.md skills/citation-format.md skills/solve-issue/version-bump.md
skills/solve-milestone/SKILL.md   10400   skills/notices.md skills/output-style.md skills/citation-format.md
skills/triage/SKILL.md             8800   skills/output-style.md skills/citation-format.md
'@

# Parse into three index-aligned lists, by the same rule the governed parse
# applies: the skill is appended unconditionally and its ceiling only when that
# column is present AND all digits. Surplus columns fold into the members list
# the way the .sh twin's `read -r skill closure_ceiling members` folds them into
# one trailing field, so both twins read the same row the same way. Members are
# held as ONE space-joined string, mirroring that field exactly; the emission
# loop splits it back, mirroring the twin's unquoted `for m in $skill $members`.
# StartsWith is Ordinal (matching scripts/check-doc-toc.ps1): a comment marker
# is a byte, never a culture-sensitive comparison.
$closureSkills = New-Object System.Collections.Generic.List[string]
$closureCeilings = New-Object System.Collections.Generic.List[long]
$closureMembers = New-Object System.Collections.Generic.List[string]
foreach ($row in ($closureTable -split "`n")) {
  $cols = $row.Trim() -split '\s+'
  if ($cols[0] -eq '' -or $cols[0].StartsWith('#', [System.StringComparison]::Ordinal)) { continue }
  $closureSkills.Add($cols[0])
  $cc = if ($cols.Count -ge 2) { $cols[1] } else { '' }
  $closureMembers.Add($(if ($cols.Count -ge 3) { ($cols[2..($cols.Count - 1)] -join ' ') } else { '' }))
  if ($cc -match '^[0-9]+$') { $closureCeilings.Add([long]$cc) }
}

# Same length-parity guard the governed table carries, for the same reason: a
# row whose ceiling was dropped or garbled (most plausibly by writing a member
# path where the ceiling belongs) shows up here as unequal counts and refuses to
# run. A row with NO members is not malformed — that is a one-file closure, and
# its sum is just the SKILL.md. The refusal is emitted with the same explicit
# "`n" the guard above uses, and for the same byte-identity reason it records —
# do not reword that phrasing here, it is a UNIQUE citation anchor
# (scripts/triage-cache.ps1 cites it, and a second copy of the anchor text in
# this file fails scripts/check-citations.sh on ambiguity).
if ($closureSkills.Count -ne $closureCeilings.Count) {
  [Console]::Error.Write("ERROR check-size-budgets: CLOSURE_SKILLS($($closureSkills.Count)) and CLOSURE_CEILINGS($($closureCeilings.Count)) length mismatch, fix the closure table`n")
  exit 1
}

# ONE function, called by BOTH the per-file word column and the CLOSURE sums,
# so the two can never be measured by different algorithms — a closure is a sum
# of the very numbers the per-file rows print, not a second count of the same
# files. Words are counted off the raw BYTES, never a decoded string: `wc -w` is
# not portable for this content (GNU adds a non-breaking-space clause BSD lacks,
# measured as a one-word divergence on the emoji-bearing fixtures), so the .sh
# twin counts maximal runs of non-whitespace with `tr`+`grep` over exactly the
# six C isspace bytes — space (0x20), \t (0x09), \n (0x0A), \v (0x0B), \f (0x0C),
# \r (0x0D). Counting run STARTS over those same six byte values is locale-free
# and identical to that by construction; splitting a .NET string on `\s` instead
# would also break on NBSP and the other Unicode spaces, which are word CONTENT
# to the twin, and the two would disagree on non-ASCII content.
function Get-WordCount {
  param([byte[]]$Bytes)
  $n = 0
  $inWord = $false
  foreach ($b in $Bytes) {
    $isSpace = ($b -eq 0x20 -or ($b -ge 0x09 -and $b -le 0x0D))
    if ($isSpace) { $inWord = $false }
    elseif (-not $inWord) { $inWord = $true; $n++ }
  }
  return $n
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
  # Word count off the SAME already-materialized byte array, through the SAME
  # function the CLOSURE sums below call — see its definition above for what it
  # counts and why it never decodes to a string.
  $actualWords = Get-WordCount $bytes
  if ($actual -gt $ceiling -or $actualBytes -gt $byteCeiling -or $actualWords -gt $wordCeiling) {
    $out.Add("FAIL`t$f`t$actual/$ceiling`t$actualBytes/$byteCeiling`t$actualWords/$wordCeiling")
    $failed++
  } else {
    $out.Add("OK`t$f`t$actual/$ceiling`t$actualBytes/$byteCeiling`t$actualWords/$wordCeiling")
    $ok++
  }
}

# One CLOSURE record per closure row, AFTER every per-file record and BEFORE
# the trailing SUMMARY. The skill's own SKILL.md leads the member list because
# column 1 is the first member of its own closure and is never listed in the
# members column; the split of the joined members string mirrors the .sh twin's
# unquoted `for m in $skill $members`.
#
# NEITHER $ok NOR $failed IS TOUCHED HERE, and no exit code is decided here. The
# absence check short-circuits before summing rather than summing what is
# present: a partial sum reads as a real measurement of a closure that cannot be
# measured, and would silently drop under its ceiling exactly when a member was
# deleted.
for ($j = 0; $j -lt $closureSkills.Count; $j++) {
  $skill = $closureSkills[$j]
  $closureCeiling = $closureCeilings[$j]
  $members = @($skill)
  if ($closureMembers[$j] -ne '') { $members += ($closureMembers[$j] -split ' ') }
  $closureWords = 0
  $closureMissing = $false
  foreach ($m in $members) {
    $mp = "$Root/$m"
    if (-not (Test-Path -LiteralPath $mp -PathType Leaf)) { $closureMissing = $true; break }
    $closureWords += Get-WordCount ([System.IO.File]::ReadAllBytes($mp))
  }
  if ($closureMissing) {
    $out.Add("CLOSURE`t$skill`tMISSING/$closureCeiling")
  } else {
    $out.Add("CLOSURE`t$skill`t$closureWords/$closureCeiling")
  }
}

$out.Add("SUMMARY`tok=$ok`tfailed=$failed")
$sb = New-Object System.Text.StringBuilder
foreach ($l in $out) { [void]$sb.Append($l); [void]$sb.Append("`n") }
[Console]::Out.Write($sb.ToString())
if ($failed -ne 0) { exit 1 } else { exit 0 }
