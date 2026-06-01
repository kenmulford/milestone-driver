#!/usr/bin/env bash
# milestone-driver — no-bom gate (Claude PreToolUse: Write|Edit|MultiEdit).
# Denies writes whose content begins with the UTF-8 BOM (EF BB BF / U+FEFF).
# Deny: exit 2 + stderr. Requires jq. Escape: CLAUDE_HOOK_DISABLE_NO_BOM=1. Fail-open.
[ "${CLAUDE_HOOK_DISABLE_NO_BOM:-}" = "1" ] && exit 0

input="$(cat)"
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
  Write)
    if has_bom ".tool_input.content"; then
      echo "milestone-driver: no-bom gate — content begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override." >&2
      exit 2
    fi
    ;;
  Edit)
    if has_bom ".tool_input.new_string"; then
      echo "milestone-driver: no-bom gate — new_string begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override." >&2
      exit 2
    fi
    ;;
  MultiEdit)
    count="$(printf "%s" "$input" | jq ".tool_input.edits | length" 2>/dev/null)"
    [[ "$count" =~ ^[0-9]+$ ]] || exit 0
    for (( i=0; i<count; i++ )); do
      if has_bom ".tool_input.edits[$i].new_string"; then
        echo "milestone-driver: no-bom gate — edits[$i].new_string begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override." >&2
        exit 2
      fi
    done
    ;;
esac

exit 0
