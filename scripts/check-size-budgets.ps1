#!/usr/bin/env pwsh
# milestone-driver — CI size-budget ratchet (issue #295).
# Behavior-identical pwsh sibling of scripts/check-size-budgets.sh — see its
# header for the full ceiling-ratchet discipline and design rationale
# (ceilings only go down; a missing/renamed governed file is a FAILURE).
#
# Usage:   check-size-budgets.ps1 [REPO_ROOT]
# Output:  the same TAB-separated OK/FAIL/SUMMARY record stream as the .sh
#          sibling. Exit 0 when every governed file is present and at/under
#          its ceiling; exit 1 when any file is missing or over.
param(
  [string]$Root = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout (no BOM) so output is byte-identical to the .sh sibling.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Root = ($Root -replace '[\\/]+$', '')

# Parallel arrays — index i in $files lines up with $ceilings[i]. MUST stay in
# sync with scripts/check-size-budgets.sh's FILES/CEILINGS (see its header for
# the ratchet discipline that governs these numbers).
$files = @(
  'skills/setup/SKILL.md',
  'skills/solve-issue/SKILL.md',
  'skills/solve-issue/worker-mode.md',
  'skills/solve-issue/async-mode.md',
  'skills/solve-issue/md-epic-fanout.md',
  'skills/solve-milestone/SKILL.md',
  'skills/solve-milestone/parallel-waves.md',
  'skills/solve-milestone/trello-sync.md',
  'skills/triage/SKILL.md',
  'skills/notices.md',
  'skills/output-style.md',
  'agents/design-reviewer.md',
  'agents/implementer.md',
  'agents/triage-reviewer.md'
)
$ceilings = @(280, 380, 70, 40, 60, 680, 200, 400, 460, 250, 100, 115, 130, 120)

# Length-parity guard: $files/$ceilings are hand-edited parallel arrays with no
# structural link between them — a dropped/added line in one and not the
# other must fail loud (same shape as the .sh sibling), not silently emit a
# malformed record or misattribute a ceiling to the wrong file.
if ($files.Count -ne $ceilings.Count) {
  [Console]::Error.WriteLine("ERROR check-size-budgets: FILES($($files.Count)) and CEILINGS($($ceilings.Count)) length mismatch — fix the table")
  exit 1
}

$ok = 0
$failed = 0
$out = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $files.Count; $i++) {
  $f = $files[$i]
  $ceiling = $ceilings[$i]
  $path = "$Root/$f"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $out.Add("FAIL`t$f`tMISSING/$ceiling")
    $failed++
    continue
  }
  # Count newline (0x0A) bytes to match `wc -l` exactly, regardless of the
  # checkout's line-ending style (CRLF vs LF) — a trailing line with no final
  # newline is not counted, same as wc -l.
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $actual = 0
  foreach ($b in $bytes) { if ($b -eq 10) { $actual++ } }
  if ($actual -gt $ceiling) {
    $out.Add("FAIL`t$f`t$actual/$ceiling")
    $failed++
  } else {
    $out.Add("OK`t$f`t$actual/$ceiling")
    $ok++
  }
}

$out.Add("SUMMARY`tok=$ok`tfailed=$failed")
$sb = New-Object System.Text.StringBuilder
foreach ($l in $out) { [void]$sb.Append($l); [void]$sb.Append("`n") }
[Console]::Out.Write($sb.ToString())
if ($failed -ne 0) { exit 1 } else { exit 0 }
