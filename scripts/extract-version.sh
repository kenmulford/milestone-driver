#!/usr/bin/env bash
# milestone-driver — deterministic milestone version extractor (issue #158).
# stdin: JSON {title, description?}. stdout: normalized version or empty.
# When empty, stderr is "none" or "ambiguous:<v1>,<v2>,...". Fail-open, exit 0.
set -u
# Force a deterministic byte model: grep -Eob returns BYTE offsets while bash
# ${#text} / ${text:i:1} are CHAR-indexed under a UTF-8 locale, so a multibyte
# title would desync the boundary math (and diverge from the pwsh UTF-16 model).
# LC_ALL=C makes every string operation byte-indexed, keeping the two impls in lockstep.
export LC_ALL=C
emit_none() { printf 'none' >&2; exit 0; }

input="$(cat)"; [ -z "$input" ] && emit_none
command -v jq >/dev/null 2>&1 || emit_none
title="$(printf '%s' "$input" | jq -r '.title // ""' 2>/dev/null)" || emit_none
desc="$(printf '%s' "$input" | jq -r '.description // ""' 2>/dev/null)"

CAND='[vV]?[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?'

# normalize <token> -> echoes normalized version and returns 0, or returns 1.
normalize() {
  local tok="$1" core suffix; tok="${tok#[vV]}"
  core="${tok%%[-+]*}"; suffix=""
  [ "$core" != "$tok" ] && suffix="${tok:${#core}}"
  local IFS='.'; read -r -a comps <<< "$core"
  local n="${#comps[@]}" c
  [ "$n" -ge 2 ] && [ "$n" -le 4 ] || return 1
  for c in "${comps[@]}"; do [[ "$c" =~ ^(0|[1-9][0-9]*)$ ]] || return 1; done
  [ "$n" -eq 2 ] && core="$core.0"
  printf '%s%s' "$core" "$suffix"
}

# part_count <token> -> numeric components in core (2..4)
part_count() { local t="${1#[vV]}"; t="${t%%[-+]*}"; local IFS='.'; read -r -a a <<< "$t"; echo "${#a[@]}"; }

# scan <text> <anchor>  (anchor=1 apply title tiers; anchor=0 prose/first-match)
# echoes accepted normalized versions, one per line, in order.
scan() {
  local text; text="$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  local anchor="$2" len="${#text}" line off match start mlen end before after hasv n norm
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    off="${line%%:*}"; match="${line#*:}"
    start="$off"; mlen="${#match}"; end="$((start+mlen))"
    # boundary before: separator (not alnum or dot)
    if [ "$start" -gt 0 ]; then before="${text:$((start-1)):1}"; [[ "$before" =~ [0-9A-Za-z.] ]] && continue; fi
    # boundary after: not a digit, letter, or dot — symmetric with the before-check
    # (rejects a 5th component, a trailing digit, AND a trailing-letter token like
    # "1.2.3abc"). The suffix (-rc.1 / +build7) is part of the matched token, so the
    # after-char is evaluated PAST the suffix and pre-release/build metadata still pass.
    if [ "$end" -lt "$len" ]; then after="${text:$end:1}"; [[ "$after" =~ [0-9A-Za-z.] ]] && continue; fi
    norm="$(normalize "$match")" || continue
    # 3-tier title anchoring (anchor=1). WHY the tiers exist: bare numeric tokens
    # in a title are mostly NOT versions (dates "2024.06.19", section numbers
    # "section 1.2.3"), so the more ambiguous the shape, the stronger the position
    # it must occupy to be accepted.
    #   • bare 2-part (1.9)      → whole-title only — too ambiguous mid-sentence.
    #   • bare 3/4-part (1.2.3)  → title start OR end — rejects "section 1.2.3 rewrite".
    #   • v-prefixed (v1.2.3)    → anywhere — the explicit "v" disambiguates it.
    # tests/extract-version.cases.tsv is the parity/regression contract that pins
    # the date / section-number false-positive cases; do NOT "simplify" these tiers
    # away — that regresses date_zeropad / bare_3part_mid / date_2part_decorated.
    if [ "$anchor" = "1" ]; then
      case "$match" in [vV]*) hasv=1;; *) hasv=0;; esac
      if [ "$hasv" = "0" ]; then
        n="$(part_count "$match")"
        if [ "$n" -eq 2 ]; then
          [ "$start" -eq 0 ] && [ "$end" -eq "$len" ] || continue   # bare 2-part: whole title only
        else
          [ "$start" -eq 0 ] || [ "$end" -eq "$len" ] || continue   # bare 3/4-part: start or end
        fi
      fi
    fi
    printf '%s\n' "$norm"
  done < <(printf '%s' "$text" | grep -Eob -o "$CAND")
}

# title pass
mapfile -t tv < <(scan "$title" 1)
# distinct, preserve order
declare -a distinct=(); for v in "${tv[@]:-}"; do [ -z "$v" ] && continue
  dup=0; for d in "${distinct[@]:-}"; do [ "$d" = "$v" ] && dup=1 && break; done
  [ "$dup" -eq 0 ] && distinct+=("$v"); done
if [ "${#distinct[@]}" -eq 1 ]; then printf '%s' "${distinct[0]}"; exit 0; fi
if [ "${#distinct[@]}" -ge 2 ]; then
  joined="$(IFS=,; echo "${distinct[*]}")"; printf 'ambiguous:%s' "$joined" >&2; exit 0
fi
# description fallback: first match
mapfile -t dv < <(scan "$desc" 0)
for v in "${dv[@]:-}"; do [ -n "$v" ] && { printf '%s' "$v"; exit 0; }; done
emit_none
