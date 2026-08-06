#!/usr/bin/env pwsh
# milestone-driver — repo-wide citation gate (issue #432).
#
# Twin of check-citations.sh: SAME walk, SAME discriminator, SAME resolution
# model, BYTE-IDENTICAL stdout and stderr. See that file's header for the full
# contract — what a green run does and does not verify, the four discriminator
# rules and the measurements behind them, the edge cases and the choice made for
# each, why an anchor is resolved only against the walked file set, and why
# docs/superpowers/**, docs/briefs/**, CHANGELOG.md, tests/fixtures/**,
# .milestone-config/worktrees/** and .milestone-feeder/** are excluded from the
# walk. This header records only what is specific to THIS leg.
#
# Usage:   check-citations.ps1 [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# A GREEN RUN VERIFIES ONLY `path (anchor)` CITATIONS. `path:line`,
# `path:start-end`, `path#Heading` and `path § Heading` are counted and reported
# as UNVERIFIED records, never resolved — `failed=0` means "every anchor still
# points at its string", NOT "every citation in this repo is good".
#
# ── THE BYTE DOMAIN, AND WHY IT IS LATIN-1 ────────────────────────────────────
# The bash leg runs under LC_ALL=C and `grep -a -c -F`: it compares BYTES, with
# no decoding step anywhere. For this leg to answer identically it must compare
# bytes too, so EVERY FILE IS READ AS RAW BYTES AND DECODED WITH LATIN-1
# (ISO-8859-1), which is the ONLY .NET encoding that is a LOSSLESS BYTE-TO-CHAR
# BIJECTION: byte 0x00-0xFF maps to char U+0000-U+00FF and back, always. One
# byte in, one char out, nothing normalized and nothing lost. Content strings in
# this script are therefore BYTE-CHARS, not text, and `.Length` is a byte count.
#
# What that fixes, both measured as red-vs-green splits between the legs:
#   - `Get-Content -Raw` with no -Encoding runs BOM DETECTION. A UTF-16 target
#     file decoded to real text on this leg while the bash leg saw UTF-16 bytes:
#     bash `FAIL … 0 matches` exit 1, pwsh `OK` exit 0, SAME TREE. Latin-1 has
#     no BOM concept, so a BOM is three ordinary bytes here exactly as it is to
#     `grep` and to the bash leg's `read`.
#   - The same reader SUBSTITUTES U+FFFD for invalid UTF-8. A raw 0xE9 byte in
#     an anchor came out of this leg as `EF BF BD` while bash emitted `E9` —
#     different stdout bytes, which breaks twin parity directly. Latin-1 cannot
#     substitute: 0xE9 decodes to U+00E9 and re-encodes to 0xE9.
# UTF-8 was rejected for the same reason a "usually the same" answer was
# rejected on #441's ISO-8601 coercion: .NET's UTF-8 decoder has no mode that
# preserves an invalid byte. It either throws or replaces. Only Latin-1 is
# total.
#
# STDOUT AND STDERR ARE WRITTEN AS RAW BYTES through the standard streams, not
# through [Console]::Out — Console.OutputEncoding would re-encode a byte-char
# above 0x7F and undo the whole model. The script's own non-ASCII literals (the
# ` § ` separator, the ` — ` terminator, the three `— not verified` suffixes)
# are written readably in this source and converted ONCE by ToByteChars, so
# source stays legible while the stream stays byte-exact.
#
# ── TWIN-PARITY NOTES ─────────────────────────────────────────────────────────
#   - OFFSETS. Because content is byte-chars, every index here is a BYTE index,
#     the same unit the bash leg's LC_ALL=C parameter expansions use. The two
#     legs now agree on offsets as well as on output.
#   - THE SORT. Byte-char strings sorted with StringComparer.Ordinal ARE sorted
#     by byte value, so the walk order matches `LC_ALL=C sort` exactly — for
#     every path, including one holding an astral character, where a sort of
#     decoded UTF-16 text would have disagreed.
#   - THE WALK, and its LIST/READ split. The bash leg LISTS every entry that is
#     not a directory and not a symlink, and READS only those with size greater
#     than zero. This leg does exactly the same, because `-type f` is a test it
#     CANNOT reproduce: .NET on Unix exposes no regular-file bit. Probed on pwsh
#     7.6.3, a FIFO reports FileAttributes.Normal AND UnixMode `-rw-r--r--`,
#     both identical to a 0-byte regular file, so nothing here can tell them
#     apart. Listing on the looser rule keeps the two legs' EXCLUDED counts
#     equal (this repo's fixtures hold three 0-byte files, which `-type f`
#     counted and an earlier size-based walk here did not: a 3-file gap in the
#     record stream), and refusing to OPEN a 0-byte entry is what keeps both
#     legs off a FIFO. That last part is why this leg used to hang: Get-Content
#     on a FIFO BLOCKS ON OPEN FOREVER, turning a CI job into a timeout with
#     zero output while the bash leg finished normally.
#   - UNREADABLE DIRECTORIES. Enumeration is materialized inside a try/catch and
#     an unreadable directory is skipped whole, matching what `find` does. The
#     bash leg discards find's own warning because its wording is not portable
#     (BSD and GNU spell it differently), so BOTH legs stay silent and stdout,
#     stderr and exit code all match. Before this, $ErrorActionPreference =
#     'Stop' turned one chmod-000 subdirectory into an aborted run: empty
#     stdout, a ParentContainsErrorRecordException, exit 1.
#   - CONTAINMENT. An anchor is resolved only against a path that is a MEMBER OF
#     THE WALKED SET, held here as a dictionary keyed by the byte-char relative
#     path. Same test as the bash leg's in_tree, same answer.
#   - THE MATCH COUNT. `grep -a -c -F` counts MATCHING LINES. This leg splits
#     the raw bytes on LF only and counts lines containing the anchor
#     ORDINALLY. Ordinal is load-bearing — PowerShell's default comparison is
#     culture-sensitive and case-insensitive, and would count matches `grep`
#     does not. Same call as
#     scripts/resolve-citation.ps1 (Ordinal comparison keeps this).
#
# OUT OF CONTRACT: a filename whose bytes are not valid UTF-8. .NET decodes
# Unix paths as UTF-8 and such a name is not round-trippable, so it is skipped
# rather than mis-opened; the bash leg would list it. No such name exists in
# this repo, and the same carve-out covers NUL bytes in file CONTENT, which
# scripts/resolve-citation.ps1 (OUT OF CONTRACT) already documents.
#
# Dependency-free: PowerShell 7+ built-ins only — no jq, no yq, no python, no
# YAML or markdown parser
# (.project/library-manifest.md#Adding a dependency (the gate)).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The two encodings the byte domain is built on. Latin1 is the byte<->char
# bijection; UTF8 is used ONLY to turn this source file's own literals into
# their byte-char spelling.
$L1 = [System.Text.Encoding]::Latin1
$U8 = [System.Text.UTF8Encoding]::new($false)

