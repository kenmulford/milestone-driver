#!/usr/bin/env pwsh
# milestone-driver — render-daemon lifecycle seam (issue #208).
#
# Behavior-identical pwsh twin of scripts/render-daemon.sh. Boots the consumer's
# seeded/persona app server ONCE per run and reuses it across the run; tears it
# down at run end. Built for the SERIAL capture path only — a single per-run
# daemon on the consumer's configured port (under --parallel, render capture is
# deferred to the serial tail — skills/solve-issue/SKILL.md:321).
#
# Inputs are read DIRECTLY from the profile .milestone-config/driver.json
# (mirroring the native-JSON profile-read in scripts/ci-preflight-steps.ps1:52-57):
#   visualCapture.serverCmd  — the command that boots the app server.
#   visualCapture.readyUrl   — the full /health-style ready-probe URL. The port
#                              is the consumer's; parsed from readyUrl for the
#                              state file's informational `port` field — NOT
#                              dynamically allocated.
# The visualCapture block is defined/documented by sibling issue #209; this
# script only READS serverCmd + readyUrl (key names fixed by spec).
#
# Usage:   render-daemon.ps1 <start|status|stop> [REPO_ROOT]
#   start  — reuse-or-autostart (reuse only when the recorded process is still a
#            live, OURS process tree AND the readyUrl probe passes; else spawn
#            serverCmd DETACHED, poll readyUrl within a bounded timeout, exit 0
#            when ready / fail loud nonzero on boot failure, reaping the partial
#            process tree).
#   status — live endpoint + ours/stale verdict when up (exit 0); "no daemon
#            running" + exit 0 when state is absent.
#   stop   — idempotent teardown: gracefully terminate the recorded process TREE
#            (the spawned wrapper plus its descendants — a compound serverCmd
#            runs the real server as a child of the wrapper), remove the state
#            file, exit 0; no-op exit 0 when absent.
#   A state file that exists but whose probe fails or whose recorded process is
#            gone is STALE: treated as down, cleaned, fall through to autostart.
#            A recycled bare pid that is no longer alive is therefore treated as
#            down (cleaned, NOT killed) rather than trusted.
#
# State file: .milestone-config/.runtime/render-daemon.json (.runtime/ reserved +
#   gitignored). Single per-run daemon -> single state file. Shape (identical to
#   the .sh twin): port (int) · token (string) · pid (int) · readyUrl (string) ·
#   startedAt (string, ISO-8601 UTC).
#   `pid` is the spawned wrapper; teardown walks its descendant tree so a forked
#   real server dies with it. `token` is a per-run nonce (NOT server-verified —
#   the app server never echoes it); it is kept because sibling #210 reads
#   port+token from the state file. Ownership/liveness is proven by the live
#   process plus the readyUrl probe, never by the token.
#
# Fail-loud / fail-closed on a not-ready server mirrors scripts/read-doc-section.ps1.
# Exit codes: 0 ok · 1 boot failure / not ready · 2 bad usage / missing config.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Force UTF-8 stdout so endpoint/em-dash output matches the .sh byte output.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Err([string]$msg) { [Console]::Error.WriteLine($msg) }

$cmd  = if ($args.Count -ge 1) { [string]$args[0] } else { '' }
$root = if ($args.Count -ge 2) { [string]$args[1] } else { (Get-Location).Path }
$root = ($root -replace '[\\/]+$', '')

if ($cmd -ne 'start' -and $cmd -ne 'status' -and $cmd -ne 'stop') {
  Err 'usage: render-daemon.ps1 <start|status|stop> [REPO_ROOT]'
  exit 2
}

