#!/usr/bin/env pwsh
# milestone-driver — behavior matrix runner for render-daemon.ps1 (issue #208).
# Behavior-identical pwsh twin of tests/render-daemon.test.sh: drives the
# render-daemon lifecycle (start | status | stop) against a throwaway app server
# and asserts the SAME command + state-file contract (cross-impl parity).
# Stub server: a trivial python3 HTTP server is the consumer serverCmd; absent,
# the stub-backed sub-cases SKIP cleanly (mirroring the .sh twin's python3 guard).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'render-daemon.ps1'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

$pass = 0; $fail = 0; $skipped = 0
function Pass-T { $script:pass++ }
function Fail-T([string]$m) { $script:fail++; Write-Host "FAIL $m" }
function Skip-T([string]$m) { $script:skipped++; Write-Host "SKIP $m (python3 absent)" }

# Throwaway workspace root.
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rd_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$state = Join-Path $tmp '.milestone-config/.runtime/render-daemon.json'
$havePy = [bool](Get-Command python3 -ErrorAction SilentlyContinue)
$port = 8732
$readyUrl = "http://127.0.0.1:$port/"

# Invoke the daemon; capture stdout+stderr (merged) and exit code.
function Run-Daemon([string[]]$daemonArgs, [hashtable]$envVars = @{}) {
  $old = @{}
  foreach ($k in $envVars.Keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, [string]$envVars[$k]) }
  try {
    $out = & pwsh -NoProfile -File $script @daemonArgs 2>&1 | Out-String
    return @{ out = $out; rc = $LASTEXITCODE }
  } finally {
    foreach ($k in $envVars.Keys) { [Environment]::SetEnvironmentVariable($k, $old[$k]) }
  }
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

  # bad usage -> nonzero, usage message naming the subcommand set on stderr.
  # (No state file is touched by a bad-usage exit; the meaningful assertions are
  # the nonzero rc and the usage line naming start/status/stop.)
  $r = Run-Daemon @('frobnicate', $tmp)
  if ($r.rc -ne 0 -and $r.out -match 'start\|status\|stop') { Pass-T } else { Fail-T "bad-usage: rc=$($r.rc) out=[$($r.out)]" }

  # boot-failure: serverCmd never serves readyUrl -> fail loud nonzero, probe URL
  # named on stderr, no live daemon afterward.
  Write-Profile 'sleep 30' $readyUrl
  $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '2' }
  if ($r.rc -ne 0 -and $r.out -match [regex]::Escape($readyUrl)) {
    $s = Run-Daemon @('status', $tmp)
    if ($s.rc -eq 0 -and $s.out -match '(?i)no daemon') { Pass-T } else { Fail-T "boot-fail-status: rc=$($s.rc) out=[$($s.out)]" }
  } else { Fail-T "boot-fail: rc=$($r.rc) out=[$($r.out)]" }
  Run-Daemon @('stop', $tmp) | Out-Null

  # Malformed-pid footgun guard (parity with the .sh valid_pgid regression): a
  # state file recording pid 0 / 1 must read as DOWN — stop/status exit 0, the
  # state file is removed, and NOTHING external is killed. The pwsh twin already
  # rejects processId <= 0 in Test-PidAlive (render-daemon.ps1:165) so Remove-
  # DaemonState never walks/kills a tree; this case CONFIRMS that parity (it would
  # regress if the guard were dropped). We prove "nothing killed" with a sentinel
  # process we own: it must still be alive after stop/status. (The .sh twin's
  # group-kill footgun has no pwsh analogue — pwsh kills an explicit pid tree, not
  # a negative-pgid group — but the pid<=0 reject is the same fail-closed rule, so
  # we assert the same observable contract.)
  foreach ($badpid in @(0, 1)) {
    Write-Profile 'true' $readyUrl
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp '.milestone-config/.runtime') | Out-Null
    $corrupt = [ordered]@{ port = 8731; token = 'corrupt'; pid = $badpid; readyUrl = $readyUrl; startedAt = '2020-01-01T00:00:00Z' }
    ($corrupt | ConvertTo-Json -Compress) | Set-Content -LiteralPath $state -Encoding utf8NoBOM
    # Sentinel process we own; a stray kill targeting a bad pid must not reach it.
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
    Write-Profile "python3 -m http.server $port --bind 127.0.0.1" $readyUrl

    # Happy autostart: exit 0, well-formed state file, port parsed from readyUrl.
    $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '15' }
    if ($r.rc -eq 0 -and (Test-Path -LiteralPath $state)) {
      $p = State-Field 'port'; $tok = State-Field 'token'; $pidv = State-Field 'pid'
      $rurl = State-Field 'readyUrl'
      # startedAt: assert the RAW on-disk JSON string (parity with the .sh twin's
      # jq read). ConvertFrom-Json auto-coerces an ISO-8601 string into a
      # [DateTime] that stringifies to a culture format, so State-Field can't see
      # the bytes the daemon wrote — read the file raw and match the exact
      # "startedAt":"<ISO-8601-UTC>" the daemon's Now-Iso emits.
      $raw = Get-Content -LiteralPath $state -Raw
      $stOk = $raw -match '"startedAt":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'
      if ([int]$p -eq $port -and $tok -and $pidv -and $rurl -eq $readyUrl -and $stOk) { Pass-T }
      else { Fail-T "autostart-state: port=$p tok=$tok pid=$pidv url=$rurl startedAt-raw-ok=$stOk raw=[$raw]" }
    } else { Fail-T "autostart: rc=$($r.rc) out=[$($r.out)]" }

    # Reuse: second start reuses (same pid), reports port, exit 0.
    $pid1 = State-Field 'pid'
    $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '15' }
    $pid2 = State-Field 'pid'
    if ($r.rc -eq 0 -and "$pid1" -eq "$pid2" -and $r.out -match [string]$port) { Pass-T }
    else { Fail-T "reuse: rc=$($r.rc) pid1=$pid1 pid2=$pid2 out=[$($r.out)]" }

    # status when up: port + ours verdict, exit 0.
    $r = Run-Daemon @('status', $tmp)
    if ($r.rc -eq 0 -and $r.out -match [string]$port -and $r.out -match '(?i)ours') { Pass-T }
    else { Fail-T "status-up: rc=$($r.rc) out=[$($r.out)]" }

    # Idempotent teardown: stop kills pid, removes state, exit 0; pid dead; 2nd stop no-op.
    # stop signals the recorded daemon best-effort and returns WITHOUT waiting, so
    # the death is asynchronous — poll for it rather than asserting in the same
    # instant (on a loaded runner the recorded process can still be alive for a
    # microsecond after stop returns). Same bound as the .sh twin (5x1s) to keep
    # the pair behavior-identical (.project/conventions.md#Test patterns), mirroring
    # the sibling poll-with-timeout in the compound-teardown case below. The 5s
    # window is generous and deterministic — on the happy path stop reaps the
    # process on the first iteration, so $stopReaped flips to $true and the case
    # PASSES.
    #
    # The escalation is a DIAGNOSTIC SAFETY NET, not a silent rescue (parity with
    # the .sh twin): if the grace window elapses with the process STILL alive,
    # stop did NOT reap it within 5s — a real teardown regression, not flake. We
    # still Stop-Process -Force the orphan (suite hygiene — the pwsh analogue of
    # SIGKILL; note pwsh kills an explicit pid, not a negative-pgid group, so it
    # has no group-signal footgun and needs no valid_pgid guard), but $stopReaped
    # stays $false so the assertion FAILS loudly. An escalation kill must never
    # flip the result to PASS, otherwise a broken stop would hide behind the
    # test's own cleanup (state-removed always passes — Remove-DaemonState removes
    # the file unconditionally — so the liveness check is the only catch).
    $r = Run-Daemon @('stop', $tmp)
    $stopReaped = $false
    for ($i = 0; $i -lt 5; $i++) {
      if (-not (Get-Process -Id ([int]$pid1) -ErrorAction SilentlyContinue)) { $stopReaped = $true; break }
      Start-Sleep -Seconds 1
    }
    if (-not $stopReaped) {
      # Orphan hygiene only — does NOT count as a pass.
      Stop-Process -Id ([int]$pid1) -Force -ErrorAction SilentlyContinue
    }
    if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath $state) -and $stopReaped) { Pass-T }
    else { Fail-T "teardown: rc=$($r.rc) state-exists=$(Test-Path -LiteralPath $state) stop-reaped=$stopReaped (stop did not reap the daemon within 5s — teardown regression)" }
    $r = Run-Daemon @('stop', $tmp)
    if ($r.rc -eq 0) { Pass-T } else { Fail-T "teardown-idempotent: rc=$($r.rc)" }

    # Compound-serverCmd teardown (genuineness guard for the process-TREE reap):
    # `python3 -m http.server ... & wait` backgrounds the listener and keeps the
    # spawned bash wrapper alive on `wait` — so the recorded pid is the WRAPPER
    # and the real listener is a CHILD (mirrors a realistic `npm start` that
    # forks). A wrapper-only kill would leave the listener holding the port; only
    # a descendant-tree reap frees it. Probe the readyUrl post-stop: it must no
    # longer answer. Uses a 2nd port so it never collides with the autostart case.
    $port2 = 8734
    $readyUrl2 = "http://127.0.0.1:$port2/"
    Write-Profile "python3 -m http.server $port2 --bind 127.0.0.1 & wait" $readyUrl2
    $r = Run-Daemon @('start', $tmp) @{ RENDER_DAEMON_TIMEOUT = '15' }
    $upBefore = $false
    try { $null = Invoke-WebRequest -Uri $readyUrl2 -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop; $upBefore = $true } catch {}
    if ($r.rc -eq 0 -and $upBefore) {
      Run-Daemon @('stop', $tmp) | Out-Null
      # Probe a few times post-stop: the port must no longer answer.
      $freed = $false
      for ($i = 0; $i -lt 5; $i++) {
        $still = $false
        try { $null = Invoke-WebRequest -Uri $readyUrl2 -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop; $still = $true } catch {}
        if (-not $still) { $freed = $true; break }
        Start-Sleep -Seconds 1
      }
      if (-not (Test-Path -LiteralPath $state) -and $freed) { Pass-T }
      else { Fail-T "teardown-compound: state-removed=$(-not (Test-Path -LiteralPath $state)) port-freed=$freed (compound serverCmd leaked the listener — tree reap failed)" }
    } else { Fail-T "teardown-compound-setup: rc=$($r.rc) upBefore=$upBefore out=[$($r.out)] (compound serverCmd never came up; cannot test tree reap)" }
    Run-Daemon @('stop', $tmp) | Out-Null

    # restore the single-command profile for the stale-state case below.
    Write-Profile "python3 -m http.server $port --bind 127.0.0.1" $readyUrl

    # Stale state file: dead recorded pid + failing probe -> cleaned, autostart (fresh pid).
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

Write-Host "render-daemon.ps1: $pass passed, $fail failed, $skipped skipped"
if ($fail -ne 0) { exit 1 }
