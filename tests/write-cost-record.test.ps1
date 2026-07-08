#!/usr/bin/env pwsh
# milestone-driver — behavior matrix runner for write-cost-record.ps1 (issue #320).
# Behavior-identical pwsh twin of tests/write-cost-record.test.sh: drives the
# cache-aware cost-record helper and asserts the SAME field + rateSnapshot +
# fail-open contract (cross-impl parity). Each case runs the helper with its
# WorkingDirectory set to a fresh temp workspace so cost-records/ lands there
# (test isolation — .project/environment.md#Data stores).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'write-cost-record.ps1'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

# rateSnapshot provenance base string (single-quoted so $ is literal). Byte-
# identical to scripts/write-cost-record.ps1 and the .sh twin + its test.
$BASE = 'Opus 4.8 $5/$25 per MTok in/out; Sonnet 4.6 $3/$15 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.1x tier input rate; source: kenmulford/milestone-suite benchmarks/after/RESULTS.md, as-of 2026-07'

$pass = 0; $fail = 0
function Ok { $script:pass++ }
function No([string]$m) { $script:fail++; Write-Host "FAIL $m" }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("wcr_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null

# Run the helper with WorkingDirectory = a fresh workspace and $Input on stdin.
# Returns @{ out; err; rc; ws }.
function Run-Case([string]$inputJson) {
  $ws = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $ws | Out-Null
  $inFile  = Join-Path $ws '.stdin'
  $outFile = Join-Path $ws '.stdout'
  $errFile = Join-Path $ws '.stderr'
  # -NoNewline so empty stdin stays truly empty (parity with the .sh `printf %s`).
  [System.IO.File]::WriteAllText($inFile, $inputJson, (New-Object System.Text.UTF8Encoding($false)))
  $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $script) `
        -WorkingDirectory $ws -RedirectStandardInput $inFile `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
        -NoNewWindow -PassThru -Wait
  $out = if (Test-Path $outFile) { [System.IO.File]::ReadAllText($outFile) } else { '' }
  $err = if (Test-Path $errFile) { [System.IO.File]::ReadAllText($errFile) } else { '' }
  return @{ out = $out; err = $err; rc = $p.ExitCode; ws = $ws }
}
function Err-Lines($err) { @($err -split "`r?`n" | Where-Object { $_ -ne '' }).Count }
function Rec-File($ws) {
  $d = Join-Path $ws '.milestone-config/.runtime/cost-records'
  # -PathType Container: a FILE pre-created at the cost-records PATH (the F7a
  # uncreatable-dir case) must count as NO record dir. Without it Test-Path is true
  # for that file AND Get-ChildItem -LiteralPath <file> -Filter '*.json' returns the
  # leaf file itself, falsely reporting a phantom record.
  if (-not (Test-Path -LiteralPath $d -PathType Container)) { return $null }
  $f = Get-ChildItem -LiteralPath $d -File -Filter '*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($f) { return $f.FullName } else { return $null }
}
function Rec-Json($ws) { $r = Rec-File $ws; if ($r) { Get-Content -LiteralPath $r -Raw | ConvertFrom-Json } else { $null } }

