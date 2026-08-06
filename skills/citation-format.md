# Citation format — shared reference

This file is the single source of truth for the citation forms milestone-driver
writes — how a skill, an agent, or a PR body points a later reader at the exact
place that grounds a claim. **Four** forms are in use. This file names all
four, says when each applies, and defines the newest of them, `path (anchor)`,
in full.

It sits here — a peer of the skill folders — because every skill and every
agent cites something, and a reference file with no single owning skill sits
one level up (`skills/notices.md (sits one level up)`).
`skills/output-style.md (Each shape is defined)` points here rather than
restating the format at each of its evidence slots.

The defect `path (anchor)` removes: a citation pinned to a line number is
invalidated by any edit above that line — silently. Nothing warns, the citation
still looks well-formed, and it sends its reader to the wrong place.

## The four forms

| Form | Points at | Resolved by | Write it when |
|---|---|---|---|
| `path#Heading` | a markdown heading section | `scripts/read-doc-section.{sh,ps1}` — shipped and wired | a tool must fetch the section — the `.project/` anchors an issue cites |
| `path § Heading` | a markdown heading section | nothing; the reader opens the file | prose in a skill or agent body sends a reader to a section |
| `path (anchor)` | any region of any file, keyed to a literal string | `scripts/resolve-citation.{sh,ps1}` — shipped and wired | the target is not a heading — a function, a comment block, a table row, a line of prose, or anything in a non-markdown file |
| `path:line`, `path:start-end` | one line, or a line range, as written | nothing; the reader opens the file | you mean those exact lines, or no form above fits |

**Both heading forms are untouched by this file.** `path#Heading` is live and
load-bearing: `scripts/read-doc-section.{sh,ps1}` resolves it and fails loud on
a miss, and `skills/solve-issue/SKILL.md (Pull a superset via the primitive)`
and `skills/triage/SKILL.md (Pull a superset via the primitive)` invoke that
resolver once per run over the anchors an issue cites — for example
`.project/conventions.md#Naming`. `path § Heading` is the prose spelling of the
same target, used throughout `skills/` and `agents/`; one lives at
`skills/solve-milestone/SKILL.md (parallel-waves.md § Parallelizable-set selection)`
and names the heading
`skills/solve-milestone/parallel-waves.md (Parallelizable-set selection (parallel mode))`.
`path (anchor)` does not replace, narrow, or compete with either — **where a
heading exists, a heading form remains the form to write.**

## D1 — the `path (anchor)` form

A citation in this form is `path (anchor)`:

    ITrelloClient.cs (AddCardLabelAsync)

- `path` — the path to the file.
- `anchor` — a literal string that appears in that file.
- **When you write this form, no line number and no line range is ever
  included** — not instead of the anchor, not alongside it. `path (anchor)` and
  the line forms are separate forms; a citation is one or the other, never a
  hybrid of both. This bans the mixture, not the line forms — D2 records that
  `path:line` and `path:start-end` remain fully valid to write.

### What marks it as a citation

Unlike the other three forms, `path (anchor)` is not self-delimiting. "A file
name, then a parenthetical aside" is ordinary prose this repo writes often —
`.claude/settings.local.json` (project local), at
`skills/solve-issue/SKILL.md (settings.local.json)`, is one — and read
carelessly every such phrase is a valid citation whose anchor is absent from
the file it names. D3 would fail closed on all of them.

The discriminator is the **code span**. A citation is one whole
backtick-wrapped token: the span opens before the path and closes after the
final `)`.

| Written | Read as |
|---|---|
| `` `skills/solve-issue/SKILL.md (settings.local.json)` `` | a citation — anchor `settings.local.json` |
| `` `skills/solve-issue/SKILL.md` (the settings table) `` | prose — a file name, then an aside |

The span test alone is not sufficient. A `path § Heading` reference whose
heading ends in a parenthetical is one whole span and is citation-shaped; parse
rule step 1 is what keeps those resolving as heading citations instead of
mis-splitting at the parenthesis.

A citation must also stand in a **citation position**: an **evidence** or
**citation** slot of a shape in `skills/output-style.md (Each shape is defined)`,
or a grounding reference in a skill, an agent, or a PR body. Text that fails
either test — the span or the position — is prose, and is never resolved.

### Parse rule

A citation is one whole token, on one line, read left to right:

