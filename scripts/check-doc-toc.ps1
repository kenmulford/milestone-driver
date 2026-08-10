#!/usr/bin/env pwsh
# milestone-driver — CI table-of-contents gate (issue #490).
# Behavior-identical pwsh sibling of scripts/check-doc-toc.sh — see its header
# for the full rationale: the standard being satisfied, why the scan takes the
# first level-2-or-higher heading rather than an H1 (three agents/*.md files
# carry no `^# ` line at all; three skills files carry `^# ` bash comments
# inside fenced blocks), what the scan does and does not assert (the heading
# and its position, never the index body), the deliberate fence limitation, and
# why the threshold is strictly over 100 lines.
#
# Usage:   check-doc-toc.ps1 [REPO_ROOT]
# Output:  the same TAB-separated OK/FAIL/SUMMARY record stream as the .sh
#          sibling:
#            OK       <path>
#            FAIL     <path>
#            FAIL     <path>  MISSING
#            SUMMARY  ok=<N>  failed=<M>
#          Exit 0 only when every listed file is present and compliant; exit 1
#          when any file is missing, or is over the threshold without
#          `## Contents` as its first level-2-or-higher heading.
param(
  [string]$Root = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout (no BOM) so output is byte-identical to the .sh sibling.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Root = ($Root -replace '[\\/]+$', '')

# Lines strictly above this count make `## Contents` mandatory.
$threshold = 100

# The governed set, PATH ONLY. MUST stay in sync with
# scripts/check-doc-toc.sh's GOVERNED_PATHS heredoc, row for row, and with the
# path column of scripts/check-size-budgets.sh's GOVERNED_TABLE — the one
# definition of "a governed file" in this repo.
$governedPaths = @'
skills/setup/SKILL.md
skills/solve-issue/SKILL.md
skills/solve-issue/async-mode.md
skills/solve-issue/md-epic-fanout.md
skills/solve-milestone/SKILL.md
skills/solve-milestone/parallel-waves.md
skills/solve-milestone/trello-sync.md
skills/solve-milestone/milestone-granularity.md
skills/triage/SKILL.md
skills/notices.md
skills/output-style.md
skills/citation-format.md
agents/design-reviewer.md
agents/implementer.md
agents/triage-reviewer.md
'@

$files = New-Object System.Collections.Generic.List[string]
foreach ($row in ($governedPaths -split "`n")) {
  $p = $row.Trim()
  if ($p -eq '' -or $p.StartsWith('#')) { continue }
  $files.Add($p)
}

# The exact whitespace set C `isspace()` defines, which is what the .sh twin
# trims under LC_ALL=C: space, \t, \n, \v, \f, \r. Trimming with .NET's
# parameterless .Trim() instead would also eat NBSP and the other Unicode
# spaces, which are heading TEXT to the bash twin, and the two would then
# disagree on a heading containing one.
$asciiSpace = [char[]](0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D)
$u8 = New-Object System.Text.UTF8Encoding($false)

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

  # Count newline (0x0A) bytes to match `wc -l` exactly, regardless of the
  # checkout's line-ending style (CRLF vs LF) — a trailing line with no final
  # newline is not counted, same as wc -l.
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $lines = 0
  foreach ($b in $bytes) { if ($b -eq 10) { $lines++ } }
  if ($lines -le $threshold) {
    $out.Add("OK`t$f")
    $ok++
    continue
  }

  # Decode the SAME byte array, so the file is read once on both twins.
  $rows = ($u8.GetString($bytes)) -split "`n"
  $inFrontmatter = $false
  $found = $false
  $level = 0
  $text = ''
  for ($j = 0; $j -lt $rows.Count; $j++) {
    # Tolerate a CRLF working tree even though .gitattributes pins *.md and
    # tests/fixtures/** to LF.
    $line = $rows[$j].TrimEnd([char]0x0D)

    # Skip a LEADING YAML frontmatter fence only: `---` on line 1 opens it, the
    # next `---` closes it.
    if ($j -eq 0 -and $line -eq '---') { $inFrontmatter = $true; continue }
    if ($inFrontmatter) {
      if ($line -eq '---') { $inFrontmatter = $false }
      continue
    }

    # Level 2 or higher only. A `# ...` line — an H1, or a bash comment inside
    # a fence, which this scanner cannot tell apart — is ordinary content.
    if (-not $line.StartsWith('##', [System.StringComparison]::Ordinal)) { continue }
    $hashes = 0
    while ($hashes -lt $line.Length -and $line[$hashes] -eq '#') { $hashes++ }
    $rest = $line.Substring($hashes)
    # ATX requires a space after the #s. A bare `##` or a `##hashtag` is body
    # text, matching scripts/read-doc-section.ps1's heading rule.
    # ORDINAL, not culture-sensitive. .NET's default StartsWith uses ICU
    # collation, under which zero-width characters (U+200B, U+00AD, U+FEFF)
    # are ignorable — so `"##<U+200B> Bogus"` reports a leading space here and
    # is read as a heading, while the bash twin compares bytes and reads it as
    # body text. Measured: the two legs returned OK and FAIL for the same file,
    # which is one CI leg green and the other red. Same ordinal discipline the
    # $asciiSpace trim set above already applies, for the same reason.
    if (-not $rest.StartsWith(' ', [System.StringComparison]::Ordinal)) { continue }
    $level = $hashes
    $text = $rest.Trim($asciiSpace)
    $found = $true
    break
  }

  if ($found -and $level -eq 2 -and $text -eq 'Contents') {
    $out.Add("OK`t$f")
    $ok++
  } else {
    $out.Add("FAIL`t$f")
    $failed++
  }
}

$out.Add("SUMMARY`tok=$ok`tfailed=$failed")
# Assemble with explicit "`n" and write with [Console]::Out.Write: WriteLine
# would terminate with [Environment]::NewLine, which is CRLF on Windows, and
# the .sh sibling's printf emits a bare LF there too.
$sb = New-Object System.Text.StringBuilder
foreach ($l in $out) { [void]$sb.Append($l); [void]$sb.Append("`n") }
[Console]::Out.Write($sb.ToString())
if ($failed -ne 0) { exit 1 } else { exit 0 }
