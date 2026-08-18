# Citation format — shared reference

The single source of truth for the citation forms milestone-driver writes —
how a skill, an agent, or a PR body points a later reader at the exact place
that grounds a claim. **Four** forms are in use; the anchor form,
`path (anchor)`, is defined in full here.

## Contents

The four citation forms · The base a citation path resolves from · D1 — the anchor form — What marks a citation · Parse rule · Same-file — write a heading form · D2 — resolution, and the line forms · D3 — an anchor that is not found fails closed

## The four forms

| Form | Points at | Resolved by | Write it when |
|---|---|---|---|
| `path#Heading` | a markdown heading section | `scripts/read-doc-section.{sh,ps1}` — shipped and wired | a tool must fetch the section — the `.project/` anchors an issue cites |
| `path § Heading` | a markdown heading section | nothing; the reader opens the file | prose in a skill or agent body sends a reader to a section |
| `path (anchor)` | any region of any file, keyed to a literal string | `scripts/resolve-citation.{sh,ps1}` — shipped and wired | the target is not a heading — a function, a comment block, a table row, a line of prose, or anything in a non-markdown file |
| `path:line`, `path:start-end` | one line, or a line range, as written | nothing; the reader opens the file | you mean those exact lines, or no form above fits |

**Where a heading exists, a heading form remains the form to write.**
`path#Heading` is resolved by `scripts/read-doc-section.{sh,ps1}`, which fails
loud on a miss; `skills/solve-issue/SKILL.md (Pull a superset via the primitive)`
and `skills/triage/SKILL.md (Pull a superset via the primitive)` invoke that
resolver once per run over the anchors an issue cites. `path § Heading` is the
prose spelling of the same target — one lives at
`skills/solve-milestone/SKILL.md (parallel-waves.md § Parallelizable-set selection)`
and names the heading
`skills/solve-milestone/parallel-waves.md (Parallelizable-set selection (parallel mode))`.

## The base a citation path resolves from

**Every `path`, in all four forms, is relative to the root of the repository
the citation is written in**, and **there is no fallback to any other base**:
not the citing file's own directory, not a walk up the tree.

Nothing rebases the path. `scripts/resolve-citation.{sh,ps1}` and
`scripts/read-doc-section.{sh,ps1}` open `path` exactly as written against the
process working directory, and the skills that invoke them
(`skills/solve-issue/SKILL.md (Resolve each citation once)`,
`skills/triage/SKILL.md (Resolve, then feed BOTH briefs)`) do not change
directory first. A mis-based path fails closed — nonzero exit, nothing on
stdout, the failure named on stderr
(`scripts/resolve-citation.sh (a missing/unreadable file)`) — unless a file
happens to sit at that path relative to the root (a bare filename against a
root-level `README.md`), in which case it opens the wrong file and answers at
exit 0 when the anchor happens to appear there too (otherwise D3 fails closed). From the repository root — a bare `parallel-waves.md` fails (`resolve-citation: file not found or not readable`, exit 1), the full path resolves:

    $ bash scripts/resolve-citation.sh "skills/solve-milestone/parallel-waves.md" "Parallelizable-set selection (parallel mode)"
    PRIMARY	11	### Parallelizable-set selection (parallel mode)
    $ echo $?
    0

For `path § Heading` and the line forms, which nothing resolves, the same base
is where the reader opens the path from.

`skills/solve-issue/SKILL.md (an issue has no directory)` and
`skills/triage/SKILL.md (no multi-base fallback)` state this rule for citations
written inside a GitHub issue body.

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

Unlike the other three forms, `path (anchor)` is not self-delimiting: "a file
name, then a parenthetical aside" is ordinary prose this repo writes often
(one lives at `skills/solve-issue/SKILL.md (settings.local.json)`), and D3
would fail closed on every such phrase read as a citation.

The discriminator is the **code span**: a citation is one whole
backtick-wrapped token — the span opens before the path and closes after the
final `)`.

| Written | Read as |
|---|---|
| `` `skills/solve-issue/SKILL.md (settings.local.json)` `` | a citation — anchor `settings.local.json` |
| `` `skills/solve-issue/SKILL.md` (the settings table) `` | prose — a file name, then an aside |

The span test alone is not sufficient — a `path § Heading` span whose heading
ends in a parenthetical is citation-shaped, and parse rule step 1 keeps it
resolving as a heading citation instead of mis-splitting at the parenthesis.
A citation must also stand in a **citation position**: an **evidence** or
**citation** slot of a shape in `skills/output-style.md (Each shape is defined)`,
or a grounding reference in a skill, an agent, or a PR body. Text failing
either test — span or position — is prose, never resolved.

### Parse rule

A citation is one whole token, on one line, read left to right:

1. **A `#` or a `§` appearing before any ` (` makes it a heading citation.**
   Split on that separator: path before it, heading **everything after it** —
   both trimmed, the heading's own parentheses included. Two live citations
   depend on this: `.project/library-manifest.md#Adding a dependency (the gate)`
   names the heading `Adding a dependency (the gate)`, and
   `skills/solve-milestone/SKILL.md (parallel-waves.md § Parallelizable-set selection)`
   names a real heading the same way. Splitting at the parenthesis instead
   produces a path that does not exist, and D3 fails closed on a correct
   citation.

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
resolved through a language's grammar.

**The citing author picks the anchor** — the *shortest string that uniquely
names the region they mean*:

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
unique as intended (`scripts/read-doc-section.sh (Duplicate anchors)` makes the
same call for a repeated heading).

**`path:line` and `path:start-end` remain fully valid to write.** A citation
carrying no `(anchor)` — `skills/notices.md:9-13` — resolves as the bare line
or lines: no resolution attempted, no error, no warning. Both forms satisfy **every**
evidence and citation slot in `skills/output-style.md (Each shape is defined)`;
**no slot requires an anchor.** Prefer `path (anchor)` when the region you are
citing will outlive the line number it sits on today; an edit above a cited
line invalidates it silently.

## D3 — an anchor that is not found fails closed

An anchor that is **present in the citation but not found in the file** is a
hard failure. The resolver exits **nonzero**, writes **nothing to stdout**, and
writes **the anchor and the file** to stderr.

It does not fall back to the whole file, to a fuzzy match, or to silence.
`scripts/read-doc-section.sh (Fail-loud (fail-CLOSED))` makes the same call for
a missing heading anchor.

This applies only to text that passed D1's citation test. Prose that names a
file and adds a parenthetical aside is never resolved, so it can never trip
this failure.
