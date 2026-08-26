#!/usr/bin/env bash
# milestone-driver — triage-cache mechanics, extracted from skills/triage/SKILL.md
# Steps 2.5 and 6.5 (issue #441).
#
# Usage:
#   triage-cache.sh query <keys|edges> <owner> <repo> <n>...
#   triage-cache.sh lookup      <repo-root> <graphql-response.json>
#   triage-cache.sh check-edges <repo-root> <graphql-response.json>
#   triage-cache.sh write       <repo-root> <entries.json> <graphql-response.json>
#
# THIS SCRIPT NEVER RUNS `gh`. `query` PRINTS the batched, aliased GraphQL text
# and stops there; the caller runs it (`gh api graphql -f query=…`) and hands
# the response file back to `lookup` / `check-edges` / `write`. Zero of this
# repo's other shipped scripts shell out to `gh`, and the offline golden matrix
# (tests/triage-cache.cases.tsv) could not run one if they did.
#
# `write` COMPUTES each entry's `key` itself, from the same `query keys`
# response the caller already handed `lookup` — one livekey definition per leg,
# so what write stores is by construction what lookup compares against, and the
# caller never handles a key at all (issue #462). Pass the SAVED Step 2.5 file,
# never a fresh fetch: that file predates the Blocker comments Step 6 posts, and
# recomputing from it is what keeps the pre-comment key semantics.
# Pass the KEYS response, never the `query edges` one — an edges response has
# none of the key's fields, so every key it covers computes to "<n>::0:"
# (measured on both legs: empty timestamp, the 0 comment-count default, empty
# label list) and misses forever at exit 0.
#
# Both cache-reading subcommands take the REPO ROOT rather than a cache path,
# because resolving which of the two cache paths is live is part of the
# mechanics being extracted, not the caller's job.
#
# ---- output: TAB-separated records on stdout ------------------------------
# Same TAB-record convention as scripts/check-size-budgets.sh (printf 'OK\t%s\t)
# and scripts/resolve-citation.sh (printf '%s\n' "${recs[@]}").
#
#   query        one line: the GraphQL document. Aliases are issue_<n>, keyed by
#                ISSUE NUMBER (not position), so a response is self-describing
#                and duplicate numbers collapse to one alias.
#   lookup       HIT<TAB><n>
#                MISS<TAB><n><TAB><reason>       no-entry | key-mismatch | no-live-key
#                EDGES<TAB><n>…                  deduplicated union of every HIT
#                                                candidate's cached result.edges;
#                                                the bare token when the union is empty
#                SUMMARY<TAB>hits=<h><TAB>misses=<m>
#   check-edges  MISS<TAB><n><TAB>stale-edge     one per downgraded entry
#                SUMMARY<TAB>stale=<k>
#   write        OK<TAB>.milestone-config/triage-cache.json
#                SKIP<TAB><reason>               no-jq | bad-entries | mkdir-failed | write-failed
#
# A SKIP<TAB><reason> record may replace the whole record set of lookup /
# check-edges / write. It means "no cache information this run" and is the
# fail-open signal the calling skill reports; it is never an error exit.
#
# ---- degradation (fail-open, .project/design-philosophy.md#Error & failure philosophy)
# lookup: degrade to an empty cache. The cache is read from the canonical
#   <root>/.milestone-config/triage-cache.json, falling back to the legacy root
#   <root>/.milestone-driver-triage-cache.json ONLY when the canonical path is
#   ABSENT — a present-but-corrupt canonical file does NOT fall back, because
#   falling back would silently answer from a file the writer stopped
#   maintaining. Absent, unreadable, non-object, or invalid JSON all resolve to
#   an empty cache, every issue then reports MISS no-entry, and no path errors
#   the run.
# check-edges: closed but not merged. A cached entry whose result.edges names an
#   issue that is CLOSED with a stateReason other than COMPLETED is reported as
#   MISS <n> stale-edge, downgrading that entry's HIT to a MISS and forcing
#   re-triage. A dependency closed without merging otherwise leaves its
#   dependents blocked forever on a cached edge that claims they are blocked by
#   an issue nobody is going to merge. The scan covers every cache entry, not
#   just this run's HIT set: a number that was already a MISS is unaffected by a
#   second MISS record, so scoping it costs an argument and buys nothing.
# write: ALWAYS EXITS 0. Every failure path prints one SKIP record and returns
#   success — a cache write must never abort a triage run.
#
# Exit codes: 0 every subcommand's normal and degraded paths · 2 bad usage
#   (unknown subcommand, wrong argument count, non-numeric issue number, owner
#   or repo outside [A-Za-z0-9._-]) — never for `write`, which is exit 0 always.
#
# Dependency: jq on the read/write paths (already permitted —
#   .project/library-manifest.md#Adding a dependency (the gate)); no new tool
#   dependency. `query` needs no jq at all. When jq is absent the read/write
#   paths print SKIP no-jq and exit 0.
# bash-3.2-safe: no ${var,,}, no `declare -A`, no `mapfile`, no process
#   substitution in the record paths (macOS ships /bin/bash 3.2.57).
set -u
export LC_ALL=C

