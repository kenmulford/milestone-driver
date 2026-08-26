#!/usr/bin/env bash
# milestone-driver — CI size-budget ratchet (issue #295).
# Byte ceiling added by issue #399. Word ceiling added by issue #489.
#
# Guards the size of a small set of GOVERNED files (the core skills/*/SKILL.md
# files, the reviewer/implementer agents/*.md files, and the sibling reference
# docs split out of the once-monolithic SKILL.md files) against THREE per-file
# ceilings recorded in the table below: a LINE ceiling, a BYTE ceiling and a
# WORD ceiling. Dependency-free: `wc -l`, `wc -c`, `tr` and `grep` only, no
# YAML/markdown library (mirrors ci-preflight-steps.sh's
# line-oriented-parser posture;
# .project/library-manifest.md#Adding a dependency (the gate), "no new tool
# dependency"). `tr` and `grep` are POSIX shell utilities already relied on
# across scripts/, not a new dependency in the sense that gate means; they
# replace `wc -w`, which is not portable for this content — see the word-count
# block below.
#
# Which unit is authoritative (issue #399):
#   - BYTES is authoritative for COST. Every governed file loads into context
#     on every run, and that cost tracks bytes, not lines. So prose APPENDED TO
#     AN EXISTING LINE IS governed here: it moves the byte count while the
#     line count does not move at all. PR #398 appended 1052 bytes to
#     skills/solve-milestone/SKILL.md at a flat 664 lines and this ratchet
#     reported no change; three later merges added another 3818 bytes ACROSS
#     THE GOVERNED SET the same way (#363 +1200, #365 +2439, #397 +179, all
#     at zero line delta, none of them in that file). The byte ceiling sees it.
#   - LINES is kept as a second, independent ceiling, not replaced: this repo's
#     cross-file `file:line` citations anchor to line numbers, so line growth
#     carries a cost of its own that a byte count cannot express (issue #397
#     re-derived 18 citations staled by line shifts).
#   - BYTES, NOT CHARACTERS. This script runs under LC_ALL=C, where `wc -m`
#     already returns bytes; and a character count cannot be made
#     byte-identical across the bash/pwsh twins, because .NET strings are
#     UTF-16 (an astral character, which includes most emoji, is 1 character to
#     a UTF-8-aware count but 2 code units to a naive .Length). Bytes are
#     locale-independent and identical on both sides by construction.
#   - WORDS AS WELL, and issue #489 reversed #399 to add them. #399's argument
#     was that word count undercounts: "scripts/check-size-budgets.ps1" scores
#     1 word for 30 bytes, and these files are dense with such path/flag tokens.
#     That measurement is correct and is exactly why words are a THIRD ceiling
#     rather than a replacement — it makes the word axis blind to the growth
#     the byte axis sees best, and BLINDNESS IN ONE AXIS IS ONLY A REASON TO
#     DROP IT IF NO OTHER AXIS IS BLIND WHERE IT SEES. Words are what
#     superpowers:writing-skills (a domainSkill of this repo) sizes a skill by,
#     because words track the LOAD an agent must actually read, and they move
#     under a flat byte total when dense path/flag tokens are traded for
#     ordinary prose — the same trade a rewrite for readability makes.
#     tests/fixtures/check-size-budgets/byte-flat-word-over/ is that shape
#     pinned: 40/40 lines and 4500/4500 bytes, both unmoved, 726 words against
#     a 700 ceiling.
#   - Byte counts read the file ON DISK. A CRLF working tree (Windows
#     core.autocrlf) therefore reads one extra byte per line: 0.29% to 2.27%
#     across the governed set. THE HEADROOM DOES NOT ABSORB THAT, and an earlier
#     version of this comment claiming it did was wrong. Measured on a simulated
#     autocrlf tree, TODAY: agents/design-reviewer.md carries 0.55% headroom
#     against a 0.72% CRLF cost, so it STILL FAILS (16528/16500) on a Windows
#     contributor's first clone, on a file they never touched. Its twin
#     agents/triage-reviewer.md no longer does: issue #464 raised that file's
#     byte ceiling for reasons unrelated to CRLF, and 16689/17000 now absorbs
#     the cost. That is one file clearing it, not the set, and the pin is what
#     keeps it from mattering. What guarantees the byte ceilings mean the
#     same number on every platform is the `*.md text eol=lf` PIN in
#     .gitattributes, alongside the pins already held by *.sh, *.ps1, *.tsv,
#     *.txt, *.yml and tests/fixtures/**. Do not remove it, and do not size a
#     ceiling to tolerate CRLF instead. The LINE count stays CRLF-proof either
#     way (the pwsh twin counts 0x0A bytes). The WARN record in the output
#     stream below is the standing guard against a file drifting back into that
#     state unseen: it fires the moment byte headroom drops under the line
#     count, which is exactly the CRLF cost.
#
# Ceiling discipline (documented, not machine-enforced):
#   - CEILINGS ONLY GO DOWN, NEVER UP. Each ceiling starts at the governed
#     file's actual count (when the ratchet was introduced, or last tightened)
#     plus ~5% headroom, ROUNDED UP TO A FIXED GRANULARITY so the 15 derivations
#     stay arithmetic instead of 15 judgment calls: the next 500 BYTES on the
#     byte axis, the next 5 LINES on the line axis, the next 100 WORDS on the
#     word axis. The word granularity is NOT the byte granularity divided by
#     this set's density: 500 bytes over the measured 6.26-7.25 bytes per word
#     (mean ~6.8) is ~73 words, and rounding that lands on 70, not 100. 100 is
#     chosen instead because it is the round step at the same order of
#     magnitude, and because it doubles as the word axis's minimum-headroom
#     floor — the smallest allowance it grants is 90 words, on the 581-word
#     skills/solve-issue/async-mode.md, so the word axis needs no separate
#     `actual + N` floor rule of the kind the line axis required.
#   - THE WORD AXIS ALSO CARRIES A HARD 5000-WORD CAP, which is
#     superpowers:writing-skills' ceiling for one skill. A file at or under
#     5000 words takes min(derived, 5000), so the 5% headroom can never ratchet
#     a compliant file PAST the cap. FOUR files were already over it when #489
#     landed; each seeded at its own actual + headroom and ratchets DOWN toward
#     the cap as it is split, in the SAME change that shrinks it. Capping them
#     at 5000 on day one would have failed the gate on content #489 does not
#     change. Milestone #39's splits brought TWO of the four under, and both
#     have now taken the cap: skills/solve-milestone/SKILL.md 4976 and
#     skills/triage/SKILL.md 4926, each ceilinged at 5000 rather than at the
#     5300/5200 their own actuals would derive. TWO remain over and still seed
#     from their own actuals — skills/solve-issue/SKILL.md 5703 (ceiling 6000)
#     and skills/solve-milestone/parallel-waves.md 5647 (ceiling 6000). All
#     four measured 2026-08-10.
#   - BOTH AXES CARRY A MINIMUM-HEADROOM FLOOR, and the line axis needs its own
#     because 5% of a small line count is not a usable allowance. A LINE CEILING
#     IS NEVER LOWERED BELOW `actual + 5` ROUNDED UP TO THE NEXT 5. Without it,
#     5% of a 33-line file granted 2 lines: skills/solve-issue/async-mode.md
#     derived a 35-line ceiling that an ordinary 3-line bullet would break while
#     the file still sat 473 bytes under its byte ceiling, and
#     md-epic-fanout.md at 52 lines was the same shape. The 500-byte granularity
#     already does this job on the byte axis, which is why only the line axis
#     had to be told. APPLY BOTH AXES' FLOORS on every re-derivation.
#   - When a governed file SHRINKS (a future split/trim), lower ALL THREE of
#     its ceilings to the new actuals + headroom in the SAME change that
#     shrinks it.
#   - Raising a ceiling requires a recorded decision in the Decision Log of
#     the PR body that grows the file. This script enforces whatever ceiling
#     it is given — it has no opinion on when raising one is warranted.
#     RECORDED RAISE, issue #464 (decision 2026-08-06): agents/triage-reviewer.md
#     BYTE 16500 -> 17000, agents/design-reviewer.md LINE 115 -> 120, each
#     narrowed to what its own file actually needed rather than raised in
#     lockstep. That authorization is spent on that issue's three fixes and
#     covers nothing else: the next edit to either row re-derives normally, and
#     both go down again from there.
#     RECORDED RAISE, issue #520 (decision 2026-08-18):
#     skills/solve-issue/wave-clauses.md BYTE 3000 -> 3500. The two rows that
#     issue requires (`6.7`, `Autonomy model`) measure 227 + 229 = 456 bytes
#     against 193 free (2807/3000), so 263 bytes cannot be found without
#     rewriting the shipping clause rows that issue lists as a non-goal.
#     New actual 3263; 3263 * 1.05 = 3426.15, rounded UP to the next 500 =
#     3500. LINE 18/25 and WORD 471/500 still hold, so neither moves.
#     Spent on this issue's two rows: the next edit re-derives normally.
#     RECORDED RAISE, issue #606 (decision 2026-08-26):
#     skills/notices.md LINE 250 -> 290, BYTE 11500 -> 13500, WORD 1600 -> 1900,
#     and skills/solve-issue/SKILL.md's CLOSURE 11000 -> 11600, which follows
#     from the same growth (notices.md is one of its members).
#     #606 appends two `##` notice sections (visual-hold-removed,
#     code-review-run-no) to the file whose own header declares it a growing
#     list. Their bare scaffolding alone, before a sentence of content, is
#     ~26 lines and ~724 bytes: two headings, two Marker lines, two
#     Skills/Trigger/Legacy lines, two `**Text:**` blocks, two fences, two
#     banner lines, two `## Contents` entries. The row had 9 lines and 971
#     bytes free, so no phrasing of the two Texts fits, and no in-file trade
#     exists either: this file's ONLY anchored citation points at the one
#     `It sits here` paragraph that would otherwise be the cut, and dropping
#     it recovers 8 lines against a 23-line gap while breaking that citation.
#     New actuals 273 / 12533 / 1755. 273 * 1.05 = 286.65, rounded UP to the
#     next 5 = 290 (the `actual + 5` floor gives 280, so the derivation
#     governs); 12533 * 1.05 = 13159.65, rounded UP to the next 500 = 13500;
#     1755 * 1.05 = 1842.75, rounded UP to the next 100 = 1900, under the
#     5000-word cap. The BYTE number is a RESTORE, not an invention: this row
#     read 13500 until a215feb (`chore: v1.20.0 end-of-milestone pass (#460)`)
#     tightened it to 11500. The LINE ceiling has been 250 since the row was
#     created and has never moved; this is its first raise. The closure sum
#     11041 * 1.05 = 11593.05, rounded UP to the next 100 = 11600, by the
#     closure rule below; solve-milestone's closure holds at 9167/9200 and
#     does NOT move. Spent on this issue's two sections: the next edit
#     re-derives normally.
#     RECORDED RAISE, issues #605 / #608 / #609 (decision 2026-08-26):
#     skills/solve-issue/SKILL.md BYTE 41500 -> 45500, WORD 5800 -> 6300;
#     skills/solve-issue/post-fix-commit.md BYTE 4500 -> 5000, WORD 700 -> 800;
#     skills/solve-milestone/parallel-waves.md BYTE 39500 -> 43000,
#     WORD 5900 -> 6400; agents/implementer.md BYTE 14500 -> 15500.
#     Every LINE ceiling holds and none moves (313/325, 20/25, 197/205,
#     129/130), as do agents/implementer.md's WORD 2174/2200 and
#     solve-issue's CLOSURE 11304/11600.
#     The three issues add clauses rather than restate them: the
#     classifier-verdict review ladder (#608 in SKILL.md and
#     post-fix-commit.md, #609 in parallel-waves.md), and the code-comment
#     rule plus the reviewer out-of-scope sentence (#605 in SKILL.md,
#     parallel-waves.md and implementer.md). Deleting two columns from
#     SKILL.md's build-profile table is the only recovery available: every
#     other paragraph in the touched regions is a shipping clause one of the
#     three issues lists as a non-goal, so no in-file trade exists.
#     New actuals, all measured 2026-08-26: 43102 / 5980, 4703 / 722,
#     40703 / 6006, 14680.
#     43102 * 1.05 = 45257.1, UP to the next 500 = 45500;
#     5980 * 1.05 = 6279, UP to the next 100 = 6300;
#     4703 * 1.05 = 4938.15, UP to the next 500 = 5000;
#     722 * 1.05 = 758.1, UP to the next 100 = 800;
#     40703 * 1.05 = 42738.15, UP to the next 500 = 43000;
#     6006 * 1.05 = 6306.3, UP to the next 100 = 6400;
#     14680 * 1.05 = 15414, UP to the next 500 = 15500.
#     The 5000-word cap binds none of the four: SKILL.md and parallel-waves.md
#     are the two files this header already records as over it and seeding
#     from their own actuals, and the other two rows sit far under it.
#     SKILL.md's byte raise also clears its standing CRLF WARN, which had 154
#     bytes free against 309 lines.
#     Spent on these three issues' clauses: the next edit re-derives normally.
#   - A governed file that is renamed or deleted is a FAILURE, not a silent
#     pass — the table must be updated (moved or removed) in the SAME change,
#     with a recorded decision if a file is dropped from governance.
#   - CLOSURE ceilings ratchet the same way — `actual * 1.05` rounded UP to the
#     next 100 words, down freely, up only with a recorded decision — with ONE
#     documented difference: THE 5000-WORD CAP DOES NOT APPLY TO THEM. That cap
#     is superpowers:writing-skills' ceiling for ONE skill file, and a closure is
#     a sum across several; applying it would put every closure permanently over
#     on day one and say nothing about any file. The four closures seeded at
#     their measured actuals (2026-08-10, issue #491): setup 7413, solve-issue
#     14820, solve-milestone 14469, triage 8682.
#
# Usage:   check-size-budgets.sh [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# Output (stdout), one line per governed file, then one line per governed
# SKILL's load closure, then a trailing summary, TAB-separated (mirrors
# ci-preflight-steps.sh's STEP/SKIP/SUMMARY stream):
#   OK    <path>  <lines>/<lineCeiling>  <bytes>/<byteCeiling>  <words>/<wordCeiling>
#   WARN  <path>  <free> bytes free < <lines> lines (a CRLF checkout would FAIL this row)
#   FAIL  <path>  <lines>/<lineCeiling>  <bytes>/<byteCeiling>  <words>/<wordCeiling>
#   FAIL  <path>  MISSING/<lineCeiling>  MISSING/<byteCeiling>  MISSING/<wordCeiling>
#   CLOSURE <skillPath>  <wordSum>/<closureWordCeiling>
#   CLOSURE <skillPath>  MISSING/<closureWordCeiling>
#   SUMMARY ok=<N> failed=<M>
# A file FAILS when ANY count is over its ceiling, and all three columns always
# print, so the record itself shows which one moved. Exit 0 when every governed
# file is present and at/under ALL THREE ceilings; exit 1 when any file is
# missing or over. bash-3.2-safe (no ${var,,}, no `declare -A`, no `mapfile`).
#
# A WARN record (issue #574) FOLLOWS the OK record of a file whose BYTE HEADROOM
# IS SMALLER THAN ITS LINE COUNT, the one condition under which a file passes
# here and fails on a core.autocrlf clone, which reads one extra byte per line.
# It is ADVISORY: it changes no exit code, is counted in NEITHER ok= NOR
# failed=, and is emitted only after an OK record, never after a FAIL (a FAIL is
# already the louder signal on that file). Repay a WARN by trading bytes inside
# the file; raising the ceiling to silence it is the move the ratchet forbids.
#
# The CLOSURE record (issue #491) is INFORMATIONAL AND NEVER GATES. It carries
# ONE unit, words, because words are what superpowers:writing-skills sizes a
# skill by and the only axis with a published per-skill standard; it names the
# skill by its SKILL.md path so it reads against the per-file rows above without
# a second naming scheme; and it keeps the `<actual>/<ceiling>` column shape of
# those rows so one reader parses the whole stream. Its position — after every
# per-file row and before the trailing SUMMARY — is what makes it additive: a
# consumer reading the first field still sees the same OK/FAIL rows in the same
# order and the same SUMMARY last.
#
# NEVER GATES is the load-bearing half, and it is a MILESTONE-SCOPED CHOICE, not
# a permanent property. A closure sum over its ceiling changes NO exit code and
# is counted in NEITHER ok= nor failed=; only the per-file rows decide those. A
# closure whose sum cannot be computed (any member absent from disk) prints
# MISSING and still changes no exit code — that member is itself a governed file,
# so its own `FAIL <path> MISSING/...` row above has already failed the run, and
# failing twice for one deletion would double-count it in failed=.
set -u
export LC_ALL=C

