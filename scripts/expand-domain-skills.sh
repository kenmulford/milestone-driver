#!/usr/bin/env bash
# milestone-driver — expand a profile's domainSkills entries into exact,
# invocable plugin:skill names (issue #589).
#
# usage: expand-domain-skills.sh <plugin-cache-root> <entry>...
#
# The cache root is an ARGUMENT, not a hardcoded ~/.claude/plugins/cache, so the
# golden matrix can drive a fixture root; the callers pass the real one.
#
# Per entry:
#   * no `*`            -> passed through unchanged (already an exact name).
#   * `<plugin>:*`      -> every <plugin>:<skill> for which
#                          <root>/<marketplace>/<plugin>/<version-dir>/skills/<skill>/SKILL.md
#                          exists, across every marketplace under the root.
#                          `<plugin>` holds neither `:` nor `*`.
#   * any other `*`     -> unresolved.
#
# Version-directory selection, among the plugin's immediate child directories:
# the highest name matching ^[0-9]+(\.[0-9]+)+$ by COMPONENT-WISE NUMERIC
# compare (1.10.0 beats 1.9.0, which byte order gets wrong); if no name matches,
# the byte-last name. A non-version name is never a skip — the live install's
# plugin-dev sits in a directory literally named `unknown`, and it is the
# selection there.
#
# stdout: resolved names, one per line, LC_ALL=C byte order, deduplicated.
# stderr: one `unresolved: <entry>` line per dropped entry, in argument order.
# Fail-open, ALWAYS exit 0 (mirrors scripts/extract-version.sh): an absent or
# unreadable cache root leaves every wildcard unresolved and still passes the
# exact names through, so a caller never loses its invocable names to a cache
# that is not there.
set -u
# Byte model, the .ps1 twin's byte-domain collation matched: LC_ALL=C makes
# `sort -u` and `[[ a > b ]]` compare BYTES, not the host locale's collation.
export LC_ALL=C

root="${1:-}"
[ "$#" -gt 0 ] && shift

# A leading `~/` only ever arrives QUOTED — an unquoted `~/…` is expanded by the
# shell before exec. Resolving it here puts this leg on the same literal the
# .ps1 twin gets, where no shell expands anything, so the two legs agree on one
# input. Only the `~/<path>` shape resolves: every caller site writes
# `~/.claude/plugins/cache`, and leaving a bare `~` literal keeps every code
# path here covered by the golden matrix.
case "$root" in
  '~/'*) root="${HOME:-}/${root#'~/'}";;
esac

# resolved — newline-terminated accumulator, sorted and deduplicated at exit.
resolved=""

# strip_zeros <digits> — echo the value with leading zeros removed, so `08` and
# `8` compare as the same magnitude below.
strip_zeros() {
  local d="$1"
  while [ "${#d}" -gt 1 ]; do
    case "$d" in 0*) d="${d#0}";; *) break;; esac
  done
  printf '%s' "$d"
}

# version_gt <a> <b> — 0 when dotted-numeric <a> ranks above <b>, comparing
# component by component by MAGNITUDE. A missing component counts as 0, so 1.10
# ranks above 1.9 and 1.2.1 above 1.2. NEVER `[ -gt ]`: a component wider than
# Int64 makes it print `integer expected` on stderr, the channel the caller reads
# `unresolved:` records from. Zeros stripped, a longer digit string is the larger
# value and equal lengths compare bytewise — arbitrary width, no conversion.
version_gt() {
  local a="$1." b="$2." ac bc
  while [ -n "$a" ] || [ -n "$b" ]; do
    ac="${a%%.*}"; bc="${b%%.*}"
    [ -z "$ac" ] && ac=0
    [ -z "$bc" ] && bc=0
    ac="$(strip_zeros "$ac")"; bc="$(strip_zeros "$bc")"
    if [ "${#ac}" != "${#bc}" ]; then
      [ "${#ac}" -gt "${#bc}" ] && return 0
      return 1
    fi
    if [ "$ac" != "$bc" ]; then
      [[ "$ac" > "$bc" ]] && return 0
      return 1
    fi
    a="${a#*.}"; b="${b#*.}"
  done
  return 1
}

# select_version_dir <plugin-dir> — echo the selected child directory NAME, or
# nothing when the plugin directory holds no child directory at all.
select_version_dir() {
  local pdir="$1" d name best="" have_version=0 bytelast=""
  for d in "$pdir"/*/; do
    [ -d "$d" ] || continue
    name="${d%/}"; name="${name##*/}"
    if [ -z "$bytelast" ] || [[ "$name" > "$bytelast" ]]; then bytelast="$name"; fi
    if [[ "$name" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
      if [ "$have_version" -eq 0 ] || version_gt "$name" "$best"; then
        best="$name"; have_version=1
      fi
    fi
  done
  if [ "$have_version" -eq 1 ]; then printf '%s' "$best"; else printf '%s' "$bytelast"; fi
}

for entry in "$@"; do
  case "$entry" in
    *'*'*) ;;
    *) resolved="$resolved$entry
"; continue;;
  esac
  # From here the entry holds a `*`: only the exact `<plugin>:*` shape expands.
  plugin=""
  case "$entry" in
    *:'*') plugin="${entry%:'*'}";;
  esac
  case "$plugin" in
    ''|*'*'*|*:*) printf 'unresolved: %s\n' "$entry" >&2; continue;;
  esac
  found=0
  # An empty root NEVER reaches the glob: `""/*/` expands to `/*/` and walks
  # every top-level directory of the filesystem once per wildcard entry,
  # `/Volumes` and its network mounts included. The .ps1 twin's
  # `Directory.Exists('')` is already False, so skipping the scan holds the two
  # legs to one behavior and one cost — the entry simply goes unresolved.
  if [ -n "$root" ]; then
    for mp in "$root"/*/; do
      [ -d "$mp$plugin" ] || continue
      sel="$(select_version_dir "$mp$plugin")"
      [ -n "$sel" ] || continue
      for s in "$mp$plugin/$sel"/skills/*/SKILL.md; do
        [ -f "$s" ] || continue
        skill="${s%/SKILL.md}"; skill="${skill##*/}"
        resolved="$resolved$plugin:$skill
"
        found=1
      done
    done
  fi
  [ "$found" -eq 1 ] || printf 'unresolved: %s\n' "$entry" >&2
done

printf '%s' "$resolved" | sort -u
exit 0
