#!/usr/bin/env pwsh
# milestone-driver — diff-scoped repo file-index resolver (issue #318).
# stdin: JSON {"files":["<repo-relative-path>", ...]}. stdout: one line per input
# file, IN INPUT ORDER — "<path> → <purpose>[ (callers: a, b)][ (symbols: x, y)]".
# Fail-open (twin of scripts/build-file-index.sh): malformed/empty stdin, or zero
# emitted lines => empty stdout, stderr "none", exit 0. Never a non-zero exit,
# never a crash. Named paths that don't exist on disk or resolve outside the repo
# root (cwd) are skipped, not fatal. Output bytes are written UTF-8 (no BOM) so
# the ` -> ` (U+2192) separator and em-dash survive redirection on any host.

function Emit-None {
  $b = [System.Text.Encoding]::UTF8.GetBytes('none')
  $se = [Console]::OpenStandardError(); $se.Write($b, 0, $b.Length); $se.Flush()
  exit 0
}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrEmpty($raw)) { Emit-None }
try { $o = $raw | ConvertFrom-Json -ErrorAction Stop } catch { Emit-None }
if ($null -eq $o) { Emit-None }
if (-not (@($o.PSObject.Properties.Name) -contains 'files')) { Emit-None }
$files = if ($null -eq $o.files) { @() } else { @($o.files) }

$rootFull = [System.IO.Path]::GetFullPath((Get-Location).ProviderPath)
$sep = ' ' + [char]0x2192 + ' '   # " → " (U+2192, one space each side)
$bt = [char]0x60                  # backtick

# sourceGlobs: read from cwd's .milestone-config/driver.json when readable, else
# fail-open to the literal defaults (orchestrator decision, issue #318).
$srcDirs = @()
$prof = '.milestone-config/driver.json'
if (Test-Path -LiteralPath $prof -PathType Leaf) {
  try {
    $pj = Get-Content -LiteralPath $prof -Raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($g in @($pj.sourceGlobs)) {
      if ($null -eq $g) { continue }
      $d = (([string]$g) -replace '\*.*$', '').TrimEnd('/')   # "skills/**" -> "skills"
      if ($d -ne '') { $srcDirs += $d }
    }
  } catch { $srcDirs = @() }
}
if ($srcDirs.Count -eq 0) { $srcDirs = @('skills', 'agents', 'hooks') }