ROOT="${1:-$PWD}"
ROOT="${ROOT%/}"

# The governed set, ONE ROW PER FILE:
#
#   <path>   <lineCeiling>   <byteCeiling>   <wordCeiling>
#
# All four columns of a file sit on the same line, so a file's three ceilings
# can no longer be MOVED apart from their path, and every number is read next
# to the path it belongs to. Issue #428 is why: this used to be
# free-standing parallel arrays, and length was all the guard below compared.
# Swapping two entries inside FILES alone kept every length equal, passed
# the guard, measured each file against the other's ceiling and still exited 0
# — and reading a ceiling meant counting down an unlabelled column, which on
# 2026-08-05 mis-reported skills/triage/SKILL.md as having 26KB of byte
# headroom when it had 66 bytes. One row per file removes that MOVE, and every
# plausible accident with it; deliberately swapping two path STRINGS between
# rows still desyncs silently, which no table shape can prevent. See the header
# for the ratchet discipline that governs these numbers. Rows start at column
# 0; `#` starts a comment row.
#
# BYTE ceilings were set from the actuals measured at introduction (issue #399)
# as actual * 1.05 rounded UP to the next 500 bytes; WORD ceilings the same way
# at introduction (issue #489, actuals measured 2026-08-10) rounded UP to the
# next 100 words, then capped at 5000 for every file already at or under it.
# Same ratchet discipline as the line ceilings: down freely, up only with a
# decision recorded in the PR body.
FILES=()
CEILINGS=()
BYTE_CEILINGS=()
WORD_CEILINGS=()
nfiles=0
nceilings=0
nbytes=0
nwords=0
# A row contributes to a ceiling array only when that column is present AND all
# digits, so a hand-edit that drops or garbles a column leaves the four counts
# unequal and trips the parity guard below. Without the digit check a garbled
# ceiling would reach `[ "$actual" -gt "$ceiling" ]`, which prints "integer
# expression expected" on stderr and then takes the FALSE branch — a silent OK,
# the same shape of quiet wrong answer #428 removed.
# bash-3.2-safe: `read` and `case` builtins plus index assignment, no
# associative arrays and no `mapfile`; the heredoc feeds the loop in the
# CURRENT shell, so the arrays it fills survive it.
while read -r f line_ceiling byte_ceiling word_ceiling; do
  case "$f" in ''|'#'*) continue ;; esac
  FILES[$nfiles]="$f"; nfiles=$((nfiles + 1))
  case "$line_ceiling" in ''|*[!0-9]*) ;; *) CEILINGS[$nceilings]="$line_ceiling"; nceilings=$((nceilings + 1)) ;; esac
  case "$byte_ceiling" in ''|*[!0-9]*) ;; *) BYTE_CEILINGS[$nbytes]="$byte_ceiling"; nbytes=$((nbytes + 1)) ;; esac
  case "$word_ceiling" in ''|*[!0-9]*) ;; *) WORD_CEILINGS[$nwords]="$word_ceiling"; nwords=$((nwords + 1)) ;; esac
