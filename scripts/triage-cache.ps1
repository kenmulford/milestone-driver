#!/usr/bin/env pwsh
# milestone-driver - triage-cache mechanics, extracted from skills/triage/SKILL.md
# Steps 2.5 and 6.5 (issue #441).
#
# Usage:
#   triage-cache.ps1 query <keys|edges> <owner> <repo> <n>...
#   triage-cache.ps1 lookup      <repo-root> <graphql-response.json>
#   triage-cache.ps1 check-edges <repo-root> <graphql-response.json>
#   triage-cache.ps1 write       <repo-root> <entries.json> <graphql-response.json>
#
# Behavior twin of scripts/triage-cache.sh - see that file's header for the full
# record contract, the degradation rules, the exit codes, and why `write` takes
# the SAVED Step 2.5 keys response and stamps each entry's `key` itself (#462).
# Every subcommand emits BYTE-IDENTICAL stdout and stderr on both legs;
# tests/triage-cache.test.{sh,ps1} drive the same cases table against the same
# goldens to hold that - EXCEPT for one hazard the table cannot express: an argv
# value containing a NEWLINE. The table's args column is a space-separated word
# list, so no row can carry one, and .NET's `$` anchor matches before a trailing
# newline while the .sh twin's `case` patterns do not. Every regex validator here
# therefore anchors with \z, never $; that discipline is the only thing holding
# the contract on that path. Two documented leg differences, both structural:
#   - SKIP<TAB>no-jq is unreachable here. This leg parses JSON with built-in
#     .NET types and has no external-tool dependency at all, exactly as
#     scripts/write-cost-record.ps1 has none where its .sh twin needs jq.
#   - The cache FILE this leg writes is semantically identical to the .sh twin's
#     but not byte-identical (the two serializers indent and escape
#     differently). Only stdout/stderr is byte-pinned; the file is asserted by
#     parsed content on both legs, the same call
#     tests/write-cost-record.test.ps1 (tiny sub-1e-4 costUsd asserted by NUMERIC VALUE) makes.
#
# System.Text.Json, NOT ConvertFrom-Json / ConvertTo-Json. ConvertFrom-Json
# COERCES any ISO-8601-shaped string into a [datetime], which breaks this script
# twice over and both times silently:
#   - the cache key embeds lastEditedAt, so `$x.lastEditedAt` came back as a
#     [datetime] and interpolated to the CULTURE format ("08/01/2026 00:00:00"),
#     making every live key mismatch its cached twin - a permanent 100% miss
#     rate that still exits 0 and still looks like a working cache;
#   - `write` round-trips entries it does not touch, so every `triaged_at` an
#     existing entry carried would be rewritten in .NET's date format, silently
#     rewriting data the .sh twin preserves verbatim.
# JsonElement.GetString() returns the exact source text, and JsonElement.WriteTo
# re-emits untouched values byte-for-byte, so neither failure can recur here.
# (PowerShell 7.5 added `ConvertFrom-Json -DateKind String` for the first half;
# it is not used, because CI's pwsh version is not pinned and the second half
# would still need the raw-text path.)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# LF, not [Environment]::NewLine: WriteLine emits CRLF on Windows while the .sh
# twin's printf emits LF, so every record would diverge by host. Same reason
# scripts/check-size-budgets.ps1 (Write, not WriteLine) hard-codes it.
$TAB = "`t"
function Out-Rec([string]$s) { [Console]::Out.Write($s + "`n") }
function Err([string]$s) { [Console]::Error.Write($s + "`n") }

function Show-Usage {
  Err 'usage: triage-cache.ps1 query <keys|edges> <owner> <repo> <n>...'
  Err '       triage-cache.ps1 lookup <repo-root> <graphql-response.json>'
  Err '       triage-cache.ps1 check-edges <repo-root> <graphql-response.json>'
  Err '       triage-cache.ps1 write <repo-root> <entries.json> <graphql-response.json>'
  exit 2
}