try {
  # ---- happy path: both priced tiers, exact dollar math --------------------
  # opus 400000/40000/2000000cRead/160000cWrite = 5.0 ; sonnet
  # 1000000/200000/10000000cRead/800000cWrite = 12.0 -> total 17.0
  $r = Run-Case '{"runId":"run-happy","wallClockSeconds":42,"tiers":{"opus":{"inputTokens":400000,"outputTokens":40000,"cacheReadTokens":2000000,"cacheWriteTokens":160000},"sonnet":{"inputTokens":1000000,"outputTokens":200000,"cacheReadTokens":10000000,"cacheWriteTokens":800000}}}'
  $j = Rec-Json $r.ws
  # writtenAt: assert the RAW on-disk string — ConvertFrom-Json auto-coerces an
  # ISO-8601 string into a [DateTime] that stringifies to a culture format, so
  # $j.writtenAt can't see the bytes the helper wrote (parity with the .sh jq read
  # and render-daemon.test.ps1:117).
  $rf = Rec-File $r.ws
  $rawJson = if ($rf) { Get-Content -LiteralPath $rf -Raw } else { '' }
  if ($r.rc -eq 0 -and $r.err -eq '' -and $j -and
      ($r.out -match 'cost-records/run-happy-[0-9]+-.+\.json') -and
      (Test-Path (Join-Path $r.ws ($r.out.Trim()))) -and
      $j.runId -eq 'run-happy' -and $j.wallClockSeconds -eq 42 -and $j.costUsd -eq 17 -and
      $j.tiers.opus.inputTokens -eq 400000 -and $j.tiers.opus.outputTokens -eq 40000 -and
      $j.tiers.opus.cacheReadTokens -eq 2000000 -and $j.tiers.opus.cacheWriteTokens -eq 160000 -and
      $j.tiers.opus.costUsd -eq 5 -and $j.tiers.sonnet.costUsd -eq 12 -and
      (@($j.unpricedTiers.PSObject.Properties).Count -eq 0) -and
      ($rawJson -match '"writtenAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"') -and
      $j.rateSnapshot -eq $BASE) { Ok } else {
    No "happy: rc=$($r.rc) err=[$($r.err)] out=[$($r.out)] snapshot=[$(if($j){$j.rateSnapshot})]" }

  # ---- runId sanitization: filename sanitized, body verbatim --------------
  $r = Run-Case '{"runId":"run/1 x","tiers":{"opus":{"inputTokens":1000000}}}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and ($r.out -match 'cost-records/run-1-x-[0-9]+-.+\.json') -and
      $j.runId -eq 'run/1 x' -and $j.tiers.opus.costUsd -eq 5) { Ok } else {
    No "sanitize: rc=$($r.rc) out=[$($r.out)] runId=[$(if($j){$j.runId})]" }

  # ---- omitted wallClock / tier / token-fields -> zeros -------------------
  $r = Run-Case '{"runId":"run-omit","tiers":{"opus":{"inputTokens":1000000}}}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and $j.wallClockSeconds -eq 0 -and $j.costUsd -eq 5 -and
      $j.tiers.opus.inputTokens -eq 1000000 -and $j.tiers.opus.outputTokens -eq 0 -and
      $j.tiers.opus.cacheReadTokens -eq 0 -and $j.tiers.opus.cacheWriteTokens -eq 0 -and
      $j.tiers.opus.costUsd -eq 5) { Ok } else { No "omit-zeros: rc=$($r.rc)" }

  # ---- empty-state: omitted fields -> zeros present in record -------------
  $r = Run-Case '{"runId":"run-empty"}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $r.err -eq '' -and $j -and $j.runId -eq 'run-empty' -and
      $j.wallClockSeconds -eq 0 -and $j.costUsd -eq 0 -and
      (@($j.tiers.PSObject.Properties).Count -eq 0) -and
      (@($j.unpricedTiers.PSObject.Properties).Count -eq 0) -and
      $j.PSObject.Properties['rateSnapshot'] -and $j.PSObject.Properties['writtenAt']) { Ok } else {
    No "empty-state: rc=$($r.rc) err=[$($r.err)]" }

  # ---- fail-open cases: exactly one stderr line, NO record, exit 0 --------
  function Fail-Open([string]$label, [string]$json) {
    $r = Run-Case $json
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and (-not (Rec-File $r.ws))) { Ok } else {
      No "$label`: rc=$($r.rc) errlines=$(Err-Lines $r.err) record=$(Rec-File $r.ws)" }
  }
  Fail-Open 'empty-stdin'      ''
  Fail-Open 'malformed-json'   '{not valid json'
  Fail-Open 'nonnumeric-token' '{"runId":"x","tiers":{"opus":{"inputTokens":"lots"}}}'
  Fail-Open 'nonnumeric-wall'  '{"runId":"x","wallClockSeconds":"soon"}'
  Fail-Open 'missing-runid'    '{"wallClockSeconds":1}'
  Fail-Open 'empty-runid'      '{"runId":""}'
  Fail-Open 'nonstring-runid'  '{"runId":123}'

  # ---- unknown (unpriced) tier --------------------------------------------
  $r = Run-Case '{"runId":"run-unpriced","tiers":{"opus":{"inputTokens":1000000},"weirdmodel":{"inputTokens":5,"outputTokens":6,"cacheReadTokens":7,"cacheWriteTokens":8}}}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and ($r.err -match 'weirdmodel') -and
      $j.costUsd -eq 5 -and (-not $j.tiers.PSObject.Properties['weirdmodel']) -and
      $j.tiers.opus.costUsd -eq 5 -and
      $j.unpricedTiers.weirdmodel.inputTokens -eq 5 -and $j.unpricedTiers.weirdmodel.outputTokens -eq 6 -and
      $j.unpricedTiers.weirdmodel.cacheReadTokens -eq 7 -and $j.unpricedTiers.weirdmodel.cacheWriteTokens -eq 8 -and
      (-not $j.unpricedTiers.weirdmodel.PSObject.Properties['costUsd'])) { Ok } else {
    No "unpriced: rc=$($r.rc) err=[$($r.err)]" }

  # ---- provenanceNote present -> "; note: <note>" suffix ------------------
  $r = Run-Case '{"runId":"run-note","provenanceNote":"manual backfill"}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and $j.rateSnapshot -eq "$BASE; note: manual backfill") { Ok } else {
    No "note-present: rc=$($r.rc) snap=[$(if($j){$j.rateSnapshot})]" }

  # ---- provenanceNote non-string -> treated as absent (byte-identical base) -
  $r = Run-Case '{"runId":"run-badnote","provenanceNote":123}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $r.err -eq '' -and $j -and $j.rateSnapshot -eq $BASE) { Ok } else {
    No "note-nonstring: rc=$($r.rc) err=[$($r.err)] snap=[$(if($j){$j.rateSnapshot})]" }

  # ---- (F7a) cost-records path occupied by a FILE -> dir uncreatable -> fail-open
  # Pre-create a regular FILE where the cost-records/ dir must go, then run the
  # helper in that workspace. On Windows New-Item -Directory -Force silently
  # succeeds but leaves the file, so the subsequent record write fails open; the
  # contract holds either way: one stderr line, NO record, exit 0.
  $ws = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $ws '.milestone-config/.runtime') | Out-Null
  Set-Content -LiteralPath (Join-Path $ws '.milestone-config/.runtime/cost-records') -Value 'x' -NoNewline
  $inFile = Join-Path $ws '.stdin'; $outFile = Join-Path $ws '.stdout'; $errFile = Join-Path $ws '.stderr'
  [System.IO.File]::WriteAllText($inFile, '{"runId":"run-nodir","tiers":{"opus":{"inputTokens":1000000}}}', (New-Object System.Text.UTF8Encoding($false)))
  $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $script) `
        -WorkingDirectory $ws -RedirectStandardInput $inFile `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
        -NoNewWindow -PassThru -Wait
  $uerr = if (Test-Path $errFile) { [System.IO.File]::ReadAllText($errFile) } else { '' }
  if ($p.ExitCode -eq 0 -and (Err-Lines $uerr) -eq 1 -and (-not (Rec-File $ws))) { Ok } else {
    No "uncreatable-dir: rc=$($p.ExitCode) errlines=$(Err-Lines $uerr) record=$(Rec-File $ws)" }

  # ---- (F7b) non-object tier value -> malformed -> fail-open (F5 parity) -----
  # A scalar tier value (opus=42) is malformed; the F5 guard now fails open to
  # match bash's jq error. Both: one stderr line, no record, exit 0.
  $r = Run-Case '{"runId":"x","tiers":{"opus":42}}'
  if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and (-not (Rec-File $r.ws))) { Ok } else {
    No "nonobject-tier: rc=$($r.rc) errlines=$(Err-Lines $r.err) record=$(Rec-File $r.ws)" }

  # ---- tiny sub-1e-4 costUsd asserted by NUMERIC VALUE (not float bytes) -----
  # opus outputTokens=2 -> 2*25/1e6 = 5e-05. The on-disk float form is serializer-
  # dependent (ConvertTo-Json emits `5E-05`, jq 1.8 `0.00005`, jq 1.7 `5e-05`) — all
  # valid JSON for the same value — so assert the parsed NUMBER, never the bytes.
  $r = Run-Case '{"runId":"run-tiny","tiers":{"opus":{"outputTokens":2}}}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and $j.costUsd -eq 5e-05 -and $j.tiers.opus.costUsd -eq 5e-05) { Ok } else {
    No "tiny-sci: rc=$($r.rc) costUsd=[$(if($j){$j.costUsd})]" }

  # ---- fail-open AT THE WRITE + unpriced tier -> STILL exactly one stderr line -
  # An unpriced tier normally prints a note; but when the RECORD WRITE fails open the
  # note MUST NOT precede the fail line — exactly ONE stderr line. Use a READ-ONLY
  # cost-records DIR so New-Item -Force succeeds (dir exists) but Set-Content fails
  # AFTER the unpriced tier is computed — reaches the write fail-open branch and
  # exercises the emit-notes-AFTER-write ordering. chmod bites on the CI (Linux/macOS)
  # leg; where perms don't bite (Windows) the record writes and we skip.
  $ws = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  $crDir = Join-Path $ws '.milestone-config/.runtime/cost-records'
  New-Item -ItemType Directory -Force -Path $crDir | Out-Null
  try { & chmod 555 $crDir 2>$null } catch {}
  $inFile = Join-Path $ws '.stdin'; $outFile = Join-Path $ws '.stdout'; $errFile = Join-Path $ws '.stderr'
  [System.IO.File]::WriteAllText($inFile, '{"runId":"r","tiers":{"gpt":{"inputTokens":1}}}', (New-Object System.Text.UTF8Encoding($false)))
  $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $script) `
        -WorkingDirectory $ws -RedirectStandardInput $inFile `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
        -NoNewWindow -PassThru -Wait
  $uerr = if (Test-Path $errFile) { [System.IO.File]::ReadAllText($errFile) } else { '' }
  if (Rec-File $ws) {
    Ok  # read-only not enforced on this FS (Windows) — write fail-open path unreachable; skip
  } elseif ($p.ExitCode -eq 0 -and (Err-Lines $uerr) -eq 1) { Ok } else {
    No "failopen-write-unpriced-oneline: rc=$($p.ExitCode) errlines=$(Err-Lines $uerr) record=$(Rec-File $ws)" }
  try { & chmod 755 $crDir 2>$null } catch {}

  # ---- runId / provenanceNote with `<digit>E<digit>` preserved VERBATIM ------
  # Guards against any exponent-normalizing rewrite bleeding into string fields
  # (would turn runId "1E2" -> "1e2"). Body must carry the raw values.
  $r = Run-Case '{"runId":"1E2","provenanceNote":"batch 2E10 rows"}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and $j.runId -eq '1E2' -and
      $j.rateSnapshot -eq "$BASE; note: batch 2E10 rows") { Ok } else {
    No "verbatim-E: rc=$($r.rc) runId=[$(if($j){$j.runId})] snap=[$(if($j){$j.rateSnapshot})]" }
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "write-cost-record.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
