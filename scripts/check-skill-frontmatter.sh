#!/usr/bin/env bash
# milestone-driver — CI SKILL.md frontmatter YAML-validity lint (issue #314).
#
# Guards against the exact defect class that dropped solve-milestone from the
# Claude Desktop skill registry (issue #314): an UNQUOTED plain-scalar value in
# a SKILL.md's YAML frontmatter (e.g. a `description:`) that contains a
# colon+space (`: `) sequence — which a strict YAML parser (js-yaml) reads as a
# nested mapping and rejects, silently dropping the WHOLE skill. Claude Code's
# CLI loader is lenient and masks it; Claude Desktop's strict loader does not.
#
# Dependency-free by mandate: a LINE-ORIENTED heuristic, shell-only, NO YAML
# library and NO new tool dependency — the same posture check-size-budgets.sh
# and the CI-preflight parser take over their narrow YAML surface
# (.project/library-manifest.md#Adding a dependency (the gate) — "no YAML
# library and no new tool dependency"; docs/architecture.md#preflight-optional).
# A strict-YAML-parser library is explicitly OUT OF SCOPE for this plugin.
#
# Heuristic (narrow, false-positive-averse):
#   Within each governed SKILL.md's frontmatter (the block between the first two
#   `---` fences, opening fence required on line 1), examine each TOP-LEVEL key
#   line — a `key:` at column 0. If its inline value is a PLAIN scalar (NOT a
#   block scalar `|`/`>`, NOT quoted `"`/`'`, NOT a flow collection `[`/`{`, and
#   non-empty), scan the value for an unquoted colon+space (`: `). A plain YAML
#   scalar may never contain `: ` (it reads as a mapping), so any hit is a real
#   strict-YAML breakage. Block scalars — the FIX for #314 folds `description:`
#   to `>-` — and quoted scalars are SKIPPED, so a `parallel: false` mention
#   survives verbatim inside a `>-` block without tripping the lint. URLs
#   (`http://…`) are safe: they carry colon-SLASH, never colon-SPACE. Continuation
#   lines of a block scalar are indented, so they never match a column-0 key and
#   are never examined.
#
# Usage:   check-skill-frontmatter.sh [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# Output (stdout), one line per governed file plus a trailing summary,
# TAB-separated (mirrors check-size-budgets.sh's OK/FAIL/SUMMARY stream):
#   OK    <path>  clean
#   FAIL  <path>  <reason>   (MISSING | NO-FRONTMATTER | "<key>: unquoted colon-space …")
#   SUMMARY ok=<N> failed=<M>
# Exit 0 when every governed file is present, has frontmatter, and is clean;
# exit 1 when any file is missing, lacks frontmatter, or carries the defect.
# bash-3.2-safe (no ${var,,}, no `declare -A`, no `mapfile`).
set -u
export LC_ALL=C

ROOT="${1:-$PWD}"
ROOT="${ROOT%/}"

# Governed set: the frontmatter-bearing skill entry points. A skill that fails
# to parse never registers, so these are exactly the files this lint guards.
# Fixed list (like check-size-budgets.sh): a governed file that is renamed or
# deleted is a FAILURE (MISSING), never a silent pass — update the list in the
# same change.
FILES=(
  "skills/setup/SKILL.md"
  "skills/solve-issue/SKILL.md"
  "skills/solve-milestone/SKILL.md"
  "skills/triage/SKILL.md"
)

# Scan one file's frontmatter. Echoes a reason string on the FIRST defect found
# (empty => clean, "NO-FRONTMATTER" => no opening fence on line 1).
scan_frontmatter() {
  f_path="$1"
  in_fm=0
  had_fm=0
  reason=""
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"   # strip a trailing CR so a CRLF checkout compares clean
    lineno=$((lineno + 1))
    if [ "$lineno" -eq 1 ]; then
      line="${line#$'\xef\xbb\xbf'}"   # strip a leading UTF-8 BOM for byte-parity
                                       # with pwsh's ReadAllText (which strips it);
                                       # the no-bom hook forbids BOM, but keep the
                                       # twins identical even on a stray one.
      if [ "$line" = "---" ]; then
        in_fm=1
        had_fm=1
        continue
      fi
      break   # no opening fence on line 1 -> no frontmatter (do not hunt body)
    fi
    if [ "$in_fm" -eq 1 ] && [ "$line" = "---" ]; then
      break   # closing fence -> done scanning frontmatter
    fi
    [ "$in_fm" -eq 1 ] || continue
    # Only TOP-LEVEL key lines: `key:` at column 0 (no leading whitespace).
    case "$line" in
      [A-Za-z_]*) : ;;   # starts with a key char
      *) continue ;;     # indented / blank / other -> not a top-level key
    esac
    key="${line%%:*}"
    [ "$key" = "$line" ] && continue          # no colon at all -> not a key line
    case "$key" in
      *[!A-Za-z0-9_-]*) continue ;;           # key has a non-key char -> not a key
    esac
    val="${line#*:}"                          # value = text after the first colon
    val="${val# }"                            # drop one optional leading space
    case "$val" in
      "") continue ;;                         # empty -> value on later lines; skip
      "|"* | ">"*) continue ;;                # block scalar -> colons safe; skip
      '"'* | "'"*) continue ;;                # quoted scalar -> colons safe; skip
      "["* | "{"*) continue ;;                # flow collection -> out of narrow scope
    esac
    # Plain scalar: an unquoted colon+space is a strict-YAML breakage.
    case "$val" in
      *": "*)
        reason="$key: unquoted colon-space in plain scalar (breaks strict YAML)"
        break
        ;;
    esac
  done < "$f_path"
  if [ -n "$reason" ]; then
    printf '%s' "$reason"
  elif [ "$had_fm" -eq 0 ]; then
    printf 'NO-FRONTMATTER'
  fi
}

ok=0
failed=0
i=0
while [ "$i" -lt "${#FILES[@]}" ]; do
  f="${FILES[$i]}"
  path="$ROOT/$f"
  if [ ! -f "$path" ]; then
    printf 'FAIL\t%s\tMISSING\n' "$f"
    failed=$((failed + 1))
  else
    reason="$(scan_frontmatter "$path")"
    if [ -n "$reason" ]; then
      printf 'FAIL\t%s\t%s\n' "$f" "$reason"
      failed=$((failed + 1))
    else
      printf 'OK\t%s\tclean\n' "$f"
      ok=$((ok + 1))
    fi
  fi
  i=$((i + 1))
done

printf 'SUMMARY\tok=%s\tfailed=%s\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