# ToByteChars — a readable source literal, respelled as the byte-chars of its
# UTF-8 encoding, so it can be concatenated with and compared against file
# content without leaving the byte domain.
function ToByteChars([string]$s) { return $L1.GetString($U8.GetBytes($s)) }

$StdOut = [Console]::OpenStandardOutput()
$StdErr = [Console]::OpenStandardError()

# Write-ByteChars — raw byte write. Never [Console]::Out: OutputEncoding would
# re-encode anything above 0x7F and break byte parity with the bash leg.
function Write-ByteChars($stream, [string]$byteChars) {
  $b = $L1.GetBytes($byteChars)
  $stream.Write($b, 0, $b.Length)
  $stream.Flush()
}

function Err([string]$msg) { Write-ByteChars $StdErr ($msg + "`n") }

# Non-ASCII literals, converted once.
$SECT     = ToByteChars ' § '
$EMDASH   = ToByteChars ' — '
$NV_HASH  = ToByteChars 'path#Heading — not verified'
$NV_SECT  = ToByteChars 'path § Heading — not verified'
$NV_LINE  = ToByteChars 'path:line — not verified'

$Root = if ($args.Count -ge 1) { [string]$args[0] } else { (Get-Location).Path }
if ($Root.EndsWith('/')) { $Root = $Root.Substring(0, $Root.Length - 1) }
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
  Err ('ERROR check-citations: not a directory: ' + (ToByteChars $Root))
  exit 1
}
$RootFull = (Resolve-Path -LiteralPath $Root).Path
if ($RootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
  $RootFull = $RootFull.Substring(0, $RootFull.Length - 1)
}