$KObject = [System.Text.Json.JsonValueKind]::Object
$KArray = [System.Text.Json.JsonValueKind]::Array
$KString = [System.Text.Json.JsonValueKind]::String
$KNumber = [System.Text.Json.JsonValueKind]::Number

# J-Get - a property's value as a JsonElement, or $null when absent or when the
# receiver is not an object. Mirrors jq, where indexing an absent key is null.
# EnumerateObject rather than TryGetProperty: no `out` parameter to marshal, and
# these objects hold a handful of keys.
function J-Get($el, [string]$name) {
  if ($null -eq $el -or $el.ValueKind -ne $KObject) { return $null }
  foreach ($p in $el.EnumerateObject()) { if ($p.Name -ceq $name) { return $p.Value } }
  return $null
}
# J-Str - the value when it is a JSON string, else $null. Non-string is treated
# as absent on BOTH legs (the .sh twin's `select(type == "string")`), so a
# malformed timestamp degrades the same way here.
function J-Str($el) {
  if ($null -ne $el -and $el.ValueKind -eq $KString) { return $el.GetString() }
  return $null
}

function Read-JsonRoot([string]$path) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try { $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop } catch { return $null }
  if ($null -eq $raw -or $raw.Trim().Length -eq 0) { return $null }
  try { return ([System.Text.Json.JsonDocument]::Parse($raw)).RootElement } catch { return $null }
}

# Read-Cache - the live cache object as a JsonElement, or $null for "empty
# cache". The FIRST PRESENT path wins; only ABSENCE falls through to the legacy
# root (see the .sh twin's "lookup: degrade to an empty cache" note for why a
# corrupt canonical file must not fall back).
function Read-Cache([string]$root) {
  foreach ($p in @((Join-Path $root '.milestone-config/triage-cache.json'),
                   (Join-Path $root '.milestone-driver-triage-cache.json'))) {
    if (Test-Path -LiteralPath $p) {
      $o = Read-JsonRoot $p
      if ($null -ne $o -and $o.ValueKind -eq $KObject) { return $o }
      return $null
    }
  }
  return $null
}

# Get-Aliases - the response's issue_<n> aliases as {n, x} records sorted by
# issue number, so the record order never depends on the response's key order or
# on the host parser's property ordering. $x is $null when the alias carries no
# issue object (a deleted or unreadable issue) - that becomes no-live-key.
function Get-Aliases($resp) {
  $doc = $resp
  $d = J-Get $resp 'data'
  if ($null -ne $d -and $d.ValueKind -eq $KObject) { $doc = $d }
  $list = New-Object System.Collections.Generic.List[psobject]
  if ($null -eq $doc -or $doc.ValueKind -ne $KObject) { return $list }
  foreach ($p in $doc.EnumerateObject()) {
    if (-not $p.Name.StartsWith('issue_')) { continue }
    $ns = $p.Name.Substring(6)
    if ($ns -notmatch '^[0-9]+$') { continue }
    $x = $null
    $iv = J-Get $p.Value 'issue'
    if ($null -ne $iv -and $iv.ValueKind -eq $KObject) { $x = $iv }
    $list.Add([pscustomobject]@{ n = [long]$ns; x = $x })
  }
  # Emit the sorted records into the pipeline and let every CALLER wrap the
  # result in @(). Returning `,(...)` instead would hand back an array nested
  # one level deep, which @() cannot flatten: `foreach` then binds the whole
  # inner array to one loop variable and `$a.n` member-enumerates to "7 9".
  return ($list.ToArray() | Sort-Object -Property n)
}

# The two encodings the label sort's byte keys are built on. Latin1 is the
# byte<->char bijection: every byte 0x00-0xFF maps to the char of the same value
# and back, losslessly (scripts/check-citations.ps1 (Latin1 is the byte<->char)).
$LKU8 = [System.Text.Encoding]::UTF8
$LKL1 = [System.Text.Encoding]::Latin1
# Get-ByteKey - a name respelled as the byte-chars of its UTF-8 encoding, so
# StringComparer.Ordinal over the result compares BYTES.
function Get-ByteKey([string]$s) { return $LKL1.GetString($LKU8.GetBytes($s)) }

