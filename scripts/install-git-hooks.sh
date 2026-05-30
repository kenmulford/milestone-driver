#!/usr/bin/env bash
# milestone-driver — install native git hooks into a consuming repo.
#
# Writes <repo>/.git/hooks/pre-commit and pre-push as POSIX-sh shims that invoke
# the plugin's tests-green / no-push scripts (pwsh if available, else bash+jq).
# The plugin's hooks dir is baked into the shim, so re-run this after the plugin
# moves (e.g. a version-bumped install path).
#
# Usage: bash scripts/install-git-hooks.sh [<repo-path>]

set -euo pipefail

REPO="${1:-$PWD}"
HOOKS_DIR="$(cd "$(dirname "$0")/../hooks" && pwd)"
[ -d "$REPO/.git" ] || { echo "Not a git repository: $REPO" >&2; exit 1; }
GIT_HOOKS="$REPO/.git/hooks"
mkdir -p "$GIT_HOOKS"

[ -f "$REPO/.claude/milestone-driver.json" ] || \
  echo "Warning: no .claude/milestone-driver.json in $REPO — the hooks no-op until you add the profile." >&2

install_shim() {
  name="$1"; script="$2"; target="$GIT_HOOKS/$name"
  if [ -f "$target" ] && ! grep -q 'milestone-driver-managed' "$target"; then
    mv "$target" "$target.pre-milestone-driver.bak"
    echo "Existing $name backed up to $target.pre-milestone-driver.bak — chain it manually if you still need it." >&2
  fi
  cat > "$target" <<EOF
#!/bin/sh
# milestone-driver-managed
HOOK_DIR="$HOOKS_DIR"
if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "\$HOOK_DIR/$script.ps1" "\$@"
else
  exec bash "\$HOOK_DIR/$script.sh" "\$@"
fi
EOF
  chmod +x "$target"
  echo "installed .git/hooks/$name -> $script"
}

install_shim pre-commit tests-green
install_shim pre-push   no-push
echo "milestone-driver native hooks installed into $GIT_HOOKS (HOOK_DIR=$HOOKS_DIR)"
