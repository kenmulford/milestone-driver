#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for write-cost-record.ps1 (issue #320).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$script = Join-Path $here '..' 'scripts' 'write-cost-record'

$BASE = 'Opus 4.8 $5/$25 per MTok in/out; Sonnet 4.6 $3/$15 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.1x tier input rate; source: kenmulford/milestone-suite benchmarks/after/RESULTS.md, as-of 2026-07'

$pass = 0; $fail = 0
function Ok { $script:pass++ }
function No([string]$m) { $script:fail++; Write-Host "FAIL $m" }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("wcr_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Run-Case([string]$inputJson) {
  $ws = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $ws | Out-Null
  $r = Invoke-Leg -Script $script -Stdin $inputJson -Cwd $ws
  return @{ out = $r.out; err = $r.err; rc = $r.rc; ws = $ws }
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
  $p = Invoke-Leg -Script $script -Stdin '{"runId":"run-nodir","tiers":{"opus":{"inputTokens":1000000}}}' -Cwd $ws
  $uerr = $p.err
  if ($p.rc -eq 0 -and (Err-Lines $uerr) -eq 1 -and (-not (Rec-File $ws))) { Ok } else {
    No "uncreatable-dir: rc=$($p.rc) errlines=$(Err-Lines $uerr) record=$(Rec-File $ws)" }

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
  $p = Invoke-Leg -Script $script -Stdin '{"runId":"r","tiers":{"gpt":{"inputTokens":1}}}' -Cwd $ws
  $uerr = $p.err
  if (Rec-File $ws) {
    Ok  # read-only not enforced on this FS (Windows) - write fail-open path unreachable; skip
  } elseif ($p.rc -eq 0 -and (Err-Lines $uerr) -eq 1) { Ok } else {
    No "failopen-write-unpriced-oneline: rc=$($p.rc) errlines=$(Err-Lines $uerr) record=$(Rec-File $ws)" }
  try { & chmod 755 $crDir 2>$null } catch {}

  # ---- runId / provenanceNote with `<digit>E<digit>` preserved VERBATIM ------
  $r = Run-Case '{"runId":"1E2","provenanceNote":"batch 2E10 rows"}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and $j.runId -eq '1E2' -and
      $j.rateSnapshot -eq "$BASE; note: batch 2E10 rows") { Ok } else {
    No "verbatim-E: rc=$($r.rc) runId=[$(if($j){$j.runId})] snap=[$(if($j){$j.rateSnapshot})]" }

  # =====================================================================
  # --append <runId>: one usage line per dispatch, survives compaction (D5)
  # =====================================================================
  function Usage-File([string]$ws, [string]$sanitizedRunId) {
    Join-Path $ws (".milestone-config/.runtime/usage/$sanitizedRunId.jsonl")
  }
  function Run-Append([string]$ws, [string]$runId, [string]$inputJson) {
    return Invoke-Leg -Script $script -Args @('--append', $runId) -Stdin $inputJson -Cwd $ws
  }

  # ---- append happy path: one line, exact fields, LF-terminated -----------
  $ws = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $ws | Out-Null
  $r = Run-Append $ws 'run-append' '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678}'
  $uf = Usage-File $ws 'run-append'
  $raw = if (Test-Path -LiteralPath $uf) { Get-Content -LiteralPath $uf -Raw } else { $null }
  if ($r.rc -eq 0 -and $r.err -eq '' -and ($r.out -match 'usage/run-append\.jsonl') -and
      $raw -and (-not $raw.Contains("`r")) -and $raw.EndsWith("`n") -and
      (@($raw -split "`n" | Where-Object { $_ -ne '' })).Count -eq 1) {
    $line = ($raw -split "`n")[0] | ConvertFrom-Json
    if ($line.agent -eq 'implementer' -and $line.tier -eq 'opus' -and
        $line.totalTokens -eq 1234 -and $line.durationMs -eq 5678) { Ok } else {
      No "append-happy-fields: line=[$raw]" }
  } else { No "append-happy: rc=$($r.rc) err=[$($r.err)] out=[$($r.out)] raw=[$raw]" }

  # ---- append a second time: TWO lines, second appended not overwritten ----
  $r2 = Run-Append $ws 'run-append' '{"agent":"code-review","tier":"sonnet","totalTokens":99,"durationMs":11}'
  $raw2 = if (Test-Path -LiteralPath $uf) { Get-Content -LiteralPath $uf -Raw } else { $null }
  $lines2 = @(if ($raw2) { $raw2 -split "`n" | Where-Object { $_ -ne '' } } else { @() })
  if ($r2.rc -eq 0 -and $lines2.Count -eq 2 -and
      (($lines2[1] | ConvertFrom-Json).agent -eq 'code-review')) { Ok } else {
    No "append-second: rc=$($r2.rc) lines=$($lines2.Count)" }

  # ---- append omitted totalTokens/durationMs -> zeros ----------------------
  $ws3 = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $ws3 | Out-Null
  $r3 = Run-Append $ws3 'run-omit2' '{"agent":"implementer","tier":"opus"}'
  $uf3 = Usage-File $ws3 'run-omit2'
  $line3 = if (Test-Path -LiteralPath $uf3) { (Get-Content -LiteralPath $uf3 -Raw).Trim() | ConvertFrom-Json } else { $null }
  if ($r3.rc -eq 0 -and $line3 -and $line3.totalTokens -eq 0 -and $line3.durationMs -eq 0) { Ok } else {
    No "append-omit-zeros: rc=$($r3.rc)" }

  # ---- append fail-open cases: exactly one stderr line, no line written ----
  function Append-FailOpen([string]$label, [string]$runId, [string]$json) {
    $w = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $w | Out-Null
    $r = Run-Append $w $runId $json
    $uf = if ($runId) { Usage-File $w ($runId -replace '[^A-Za-z0-9._-]', '-') } else { $null }
    $exists = $uf -and (Test-Path -LiteralPath $uf)
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and (-not $exists)) { Ok } else {
      No "$label`: rc=$($r.rc) errlines=$(Err-Lines $r.err) exists=$exists" }
  }
  Append-FailOpen 'append-empty-stdin'    'run-x' ''
  Append-FailOpen 'append-malformed-json' 'run-x' '{not valid'
  Append-FailOpen 'append-missing-agent'  'run-x' '{"tier":"opus"}'
  Append-FailOpen 'append-empty-agent'    'run-x' '{"agent":"","tier":"opus"}'
  Append-FailOpen 'append-missing-tier'   'run-x' '{"agent":"a"}'
  Append-FailOpen 'append-nonnumeric-tt'  'run-x' '{"agent":"a","tier":"opus","totalTokens":"lots"}'
  Append-FailOpen 'append-nonnumeric-dur' 'run-x' '{"agent":"a","tier":"opus","durationMs":"soon"}'

  # ---- append missing runId arg -> fail-open, no crash ----------------------
  $wNoId = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wNoId | Out-Null
  $rNoId = Invoke-Leg -Script $script -Args @('--append') -Stdin '{"agent":"a","tier":"opus"}' -Cwd $wNoId
  if ($rNoId.rc -eq 0 -and (Err-Lines $rNoId.err) -eq 1) { Ok } else {
    No "append-missing-runid-arg: rc=$($rNoId.rc) errlines=$(Err-Lines $rNoId.err)" }

  # =====================================================================
  # --finalize <runId>: rebuild the run-end record from the usage file alone
  # =====================================================================
  function Run-Finalize([string]$ws, [string]$runId) {
    return Invoke-Leg -Script $script -Args @('--finalize', $runId) -Stdin '' -Cwd $ws
  }

  # ---- finalize happy path: two entries, same tier, sums + agents[] --------
  $wsF = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wsF | Out-Null
  Run-Append $wsF 'run-final' '{"agent":"implementer","tier":"opus","totalTokens":400000,"durationMs":10000}' | Out-Null
  Run-Append $wsF 'run-final' '{"agent":"code-review","tier":"opus","totalTokens":100000,"durationMs":5000}' | Out-Null
  $rf = Run-Finalize $wsF 'run-final'
  $jf = Rec-Json $wsF
  if ($rf.rc -eq 0 -and $rf.err -eq '' -and $jf -and
      $jf.runId -eq 'run-final' -and $jf.wallClockSeconds -eq 15 -and
      $jf.tiers.opus.inputTokens -eq 500000 -and $jf.tiers.opus.costUsd -eq 2.5 -and
      $jf.costUsd -eq 2.5 -and $jf.rateSnapshot -eq "$BASE; note: unsplit-total-as-input" -and
      $jf.agents -and (@($jf.agents)).Count -eq 2 -and
      ($jf.agents[0].agent -eq 'implementer') -and ($jf.agents[0].durationMs -eq 10000) -and
      ($jf.agents[1].agent -eq 'code-review') -and ($jf.agents[1].durationMs -eq 5000)) { Ok } else {
    No "finalize-happy: rc=$($rf.rc) err=[$($rf.err)] j=[$(if($jf){$jf | ConvertTo-Json -Compress})]" }

  # ---- finalize: two different tiers, unpriced tier included ---------------
  $wsF2 = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wsF2 | Out-Null
  Run-Append $wsF2 'run-final2' '{"agent":"a","tier":"opus","totalTokens":1000000,"durationMs":1000}' | Out-Null
  Run-Append $wsF2 'run-final2' '{"agent":"b","tier":"sonnet","totalTokens":1000000,"durationMs":2000}' | Out-Null
  Run-Append $wsF2 'run-final2' '{"agent":"c","tier":"haiku","totalTokens":500,"durationMs":500}' | Out-Null
  $rf2 = Run-Finalize $wsF2 'run-final2'
  $jf2 = Rec-Json $wsF2
  if ($rf2.rc -eq 0 -and ($rf2.err -match 'haiku') -and $jf2 -and
      $jf2.tiers.opus.costUsd -eq 5 -and $jf2.tiers.sonnet.costUsd -eq 3 -and
      $jf2.costUsd -eq 8 -and $jf2.unpricedTiers.haiku.inputTokens -eq 500 -and
      $jf2.wallClockSeconds -eq 3.5 -and (@($jf2.agents)).Count -eq 3) { Ok } else {
    No "finalize-multi-tier: rc=$($rf2.rc) err=[$($rf2.err)]" }

  # ---- append + finalize: tier lowercased, identical on both legs ----------
  $wsFc = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wsFc | Out-Null
  Run-Append $wsFc 'run-case' '{"agent":"a","tier":"opus","totalTokens":1000000,"durationMs":1000}' | Out-Null
  Run-Append $wsFc 'run-case' '{"agent":"b","tier":"Opus","totalTokens":700,"durationMs":1000}' | Out-Null
  $caseLine = @(Get-Content -LiteralPath (Join-Path $wsFc '.milestone-config/.runtime/usage/run-case.jsonl'))[1]
  $rfc = Run-Finalize $wsFc 'run-case'
  $jfc = Rec-Json $wsFc
  if ($rfc.rc -eq 0 -and $jfc -and ($caseLine -cmatch '"tier":"opus"') -and
      (@($jfc.tiers.PSObject.Properties.Name) -join ',') -ceq 'opus' -and
      (@($jfc.unpricedTiers.PSObject.Properties).Count -eq 0) -and
      $jfc.tiers.opus.inputTokens -eq 1000700 -and $jfc.agents[1].tier -ceq 'opus') { Ok } else {
    No "tier-lowercase: rc=$($rfc.rc) line=[$caseLine] err=[$($rfc.err)] j=[$(if($jfc){$jfc | ConvertTo-Json -Compress -Depth 5})]" }

  # ---- finalize: no usage file -> fail-open, no record ----------------------
  $wsF3 = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wsF3 | Out-Null
  $rf3 = Run-Finalize $wsF3 'run-nofile'
  if ($rf3.rc -eq 0 -and (Err-Lines $rf3.err) -eq 1 -and (-not (Rec-File $wsF3))) { Ok } else {
    No "finalize-nofile: rc=$($rf3.rc) errlines=$(Err-Lines $rf3.err) record=$(Rec-File $wsF3)" }

  # ---- finalize: malformed line in the usage file -> fail-open, no record ---
  $wsF4 = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wsF4 | Out-Null
  $ufDir = Join-Path $wsF4 '.milestone-config/.runtime/usage'
  New-Item -ItemType Directory -Force -Path $ufDir | Out-Null
  Set-Content -LiteralPath (Join-Path $ufDir 'run-bad.jsonl') -Value "not json`n" -NoNewline
  $rf4 = Run-Finalize $wsF4 'run-bad'
  if ($rf4.rc -eq 0 -and (Err-Lines $rf4.err) -eq 1 -and (-not (Rec-File $wsF4))) { Ok } else {
    No "finalize-malformed-line: rc=$($rf4.rc) errlines=$(Err-Lines $rf4.err)" }

  # ---- finalize: missing runId arg -> fail-open ------------------------------
  $wsF5 = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wsF5 | Out-Null
  $rf5 = Invoke-Leg -Script $script -Args @('--finalize') -Stdin '' -Cwd $wsF5
  if ($rf5.rc -eq 0 -and (Err-Lines $rf5.err) -eq 1) { Ok } else {
    No "finalize-missing-runid-arg: rc=$($rf5.rc) errlines=$(Err-Lines $rf5.err)" }
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "write-cost-record ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
