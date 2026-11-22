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

$usageDir = '.milestone-config/.runtime/usage'

# Modes (issue: lean-loop D5 - the run-end record must survive context
# compaction, which erases the orchestrator's in-context <usage> sums). See
# the .sh twin's header comment for the full contract; behavior-identical here.
# One invocation is one window: --start writes the time and CLAUDE_CODE_SESSION_ID,
# --finalize deletes the .start and .jsonl once the record is written. Once a runId is given,
# every --finalize exit that writes no record, but a failed record write or `cannot create`,
# deletes the .start. The exits after the no-usage check (malformed data, malformed input)
# also rename the .jsonl to <runId>.jsonl.bad (replacing an older file) and end with
# `(moved to <name>)`, or `(could not move it aside)` when a non-file holds that name or the
# rename failed. <runId>.jsonl.bad holds the usage lines of the run that hit the exit, valid lines
# on the .sh twin's jq-missing and internal-error exits, and a later move aside for the same runId
# replaces it.
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
  $rel = "$usageDir/$(Sanitize-Filename $runidArg).jsonl"
  $base = (Get-Location).Path
  try { New-Item -ItemType Directory -Force -Path (Join-Path $base $usageDir) -ErrorAction Stop | Out-Null } catch {
    Fail "cannot create $usageDir - no line appended"
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
# "cannot create"; an existing start file is never rewritten (--finalize is what
# deletes it). Line 2 is the current CLAUDE_CODE_SESSION_ID, empty when unset.
if ($mode -eq '--start') {
  $runidArg = if ($cliArgs.Count -ge 2) { $cliArgs[1] } else { $null }
  if ([string]::IsNullOrEmpty($runidArg)) { Fail 'usage: write-cost-record.ps1 --start <runId> - no start time written' }
  $rel = "$usageDir/$(Sanitize-Filename $runidArg).start"
  $base = (Get-Location).Path
  try { New-Item -ItemType Directory -Force -Path (Join-Path $base $usageDir) -ErrorAction Stop | Out-Null } catch {
    Fail "cannot create $usageDir - no start time written"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $base $rel))) {
    $writtenAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    try {
      [System.IO.File]::WriteAllText((Join-Path $base $rel), $writtenAt + "`n" + [string]$env:CLAUDE_CODE_SESSION_ID + "`n", [System.Text.UTF8Encoding]::new($false))
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
# Parse-UtcEpoch: a whole-second `yyyy-MM-ddTHH:mm:ssZ` string -> unix seconds, or
# throws. The one form jq's fromdate accepts, so both twins reject the same strings. An
# epoch below 0 returns -1, below any valid start: the .sh twin returns -1 for every pre-1970 year too.
function Parse-UtcEpoch([string]$s) {
  $e = [datetimeoffset]::ParseExact($s, "yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUnixTimeSeconds()
  if ($e -lt 0) { return -1 }
  return $e
}

# Per-turn token fields: the record's own tier key -> the transcript's `message.usage` field.
$usageFields = [ordered]@{
  inputTokens      = 'input_tokens'
  outputTokens     = 'output_tokens'
  cacheReadTokens  = 'cache_read_input_tokens'
  cacheWriteTokens = 'cache_creation_input_tokens'
}

# Read-AgentTurns: one agent-*.jsonl -> its deduped assistant turns, or $null when
# the file is unreadable (at open or mid-read) or its first string `.timestamp` is unusable or before
# the start (whole seconds). Dedup by `message.id` is per file; an id-less turn
# keys as `null`, so all of them in one file share one key (parity with the .sh
# `$e.message.id | tojson`). A usage field that is missing, null or not a number
# or a count that is not finite adds 0. ReadLines is lazy, so the early `return` on a pre-start file stops reading.
# The enumerator is disposed by hand: a PowerShell `foreach` leaves it (and the file
# handle) open until GC when the loop exits early.
# MaxDepth 10000 matches jq's parse limit: the .NET default of 64 would drop a deeply nested line jq counts.
$jsonOpts = [System.Text.Json.JsonDocumentOptions]::new()
$jsonOpts.MaxDepth = 10000
function Read-AgentTurns([string]$path, [long]$startEpoch) {
  try { $reader = [System.IO.File]::ReadLines($path).GetEnumerator() } catch { return $null }
  $started = $false
  $seen = [System.Collections.Generic.HashSet[string]]::new()
  $turns = [System.Collections.Generic.List[object]]::new()
  try {
    while ($reader.MoveNext()) {
      try { $doc = [System.Text.Json.JsonDocument]::Parse($reader.Current, $jsonOpts) } catch { continue }
      try {
        $e = $doc.RootElement
        if ($e.ValueKind -ne 'Object') { continue }
        $p = [System.Text.Json.JsonElement]::new()
        if (-not $started -and $e.TryGetProperty('timestamp', [ref]$p) -and $p.ValueKind -eq 'String') {
          $started = $true
          # mirrors scripts/measure-dispatch.ps1 (ParseExact takes only the one form), which truncates fractional seconds
          $ts = $p.GetString()
          if ($ts -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z\z') { return $null }
          $s = [regex]::new('\.[0-9]+').Replace($ts, '', 1)
          try { $t0 = Parse-UtcEpoch $s } catch { return $null }
          if ($t0 -lt $startEpoch) { return $null }
        }
        if (-not ($e.TryGetProperty('type', [ref]$p) -and $p.ValueKind -eq 'String' -and $p.GetString() -ceq 'assistant')) { continue }
        $m = [System.Text.Json.JsonElement]::new()
        if (-not ($e.TryGetProperty('message', [ref]$m) -and $m.ValueKind -eq 'Object')) { continue }
        $u = [System.Text.Json.JsonElement]::new()
        if (-not ($m.TryGetProperty('usage', [ref]$u) -and $u.ValueKind -eq 'Object')) { continue }
        $key = if ($m.TryGetProperty('id', [ref]$p)) { $p.GetRawText() } else { 'null' }
        if (-not $seen.Add($key)) { continue }
        $model = if ($m.TryGetProperty('model', [ref]$p) -and $p.ValueKind -eq 'String' -and $p.GetString().Length -gt 0) { $p.GetString().ToLowerInvariant() } else { '?' }
        if ($model -ceq '<synthetic>') { continue }
        $tier = if ([regex]::IsMatch($model, '(^|[./])claude-opus-5-5', 'CultureInvariant')) { 'opus' } elseif ([regex]::IsMatch($model, '(^|[./])claude-sonnet-5-5', 'CultureInvariant')) { 'sonnet' } else { $model }
        $n = [ordered]@{ tier = $tier }
        foreach ($k in $usageFields.Keys) {
          $d = 0.0
          $n[$k] = if ($u.TryGetProperty($usageFields[$k], [ref]$p) -and $p.ValueKind -eq 'Number' -and $p.TryGetDouble([ref]$d) -and [double]::IsFinite($d)) { $d } else { 0.0 }
        }
        $turns.Add([pscustomobject]$n)
      } finally { $doc.Dispose() }
    }
  } catch { return $null } finally { $reader.Dispose() }
  if (-not $started) { return $null }
  return ,$turns
}

$finalizeAgents = $null
$finalizeNote = $null
if ($mode -eq '--finalize') {
  $runidArg = if ($cliArgs.Count -ge 2) { $cliArgs[1] } else { $null }
  if ([string]::IsNullOrEmpty($runidArg)) { Fail 'usage: write-cost-record.ps1 --finalize <runId> - no record written' }
  $usageRel = "$usageDir/$(Sanitize-Filename $runidArg).jsonl"
  $usageAbs = Join-Path (Get-Location).Path $usageRel
  $startRel = "$usageDir/$(Sanitize-Filename $runidArg).start"
  $startAbs = Join-Path (Get-Location).Path $startRel
  # Every exit past the no-usage check also moves the usage file aside, or the next run of
  # this runId would fail on the same data forever. A non-file at the .bad name blocks the
  # move, since Move-Item -Force would put the usage file inside a directory there.
  function Fail-Aside([string]$msg) {
    Remove-Item -LiteralPath $startAbs -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $usageAbs -PathType Leaf) {
      $badName = "$(Sanitize-Filename $runidArg).jsonl.bad"
      $badAbs = Join-Path (Split-Path -Parent $usageAbs) $badName
      $moved = 'could not move it aside'
      if (-not (Test-Path -LiteralPath $badAbs) -or (Test-Path -LiteralPath $badAbs -PathType Leaf)) {
        try { Move-Item -LiteralPath $usageAbs -Destination $badAbs -Force -ErrorAction Stop; $moved = "moved to $badName" } catch {}
      }
      Fail "$msg ($moved)"
    }
    Fail $msg
  }
  # No usage data: not a readable regular file, or nothing but ASCII whitespace (the bytes are tested
  # as Latin-1, so a no-break space or a BOM is data, as it is to the .sh twin's grep and jq).
  $usageBytes = $null
  if (Test-Path -LiteralPath $usageAbs -PathType Leaf) {
    try { $usageBytes = [System.IO.File]::ReadAllBytes($usageAbs) } catch {}
  }
  if ($null -eq $usageBytes -or [System.Text.Encoding]::Latin1.GetString($usageBytes) -cmatch '\A[ \t\n\v\f\r]*\z') {
    # An exit that writes no record also drops the .start, or the next run of this runId
    # would open its window at this one's start time (or read this session's id).
    Remove-Item -LiteralPath $startAbs -Force -ErrorAction SilentlyContinue
    Fail "no usage data at $usageRel - no record written"
  }
  # The same bytes decoded as Get-Content -Raw would, a leading UTF-8 BOM dropped.
  $usageRaw = [System.Text.Encoding]::UTF8.GetString($usageBytes) -replace '\A\uFEFF', ''
  try {
    # Only JSON whitespace makes a line blank, as to jq -s; a line of only \v, \f or U+00A0 reaches
    # ConvertFrom-Json, which would skip it, so it fails as a non-object instead.
    $lines = @($usageRaw -split "`n" | Where-Object { $_ -cnotmatch '\A[ \t\r]*\z' })
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
    Fail-Aside "malformed usage data in $usageRel - no record written"
  }

  # Per-turn path: replace the unsplit `tiers` with sums over the session's agent
  # transcripts. Any reason it cannot run keeps $o as built above and is held in
  # $finalizeNote, printed after the record write so a failed write stays one
  # stderr line (parity with the .sh twin).
  $tdir = if ($cliArgs.Count -ge 3) { $cliArgs[2] } else { $null }
  if ([string]::IsNullOrEmpty($tdir)) {
    $finalizeNote = 'no transcript directory argument'
  } elseif (-not (Test-Path -LiteralPath $tdir -PathType Container)) {
    $finalizeNote = "transcript directory $tdir not found"
  } elseif (-not (Test-Path -LiteralPath $startAbs -PathType Leaf)) {
    $finalizeNote = "no start file at $startRel"
  } else {
    $startLines = @()
    try { $startLines = @(Get-Content -LiteralPath $startAbs -TotalCount 2 -ErrorAction Stop) } catch {}
    $startLine = if ($startLines.Count -ge 1) { ([string]$startLines[0]).TrimEnd("`r") } else { '' }
    $startSid = if ($startLines.Count -ge 2) { ([string]$startLines[1]).TrimEnd("`r") } else { '' }
    $startEpoch = $null
    try {
      $startEpoch = Parse-UtcEpoch $startLine
    } catch {}
    if ($null -eq $startEpoch) {
      $finalizeNote = "start file $startRel is not %Y-%m-%dT%H:%M:%SZ"
    } elseif ($startEpoch -eq -1) {
      $finalizeNote = "start file $startRel is before 1970"
    } elseif ($startSid -ne '' -and $startSid -cne [string]$env:CLAUDE_CODE_SESSION_ID) {
      $finalizeNote = 'run started in another session'
    } else {
      try {
        # Ordinal sort = the .sh twin's C-locale glob order; -clike keeps its case-sensitive match.
        $files = @(Get-ChildItem -LiteralPath $tdir -File -Filter 'agent-*.jsonl' | Where-Object { $_.Name -clike 'agent-*.jsonl' })
        $names = [string[]]@($files | ForEach-Object { $_.Name })
        [Array]::Sort($names, [object[]]$files, [System.StringComparer]::Ordinal)
        $matched = 0
        $sums = [ordered]@{}
        foreach ($f in $files) {
          $turns = Read-AgentTurns $f.FullName $startEpoch
          if ($null -eq $turns) { continue }
          $matched++
          foreach ($t in $turns) {
            if (-not $sums.Contains($t.tier)) { $sums[$t.tier] = [pscustomobject][ordered]@{ inputTokens = 0.0; outputTokens = 0.0; cacheReadTokens = 0.0; cacheWriteTokens = 0.0 } }
            foreach ($k in $usageFields.Keys) { $sums[$t.tier].$k += $t.$k }
          }
        }
        if ($matched -eq 0) {
          $finalizeNote = "no agent transcript at or after $startLine in $tdir"
        } else {
          $o.tiers = [pscustomobject]$sums
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
  $malformedMsg = 'malformed input (unparseable JSON, missing/empty runId, or non-numeric token/wallClock) - no record written'
  if ($mode -eq '--finalize') { Fail-Aside $malformedMsg }
  Fail $malformedMsg
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
# New-Item -Force returns a file already at that path without error, which the .sh twin's
# mkdir -p refuses; the Container test makes that the same `cannot create` exit.
try { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null } catch {}
if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
  Fail "cannot create $reldir - no record written"
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

# --finalize only: the record carries every raw entry in `agents`, so the window is
# spent. Deleting it lets the next invocation of this runId (a resume or a rerun) open
# a fresh one instead of billing this session's agents again.
if ($mode -eq '--finalize') { Remove-Item -LiteralPath $usageAbs, $startAbs -Force -ErrorAction SilentlyContinue }

# Record is written - NOW emit one stderr note per unpriced tier. Emitting AFTER the
# write (not before) guarantees a write fail-open above stays a SINGLE stderr line,
# never note(s) + the fail line (parity with the .sh twin's ordering).
if ($finalizeNote) { [Console]::Error.WriteLine("write-cost-record: $finalizeNote - using unsplit totals") }
foreach ($t in $unpriced) {
  [Console]::Error.WriteLine("write-cost-record: tier '$t' has no rate table entry - recorded under unpricedTiers, excluded from costUsd")
}

[Console]::Out.Write($rel + "`n")
exit 0
