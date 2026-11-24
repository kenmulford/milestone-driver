#!/usr/bin/env bash
# milestone-driver - agent-env (SessionStart, every source). Appends to
# $CLAUDE_ENV_FILE, which Claude Code sources before each Bash command: the shim
# directory first on PATH (shims/gh checks gh argv) and core.hooksPath=<root>/git-hooks
# through GIT_CONFIG_* (git-hooks/pre-push checks each pushed ref). The GIT_CONFIG
# index is computed when the env file runs, because this hook's environment is not
# the command's. A file already holding the shim line is left alone: SessionStart
# reruns into one session. Never gates: always exits 0.
hook_dir="${BASH_SOURCE[0]%[/\\]*}"; [ "$hook_dir" = "${BASH_SOURCE[0]}" ] && hook_dir=.   # builtin: PATH may lack dirname
hook_dir="${hook_dir//\\//}"
root="$(cd "$hook_dir/.." 2>/dev/null && pwd)"
# Git for Windows resolves core.hooksPath natively, so it gets the C:/ form Git
# Bash's `pwd -W` prints; Git Bash splits PATH on `:`, so PATH gets the POSIX form.
# Elsewhere `pwd -W` is an invalid option and both are the same path.
hooks_root="$(cd "$hook_dir/.." 2>/dev/null && { pwd -W 2>/dev/null || pwd; })"
if [ -z "${CLAUDE_ENV_FILE:-}" ]; then
  echo "milestone-driver agent-env: CLAUDE_ENV_FILE is unset; the gh shim and git hooks are not installed for this session." >&2
  exit 0
fi
[ -n "$root" ] && [ -n "$hooks_root" ] || exit 0
sq="'"; bs='\'; esc="$sq$bs$sq$sq"   # a quote inside a single-quoted word becomes '\''
shims_q="${root//$sq/$esc}"
hooks_q="${hooks_root//$sq/$esc}"
path_line="export PATH='$shims_q/shims':\"\$PATH\""
grep -qxF -- "$path_line" "$CLAUDE_ENV_FILE" 2>/dev/null && exit 0
{
  printf '%s\n' "$path_line"
  printf '%s\n' 'export GIT_CONFIG_KEY_${GIT_CONFIG_COUNT:-0}=core.hooksPath'
  printf '%s\n' "export GIT_CONFIG_VALUE_\${GIT_CONFIG_COUNT:-0}='$hooks_q/git-hooks'"
  printf '%s\n' 'export GIT_CONFIG_COUNT=$(( ${GIT_CONFIG_COUNT:-0} + 1 ))'
} >> "$CLAUDE_ENV_FILE" 2>/dev/null
exit 0