done <<'GOVERNED_TABLE'
skills/setup/SKILL.md                               280    28000     4000
skills/solve-issue/SKILL.md                         325    45500     6300
skills/solve-issue/async-mode.md                     40     4500      700
skills/solve-issue/md-epic-fanout.md                 60     8500     1200
skills/solve-issue/coherence-review.md               15     2500      300
skills/solve-issue/milestone-clauses.md              30     6000      900
skills/solve-issue/permission-preflight.md           35     2500      400
skills/solve-issue/post-fix-commit.md                25     5000      800
skills/solve-issue/preflight-github-ci.md            20     3000      400
skills/solve-issue/resume-paths.md                   20     3000      500
skills/solve-issue/version-bump.md                   20     4000      600
skills/solve-issue/visual-capture.md                 20     6000      800
skills/solve-issue/wave-clauses.md                   25     3500      500
skills/solve-milestone/SKILL.md                     320    32500     4500
skills/solve-milestone/parallel-waves.md            205    43000     6400
skills/solve-milestone/trello-sync.md               400    19500     3000
skills/solve-milestone/milestone-granularity.md     165    23500     3300
skills/solve-milestone/abandoned-recovery.md         45     5500      900
skills/solve-milestone/blocked-label-clear.md        25     2500      400
skills/solve-milestone/changelog-authoring.md       205    14000     2200
skills/solve-milestone/contingencies.md              70     8500     1200
skills/solve-milestone/db-hazard-interview.md        30     2500      400
skills/solve-milestone/integration-granularity.md    85    15000     2300
skills/solve-milestone/md-epic-parent-check.md       30     2500      400
skills/solve-milestone/not-buildable.md              20     3500      500
skills/solve-milestone/sequential-loop.md            35     7500     1100
skills/solve-milestone/simplify-pass.md             125    14000     2100
skills/solve-milestone/version-target.md             30     3000      400
skills/triage/SKILL.md                              390    34000     5000
skills/triage/blocker-resolver-dispatch.md           60     5000      800
skills/notices.md                                   290    13500     1900
skills/output-style.md                               85     9500     1600
skills/citation-format.md                           190    10500     1600
skills/remediate-handoff.md                          90     5000      800
agents/blocker-resolver.md                          125    10500     1700
agents/design-reviewer.md                           120    16000     2400
agents/implementer.md                               130    15500     2200
agents/triage-reviewer.md                           120    16000     2500
GOVERNED_TABLE