1. **A `#` or a `§` appearing before any ` (` makes it a heading citation.**
   Split on that separator: the path is the text before it, the heading is
   **everything after it** — both trimmed, the heading's own parentheses
   included. Two live citations depend on this, both ending in a parenthetical:
   `.project/library-manifest.md#Adding a dependency (the gate)` names the
   heading `Adding a dependency (the gate)`, which
   `scripts/read-doc-section.sh` resolves today; the `§` reference at
   `skills/solve-milestone/SKILL.md (parallel-waves.md § Parallelizable-set selection)`
   names a real heading the same way. Split at the parenthesis instead of the
   separator and both produce a path that does not exist, so D3 would fail
   closed on a citation that is correct:

       .project/library-manifest.md#Adding a dependency  + anchor "the gate"
       …/parallel-waves.md § Parallelizable-set selection + anchor "parallel mode"

2. **Otherwise the path ends at the first ` (`** — a space followed by an open
   parenthesis. The anchor is the text between that `(` and the **final `)`**
   of the token, exclusive of both. The anchor may contain its own
   parentheses: `scripts/read-doc-section.sh (Fail-loud (fail-CLOSED))` carries
   the anchor `Fail-loud (fail-CLOSED)`.
3. **A path containing ` (` cannot be cited in the anchor form or in either
   heading form.** Step 1 keys off a separator standing *before* the first
   ` (`, so `docs/my notes (draft).md#Section` never reaches it and step 2
   mis-splits. There is no escape syntax: write `path:line` or
   `path:start-end` for that file instead.

### Same-file — write a heading form

A citation **in the file it points at** reproduces its own anchor, so the citing
line is itself an occurrence. Above its target it becomes the `PRIMARY` and the
citation resolves to itself, at exit 0, with no error. **Never write the anchor
form at a same-file citation.** Write a heading form: `read-doc-section.sh`
matches an ATX heading whose text equals the anchor exactly, and a citing line
is not a heading, so it cannot collide. If the target has no heading, add one.

## D2 — resolution, and the line forms

**Resolution is a literal string search, and nothing else.** The anchor is
matched as raw text — never parsed as a symbol, never read as a regex, never
resolved through a language's grammar. There is no language awareness to lean
on: this plugin's one symbol extractor,
`scripts/build-file-index.sh (extract_symbols() {)`, is hardcoded to the bash
shape `name() {` and the pwsh shape `function Name`, and does not generalize to
the C#, Ruby, TypeScript, and Python repos that consume this plugin.

**The citing author picks the anchor** — the *shortest string that uniquely
names the region they mean*. Uniqueness is the author's job because only the
author knows which occurrence is the one worth reading:

| Anchor | What it matches |
|---|---|
| `AddCardLabelAsync` | the declaration **and every call site** |
| `Task<bool> AddCardLabelAsync` | the declaration, and only the declaration |

The second is the citation to write. The same test run against this repo:
`extract_symbols` matches 3 places in `scripts/build-file-index.sh`,
`extract_symbols() {` matches 1.

**When an anchor matches more than once**, resolution still succeeds: the
**first occurrence in file order is the primary**, and **every further
occurrence is also reported**, so the author can see the anchor was not as
unique as intended. This follows the precedent already set for a repeated
heading, `scripts/read-doc-section.sh (Duplicate anchors)`, and extends it with
the report of the extras.

**`path:line` and `path:start-end` are forms you may write today — not a legacy
tolerance.** A citation carrying no `(anchor)` — `skills/solve-issue/SKILL.md:249`,
or a range like `skills/notices.md:10-16` — resolves exactly as it does now:
the bare line or lines, no resolution attempted, no error, and no warning. Both
satisfy **every** evidence and citation slot in
`skills/output-style.md (Each shape is defined)`; **no slot requires an anchor,
and none is being changed to require one.** Nothing already written needs
migrating, and a newly written line or range citation is correct, not a lapse.

Prefer `path (anchor)` when the region you are citing will outlive the line
number it happens to sit on today — that drift is the whole reason the form
exists. That is a reason to choose the anchor, not a rule demanding it.

## D3 — an anchor that is not found fails closed

An anchor that is **present in the citation but not found in the file** is a
hard failure. The resolver exits **nonzero**, writes **nothing to stdout**, and
writes **the anchor and the file** to stderr.

It does not fall back to the whole file, to a fuzzy match, or to silence. A
stale anchor is the drift this form exists to surface, so surfacing it loudly
is the point. `scripts/read-doc-section.sh (Fail-loud (fail-CLOSED))` already
makes the same call for a missing heading anchor, and records it there as a
deliberate divergence from `extract-version.sh`, which fails open on a version
miss.

This applies only to text that passed D1's citation test. Prose that names a
file and adds a parenthetical aside is never resolved, so it can never trip
this failure.
