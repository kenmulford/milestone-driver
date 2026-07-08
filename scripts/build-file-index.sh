#!/usr/bin/env bash
# milestone-driver — diff-scoped repo file-index resolver (issue #318).
# stdin: JSON {"files":["<repo-relative-path>", ...]}. stdout: one line per input
# file, IN INPUT ORDER — "<path> → <purpose>[ (callers: a, b)][ (symbols: x, y)]".
# Fail-open (mirrors scripts/extract-version.sh:11 emit_none): malformed/empty
# stdin, missing jq, or zero emitted lines => empty stdout, stderr "none", exit 0.
# Never a non-zero exit, never a crash. Named paths that don't exist on disk or
# resolve outside the repo root (cwd) are skipped, not fatal.
set -u
# Force a deterministic byte model: LC_ALL=C makes every string op and `sort`
# byte-indexed, keeping this leg in lockstep with the pwsh twin's ordinal model
# (same rationale as scripts/extract-version.sh:6-10).
export LC_ALL=C

emit_none() { printf 'none' >&2; exit 0; }

SEP=" $(printf '\xe2\x86\x92') "   # " → " (U+2192, one space each side)

input="$(cat)"
[ -z "$input" ] && emit_none
command -v jq >/dev/null 2>&1 || emit_none
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || emit_none
# tr -d '\r' guards against a Windows jq build emitting CRLF line terminators.
[ "$(printf '%s' "$input" | jq -r 'has("files")' 2>/dev/null | tr -d '\r')" = "true" ] || emit_none
mapfile -t FILES < <(printf '%s' "$input" | jq -r '.files[]?' 2>/dev/null | tr -d '\r')

ROOT="$(pwd -P)"

# sourceGlobs: read from cwd's .milestone-config/driver.json when readable, else
# fail-open to the literal defaults (orchestrator decision, issue #318).
declare -a SRC_DIRS=()
prof=".milestone-config/driver.json"
if [ -r "$prof" ]; then
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    d="${g%%\**}"; d="${d%/}"        # "skills/**" -> "skills"
    [ -n "$d" ] && SRC_DIRS+=("$d")
  done < <(jq -r '.sourceGlobs[]?' "$prof" 2>/dev/null | tr -d '\r')
fi
[ "${#SRC_DIRS[@]}" -eq 0 ] && SRC_DIRS=(skills agents hooks)

# Enumerate every file under the source trees (repo-relative paths).
declare -a SRC_FILES=()
for d in "${SRC_DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r sf; do SRC_FILES+=("${sf#./}"); done < <(find "$d" -type f 2>/dev/null)
done

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

is_block_indicator() { case "$1" in '>-'|'>'|'|'|'|-') return 0;; *) return 1;; esac; }

# first_sentence <text>: truncate at the first ". " (period+space) occurring
# OUTSIDE a backtick span, keeping the sentence THROUGH the period (dropping the
# space and remainder); if none, keep the whole text. Byte-scanned under LC_ALL=C
# — ASCII '.'/' '/'`' never collide with UTF-8 continuation bytes, so the em-dash
# / arrow pass through intact and the result matches the pwsh char-scan twin.
first_sentence() {
  local s="$1"; local n="${#s}" i=0 inbt=0 c nx
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ "$c" = '`' ]; then inbt=$((1 - inbt)); i=$((i + 1)); continue; fi
    if [ "$inbt" -eq 0 ] && [ "$c" = '.' ]; then
      nx="${s:$((i + 1)):1}"
      [ "$nx" = " " ] && { printf '%s' "${s:0:$((i + 1))}"; return; }
    fi
    i=$((i + 1))
  done
  printf '%s' "$s"
}

# purpose_frontmatter <file>: YAML-frontmatter description value, applying the
# folded/literal-scalar rule — the same-line value when non-empty and not a bare
# block indicator (>- > | |-), else the first non-empty line FOLLOWING the key.
purpose_frontmatter() {
  local file="$1" in_fm=0 want=0 line trimmed val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$in_fm" -eq 0 ]; then
      [ "$line" = "---" ] && in_fm=1
      continue
    fi
    if [ "$want" -eq 1 ]; then
      [ "$line" = "---" ] && { printf ''; return; }
      trimmed="$(trim "$line")"
      [ -n "$trimmed" ] && { printf '%s' "$trimmed"; return; }
      continue
    fi
    [ "$line" = "---" ] && break
    case "$line" in
      description:*)
        val="$(trim "${line#description:}")"
        if [ -z "$val" ] || is_block_indicator "$val"; then want=1; continue; fi
        printf '%s' "$val"; return;;
    esac
  done < "$file"
  printf ''
}