$runtimeDir = Join-Path $root '.milestone-config/.runtime'
$state = Join-Path $runtimeDir 'render-daemon.json'
# Bounded ready-probe timeout (seconds); overridable for tests / slow boots.
# Validate it is a positive integer before use; a bad value -> default 30 with a
# stderr note (parity with the .sh twin's guard).
$timeout = 30
if ($env:RENDER_DAEMON_TIMEOUT) {
  $parsed = 0
  if ([int]::TryParse($env:RENDER_DAEMON_TIMEOUT, [ref]$parsed) -and $parsed -gt 0) {
    $timeout = $parsed
  } else {
    Err "render-daemon: ignoring invalid RENDER_DAEMON_TIMEOUT='$($env:RENDER_DAEMON_TIMEOUT)' (want positive integer); using 30"
  }
}

# --- profile read (mirrors ci-preflight-steps.ps1:52-57) --------------------
function Read-Profile {
  # Avoid the automatic $profile variable name (PowerShell profile path).
  $profilePath = Join-Path $root '.milestone-config/driver.json'
  if (-not (Test-Path -LiteralPath $profilePath)) { $profilePath = Join-Path $root 'milestone-driver.json' }
  if (-not (Test-Path -LiteralPath $profilePath)) {
    Err "render-daemon: no profile (.milestone-config/driver.json) at $root"; return $false
  }
  try { $cfg = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json -ErrorAction Stop } catch {
    Err "render-daemon: could not parse profile JSON at $profilePath"; return $false
  }
  $script:serverCmd = ''
  $script:readyUrl = ''
  if ($cfg.PSObject.Properties['visualCapture'] -and $cfg.visualCapture) {
    if ($cfg.visualCapture.PSObject.Properties['serverCmd']) { $script:serverCmd = [string]$cfg.visualCapture.serverCmd }
    if ($cfg.visualCapture.PSObject.Properties['readyUrl'])  { $script:readyUrl  = [string]$cfg.visualCapture.readyUrl }
  }
  if ([string]::IsNullOrEmpty($script:serverCmd) -or [string]::IsNullOrEmpty($script:readyUrl)) {
    Err 'render-daemon: profile is missing visualCapture.serverCmd and/or visualCapture.readyUrl'
    return $false
  }
  return $true
}

# Get-PortFromUrl <url> -> the explicit port when the URL carries one, the
# scheme default for http (80) / https (443) when it does not, or 0 for any
# other case (portless non-http(s), unparseable). [System.Uri].Port already
# returns the scheme default for http/https and -1 when the scheme has no
# default — so map -1 (and any parse failure) to 0. Parity contract with the
# .sh parse_port twin: explicit port -> that port; else 0-when-absent.
function Get-PortFromUrl([string]$url) {
  try {
    $u = [System.Uri]$url
    if ($u.Port -ge 0) { return $u.Port }
  } catch {}
  return 0
}

# Test-Ready <url> -> $true only if the ready URL answers with SUCCESS (2xx),
# matching the .sh twin's `curl -fsS` (which fails on a non-2xx status). A
# non-2xx status throws in PS7 and a connection failure throws too — both are
# "not ready", so any thrown error => not ready (parity with curl -f).
function Test-Ready([string]$url) {
  try {
    $null = Invoke-WebRequest -Uri $url -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
    return $true
  } catch {
    return $false
  }
}

# Get-DescendantPids <pid> -> the recorded process and every descendant, deepest
# first, so a tree teardown signals children before their parents. Cross-platform:
# Windows uses the CIM Win32_Process ParentProcessId graph; Unix uses `pgrep -P`.
function Get-DescendantPids([int]$rootPid) {
  $ordered = New-Object System.Collections.Generic.List[int]
  $stack = New-Object System.Collections.Generic.Stack[int]
  $stack.Push($rootPid)
  $seen = New-Object System.Collections.Generic.HashSet[int]
  while ($stack.Count -gt 0) {
    $p = $stack.Pop()
    if (-not $seen.Add($p)) { continue }
    $ordered.Add($p)
    $children = @()
    if ($IsWindows) {
      try {
        $children = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId=$p" -ErrorAction Stop |
                      ForEach-Object { [int]$_.ProcessId })
      } catch { $children = @() }
    } else {
      try {
        $out = & pgrep -P $p 2>$null
        if ($out) { $children = @($out | ForEach-Object { [int]$_ }) }
      } catch { $children = @() }
    }
    foreach ($c in $children) { if (-not $seen.Contains($c)) { $stack.Push($c) } }
  }
  # Deepest-first: reverse so descendants are signalled before the root wrapper.
  [int[]]$arr = $ordered.ToArray()
  [array]::Reverse($arr)
  return ,$arr
}

