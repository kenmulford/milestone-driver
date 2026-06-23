#!/usr/bin/env bash
# milestone-driver — behavior matrix runner for render-daemon.sh (issue #208).
# Drives the render-daemon lifecycle seam (start | status | stop) against a
# lightweight throwaway app server, asserting every acceptance criterion:
# happy autostart, reuse, empty/no-daemon status+stop, boot-failure (fail-loud
# nonzero), stale-state cleanup -> autostart, idempotent teardown, and a
# COMPOUND-serverCmd teardown that asserts the port is actually freed after stop
# (the genuineness guard for the process-group reap — a wrapper-only kill would
# leak the forked listener and the port).
# The .sh and .ps1 runners assert the SAME command + state-file contract
# (cross-impl parity), mirroring tests/read-doc-section.test.{sh,ps1}.
#
# Stub server: a trivial python3 HTTP server is the consumer `serverCmd`. python3
# ships on the CI ubuntu-latest runner; absent locally, the boot/reuse/stale
# sub-cases SKIP cleanly (mirroring the command-presence guards in
# tests/extract-version.test.sh / ci-preflight-steps.sh) — the state-shape and
# no-daemon sub-cases still run with no stub.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/render-daemon.sh"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }

pass=0; fail=0; skipped=0
# Per-run temp dir as the throwaway workspace root — mktemp -d avoids fixed-path
# collisions under concurrent runs and is portable; trap removes it on exit AND
# stops any stub daemon left running so no orphan process survives the suite.
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/rd.$$")"; mkdir -p "$TMP"
cleanup() {
  [ -f "$TMP/.milestone-config/.runtime/render-daemon.json" ] && bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

STATE="$TMP/.milestone-config/.runtime/render-daemon.json"
HAVE_PY=0; command -v python3 >/dev/null 2>&1 && HAVE_PY=1

# Pick a port unlikely to collide; bind to loopback only.
PORT=8731
READY_URL="http://127.0.0.1:$PORT/"

# write_profile <serverCmd> <readyUrl> — seed the workspace driver.json with a
# visualCapture block (the daemon reads serverCmd/readyUrl straight from it).
write_profile() {
  mkdir -p "$TMP/.milestone-config"
  jq -n --arg s "$1" --arg u "$2" \
    '{integrationBranch:"develop", visualCapture:{serverCmd:$s, readyUrl:$u}}' \
    > "$TMP/.milestone-config/driver.json"
}

pass_t()  { pass=$((pass+1)); }
fail_t()  { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }
skip_t()  { skipped=$((skipped+1)); printf 'SKIP %s (python3 absent)\n' "$*" >&2; }

# ---- no-stub sub-cases (always run) ---------------------------------------

# status with no state file -> "no daemon running", exit 0 (clean no-op).
write_profile "true" "$READY_URL"
out="$(bash "$SCRIPT" status "$TMP" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi 'no daemon'; then pass_t; else
  fail_t "status-empty: rc=$rc out=[$out] (want exit 0 + 'no daemon')"; fi

# stop with no state file -> no-op success, exit 0.
out="$(bash "$SCRIPT" stop "$TMP" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then pass_t; else fail_t "stop-empty: rc=$rc out=[$out] (want exit 0)"; fi

# bad usage (unknown subcommand) -> nonzero, stderr names the subcommand set.
# (No state file is touched by a bad-usage exit; the meaningful assertions are
# the nonzero rc and the usage message naming start/status/stop on stderr.)
out="$(bash "$SCRIPT" frobnicate "$TMP" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'start|status|stop'; then pass_t; else
  fail_t "bad-usage: rc=$rc out=[$out] (want nonzero + usage naming start|status|stop)"; fi

# boot-failure: a serverCmd that never serves readyUrl -> fail loud nonzero,
# stderr names the probe URL, partial process reaped, no live daemon left.
# Uses a short timeout via RENDER_DAEMON_TIMEOUT so the test stays fast.
write_profile "sleep 30" "$READY_URL"
out="$(RENDER_DAEMON_TIMEOUT=2 bash "$SCRIPT" start "$TMP" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "$READY_URL"; then
  # status must NOT report a live daemon after a failed boot.
  sout="$(bash "$SCRIPT" status "$TMP" 2>&1)"; src=$?
  if [ "$src" -eq 0 ] && printf '%s' "$sout" | grep -qi 'no daemon'; then pass_t; else
    fail_t "boot-fail-status: src=$src sout=[$sout] (want 'no daemon' after failed boot)"; fi
else
  fail_t "boot-fail: rc=$rc out=[$out] (want nonzero + probe URL on stderr)"; fi
bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1 || true

# Malformed-pgid footgun guard (regression for the group-reap fix): a state file
# recording pid 0 / 1 must NEVER reach `kill -- -<g>` — `kill -- -0` signals the
# CALLER'S entire process group and `kill -- -1` signals every process the user
# owns. A corrupted pid must read as DOWN: stop/status exit 0, the state file is
# removed, and NOTHING external is signaled. We prove "nothing signaled" with a
# sentinel sleep started in OUR process group (no setsid/new group) that traps
# TERM into a flag file; if the daemon group-kills our group, the sentinel is
# signaled and the flag appears. This case FAILS against the unguarded code
# (where group_alive accepted 0/1 and teardown_state ran `kill -- -0`/`-1`,
# SIGTERM'ing the test's own group) and PASSES with valid_pgid (reject <= 1).
for badpid in 0 1; do
  write_profile "true" "$READY_URL"
  mkdir -p "$TMP/.milestone-config/.runtime"
  jq -n --argjson pid "$badpid" --arg u "$READY_URL" \
    '{port:8731, token:"corrupt", pid:$pid, readyUrl:$u, startedAt:"2020-01-01T00:00:00Z"}' \
    > "$STATE"
  # Run stop + status inside a subshell that shares OUR process group and traps
  # SIGTERM into a sentinel flag; a sentinel sleep in the same group is the thing
  # a stray `kill -- -<g>` would hit. The subshell reports its own exit codes.
  flag="$TMP/sentinel-signaled.$badpid"; rm -f "$flag"
  res="$(bash -c '
    trap "echo signaled > \"$2\"" TERM
    sleep 30 &
    sent=$!
    bash "$3" stop "$1"   >/dev/null 2>&1; src=$?
    bash "$3" status "$1" >/dev/null 2>&1; stc=$?
    salive=0; kill -0 "$sent" 2>/dev/null && salive=1
    kill "$sent" 2>/dev/null || true
    printf "%s %s %s" "$src" "$stc" "$salive"
  ' _ "$TMP" "$flag" "$SCRIPT")"
  src="${res%% *}"; rest="${res#* }"; stc="${rest%% *}"; salive="${rest##* }"
  state_gone=$([ ! -f "$STATE" ] && echo 1 || echo 0)
  caught=$([ -f "$flag" ] && echo 1 || echo 0)
  if [ "$src" -eq 0 ] && [ "$stc" -eq 0 ] && [ "$state_gone" -eq 1 ] \
     && [ "$caught" -eq 0 ] && [ "$salive" -eq 1 ]; then pass_t; else
    fail_t "malformed-pgid(pid=$badpid): stop-rc=$src status-rc=$stc state-removed=$state_gone caller-signaled=$caught sentinel-alive=$salive (want 0/0/1/0/1 — a kill -- -$badpid would signal the caller's group)"; fi
  rm -f "$flag"
done

# ---- stub-backed sub-cases (skip cleanly if python3 absent) ----------------

if [ "$HAVE_PY" -eq 1 ]; then
  write_profile "python3 -m http.server $PORT --bind 127.0.0.1" "$READY_URL"

  # Happy autostart: spawns detached, polls readyUrl, exits 0 when ready, writes
  # a well-formed state file (port parsed from readyUrl, token, pid, readyUrl,
  # startedAt) and the live endpoint is on stdout.
  out="$(RENDER_DAEMON_TIMEOUT=15 bash "$SCRIPT" start "$TMP" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$STATE" ]; then
    port="$(jq -r '.port' "$STATE")"; tok="$(jq -r '.token' "$STATE")"
    pid="$(jq -r '.pid' "$STATE")"; rurl="$(jq -r '.readyUrl' "$STATE")"
    st="$(jq -r '.startedAt' "$STATE")"
    if [ "$port" = "$PORT" ] && [ -n "$tok" ] && [ "$tok" != "null" ] \
       && [ -n "$pid" ] && [ "$pid" != "null" ] && [ "$rurl" = "$READY_URL" ] \
       && printf '%s' "$st" | grep -q 'T.*Z'; then pass_t; else
      fail_t "autostart-state: port=$port tok=$tok pid=$pid url=$rurl startedAt=$st"; fi
  else
    fail_t "autostart: rc=$rc out=[$out] state-exists=$([ -f "$STATE" ] && echo y || echo n)"; fi

  # Reuse: a second start with a live, ours-token-matching daemon reuses it —
  # no second spawn (pid unchanged), reports the port, exits 0.
  pid1="$(jq -r '.pid' "$STATE" 2>/dev/null)"
  out="$(RENDER_DAEMON_TIMEOUT=15 bash "$SCRIPT" start "$TMP" 2>&1)"; rc=$?
  pid2="$(jq -r '.pid' "$STATE" 2>/dev/null)"
  if [ "$rc" -eq 0 ] && [ "$pid1" = "$pid2" ] && printf '%s' "$out" | grep -q "$PORT"; then
    pass_t; else
    fail_t "reuse: rc=$rc pid1=$pid1 pid2=$pid2 out=[$out] (want exit 0, same pid, port shown)"; fi

  # status when a verified daemon is up: live endpoint + ours verdict, exit 0.
  out="$(bash "$SCRIPT" status "$TMP" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "$PORT" \
     && printf '%s' "$out" | grep -qi 'ours'; then pass_t; else
    fail_t "status-up: rc=$rc out=[$out] (want exit 0 + port + ours verdict)"; fi

  # Idempotent teardown: stop kills the recorded pid, removes the state file,
  # exit 0; the pid is no longer alive; a second stop is a clean no-op.
  out="$(bash "$SCRIPT" stop "$TMP" 2>&1)"; rc=$?
  alive=0; kill -0 "$pid1" 2>/dev/null && alive=1
  if [ "$rc" -eq 0 ] && [ ! -f "$STATE" ] && [ "$alive" -eq 0 ]; then pass_t; else
    fail_t "teardown: rc=$rc state-removed=$([ ! -f "$STATE" ] && echo y || echo n) alive=$alive"; fi
  out="$(bash "$SCRIPT" stop "$TMP" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then pass_t; else fail_t "teardown-idempotent: rc=$rc (want exit 0)"; fi

  # Compound-serverCmd teardown (genuineness guard for the process-group reap):
  # `python3 -m http.server ... & wait` backgrounds the listener and keeps the
  # bash wrapper alive on `wait` — so bash does NOT exec-optimize, the recorded
  # pid is the WRAPPER, and the real listener is a CHILD in the wrapper's process
  # group (this mirrors a realistic `npm start` that forks its server). A
  # wrapper-only `kill <pid>` would leave the listener holding the port; only a
  # process-GROUP reap frees it. Uses a 2nd port so it never collides with the
  # autostart case above. (Verified to genuinely leak under a wrapper-only kill —
  # a single-command serverCmd would exec-optimize and hide this bug.)
  PORT2=8733
  READY_URL2="http://127.0.0.1:$PORT2/"
  write_profile "python3 -m http.server $PORT2 --bind 127.0.0.1 & wait" "$READY_URL2"
  out="$(RENDER_DAEMON_TIMEOUT=15 bash "$SCRIPT" start "$TMP" 2>&1)"; rc=$?
  wpid="$(jq -r '.pid' "$STATE" 2>/dev/null)"
  if [ "$rc" -eq 0 ] && curl -fsS -o /dev/null --max-time 3 "$READY_URL2" >/dev/null 2>&1; then
    # The recorded pid is the wrapper's process-group leader; the listener is a
    # child in that group. Teardown must reap the group and free the port.
    bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1
    # Probe the readyUrl a few times post-stop: the port must no longer answer.
    freed=0
    for _ in 1 2 3 4 5; do
      if ! curl -fsS -o /dev/null --max-time 2 "$READY_URL2" >/dev/null 2>&1; then freed=1; break; fi
      sleep 1
    done
    grp_gone=1; kill -0 -- -"$wpid" 2>/dev/null && grp_gone=0
    if [ ! -f "$STATE" ] && [ "$freed" -eq 1 ] && [ "$grp_gone" -eq 1 ]; then pass_t; else
      fail_t "teardown-compound: state-removed=$([ ! -f "$STATE" ] && echo y || echo n) port-freed=$freed group-gone=$grp_gone (compound serverCmd leaked the listener — group reap failed)"; fi
  else
    fail_t "teardown-compound-setup: rc=$rc out=[$out] (compound serverCmd never came up; cannot test group reap)"; fi
  # Belt-and-suspenders: ensure nothing on PORT2 survives into later cases.
  bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1 || true
  pkill -f "http.server $PORT2" >/dev/null 2>&1 || true

  # restore the single-command profile for the stale-state case below.
  write_profile "python3 -m http.server $PORT --bind 127.0.0.1" "$READY_URL"

  # Stale state file: a state file whose recorded pid is dead and whose probe
  # fails -> treated as down, cleaned, falls through to autostart (new pid, exit 0).
  mkdir -p "$TMP/.milestone-config/.runtime"
  jq -n --arg u "$READY_URL" \
    '{port:8731, token:"deadbeef", pid:999999, readyUrl:$u, startedAt:"2020-01-01T00:00:00Z"}' \
    > "$STATE"
  out="$(RENDER_DAEMON_TIMEOUT=15 bash "$SCRIPT" start "$TMP" 2>&1)"; rc=$?
  newpid="$(jq -r '.pid' "$STATE" 2>/dev/null)"
  if [ "$rc" -eq 0 ] && [ "$newpid" != "999999" ] && [ "$newpid" != "null" ]; then
    pass_t; else
    fail_t "stale-autostart: rc=$rc newpid=$newpid out=[$out] (want exit 0 + fresh pid)"; fi
  bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1 || true
else
  skip_t "autostart"; skip_t "reuse"; skip_t "status-up"; skip_t "teardown"
  skip_t "teardown-idempotent"; skip_t "teardown-compound"; skip_t "stale-autostart"
fi

echo "render-daemon.sh: $pass passed, $fail failed, $skipped skipped"
[ "$fail" -eq 0 ]
