#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for render-daemon.ps1 (issue #208).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$script = Join-Path $here '..' 'scripts' 'render-daemon'

$pass = 0; $fail = 0; $skipped = 0
function Pass-T { $script:pass++ }
function Fail-T([string]$m) { $script:fail++; Write-Host "FAIL $m" }
function Skip-T([string]$m) { $script:skipped++; Write-Host "SKIP $m (python3 absent)" }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rd_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$state = Join-Path $tmp '.milestone-config/.runtime/render-daemon.json'
$py = if ($IsMacOS -and (Test-Path -LiteralPath '/usr/bin/python3')) { '/usr/bin/python3' } else { 'python3' }
$havePy = [bool](Get-Command $py -ErrorAction SilentlyContinue)
$port = 8732
$readyUrl = "http://127.0.0.1:$port/"

function Run-Daemon([string[]]$daemonArgs, [hashtable]$envVars = @{}) {
  $r = Invoke-Spawn -Script $script -Args $daemonArgs -Env $envVars
  return @{ out = ($r.out + $r.err); rc = $r.rc }
}

function Write-Profile([string]$serverCmd, [string]$url) {
  New-Item -ItemType Directory -Force -Path (Join-Path $tmp '.milestone-config') | Out-Null
  $obj = [ordered]@{ integrationBranch = 'develop'; visualCapture = [ordered]@{ serverCmd = $serverCmd; readyUrl = $url } }
  ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $tmp '.milestone-config/driver.json') -Encoding utf8NoBOM
}

function State-Field([string]$f) {
  if (-not (Test-Path -LiteralPath $state)) { return $null }
  try { $s = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json; return $s.$f } catch { return $null }
}

