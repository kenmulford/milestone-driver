#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for write-cost-record.ps1 (issue #320).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'write-cost-record.ps1'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

$BASE = 'Opus 4.8 $5/$25 per MTok in/out; Sonnet 4.6 $3/$15 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.1x tier input rate; source: kenmulford/milestone-suite benchmarks/after/RESULTS.md, as-of 2026-07'

$pass = 0; $fail = 0
function Ok { $script:pass++ }
function No([string]$m) { $script:fail++; Write-Host "FAIL $m" }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("wcr_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Run-Case([string]$inputJson) {
  $ws = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $ws | Out-Null
  $inFile  = Join-Path $ws '.stdin'
  $outFile = Join-Path $ws '.stdout'
  $errFile = Join-Path $ws '.stderr'
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
  if (-not (Test-Path -LiteralPath $d -PathType Container)) { return $null }
  $f = Get-ChildItem -LiteralPath $d -File -Filter '*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($f) { return $f.FullName } else { return $null }
}
function Rec-Json($ws) { $r = Rec-File $ws; if ($r) { Get-Content -LiteralPath $r -Raw | ConvertFrom-Json } else { $null } }

try {
  # ---- happy path: both priced tiers, exact dollar math --------------------
  $r = Run-Case '{"runId":"run-happy","wallClockSeconds":42,"tiers":{"opus":{"inputTokens":400000,"outputTokens":40000,"cacheReadTokens":2000000,"cacheWriteTokens":160000},"sonnet":{"inputTokens":1000000,"outputTokens":200000,"cacheReadTokens":10000000,"cacheWriteTokens":800000}}}'
  $j = Rec-Json $r.ws
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
  $r = Run-Case '{"runId":"x","tiers":{"opus":42}}'
  if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and (-not (Rec-File $r.ws))) { Ok } else {
    No "nonobject-tier: rc=$($r.rc) errlines=$(Err-Lines $r.err) record=$(Rec-File $r.ws)" }

  # ---- tiny sub-1e-4 costUsd asserted by NUMERIC VALUE (not float bytes) -----
  $r = Run-Case '{"runId":"run-tiny","tiers":{"opus":{"outputTokens":2}}}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and $j.costUsd -eq 5e-05 -and $j.tiers.opus.costUsd -eq 5e-05) { Ok } else {
    No "tiny-sci: rc=$($r.rc) costUsd=[$(if($j){$j.costUsd})]" }

  # ---- fail-open AT THE WRITE + unpriced tier -> STILL exactly one stderr line -
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
    Ok  # read-only not enforced on this FS (Windows) - write fail-open path unreachable; skip
  } elseif ($p.ExitCode -eq 0 -and (Err-Lines $uerr) -eq 1) { Ok } else {
    No "failopen-write-unpriced-oneline: rc=$($p.ExitCode) errlines=$(Err-Lines $uerr) record=$(Rec-File $ws)" }
  try { & chmod 755 $crDir 2>$null } catch {}

  # ---- runId / provenanceNote with `<digit>E<digit>` preserved VERBATIM ------
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