# Length-parity guard: the parse above appends a path unconditionally and each
# ceiling only when its column is present and numeric, so a malformed row shows
# up here as unequal counts. That must fail loud, not desync the loop (which
# would misattribute ceilings under `set -u`, or die mid-loop on an unbound
# index).
if [ "$nfiles" -ne "$nceilings" ] || [ "$nfiles" -ne "$nbytes" ] || [ "$nfiles" -ne "$nwords" ]; then
  printf 'ERROR check-size-budgets: FILES(%s), CEILINGS(%s), BYTE_CEILINGS(%s) and WORD_CEILINGS(%s) length mismatch, fix the table\n' \
    "$nfiles" "$nceilings" "$nbytes" "$nwords" >&2
  exit 1
fi

# The UNCONDITIONAL LOAD CLOSURE of each governed skill (issue #491), ONE ROW
# PER SKILL:
#
#   <skillPath>   <closureWordCeiling>   <member> <member> ...
#
# Why the record exists: a per-file ceiling understates what a skill actually
# costs, because a SKILL.md is never the whole load. Moving 2,000 words out of
# a SKILL.md and into a file that same skill read-directs on EVERY run leaves
# the agent reading exactly as many words as before while the per-file table
# reports a 2,000-word improvement. The closure sum is what makes that trade
# visible: it does not move.
#
# Column 1 is BOTH the record's label AND the first member of its own closure —
# a skill's SKILL.md is counted implicitly and is never listed in the members
# column. That is deliberate, and it is the same class of protection the
# one-row-per-file shape gives GOVERNED_TABLE: a closure that omits its own
# SKILL.md cannot be written.
#
# MEMBERSHIP RULE, and the only one: a file belongs to a closure when the skill
# reads it on EVERY run, with no branch in front of the read. Verified against
# the read directives on 2026-08-10:
#   skills/notices.md         solve-issue step 1.1.1, solve-milestone step 2.1 —
#                             both read it immediately after the profile read,
#                             unconditionally. `setup` and `triage` do not.
#   skills/output-style.md    all four skills' `## Output contract` sections, plus
#                             solve-issue step 6 and triage step 5.
#   skills/citation-format.md all four, though NOT because a SKILL.md
#                             read-directs it: skills/output-style.md
#                             (Citations inside those slots follow one format)
#                             makes it a required onward read of output-style.md
#                             itself, so it is unconditional wherever
#                             output-style.md is. Issue #497 adds the direct
#                             directives; that changes this file's GROUNDING,
#                             not its membership, and no row below moves.
#   skills/solve-issue/version-bump.md
#                             solve-issue step 4 only, and a member of that one
#                             closure. All three modes it selects between
#                             (version-free, fail-safe degradation, versioned)
#                             route INTO the read, so no branch stands in front
#                             of it.
#
# EXCLUDED, and each is excluded for the same reason — an OBSERVABLE branch
# stands in front of the read, so the file is not on every run's load path:
#   skills/solve-milestone/parallel-waves.md          parallel mode only
#                                                     (SKILL.md, Mode branch point)
#   skills/solve-milestone/milestone-granularity.md   loaded whole under
#                                                     integrationGranularity:
#                                                     "milestone" only
#                                                     (SKILL.md, Granularity branch
#                                                     point). A "wave" run reads
#                                                     the anchors
#                                                     integration-granularity.md and
#                                                     solve-issue/wave-clauses.md
#                                                     cite, never the whole file, so
#                                                     the exclusion still holds
#   skills/solve-milestone/trello-sync.md             `integrations.trello` present only
#   skills/solve-issue/async-mode.md                  retired, inert — read on no run
#   skills/solve-issue/md-epic-fanout.md              `md-epic` label only
#   skills/triage/blocker-resolver-dispatch.md        >=1 Blocker gap on a
#                                                     MISS-set issue (issue #506;
#                                                     SKILL.md, Step 3.5)
# They stay GOVERNED as per-file rows above; they are simply not summed here.
# tests/check-size-budgets.test.{sh,ps1}'s excluded-untouched case pins that:
# perturbing all six leaves every CLOSURE line byte-identical.
#
# Milestone #39 split 18 more reference files out of the four SKILL.md files,
# issue #502 added solve-issue/wave-clauses.md beside its milestone twin, and
# issue #516 added solve-milestone/blocked-label-clear.md, and issue #610 added
# solve-milestone/simplify-pass.md. 19 of the 20 that still exist are
# EXCLUDED on the same rule, each verified against its read
# directive — the #39 set on 2026-08-10, wave-clauses.md on 2026-08-12,
# blocked-label-clear.md on 2026-08-18 — with the branch that stands in front
# of the read in brackets:
#   solve-issue/coherence-review.md      [coherenceReviewAgent present AND configured]
#   solve-issue/milestone-clauses.md     [integrationGranularity: "milestone"]
#   solve-issue/wave-clauses.md          [integrationGranularity: "wave"]
#   solve-issue/permission-preflight.md  [background dispatch only; a fully
#                                         synchronous run skips the gate outright]
#   solve-issue/post-fix-commit.md       [>=1 in-scope review finding]
#   solve-issue/preflight-github-ci.md   [the "github-ci" sentinel]
#   solve-issue/resume-paths.md          [a resume, not an inline start]
#   solve-issue/visual-capture.md        [diff matches uiSurfaceGlobs AND visualCapture complete]
#   solve-milestone/abandoned-recovery.md    [non-empty `abandoned` bucket]
#   solve-milestone/blocked-label-clear.md   [(a) held with a non-empty edge set]
#   solve-milestone/changelog-authoring.md   [clean completion, zero parked]
#   solve-milestone/contingencies.md         [a named failure branch]
#   solve-milestone/db-hazard-interview.md   [cascade row 4 only]
#   solve-milestone/integration-granularity.md [non-default integrationGranularity]
#   solve-milestone/md-epic-parent-check.md  [an `md-epic` parent]
#   solve-milestone/not-buildable.md         [a non-buildable issue]
#   solve-milestone/sequential-loop.md       [sequential mode only]
#   solve-milestone/simplify-pass.md         [clean completion; a systemic halt
#                                             skips the pass outright. Verified
#                                             2026-08-26]
#   solve-milestone/version-target.md        [versioning not false]
#
# THE ONE REMAINING, skills/solve-issue/version-bump.md, IS A MEMBER of solve-issue's
# closure and is summed in the row below (decision recorded 2026-08-10). It is
# not branch-gated: solve-issue step 4 selects a mode and then reads the file in
# every one of them, so no branch stands in front of the read. Contrast
# version-target.md, whose directive spells out "Under `versioning: false` it is
# **never read**"; step 4 carries no such clause.
#
# That membership moves solve-issue's closure ceiling 11200 -> 11700, re-derived
# by the standing rule from the corrected sum (10607 + 513 = 11120 words;
# 11120 * 1.05 = 11676, rounded UP to the next 100). It is a re-derivation of a
# ceiling the previous pass computed from an understated sum, not a raise: the
# row was seeded at 15600 when the record was added (#491), and 11700 is still
# well under it. Gating the step-4 read would be a behavior change and is out
# of scope —
# the CLOSURE record exists to make an unconditional load visible.
#
# MUST stay in sync with scripts/check-size-budgets.ps1's $closureTable, row for
# row, the same requirement GOVERNED_TABLE carries. Rows start at column 0; `#`
# starts a comment row; an EMPTY table is legal and simply prints no CLOSURE
# records (the run still exits on the per-file outcome alone).
CLOSURE_SKILLS=()
CLOSURE_CEILINGS=()
CLOSURE_MEMBERS=()
nclosures=0
nclosureceilings=0
while read -r skill closure_ceiling members; do
  case "$skill" in ''|'#'*) continue ;; esac
  CLOSURE_SKILLS[$nclosures]="$skill"
  CLOSURE_MEMBERS[$nclosures]="$members"
  nclosures=$((nclosures + 1))
  case "$closure_ceiling" in ''|*[!0-9]*) ;; *) CLOSURE_CEILINGS[$nclosureceilings]="$closure_ceiling"; nclosureceilings=$((nclosureceilings + 1)) ;; esac
