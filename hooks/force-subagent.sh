#!/usr/bin/env bash
# milestone-driver - force-subagent gate (Claude PreToolUse: Write|Edit|MultiEdit|NotebookEdit|apply_patch)
#
# Bash parity of force-subagent.ps1. Blocks main-thread edits to the consuming
# repo's source/test globs so application/test code is authored only by the
# dispatched implementer subagent. Requires `jq`.
#
# Deny mechanism: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON). Escape hatch: CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT=1
# Fail-open: missing jq / parse errors exit 0 so a hook bug never bricks editing.

[ "${CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT:-}" = "1" ] && exit 0

input="$(cat)"
hook_dir="${BASH_SOURCE[0]%[/\\]*}"; [ "$hook_dir" = "${BASH_SOURCE[0]}" ] && hook_dir=.   # builtin: PATH may lack dirname
. "$hook_dir/hook-deny.sh"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Subagent context -> allow.
for field in agent_id agent_type parent_session_id; do
  val="$(printf '%s' "$input" | jq -r ".${field} // empty" 2>/dev/null)"
  [ -n "$val" ] && exit 0
done

. "$hook_dir/patch-input.sh"
paths=()
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
if [ "$tool" = apply_patch ]; then
  patch="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  read_codex_patch "$patch"
  paths=("${PATCH_PATHS[@]}")
else
  file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
  [ -n "$file_path" ] && paths=("$file_path")
fi
[ "${#paths[@]}" -eq 0 ] && exit 0

project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="$(normalize_hook_path "$project_dir" "$PWD")"

profile="$project_dir/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0

# GLOB DIALECT, and where the repo's three sourceGlobs matchers part. This gate
# and `hooks/tests-green.sh` collapse `**` to `*` and match with a shell `case`;
# `scripts/classify-review-depth.sh` translates the same glob to an ERE, `**/` to
# `(.*/)?`. All three agree on `dir/**`, the shape every sourceGlobs entry in
# this repo takes. They part on `**/*.ext`: the ERE matches a ROOT-level `x.md`
# and tests-green's collapsed `*/*.md` does not. This gate lands on the ERE's
# answer anyway, through the SECOND test below - the ABSOLUTE path against
# `*/<pat>`, which supplies the leading segment tests-green has no source for.
# Pinned as behavior, not endorsed as a contract:
# `tests/force-subagent.test.ps1 (a globstar-prefix glob blocks a root-level path)`.
# Aligning the three is its own issue: this gate decides whether a source edit
# is blocked at all.
# ** -> * ('*' in a case glob matches across '/'). Both operands of the //
# replacement are QUOTED VARIABLES, never backslash escapes: bash 3.2 keeps the
# backslash in the replacement, so `${g//\*\*/\*}` yields `skills/\*` there and
# `skills/*` on 5.x - a pattern matching a literal star, so every `**` glob
# stopped matching and this gate silently allowed source edits (#571). Quoting
# through $STARSTAR/$STAR is byte-identical on 3.2.57 and 5.3.15.
STARSTAR='**'; STAR='*'
for file_path in "${paths[@]}"; do
  norm="$(normalize_hook_path "$file_path" "$project_dir")"
  case "$norm" in */docs/*|*/.claude/*|*/Obsidian/*) continue ;; esac
  rel="$norm"
  case "$norm" in "$project_dir"/*) rel="${norm#"$project_dir"/}" ;; esac
  while IFS= read -r g; do
    g="${g%$'\r'}"          # strip trailing CR (jq on Windows/msys emits CRLF)
    [ -z "$g" ] && continue
    pat="${g//"$STARSTAR"/$STAR}"
    blocked=0
    # shellcheck disable=SC2254
    case "$rel"  in $pat)    blocked=1 ;; esac
    # shellcheck disable=SC2254
    case "$norm" in */$pat)  blocked=1 ;; esac
    if [ "$blocked" = "1" ]; then
      hook_deny "$input" "milestone-driver: main-thread edits to source ('$rel') are blocked. Dispatch the implementer subagent to author application/test code, or set CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT=1 to override."
    fi
  done < <(jq -r '.sourceGlobs[]? // empty' "$profile" 2>/dev/null)
done

exit 0