# Enumerate every file under the source trees (repo-relative, forward-slash).
$srcFiles = @()
foreach ($d in $srcDirs) {
  if (Test-Path -LiteralPath $d -PathType Container) {
    Get-ChildItem -LiteralPath $d -Recurse -File | ForEach-Object {
      $srcFiles += ($_.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/')
    }
  }
}

function Leaf([string]$path) { return $path.Substring($path.LastIndexOfAny([char[]]@('/', '\')) + 1) }

function Is-BlockIndicator([string]$v) { return @('>-', '>', '|', '|-') -contains $v }

# The two encodings Sort-Uniq's byte keys are built on. Latin1 is the
# byte<->char bijection: every byte 0x00-0xFF maps to the char of the same value
# and back, losslessly (scripts/check-citations.ps1 (Latin1 is the byte<->char)).
$SUU8 = [System.Text.Encoding]::UTF8
$SUL1 = [System.Text.Encoding]::Latin1
# Get-ByteKey — a path respelled as the byte-chars of its UTF-8 encoding, so
# StringComparer.Ordinal over the result compares BYTES.
function Get-ByteKey([string]$s) { return $SUL1.GetString($SUU8.GetBytes($s)) }

# De-duplicated string list in CODEPOINT ORDER, parity with the .sh twin's
# `LC_ALL=C sort -u`. The keys are each item's UTF-8 BYTES as byte-chars, so
# Ordinal over them IS a byte sort, and UTF-8 byte order IS codepoint order — the
# byte-domain model scripts/check-citations.ps1 (THE SORT) already ships. Ordinal
# over the DECODED strings would NOT do: that is UTF-16 code-unit order, which
# ranks an astral char (lead surrogate U+D800-DBFF) BEFORE every U+E000-FFFF char
# where codepoint order ranks it after, so a `(callers: …)` list holding both
# would come out in a different order on each leg. ASCII-only input agrees under
# both orders, so ASCII agreement is NOT evidence of parity: the pin is
# tests/build-file-index.cases.tsv (sort-order).
function Sort-Uniq([string[]]$items) {
  $set = [System.Collections.Generic.List[string]]::new()
  foreach ($x in $items) { if (-not $set.Contains($x)) { $set.Add($x) } }
  $arr = $set.ToArray()
  $bk = New-Object string[] $arr.Length
  for ($i = 0; $i -lt $arr.Length; $i++) { $bk[$i] = Get-ByteKey $arr[$i] }
  [Array]::Sort($bk, $arr, [System.StringComparer]::Ordinal)
  return , $arr
}

# Truncate at the first ". " outside a backtick span, keeping the sentence THROUGH
# the period; else keep whole. Char-scan mirrors the bash byte-scan twin (the
# result is the same logical prefix regardless of index units).
function First-Sentence([string]$s) {
  $inbt = $false
  for ($i = 0; $i -lt $s.Length; $i++) {
    $c = $s[$i]
    if ($c -eq $bt) { $inbt = -not $inbt; continue }
    if (-not $inbt -and $c -eq '.') {
      if (($i + 1) -lt $s.Length -and $s[$i + 1] -eq ' ') { return $s.Substring(0, $i + 1) }
    }
  }
  return $s
}

# YAML-frontmatter description value with the folded/literal-scalar rule: same-line
# value when non-empty and not a bare block indicator (>- > | |-), else the first
# non-empty line FOLLOWING the key.
function Purpose-Frontmatter([string]$path) {
  $lines = [System.IO.File]::ReadAllLines($path)
  $inFm = $false; $want = $false
  foreach ($line in $lines) {
    if (-not $inFm) { if ($line -eq '---') { $inFm = $true }; continue }
    if ($want) {
      if ($line -eq '---') { return '' }
      $t = $line.Trim()
      if ($t -ne '') { return $t }
      continue
    }
    if ($line -eq '---') { break }
    if ($line -match '^description:') {
      $val = ($line -replace '^description:', '').Trim()
      if ($val -eq '' -or (Is-BlockIndicator $val)) { $want = $true; continue }
      return $val
    }
  }
  return ''
}

# The file's line-2 header comment, stripping leading '#' markers and whitespace.
function Purpose-Header([string]$path) {
  $lines = [System.IO.File]::ReadAllLines($path)
  if ($lines.Count -lt 2) { return '' }
  $l = $lines[1]
  while ($l.StartsWith('#')) { $l = $l.Substring(1) }
  return $l.Trim()
}

# Top-level function names in a .sh/.ps1 — BOTH bash shape `name() {` AND pwsh
# shape `function Name` matched in this leg. Deduped + byte-sorted.
function Extract-Symbols([string]$path) {
  $names = [System.Collections.Generic.List[string]]::new()
  foreach ($line in [System.IO.File]::ReadAllLines($path)) {
    if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{') { $names.Add($matches[1]) }
    if ($line -match '^function\s+([A-Za-z_][A-Za-z0-9_-]*)') { $names.Add($matches[1]) }
  }
  return Sort-Uniq $names.ToArray()
}

# Combined callers UNION callees (see the .sh twin), deduped + byte-sorted.
function File-Relations([string]$p, [string]$pFull) {
  $pbase = Leaf $p
  $pContent = [System.IO.File]::ReadAllText($pFull)
  $rel = [System.Collections.Generic.List[string]]::new()
  foreach ($g in $srcFiles) {
    if ($g -eq '' -or $g -eq $p) { continue }
    $gbase = Leaf $g
    $gContent = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($rootFull, $g))
    $callee = $pContent.Contains($g) -or $pContent.Contains($gbase)
    $caller = $gContent.Contains($p) -or $gContent.Contains($pbase)
    if ($callee -or $caller) { $rel.Add($g) }
  }
  return Sort-Uniq $rel.ToArray()
}

$sb = [System.Text.StringBuilder]::new()
$emitted = 0
foreach ($pRaw in $files) {
  if ($null -eq $pRaw) { continue }
  $p = [string]$pRaw
  if ($p -eq '') { continue }
  # Skip absolute paths and paths that resolve outside the repo root (cwd).
  if ([System.IO.Path]::IsPathRooted($p)) { continue }
  $full = $null
  try { $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootFull, $p)) } catch { continue }
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
  $rootPrefix = $rootFull.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
  if (-not $full.StartsWith($rootPrefix, [System.StringComparison]::Ordinal)) { continue }

  $base = Leaf $p
  $dot = $base.LastIndexOf('.'); $ext = if ($dot -ge 0) { $base.Substring($dot + 1) } else { '' }
  if ($base -eq 'SKILL.md') { $purpose = Purpose-Frontmatter $full }
  elseif ($p -match '(^|/)agents/[^/]*\.md$') { $purpose = Purpose-Frontmatter $full }
  elseif ($ext -eq 'sh' -or $ext -eq 'ps1') { $purpose = Purpose-Header $full }
  else { $purpose = '(unclassified)' }
  if ($purpose -eq '') { $purpose = '(unclassified)' }
  $purpose = First-Sentence $purpose

  $line = "$p$sep$purpose"

  $rels = File-Relations $p $full
  if ($rels.Count -gt 0) { $line += ' (callers: ' + ($rels -join ', ') + ')' }

  if ($ext -eq 'sh' -or $ext -eq 'ps1') {
    $syms = Extract-Symbols $full
    if ($syms.Count -gt 0) { $line += ' (symbols: ' + ($syms -join ', ') + ')' }
  }

  [void]$sb.Append($line).Append("`n")
  $emitted++
}

if ($emitted -eq 0) { Emit-None }
$bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
$so = [Console]::OpenStandardOutput(); $so.Write($bytes, 0, $bytes.Length); $so.Flush()
exit 0
