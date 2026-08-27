#!/usr/bin/env bash
# milestone-driver - behavior matrix runner for render-daemon.sh (issue #208).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/render-daemon.sh"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }

pass=0; fail=0; skipped=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/rd.$$")"; mkdir -p "$TMP"
cleanup() {
  [ -f "$TMP/.milestone-config/.runtime/render-daemon.json" ] && bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

STATE="$TMP/.milestone-config/.runtime/render-daemon.json"
PY=python3
if [ "$(uname -s)" = "Darwin" ] && [ -x /usr/bin/python3 ]; then PY=/usr/bin/python3; fi
HAVE_PY=0; command -v "$PY" >/dev/null 2>&1 && HAVE_PY=1

PORT=8731
READY_URL="http://127.0.0.1:$PORT/"

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

write_profile "true" "$READY_URL"
out="$(bash "$SCRIPT" status "$TMP" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi 'no daemon'; then pass_t; else
  fail_t "status-empty: rc=$rc out=[$out] (want exit 0 + 'no daemon')"; fi

out="$(bash "$SCRIPT" stop "$TMP" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then pass_t; else fail_t "stop-empty: rc=$rc out=[$out] (want exit 0)"; fi

out="$(bash "$SCRIPT" frobnicate "$TMP" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'start|status|stop'; then pass_t; else
  fail_t "bad-usage: rc=$rc out=[$out] (want nonzero + usage naming start|status|stop)"; fi

write_profile "sleep 30" "$READY_URL"
out="$(RENDER_DAEMON_TIMEOUT=2 bash "$SCRIPT" start "$TMP" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "$READY_URL"; then
  sout="$(bash "$SCRIPT" status "$TMP" 2>&1)"; src=$?
  if [ "$src" -eq 0 ] && printf '%s' "$sout" | grep -qi 'no daemon'; then pass_t; else
    fail_t "boot-fail-status: src=$src sout=[$sout] (want 'no daemon' after failed boot)"; fi
else
  fail_t "boot-fail: rc=$rc out=[$out] (want nonzero + probe URL on stderr)"; fi
bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1 || true

for badpid in 0 1; do
  write_profile "true" "$READY_URL"
  mkdir -p "$TMP/.milestone-config/.runtime"
  jq -n --argjson pid "$badpid" --arg u "$READY_URL" \
    '{port:8731, token:"corrupt", pid:$pid, readyUrl:$u, startedAt:"2020-01-01T00:00:00Z"}' \
    > "$STATE"
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
    fail_t "malformed-pgid(pid=$badpid): stop-rc=$src status-rc=$stc state-removed=$state_gone caller-signaled=$caught sentinel-alive=$salive (want 0/0/1/0/1 - a kill -- -$badpid would signal the caller's group)"; fi
  rm -f "$flag"
done

# ---- stub-backed sub-cases (skip cleanly if python3 absent) ----------------

if [ "$HAVE_PY" -eq 1 ]; then
  write_profile "$PY -m http.server $PORT --bind 127.0.0.1" "$READY_URL"

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

  pid1="$(jq -r '.pid' "$STATE" 2>/dev/null)"
  out="$(RENDER_DAEMON_TIMEOUT=15 bash "$SCRIPT" start "$TMP" 2>&1)"; rc=$?
  pid2="$(jq -r '.pid' "$STATE" 2>/dev/null)"
  if [ "$rc" -eq 0 ] && [ "$pid1" = "$pid2" ] && printf '%s' "$out" | grep -q "$PORT"; then
    pass_t; else
    fail_t "reuse: rc=$rc pid1=$pid1 pid2=$pid2 out=[$out] (want exit 0, same pid, port shown)"; fi

  out="$(bash "$SCRIPT" status "$TMP" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "$PORT" \
     && printf '%s' "$out" | grep -qi 'ours'; then pass_t; else
    fail_t "status-up: rc=$rc out=[$out] (want exit 0 + port + ours verdict)"; fi

  out="$(bash "$SCRIPT" stop "$TMP" 2>&1)"; rc=$?
  stop_reaped=0
  for _ in 1 2 3 4 5; do
    if ! kill -0 "$pid1" 2>/dev/null; then stop_reaped=1; break; fi
    sleep 1
  done
  if [ "$stop_reaped" -eq 0 ]; then
    case "$pid1" in
      ''|*[!0-9]*) : ;;                                  # not digits -> never group-kill
      *) if [ "$pid1" -gt 1 ]; then kill -KILL -- -"$pid1" 2>/dev/null || true
         else kill -KILL "$pid1" 2>/dev/null || true; fi ;;  # 0/1 -> plain pid kill at most
    esac
  fi
  if [ "$rc" -eq 0 ] && [ ! -f "$STATE" ] && [ "$stop_reaped" -eq 1 ]; then pass_t; else
    fail_t "teardown: rc=$rc state-removed=$([ ! -f "$STATE" ] && echo y || echo n) stop-reaped=$stop_reaped (stop did not reap the daemon within 5s - teardown regression)"; fi
  out="$(bash "$SCRIPT" stop "$TMP" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then pass_t; else fail_t "teardown-idempotent: rc=$rc (want exit 0)"; fi

  PORT2=8733
  READY_URL2="http://127.0.0.1:$PORT2/"
  write_profile "$PY -m http.server $PORT2 --bind 127.0.0.1 & wait" "$READY_URL2"
  out="$(RENDER_DAEMON_TIMEOUT=15 bash "$SCRIPT" start "$TMP" 2>&1)"; rc=$?
  wpid="$(jq -r '.pid' "$STATE" 2>/dev/null)"
  if [ "$rc" -eq 0 ] && curl -fsS -o /dev/null --max-time 3 "$READY_URL2" >/dev/null 2>&1; then
    bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1
    freed=0
    for _ in 1 2 3 4 5; do
      if ! curl -fsS -o /dev/null --max-time 2 "$READY_URL2" >/dev/null 2>&1; then freed=1; break; fi
      sleep 1
    done
    grp_gone=1; kill -0 -- -"$wpid" 2>/dev/null && grp_gone=0
    if [ ! -f "$STATE" ] && [ "$freed" -eq 1 ] && [ "$grp_gone" -eq 1 ]; then pass_t; else
      fail_t "teardown-compound: state-removed=$([ ! -f "$STATE" ] && echo y || echo n) port-freed=$freed group-gone=$grp_gone (compound serverCmd leaked the listener - group reap failed)"; fi
  else
    fail_t "teardown-compound-setup: rc=$rc out=[$out] (compound serverCmd never came up; cannot test group reap)"; fi
  bash "$SCRIPT" stop "$TMP" >/dev/null 2>&1 || true
  pkill -f "http.server $PORT2" >/dev/null 2>&1 || true

  write_profile "$PY -m http.server $PORT --bind 127.0.0.1" "$READY_URL"

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
