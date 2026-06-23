#!/usr/bin/env bash
# milestone-driver — render-daemon lifecycle seam (issue #208).
#
# Boots the consumer's seeded/persona app server ONCE per run and reuses it
# across the run; tears it down at run end. Built for the SERIAL capture path
# only — a single per-run daemon on the consumer's configured port (under
# --parallel, render capture is deferred to the serial tail, so this never
# serves concurrent worktrees — skills/solve-issue/SKILL.md:321).
#
# Inputs are read DIRECTLY from the profile .milestone-config/driver.json
# (mirroring the jq profile-read in scripts/ci-preflight-steps.sh:64-68):
#   visualCapture.serverCmd  — the command that boots the app server.
#   visualCapture.readyUrl   — the full /health-style ready-probe URL
#                              (e.g. http://127.0.0.1:3000/health). The port is
#                              the consumer's; we parse it from readyUrl for the
#                              state file's informational `port` field — we do
#                              NOT dynamically allocate a port.
# The visualCapture block itself is defined/documented by sibling issue #209;
# this script only READS serverCmd + readyUrl (the key names are fixed by spec).
#
# Usage:   render-daemon.sh <start|status|stop> [REPO_ROOT]
#   start  — reuse-or-autostart: if the state file exists AND the recorded
#            process GROUP is still alive AND the readyUrl probe passes, reuse
#            (print endpoint, exit 0). Else write the state file, spawn serverCmd
#            DETACHED in its own process group (survives this shell, does not
#            block), poll readyUrl until ready within a bounded timeout, exit 0
#            when ready / fail loud to stderr + nonzero on boot failure (reap the
#            partial process group, leave state non-misleading).
#   status — print the live endpoint + an ours/stale verdict if a verified daemon
#            is up (exit 0); "no daemon running" + exit 0 when state is absent.
#   stop   — idempotent teardown: SIGTERM the recorded process GROUP (so a
#            compound serverCmd's forked children die with it), remove the state
#            file, exit 0; no-op exit 0 when absent.
#   A state file that exists but whose probe fails or whose process group is gone
#            is STALE: treated as down, cleaned, fall through to autostart — never
#            reused, never an error on staleness alone. A recycled bare pid whose
#            group no longer matches ours is therefore treated as down (cleaned,
#            NOT killed) rather than trusted.
#
# State file: .milestone-config/.runtime/render-daemon.json (the .runtime/ dir is
#   already reserved + gitignored — .milestone-config/.gitignore, hooks/tests-green.sh:79).
#   Single per-run daemon -> single state file. Shape (jq-readable):
#     port (int) · token (string) · pid (int) · readyUrl (string) ·
#     startedAt (string, ISO-8601 UTC).
#   `pid` is the spawned child, which we run as its own process-group leader
#   (pgid == pid) so liveness/teardown act on the whole group, not just the
#   wrapper. `token` is a per-run nonce (NOT server-verified — the app server
#   never echoes it); it is kept because sibling #210 reads port+token from the
#   state file. Ownership/liveness is proven by the live process group plus the
#   readyUrl probe, never by the token.
#
# Fail-loud / fail-closed on a not-ready server (clear stderr message + nonzero
#   exit, never silent) mirrors scripts/read-doc-section.sh:12-14. The
#   complementary "nothing to tear down" case (status/stop with no state) is a
#   clean no-op success — these are not in tension.
#
# Dependency: jq (the cross-platform nonNegotiable already permits it); no new dep.
# Exit codes: 0 ok · 1 boot failure / not ready · 2 bad usage / missing config.
set -u
# Byte-deterministic string handling (mirrors ci-preflight-steps.sh:32 /
# read-doc-section.sh:23) so parsing stays aligned with the pwsh UTF-16 twin.
export LC_ALL=C

err() { printf '%s\n' "$*" >&2; }

CMD="${1:-}"
ROOT="${2:-$PWD}"; ROOT="${ROOT%/}"

case "$CMD" in
  start|status|stop) : ;;
  *) err "usage: render-daemon.sh <start|status|stop> [REPO_ROOT]"; exit 2 ;;
esac

command -v jq >/dev/null 2>&1 || { err "render-daemon: jq is required but not on PATH"; exit 2; }

RUNTIME_DIR="$ROOT/.milestone-config/.runtime"
STATE="$RUNTIME_DIR/render-daemon.json"
# Bounded ready-probe timeout (seconds); overridable for tests / slow boots.
# Validate it is a positive integer BEFORE any arithmetic (a non-numeric value
# would otherwise crash under set -u in the deadline calc, after the server is
# already spawned — orphaning it). Bad value -> default 30 with a stderr note.
TIMEOUT="${RENDER_DAEMON_TIMEOUT:-30}"
case "$TIMEOUT" in
  ''|*[!0-9]*|0) err "render-daemon: ignoring invalid RENDER_DAEMON_TIMEOUT='$TIMEOUT' (want positive integer); using 30"; TIMEOUT=30 ;;