# purpose_header <file>: the file's line-2 header comment, stripping leading '#'
# markers and whitespace (exemplars scripts/extract-version.sh:2, hooks/force-subagent.sh:2).
purpose_header() {
  local file="$1" line2
  line2="$(sed -n '2p' "$file" 2>/dev/null)"
  line2="${line2%$'\r'}"
  while [ "${line2:0:1}" = "#" ]; do line2="${line2#\#}"; done
  trim "$line2"
}

# extract_symbols <file>: top-level function names in a .sh/.ps1 — BOTH the
# bash shape `name() {` AND the pwsh shape `function Name` are matched in this
# leg (a .ps1 file carries pwsh-shape functions). Deduped + byte-sorted.
extract_symbols() {
  local file="$1" line
  {
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\)[[:space:]]*\{ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
      fi
      if [[ "$line" =~ ^function[[:space:]]+([A-Za-z_][A-Za-z0-9_-]*) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
      fi
    done < "$file"
  } | LC_ALL=C sort -u
}

# file_relations <path>: one combined, deduped, byte-sorted list of source-tree
# files related to <path> — callers (a source file that references <path> by
# repo-relative path OR basename) UNION callees (a source file whose path/basename
# appears inside <path>). One hop only; <path> itself is excluded.
file_relations() {
  local p="$1"; local pbase="${p##*/}" g gbase
  {
    for g in "${SRC_FILES[@]:-}"; do
      [ -n "$g" ] || continue
      [ "$g" = "$p" ] && continue
      gbase="${g##*/}"
      if grep -qF -e "$g" -e "$gbase" -- "$p" 2>/dev/null \
        || grep -qF -e "$p" -e "$pbase" -- "$g" 2>/dev/null; then
        printf '%s\n' "$g"
      fi
    done
  } | LC_ALL=C sort -u
}

join_comma() { local out="" x; for x in "$@"; do [ -n "$out" ] && out+=", "; out+="$x"; done; printf '%s' "$out"; }

emitted=0
for p in "${FILES[@]:-}"; do
  [ -n "$p" ] || continue
  # Skip absolute paths and paths that resolve outside the repo root (cwd).
  case "$p" in /*) continue;; esac
  [ -e "$p" ] || continue
  d="$(cd "$(dirname -- "$p")" 2>/dev/null && pwd -P)" || continue
  abs="$d/$(basename -- "$p")"
  case "$abs/" in "$ROOT"/*) : ;; *) continue;; esac
  [ -f "$abs" ] || continue

  base="${p##*/}"; ext=""; case "$p" in *.*) ext="${p##*.}";; esac
  if [ "$base" = "SKILL.md" ]; then
    purpose="$(purpose_frontmatter "$p")"
  else
    case "$p" in
      agents/*.md|*/agents/*.md) purpose="$(purpose_frontmatter "$p")";;
      *)
        case "$ext" in
          sh|ps1) purpose="$(purpose_header "$p")";;
          *)      purpose="(unclassified)";;
        esac;;
    esac
  fi
  [ -n "$purpose" ] || purpose="(unclassified)"
  purpose="$(first_sentence "$purpose")"

  line="$p$SEP$purpose"

  mapfile -t rels < <(file_relations "$p")
  [ "${#rels[@]}" -gt 0 ] && line="$line (callers: $(join_comma "${rels[@]}"))"

  if [ "$ext" = "sh" ] || [ "$ext" = "ps1" ]; then
    mapfile -t syms < <(extract_symbols "$p")
    [ "${#syms[@]}" -gt 0 ] && line="$line (symbols: $(join_comma "${syms[@]}"))"
  fi

  printf '%s\n' "$line"
  emitted=$((emitted + 1))
done

[ "$emitted" -eq 0 ] && emit_none
exit 0