# Get-LiveKey - "<n>:<lastEditedAt // createdAt>:<comments>:<labels>".
# The fallback fires when lastEditedAt is absent, null, or not a string,
# matching the .sh twin's `select(type == "string") // …` chain.
#
# LABELS SORT IN CODEPOINT ORDER, matching the .sh twin's jq `sort` under
# LC_ALL=C. The keys are the names' UTF-8 BYTES as byte-chars, so Ordinal over
# them IS a byte sort, and UTF-8 byte order IS codepoint order - the byte-domain
# model scripts/check-citations.ps1 (THE SORT) already ships. Neither of the
# obvious alternatives works: Sort-Object is culture-sensitive, and Ordinal over
# the DECODED names is UTF-16 code-unit order, which ranks an astral name (lead
# surrogate U+D800-DBFF) BEFORE every U+E000-FFFF name where codepoint order
# ranks it after. Getting this wrong changes the key on ONE leg only, and the
# sole symptom is a `MISS … key-mismatch` at exit 0 - indistinguishable from a
# genuinely edited issue. ASCII-only label sets agree under all three orders, so
# ASCII agreement is NOT evidence of parity: the pin is
# tests/triage-cache.cases.tsv (lookup-astral-vs-bmp-labels).
function Get-LiveKey([long]$n, $x) {
  $ts = J-Str (J-Get $x 'lastEditedAt')
  if ($null -eq $ts) { $ts = J-Str (J-Get $x 'createdAt') }
  if ($null -eq $ts) { $ts = '' }
  $cc = 0
  $t = J-Get (J-Get $x 'comments') 'totalCount'
  if ($null -ne $t -and $t.ValueKind -eq $KNumber) {
    $parsed = [long]0
    if ($t.TryGetInt64([ref]$parsed)) { $cc = $parsed }
  }
  $names = New-Object System.Collections.Generic.List[string]
  $nodes = J-Get (J-Get $x 'labels') 'nodes'
  if ($null -ne $nodes -and $nodes.ValueKind -eq $KArray) {
    foreach ($nd in $nodes.EnumerateArray()) {
      $nm = J-Str (J-Get $nd 'name')
      if ($null -ne $nm) { $names.Add($nm) }
    }
  }
  $arr = $names.ToArray()
  $bk = New-Object string[] $arr.Length
  for ($i = 0; $i -lt $arr.Length; $i++) { $bk[$i] = Get-ByteKey $arr[$i] }
  [array]::Sort($bk, $arr, [System.StringComparer]::Ordinal)
  return "${n}:${ts}:${cc}:" + ($arr -join ',')
}

# Get-Edges - a cache entry's result.edges as integers, or an empty list for any
# shape that is not an array of numbers (parity with the .sh twin's edges_of).
function Get-Edges($entry) {
  $out = New-Object System.Collections.Generic.List[long]
  $e = J-Get (J-Get $entry 'result') 'edges'
  if ($null -eq $e -or $e.ValueKind -ne $KArray) { return , $out }
  foreach ($v in $e.EnumerateArray()) {
    if ($v.ValueKind -ne $KNumber) { continue }
    $parsed = [long]0
    if ($v.TryGetInt64([ref]$parsed)) { $out.Add($parsed) }
  }
  # `, $out` returns the List ITSELF rather than its unrolled elements, so a
  # one-edge entry does not collapse to a bare scalar at the call site.
  return , $out
}

if ($args.Count -lt 1) { Show-Usage }
$sub = $args[0]

