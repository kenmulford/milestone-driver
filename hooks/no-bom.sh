#!/usr/bin/env bash
# milestone-driver - no-bom gate (Claude PreToolUse: Write|Edit|MultiEdit|apply_patch).
# Denies writes whose content begins with the UTF-8 BOM (EF BB BF / U+FEFF).
# Deny: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON). Requires jq. Escape: CLAUDE_HOOK_DISABLE_NO_BOM=1. Fail-open.
[ "${CLAUDE_HOOK_DISABLE_NO_BOM:-}" = "1" ] && exit 0

input="$(cat)"
hook_dir="${BASH_SOURCE[0]%[/\\]*}"; [ "$hook_dir" = "${BASH_SOURCE[0]}" ] && hook_dir=.   # builtin: PATH may lack dirname
. "$hook_dir/hook-deny.sh"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf "%s" "$input" | jq -r ".tool_name // empty" 2>/dev/null)"

has_bom() {
  # Check whether the string value at jq path $1 starts with U+FEFF.
  # jq -r decodes JSON strings; the BOM is U+FEFF = UTF-8 bytes EF BB BF.
  local val
  val="$(printf "%s" "$input" | jq -r "$1 // empty" 2>/dev/null)"
  [ -z "$val" ] && return 1
  # Inspect the first three bytes of the jq-decoded value.
  local first3
  first3="$(printf "%s" "$val" | head -c 3 | od -An -tx1 | tr -d " \n")"
  [ "$first3" = "efbbbf" ]
}

case "$tool" in
  apply_patch)
    . "$hook_dir/patch-input.sh"
    patch="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    read_codex_patch "$patch"
    if [ "$PATCH_HAS_BOM" = 1 ]; then
      hook_deny "$input" 'milestone-driver: no-bom gate - patch content begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override.'
    fi
    ;;
  Write)
    if has_bom ".tool_input.content"; then
      hook_deny "$input" "milestone-driver: no-bom gate - content begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override."
    fi
    ;;
  Edit)
    if has_bom ".tool_input.new_string"; then
      hook_deny "$input" "milestone-driver: no-bom gate - new_string begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override."
    fi
    ;;
  MultiEdit)
    count="$(printf "%s" "$input" | jq ".tool_input.edits | length" 2>/dev/null)"
    [[ "$count" =~ ^[0-9]+$ ]] || exit 0
    for (( i=0; i<count; i++ )); do
      if has_bom ".tool_input.edits[$i].new_string"; then
        hook_deny "$input" "milestone-driver: no-bom gate - edits[$i].new_string begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override."
      fi
    done
    ;;
esac

exit 0