esac

# --- profile read (mirrors ci-preflight-steps.sh:64-68) ---------------------
read_profile() {
  local profile="$ROOT/.milestone-config/driver.json"
  [ -f "$profile" ] || profile="$ROOT/milestone-driver.json"
  if [ ! -f "$profile" ]; then
    err "render-daemon: no profile (.milestone-config/driver.json) at $ROOT"; return 1
  fi
  SERVER_CMD="$(jq -r '.visualCapture.serverCmd // empty' "$profile" 2>/dev/null)"
  READY_URL="$(jq -r '.visualCapture.readyUrl // empty' "$profile" 2>/dev/null)"
  SERVER_CMD="${SERVER_CMD%$'\r'}"; READY_URL="${READY_URL%$'\r'}"
  if [ -z "$SERVER_CMD" ] || [ -z "$READY_URL" ]; then
    err "render-daemon: profile is missing visualCapture.serverCmd and/or visualCapture.readyUrl"
    return 1
  fi
  return 0
}

# parse_port <url> -> the port from a URL, or "" when it cannot be determined.
# A URL with an explicit :port returns that port. A portless http/https URL
# returns the scheme default (80/443). Any other case (portless non-http(s),
# unparseable) returns "" — the caller records the informational `port` field
# as 0 in that case. (Parity contract with the pwsh Get-PortFromUrl twin:
# explicit port -> that port; else 0-when-absent.)
parse_port() {
  local url="$1" hostport scheme rest
  scheme="${url%%://*}"
  rest="${url#*://}"
  hostport="${rest%%/*}"          # strip path
  hostport="${hostport%%\?*}"     # strip query
  case "$hostport" in
    *:*) printf '%s' "${hostport##*:}" ;;
    *)   case "$scheme" in https) printf '443' ;; http) printf '80' ;; *) printf '' ;; esac ;;
  esac
}

# probe <url> -> 0 if the ready URL answers with a 2xx (curl -fsS / wget -q both
# fail on a non-2xx status, so the two agree); nonzero otherwise. Prefers curl,
# falls back to wget. Missing-tool handling is done once up front (see the
# curl/wget preflight in `start`), not per-probe.
probe() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -o /dev/null --max-time 3 "$url" >/dev/null 2>&1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null --timeout=3 "$url" >/dev/null 2>&1
  else
    return 2
  fi
}

# valid_pgid <pgid> -> 0 only when the recorded pgid is safe to use in a NEGATIVE
# process-group signal (`kill -- -<g>`). It must be a non-empty run of digits AND
# > 1. This is a fail-CLOSED guard against the catastrophic group-signal footgun:
# `kill -- -0` targets the CALLER'S entire process group (the orchestrator + its
# children) and `kill -- -1` targets EVERY process the user owns. A corrupted /
# zero / one / negative / non-numeric recorded pid must therefore read as "no
# usable group" so nothing is ever signaled. (Parity with the pwsh twin, which
# rejects processId <= 0 in Test-PidAlive — render-daemon.ps1:165.)
valid_pgid() { local g="$1"; case "$g" in ''|*[!0-9]*) return 1 ;; esac; [ "$g" -gt 1 ]; }

# group_alive <pgid> -> 0 if any process in that process group exists. This is
# the ownership/liveness primitive: a recycled BARE pid will not be the leader
# of OUR recorded group, so `kill -0 -<pgid>` on a stale recording fails and the
# state is treated as down (never trusted, never killed). An invalid pgid (per
# valid_pgid) reads as down WITHOUT ever issuing a negative-group `kill -0`.
group_alive() { local g="$1"; valid_pgid "$g" && kill -0 -- -"$g" 2>/dev/null; }

# read_state_field <field> -> the field value, or "" on any error.
read_state_field() { jq -r --arg f "$1" '.[$f] // empty' "$STATE" 2>/dev/null; }

# daemon_live -> 0 if the recorded state describes a live daemon that is OURS:
# the recorded process group is still alive AND the readyUrl probe passes. Sets
# STATE_PID / STATE_PORT / STATE_TOKEN / STATE_URL as a side effect.
daemon_live() {
  [ -f "$STATE" ] || return 1
  STATE_PID="$(read_state_field pid)"
  STATE_PORT="$(read_state_field port)"
  STATE_TOKEN="$(read_state_field token)"
  STATE_URL="$(read_state_field readyUrl)"
  group_alive "$STATE_PID" || return 1
  [ -n "$STATE_URL" ] || return 1
  probe "$STATE_URL" || return 1
  return 0
}

