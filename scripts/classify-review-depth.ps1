#!/usr/bin/env pwsh
# milestone-driver - review-depth classifier (issue #598).
# Behavior-identical pwsh sibling of scripts/classify-review-depth.sh. That
# file's header carries the full design rationale: why the safe direction is
# more review and every degrade emits `standard`, what the candidate set is and
# what it deliberately is not, why the delta is read against `HEAD` rather than
# bare, why `--no-renames`, `--full-name` and `core.quotePath=false` are pinned
# and what that last one does NOT cover, what counts as a new file, why the twin
# test is set-membership rather than an existence check, why hooks/** is checked
# against every candidate and ahead of the config read, why the path-shape guard
# rejects on a plain `..` substring and on git's C-quoted spelling, why a
# rejected candidate floors the verdict at `standard`, and what the
# three-wildcard glob subset is.
#
# Usage:   classify-review-depth.ps1 [REPO_ROOT]
# Output:  stdout is one newline-terminated verdict, `deep`, `standard` or
#          `shallow`. stderr carries a single reason token, and only when there
#          is a specific trigger to name: hooks:<path>, new-file:<path>,
#          twin:<path>, rejected-path:<path>, no-git, no-diff,
#          empty-candidates, no-config, or no-source-globs. Exit is ALWAYS 0.
#
# THE ONE TOKEN THIS LEG NEVER EMITS is `no-jq`. The bash leg reads sourceGlobs
# with jq and degrades when jq is absent; this leg reads it with
# ConvertFrom-Json and has no such dependency to lose - the same split
# `scripts/build-file-index.ps1 (sourceGlobs: read from cwd)` already carries.
# Every other token, and every verdict, is identical on both legs.
#
# ── THE BYTE DOMAIN ───────────────────────────────────────────────────────────
# Glob matching happens on BYTE-CHARS, not text: each path and each glob is
# respelled as the byte-chars of its UTF-8 encoding before the regex runs
# (`scripts/check-citations.ps1 (function ToByteChars)`). That is what keeps
# `?` and `[^/]` one BYTE wide here as well as under the bash leg's
# `LC_ALL=C grep -E`, so the two legs cannot disagree on a multibyte path. The
# text form is kept alongside for the reason token, because stderr must carry
# the path's real bytes and not the Latin-1 respelling of them.
#
# `\z` rather than `$` anchors the pattern: .NET's `$` also matches before a
# trailing newline, while the bash leg's `grep` matches a whole line. Git quotes
# a path holding a control character, so no candidate can contain a newline
# either way - `\z` just removes the question.
param(
  [string]$Root = (Get-Location).Path
)
# Continue, not Stop: git writes to stderr on an ordinary non-repo root, and
# that is a classification input here, not a failure.
$ErrorActionPreference = 'Continue'
# Force UTF-8 stdout (no BOM) so output is byte-identical to the .sh sibling,
# and so git's own output decodes as UTF-8 before Get-ByteKey re-encodes it.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Root = ($Root -replace '/+$', '')

# Latin1 is the byte<->char bijection: every byte 0x00-0xFF maps to the char of
# the same value and back, losslessly
# (`scripts/check-citations.ps1 (Latin1 is the byte<->char)`).
$U8 = [System.Text.Encoding]::UTF8
$L1 = [System.Text.Encoding]::Latin1
function Get-ByteKey([string]$s) { return $L1.GetString($U8.GetBytes($s)) }

function Emit([string]$verdict, [string]$reason) {
  [Console]::Out.Write($verdict + "`n")
  if (-not [string]::IsNullOrEmpty($reason)) { [Console]::Error.Write($reason) }
  exit 0
}

# Test-ValidPath -> $true when the path is repo-relative and forward-slash.
function Test-ValidPath([string]$p) {
  if ([string]::IsNullOrEmpty($p)) { return $false }
  if ($p.StartsWith('/', [StringComparison]::Ordinal)) { return $false }
  if ($p.StartsWith('~', [StringComparison]::Ordinal)) { return $false }
  if ($p.StartsWith('"', [StringComparison]::Ordinal)) { return $false }
  if ($p.Contains('..')) { return $false }
  if ($p -cmatch '^[A-Za-z]:/') { return $false }
  return $true
}