try {
  # ---- no-stub sub-cases (always run) -------------------------------------

  Write-Profile 'true' $readyUrl
  $r = Run-Daemon @('status', $tmp)
  if ($r.rc -eq 0 -and $r.out -match '(?i)no daemon') { Pass-T } else { Fail-T "status-empty: rc=$($r.rc) out=[$($r.out)]" }

  $r = Run-Daemon @('stop', $tmp)
  if ($r.rc -eq 0) { Pass-T } else { Fail-T "stop-empty: rc=$($r.rc) out=[$($r.out)]" }

  $r = Run-Daemon @('frobnicate', $tmp)
  if ($r.rc -ne 0 -and $r.out -match 'start\|status\|stop') { Pass-T } else { Fail-T "bad-usage: rc=$($r.rc) out=[$($r.out)]" }

  Write-Profile 'sleep 30' $readyUrl
  $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '2' }
  if ($r.rc -ne 0 -and $r.out -match [regex]::Escape($readyUrl)) {
    $s = Run-Daemon @('status', $tmp)
    if ($s.rc -eq 0 -and $s.out -match '(?i)no daemon') { Pass-T } else { Fail-T "boot-fail-status: rc=$($s.rc) out=[$($s.out)]" }
  } else { Fail-T "boot-fail: rc=$($r.rc) out=[$($r.out)]" }
  Run-Daemon @('stop', $tmp) | Out-Null

  foreach ($badpid in @(0, 1)) {
    Write-Profile 'true' $readyUrl
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp '.milestone-config/.runtime') | Out-Null
    $corrupt = [ordered]@{ port = 8731; token = 'corrupt'; pid = $badpid; readyUrl = $readyUrl; startedAt = '2020-01-01T00:00:00Z' }
    ($corrupt | ConvertTo-Json -Compress) | Set-Content -LiteralPath $state -Encoding utf8NoBOM
    $sentinel = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') -PassThru
    $rs = Run-Daemon @('stop', $tmp)
    $rt = Run-Daemon @('status', $tmp)
    $stateGone = -not (Test-Path -LiteralPath $state)
    $sentAlive = [bool](Get-Process -Id $sentinel.Id -ErrorAction SilentlyContinue)
    if ($rs.rc -eq 0 -and $rt.rc -eq 0 -and $stateGone -and $sentAlive) { Pass-T }
    else { Fail-T "malformed-pid(pid=$badpid): stop-rc=$($rs.rc) status-rc=$($rt.rc) state-removed=$stateGone sentinel-alive=$sentAlive (want 0/0/True/True)" }
    try { Stop-Process -Id $sentinel.Id -Force -ErrorAction SilentlyContinue } catch {}
  }

  # ---- stub-backed sub-cases (skip cleanly if python3 absent) -------------

  if ($havePy) {
    Write-Profile "$py -m http.server $port --bind 127.0.0.1" $readyUrl

    $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '15' }
    if ($r.rc -eq 0 -and (Test-Path -LiteralPath $state)) {
      $p = State-Field 'port'; $tok = State-Field 'token'; $pidv = State-Field 'pid'
      $rurl = State-Field 'readyUrl'
      $raw = Get-Content -LiteralPath $state -Raw
      $stOk = $raw -match '"startedAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
      if ([int]$p -eq $port -and $tok -and $pidv -and $rurl -eq $readyUrl -and $stOk) { Pass-T }
      else { Fail-T "autostart-state: port=$p tok=$tok pid=$pidv url=$rurl startedAt-raw-ok=$stOk raw=[$raw]" }
    } else { Fail-T "autostart: rc=$($r.rc) out=[$($r.out)]" }

    $pid1 = State-Field 'pid'
    $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '15' }
    $pid2 = State-Field 'pid'
    if ($r.rc -eq 0 -and "$pid1" -eq "$pid2" -and $r.out -match [string]$port) { Pass-T }
    else { Fail-T "reuse: rc=$($r.rc) pid1=$pid1 pid2=$pid2 out=[$($r.out)]" }

    $r = Run-Daemon @('status', $tmp)
    if ($r.rc -eq 0 -and $r.out -match [string]$port -and $r.out -match '(?i)ours') { Pass-T }
    else { Fail-T "status-up: rc=$($r.rc) out=[$($r.out)]" }

    $r = Run-Daemon @('stop', $tmp)
    $stopReaped = $false
    for ($i = 0; $i -lt 5; $i++) {
      if (-not (Get-Process -Id ([int]$pid1) -ErrorAction SilentlyContinue)) { $stopReaped = $true; break }
      Start-Sleep -Seconds 1
    }
    if (-not $stopReaped) {
      Stop-Process -Id ([int]$pid1) -Force -ErrorAction SilentlyContinue
    }
    if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath $state) -and $stopReaped) { Pass-T }
    else { Fail-T "teardown: rc=$($r.rc) state-exists=$(Test-Path -LiteralPath $state) stop-reaped=$stopReaped (stop did not reap the daemon within 5s - teardown regression)" }
    $r = Run-Daemon @('stop', $tmp)
    if ($r.rc -eq 0) { Pass-T } else { Fail-T "teardown-idempotent: rc=$($r.rc)" }

    $port2 = 8734
    $readyUrl2 = "http://127.0.0.1:$port2/"
    Write-Profile "$py -m http.server $port2 --bind 127.0.0.1 & wait" $readyUrl2
    $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '15' }
    $upBefore = $false
    try { $null = Invoke-WebRequest -Uri $readyUrl2 -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop; $upBefore = $true } catch {}
    if ($r.rc -eq 0 -and $upBefore) {
      Run-Daemon @('stop', $tmp) | Out-Null
      $freed = $false
      for ($i = 0; $i -lt 5; $i++) {
        $still = $false
        try { $null = Invoke-WebRequest -Uri $readyUrl2 -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop; $still = $true } catch {}
        if (-not $still) { $freed = $true; break }
        Start-Sleep -Seconds 1
      }
      if (-not (Test-Path -LiteralPath $state) -and $freed) { Pass-T }
      else { Fail-T "teardown-compound: state-removed=$(-not (Test-Path -LiteralPath $state)) port-freed=$freed (compound serverCmd leaked the listener - tree reap failed)" }
    } else { Fail-T "teardown-compound-setup: rc=$($r.rc) upBefore=$upBefore out=[$($r.out)] (compound serverCmd never came up; cannot test tree reap)" }
    Run-Daemon @('stop', $tmp) | Out-Null

    Write-Profile "$py -m http.server $port --bind 127.0.0.1" $readyUrl

    New-Item -ItemType Directory -Force -Path (Join-Path $tmp '.milestone-config/.runtime') | Out-Null
    $stale = [ordered]@{ port = $port; token = 'deadbeef'; pid = 999999; readyUrl = $readyUrl; startedAt = '2020-01-01T00:00:00Z' }
    ($stale | ConvertTo-Json -Compress) | Set-Content -LiteralPath $state -Encoding utf8NoBOM
    $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '15' }
    $newpid = State-Field 'pid'
    if ($r.rc -eq 0 -and "$newpid" -ne '999999' -and $newpid) { Pass-T }
    else { Fail-T "stale-autostart: rc=$($r.rc) newpid=$newpid out=[$($r.out)]" }
    Run-Daemon @('stop', $tmp) | Out-Null
  } else {
    Skip-T 'autostart'; Skip-T 'reuse'; Skip-T 'status-up'; Skip-T 'teardown'
    Skip-T 'teardown-idempotent'; Skip-T 'teardown-compound'; Skip-T 'stale-autostart'
  }
} finally {
  if (Test-Path -LiteralPath $state) { Run-Daemon @('stop', $tmp) | Out-Null }
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "render-daemon ($Leg): $pass passed, $fail failed, $skipped skipped"
if ($fail -ne 0) { exit 1 }