# now_iso -> current time as ISO-8601 UTC (Zulu).
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# write_state <port> <token> <pid> <url> <startedAt>
write_state() {
  mkdir -p "$RUNTIME_DIR"
  jq -n --argjson port "$1" --arg token "$2" --argjson pid "$3" \
        --arg url "$4" --arg startedAt "$5" \
    '{port:$port, token:$token, pid:$pid, readyUrl:$url, startedAt:$startedAt}' \
    > "$STATE"
}

# reap the recorded process GROUP (best-effort SIGTERM so a server's cleanup
# handler runs and forked children die with it) and remove the state file.
teardown_state() {
  if [ -f "$STATE" ]; then
    local g; g="$(read_state_field pid)"
    # Defense in depth: re-check valid_pgid at the kill site so a malformed pgid
    # can never reach `kill -- -<g>` even if group_alive's contract drifts. Only
    # a live, valid group is signaled; the state file is removed either way.
    if valid_pgid "$g" && group_alive "$g"; then kill -- -"$g" 2>/dev/null || true; fi
    rm -f "$STATE" 2>/dev/null || true
  fi
}

case "$CMD" in
  status)
    if daemon_live; then
      printf 'render-daemon: ours — live at %s (pid %s, port %s)\n' "$STATE_URL" "$STATE_PID" "$STATE_PORT"
      exit 0
    fi
    if [ -f "$STATE" ]; then
      # State exists but not live -> stale. Report down (clean the stale file).
      teardown_state
    fi
    printf 'render-daemon: no daemon running\n'
    exit 0
    ;;

  stop)
    teardown_state
    printf 'render-daemon: stopped (no daemon running if none was up)\n'
    exit 0
    ;;

  start)
    read_profile || exit 2

    # Fail loud immediately if no HTTP probe tool is available, rather than
    # spawning the server and then spinning the full timeout re-failing the probe.
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
      err "render-daemon: neither curl nor wget on PATH — cannot probe $READY_URL"
      exit 1
    fi

    # reuse-or-autostart: a live, ours daemon is reused as-is.
    if daemon_live; then
      printf 'render-daemon: reused — live at %s (port %s)\n' "$STATE_URL" "$STATE_PORT"
      exit 0
    fi
    # A non-live state file is stale -> clean it and fall through to autostart.
    [ -f "$STATE" ] && teardown_state

    PORT="$(parse_port "$READY_URL")"; [ -n "$PORT" ] || PORT=0
    TOKEN="rd-$$-$(date +%s)-$RANDOM"

    # Spawn serverCmd DETACHED in its OWN process group so teardown can reap the
    # whole group (a compound serverCmd — `cd app && npm run dev`, a pipeline,
    # an `npm start` that forks — runs the real server as a CHILD of the wrapper;
    # killing only the wrapper pid would leak it). `set -m` (job-control monitor
    # mode) makes bash place the background job in a new process group whose pgid
    # equals the job's pid, on both Linux and macOS — so the recorded pid ($!) IS
    # the pgid. We do NOT use setsid: under `set -m` the background job is already
    # a process-group leader, and setsid(1) cannot create a new session from a
    # group leader so it FORKS and exits — leaving $! pointing at the dead setsid
    # parent rather than the live server (the Linux-only failure mode this fixes;
    # macOS has no setsid so it never tripped there). `nohup` is used uniformly on
    # both platforms purely to ignore SIGHUP; the new group comes from `set -m`.
    # stdio is detached (</dev/null >/dev/null 2>&1) so `start` never blocks and
    # the child's boot output never pollutes our stdout (byte-identical contract).
    mkdir -p "$RUNTIME_DIR"
    set -m
    nohup bash -c "$SERVER_CMD" </dev/null >/dev/null 2>&1 &
    SRV_PID=$!
    set +m
    disown "$SRV_PID" 2>/dev/null || true

    # Guard: an empty/non-numeric $! means the spawn never produced a pid; abort
    # before write_state's `jq --argjson pid` (which would fail on empty input
    # and otherwise orphan the spawned process).
    case "$SRV_PID" in
      ''|*[!0-9]*) err "render-daemon: failed to spawn serverCmd (no pid)"; exit 1 ;;
    esac

    write_state "$PORT" "$TOKEN" "$SRV_PID" "$READY_URL" "$(now_iso)"

    # Poll readyUrl until ready within the bounded timeout. Liveness here uses
    # the process GROUP so a wrapper whose forked child died is detected too.
    deadline=$(( $(date +%s) + TIMEOUT ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
      if ! group_alive "$SRV_PID"; then
        err "render-daemon: server process group (pgid $SRV_PID) exited during boot before $READY_URL was ready"
        teardown_state
        exit 1
      fi
      if probe "$READY_URL"; then
        printf 'render-daemon: started — live at %s (port %s)\n' "$READY_URL" "$PORT"
        exit 0
      fi
      sleep 1
    done

    err "render-daemon: server did not become ready at $READY_URL within ${TIMEOUT}s — reaping and failing"
    teardown_state
    exit 1
    ;;
esac