if ($sub -ceq 'query') {
  # Pure text generation: no JSON, no filesystem, no network.
  if ($args.Count -lt 5) { Show-Usage }
  $kind = $args[1]; $owner = $args[2]; $repo = $args[3]
  if ($kind -cne 'keys' -and $kind -cne 'edges') { Show-Usage }
  # Validate rather than escape: every real owner/repo already sits inside this
  # set, and a validated value cannot break out of the GraphQL string literal.
  # \z, NOT $: .NET's `$` also matches BEFORE a final newline, so "acme`n" passed
  # here while the .sh twin's `case` pattern rejected it - the value then reached
  # the emitted GraphQL and the two legs diverged (exit 0 + a query vs exit 2 +
  # usage). \z is the only anchor that means end-of-string in .NET.
  if ($owner -notmatch '^[A-Za-z0-9._-]+\z') { Show-Usage }
  if ($repo -notmatch '^[A-Za-z0-9._-]+\z') { Show-Usage }
  if ($kind -ceq 'keys') {
    $opname = 'BatchTimestamps'
    $fields = 'lastEditedAt createdAt comments { totalCount } labels(first:100) { nodes { name } }'
  } else {
    $opname = 'BatchEdgeStates'
    $fields = 'state stateReason'
  }
  $seen = New-Object System.Collections.Generic.List[string]
  $body = ''
  for ($i = 4; $i -lt $args.Count; $i++) {
    $n = [string]$args[$i]
    if ($n -notmatch '^[0-9]+\z') { Show-Usage }   # \z, not $ - see the owner/repo note above
    if ($seen.Contains($n)) { continue }
    $seen.Add($n)
    $body += " issue_${n}: repository(owner:`"$owner`", name:`"$repo`") { issue(number:$n) { $fields } }"
  }
  if ($seen.Count -eq 0) { Show-Usage }
  Out-Rec "query $opname {$body }"
  exit 0
}

if ($sub -cne 'lookup' -and $sub -cne 'check-edges' -and $sub -cne 'write') { Show-Usage }
# `write` alone takes FOUR: it recomputes each entry's key from the response.
# The response is NOT optional - an optional argument would restore exactly the
# "the key can be omitted" hole this signature exists to close (#462).
$wantArgc = if ($sub -ceq 'write') { 4 } else { 3 }
if ($args.Count -ne $wantArgc) { Show-Usage }
$root = $args[1]
$argfile = $args[2]
$respfile = if ($sub -ceq 'write') { $args[3] } else { $null }

if ($sub -ceq 'lookup') {
  $resp = Read-JsonRoot $argfile
  if ($null -eq $resp) { Out-Rec "SKIP${TAB}bad-response"; exit 0 }
  $aliases = @(Get-Aliases $resp)
  if ($aliases.Count -eq 0) { Out-Rec "SKIP${TAB}bad-response"; exit 0 }
  $cache = Read-Cache $root
  $recs = New-Object System.Collections.Generic.List[string]
  $hits = New-Object System.Collections.Generic.List[long]
  foreach ($a in $aliases) {
    $entry = J-Get $cache ([string]$a.n)
    if ($null -eq $a.x) {
      $recs.Add("MISS${TAB}$($a.n)${TAB}no-live-key")
    } elseif ($null -eq $entry -or $entry.ValueKind -ne $KObject) {
      $recs.Add("MISS${TAB}$($a.n)${TAB}no-entry")
    } else {
      $k = J-Str (J-Get $entry 'key')
      if ($null -eq $k) { $k = '' }
      if ([string]::Equals($k, (Get-LiveKey $a.n $a.x), [System.StringComparison]::Ordinal)) {
        $recs.Add("HIT${TAB}$($a.n)")
        $hits.Add($a.n)
      } else {
        $recs.Add("MISS${TAB}$($a.n)${TAB}key-mismatch")
      }
    }
  }
  $union = New-Object System.Collections.Generic.List[long]
  foreach ($h in $hits) {
    foreach ($e in (Get-Edges (J-Get $cache ([string]$h)))) {
      if (-not $union.Contains($e)) { $union.Add($e) }
    }
  }
  $edges = $union.ToArray(); [array]::Sort($edges)
  $line = 'EDGES'
  foreach ($e in $edges) { $line += "$TAB$e" }
  $recs.Add($line)
  $recs.Add("SUMMARY${TAB}hits=$($hits.Count)${TAB}misses=$($aliases.Count - $hits.Count)")
  foreach ($r in $recs) { Out-Rec $r }
  exit 0
}

