#!/usr/bin/env pwsh
# milestone-driver - cache-aware cost-record helper (issue #320).
#
# Behavior-identical pwsh twin of scripts/write-cost-record.sh (native JSON - no
# jq). Writes ONE JSON cost record per invocation to the gitignored per-clone
# scratch dir .milestone-config/.runtime/cost-records/ (relative to the CURRENT
# WORKING DIRECTORY). Deterministic, cross-platform, NON-GATING; #322 wires it in.
#
# Input contract (stdin JSON, read ONCE):
#   {"runId":"<str>", "wallClockSeconds":<num>, "tiers":{"<tier>":{
#     "inputTokens":n,"outputTokens":n,"cacheReadTokens":n,"cacheWriteTokens":n}},
#    "provenanceNote":"<optional str>"}
#   Any OMITTED (or null) token/wallClock field defaults to 0; absent tiers -> {}.
#   A PRESENT-but-non-numeric token/wallClock value is MALFORMED (fail-open).
#
# Rate snapshot (hardcoded - NOT read from disk; source:
#   https://platform.claude.com/docs/en/about-claude/pricing, as-of 2026-11-21):
#     Opus 5.5  $4 in / $20 out per MTok ; Sonnet 5.5 $2 / $10.
#     cache-write rate = 1.25 x tier input rate ; cache-read = 0.05 x tier input rate.
#   Per-tier costUsd = (in*inRate + out*outRate + cWrite*inRate*1.25
#                       + cRead*inRate*0.05) / 1000000. Total = sum of PRICED tiers
#   only (rate-table keys: exactly opus + sonnet). Unknown tiers -> unpricedTiers,
#   excluded from costUsd, one stderr note each.
#
# Fail-open (mirrors the .sh twin / scripts/read-doc-section.ps1 fail path - always
#   exit 0; .project/design-philosophy.md#Error & failure philosophy): on empty/
#   malformed stdin, present-but-non-numeric token/wallClock, empty/missing/non-
#   string runId, or an uncreatable/unwritable cost-records/ dir -> write NO
#   record, print EXACTLY ONE stderr diagnostic, exit 0. NEVER a non-zero exit.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout so a non-ASCII record path or runId matches the .sh byte
# output. The script's own literals are all ASCII today; the forcing guards the
# interpolated content.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# fail-open: one stderr line, no record, exit 0.
function Fail([string]$msg) { [Console]::Error.WriteLine("write-cost-record: $msg"); exit 0 }

# rateSnapshot provenance base (single-quoted so $ is literal). Byte-identical to
# the .sh twin and both test runners (behavior-identical contract).
$rateBase = 'Opus 5.5 $4/$20 per MTok in/out; Sonnet 5.5 $2/$10 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.05x tier input rate; source: https://platform.claude.com/docs/en/about-claude/pricing, as-of 2026-11-21'

# Rate table: exactly opus + sonnet are priced (parity with the .sh $rates).
$rates = @{ opus = @{ inr = 4.0; outr = 20.0 }; sonnet = @{ inr = 2.0; outr = 10.0 } }

