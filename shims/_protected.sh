# milestone-driver - shared branch policy for shims/gh and git-hooks/pre-push. POSIX sh, sourced.
#
# md_profile <dir>   sets md_integ, md_protected, md_extra (newline-separated globs)
#                    from <toplevel>/.milestone-config/driver.json, else the legacy
#                    <toplevel>/milestone-driver.json. md_integ defaults to develop,
#                    or dev when the repo has no origin/develop, so the gate holds
#                    in a repo with no driver config.
# md_denied <branch> returns 0 when a push to <branch> is denied: protectedBranch,
#                    a default protected name, or a protectedBranches entry; 1 for
#                    the integration branch, which GitHub branch protection owns.
# md_deny <action> <branch>   prints the deny text to stderr.

md_profile() {
  md_integ=""; md_protected=""; md_extra=""
  md_top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$md_top" ] || md_top="$1"
  md_file="$md_top/.milestone-config/driver.json"
  [ -f "$md_file" ] || md_file="$md_top/milestone-driver.json"
  if [ -f "$md_file" ]; then
    if command -v jq >/dev/null 2>&1; then
      md_integ="$(jq -r '.integrationBranch // empty' "$md_file" 2>/dev/null)"
      md_protected="$(jq -r '.protectedBranch // empty' "$md_file" 2>/dev/null)"
      md_extra="$(jq -r '.protectedBranches[]? // empty' "$md_file" 2>/dev/null)"
    else
      md_integ="$(sed -n 's/.*"integrationBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$md_file" | head -n 1)"
      md_protected="$(sed -n 's/.*"protectedBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$md_file" | head -n 1)"
      if grep -q '"protectedBranches"' "$md_file" 2>/dev/null; then
        echo "milestone-driver: jq is absent, so the profile's protectedBranches entries are not applied." >&2
      fi
    fi
    md_integ="$(printf '%s' "$md_integ" | tr -d '\r')"
    md_protected="$(printf '%s' "$md_protected" | tr -d '\r')"
    md_extra="$(printf '%s' "$md_extra" | tr -d '\r')"
  fi
  if [ -z "$md_integ" ]; then
    md_integ=develop
    git -C "$1" rev-parse --verify --quiet refs/remotes/origin/develop >/dev/null 2>&1 || md_integ=dev
  fi
}

md_denied() {
  md_n="${1#refs/heads/}"
  [ "$md_n" = "$md_integ" ] && return 1
  [ -n "$md_protected" ] && [ "$md_n" = "$md_protected" ] && return 0
  for md_p in main master production prod staging stage testing test qa uat 'release/*' 'hotfix/*'; do
    case "$md_n" in $md_p) return 0 ;; esac
  done
  # set -f: an unquoted entry such as rel-* must reach `case` as a pattern, not expand against the cwd.
  set -f
  md_old_ifs="$IFS"; IFS='
'
  for md_p in $md_extra; do
    case "$md_n" in $md_p) IFS="$md_old_ifs"; set +f; return 0 ;; esac
  done
  IFS="$md_old_ifs"; set +f
  return 1
}

md_deny() {
  printf "milestone-driver: %s into '%s' is blocked. Agents stop at the integration branch '%s'; anything past it is a human step.\n" "$1" "$2" "$md_integ" >&2
}
