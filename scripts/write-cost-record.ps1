#!/usr/bin/env pwsh
# milestone-driver — cache-aware cost-record helper (issue #320).
#
# Behavior-identical pwsh twin of scripts/write-cost-record.sh (native JSON — no
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
# Rate snapshot (hardcoded — NOT read from disk; source: kenmulford/milestone-suite
#   benchmarks/after/RESULTS.md ~lines 100-111, as-of 2026-07):
#     Opus 4.8  $5 in / $25 out per MTok ; Sonnet 4.6 $3 / $15.
#     cache-write rate = 1.25 x tier input rate ; cache-read = 0.1 x tier input rate.
#   Per-tier costUsd = (in*inRate + out*outRate + cWrite*inRate*1.25
#                       + cRead*inRate*0.1) / 1000000. Total = sum of PRICED tiers
#   only (rate-table keys: exactly opus + sonnet). Unknown tiers -> unpricedTiers,
#   excluded from costUsd, one stderr note each.
#
# Fail-open (mirrors the .sh twin / scripts/read-doc-section.ps1 fail path — always
#   exit 0; .project/design-philosophy.md#Error & failure philosophy): on empty/
#   malformed stdin, present-but-non-numeric token/wallClock, empty/missing/non-
#   string runId, or an uncreatable/unwritable cost-records/ dir -> write NO
#   record, print EXACTLY ONE stderr diagnostic, exit 0. NEVER a non-zero exit.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout so the printed path / em-dash notes match the .sh byte output.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# fail-open: one stderr line, no record, exit 0.
function Fail([string]$msg) { [Console]::Error.WriteLine("write-cost-record: $msg"); exit 0 }

# rateSnapshot provenance base (single-quoted so $ is literal). Byte-identical to
# the .sh twin and both test runners (behavior-identical contract).
$rateBase = 'Opus 4.8 $5/$25 per MTok in/out; Sonnet 4.6 $3/$15 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.1x tier input rate; source: kenmulford/milestone-suite benchmarks/after/RESULTS.md, as-of 2026-07'

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrEmpty($raw)) { Fail 'empty stdin — no record written' }

# Rate table: exactly opus + sonnet are priced (parity with the .sh $rates).
$rates = @{ opus = @{ inr = 5.0; outr = 25.0 }; sonnet = @{ inr = 3.0; outr = 15.0 } }

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

try {
  $o = $raw | ConvertFrom-Json -ErrorAction Stop

  # runId: must be a present, non-empty JSON string (parity with the .sh
  # (.runId|type)=="string" and length>0 guard).
  if (-not $o.PSObject.Properties['runId']) { Fail 'missing runId — no record written' }
  $runId = $o.runId
  if ($null -eq $runId -or $runId -isnot [string] -or $runId.Length -eq 0) {
    Fail 'empty or non-string runId — no record written'
  }

  # tiers -> ordered list of [name, valueObject]; absent/null tiers -> empty.
  # A present-non-null `tiers` MUST be a JSON object, and each tier value MUST be
  # a JSON object. A scalar/array in either position is MALFORMED -> fail-open,
  # matching the .sh jq path where `(.tiers // {}) | to_entries` errors on a
  # non-object tiers and numify errors on a non-object tier value. Without this,
  # pwsh would Numify a scalar tier to 0 (silent zeroed record) or fabricate bogus
  # tiers from a scalar's PSObject.Properties (e.g. Length) — diverging from bash.
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
             (Numify $t 'cacheReadTokens') * ($r.inr * 0.1) ) / 1000000
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
  Fail 'malformed input (unparseable JSON, missing/empty runId, or non-numeric token/wallClock) — no record written'
}

# Sanitize runId for the FILENAME only (raw runId stays verbatim in the body).
# Byte-wise over UTF-8 to match the .sh twin's `tr -c 'A-Za-z0-9._-' '-'` under
# LC_ALL=C: encode the runId as UTF-8 bytes and map every byte that is NOT an
# allowed ASCII char to '-'. A per-CHAR -replace would emit one dash for a
# multi-byte char (e.g. "café" -> "caf-"), but bash sees two bytes for 'é' ->
# "caf--"; byte-wise keeps filenames identical for ANY runId across both twins.
$sb = [System.Text.StringBuilder]::new()
foreach ($b in [System.Text.Encoding]::UTF8.GetBytes($runId)) {
  if (($b -ge 0x30 -and $b -le 0x39) -or   # 0-9
      ($b -ge 0x41 -and $b -le 0x5A) -or   # A-Z
      ($b -ge 0x61 -and $b -le 0x7A) -or   # a-z
      $b -eq 0x2E -or $b -eq 0x5F -or $b -eq 0x2D) { # . _ -
    [void]$sb.Append([char]$b)
  } else {
    [void]$sb.Append('-')
  }
}
$sanitized = $sb.ToString()
# Filename: <sanitized>-<UTC-unix-seconds>-<nonce>.json. Nonce mirrors the
# existing per-run pattern (render-daemon.ps1:269): $PID-<unixseconds>-<random>.
# Single source of truth for the relative dir segment (parity with the .sh $dir),
# so $rel / $dir / $abs cannot drift.
$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$nonce = "$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())-$(Get-Random)"
$reldir = '.milestone-config/.runtime/cost-records'
$rel = "$reldir/$sanitized-$ts-$nonce.json"
$base = (Get-Location).Path
$dir = Join-Path $base $reldir
$abs = Join-Path $base $rel

# Create the scratch dir (mirrors render-daemon.ps1:202,275). Uncreatable /
# unwritable -> fail-open.
try { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null } catch {
  Fail "cannot create $dir — no record written"
}

try {
  # Depth covers record -> tiers -> per-tier token object.
  $json = $record | ConvertTo-Json -Depth 10
  # Normalize to jq's on-disk bytes — LF-only line endings (ConvertTo-Json emits
  # CRLF on Windows) and EXACTLY ONE trailing newline. utf8NoBOM + -NoNewline writes
  # the string verbatim (no BOM, no added terminator), byte-parity with the .sh twin's
  # `jq '.record' | tr -d '\r' > file`.
  #
  # Float representation is deliberately NOT forced to a specific form: jq's numeric
  # serialization is version-dependent (jq 1.8 emits `0.00005` where 1.7 emitted
  # `5e-05`; ConvertTo-Json emits `5E-05`) — all valid JSON for the same value. Both
  # twins assert costUsd by NUMERIC VALUE, never on-disk float bytes, so no exponent
  # rewrite is done here (an earlier `-replace ...E...` variant also corrupted any
  # string field containing `<digit>E<digit>`, e.g. a runId "1E2").
  $json = ($json -replace "`r`n", "`n").TrimEnd("`n") + "`n"
  Set-Content -LiteralPath $abs -Value $json -Encoding utf8NoBOM -NoNewline -ErrorAction Stop
} catch {
  Fail "cannot write record to $rel — no record written"
}

# Record is written — NOW emit one stderr note per unpriced tier. Emitting AFTER the
# write (not before) guarantees a write fail-open above stays a SINGLE stderr line,
# never note(s) + the fail line (parity with the .sh twin's ordering).
foreach ($t in $unpriced) {
  [Console]::Error.WriteLine("write-cost-record: tier '$t' has no rate table entry — recorded under unpricedTiers, excluded from costUsd")
}

[Console]::Out.Write($rel + "`n")
exit 0