# numify: omitted (absent property) or null -> 0; a JSON number -> its value; any
# other present type -> malformed (throw, caught below into the fail-open path).
# Parity with the .sh numify: null and omitted both collapse to 0.
function Numify($obj, [string]$name) {
  if (-not $obj.PSObject.Properties[$name]) { return 0.0 }
  $v = $obj.$name
  if ($null -eq $v) { return 0.0 }
  if (($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [single] -or $v -is [decimal]) `
      -and ($v -isnot [bool])) { return [double]$v }
  throw 'nonnumeric'
}

# Fmt-Num: render an integral value as an integer, matching jq's number output
# (jq prints a whole-valued number without a trailing ".0", so the .sh twin emits
# `5` / `400000`, not `5.0`). Keeps the two twins' on-disk JSON byte-identical for
# whole numbers; fractional values (e.g. wallClockSeconds 12.5) stay doubles in both.
function Fmt-Num([double]$d) {
  if ([double]::IsFinite($d) -and [Math]::Floor($d) -eq $d -and [Math]::Abs($d) -lt 9.2e18) { return [long]$d }
  return $d
}

# Sanitize-Filename: byte-wise over UTF-8, mapping every byte outside
# [A-Za-z0-9._-] to '-' (parity with the .sh twin's `tr -c 'A-Za-z0-9._-' '-'`
# under LC_ALL=C). One definition shared by the default mode's runId sanitize
# below and by --append / --finalize's usage-file path, so the same runId
# always names the same usage file across all three modes.
function Sanitize-Filename([string]$s) {
  $sb = [System.Text.StringBuilder]::new()
  foreach ($b in [System.Text.Encoding]::UTF8.GetBytes($s)) {
    if (($b -ge 0x30 -and $b -le 0x39) -or ($b -ge 0x41 -and $b -le 0x5A) -or
        ($b -ge 0x61 -and $b -le 0x7A) -or $b -eq 0x2E -or $b -eq 0x5F -or $b -eq 0x2D) {
      [void]$sb.Append([char]$b)
    } else { [void]$sb.Append('-') }
  }
  return $sb.ToString()
}

# Modes (issue: lean-loop D5 - the run-end record must survive context
# compaction, which erases the orchestrator's in-context <usage> sums). See
# the .sh twin's header comment for the full contract; behavior-identical here.
$cliArgs = $args
$mode = if ($cliArgs.Count -ge 1) { $cliArgs[0] } else { $null }

# ---- --append <runId>: one usage line per dispatch, its own short path -----
if ($mode -eq '--append') {
  $runidArg = if ($cliArgs.Count -ge 2) { $cliArgs[1] } else { $null }
  if ([string]::IsNullOrEmpty($runidArg)) { Fail 'usage: write-cost-record.ps1 --append <runId> - no line appended' }
  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrEmpty($raw)) { Fail 'empty stdin - no line appended' }
  try {
    $eo = $raw | ConvertFrom-Json -ErrorAction Stop
    if (-not $eo.PSObject.Properties['agent']) { throw 'badagent' }
    $ea = $eo.agent
    if ($null -eq $ea -or $ea -isnot [string] -or $ea.Length -eq 0) { throw 'badagent' }
    if (-not $eo.PSObject.Properties['tier']) { throw 'badtier' }
    $et = $eo.tier
    if ($null -eq $et -or $et -isnot [string] -or $et.Length -eq 0) { throw 'badtier' }
    $lineObj = [ordered]@{
      agent = $ea; tier = $et.ToLowerInvariant()
      totalTokens = (Fmt-Num (Numify $eo 'totalTokens'))
      durationMs  = (Fmt-Num (Numify $eo 'durationMs'))
    }
    foreach ($k in 'steps', 'stepsBeforeFirstEdit', 'minutesToFirstEdit') {
      if ($eo.PSObject.Properties[$k] -and $null -ne $eo.$k) { $lineObj[$k] = (Fmt-Num (Numify $eo $k)) }
    }
    $lineJson = ($lineObj | ConvertTo-Json -Compress -ErrorAction Stop)
  } catch {
    Fail 'malformed input (unparseable JSON, missing/empty agent or tier, or non-numeric totalTokens/durationMs/steps/stepsBeforeFirstEdit/minutesToFirstEdit) - no line appended'
  }
  $reldir = '.milestone-config/.runtime/usage'
  $rel = "$reldir/$(Sanitize-Filename $runidArg).jsonl"
  $base = (Get-Location).Path
  try { New-Item -ItemType Directory -Force -Path (Join-Path $base $reldir) -ErrorAction Stop | Out-Null } catch {
    Fail "cannot create $reldir - no line appended"
  }
  try {
    $lineJson = $lineJson -replace "`r`n", "`n"
    [System.IO.File]::AppendAllText((Join-Path $base $rel), $lineJson + "`n", [System.Text.UTF8Encoding]::new($false))
  } catch {
    Fail "cannot append to $rel - no line appended"
  }
  [Console]::Out.Write($rel + "`n")
  exit 0
}

# ---- --start <runId>: record the run's start time once, its own short path --
# mkdir runs before the existence check so an occupied `usage` path reports
# "cannot create"; an existing start file is never rewritten.
if ($mode -eq '--start') {
  $runidArg = if ($cliArgs.Count -ge 2) { $cliArgs[1] } else { $null }
  if ([string]::IsNullOrEmpty($runidArg)) { Fail 'usage: write-cost-record.ps1 --start <runId> - no start time written' }
  $reldir = '.milestone-config/.runtime/usage'
  $rel = "$reldir/$(Sanitize-Filename $runidArg).start"
  $base = (Get-Location).Path
  try { New-Item -ItemType Directory -Force -Path (Join-Path $base $reldir) -ErrorAction Stop | Out-Null } catch {
    Fail "cannot create $reldir - no start time written"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $base $rel))) {
    $writtenAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    try {
      [System.IO.File]::WriteAllText((Join-Path $base $rel), $writtenAt + "`n", [System.Text.UTF8Encoding]::new($false))
    } catch {
      Fail "cannot write $rel - no start time written"
    }
  }
  [Console]::Out.Write($rel + "`n")
  exit 0
}

