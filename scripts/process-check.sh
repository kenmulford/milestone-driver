#!/usr/bin/env bash
# milestone-driver - process-check status and record (issue #791).
# Usage: process-check.sh --status <repo-root>
#        process-check.sh --record <clean|declined> <repo-root>
# --status prints `due` or `current`. --record prints nothing. The marker is
# <main-repo-root>/.milestone-config/.runtime/process-check.json, one line
# {"hash":"<digest>","outcome":"<outcome>"} plus LF; --status compares only hash.
# <main-repo-root> is `git -C <repo-root> rev-parse --show-toplevel` when `--git-dir` and
# `--git-common-dir` agree (the main checkout, a submodule, a --separate-git-dir repo), else
# the first `worktree ` entry of `git -C <repo-root> worktree list --porcelain` (a linked
# worktree), so every worktree and the main checkout share one marker; a failing rev-parse,
# rev-parse output of other than two lines, or no entry uses <repo-root>. `worktree list` alone names the git dir of a separate-git-dir repo, so the
# parent of the common dir and the first list entry both miss its work tree. The scanned files
# and the profile are read from <repo-root>.
# The digest is `git hash-object --stdin` over LF-terminated manifest lines:
# `contract <blob>` first, then `key <name> <raw string value>` per present
# string-valued profile key among integrationGranularity, implementerAgent, unitTestCmd,
# e2eTestCmd, preflightCmd, coherenceReviewAgent (that order; absent and non-string
# keys omitted, as is a value holding any code point below U+0020; exact-case lookup),
# then `declined <blob>` when <main-repo-root>/.milestone-config/.runtime/process-check-declined.json
# is a readable file (absent omitted), so deleting or changing it makes `--status` print `due`,
# then `<blob> <repo-relative path>` per present scanned file in byte order. A
# projectDocs value or standingDocs entry with such a code point is omitted too
# (projectDocs then reads as .project), so no value can split a line or drop in command
# substitution (NUL) and both twins hash identical lines; the jq test is
# `explode | any(. < 32)`, as `contains` on U+0000 matches everything on jq 1.6. Every
# CR in jq's output is stripped, in case a jq emits CRLF. Only those keys join because
# the auditor judges keyed rows against them; hashing the whole profile would re-ask a
# run whose own interview wrote another key (`parallel`). Each <blob> is
# `git hash-object --no-filters`, so line-ending filters never change it; one call
# hashes the contract and every file, and prints the blobs in argument order. The
# contract is skills/process-check.md in this script's own plugin install, since the
# invocation carries no plugin-root argument.
# Scanned files: CLAUDE.md, AGENTS.md and .claude/CLAUDE.md at the repo root, the
# *.md directly inside .project/ and inside the profile's projectDocs directory
# (default .project/), and each standingDocs entry's <doc> part under projectDocs.
# An absent scanned file is skipped, and so is a filename holding any code point below
# U+0020 (an LF would split the manifest line); DEL is not below U+0020 and stays.
# The profile is .milestone-config/driver.json, else
# the legacy root milestone-driver.json, as solve-issue and hooks/tests-green.sh resolve it;
# with neither, the defaults apply.
# The marker is built in a temp file beside it and moved into place, so a failed
# write leaves the old marker. A marker that is not one JSON object with a string
# hash reads as `due`. Check order: usage, jq, driver.json, contract.
# The .ps1 twin parses with JsonDocument, so its jq line never occurs.
# Exit codes: 0 ok · 1 jq absent / unreadable profile or contract / write failure · 2 bad usage.
set -u

err() { printf 'process-check: %s\n' "$*" >&2; }
usage() { err 'usage: process-check (--status | --record <clean|declined>) <repo-root>'; exit 2; }
die() { err "$1"; exit 1; }

outcome=""
case "${1:-}" in
  --status) [ "$#" -eq 2 ] || usage; root="$2" ;;
  --record)
    [ "$#" -eq 3 ] || usage
    outcome="$2"; root="$3"
    case "$outcome" in clean|declined) ;; *) usage ;; esac ;;
  *) usage ;;
esac
[ -n "$root" ] && [ -d "$root" ] || usage
mode="$1"
command -v jq >/dev/null 2>&1 || die 'jq is required but not on PATH'

here="$(cd "$(dirname "$0")" && pwd)"
plugin="$(dirname "$here")"
profile="$root/.milestone-config/driver.json"; pname='.milestone-config/driver.json'
if [ ! -e "$profile" ] && [ -e "$root/milestone-driver.json" ]; then profile="$root/milestone-driver.json"; pname='milestone-driver.json'; fi