TAB=$'\t'
SELF="triage-cache.sh"

err() { printf '%s\n' "$*" >&2; }
usage() {
  err "usage: $SELF query <keys|edges> <owner> <repo> <n>..."
  err "       $SELF lookup <repo-root> <graphql-response.json>"
  err "       $SELF check-edges <repo-root> <graphql-response.json>"
  err "       $SELF write <repo-root> <entries.json> <graphql-response.json>"
  exit 2
}

# read_cache <root> — echo the live cache object as compact JSON, or {}.
# The first PRESENT path wins; only ABSENCE falls through to the legacy root.
read_cache() {
  local root="$1" p parsed
  for p in "$root/.milestone-config/triage-cache.json" "$root/.milestone-driver-triage-cache.json"; do
    if [ -e "$p" ]; then
      parsed="$(jq -c 'if type == "object" then . else {} end' "$p" 2>/dev/null)" || parsed=""
      [ -n "$parsed" ] || parsed="{}"
      printf '%s' "$parsed"
      return 0
    fi
  done
  printf '%s' "{}"
}

# The two response readers share this preamble: `gh api graphql` wraps the
# aliases in a top-level "data" object, while a hand-saved inner object does
# not. Accept both rather than making the caller unwrap.
JQ_BASE='def basedoc: if (type == "object") and (has("data")) and ((.data | type) == "object") then .data else . end;
def aliases: basedoc | (if type == "object" then . else {} end) | [ to_entries[]
    | select(.key | startswith("issue_"))
    | (.key | ltrimstr("issue_")) as $ns
    | select($ns | test("^[0-9]+$"))
    | { n: ($ns | tonumber),
        x: (if ((.value | type) == "object") and (((.value.issue) | type) == "object")
            then .value.issue else null end) } ];'