done <<'CLOSURE_TABLE'
skills/setup/SKILL.md              7200   skills/output-style.md skills/citation-format.md
skills/solve-issue/SKILL.md       11600   skills/notices.md skills/output-style.md skills/citation-format.md skills/solve-issue/version-bump.md
skills/solve-milestone/SKILL.md    9200   skills/notices.md skills/output-style.md skills/citation-format.md
skills/triage/SKILL.md             8100   skills/output-style.md skills/citation-format.md
CLOSURE_TABLE

# Same length-parity guard the governed table carries, for the same reason: the
# parse appends a skill unconditionally and its ceiling only when that column is
# present and all digits, so a row whose ceiling was dropped or garbled (most
# plausibly by writing a member path where the ceiling belongs) shows up here as
# unequal counts and refuses to run. A row with NO members is not malformed —
# that is a one-file closure, and its sum is just the SKILL.md.
if [ "$nclosures" -ne "$nclosureceilings" ]; then
  printf 'ERROR check-size-budgets: CLOSURE_SKILLS(%s) and CLOSURE_CEILINGS(%s) length mismatch, fix the closure table\n' \
    "$nclosures" "$nclosureceilings" >&2
  exit 1
fi

# WORDS ARE COUNTED WITH `tr`+`grep`, NOT `wc -w`. `wc -w` is NOT portable for
# this repo's content, which is dense with emoji. GNU coreutils builds its
# single-byte whitespace table as
#     wc_isspace[i] = isspace (i) || maybe_c32isnbspace (btoc32 (i));
# (coreutils src/wc.c) — an extra non-breaking-space clause BSD's wc has no
# equivalent of. MEASURED, on CI run 31426420226: the goldens generated on macOS
# read 488 and 726 words for two fixtures whose only non-ASCII content is a
# single 🔴 sitting alone between two spaces; GNU read 487 and 725, one fewer
# each, because that byte run was a word to BSD and not to GNU. Bytes on disk
# were identical on both legs, so the file was not the variable — the algorithm
# was. That is one CI leg green and the other red on identical content, and it
# would have silently mis-derived every word ceiling depending on which machine
# ran the ratchet.
#
# `tr -s` with explicit OCTAL escapes squeezes runs of exactly the six C
# isspace bytes — space, \t, \n, \v, \f, \r — into newlines, and `grep -c .`
# counts the non-empty lines that remain. Both are POSIX-specified on the byte,
# so the two tr implementations agree where the two wc implementations do not,
# and the result is identical BY CONSTRUCTION to the pwsh twin, which scans its
# already-read byte array for those same six values. Verified against all three
# fixtures: 469 / 488 / 726, unchanged.
#
# ONE function, called by BOTH the per-file word column and the CLOSURE sums, so
# the two can never be measured by different algorithms — a closure is a sum of
# the very numbers the rows above print, not a second count of the same files.
count_words() {
  local n
  n="$(tr -s '\040\011\012\013\014\015' '\n' < "$1" | grep -c .)"
  printf '%s' "${n//[[:space:]]/}"
}