# Walk exclusions, in report order. A trailing '/' means "this prefix"; anything
# else is an exact repo-relative path. All ASCII, so no conversion is needed.
$Ex1 = 'docs/superpowers/'; $ExN1 = 0
$Ex2 = 'docs/briefs/';      $ExN2 = 0
$Ex3 = 'CHANGELOG.md';      $ExN3 = 0
$Ex4 = 'tests/fixtures/';   $ExN4 = 0
$Ex5 = '.milestone-config/worktrees/'; $ExN5 = 0
$Ex6 = '.milestone-feeder/';           $ExN6 = 0

$ok = 0
$failed = 0
$unverified = 0
$out = [System.Collections.Generic.List[string]]::new()

# The path-class run, as the maximal-munch regex equivalent of the bash leg's
# `${rest%%[!A-Za-z0-9._/-]*}` peel. Compiled once; explicit ASCII ranges, so it
# never widens to Unicode letters the way \w would, and it runs over byte-chars,
# so a multibyte sequence is several non-matching bytes exactly as it is to the
# bash leg.
$RunRx = [regex]::new('[A-Za-z0-9._/-]+', [System.Text.RegularExpressions.RegexOptions]::Compiled)

# Test-CitablePath — discriminator rules 2 and 3 (see the .sh header).
function Test-CitablePath([string]$p) {
  if ($p.IndexOf('/') -lt 0) { return $false }
  if ($p.StartsWith('/')) { return $false }
  $b = $p.Substring($p.LastIndexOf('/') + 1)
  $dot = $b.LastIndexOf('.')
  if ($dot -lt 0) { return $false }
  $e = $b.Substring($dot + 1)
  if ($e.Length -lt 1 -or $e.Length -gt 4) { return $false }
  $hasLetter = $false
  foreach ($c in $e.ToCharArray()) {
    if (($c -ge 'a' -and $c -le 'z') -or ($c -ge 'A' -and $c -le 'Z')) { $hasLetter = $true }
    elseif ($c -ge '0' -and $c -le '9') { }
    else { return $false }
  }
  return $hasLetter
}

# Get-BalancedEnd — index of the ')' closing a paren opened just before $t, or
# -1 when the parens never balance on this line.
function Get-BalancedEnd([string]$t) {
  $d = 1
  for ($i = 0; $i -lt $t.Length; $i++) {
    $c = $t[$i]
    if ($c -eq '(') { $d++ }
    elseif ($c -eq ')') { $d--; if ($d -eq 0) { return $i } }
  }
  return -1
}

# Get-HeadingEnd — where a heading citation's text stops. $mode is 'span' when
# the path was immediately preceded by a backtick and 'bare' otherwise. See the
# .sh leg's heading_end for why the two are bounded differently: inside a code
# span the closing backtick is the EXACT bound and nothing else may cut a
# heading that legitimately holds quotes, commas or parentheses; bare in prose
# there is no exact bound, so the stop is conservative.
function Get-HeadingEnd([string]$t, [string]$mode) {
  $d = 0
  for ($i = 0; $i -lt $t.Length; $i++) {
    $c = $t[$i]
    if ($c -eq '`') { return $i }
    if ($mode -eq 'bare') {
      if ($c -eq '(') { $d++ }
      elseif ($c -eq ')') { if ($d -eq 0) { return $i }; $d-- }
      elseif ($c -eq ',' -or $c -eq ';' -or $c -eq '"') { return $i }
      # 5 byte-chars: space + the 3-byte UTF-8 em-dash + space, the same 5-byte
      # slice the bash leg compares.
      if (($i + 5) -le $t.Length -and $t.Substring($i, 5) -ceq $EMDASH) { return $i }
    }
  }
  return $t.Length
}

# Read-AllByteChars — a file's raw bytes as byte-chars, or $null when it cannot
# be read. No encoding detection, no BOM handling, no replacement character.
function Read-AllByteChars([string]$path) {
  # READ half of the LIST/READ split: refuse to OPEN a 0-byte entry. A FIFO, a
  # socket and a device node all stat as 0 and opening one blocks forever; a
  # 0-byte regular file has nothing to return anyway. Mirrors the bash leg's
  # `[ -s ... ]` guards exactly.
  $len = -1
  try { $len = [System.IO.FileInfo]::new($path).Length } catch { return $null }
  if ($len -le 0) { return '' }
  try { return $L1.GetString([System.IO.File]::ReadAllBytes($path)) } catch { return $null }
}