# ONE livekey definition for this leg, shared by `lookup` (which compares it
# against the cached key) and `write` (which stamps it). Two copies would drift
# invisibly: the only symptom of a drifted key is a 100% cache miss at exit 0.
# obj/arr are J-Get parity for CONTAINER access. The pwsh twin returns null
# when it indexes a non-object, but jq ERRORS — and a jq error aborts the
# whole program, so one wrong-typed field (`"comments": 5`) collapsed this
# leg to SKIP bad-response while the pwsh leg kept going. Guarding only the
# LEAF with select(...) never ran, because jq aborted one step earlier.
JQ_LIVEKEY='def obj($v): if ($v | type) == "object" then $v else {} end;
def arr($v): if ($v | type) == "array"  then $v else [] end;
# select(type == …) before each // : the fallback fires when the field is
# absent, null, OR the wrong JSON type — exactly what the pwsh twin can
# express over a JsonElement. An EMPTY lastEditedAt IS a string, so it is
# still kept verbatim rather than replaced by createdAt, on both legs.
def livekey($n; $x):
  (($x.lastEditedAt | select(type == "string"))
   // ($x.createdAt | select(type == "string")) // "") as $ts
  | ((obj($x.comments).totalCount | select(type == "number")) // 0) as $cc
  # map(select(type == "string")) drops a label node with no name: the
  # pwsh twin skips it too, and without the filter jq would fold it in as
  # a null that sorts first and joins as an empty field. obj(.) covers a
  # node that is not an object at all (`["str"]`), which .name would error on.
  | (arr(obj($x.labels).nodes) | map(obj(.).name) | map(select(type == "string")) | sort | join(",")) as $lb
  | "\($n):\($ts):\($cc):\($lb)";'

sub="${1-}"
[ -n "$sub" ] || usage

case "$sub" in
  query)
    # `query` is pure text generation: no jq, no filesystem, no network.
    [ "$#" -ge 5 ] || usage
    kind="$2"; owner="$3"; repo="$4"
    shift 4
    case "$kind" in keys|edges) ;; *) usage ;; esac
    # Validate rather than escape: every real owner/repo is already inside this
    # set, and a validated value cannot break out of the GraphQL string literal
    # below (no quote, no backslash, no newline can reach it).
    case "$owner" in ''|*[!A-Za-z0-9._-]*) usage ;; esac
    case "$repo"  in ''|*[!A-Za-z0-9._-]*) usage ;; esac
    if [ "$kind" = keys ]; then
      opname="BatchTimestamps"
      fields="lastEditedAt createdAt comments { totalCount } labels(first:100) { nodes { name } }"
    else
      opname="BatchEdgeStates"
      fields="state stateReason"
    fi
    # Dedup preserving first-seen order. bash-3.2-safe membership test: a
    # space-delimited seen-list, not an associative array.
    body=""
    seen=" "
    for n in "$@"; do
      case "$n" in ''|*[!0-9]*) usage ;; esac
      case "$seen" in *" $n "*) continue ;; esac
      seen="$seen$n "
      body="$body issue_$n: repository(owner:\"$owner\", name:\"$repo\") { issue(number:$n) { $fields } }"
    done
    [ -n "$body" ] || usage
    printf 'query %s {%s }\n' "$opname" "$body"
    exit 0
    ;;

  lookup|check-edges)
    [ "$#" -eq 3 ] || usage
    root="$2"; argfile="$3"
    ;;

  # `write` alone takes FOUR: it recomputes each entry's key from the response.
  # The response is NOT optional — an optional argument would restore exactly
  # the "the key can be omitted" hole this signature exists to close (#462).
  write)
    [ "$#" -eq 4 ] || usage
    root="$2"; argfile="$3"; respfile="$4"
    ;;

  *) usage ;;
esac

# One shared no-jq gate for the three jq-backed subcommands. Fail-open: the
# caller treats SKIP as "no cache information", re-triages everything, and the
# run proceeds (pattern from hooks/tests-green.sh (input="$(cat)"; [ -z "$input" ] &&)).
if ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP%sno-jq\n' "$TAB"
  exit 0
fi