pd=""; docs=""; keys=""
if [ -e "$profile" ]; then
  parsed="$([ -f "$profile" ] && jq -rs 'def clean: select(explode | any(. < 32) | not); if length == 1 and (.[0] | type) == "object" then .[0] | ((.projectDocs | strings | clean) // ""), (.standingDocs | arrays | .[] | strings | clean | (split("#")[0] // "")) else error("not one object") end' "$profile" 2>/dev/null)" \
    || die "cannot read $pname"
  parsed="${parsed//$'\r'/}"
  pd="${parsed%%$'\n'*}"
  case "$parsed" in *$'\n'*) docs="${parsed#*$'\n'}" ;; esac
  keys="$(jq -js '.[0] as $p | ["integrationGranularity","implementerAgent","unitTestCmd","e2eTestCmd","preflightCmd","coherenceReviewAgent"][] | . as $k | ($p[$k] | strings | select(explode | any(. < 32) | not)) | "key \($k) \(.)\n"' "$profile" 2>/dev/null; printf x)"
  keys="${keys%x}"; keys="${keys//$'\r'/}"
fi
while [ "${pd#./}" != "$pd" ]; do pd="${pd#./}"; done
while [ "${pd%/}" != "$pd" ]; do pd="${pd%/}"; done
[ -n "$pd" ] || pd='.project'

contract="$plugin/skills/process-check.md"
{ [ -f "$contract" ] && [ -r "$contract" ]; } || die 'cannot read skills/process-check.md'

list=$'CLAUDE.md\nAGENTS.md\n.claude/CLAUDE.md\n'
scan() {
  local LC_ALL=C f n
  for f in "$root/$1"/*.md; do
    n="${f##*/}"; n="${n//$'\177'/}"
    case "$n" in *[[:cntrl:]]*) continue ;; esac
    [ -f "$f" ] && list="$list$1/${f##*/}"$'\n'
  done
}
scan .project
[ "$pd" = '.project' ] || scan "$pd"
while IFS= read -r doc; do
  while [ "${doc#./}" != "$doc" ]; do doc="${doc#./}"; done
  [ -n "$doc" ] && list="$list$pd/$doc"$'\n'
done <<< "$docs"

rels=(); files=()
while IFS= read -r rel; do
  [ -n "$rel" ] && [ -f "$root/$rel" ] && [ -r "$root/$rel" ] || continue
  rels+=("$rel"); files+=("$root/$rel")
done <<< "$(printf '%s' "$list" | LC_ALL=C sort -u)"
blobs="$(git hash-object --no-filters -- "$contract" ${files[@]+"${files[@]}"} 2>/dev/null)" || die 'cannot hash the contract or a scanned file'

main="$root"
if gits="$(git -C "$root" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)"; then
  gits="${gits//\\//}"; gits="${gits//$'\r'/}"
  gd="${gits%%$'\n'*}"; cdir="${gits#*$'\n'}"
  if [ "$cdir" != "$gits" ] && [ "$cdir" = "${cdir%%$'\n'*}" ]; then
    if [ "$gd" = "$cdir" ]; then
      top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" && top="${top//\\//}" && main="${top//$'\r'/}"
    else
      wt="$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n '/^worktree /{s///;p;q;}')"
      wt="${wt//\\//}"; wt="${wt//$'\r'/}"
      [ -n "$wt" ] && main="$wt"
    fi
  fi
fi
[ -n "$main" ] || main="$root"
rt="$main/.milestone-config/.runtime"
marker="$rt/process-check.json"

dline=""
if [ -f "$rt/process-check-declined.json" ] && [ -r "$rt/process-check-declined.json" ]; then
  dblob="$(git hash-object --no-filters -- "$rt/process-check-declined.json" 2>/dev/null)" || die 'cannot hash the contract or a scanned file'
  dline="declined $dblob"$'\n'
fi

manifest=""; i=-1
while IFS= read -r h; do
  if [ "$i" -lt 0 ]; then manifest="contract $h"$'\n'"$keys$dline"
  else manifest="$manifest$h ${rels[$i]}"$'\n'; fi
  i=$((i + 1))
done <<< "$blobs"
digest="$(printf '%s' "$manifest" | git hash-object --stdin 2>/dev/null)"
[ -n "$digest" ] || die 'cannot hash the contract or a scanned file'

if [ "$mode" = "--status" ]; then
  res=""
  [ -f "$marker" ] && res="$(jq -rs --arg d "$digest" 'if length == 1 and .[0].hash == $d then "current" else "due" end' "$marker" 2>/dev/null)"
  res="${res//$'\r'/}"
  if [ "$res" = "current" ]; then printf 'current\n'; else printf 'due\n'; fi
  exit 0
fi

tmp="$marker.tmp.$$"
wfail() { rm -f "$tmp" 2>/dev/null; die 'cannot write .milestone-config/.runtime/process-check.json'; }
mkdir -p "$rt" 2>/dev/null || wfail
[ -d "$marker" ] && wfail
{ printf '{"hash":"%s","outcome":"%s"}\n' "$digest" "$outcome" > "$tmp"; } 2>/dev/null || wfail
mv -f "$tmp" "$marker" 2>/dev/null || wfail
exit 0
