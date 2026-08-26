#!/usr/bin/env pwsh
# milestone-driver - expand a profile's domainSkills entries into exact,
# invocable plugin:skill names (issue #589). Twin of expand-domain-skills.sh;
# the argument contract, the entry shapes, the version-directory selection rule,
# and the fail-open exit 0 are documented once, in the .sh header.
# Byte parity is the contract this leg is held to: same stdout, same stderr,
# byte for byte, for the same cache tree and the same arguments.
param(
  [Parameter(Position = 0)][string]$Root = '',
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Entries = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($null -eq $Entries) { $Entries = @() }

# A leading `~/` reaches this leg VERBATIM - no shell expands it here, and .NET
# never treats `~` as the home directory, so
# `Directory.Exists('~/.claude/plugins/cache')` is False and every wildcard would
# go unresolved on Windows, the one OS this twin exists for. $env:HOME first so
# the golden matrix can fake it anywhere; the $HOME automatic variable is the
# fallback Windows needs, where PowerShell sets it from the user profile. The
# .sh twin resolves the same `~/<path>` shape, and only that shape, so both legs
# read one literal alike.
if ($Root.StartsWith('~/', [System.StringComparison]::Ordinal)) {
  $homeDir = if ($env:HOME) { $env:HOME } else { $HOME }
  $Root = $homeDir + '/' + $Root.Substring(2)
}

# Byte domain, matching the .sh twin's LC_ALL=C. Latin1 is the byte<->char
# bijection; UTF8 turns a decoded .NET string into its byte-char spelling, so
# StringComparer.Ordinal over the result compares BYTES and the raw write below
# reproduces the original UTF-8 bytes exactly
# (.project/conventions.md (Sorting or comparing strings in a pwsh twin)).
# NEVER bare Ordinal (UTF-16 code-unit order) and NEVER Sort-Object (culture order).
$L1 = [System.Text.Encoding]::Latin1
$U8 = [System.Text.UTF8Encoding]::new($false)
function Get-ByteKey([string]$s) { return $L1.GetString($U8.GetBytes($s)) }

$StdOut = [Console]::OpenStandardOutput()
$StdErr = [Console]::OpenStandardError()
# Raw byte write. Never [Console]::Out: OutputEncoding would re-encode anything
# above 0x7F and break byte parity with the bash leg
# (scripts/check-citations.ps1 (Write-ByteChars - raw byte write)).
function Write-ByteChars($stream, [string]$byteChars) {
  $b = $L1.GetBytes($byteChars)
  $stream.Write($b, 0, $b.Length)
  $stream.Flush()
}

# Get-ChildDirNames - immediate child directory names in the bash twin's `*/`
# glob ORDER, dot-prefixed ones skipped. Directory.GetDirectories order is
# UNSPECIFIED by .NET, and order is part of the answer: Select-VersionDir keeps
# the FIRST of two names that tie on magnitude (`1.0` vs `1.0.0`, `1.0` vs
# `01.0`, which a missing-component-is-0 compare scores equal), so an
# unspecified order lets the two legs pick different directories on one tree.
# The sort key carries the TRAILING SLASH the bash glob's own key has - `1.0.0/`
# before `1.0/`, `aaa-b/` before `aaa/` - without which the two orders diverge
# wherever one name is a prefix of another. Byte domain via Get-ByteKey, never
# bare Ordinal. An absent, unreadable, or not-a-directory path yields none: that
# is the fail-open branch.
function Get-ChildDirNames([string]$path) {
  $out = New-Object System.Collections.Generic.List[string]
  try {
    if (-not [System.IO.Directory]::Exists($path)) { return , $out.ToArray() }
    foreach ($d in [System.IO.Directory]::GetDirectories($path)) {
      $n = [System.IO.Path]::GetFileName($d)
      if ($n.StartsWith('.', [System.StringComparison]::Ordinal)) { continue }
      $out.Add($n)
    }
  } catch { return , @() }
  $names = $out.ToArray()
  $keys = New-Object string[] $names.Length
  for ($i = 0; $i -lt $names.Length; $i++) { $keys[$i] = Get-ByteKey ($names[$i] + '/') }
  [Array]::Sort($keys, $names, [System.StringComparer]::Ordinal)
  return , $names
}

function Test-VersionName([string]$n) { return ($n -match '^[0-9]+(\.[0-9]+)+$') }

# Remove-LeadingZeros - the digit string's magnitude spelling, so `08` and `8`
# compare as one value.
function Remove-LeadingZeros([string]$d) {
  $t = $d.TrimStart('0')
  if ($t.Length -eq 0) { return '0' }
  return $t
}

# Compare-VersionGt - $true when dotted-numeric $a ranks above $b, component by
# component by MAGNITUDE. A missing component counts as 0. NEVER [long]::Parse: a
# component wider than Int64 throws under $ErrorActionPreference = 'Stop', which
# exits 1 with empty stdout and loses the exact names the caller passed alongside,
# breaking the fail-open contract the header states. Zeros stripped, a longer
# digit string is the larger value and equal lengths compare Ordinal - the
# components are ASCII digits by Test-VersionName, where Ordinal IS byte order.
function Compare-VersionGt([string]$a, [string]$b) {
  $ac = $a -split '\.'
  $bc = $b -split '\.'
  $n = [Math]::Max($ac.Count, $bc.Count)
  for ($i = 0; $i -lt $n; $i++) {
    $x = if ($i -lt $ac.Count) { Remove-LeadingZeros $ac[$i] } else { '0' }
    $y = if ($i -lt $bc.Count) { Remove-LeadingZeros $bc[$i] } else { '0' }
    if ($x.Length -ne $y.Length) { return ($x.Length -gt $y.Length) }
    $c = [System.StringComparer]::Ordinal.Compare($x, $y)
    if ($c -ne 0) { return ($c -gt 0) }
  }
  return $false
}

# Select-VersionDir - the selected child directory NAME, or '' when the plugin
# directory holds no child directory at all.
function Select-VersionDir([string]$pdir) {
  $best = ''; $haveVersion = $false; $byteLast = ''; $byteLastKey = ''
  foreach ($n in (Get-ChildDirNames $pdir)) {
    $k = Get-ByteKey $n
    if ($byteLast.Length -eq 0 -or [System.StringComparer]::Ordinal.Compare($k, $byteLastKey) -gt 0) {
      $byteLast = $n; $byteLastKey = $k
    }
    if (Test-VersionName $n) {
      if ((-not $haveVersion) -or (Compare-VersionGt $n $best)) { $best = $n; $haveVersion = $true }
    }
  }
  if ($haveVersion) { return $best }
  return $byteLast
}

function Write-Unresolved([string]$entry) {
  Write-ByteChars $StdErr ((Get-ByteKey ('unresolved: ' + $entry)) + "`n")
}

$resolved = New-Object System.Collections.Generic.List[string]
# Ordinal at every string-matching site below, and in Get-ChildDirNames above:
# .NET's IndexOf(string), EndsWith(string) and StartsWith(string) default to
# CurrentCulture, which under ICU is collation, not byte matching, while the .sh
# twin's `case` is bytes. Contains(string) is ordinal by contract and takes no
# argument; TrimStart(char) and -match/-split/-replace are culture-free too.
# PowerShell's own -eq/-ceq are InvariantCulture compares under ICU, NOT byte
# compares (`"a$([char]0x00AD)b" -ceq "ab"` is True), so every equality here is
# either `.Length -eq 0` or StringComparer.Ordinal
# (.project/conventions.md (Sorting or comparing strings in a pwsh twin)).
foreach ($entry in $Entries) {
  if ($entry.IndexOf('*', [System.StringComparison]::Ordinal) -lt 0) { $resolved.Add($entry); continue }
  # From here the entry holds a `*`: only the exact `<plugin>:*` shape expands.
  $plugin = ''
  if ($entry.EndsWith(':*', [System.StringComparison]::Ordinal)) { $plugin = $entry.Substring(0, $entry.Length - 2) }
  if ($plugin.Length -eq 0 -or $plugin.Contains('*') -or $plugin.Contains(':')) {
    Write-Unresolved $entry; continue
  }
  $found = $false
  foreach ($mp in (Get-ChildDirNames $Root)) {
    $pdir = Join-Path $Root $mp $plugin
    if (-not [System.IO.Directory]::Exists($pdir)) { continue }
    $sel = Select-VersionDir $pdir
    if ($sel.Length -eq 0) { continue }
    $skillsDir = Join-Path $pdir $sel 'skills'
    foreach ($sk in (Get-ChildDirNames $skillsDir)) {
      if (-not [System.IO.File]::Exists((Join-Path $skillsDir $sk 'SKILL.md'))) { continue }
      $resolved.Add($plugin + ':' + $sk)
      $found = $true
    }
  }
  if (-not $found) { Write-Unresolved $entry }
}

# Sort + dedupe in the byte domain - parity with the twin's `sort -u` under
# LC_ALL=C. The sort keys ARE the emitted bytes, so they are written directly.
$arr = $resolved.ToArray()
$keys = New-Object string[] $arr.Length
for ($i = 0; $i -lt $arr.Length; $i++) { $keys[$i] = Get-ByteKey $arr[$i] }
[Array]::Sort($keys, [System.StringComparer]::Ordinal)
$sb = New-Object System.Text.StringBuilder
$prev = $null
foreach ($k in $keys) {
  if ($null -ne $prev -and [System.StringComparer]::Ordinal.Compare($k, $prev) -eq 0) { continue }
  [void]$sb.Append($k).Append("`n")
  $prev = $k
}
Write-ByteChars $StdOut $sb.ToString()
exit 0