if ($sub -ceq 'check-edges') {
  $resp = Read-JsonRoot $argfile
  if ($null -eq $resp) { Out-Rec "SKIP${TAB}bad-response"; exit 0 }
  $states = @{}
  foreach ($a in @(Get-Aliases $resp)) {
    if ($null -ne $a.x) { $states[[string]$a.n] = $a.x }
  }
  if ($states.Count -eq 0) { Out-Rec "SKIP${TAB}bad-response"; exit 0 }
  $cache = Read-Cache $root
  $stale = New-Object System.Collections.Generic.List[long]
  if ($null -ne $cache) {
    foreach ($p in $cache.EnumerateObject()) {
      if ($p.Name -notmatch '^[0-9]+$') { continue }
      foreach ($e in (Get-Edges $p.Value)) {
        if (-not $states.ContainsKey([string]$e)) { continue }
        $st = $states[[string]$e]
        $reason = J-Str (J-Get $st 'stateReason')
        if ($null -eq $reason) { $reason = '' }
        if ((J-Str (J-Get $st 'state')) -ceq 'CLOSED' -and $reason -cne 'COMPLETED') {
          $n = [long]$p.Name
          if (-not $stale.Contains($n)) { $stale.Add($n) }
          break
        }
      }
    }
  }
  $arr = $stale.ToArray(); [array]::Sort($arr)
  foreach ($n in $arr) { Out-Rec "MISS${TAB}$n${TAB}stale-edge" }
  Out-Rec "SUMMARY${TAB}stale=$($arr.Count)"
  exit 0
}

# ---- write: from here on EVERY exit is 0 -----------------------------------
function Skip([string]$reason) { Out-Rec "SKIP${TAB}$reason"; exit 0 }

$entries = Read-JsonRoot $argfile
if ($null -eq $entries -or $entries.ValueKind -ne $KObject) { Skip 'bad-entries' }

# Number -> live key, through Read-JsonRoot and the SAME Get-LiveKey `lookup`
# compares with - never ConvertFrom-Json, which would coerce every ISO-8601
# timestamp to a [datetime] and culture-format it straight back into the key
# (see this file's header). An absent, unreadable, or unparseable response
# leaves the map EMPTY: entries are then stored exactly as supplied, with no new
# SKIP reason and still exit 0 - fail-open, matching the .sh twin.
$liveKeys = @{}
$respRoot = Read-JsonRoot $respfile
if ($null -ne $respRoot) {
  foreach ($a in @(Get-Aliases $respRoot)) {
    if ($null -ne $a.x) { $liveKeys[[string]$a.n] = Get-LiveKey $a.n $a.x }
  }
}

$cache = Read-Cache $root
# Entry-level overwrite, matching the recorded rule "write or overwrite its
# entry": a re-triaged issue replaces its own entry and touches no other.
# The ordered map keeps existing entries in file order and appends new ones.
$order = New-Object System.Collections.Generic.List[string]
$merged = @{}
$injected = @{}
if ($null -ne $cache) {
  foreach ($p in $cache.EnumerateObject()) {
    if (-not $merged.ContainsKey($p.Name)) { $order.Add($p.Name) }
    $merged[$p.Name] = $p.Value
  }
}
foreach ($p in $entries.EnumerateObject()) {
  if (-not $merged.ContainsKey($p.Name)) { $order.Add($p.Name) }
  $merged[$p.Name] = $p.Value
  $injected[$p.Name] = $true
}

$dir = Join-Path $root '.milestone-config'
try { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null } catch { Skip 'mkdir-failed' }
# -Force does NOT throw when a regular FILE already occupies $dir, so the throw
# alone is not the test - the .sh twin's `mkdir -p` fails there and reports
# mkdir-failed, and without this check this leg fell through to the write and
# reported write-failed for the same tree.
if (-not (Test-Path -LiteralPath $dir -PathType Container)) { Skip 'mkdir-failed' }