# Test-PidAlive <pid> -> $true if the process exists. Rejects pid <= 1 (require
# >= 2), matching the .sh valid_pgid contract exactly: pid 0/1 (and negative /
# non-numeric) are NEVER treated as a usable process. This is the fail-closed
# guard against the catastrophic kill footgun — on Linux pid 1 is init/systemd
# (a live process), so a tree-kill seeded from a recorded `pid:1` would walk and
# SIGTERM init's descendants = the whole session. A corrupted / zero / one /
# negative / non-numeric recorded pid must therefore read as "not alive" so the
# daemon reports down, cleans the state, and kills NOTHING.
function Test-PidAlive($processId) {
  $n = 0
  if (-not [int]::TryParse([string]$processId, [ref]$n)) { return $false }
  if ($n -le 1) { return $false }
  try { $null = Get-Process -Id $n -ErrorAction Stop; return $true } catch { return $false }
}

function Read-State {
  if (-not (Test-Path -LiteralPath $state)) { return $null }
  try { return Get-Content -LiteralPath $state -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

# Daemon-live check; populates $script:st* on success. OURS == the recorded
# process is still alive (so a recycled bare pid that is now dead reads as down)
# AND the readyUrl probe passes.
function Test-DaemonLive {
  $s = Read-State
  if ($null -eq $s) { return $false }
  $script:stPid   = if ($s.PSObject.Properties['pid'])      { $s.pid }      else { $null }
  $script:stPort  = if ($s.PSObject.Properties['port'])     { $s.port }     else { 0 }
  $script:stToken = if ($s.PSObject.Properties['token'])    { $s.token }    else { '' }
  $script:stUrl   = if ($s.PSObject.Properties['readyUrl']) { $s.readyUrl } else { '' }
  if (-not (Test-PidAlive $script:stPid)) { return $false }
  if ([string]::IsNullOrEmpty([string]$script:stUrl)) { return $false }
  if (-not (Test-Ready $script:stUrl)) { return $false }
  return $true
}

function Now-Iso { return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

function Write-State([int]$port, [string]$token, [int]$processId, [string]$url, [string]$startedAt) {
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  $obj = [ordered]@{ port = $port; token = $token; pid = $processId; readyUrl = $url; startedAt = $startedAt }
  ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $state -Encoding utf8NoBOM
}

# Stop the recorded process TREE gracefully first (SIGTERM-equivalent so a
# server's cleanup handler runs — parity with the .sh twin's `kill`), then force
# any survivors after a short grace window, then remove the state file.
function Remove-DaemonState {
  if (Test-Path -LiteralPath $state) {
    $s = Read-State
    # Test-PidAlive rejects pid <= 1 (parity with the .sh valid_pgid guard), so a
    # malformed `pid:0`/`pid:1` state never enters this block — the tree is never
    # walked or killed; only the state file is removed below.
    if ($null -ne $s -and $s.PSObject.Properties['pid'] -and (Test-PidAlive $s.pid)) {
      $rootPid = [int]$s.pid
      $pids = Get-DescendantPids $rootPid   # deepest-first
      # Graceful pass: SIGTERM on Unix / taskkill /T (no /F) tree on Windows.
      # Defense in depth: re-check Test-PidAlive at the kill site (mirrors the .sh
      # twin re-checking valid_pgid inside teardown_state) so a pid <= 1 can never
      # reach a kill even if the outer guard drifts.
      if ($IsWindows) {
        if (Test-PidAlive $rootPid) { try { & taskkill.exe /PID $rootPid /T 2>$null | Out-Null } catch {} }
      } else {
        foreach ($p in $pids) { if (Test-PidAlive $p) { try { & kill -TERM $p 2>$null | Out-Null } catch {} } }
      }
      # Grace window for the cleanup handlers to run.
      $graceDeadline = (Get-Date).AddSeconds(3)
      while ((Get-Date) -lt $graceDeadline -and (Test-PidAlive $rootPid)) { Start-Sleep -Milliseconds 100 }
      # Force pass: anything still alive is killed hard (tree).
      foreach ($p in $pids) {
        if (Test-PidAlive $p) {
          try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch {}
        }
      }
    }
    Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue
  }
}

switch ($cmd) {
  'status' {
    if (Test-DaemonLive) {
      [Console]::Out.Write("render-daemon: ours — live at $($script:stUrl) (pid $($script:stPid), port $($script:stPort))`n")
      exit 0
    }
    if (Test-Path -LiteralPath $state) { Remove-DaemonState }
    [Console]::Out.Write("render-daemon: no daemon running`n")
    exit 0
  }

  'stop' {
    Remove-DaemonState
    [Console]::Out.Write("render-daemon: stopped (no daemon running if none was up)`n")
    exit 0
  }

  'start' {
    if (-not (Read-Profile)) { exit 2 }

    if (Test-DaemonLive) {
      [Console]::Out.Write("render-daemon: reused — live at $($script:stUrl) (port $($script:stPort))`n")
      exit 0
    }
    if (Test-Path -LiteralPath $state) { Remove-DaemonState }

    $port = Get-PortFromUrl $script:readyUrl
    $token = "rd-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())-$(Get-Random)"

    # Spawn serverCmd DETACHED via a shell so an arbitrary command string runs;
    # Start-Process returns immediately (does not block) and the child survives.
    # Detach the child's stdio so its boot output never pollutes our stdout
    # (byte-identical contract line with the .sh twin, which redirects
    # </dev/null >/dev/null 2>&1). The discard is baked into the shell command
    # itself rather than via Start-Process -RedirectStandard*, because
    # Start-Process refuses to point stdout and stderr at the SAME path (the null
    # device) — an in-shell redirect sidesteps that and mirrors the .sh spawn.
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
    if ($IsWindows) {
      # Wrap so all six PowerShell output streams are discarded inside the child.
      $wrapped = "& { $($script:serverCmd) } *> `$null"
      $proc = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', $wrapped) -WindowStyle Hidden -PassThru
    } else {
      $wrapped = "exec </dev/null >/dev/null 2>&1; $($script:serverCmd)"
      $proc = Start-Process -FilePath 'bash' -ArgumentList @('-c', $wrapped) -PassThru
    }
    $srvPid = $proc.Id

    # Guard: a missing/invalid pid means the spawn failed; abort before
    # Write-State (parity with the .sh empty-$! guard).
    if ($null -eq $srvPid -or [int]$srvPid -le 0) {
      Err 'render-daemon: failed to spawn serverCmd (no pid)'
      exit 1
    }

    Write-State $port $token $srvPid $script:readyUrl (Now-Iso)

    $deadline = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $deadline) {
      if (-not (Test-PidAlive $srvPid)) {
        Err "render-daemon: server process (pid $srvPid) exited during boot before $($script:readyUrl) was ready"
        Remove-DaemonState
        exit 1
      }
      if (Test-Ready $script:readyUrl) {
        [Console]::Out.Write("render-daemon: started — live at $($script:readyUrl) (port $port)`n")
        exit 0
      }
      Start-Sleep -Seconds 1
    }

    Err "render-daemon: server did not become ready at $($script:readyUrl) within ${timeout}s — reaping and failing"
    Remove-DaemonState
    exit 1
  }
}