# Read-Lines — the bash leg's `while IFS= read -r line` model: split on LF ONLY
# (a lone CR is ordinary text), and treat a trailing LF as a terminator rather
# than the start of an empty line. A leading BOM is NOT stripped, because the
# bash leg's scanner does not strip one either.
function Read-Lines([string]$path) {
  $raw = Read-AllByteChars $path
  if ($null -eq $raw) { return $null }
  if ($raw.Length -eq 0) { return @() }
  $lines = [System.Collections.Generic.List[string]]::new($raw.Split([char]10))
  if ($raw.EndsWith("`n")) { $lines.RemoveAt($lines.Count - 1) }
  return $lines
}

# Get-MatchCount — matching LINE count, byte-exact with `grep -a -c -F`.
function Get-MatchCount([string]$path, [string]$anchor) {
  $raw = Read-AllByteChars $path
  if ($null -eq $raw -or $raw.Length -eq 0) { return 0 }
  $n = 0
  foreach ($l in $raw.Split([char]10)) {
    if ($l.Contains($anchor, [System.StringComparison]::Ordinal)) { $n++ }
  }
  return $n
}

# Get-TreeFiles — the record-stream equivalent of
# `find <root> -name .git -prune -o -type f -print`. Fills $relKeys with the
# byte-char relative path and $fullVals with the real path to open. See the
# header's walk note for the regular-file test and the unreadable-directory
# behavior.
function Get-TreeFiles([string]$dir, [string]$prefix, $relKeys, $fullVals) {
  $entries = $null
  try { $entries = [System.IO.Directory]::GetFileSystemEntries($dir) } catch { return }
  foreach ($entry in $entries) {
    $name = [System.IO.Path]::GetFileName($entry)
    if ($name -eq '.git') { continue }
    $rel = if ($prefix -eq '') { $name } else { "$prefix/$name" }
    $info = $null
    try {
      $info = [System.IO.FileInfo]::new($entry)
      $attrs = $info.Attributes
    } catch { continue }
    if ($attrs -band [System.IO.FileAttributes]::ReparsePoint) { continue }
    if ($attrs -band [System.IO.FileAttributes]::Directory) {
      Get-TreeFiles $entry $rel $relKeys $fullVals
    } else {
      # LIST is deliberately looser than READ — see the walk note in the header.
      $relKeys.Add((ToByteChars $rel))
      $fullVals.Add($entry)
    }
  }
}

$relKeys = [System.Collections.Generic.List[string]]::new()
$fullVals = [System.Collections.Generic.List[string]]::new()
Get-TreeFiles $RootFull '' $relKeys $fullVals
$keys = $relKeys.ToArray()
$vals = $fullVals.ToArray()
# Ordinal over byte-chars IS a byte sort, so this matches `LC_ALL=C sort`.
[array]::Sort($keys, $vals, [System.StringComparer]::Ordinal)

# The containment set: every walked path, keyed by its byte-char relative form.
# Exclusions govern a file as a citation SOURCE, never as a citation TARGET, so
# this map is built BEFORE the exclusion filter.
$inTree = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
for ($i = 0; $i -lt $keys.Length; $i++) {
  if (-not $inTree.ContainsKey($keys[$i])) { $inTree.Add($keys[$i], $vals[$i]) }
}

$keptRel = [System.Collections.Generic.List[string]]::new()
$keptFull = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $keys.Length; $i++) {
  $rel = $keys[$i]
  if ($rel.StartsWith($Ex1, [System.StringComparison]::Ordinal)) { $ExN1++; continue }
  if ($rel.StartsWith($Ex2, [System.StringComparison]::Ordinal)) { $ExN2++; continue }
  if ($rel -ceq $Ex3) { $ExN3++; continue }
  if ($rel.StartsWith($Ex4, [System.StringComparison]::Ordinal)) { $ExN4++; continue }
  if ($rel.StartsWith($Ex5, [System.StringComparison]::Ordinal)) { $ExN5++; continue }
  if ($rel.StartsWith($Ex6, [System.StringComparison]::Ordinal)) { $ExN6++; continue }
  $keptRel.Add($rel)
  $keptFull.Add($vals[$i])
}

$out.Add("EXCLUDED`t$Ex1`tskipped=$ExN1")
$out.Add("EXCLUDED`t$Ex2`tskipped=$ExN2")
$out.Add("EXCLUDED`t$Ex3`tskipped=$ExN3")
$out.Add("EXCLUDED`t$Ex4`tskipped=$ExN4")
$out.Add("EXCLUDED`t$Ex5`tskipped=$ExN5")
$out.Add("EXCLUDED`t$Ex6`tskipped=$ExN6")