# Self-heal the scratch-ignore BEFORE the write, so the cache is git-invisible
# in a consumer repo from the very first write with zero user setup, while the
# tracked config (driver.json, feeder.json) stays tracked. Create only when
# absent; never rewrite an existing file. Best-effort, on the same fail-open
# footing as the write itself.
# Joined with an explicit LF rather than written as a here-string, so a CRLF
# checkout of THIS file cannot leak CRLF into the emitted .gitignore and make it
# differ from the one the .sh twin writes.
# KEEP THIS BLOCK IN SYNC with the committed .milestone-config/.gitignore in
# this repo and with solve-issue / solve-milestone / hooks/tests-green.{sh,ps1},
# feeder setup / plan.
$gitignore = @(
  '# milestone-driver / milestone-feeder per-clone scratch - git-invisible by default.',
  '# Committed so per-run scratch stays out of `git status` with zero user setup.',
  '# Patterns are relative to this .milestone-config/ directory. Tracked config',
  '# (driver.json, feeder.json) is intentionally NOT listed, so it stays tracked.',
  '*-notice',
  'triage-cache.json',
  'tests-stamp',
  '.runtime/',
  'worktrees/'
) -join "`n"
$ignorePath = Join-Path $dir '.gitignore'
if (-not (Test-Path -LiteralPath $ignorePath)) {
  try {
    [System.IO.File]::WriteAllBytes($ignorePath,
      [System.Text.UTF8Encoding]::new($false).GetBytes($gitignore + "`n"))
  } catch { }
}

# Write to a per-process temp file and rename, so a concurrent reader sees
# either the old object or the new one and never a half-written file.
$target = Join-Path $dir 'triage-cache.json'
$tmp = Join-Path $dir "triage-cache.json.tmp.$PID"
try {
  # Utf8JsonWriter + JsonElement.WriteTo re-emits every untouched value from its
  # ORIGINAL text, so nothing this script does not own is reformatted.
  $ms = [System.IO.MemoryStream]::new()
  $wopts = [System.Text.Json.JsonWriterOptions]::new()
  $wopts.Indented = $true
  $w = [System.Text.Json.Utf8JsonWriter]::new($ms, $wopts)
  $w.WriteStartObject()
  foreach ($k in $order) {
    $w.WritePropertyName($k)
    $v = $merged[$k]
    if ($injected.ContainsKey($k) -and $liveKeys.ContainsKey($k) -and $v.ValueKind -eq $KObject) {
      # An INJECTED entry with a live key is the only thing rewritten, and it is
      # rewritten PROPERTY BY PROPERTY: a JsonElement cannot be mutated, and
      # round-tripping it through ConvertFrom-Json to add one field would
      # reformat every timestamp it carries. `key` is replaced IN PLACE when
      # present and appended otherwise, matching the .sh twin's `+` semantics.
      $w.WriteStartObject()
      $wroteKey = $false
      foreach ($pp in $v.EnumerateObject()) {
        if ($pp.Name -ceq 'key') { $w.WriteString('key', $liveKeys[$k]); $wroteKey = $true }
        else { $w.WritePropertyName($pp.Name); $pp.Value.WriteTo($w) }
      }
      if (-not $wroteKey) { $w.WriteString('key', $liveKeys[$k]) }
      $w.WriteEndObject()
    } else {
      # Everything else - untouched pre-existing entries above all - keeps the
      # verbatim WriteTo that byte-preserves values this script does not own.
      $v.WriteTo($w)
    }
  }
  $w.WriteEndObject()
  $w.Flush()
  # Bytes, not Set-Content: no BOM, no encoding parameter to get wrong, and the
  # single trailing LF is appended explicitly (the writer emits none).
  [System.IO.File]::WriteAllBytes($tmp, $ms.ToArray() + [byte[]]@(0x0A))
  Move-Item -LiteralPath $tmp -Destination $target -Force -ErrorAction Stop
} catch {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Skip 'write-failed'
}

# Only after the canonical file exists: drop the legacy root cache so it stops
# shadowing future transitional reads.
Remove-Item -LiteralPath (Join-Path $root '.milestone-driver-triage-cache.json') -Force -ErrorAction SilentlyContinue

Out-Rec "OK${TAB}.milestone-config/triage-cache.json"
exit 0
