# milestone-driver - runs the repo's own git hook behind git-hooks/<name>. POSIX sh, sourced.
#
# md_chain <hook-name> [args]   runs the repo's hook with the same args and stdin and
#                               returns its exit code. The repo's hook directory is the
#                               last core.hooksPath outside command scope (agent-env's
#                               own entry is command scope): system, global, local or
#                               worktree. A relative value is relative to the hook's
#                               cwd, which git sets to the work tree top level
#                               (git-config(1) core.hooksPath). No value: the
#                               <git-common-dir>/hooks default. A missing or
#                               non-executable hook, or this hook itself, returns 0.
# Cost: at most two git subprocesses per hook, because git runs a hook on every
# commit, checkout and merge.

md_chain() {
  md_name="$1"; shift
  md_hp=""
  md_cfg="$(git config --show-scope --get-all core.hooksPath 2>/dev/null)"
  md_ifs="$IFS"; IFS='
'; set -f
  for md_l in $md_cfg; do
    case "$md_l" in command[[:space:]]*) ;; *[[:space:]]*) md_hp="${md_l#*[[:space:]]}" ;; esac
  done
  IFS="$md_ifs"; set +f
  case "$md_hp" in "~/"*) md_hp="$HOME/${md_hp#\~/}" ;; esac
  if [ -z "$md_hp" ]; then
    md_hp="$(git rev-parse --git-common-dir 2>/dev/null)" || return 0
    md_hp="$md_hp/hooks"
  fi
  md_hook="$md_hp/$md_name"
  [ -f "$md_hook" ] && [ -x "$md_hook" ] || return 0
  [ "$md_hook" -ef "$0" ] && return 0
  "$md_hook" "$@"
}