# Convert-GlobToRegex <byte-char glob> -> a regex body (no anchors), byte-wise.
$MetaChars = '.^$+()[]{}|\'
function Convert-GlobToRegex([string]$g) {
  $sb = New-Object System.Text.StringBuilder
  $i = 0
  while ($i -lt $g.Length) {
    $c = $g[$i]
    if ($c -ceq '*') {
      if ($i + 1 -lt $g.Length -and $g[$i + 1] -ceq '*') {
        if ($i + 2 -lt $g.Length -and $g[$i + 2] -ceq '/') {
          [void]$sb.Append('(.*/)?'); $i += 3
        } else {
          [void]$sb.Append('.*'); $i += 2
        }
      } else {
        [void]$sb.Append('[^/]*'); $i += 1
      }
      continue
    }
    if ($c -ceq '?') { [void]$sb.Append('[^/]'); $i += 1; continue }
    if ($MetaChars.IndexOf($c) -ge 0) { [void]$sb.Append('\').Append($c) }
    else { [void]$sb.Append($c) }
    $i += 1
  }
  return $sb.ToString()
}

# ---- 1. the candidate set, from git and from nothing else.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Emit 'standard' 'no-git' }

try {
  $delta = @(& git -C $Root -c core.quotePath=false --no-pager diff --no-color `
    --no-renames --name-status HEAD 2>$null)
  $rc = $LASTEXITCODE
} catch {
  $rc = 1
}
if ($rc -ne 0) { Emit 'standard' 'no-diff' }
try {
  $others = @(& git -C $Root -c core.quotePath=false ls-files --others `
    --exclude-standard --full-name 2>$null)
} catch {
  $others = @()
}

$candidates = New-Object 'System.Collections.Generic.List[string]'
$newSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$raw = 0
foreach ($line in $delta) {
  if ([string]::IsNullOrEmpty($line)) { continue }
  $raw++
  $t = $line.IndexOf("`t", [StringComparison]::Ordinal)
  if ($t -lt 0) { $status = $line; $p = $line } else { $status = $line.Substring(0, $t); $p = $line.Substring($t + 1) }
  [void]$candidates.Add($p)
  if ($status.StartsWith('A', [StringComparison]::Ordinal)) { [void]$newSet.Add($p) }
}
foreach ($line in $others) {
  if ([string]::IsNullOrEmpty($line)) { continue }
  $raw++
  [void]$candidates.Add($line)
  [void]$newSet.Add($line)
}
if ($raw -eq 0) { Emit 'standard' 'empty-candidates' }

# ---- 2. drop the candidates whose shape disqualifies them, keeping the first
# one dropped: step 6 floors the verdict at `standard` when there is one.
$valid = New-Object 'System.Collections.Generic.List[string]'
$validSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$rejected = $null
foreach ($p in $candidates) {
  if (-not (Test-ValidPath $p)) {
    if ($null -eq $rejected) { $rejected = $p }
    continue
  }
  [void]$valid.Add($p)
  [void]$validSet.Add($p)
}

# ---- 3. the hooks/** trigger, ahead of the config read. It needs neither
# sourceGlobs nor jq, and testing it afterwards would let a consumer repo with
# no driver.json degrade a hook change to `standard`, which is the one
# downgrade this trigger exists to make impossible.
foreach ($p in $valid) {
  if ($p.StartsWith('hooks/', [StringComparison]::Ordinal)) { Emit 'deep' ('hooks:' + $p) }
}

# ---- 4. sourceGlobs, read the way
# `scripts/build-file-index.ps1 (sourceGlobs: read from cwd)` reads it.
$prof = Join-Path $Root '.milestone-config/driver.json'
if (-not (Test-Path -LiteralPath $prof -PathType Leaf)) { Emit 'standard' 'no-config' }
try {
  $rawJson = [System.IO.File]::ReadAllText($prof)
} catch {
  Emit 'standard' 'no-config'
}
try {
  $pj = $rawJson | ConvertFrom-Json -ErrorAction Stop
} catch {
  $pj = $null
}
$reParts = @()
# `-is [Array]`, so a JSON scalar `"sourceGlobs": "scripts/**"` degrades instead
# of being wrapped by `@(...)` into a one-entry glob list. The bash leg's
# `.sourceGlobs[]?` yields nothing for a scalar and emits no-source-globs; this
# test is what keeps the two legs on the same token, and on the same verdict
# when that scalar would have matched.
if ($null -ne $pj -and $pj.sourceGlobs -is [System.Array]) {
  foreach ($g in $pj.sourceGlobs) {
    if ($null -eq $g) { continue }
    $gs = [string]$g
    if (-not (Test-ValidPath $gs)) { continue }
    $reParts += (Convert-GlobToRegex (Get-ByteKey $gs))
  }
}
if ($reParts.Count -eq 0) { Emit 'standard' 'no-source-globs' }
$rx = New-Object System.Text.RegularExpressions.Regex(('^(' + ($reParts -join '|') + ')\z'))

# ---- 5. the sourceGlobs-scoped deep triggers, most specific signal first.
# Within a trigger the first candidate in git's order wins, which is path order.
$src = New-Object 'System.Collections.Generic.List[string]'
foreach ($p in $valid) {
  if ($rx.IsMatch((Get-ByteKey $p))) { [void]$src.Add($p) }
}

foreach ($p in $src) {
  if ($newSet.Contains($p)) { Emit 'deep' ('new-file:' + $p) }
}

foreach ($p in $src) {
  $sib = ''
  if ($p.EndsWith('.sh', [StringComparison]::Ordinal)) {
    $sib = $p.Substring(0, $p.Length - 3) + '.ps1'
  } elseif ($p.EndsWith('.ps1', [StringComparison]::Ordinal)) {
    $sib = $p.Substring(0, $p.Length - 4) + '.sh'
  } else {
    continue
  }
  if (-not $validSet.Contains($sib)) { Emit 'deep' ('twin:' + $p) }
}

# ---- 6. no deep trigger fired. A rejected candidate is read before the
# sourceGlobs verdict: it is the one candidate whose depth is unknown, and it
# is the reason this run cannot claim `shallow`.
if ($null -ne $rejected) { Emit 'standard' ('rejected-path:' + $rejected) }
if ($src.Count -gt 0) { Emit 'standard' '' }
Emit 'shallow' ''