# ---------------------------------------------------------------------------
# Scan. One pass per line, left to right: take the next path-class run, test it
# as a path, then classify on the byte-chars that FOLLOW it. `$consumedTo` is
# this leg's spelling of the bash loop's shrinking `$rest`: a run that starts
# inside an already-consumed citation is skipped, so an anchor's own inner
# tokens are never re-read as citations.
# ---------------------------------------------------------------------------
for ($f = 0; $f -lt $keptRel.Count; $f++) {
  $rel = $keptRel[$f]
  $lines = Read-Lines $keptFull[$f]
  if ($null -eq $lines) { continue }
  $lno = 0
  foreach ($rawLine in $lines) {
    $lno++
    $line = if ($rawLine.EndsWith("`r")) { $rawLine.Substring(0, $rawLine.Length - 1) } else { $rawLine }
    $consumedTo = 0
    foreach ($m in $RunRx.Matches($line)) {
      if ($m.Index -lt $consumedTo) { continue }
      $run = $m.Value
      if (-not (Test-CitablePath $run)) { continue }
      # A backtick immediately before the run opens a code span, which is the
      # only exact bound a heading citation ever has (see Get-HeadingEnd).
      $hmode = if ($m.Index -gt 0 -and $line[$m.Index - 1] -eq '`') { 'span' } else { 'bare' }
      $after = $m.Index + $m.Length
      $rest = $line.Substring($after)
      if ($rest.StartsWith(' (', [System.StringComparison]::Ordinal)) {
        $body = $rest.Substring(2)
        $end = Get-BalancedEnd $body
        if ($end -le 0) { continue }
        $anchor = $body.Substring(0, $end)
        $consumedTo = $after + 2 + $end + 1
        $n = if ($inTree.ContainsKey($run)) { Get-MatchCount $inTree[$run] $anchor } else { 0 }
        if ($n -eq 1) {
          $out.Add("OK`t${rel}:${lno}`t$run ($anchor)")
          $ok++
        } else {
          $out.Add("FAIL`t${rel}:${lno}`t$run ($anchor)`t$n matches")
          $failed++
        }
      }
      elseif ($rest.StartsWith('#', [System.StringComparison]::Ordinal)) {
        $h = $rest.Substring(1)
        $end = Get-HeadingEnd $h $hmode
        $head = $h.Substring(0, $end).TrimEnd(' ', "`t")
        $consumedTo = $after + 1 + $end
        $out.Add("UNVERIFIED`t${rel}:${lno}`t$run#$head`t$NV_HASH")
        $unverified++
      }
      elseif ($rest.StartsWith($SECT, [System.StringComparison]::Ordinal)) {
        $h = $rest.Substring($SECT.Length)
        $end = Get-HeadingEnd $h $hmode
        $head = $h.Substring(0, $end).TrimEnd(' ', "`t")
        $consumedTo = $after + $SECT.Length + $end
        $out.Add("UNVERIFIED`t${rel}:${lno}`t$run$SECT$head`t$NV_SECT")
        $unverified++
      }
      elseif ($rest.Length -ge 2 -and $rest[0] -eq ':' -and $rest[1] -ge '0' -and $rest[1] -le '9') {
        $j = 1
        while ($j -lt $rest.Length -and $rest[$j] -ge '0' -and $rest[$j] -le '9') { $j++ }
        $cite = $run + ':' + $rest.Substring(1, $j - 1)
        if (($j + 1) -lt $rest.Length -and $rest[$j] -eq '-' -and $rest[$j + 1] -ge '0' -and $rest[$j + 1] -le '9') {
          $k = $j + 1
          while ($k -lt $rest.Length -and $rest[$k] -ge '0' -and $rest[$k] -le '9') { $k++ }
          $cite = $cite + '-' + $rest.Substring($j + 1, $k - $j - 1)
          $j = $k
        }
        $consumedTo = $after + $j
        $out.Add("UNVERIFIED`t${rel}:${lno}`t$cite`t$NV_LINE")
        $unverified++
      }
    }
  }
}

$out.Add("TOTALS`tunverified=$unverified`texcluded-files=$($ExN1 + $ExN2 + $ExN3 + $ExN4 + $ExN5 + $ExN6)")
$out.Add("SUMMARY`tok=$ok`tfailed=$failed")

# Join with LF and append a single trailing newline — byte-parity with the .sh
# leg's printf stream, independent of the host's default line ending.
Write-ByteChars $StdOut (($out -join "`n") + "`n")
if ($failed -ne 0) { exit 1 }