case "$sub" in
  lookup)
    resp="$(jq -c '.' "$argfile" 2>/dev/null)" || resp=""
    if [ -z "$resp" ]; then
      printf 'SKIP%sbad-response\n' "$TAB"
      exit 0
    fi
    cache="$(read_cache "$root")"
    # One pass: alias set -> live key per issue -> HIT/MISS partition -> the
    # HIT set's deduplicated edge union -> summary. Sorted by issue number so
    # the record order is independent of both the response's key order and the
    # host JSON parser's property ordering.
    # BUFFERED, not streamed: a jq program that errors part-way through `.[]`
    # has already written the records before it, so streaming would emit a
    # partial record set AND the SKIP line. The record set is bounded by the
    # issue count, so holding it costs nothing.
    out="$(printf '%s' "$resp" | jq -r --argjson cache "$cache" "$JQ_BASE$JQ_LIVEKEY"'
      def edges_of($v): if ($v | type) == "object"
                        then (($v.result?) | if type == "object" then (.edges? // []) else [] end)
                        else [] end
                        | if type == "array" then . else [] end;
      aliases
      | sort_by(.n)
      | [ .[]
          | . as $i
          | ($cache[($i.n | tostring)] // null) as $e
          | if ($i.x == null) then { n: $i.n, hit: false, reason: "no-live-key" }
            elif ($e | type) != "object" then { n: $i.n, hit: false, reason: "no-entry" }
            elif (($e.key // "") == livekey($i.n; $i.x)) then { n: $i.n, hit: true, reason: "" }
            else { n: $i.n, hit: false, reason: "key-mismatch" }
            end ] as $rows
      | if ($rows | length) == 0 then [ "SKIP\tbad-response" ]
        else
          ([ $rows[] | select(.hit) | .n ]) as $hits
          | ([ $hits[] | edges_of($cache[(. | tostring)])[] ]
             | map(select(type == "number")) | unique) as $edges
          | [ $rows[] | if .hit then "HIT\t\(.n)" else "MISS\t\(.n)\t\(.reason)" end ]
            + [ (["EDGES"] + ($edges | map(tostring))) | join("\t") ]
            + [ "SUMMARY\thits=\($hits | length)\tmisses=\(($rows | length) - ($hits | length))" ]
        end
      | .[]' 2>/dev/null)" || out=""
    if [ -z "$out" ]; then
      printf 'SKIP%sbad-response\n' "$TAB"
    else
      printf '%s\n' "$out"
    fi
    exit 0
    ;;

  check-edges)
    resp="$(jq -c '.' "$argfile" 2>/dev/null)" || resp=""
    if [ -z "$resp" ]; then
      printf 'SKIP%sbad-response\n' "$TAB"
      exit 0
    fi
    cache="$(read_cache "$root")"
    # Buffered for the same reason as lookup above.
    out="$(printf '%s' "$resp" | jq -r --argjson cache "$cache" "$JQ_BASE"'
      def edges_of($v): if ($v | type) == "object"
                        then (($v.result?) | if type == "object" then (.edges? // []) else [] end)
                        else [] end
                        | if type == "array" then . else [] end;
      aliases
      | [ .[] | select(.x != null) | { key: (.n | tostring), value: .x } ] | from_entries as $states
      | if ($states | length) == 0 then [ "SKIP\tbad-response" ]
        else
          [ $cache | to_entries[]
            | select(.key | test("^[0-9]+$"))
            | { n: (.key | tonumber), es: edges_of(.value) }
            | select([ .es[]
                       | tostring as $k
                       | $states[$k]
                       | select(. != null)
                       | select((.state? == "CLOSED") and ((.stateReason? // "") != "COMPLETED")) ]
                     | length > 0)
            | .n ] | unique as $stale
          | [ $stale[] | "MISS\t\(.)\tstale-edge" ]
            + [ "SUMMARY\tstale=\($stale | length)" ]
        end
      | .[]' 2>/dev/null)" || out=""
    if [ -z "$out" ]; then
      printf 'SKIP%sbad-response\n' "$TAB"
    else
      printf '%s\n' "$out"
    fi
    exit 0
    ;;

  write)
    # From here on EVERY exit is 0. `skip` is the only failure vocabulary.
    skip() { printf 'SKIP%s%s\n' "$TAB" "$1"; exit 0; }
    entries="$(jq -c 'if type == "object" then . else error("not-an-object") end' "$argfile" 2>/dev/null)" || entries=""
    [ -n "$entries" ] || skip "bad-entries"
    cache="$(read_cache "$root")"
    # Number -> live key, from the SHARED livekey definition `lookup` compares
    # with. An absent, unreadable, or unparseable response yields an EMPTY map:
    # entries are then stored exactly as supplied, with no new SKIP reason and
    # still exit 0 — fail-open, the same posture as the cache read itself. The
    # cost of that degradation is one extra re-triage next run, never a wrong key.
    keys="$(jq -c "$JQ_BASE$JQ_LIVEKEY"'
      aliases
      | [ .[] | select(.x != null) | { key: (.n | tostring), value: livekey(.n; .x) } ]
      | from_entries' "$respfile" 2>/dev/null)" || keys=""
    [ -n "$keys" ] || keys="{}"
    # Entry-level overwrite, matching the recorded rule "write or overwrite its
    # entry" — a re-triaged issue replaces its own entry and touches no other.
    # The key is stamped onto the INJECTED entries only: an untouched cache entry
    # keeps its stored key (and its byte-preserved triaged_at) verbatim, and an
    # injected entry the response does not cover keeps whatever it was handed.
    merged="$(printf '%s' "$cache" | jq --argjson e "$entries" --argjson k "$keys" '
      . + ($e | with_entries(
            if ((.value | type) == "object") and (($k[.key] // null) != null)
            then .value += { key: $k[.key] } else . end))' 2>/dev/null)" || merged=""
    [ -n "$merged" ] || skip "bad-entries"

    dir="$root/.milestone-config"
    mkdir -p "$dir" 2>/dev/null || skip "mkdir-failed"

    # Self-heal the scratch-ignore BEFORE the write, so the cache is
    # git-invisible in a consumer repo from the very first write with zero user
    # setup, while the tracked config (driver.json, feeder.json) stays tracked.
    # Create only when absent; never rewrite an existing file. Best-effort, on
    # the same fail-open footing as the write itself.
    # KEEP THIS BLOCK IN SYNC with the committed .milestone-config/.gitignore in
    # this repo and with solve-issue / solve-milestone / hooks/tests-green.{sh,ps1},
    # feeder setup / plan.
    # The redirect sits INSIDE a group whose 2>/dev/null covers it: a plain
    # `cat > file 2>/dev/null` silences cat but NOT the redirect's own
    # open-failure, which bash reports on real fd2 — a stray diagnostic line
    # from a best-effort step, on a leg whose stderr is byte-pinned against the
    # pwsh twin's (same group idiom as
    # scripts/write-cost-record.sh (is swallowed by the group's 2>/dev/null)).
    if [ ! -e "$dir/.gitignore" ]; then
      { cat > "$dir/.gitignore" <<'GITIGNORE_BLOCK'
# milestone-driver / milestone-feeder per-clone scratch — git-invisible by default.
# Committed so per-run scratch stays out of `git status` with zero user setup.
# Patterns are relative to this .milestone-config/ directory. Tracked config
# (driver.json, feeder.json) is intentionally NOT listed, so it stays tracked.
*-notice
triage-cache.json
tests-stamp
.runtime/
worktrees/
GITIGNORE_BLOCK
      } 2>/dev/null || :
    fi

    # Write to a per-process temp file and rename, so a concurrent reader sees
    # either the old object or the new one and never a half-written file.
    tmp="$dir/triage-cache.json.tmp.$$"
    if ! { printf '%s\n' "$merged" > "$tmp"; } 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null
      skip "write-failed"
    fi
    if ! mv -f "$tmp" "$dir/triage-cache.json" 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null
      skip "write-failed"
    fi

    # Only after the canonical file exists: drop the legacy root cache so it
    # stops shadowing future transitional reads.
    rm -f "$root/.milestone-driver-triage-cache.json" 2>/dev/null

    printf 'OK%s.milestone-config/triage-cache.json\n' "$TAB"
    exit 0
    ;;
esac