ok=0
failed=0
i=0
while [ "$i" -lt "$nfiles" ]; do
  f="${FILES[$i]}"
  ceiling="${CEILINGS[$i]}"
  byte_ceiling="${BYTE_CEILINGS[$i]}"
  word_ceiling="${WORD_CEILINGS[$i]}"
  path="$ROOT/$f"
  if [ ! -f "$path" ]; then
    printf 'FAIL\t%s\tMISSING/%s\tMISSING/%s\tMISSING/%s\n' "$f" "$ceiling" "$byte_ceiling" "$word_ceiling"
    failed=$((failed + 1))
  else
    actual="$(wc -l < "$path")"
    actual="${actual//[[:space:]]/}"
    # `wc -c` is bytes on disk on every platform (BSD and GNU alike) and needs
    # no locale, matching the pwsh twin's $bytes.Length on the same file.
    actual_bytes="$(wc -c < "$path")"
    actual_bytes="${actual_bytes//[[:space:]]/}"
    # Words through count_words(), the SAME function the CLOSURE sums below
    # call — see its definition above for why `wc -w` is not portable for this
    # content and what `tr`+`grep` counts instead. Routing both callers through
    # one function is what makes a CLOSURE sum a sum of the very numbers this
    # column prints, rather than a second count of the same files by a second
    # algorithm that could drift from it.
    actual_words="$(count_words "$path")"
    if [ "$actual" -gt "$ceiling" ] || [ "$actual_bytes" -gt "$byte_ceiling" ] || [ "$actual_words" -gt "$word_ceiling" ]; then
      printf 'FAIL\t%s\t%s/%s\t%s/%s\t%s/%s\n' "$f" "$actual" "$ceiling" "$actual_bytes" "$byte_ceiling" "$actual_words" "$word_ceiling"
      failed=$((failed + 1))
    else
      printf 'OK\t%s\t%s/%s\t%s/%s\t%s/%s\n' "$f" "$actual" "$ceiling" "$actual_bytes" "$byte_ceiling" "$actual_words" "$word_ceiling"
      ok=$((ok + 1))
      # CRLF-MARGIN ADVISORY (issue #574). A passing file whose byte headroom is
      # smaller than its LINE count passes here and FAILS on a Windows
      # core.autocrlf clone, which reads one extra byte per line: the exact
      # shape the header's CRLF paragraph describes, on a file the contributor
      # never touched. Emitted ONLY after an OK record (a FAIL row is already
      # the louder signal on that file), and it never touches `ok`, `failed` or
      # the exit code. Its position, immediately after the record it annotates,
      # keeps a consumer reading the first field seeing the same OK/FAIL rows in
      # the same order and the same SUMMARY last, the same additive property the
      # CLOSURE records hold. Repay it by trading bytes inside the file, NOT by
      # raising the ceiling.
      byte_headroom=$((byte_ceiling - actual_bytes))
      if [ "$byte_headroom" -lt "$actual" ]; then
        printf 'WARN\t%s\t%s bytes free < %s lines (a CRLF checkout would FAIL this row)\n' "$f" "$byte_headroom" "$actual"
      fi
    fi
  fi
  i=$((i + 1))
