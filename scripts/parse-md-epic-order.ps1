#!/usr/bin/env pwsh
# milestone-driver — deterministic md-epic-order block parser (issue #266).
# stdin: a parent issue's raw body text. stdout (success): one TAB-separated
# record per block entry, in block order — "<kind><TAB><raw>" (kind = number|
# title). An empty block (zero non-blank interior lines) is success with empty
# stdout. stderr is used ONLY on failure, naming the failure; exit 0 on any
# success (including the empty-block case), exit 1 on any failure.
#
# Scope boundary, block location, and grammar: see scripts/parse-md-epic-order.sh
# (behavior-identical twin) — this file mirrors that contract exactly.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OPEN_FENCE = '```md-epic-order'
$CLOSE_FENCE = '```'

function Fail([string]$msg) {
  [Console]::Error.Write($msg + "`n")
  exit 1
}

$raw = [Console]::In.ReadToEnd()
$lines = $raw -split "`n"
# A trailing newline in $raw produces one trailing empty split element that has
# no bash-`read`-loop counterpart (bash's `while read` never manufactures a
# phantom final line for a trailing \n). Drop it so both legs walk the SAME
# line array regardless of how stdin was delivered (a raw pipe vs PowerShell's
# own pipeline-to-external-process framing, which always appends one newline).
if ($raw.EndsWith("`n") -and $lines.Count -gt 0) {
  $lines = $lines[0..($lines.Count - 2)]
}
# Tolerate CRLF bodies by stripping a single TRAILING \r per line — mirrors the
# .sh twin's `line="${line%$'\r'}"` exactly (scripts/parse-md-epic-order.sh:47).
# Do NOT globally replace \r with \n: bash's `read` only strips a trailing \r
# per record: an embedded LONE \r elsewhere in a line (e.g. inside a `title:`
# value) is ordinary line content there, so it must survive here too — a
# global CR->LF conversion would turn one bash-line into two pwsh-lines.
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i].EndsWith("`r")) {
    $lines[$i] = $lines[$i].Substring(0, $lines[$i].Length - 1)
  }
}

$state = 'search'   # search | inside
$foundOpen = $false
$closed = $false
$openLine = 0
$pos = 0
$kinds = [System.Collections.Generic.List[string]]::new()
$raws = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  $lineno = $i + 1

  if ($state -eq 'search') {
    if ($line -ceq $OPEN_FENCE) {
      $state = 'inside'
      $foundOpen = $true
      $openLine = $lineno
    }
    continue
  }

  # state = inside — position is 1-based from the first line inside the block,
  # blank lines included in the count.
  $pos++

  if ($line -ceq $CLOSE_FENCE) {
    $closed = $true
    break
  }

  # blank/whitespace-only interior line: ignored (never malformed, never
  # counted as an entry). ASCII-only whitespace set (space/tab/CR/FF/VT) to
  # match bash's `[:space:]` under `LC_ALL=C` byte-for-byte (scripts/parse-md-
  # epic-order.sh:70-72) — NOT `.Trim()`, which is Unicode-aware and would also
  # treat NBSP (U+00A0), U+3000, etc. as blank, diverging from the bash leg's
  # byte-oriented C-locale behavior.
  if ($line -cmatch '^[ \t\r\f\v]*$') { continue }

  if ($line -cmatch '^number: (0|[1-9][0-9]*)$') {
    $kinds.Add('number'); $raws.Add($Matches[1])
    continue
  }
  if ($line -cmatch '^title: (.+)$') {
    $kinds.Add('title'); $raws.Add($Matches[1])
    continue
  }

  Fail("parse-md-epic-order: malformed line at position ${pos}: '$line'")
}

if (-not $foundOpen) {
  Fail('parse-md-epic-order: no md-epic-order block found')
}
if (-not $closed) {
  Fail("parse-md-epic-order: unterminated md-epic-order fence opened at line $openLine")
}

$sb = New-Object System.Text.StringBuilder
for ($j = 0; $j -lt $kinds.Count; $j++) {
  [void]$sb.Append("$($kinds[$j])`t$($raws[$j])`n")
}
[Console]::Out.Write($sb.ToString())
exit 0
