#!/usr/bin/env bash
# milestone-driver - clear one issue's dispatch-cap counters at park time, so a
# re-run after the park starts a fresh chain; `milestone-<n>` clears a milestone
# end's counters when its branch is deleted.
# Usage: reset-dispatch-cap.sh <repo-root> <n | milestone-n>
# Deletes <git-common-dir>/milestone-driver/dispatch-cap/{review,implementer,planner}-<n>
# where present. The common dir resolves exactly as hooks/dispatch-cap.sh does
# (a relative answer joins to <repo-root>), so a linked worktree clears the
# counters its main checkout shares.
# stdout: one line `reset<TAB><n><TAB><count removed>`.
# Fail-open: no git, no repo, or no counter directory prints a count of 0 and
# exits 0; a park must never fail on its bookkeeping.
# Exit codes: 0 always, except 2 on bad usage (argument count, <n> neither digits nor `milestone-<digits>`).
# bash-3.2-safe.

err() { printf '%s\n' "$*" >&2; }

[ "$#" -eq 2 ] || { err "usage: reset-dispatch-cap.sh <repo-root> <n | milestone-n>"; exit 2; }
root="${1//\\//}"; n="$2"
case "${n#milestone-}" in ''|*[!0-9]*) err "reset-dispatch-cap: <n> must be digits or milestone-<digits>: $n"; exit 2 ;; esac

removed=0
if command -v git >/dev/null 2>&1 && common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)"; then
  common="${common//\\//}"
  case "$common" in
    /*|[A-Za-z]:/*) ;;
    *) common="$root/$common" ;;
  esac
  for kind in review implementer planner; do
    f="$common/milestone-driver/dispatch-cap/$kind-$n"
    [ -f "$f" ] && rm -f "$f" 2>/dev/null && removed=$((removed + 1))
  done
fi

printf 'reset\t%s\t%s\n' "$n" "$removed"
exit 0