done

# One CLOSURE record per closure row, AFTER every per-file record and BEFORE
# the trailing SUMMARY — the position that keeps the record additive (see the
# header). `$skill $members` is UNQUOTED on purpose: the members column is a
# space-separated path list read as one field, and this is the split that turns
# it back into arguments; the skill's own SKILL.md leads because column 1 is the
# first member of its own closure and is never listed in the members column.
#
# NEITHER `ok` NOR `failed` IS TOUCHED HERE, and no exit code is decided here.
# A sum over its ceiling still prints and still exits 0; a member absent from
# disk prints MISSING and still exits on the per-file outcome alone, because
# that member is itself a governed file whose own `FAIL <path> MISSING/...`
# record above already failed the run.
#
# The absence check short-circuits before summing rather than summing what is
# present: a partial sum reads as a real measurement of a closure that cannot be
# measured, and would silently drop under its ceiling exactly when a member was
# deleted. bash-3.2-safe: index-counted while loop, no `declare -A`, no
# `mapfile`.
j=0
while [ "$j" -lt "$nclosures" ]; do
  skill="${CLOSURE_SKILLS[$j]}"
  closure_ceiling="${CLOSURE_CEILINGS[$j]}"
  members="${CLOSURE_MEMBERS[$j]}"
  closure_words=0
  closure_missing=0
  for m in $skill $members; do
    if [ ! -f "$ROOT/$m" ]; then
      closure_missing=1
      break
    fi
    closure_words=$((closure_words + $(count_words "$ROOT/$m")))
  done
  if [ "$closure_missing" -eq 1 ]; then
    printf 'CLOSURE\t%s\tMISSING/%s\n' "$skill" "$closure_ceiling"
  else
    printf 'CLOSURE\t%s\t%s/%s\n' "$skill" "$closure_words" "$closure_ceiling"
  fi
  j=$((j + 1))
done

printf 'SUMMARY\tok=%s\tfailed=%s\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