# ---- --finalize <runId>: build $o from the usage file, then fall through ---
# into the SAME costing block below the default mode already runs - one rate
# table, one cost-record shape, never a second copy of either.
# Read-AgentTurns: one agent-*.jsonl -> its deduped assistant turns, or $null when
# the file is unreadable or its first string `.timestamp` is unusable or before
# the start (whole seconds). Dedup by `message.id` is per file; an id-less turn
# keys as `null`, so all of them in one file share one key (parity with the .sh
# `$e.message.id | tojson`). A usage field that is missing, null or not a number
# adds 0.
function Read-AgentTurns([string]$path, [long]$startEpoch) {
  try { $lines = [System.IO.File]::ReadAllLines($path) } catch { return $null }
  $started = $false
  $seen = [System.Collections.Generic.HashSet[string]]::new()
  $turns = [System.Collections.Generic.List[object]]::new()
  foreach ($line in $lines) {
    try { $e = ([System.Text.Json.JsonDocument]::Parse($line)).RootElement } catch { continue }
    if ($e.ValueKind -ne 'Object') { continue }
    $p = [System.Text.Json.JsonElement]::new()
    if (-not $started -and $e.TryGetProperty('timestamp', [ref]$p) -and $p.ValueKind -eq 'String') {
      $started = $true
      $s = [regex]::new('\.[0-9]+').Replace($p.GetString(), '', 1)
      try {
        $t0 = [datetimeoffset]::ParseExact($s, "yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture,
          [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUnixTimeSeconds()
      } catch { return $null }
      if ($t0 -lt $startEpoch) { return $null }
    }
    if (-not ($e.TryGetProperty('type', [ref]$p) -and $p.ValueKind -eq 'String' -and $p.GetString() -ceq 'assistant')) { continue }
    $m = [System.Text.Json.JsonElement]::new()
    if (-not ($e.TryGetProperty('message', [ref]$m) -and $m.ValueKind -eq 'Object')) { continue }
    $u = [System.Text.Json.JsonElement]::new()
    if (-not ($m.TryGetProperty('usage', [ref]$u) -and $u.ValueKind -eq 'Object')) { continue }
    $key = if ($m.TryGetProperty('id', [ref]$p)) { $p.GetRawText() } else { 'null' }
    if (-not $seen.Add($key)) { continue }
    $model = if ($m.TryGetProperty('model', [ref]$p) -and $p.ValueKind -eq 'String') { $p.GetString().ToLowerInvariant() } else { '?' }
    if ($model -ceq '<synthetic>') { continue }
    $tier = if ($model.Contains('opus')) { 'opus' } elseif ($model.Contains('sonnet')) { 'sonnet' } else { $model }
    $n = [ordered]@{ tier = $tier }
    foreach ($k in @(@('i', 'input_tokens'), @('o', 'output_tokens'), @('cr', 'cache_read_input_tokens'), @('cw', 'cache_creation_input_tokens'))) {
      $n[$k[0]] = if ($u.TryGetProperty($k[1], [ref]$p) -and $p.ValueKind -eq 'Number') { $p.GetDouble() } else { 0.0 }
    }
    $turns.Add([pscustomobject]$n)
  }
  if (-not $started) { return $null }
  return ,$turns
}

$finalizeAgents = $null
$finalizeNote = $null
if ($mode -eq '--finalize') {
  $runidArg = if ($cliArgs.Count -ge 2) { $cliArgs[1] } else { $null }
  if ([string]::IsNullOrEmpty($runidArg)) { Fail 'usage: write-cost-record.ps1 --finalize <runId> - no record written' }
  $usageRel = ".milestone-config/.runtime/usage/$(Sanitize-Filename $runidArg).jsonl"
  $usageAbs = Join-Path (Get-Location).Path $usageRel
  $usageRaw = if (Test-Path -LiteralPath $usageAbs -PathType Leaf) { Get-Content -LiteralPath $usageAbs -Raw -ErrorAction SilentlyContinue } else { $null }
  if ([string]::IsNullOrWhiteSpace($usageRaw)) { Fail "no usage data at $usageRel - no record written" }
  try {
    $lines = @($usageRaw -split "`n" | Where-Object { $_.Trim() -ne '' })
    if ($lines.Count -eq 0) { throw 'empty' }
    $tierSums = [ordered]@{}
    $totalMs = 0.0
    $agentsList = @()
    foreach ($ln in $lines) {
      $eo = $ln | ConvertFrom-Json -ErrorAction Stop
      if ($eo -isnot [System.Management.Automation.PSCustomObject]) { throw 'badline' }
      if (-not $eo.PSObject.Properties['agent']) { throw 'badagent' }
      $ea = $eo.agent
      if ($null -eq $ea -or $ea -isnot [string] -or $ea.Length -eq 0) { throw 'badagent' }
      if (-not $eo.PSObject.Properties['tier']) { throw 'badtier' }
      $et = $eo.tier
      if ($null -eq $et -or $et -isnot [string] -or $et.Length -eq 0) { throw 'badtier' }
      $et = $et.ToLowerInvariant()
      $ett = Numify $eo 'totalTokens'
      $edm = Numify $eo 'durationMs'
      if (-not $tierSums.Contains($et)) { $tierSums[$et] = 0.0 }
      $tierSums[$et] = $tierSums[$et] + $ett
      $totalMs += $edm
      $agentsList += [ordered]@{ agent = $ea; tier = $et; totalTokens = (Fmt-Num $ett); durationMs = (Fmt-Num $edm) }
    }
    $tiersInput = [ordered]@{}
    foreach ($k in $tierSums.Keys) { $tiersInput[$k] = [pscustomobject]@{ inputTokens = (Fmt-Num $tierSums[$k]) } }
    $o = [pscustomobject]@{
      runId            = $runidArg
      wallClockSeconds = (Fmt-Num ($totalMs / 1000))
      tiers            = [pscustomobject]$tiersInput
      provenanceNote   = 'unsplit-total-as-input'
    }
    $finalizeAgents = $agentsList
  } catch {
    Fail "malformed usage data in $usageRel - no record written"
  }

  # Per-turn path: replace the unsplit `tiers` with sums over the session's agent
  # transcripts. Any reason it cannot run keeps $o as built above and is held in
  # $finalizeNote, printed after the record write so a failed write stays one
  # stderr line (parity with the .sh twin).
  $tdir = if ($cliArgs.Count -ge 3) { $cliArgs[2] } else { $null }
  $startRel = ".milestone-config/.runtime/usage/$(Sanitize-Filename $runidArg).start"
  $startAbs = Join-Path (Get-Location).Path $startRel
  if ([string]::IsNullOrEmpty($tdir)) {
    $finalizeNote = 'no transcript directory argument'
  } elseif (-not (Test-Path -LiteralPath $tdir -PathType Container)) {
    $finalizeNote = "transcript directory $tdir not found"
  } elseif (-not (Test-Path -LiteralPath $startAbs -PathType Leaf)) {
    $finalizeNote = "no start file at $startRel"
  } else {
    $startLine = ''
    try { $startLine = [string](@(Get-Content -LiteralPath $startAbs -TotalCount 1 -ErrorAction Stop)[0]) } catch {}
    $startLine = $startLine.TrimEnd("`r")
    $startEpoch = $null
    try {
      $startEpoch = [datetimeoffset]::ParseExact($startLine, "yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUnixTimeSeconds()
    } catch {}
    if ($null -eq $startEpoch) {
      $finalizeNote = "start file $startRel is not %Y-%m-%dT%H:%M:%SZ"
    } else {
      try {
        # Ordinal sort = the .sh twin's C-locale glob order; -clike keeps its case-sensitive match.
        $names = @(Get-ChildItem -LiteralPath $tdir -File -Filter 'agent-*.jsonl' | Where-Object { $_.Name -clike 'agent-*.jsonl' } |
          ForEach-Object { $_.Name })
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
        $matched = 0
        $sums = [ordered]@{}
        foreach ($nm in $names) {
          $turns = Read-AgentTurns (Join-Path (Resolve-Path -LiteralPath $tdir).Path $nm) $startEpoch
          if ($null -eq $turns) { continue }
          $matched++
          foreach ($t in $turns) {
            if (-not $sums.Contains($t.tier)) { $sums[$t.tier] = @{ i = 0.0; o = 0.0; cr = 0.0; cw = 0.0 } }
            $sums[$t.tier].i += $t.i; $sums[$t.tier].o += $t.o; $sums[$t.tier].cr += $t.cr; $sums[$t.tier].cw += $t.cw
          }
        }
        if ($matched -eq 0) {
          $finalizeNote = "no agent transcript at or after $startLine in $tdir"
        } else {
          $tiersInput = [ordered]@{}
          foreach ($k in $sums.Keys) {
            $tiersInput[$k] = [pscustomobject][ordered]@{
              inputTokens = (Fmt-Num $sums[$k].i); outputTokens = (Fmt-Num $sums[$k].o)
              cacheReadTokens = (Fmt-Num $sums[$k].cr); cacheWriteTokens = (Fmt-Num $sums[$k].cw)
            }
          }
          $o.tiers = [pscustomobject]$tiersInput
          $o.provenanceNote = 'per-turn-transcript-sum'
        }
      } catch {
        $finalizeNote = "cannot sum the transcripts in $tdir"
      }
    }
  }
} else {
  $raw = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrEmpty($raw)) { Fail 'empty stdin - no record written' }
}

try {
  if ($mode -ne '--finalize') { $o = $raw | ConvertFrom-Json -ErrorAction Stop }

  # runId: must be a present, non-empty JSON string (parity with the .sh
  # (.runId|type)=="string" and length>0 guard).
  if (-not $o.PSObject.Properties['runId']) { Fail 'missing runId - no record written' }
  $runId = $o.runId
  if ($null -eq $runId -or $runId -isnot [string] -or $runId.Length -eq 0) {
    Fail 'empty or non-string runId - no record written'
  }

  # tiers -> ordered list of [name, valueObject]; absent/null tiers -> empty.
  # A present-non-null `tiers` MUST be a JSON object, and each tier value MUST be
  # a JSON object. A scalar/array in either position is MALFORMED -> fail-open,
  # matching the .sh jq path where `(.tiers // {}) | to_entries` errors on a
  # non-object tiers and numify errors on a non-object tier value. Without this,
  # pwsh would Numify a scalar tier to 0 (silent zeroed record) or fabricate bogus
  # tiers from a scalar's PSObject.Properties (e.g. Length) - diverging from bash.
  $entries = @()
  if ($o.PSObject.Properties['tiers'] -and $null -ne $o.tiers) {
    if ($o.tiers -isnot [System.Management.Automation.PSCustomObject]) { throw 'nonobject-tiers' }
    foreach ($prop in $o.tiers.PSObject.Properties) {
      if ($prop.Value -isnot [System.Management.Automation.PSCustomObject]) { throw 'nonobject-tier' }
      $entries += [pscustomobject]@{ key = $prop.Name; val = $prop.Value }
    }
  }

  # tcost: per-tier dollars from the rate snapshot (parity with the .sh tcost).
  function Get-TierCost($t, $r) {
    return ( (Numify $t 'inputTokens') * $r.inr +
             (Numify $t 'outputTokens') * $r.outr +
             (Numify $t 'cacheWriteTokens') * ($r.inr * 1.25) +
             (Numify $t 'cacheReadTokens') * ($r.inr * 0.05) ) / 1000000
  }
  # toks: the four raw token counts, normalized to numbers (order matches the .sh toks).
  function Get-Toks($t) {
    return [ordered]@{
      inputTokens      = (Fmt-Num (Numify $t 'inputTokens'))
      outputTokens     = (Fmt-Num (Numify $t 'outputTokens'))
      cacheReadTokens  = (Fmt-Num (Numify $t 'cacheReadTokens'))
      cacheWriteTokens = (Fmt-Num (Numify $t 'cacheWriteTokens'))
    }
  }

  $unpriced = @()
  $totalCost = 0.0
  $tiersObj = [ordered]@{}
  $unpricedObj = [ordered]@{}
  foreach ($e in $entries) {
    if ($rates.ContainsKey($e.key)) {
      $r = $rates[$e.key]
      $c = Get-TierCost $e.val $r
      $totalCost += $c
      $t = Get-Toks $e.val
      $t['costUsd'] = (Fmt-Num $c)
      $tiersObj[$e.key] = $t
    } else {
      $unpriced += $e.key
      $unpricedObj[$e.key] = Get-Toks $e.val
    }
  }

  # rateSnapshot: base + optional "; note: <note>" when provenanceNote is a
  # present, non-empty string (decision #2); else byte-identical base.
  $snapshot = $rateBase
  if ($o.PSObject.Properties['provenanceNote']) {
    $pn = $o.provenanceNote
    if ($pn -is [string] -and $pn.Length -gt 0) { $snapshot = "$rateBase; note: $pn" }
  }

  $writtenAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $record = [ordered]@{
    runId            = $runId
    writtenAt        = $writtenAt
    wallClockSeconds = (Fmt-Num (Numify $o 'wallClockSeconds'))
    costUsd          = (Fmt-Num $totalCost)
    tiers            = $tiersObj
    unpricedTiers    = $unpricedObj
    rateSnapshot     = $snapshot
  }
} catch {
  Fail 'malformed input (unparseable JSON, missing/empty runId, or non-numeric token/wallClock) - no record written'
}

# --finalize only: attach the raw per-dispatch entries the usage-file pass set
# aside, so the record carries a per-agent durationMs breakdown the summed
# wallClockSeconds above cannot give back on its own.
if ($finalizeAgents) { $record['agents'] = $finalizeAgents }

# Sanitize runId for the FILENAME only (raw runId stays verbatim in the body).
# Byte-wise over UTF-8 to match the .sh twin's `tr -c 'A-Za-z0-9._-' '-'` under
# LC_ALL=C - see Sanitize-Filename above (shared with --append / --finalize).
$sanitized = Sanitize-Filename $runId
# Filename: <sanitized>-<UTC-unix-seconds>-<nonce>.json. Nonce mirrors the
# existing per-run pattern at scripts/render-daemon.ps1 ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()): $PID-<unixseconds>-<random>.
# Single source of truth for the relative dir segment (parity with the .sh $dir),
# so $rel / $dir / $abs cannot drift.
$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$nonce = "$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())-$(Get-Random)"
$reldir = '.milestone-config/.runtime/cost-records'
$rel = "$reldir/$sanitized-$ts-$nonce.json"
$base = (Get-Location).Path
$dir = Join-Path $base $reldir
$abs = Join-Path $base $rel

# Create the scratch dir. Mirrors the New-Item -Force idiom in
# scripts/render-daemon.ps1 (function Write-State), repeated there at the
# detached serverCmd spawn. Uncreatable /
# unwritable -> fail-open.
try { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null } catch {
  Fail "cannot create $dir - no record written"
}

try {
  # Depth covers record -> tiers -> per-tier token object.
  $json = $record | ConvertTo-Json -Depth 10
  # Normalize to jq's on-disk bytes - LF-only line endings (ConvertTo-Json emits
  # CRLF on Windows) and EXACTLY ONE trailing newline. utf8NoBOM + -NoNewline writes
  # the string verbatim (no BOM, no added terminator), byte-parity with the .sh twin's
  # `jq '.record' | tr -d '\r' > file`.
  #
  # Float representation is deliberately NOT forced to a specific form: jq's numeric
  # serialization is version-dependent (jq 1.8 emits `0.00005` where 1.7 emitted
  # `5e-05`; ConvertTo-Json emits `5E-05`) - all valid JSON for the same value. Both
  # twins assert costUsd by NUMERIC VALUE, never on-disk float bytes, so no exponent
  # rewrite is done here (an earlier `-replace ...E...` variant also corrupted any
  # string field containing `<digit>E<digit>`, e.g. a runId "1E2").
  $json = ($json -replace "`r`n", "`n").TrimEnd("`n") + "`n"
  Set-Content -LiteralPath $abs -Value $json -Encoding utf8NoBOM -NoNewline -ErrorAction Stop
} catch {
  Fail "cannot write record to $rel - no record written"
}

# Record is written - NOW emit one stderr note per unpriced tier. Emitting AFTER the
# write (not before) guarantees a write fail-open above stays a SINGLE stderr line,
# never note(s) + the fail line (parity with the .sh twin's ordering).
if ($finalizeNote) { [Console]::Error.WriteLine("write-cost-record: $finalizeNote - using unsplit totals") }
foreach ($t in $unpriced) {
  [Console]::Error.WriteLine("write-cost-record: tier '$t' has no rate table entry - recorded under unpricedTiers, excluded from costUsd")
}

[Console]::Out.Write($rel + "`n")
exit 0
