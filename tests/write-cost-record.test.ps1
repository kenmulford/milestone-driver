#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for write-cost-record.ps1 (issue #320).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$script = Join-Path $here '..' 'scripts' 'write-cost-record'

$BASE = 'Opus 5.5 $4/$20 per MTok in/out; Sonnet 5.5 $2/$10 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.05x tier input rate; source: https://platform.claude.com/docs/en/about-claude/pricing, as-of 2026-11-21'

$pass = 0; $fail = 0
function Ok { $script:pass++ }
function No([string]$m) { $script:fail++; Write-Host "FAIL $m" }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("wcr_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null

function New-Ws { $w = Join-Path $root ([System.Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $w | Out-Null; return $w }
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
      $j.runId -eq 'run-happy' -and $j.wallClockSeconds -eq 42 -and $j.costUsd -eq 10.6 -and
      $j.tiers.opus.inputTokens -eq 400000 -and $j.tiers.opus.outputTokens -eq 40000 -and
      $j.tiers.opus.cacheReadTokens -eq 2000000 -and $j.tiers.opus.cacheWriteTokens -eq 160000 -and
      $j.tiers.opus.costUsd -eq 3.6 -and $j.tiers.sonnet.costUsd -eq 7 -and
      (@($j.unpricedTiers.PSObject.Properties).Count -eq 0) -and
      ($rawJson -match '"writtenAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"') -and
      $j.rateSnapshot -eq $BASE) { Ok } else {
    No "happy: rc=$($r.rc) err=[$($r.err)] out=[$($r.out)] snapshot=[$(if($j){$j.rateSnapshot})]" }

  # ---- runId sanitization: filename sanitized, body verbatim --------------
  $r = Run-Case '{"runId":"run/1 x","tiers":{"opus":{"inputTokens":1000000}}}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and ($r.out -match 'cost-records/run-1-x-[0-9]+-.+\.json') -and
      $j.runId -eq 'run/1 x' -and $j.tiers.opus.costUsd -eq 4) { Ok } else {
    No "sanitize: rc=$($r.rc) out=[$($r.out)] runId=[$(if($j){$j.runId})]" }

  # ---- omitted wallClock / tier / token-fields -> zeros -------------------
  $r = Run-Case '{"runId":"run-omit","tiers":{"opus":{"inputTokens":1000000}}}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $j -and $j.wallClockSeconds -eq 0 -and $j.costUsd -eq 4 -and
      $j.tiers.opus.inputTokens -eq 1000000 -and $j.tiers.opus.outputTokens -eq 0 -and
      $j.tiers.opus.cacheReadTokens -eq 0 -and $j.tiers.opus.cacheWriteTokens -eq 0 -and
      $j.tiers.opus.costUsd -eq 4) { Ok } else { No "omit-zeros: rc=$($r.rc)" }

  # ---- empty-state: omitted fields -> zeros present in record -------------
  $r = Run-Case '{"runId":"run-empty"}'
  $j = Rec-Json $r.ws
  if ($r.rc -eq 0 -and $r.err -eq '' -and $j -and $j.runId -eq 'run-empty' -and
      $j.wallClockSeconds -eq 0 -and $j.costUsd -eq 0 -and
      (@($j.tiers.PSObject.Properties).Count -eq 0) -and
      (@($j.unpricedTiers.PSObject.Properties).Count -eq 0) -and
      $j.rateSnapshot -eq $BASE -and $j.PSObject.Properties['writtenAt']) { Ok } else {
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
      $j.costUsd -eq 4 -and (-not $j.tiers.PSObject.Properties['weirdmodel']) -and
      $j.tiers.opus.costUsd -eq 4 -and
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
  if ($r.rc -eq 0 -and $j -and $j.costUsd -eq 4e-05 -and $j.tiers.opus.costUsd -eq 4e-05) { Ok } else {
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
  function Usage-File([string]$ws, [string]$sanitizedRunId, [string]$ext = 'jsonl') {
    Join-Path $ws (".milestone-config/.runtime/usage/$sanitizedRunId.$ext")
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

  # ---- append dispatch metrics: exact bytes, key order, each field gated ----
  function Append-Raw([string]$inputJson) {
    $w = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $w | Out-Null
    $r = Run-Append $w 'run-metrics' $inputJson
    $f = Usage-File $w 'run-metrics'
    $raw = if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -Raw } else { $null }
    return @{ rc = $r.rc; err = $r.err; raw = $raw }
  }
  function Append-Exact([string]$label, [string]$inputJson, [string]$expected) {
    $a = Append-Raw $inputJson
    if ($a.rc -eq 0 -and $a.err -eq '' -and $a.raw -ceq ($expected + "`n")) { Ok } else {
      No "$label`: rc=$($a.rc) err=[$($a.err)] raw=[$($a.raw)]" }
  }
  Append-Exact 'append-four-fields-bytes' '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678}' `
    '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678}'
  Append-Exact 'append-metrics-all' '{"minutesToFirstEdit":3.5,"stepsBeforeFirstEdit":7,"steps":42,"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678}' `
    '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678,"steps":42,"stepsBeforeFirstEdit":7,"minutesToFirstEdit":3.5}'
  Append-Exact 'append-metrics-minutes-dropped' '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678,"steps":42,"minutes":9.25}' `
    '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678,"steps":42}'
  Append-Exact 'append-nonnumeric-minutes-ignored' '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678,"minutes":"abc"}' `
    '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678}'
  Append-Exact 'append-metrics-steps-only' '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678,"steps":42}' `
    '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678,"steps":42}'
  Append-Exact 'append-metrics-null-absent' '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678,"steps":null,"stepsBeforeFirstEdit":0,"minutesToFirstEdit":null}' `
    '{"agent":"implementer","tier":"opus","totalTokens":1234,"durationMs":5678,"stepsBeforeFirstEdit":0}'

  # keys that differ only by case: jq accepts them and reads the lowercase members
  Append-Exact 'append-case-only-duplicate-keys' '{"agent":"implementer","Agent":5,"tier":"opus","TIER":1,"totalTokens":7,"TotalTokens":"x","durationMs":9}' `
    '{"agent":"implementer","tier":"opus","totalTokens":7,"durationMs":9}'

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
  Append-FailOpen 'append-nonnumeric-steps'      'run-x' '{"agent":"a","tier":"opus","steps":"many"}'
  Append-FailOpen 'append-nonnumeric-stepsfirst' 'run-x' '{"agent":"a","tier":"opus","stepsBeforeFirstEdit":true}'
  Append-FailOpen 'append-nonnumeric-minsfirst'  'run-x' '{"agent":"a","tier":"opus","minutesToFirstEdit":"3"}'
  # members are read by exact name, as jq does: a capitalized Agent or Tier is no agent or tier
  Append-FailOpen 'append-capitalized-members' 'run-x' '{"Agent":"x","Tier":"opus","totalTokens":1}'

  # ---- append missing runId arg -> fail-open, no crash ----------------------
  $wNoId = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wNoId | Out-Null
  $rNoId = Invoke-Leg -Script $script -Args @('--append') -Stdin '{"agent":"a","tier":"opus"}' -Cwd $wNoId
  if ($rNoId.rc -eq 0 -and (Err-Lines $rNoId.err) -eq 1) { Ok } else {
    No "append-missing-runid-arg: rc=$($rNoId.rc) errlines=$(Err-Lines $rNoId.err)" }

  # =====================================================================
  # --start <runId>: record the run's start time once, never overwrite it
  # =====================================================================
  function Run-Start([string]$ws, [string]$runId, [string]$sid = 'sess-start') {
    return Invoke-Leg -Script $script -Args @('--start', $runId) -Stdin '' -Cwd $ws -Env @{ CLAUDE_CODE_SESSION_ID = $sid }
  }
  function Start-Bytes([string]$f) {
    [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($f))
  }

  # ---- start first write: path on stdout, empty stderr, exact bytes, no .jsonl
  $wsS = New-Ws
  $rs = Run-Start $wsS 'run/1 x'
  $sf = Usage-File $wsS 'run-1-x' 'start'
  $usageDirS = Join-Path $wsS '.milestone-config/.runtime/usage'
  if ($rs.rc -eq 0 -and $rs.err -eq '' -and $rs.out -ceq ".milestone-config/.runtime/usage/run-1-x.start`n" -and
      (Test-Path -LiteralPath $sf) -and
      (Start-Bytes $sf) -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\nsess-start\n\z' -and
      @(Get-ChildItem -LiteralPath $usageDirS -Filter '*.jsonl' -ErrorAction SilentlyContinue).Count -eq 0) { Ok } else {
    No "start-first-write: rc=$($rs.rc) err=[$($rs.err)] out=[$($rs.out)] exists=$(Test-Path -LiteralPath $sf)" }

  # ---- start with no session id: line 2 is empty ------------------------------
  $wsS0 = New-Ws
  $rs0 = Run-Start $wsS0 'run-nosid' ''
  if ($rs0.rc -eq 0 -and $rs0.err -eq '' -and
      (Start-Bytes (Usage-File $wsS0 'run-nosid' 'start')) -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\n\n\z') { Ok } else {
    No "start-no-session-id: rc=$($rs0.rc) err=[$($rs0.err)] bytes=[$(Start-Bytes (Usage-File $wsS0 'run-nosid' 'start'))]" }

  # ---- start second call: existing file kept byte-for-byte -------------------
  [System.IO.File]::WriteAllText($sf, "2000-01-01T00:00:00Z`n", [System.Text.UTF8Encoding]::new($false))
  $rs2 = Run-Start $wsS 'run/1 x'
  if ($rs2.rc -eq 0 -and $rs2.err -eq '' -and $rs2.out -ceq ".milestone-config/.runtime/usage/run-1-x.start`n" -and
      (Start-Bytes $sf) -ceq "2000-01-01T00:00:00Z`n") { Ok } else {
    No "start-second-call: rc=$($rs2.rc) err=[$($rs2.err)] bytes=[$(Start-Bytes $sf)]" }

  # ---- start fail-open cases: one stderr line, empty stdout, no .start file --
  function Start-FailOpen([string]$label, [string[]]$startArgs, [string]$ws) {
    $r = Invoke-Leg -Script $script -Args $startArgs -Stdin '' -Cwd $ws
    $made = @(Get-ChildItem -LiteralPath $ws -Recurse -File -Filter '*.start' -ErrorAction SilentlyContinue).Count
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and $r.out -eq '' -and $made -eq 0) { Ok } else {
      No "$label`: rc=$($r.rc) errlines=$(Err-Lines $r.err) out=[$($r.out)] startfiles=$made" }
  }
  Start-FailOpen 'start-missing-runid-arg' @('--start') (New-Ws)
  Start-FailOpen 'start-empty-runid-arg' @('--start', '') (New-Ws)

  $wsOcc = New-Ws
  New-Item -ItemType Directory -Force -Path (Join-Path $wsOcc '.milestone-config/.runtime') | Out-Null
  Set-Content -LiteralPath (Join-Path $wsOcc '.milestone-config/.runtime/usage') -Value 'x' -NoNewline
  Start-FailOpen 'start-usage-occupied-by-file' @('--start', 'run-s') $wsOcc

  $wsRo = New-Ws
  $roDir = Join-Path $wsRo '.milestone-config/.runtime/usage'
  New-Item -ItemType Directory -Force -Path $roDir | Out-Null
  try { & chmod 555 $roDir 2>$null } catch {}
  $rRo = Run-Start $wsRo 'run-s'
  if (Test-Path -LiteralPath (Usage-File $wsRo 'run-s' 'start')) {
    Ok  # read-only not enforced on this FS (Windows) - write fail-open path unreachable; skip
  } elseif ($rRo.rc -eq 0 -and (Err-Lines $rRo.err) -eq 1 -and $rRo.out -eq '') { Ok } else {
    No "start-readonly-usage: rc=$($rRo.rc) errlines=$(Err-Lines $rRo.err) out=[$($rRo.out)]" }
  try { & chmod 755 $roDir 2>$null } catch {}

  # =====================================================================
  # --finalize <runId>: rebuild the run-end record from the usage file alone
  # =====================================================================
  function Run-Finalize([string]$ws, [string]$runId, [string]$dir = '', [hashtable]$Env = @{}) {
    $fargs = @('--finalize', $runId)
    if ($dir -ne '') { $fargs += $dir }
    return Invoke-Leg -Script $script -Args $fargs -Stdin '' -Cwd $ws -Env $Env
  }

  # ---- finalize happy path: two entries, same tier, sums + agents[] --------
  $wsF = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wsF | Out-Null
  Run-Append $wsF 'run-final' '{"agent":"implementer","tier":"opus","totalTokens":400000,"durationMs":10000}' | Out-Null
  Run-Append $wsF 'run-final' '{"agent":"code-review","tier":"opus","totalTokens":100000,"durationMs":5000}' | Out-Null
  $rf = Run-Finalize $wsF 'run-final'
  $jf = Rec-Json $wsF
  if ($rf.rc -eq 0 -and (Err-Lines $rf.err) -eq 1 -and ($rf.err -match 'no transcript directory argument - using unsplit totals') -and $jf -and
      $jf.runId -eq 'run-final' -and $jf.wallClockSeconds -eq 15 -and
      $jf.tiers.opus.inputTokens -eq 500000 -and $jf.tiers.opus.costUsd -eq 2 -and
      $jf.costUsd -eq 2 -and $jf.rateSnapshot -eq "$BASE; note: unsplit-total-as-input" -and
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
      $jf2.tiers.opus.costUsd -eq 4 -and $jf2.tiers.sonnet.costUsd -eq 2 -and
      $jf2.costUsd -eq 6 -and $jf2.unpricedTiers.haiku.inputTokens -eq 500 -and
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

  # ---- finalize over a line carrying dispatch metrics: output shape unchanged
  $wsFm = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $wsFm | Out-Null
  Run-Append $wsFm 'run-fm' '{"agent":"a","tier":"opus","totalTokens":1000000,"durationMs":1000,"steps":3,"stepsBeforeFirstEdit":1,"minutesToFirstEdit":0.5}' | Out-Null
  $rfm = Run-Finalize $wsFm 'run-fm'
  $jfm = Rec-Json $wsFm
  if ($rfm.rc -eq 0 -and (Err-Lines $rfm.err) -eq 1 -and ($rfm.err -match 'no transcript directory argument - using unsplit totals') -and $jfm -and $jfm.costUsd -eq 4 -and $jfm.wallClockSeconds -eq 1 -and
      (@($jfm.agents[0].PSObject.Properties.Name) -join ',') -ceq 'agent,tier,totalTokens,durationMs') { Ok } else {
    No "finalize-metrics-shape: rc=$($rfm.rc) err=[$($rfm.err)] j=[$(if($jfm){$jfm | ConvertTo-Json -Compress -Depth 5})]" }

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

  # ---- finalize per-turn: transcript sums, nested agent, dedup, start test --
  $tfx = Join-Path $here 'fixtures' 'write-cost-record' 'transcripts'
  function New-FinalizeWs([string]$runId, $startLine) {
    $w = New-Ws
    Run-Append $w $runId '{"agent":"implementer","tier":"opus","totalTokens":400000,"durationMs":10000}' | Out-Null
    Run-Append $w $runId '{"agent":"code-review","tier":"opus","totalTokens":100000,"durationMs":5000}' | Out-Null
    if ($null -ne $startLine) {
      Set-Content -LiteralPath (Usage-File $w $runId 'start') -Value $startLine -NoNewline
    }
    return $w
  }
  $wsP = New-FinalizeWs 'run-pt' '2026-11-21T10:00:00Z'
  $rp = Run-Finalize $wsP 'run-pt' $tfx
  $jp = Rec-Json $wsP
  if ($rp.rc -eq 0 -and (Err-Lines $rp.err) -eq 1 -and ($rp.err -match "tier 'claude-haiku-4-5' has no rate table entry") -and $jp -and
      (@($jp.tiers.PSObject.Properties.Name) -join ',') -ceq 'opus,sonnet' -and
      $jp.tiers.opus.inputTokens -eq 1000000 -and $jp.tiers.opus.outputTokens -eq 100000 -and
      $jp.tiers.opus.cacheReadTokens -eq 5000000 -and $jp.tiers.opus.cacheWriteTokens -eq 400000 -and $jp.tiers.opus.costUsd -eq 9 -and
      $jp.tiers.sonnet.inputTokens -eq 1000000 -and $jp.tiers.sonnet.outputTokens -eq 100000 -and
      $jp.tiers.sonnet.cacheReadTokens -eq 5000000 -and $jp.tiers.sonnet.cacheWriteTokens -eq 400000 -and $jp.tiers.sonnet.costUsd -eq 4.5 -and
      $jp.costUsd -eq 13.5 -and $jp.rateSnapshot -ceq "$BASE; note: per-turn-transcript-sum" -and
      $jp.unpricedTiers.'claude-haiku-4-5'.inputTokens -eq 1000 -and $jp.unpricedTiers.'claude-haiku-4-5'.outputTokens -eq 100 -and
      $jp.wallClockSeconds -eq 15 -and (@($jp.agents)).Count -eq 2) { Ok } else {
    No "finalize-per-turn: rc=$($rp.rc) err=[$($rp.err)] j=[$(if($jp){$jp | ConvertTo-Json -Compress -Depth 5})]" }

  # ---- finalize fallbacks: one stderr line naming the reason, unsplit record -
  function Finalize-Fallback([string]$label, $startLine, [bool]$missingDir, [string]$reasonPattern, [hashtable]$Env = @{}) {
    $runId = "run-$label"
    $w = New-FinalizeWs $runId $startLine
    $d = if ($missingDir) { Join-Path $w 'no-such-dir' } else { $tfx }
    $r = Run-Finalize $w $runId $d $Env
    $j = Rec-Json $w
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and ($r.err -match "$reasonPattern - using unsplit totals\s*$") -and $j -and
        $j.tiers.opus.inputTokens -eq 500000 -and $j.rateSnapshot -ceq "$BASE; note: unsplit-total-as-input") { Ok } else {
      No "$label`: rc=$($r.rc) err=[$($r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }
  }
  Finalize-Fallback 'finalize-fallback-dir-missing' '2026-11-21T10:00:00Z' $true 'transcript directory .+ not found'
  Finalize-Fallback 'finalize-fallback-start-absent' $null $false 'no start file at \.milestone-config/\.runtime/usage/run-finalize-fallback-start-absent\.start'
  Finalize-Fallback 'finalize-fallback-start-malformed' 'not-a-time' $false 'start file \.milestone-config/\.runtime/usage/run-finalize-fallback-start-malformed\.start is not %Y-%m-%dT%H:%M:%SZ'
  Finalize-Fallback 'finalize-fallback-none-after-start' '2026-11-21T11:00:00Z' $false 'no agent transcript at or after 2026-11-21T11:00:00Z in .+'

  # ---- finalize and the start file's session id (line 2) ---------------------
  Finalize-Fallback 'finalize-fallback-other-session' "2026-11-21T10:00:00Z`nsess-old" $false 'run started in another session' @{ CLAUDE_CODE_SESSION_ID = 'sess-new' }
  Finalize-Fallback 'finalize-fallback-session-now-unset' "2026-11-21T10:00:00Z`nsess-old" $false 'run started in another session' @{ CLAUDE_CODE_SESSION_ID = '' }
  foreach ($case in @(@('same-session', "2026-11-21T10:00:00Z`nsess-same"), @('start-without-session', "2026-11-21T10:00:00Z`n"))) {
    $runId = "run-finalize-$($case[0])"
    $w = New-FinalizeWs $runId $case[1]
    $r = Run-Finalize $w $runId $tfx @{ CLAUDE_CODE_SESSION_ID = 'sess-same' }
    $j = Rec-Json $w
    if ($r.rc -eq 0 -and $j -and $j.rateSnapshot -ceq "$BASE; note: per-turn-transcript-sum" -and $j.tiers.opus.inputTokens -eq 1000000 -and
        -not ($r.err -match 'using unsplit totals')) { Ok } else {
      No "finalize-$($case[0]): rc=$($r.rc) err=[$($r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }
  }

  # ---- finalize clears the run's usage + start files once the record is written
  function Run-Files($w, [string]$runId) { @((Usage-File $w $runId 'jsonl'), (Usage-File $w $runId 'start') | Where-Object { Test-Path -LiteralPath $_ }).Count }
  foreach ($case in @(@('clear-per-turn', $true), @('clear-unsplit', $false))) {
    $runId = "run-finalize-$($case[0])"
    $w = New-FinalizeWs $runId "2026-11-21T10:00:00Z`nsess-same"
    $before = Run-Files $w $runId
    $r = Run-Finalize $w $runId $(if ($case[1]) { $tfx } else { '' }) @{ CLAUDE_CODE_SESSION_ID = 'sess-same' }
    if ($before -eq 2 -and $r.rc -eq 0 -and (Rec-File $w) -and (Run-Files $w $runId) -eq 0) { Ok } else {
      No "$($case[0]): before=$before after=$(Run-Files $w $runId) rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w)" }
  }

  # ---- a rerun of a finalized runId starts a fresh window: its own start, its own record
  $w = New-FinalizeWs 'run-rerun' "2026-11-21T10:00:00Z`nsess-same"
  Run-Finalize $w 'run-rerun' $tfx @{ CLAUDE_CODE_SESSION_ID = 'sess-same' } | Out-Null
  Run-Start $w 'run-rerun' 'sess-next' | Out-Null
  Run-Append $w 'run-rerun' '{"agent":"a","tier":"sonnet","totalTokens":10,"durationMs":2000}' | Out-Null
  $rr = Run-Finalize $w 'run-rerun' $tfx @{ CLAUDE_CODE_SESSION_ID = 'sess-next' }
  $recs = @(Get-ChildItem -LiteralPath (Join-Path $w '.milestone-config/.runtime/cost-records') -File -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
  $own = @($recs | Where-Object { @($_.agents).Count -eq 1 })
  # The rerun's start is now, after every fixture turn: nothing matches, so it takes the unsplit path with only its own entry.
  if ($rr.rc -eq 0 -and $recs.Count -eq 2 -and $own.Count -eq 1 -and $own[0].tiers.sonnet.inputTokens -eq 10 -and
      (Run-Files $w 'run-rerun') -eq 0 -and $rr.err -match 'no agent transcript at or after') { Ok } else {
    No "finalize-rerun: rc=$($rr.rc) records=$($recs.Count) own=$($own.Count) files=$(Run-Files $w 'run-rerun') err=[$($rr.err)]" }

  # ---- a failed record write removes neither file ----------------------------
  foreach ($case in @('occupied', 'readonly')) {
    $runId = "run-finalize-keep-$case"
    $w = New-FinalizeWs $runId "2026-11-21T10:00:00Z`nsess-same"
    $crPath = Join-Path $w '.milestone-config/.runtime/cost-records'
    if ($case -eq 'occupied') { Set-Content -LiteralPath $crPath -Value 'x' -NoNewline }
    else { New-Item -ItemType Directory -Force -Path $crPath | Out-Null; try { & chmod 555 $crPath 2>$null } catch {} }
    $r = Run-Finalize $w $runId $tfx @{ CLAUDE_CODE_SESSION_ID = 'sess-same' }
    $wrote = if ($case -eq 'occupied') { $false } else { [bool](Rec-File $w) }
    if ($wrote) { Ok  # read-only not enforced on this FS (Windows) - write fail-open path unreachable; skip
    } elseif ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and (Run-Files $w $runId) -eq 2) { Ok } else {
      No "finalize-keep-on-failed-write-$case`: rc=$($r.rc) errlines=$(Err-Lines $r.err) files=$(Run-Files $w $runId) err=[$($r.err)]" }
    if ($case -eq 'readonly') { try { & chmod 755 $crPath 2>$null } catch {} }
  }

  # ---- per-turn edge paths: one fixture file per case ------------------------
  $efx = Join-Path $here 'fixtures' 'write-cost-record' 'edge'
  function Prop-Names($o) { if ($null -eq $o) { return '' }; (@($o.PSObject.Properties | ForEach-Object { $_.Name }) | Sort-Object) -join ',' }
  function Edge-Final([string]$fixture, [string]$startLine = '2026-11-21T10:00:00Z') {
    $d = New-Ws
    Copy-Item -LiteralPath (Join-Path $efx $fixture) -Destination $d
    $w = New-FinalizeWs "run-$fixture" $startLine
    $r = Run-Finalize $w "run-$fixture" $d
    $j = try { Rec-Json $w } catch { $null }
    return @{ r = $r; j = $j }
  }
  $perTurn = "$BASE; note: per-turn-transcript-sum"
  $unsplit = "$BASE; note: unsplit-total-as-input"

  # a turn before the file's first timestamp line is counted
  $e = Edge-Final 'agent-d-before-ts.jsonl'; $j = $e.j
  if ($j -and $j.rateSnapshot -ceq $perTurn -and $e.r.err -eq '' -and (Prop-Names $j.tiers) -ceq 'opus' -and
      $j.tiers.opus.inputTokens -eq 300 -and $j.tiers.opus.outputTokens -eq 30) { Ok } else {
    No "edge-turn-before-first-timestamp: err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # an unusable first timestamp, and a file with no timestamp, skip the file: nothing matches, unsplit fallback
  foreach ($case in @(@('agent-e-bad-ts.jsonl', 'edge-unusable-first-timestamp'), @('agent-f-no-ts.jsonl', 'edge-no-timestamp'))) {
    $e = Edge-Final $case[0]; $j = $e.j
    if ($j -and $j.rateSnapshot -ceq $unsplit -and (Err-Lines $e.r.err) -eq 1 -and
        $e.r.err -match 'no agent transcript at or after 2026-11-21T10:00:00Z in .+ - using unsplit totals\s*$' -and
        $j.tiers.opus.inputTokens -eq 500000) { Ok } else {
      No "$($case[1]): err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }
  }

  # a line nested 70 deep is counted
  $e = Edge-Final 'agent-g-deep.jsonl'; $j = $e.j
  if ($j -and $j.rateSnapshot -ceq $perTurn -and $e.r.err -eq '' -and (Prop-Names $j.tiers) -ceq 'sonnet' -and
      $j.tiers.sonnet.inputTokens -eq 1000 -and $j.tiers.sonnet.outputTokens -eq 100) { Ok } else {
    No "edge-deep-line: err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # an empty model is the `?` tier, unpriced
  $e = Edge-Final 'agent-h-empty-model.jsonl'; $j = $e.j
  if ($j -and $j.rateSnapshot -ceq $perTurn -and (Err-Lines $e.r.err) -eq 1 -and $e.r.err -match "tier '\?' has no rate table entry" -and
      (Prop-Names $j.tiers) -ceq '' -and (Prop-Names $j.unpricedTiers) -ceq '?' -and
      $j.unpricedTiers.'?'.inputTokens -eq 11 -and $j.unpricedTiers.'?'.outputTokens -eq 1 -and $j.costUsd -eq 0) { Ok } else {
    No "edge-empty-model: err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # only the 5.5 ids are priced: any other id is unpriced under its own name
  $e = Edge-Final 'agent-i-other-models.jsonl'; $j = $e.j
  if ($j -and $j.rateSnapshot -ceq $perTurn -and (Err-Lines $e.r.err) -eq 3 -and
      $e.r.err -match "tier 'claude-opus-4-8' has no rate table entry" -and $e.r.err -match "tier 'claude-sonnet-4-6' has no rate table entry" -and
      $e.r.err -match "tier 'claude-opus-5' has no rate table entry" -and
      (Prop-Names $j.tiers) -ceq '' -and $j.costUsd -eq 0 -and
      (Prop-Names $j.unpricedTiers) -ceq 'claude-opus-4-8,claude-opus-5,claude-sonnet-4-6' -and
      $j.unpricedTiers.'claude-opus-4-8'.inputTokens -eq 21 -and $j.unpricedTiers.'claude-sonnet-4-6'.outputTokens -eq 3 -and
      $j.unpricedTiers.'claude-opus-5'.inputTokens -eq 41) { Ok } else {
    No "edge-non-5.5-ids: err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # a count of 1e400 is not finite: 0, like a non-number
  $e = Edge-Final 'agent-j-nonfinite.jsonl'; $j = $e.j
  if ($j -and $j.rateSnapshot -ceq $perTurn -and $e.r.err -eq '' -and
      $j.tiers.sonnet.inputTokens -eq 0 -and $j.tiers.sonnet.outputTokens -eq 7 -and $j.costUsd -eq 0.00007) { Ok } else {
    No "edge-nonfinite-count: err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # a provider-prefixed 5.5 id is priced by family; a mid-word match is not
  $e = Edge-Final 'agent-k-prefixed-model.jsonl'; $j = $e.j
  if ($j -and $j.rateSnapshot -ceq $perTurn -and (Err-Lines $e.r.err) -eq 1 -and $e.r.err -match "tier 'xclaude-opus-5-5' has no rate table entry" -and
      (Prop-Names $j.tiers) -ceq 'opus,sonnet' -and $j.tiers.opus.inputTokens -eq 1000000 -and $j.tiers.sonnet.inputTokens -eq 1000000 -and
      $j.tiers.opus.costUsd -eq 6 -and $j.tiers.sonnet.costUsd -eq 3 -and $j.costUsd -eq 9 -and (Prop-Names $j.unpricedTiers) -ceq 'xclaude-opus-5-5') { Ok } else {
    No "edge-prefixed-model-id: err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # a first timestamp with a trailing newline, and one naming an impossible date that rolls over past the start, skip the file
  foreach ($case in @(@('agent-l-ts-newline.jsonl', '2026-11-21T10:00:00Z', 'edge-first-timestamp-trailing-newline'), @('agent-m-impossible-date.jsonl', '2026-01-01T00:00:00Z', 'edge-first-timestamp-impossible-date'))) {
    $e = Edge-Final $case[0] $case[1]; $j = $e.j
    if ($j -and $j.rateSnapshot -ceq $unsplit -and (Err-Lines $e.r.err) -eq 1 -and
        $e.r.err -match "no agent transcript at or after $($case[1]) in .+ - using unsplit totals\s*$" -and
        $j.tiers.opus.inputTokens -eq 500000) { Ok } else {
      No "$($case[2]): err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }
  }

  # a start file naming an impossible date takes the invalid-start fallback
  Finalize-Fallback 'finalize-fallback-start-impossible-date' '2026-02-30T00:00:00Z' $false 'start file \.milestone-config/\.runtime/usage/run-finalize-fallback-start-impossible-date\.start is not %Y-%m-%dT%H:%M:%SZ'

  # ---- a finalize that writes no record leaves no start file behind ----------
  # The next --start must open a fresh window, so the transcript dir holds a turn dated 2099 to be at or after it.
  $fut = New-Ws
  Copy-Item -LiteralPath (Join-Path $efx 'agent-n-future.jsonl') -Destination $fut
  $w = New-Ws
  Run-Start $w 'run-s1s2' 'sess-1' | Out-Null
  $r1 = Run-Finalize $w 'run-s1s2' $fut @{ CLAUDE_CODE_SESSION_ID = 'sess-1' }
  $startGone = -not (Test-Path -LiteralPath (Usage-File $w 'run-s1s2' 'start'))
  Run-Start $w 'run-s1s2' 'sess-2' | Out-Null
  Run-Append $w 'run-s1s2' '{"agent":"a","tier":"opus","totalTokens":10,"durationMs":2000}' | Out-Null
  $r2 = Run-Finalize $w 'run-s1s2' $fut @{ CLAUDE_CODE_SESSION_ID = 'sess-2' }
  $j = Rec-Json $w
  if ($r1.rc -eq 0 -and (Err-Lines $r1.err) -eq 1 -and $r1.err -match 'no usage data at' -and $startGone -and
      $r2.rc -eq 0 -and $r2.err -eq '' -and $j -and $j.rateSnapshot -ceq $perTurn -and $j.tiers.opus.inputTokens -eq 1000 -and
      (Run-Files $w 'run-s1s2') -eq 0) { Ok } else {
    No "finalize-no-usage-clears-start: r1err=[$($r1.err)] startGone=$startGone r2err=[$($r2.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # ---- a malformed usage file is moved aside, its start file removed, and the next run records ----
  $w = New-Ws
  $ufd = Join-Path $w '.milestone-config/.runtime/usage'
  New-Item -ItemType Directory -Force -Path $ufd | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $ufd 'run-mal.jsonl'), "not json`n", [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $ufd 'run-mal.start'), "2026-11-21T10:00:00Z`nsess-1`n", [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $ufd 'run-mal.jsonl.bad'), "older`n", [System.Text.UTF8Encoding]::new($false))
  $r1 = Run-Finalize $w 'run-mal' $fut @{ CLAUDE_CODE_SESSION_ID = 'sess-1' }
  $badPath = Join-Path $ufd 'run-mal.jsonl.bad'
  $badOk = (Test-Path -LiteralPath $badPath) -and ((Get-Content -LiteralPath $badPath -Raw) -ceq "not json`n")
  $gone = -not (Test-Path -LiteralPath (Usage-File $w 'run-mal' 'jsonl')) -and -not (Test-Path -LiteralPath (Usage-File $w 'run-mal' 'start'))
  Run-Start $w 'run-mal' 'sess-2' | Out-Null
  Run-Append $w 'run-mal' '{"agent":"a","tier":"opus","totalTokens":10,"durationMs":2000}' | Out-Null
  $r2 = Run-Finalize $w 'run-mal' $fut @{ CLAUDE_CODE_SESSION_ID = 'sess-2' }
  $j = Rec-Json $w
  if ($r1.rc -eq 0 -and (Err-Lines $r1.err) -eq 1 -and $r1.err -cmatch 'malformed usage data in \.milestone-config/\.runtime/usage/run-mal\.jsonl - no record written \(moved to run-mal\.jsonl\.bad\)\s*$' -and
      $badOk -and $gone -and $r2.rc -eq 0 -and $r2.err -eq '' -and $j -and $j.rateSnapshot -ceq $perTurn -and $j.tiers.opus.inputTokens -eq 1000) { Ok } else {
    No "finalize-malformed-moved-aside: r1err=[$($r1.err)] bad=$badOk gone=$gone r2err=[$($r2.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # ---- finalize: no usage file with a dir passed -> fail-open, no record -----
  $wsNd = New-Ws
  $rNd = Run-Finalize $wsNd 'run-nofile-dir' $tfx
  if ($rNd.rc -eq 0 -and (Err-Lines $rNd.err) -eq 1 -and ($rNd.err -match 'no usage data at') -and (-not (Rec-File $wsNd))) { Ok } else {
    No "finalize-nofile-with-dir: rc=$($rNd.rc) err=[$($rNd.err)] record=$(Rec-File $wsNd)" }

  # ---- every finalize exit that writes no record removes the start file ------
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  $usageLine = '{"agent":"a","tier":"opus","totalTokens":10,"durationMs":2000}' + "`n"
  # A workspace holding a start file and, when $usageBody is not null, a usage file with that body.
  function New-NoRecordWs([string]$runId, $usageBody) {
    $w = New-Ws
    $d = Join-Path $w '.milestone-config/.runtime/usage'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    if ($usageBody -is [byte[]]) { [System.IO.File]::WriteAllBytes((Join-Path $d "$runId.jsonl"), $usageBody) }
    elseif ($null -ne $usageBody) { [System.IO.File]::WriteAllText((Join-Path $d "$runId.jsonl"), $usageBody, $utf8) }
    [System.IO.File]::WriteAllText((Join-Path $d "$runId.start"), "2026-11-21T10:00:00Z`nsess-1`n", $utf8)
    return $w
  }
  # One no-record finalize: one stderr line matching $errPattern, no record, start file gone, usage path kept.
  function No-Record-Case([string]$label, [string]$runId, $w, [string]$errPattern, [hashtable]$Env = @{}) {
    $r = Run-Finalize $w $runId $tfx $Env
    $startGone = -not (Test-Path -LiteralPath (Usage-File $w $runId 'start'))
    $usageKept = Test-Path -LiteralPath (Usage-File $w $runId 'jsonl')
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and $r.err -cmatch $errPattern -and (-not (Rec-File $w)) -and $startGone -and $usageKept) { Ok } else {
      No "$label`: rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w) startGone=$startGone usageKept=$usageKept" }
  }

  # no usage file: the start file goes
  $w = New-NoRecordWs 'run-nr-nofile' $null
  $r = Run-Finalize $w 'run-nr-nofile' $tfx
  if ($r.rc -eq 0 -and $r.err -cmatch 'no usage data at' -and -not (Test-Path -LiteralPath (Usage-File $w 'run-nr-nofile' 'start'))) { Ok } else {
    No "finalize-nofile-removes-start: rc=$($r.rc) err=[$($r.err)]" }

  # The usage file renamed to <runId>.jsonl.bad with $body's bytes, and no .jsonl left behind.
  function Aside-Ok($w, [string]$runId, [byte[]]$body) {
    $bad = Usage-File $w $runId 'jsonl.bad'
    (Test-Path -LiteralPath $bad) -and ([Convert]::ToHexString([System.IO.File]::ReadAllBytes($bad)) -ceq [Convert]::ToHexString($body)) -and
      -not (Test-Path -LiteralPath (Usage-File $w $runId 'jsonl'))
  }
  # jq missing, and a jq that fails after the aggregation, on the sh leg: the start file goes, the usage file moves aside
  if ((Get-Leg) -eq 'sh' -and -not $IsWindows) {
    $nojq = Join-Path $root 'bin-nojq'; New-Item -ItemType Directory -Force -Path $nojq | Out-Null
    foreach ($b in @('tr', 'rm', 'mv', 'grep')) { Add-ToolStub $b $nojq }
    $w = New-NoRecordWs 'run-nr-nojq' $usageLine
    $r = Run-Finalize $w 'run-nr-nojq' $tfx @{ PATH = $nojq }
    $startGone = -not (Test-Path -LiteralPath (Usage-File $w 'run-nr-nojq' 'start'))
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and $r.err -cmatch 'jq is required but not on PATH - no record written \(moved to run-nr-nojq\.jsonl\.bad\)\s*$' -and
        (-not (Rec-File $w)) -and $startGone -and (Aside-Ok $w 'run-nr-nojq' $utf8.GetBytes($usageLine))) { Ok } else {
      No "finalize-jq-missing-removes-start: rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w) startGone=$startGone" }

    # no usage file: the no-usage check needs no jq and runs first, so it takes that exit and moves nothing
    $w = New-NoRecordWs 'run-nr-nojq-nousage' $null
    $r = Run-Finalize $w 'run-nr-nojq-nousage' $tfx @{ PATH = $nojq }
    $startGone = -not (Test-Path -LiteralPath (Usage-File $w 'run-nr-nojq-nousage' 'start'))
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and
        $r.err -cmatch 'no usage data at \.milestone-config/\.runtime/usage/run-nr-nojq-nousage\.jsonl - no record written\s*$' -and
        (-not (Rec-File $w)) -and $startGone -and -not (Test-Path -LiteralPath (Usage-File $w 'run-nr-nojq-nousage' 'jsonl.bad'))) { Ok } else {
      No "finalize-jq-missing-no-usage: rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w) startGone=$startGone" }

    $shim = Join-Path $root 'bin-jqfail'; New-Item -ItemType Directory -Force -Path $shim | Out-Null
    $realJq = (Get-Command jq -CommandType Application | Select-Object -First 1).Source
    $shimPath = Join-Path $shim 'jq'
    [System.IO.File]::WriteAllText($shimPath, "#!/bin/sh`nfor a in `"`$@`"; do [ `"`$a`" = `"`$JQ_FAIL_ARG`" ] && exit 9; done`nexec '$realJq' `"`$@`"`n", $utf8)
    & chmod 755 $shimPath
    $internalMsg = 'internal aggregation error over \.milestone-config/\.runtime/usage/{0}\.jsonl - no record written'
    $malformedInputMsg = 'malformed input \(unparseable JSON, missing/empty runId, or non-numeric token/wallClock\) - no record written'
    foreach ($case in @(
        @('input', '.input', $internalMsg),
        @('agents', '.agents', $internalMsg),
        @('attach', '.record.agents = $agents', 'internal aggregation error attaching agents - no record written'),
        @('written-at', 'writtenAt', $malformedInputMsg))) {
      $rid = "run-nr-internal-$($case[0])"
      $w = New-NoRecordWs $rid $usageLine
      $r = Run-Finalize $w $rid $tfx @{ PATH = "$shim$([System.IO.Path]::PathSeparator)$env:PATH"; JQ_FAIL_ARG = $case[1] }
      $startGone = -not (Test-Path -LiteralPath (Usage-File $w $rid 'start'))
      $msg = ($case[2] -f $rid) + " \(moved to $rid\.jsonl\.bad\)\s*$"
      if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and $r.err -cmatch $msg -and (-not (Rec-File $w)) -and $startGone -and
          (Aside-Ok $w $rid $utf8.GetBytes($usageLine))) { Ok } else {
        No "finalize-internal-error-$($case[0]): rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w) startGone=$startGone" }
    }
  }

  # a failed move-aside is reported as such, never as a move
  $w = New-NoRecordWs 'run-nr-mv' "not json`n"
  $mvDir = Join-Path $w '.milestone-config/.runtime/usage'
  try { & chmod 555 $mvDir 2>$null } catch {}
  $r = Run-Finalize $w 'run-nr-mv' $tfx
  try { & chmod 755 $mvDir 2>$null } catch {}
  if (-not (Test-Path -LiteralPath (Usage-File $w 'run-nr-mv' 'jsonl'))) {
    Ok  # read-only not enforced here (root, or Windows) - so the move cannot fail: skip
  } elseif ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and
      $r.err -cmatch 'malformed usage data in \.milestone-config/\.runtime/usage/run-nr-mv\.jsonl - no record written \(could not move it aside\)\s*$' -and
      -not (Rec-File $w)) { Ok } else {
    No "finalize-malformed-move-fails: rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w)" }

  # a usage file holding only whitespace is no usage data, like a missing one
  $w = New-NoRecordWs 'run-nr-blank' "   `n`t`r`n  `n"
  No-Record-Case 'finalize-whitespace-usage' 'run-nr-blank' $w 'no usage data at \.milestone-config/\.runtime/usage/run-nr-blank\.jsonl - no record written\s*$'

  # a directory at the usage path is no usage data
  $w = New-NoRecordWs 'run-nr-dir' $null
  New-Item -ItemType Directory -Force -Path (Usage-File $w 'run-nr-dir' 'jsonl') | Out-Null
  No-Record-Case 'finalize-usage-path-is-directory' 'run-nr-dir' $w 'no usage data at \.milestone-config/\.runtime/usage/run-nr-dir\.jsonl - no record written\s*$'

  # an unreadable usage file is no usage data (skipped when the process can read it anyway: root, or Windows)
  $w = New-NoRecordWs 'run-nr-unreadable' $usageLine
  $unreadable = Usage-File $w 'run-nr-unreadable' 'jsonl'
  try { & chmod 000 $unreadable 2>$null } catch {}
  $canRead = try { [void][System.IO.File]::ReadAllText($unreadable); $true } catch { $false }
  if ($canRead) {
    try { & chmod 644 $unreadable 2>$null } catch {}
    Ok
  } else {
    No-Record-Case 'finalize-unreadable-usage' 'run-nr-unreadable' $w 'no usage data at \.milestone-config/\.runtime/usage/run-nr-unreadable\.jsonl - no record written\s*$'
    try { & chmod 644 $unreadable 2>$null } catch {}
  }

  # a start file dated before 1970 names that in its fallback, and an impossible pre-1970 date is not a timestamp
  # at all; a first transcript timestamp before 1970 is before any start, so that transcript is skipped
  Finalize-Fallback 'finalize-fallback-start-pre-1970' '1969-12-31T23:59:59Z' $false 'start file \.milestone-config/\.runtime/usage/run-finalize-fallback-start-pre-1970\.start is before 1970'
  Finalize-Fallback 'finalize-fallback-start-1960' '1960-01-01T00:00:00Z' $false 'start file \.milestone-config/\.runtime/usage/run-finalize-fallback-start-1960\.start is before 1970'
  Finalize-Fallback 'finalize-fallback-start-pre-1970-impossible' '1960-02-30T00:00:00Z' $false 'start file \.milestone-config/\.runtime/usage/run-finalize-fallback-start-pre-1970-impossible\.start is not %Y-%m-%dT%H:%M:%SZ'
  $e = Edge-Final 'agent-o-pre-1970.jsonl'; $j = $e.j
  if ($j -and $j.rateSnapshot -ceq $unsplit -and (Err-Lines $e.r.err) -eq 1 -and
      $e.r.err -match 'no agent transcript at or after 2026-11-21T10:00:00Z in .+ - using unsplit totals\s*$' -and
      $j.tiers.opus.inputTokens -eq 500000) { Ok } else {
    No "edge-first-timestamp-before-1970: err=[$($e.r.err)] j=[$(if($j){$j | ConvertTo-Json -Compress -Depth 5})]" }

  # a usage file holding only a BOM and spaces, or only a no-break space, is data jq cannot read: moved aside, not "no usage data";
  # so is a valid line followed by a line of only a vertical tab, a form feed or a no-break space, which are not JSON whitespace
  # A usage line holds exactly one JSON object between JSON whitespace: a leading no-break space, a trailing vertical tab or
  # form feed, a one-element array, two objects, or a lone CR between objects is not that, and neither is a bad line between good ones.
  $lineBytes = $utf8.GetBytes($usageLine)
  $obj = $usageLine.TrimEnd("`n")
  $objBytes = $utf8.GetBytes($obj)
  foreach ($case in @(@('bom-spaces', [byte[]](0xEF, 0xBB, 0xBF, 0x20, 0x20, 0x0A)), @('nbsp', [byte[]](0xC2, 0xA0, 0x0A)),
      @('line-vt', [byte[]]($lineBytes + [byte[]](0x0B, 0x0A))), @('line-ff', [byte[]]($lineBytes + [byte[]](0x0C, 0x0A))),
      @('line-nbsp', [byte[]]($lineBytes + [byte[]](0xC2, 0xA0, 0x0A))),
      @('line-lead-nbsp', [byte[]]([byte[]](0xC2, 0xA0) + $lineBytes)),
      @('line-trail-vt', [byte[]]($objBytes + [byte[]](0x0B, 0x0A))), @('line-trail-ff', [byte[]]($objBytes + [byte[]](0x0C, 0x0A))),
      @('line-array', [byte[]]($utf8.GetBytes("[$obj]`n"))),
      @('line-two-objects', [byte[]]($utf8.GetBytes("$obj$obj`n"))),
      @('line-two-objects-cr', [byte[]]($utf8.GetBytes("$obj`r$obj`n"))),
      @('line-capitalized-members', [byte[]]($utf8.GetBytes('{"Agent":"a","Tier":"opus","totalTokens":10}' + "`n"))),
      @('valid-bad-valid', [byte[]]($lineBytes + $utf8.GetBytes("not json`n") + $lineBytes)))) {
    $rid = "run-nr-usage-$($case[0])"
    $w = New-NoRecordWs $rid $case[1]
    $r = Run-Finalize $w $rid $tfx
    $startGone = -not (Test-Path -LiteralPath (Usage-File $w $rid 'start'))
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and
        $r.err -cmatch "malformed usage data in \.milestone-config/\.runtime/usage/$rid\.jsonl - no record written \(moved to $rid\.jsonl\.bad\)\s*$" -and
        (-not (Rec-File $w)) -and $startGone -and (Aside-Ok $w $rid $case[1])) { Ok } else {
      No "finalize-usage-$($case[0]): rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w) startGone=$startGone" }
  }

  # a blank interior line, with or without JSON whitespace on it, is skipped by both twins, so the two lines make one record
  $rid = 'run-nr-interior-blank'
  $w = New-NoRecordWs $rid ($usageLine + " `t`r`n`n" + $usageLine)
  $r = Run-Finalize $w $rid
  $j = Rec-Json $w
  if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and $r.err -match 'no transcript directory argument - using unsplit totals' -and $j -and
      @($j.agents).Count -eq 2 -and $j.tiers.opus.inputTokens -eq 20 -and -not (Test-Path -LiteralPath (Usage-File $w $rid 'jsonl.bad'))) { Ok } else {
    No "finalize-usage-interior-blank: rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w)" }

  # a usage line whose keys differ only by case is one record: jq reads the lowercase members
  $rid = 'run-nr-case-keys'
  $w = New-NoRecordWs $rid ('{"agent":"a","Agent":5,"tier":"opus","Tier":1,"totalTokens":10,"TotalTokens":"x","durationMs":2000}' + "`n")
  $r = Run-Finalize $w $rid
  $j = Rec-Json $w
  if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and $r.err -match 'no transcript directory argument - using unsplit totals' -and $j -and
      @($j.agents).Count -eq 1 -and $j.tiers.opus.inputTokens -eq 10 -and $j.agents[0].agent -ceq 'a') { Ok } else {
    No "finalize-usage-case-only-duplicate-keys: rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w)" }

  # a file at the cost-records path is `cannot create` in both twins, and keeps the usage and start files, moving nothing aside
  $rid = 'run-nr-cannot-create'
  $w = New-FinalizeWs $rid "2026-11-21T10:00:00Z`nsess-same"
  Set-Content -LiteralPath (Join-Path $w '.milestone-config/.runtime/cost-records') -Value 'x' -NoNewline
  $r = Run-Finalize $w $rid $tfx @{ CLAUDE_CODE_SESSION_ID = 'sess-same' }
  if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and
      $r.err -cmatch '^write-cost-record: cannot create \.milestone-config/\.runtime/cost-records - no record written\s*$' -and
      (Run-Files $w $rid) -eq 2 -and -not (Test-Path -LiteralPath (Usage-File $w $rid 'jsonl.bad'))) { Ok } else {
    No "finalize-cannot-create-keeps-files: rc=$($r.rc) err=[$($r.err)] files=$(Run-Files $w $rid)" }

  # a read-only cost-records directory is `cannot write record to` in both twins, and keeps both files
  # (skipped as root or on Windows, where read-only does not stop the write)
  $isRoot = -not $IsWindows -and ((& id -u) -eq '0')
  if ($IsWindows -or $isRoot) { Ok } else {
    $rid = 'run-nr-write-fails'
    $w = New-FinalizeWs $rid "2026-11-21T10:00:00Z`nsess-same"
    $crPath = Join-Path $w '.milestone-config/.runtime/cost-records'
    New-Item -ItemType Directory -Force -Path $crPath | Out-Null
    & chmod 555 $crPath
    try { $r = Run-Finalize $w $rid $tfx @{ CLAUDE_CODE_SESSION_ID = 'sess-same' } } finally { & chmod 755 $crPath }
    if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and
        $r.err -cmatch "^write-cost-record: cannot write record to \.milestone-config/\.runtime/cost-records/$rid-[0-9]+-[0-9]+-[0-9]+-[0-9]+\.json - no record written\s*$" -and
        (Run-Files $w $rid) -eq 2 -and -not (Test-Path -LiteralPath (Usage-File $w $rid 'jsonl.bad'))) { Ok } else {
      No "finalize-write-fails-keeps-files: rc=$($r.rc) err=[$($r.err)] files=$(Run-Files $w $rid)" }
  }

  # a directory at <runId>.jsonl.bad blocks the move: the usage file stays put and the message says so
  $rid = 'run-nr-bad-dir'
  $w = New-NoRecordWs $rid "not json`n"
  $badDir = Usage-File $w $rid 'jsonl.bad'
  New-Item -ItemType Directory -Force -Path $badDir | Out-Null
  $r = Run-Finalize $w $rid $tfx
  $startGone = -not (Test-Path -LiteralPath (Usage-File $w $rid 'start'))
  if ($r.rc -eq 0 -and (Err-Lines $r.err) -eq 1 -and
      $r.err -cmatch "malformed usage data in \.milestone-config/\.runtime/usage/$rid\.jsonl - no record written \(could not move it aside\)\s*$" -and
      (Test-Path -LiteralPath (Usage-File $w $rid 'jsonl') -PathType Leaf) -and @(Get-ChildItem -LiteralPath $badDir -Force).Count -eq 0 -and
      $startGone -and -not (Rec-File $w)) { Ok } else {
    No "finalize-bad-name-is-dir: rc=$($r.rc) err=[$($r.err)] record=$(Rec-File $w) startGone=$startGone" }
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "write-cost-record ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
