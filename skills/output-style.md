# Output style and prose contract - shared reference

The single source of truth for milestone-driver's output contract. Every skill's
`## Output style` section and every agent's `## Communication style` section points
here.

It sits one level up from the skill folders, for the same recorded reason as
`skills/notices.md (It sits here - a peer of the skill)`: a reference file with no
single owning skill is not nested inside any one skill's directory.

## The surface split - read this first

| Surface | What it is | Governed by |
|---|---|---|
| **Terminal output** | What a skill prints to the operator's console during a run - run boards, gate lines, dispatch notes. Ephemeral; it scrolls away and **never reaches GitHub**. | `## Terminal output` |
| **GitHub-facing prose** | What this plugin *writes* to GitHub - issue comments, PR bodies, Decision Logs, and CHANGELOG entries that become release bodies. Permanent, public, and read later by a human who was not present for the run. | `## GitHub-facing prose` + `## Evidence slots` |

`## Terminal output` governs terminal output **only** - a display rule, not a prose contract: citing it as license to compress a Decision Log, or applying "tables, not inline prose" to a PR body whose content is a rationale, is the conflation this split forbids.

**This plugin authors no issue bodies.** Its GitHub write surfaces are issue comments and PR bodies only - issue authoring belongs to the sibling `milestone-feeder`, and every shape in `## Evidence slots` is one of those two.

## Terminal output

Be concise - report status and outcomes flatly. Present steps, gates, lists, and options as **tables**, not inline prose. Mark anything that needs a human with 🔴.

**Skills that carry an `## Output spec`** (`solve-issue`, `solve-milestone`): use those templates at their prescribed trigger points. Between boards: one-line dispatch notes only, no narration paragraphs. (`setup` and `triage` carry none.)

## GitHub-facing prose

These rules govern HOW every GitHub-facing shape reads; `## Evidence slots` governs WHAT each one must contain.

1. **One decision, one line - the citation is the rationale.** Each Decision Log entry, recorded gap, and finding resolution is a single declarative sentence; never append a second sentence restating its citation. Confidence lives in the citation, not the word count: adding prose to make a decision *sound* more certain is a contract violation, the same tier as an ungrounded citation.
2. **Fill the shape's slots - and nothing else.** Each shape in `## Evidence slots` names the slots it must carry; a line that fills no slot is scaffolding, so cut it (see `## The two anti-criteria`). That includes narrating the template - section headers and slot names carry the structure, so never explain what a section is for or announce what is about to be listed. **Cut pass before posting:** re-read the whole body before the `gh issue comment` / `gh pr comment` / PR-body write, and delete every sentence whose removal loses no decision, gate, evidence, or citation.
3. **No filler vocabulary, no hedges.** Delete on sight: "comprehensive", "robust", "seamless", "leverage", "ensure that", "in order to", "it is important to note". Hedges ("should ideally", "as appropriate") bury the decision - record the decision instead.

**Guardrail - concision cuts prose, never content.** Every gate, decision point, degradation branch, and citation stays whole; every literal directive, label name, and issue number stays verbatim. A shape that lost a slot is not concise, it is incomplete.

## When prose is the correct form

Structure is the default, not the only legal shape. Prose is the **correct** form when the content carries dependent clauses a table would fragment:

- **A rationale** - why this and not that, where the "not that" is load-bearing.
- **A tradeoff where the tension is the point** - splitting the halves into separate cells loses the relationship that made it a tradeoff.
- **A caveat qualifying several rows at once** - a condition belonging to the table as a whole has no cell to live in; it goes in a sentence below it.

When in doubt, ask whether the structure preserves the dependency; if not, write the sentence.

## Evidence slots

Every GitHub-facing shape carries an explicit **evidence/citation slot, not just a claim slot** - what makes a bad quantifier visible: a `Scope | all 3 controllers | providers_controller.rb:201` row can be checked; a bare `14 of 15` cannot.

Each shape is defined **once, here**. Its call sites point at this section; they do not restate the slots. Citations inside those slots follow one format, defined once in the citation-format file, `${CLAUDE_PLUGIN_ROOT}/skills/citation-format.md`, handed to every agent bar the coherence leaf as `citationFormatPath`.

**Openers are parsed downstream - never change them.** `🔴 Parked - `, `🔴 Triage`, and `🔴 Blocked` are matched literally by `skills/solve-milestone/SKILL.md (Issues parked)` ("A format-matching comment is one whose body opens with…") and probed by `skills/solve-milestone/parallel-waves.md (the probe found a park label)`. Every shape below restructures what *follows* its opener; the opener itself is byte-fixed.

| Shape | Opener | Required slots |
|---|---|---|
| **Park comment** (`solve-issue`, `md-epic-fanout`) | `🔴 Parked - ` | **reason** (what blocked it, one line) · **evidence** (the citation per `citationFormatPath`, command output, gate name, or parser stderr that shows it) · **what unblocks it** (the decision or artifact a human must supply) |
| **Blocked comment** (dependency hold, `solve-milestone`) | `🔴 Blocked - ` | the same three: **reason** · **evidence** (the unmerged upstream issue numbers) · **what unblocks it** (merge the upstream, re-run; the `blocked` label self-clears) |
| **STOP/PAUSE reason** (`solve-milestone` park step) | `🔴 Parked - ` | the same three, sourced from the implementer's or `solve-issue`'s own return - confirm all three are present before accepting the existing comment |
| **Decision Log entry** (PR body) | - | **choice** · **rationale** · **citation** (doc URL, repo ref per `citationFormatPath`, or skill - never fabricated) · **rejected alternatives** |
| **`## Code Review` section** (PR body) | - | run + effort · finding count · per-finding resolution · **evidence** (each finding's ref per `citationFormatPath`, or the effort level when the count is 0) · park-trigger list |
| **Triage comment** (`triage`) | `🔴 Triage` | a **structured gap list** - one row per Blocker: lens/type · description · **evidence** · `to_clear`. The closing line stays prose ONLY when it carries something the structure does not (the durable-async-note instruction); otherwise it is cut. |
| **Wave PR body** (`parallel-waves`) | - | the Wave's built-green issues, UI included · **evidence** (per issue: its branch and the gates it passed on the wave branch) · **exactly one** anchored `## Code Review` heading, one `### #<n>` sub-entry per issue, a one-issue Wave included, no special case (`skills/solve-milestone/milestone-granularity.md (aggregates these blocks under)`) |
| **CHANGELOG entry** (becomes the release body) | - | **theme** (one line - the release's net behavior change) · per bucket, one line per issue · **evidence** (the issue number and its merged PR) · **Consumer notes** (only what changes what a consumer types, configures, or must expect) · **⚖️ audit trail** (the judgment-call PR list, plus a fact list: open defects with their issue numbers, any dropped acceptance criterion as what the shipped gate does NOT verify, and any ceiling or budget state the next edit hits). **Not slots here:** how the work went (review rounds, RED-first discovery, provenance), the release's own justification, and editing history. |
| **👁️ Visual evidence comment** (PR) | `👁️` | per shot: surface × viewport × appearance · **evidence** (the embedded image and its blob link) |
| **Resolved comment** (`triage`) | `🟢 Resolved` | one row per resolved Blocker: **original gap** · **resolution** · **evidence** · **the edit a builder applies**; closes on **the park label to clear** |
| **`to_clear` field** (both reviewer agents; both `triage` return blocks) | - | the decision or artifact a human must record, plus its **evidence** reference (per `citationFormatPath`) when one exists. **Structural constraint, not a word count:** one decision, stated as an instruction a human can act on without reading the rest of the block. A `to_clear` carrying two decisions is two gaps. |

## The two anti-criteria

These bind this file and every consumer of it:

1. **No word or sentence cap on any GitHub-facing shape.** The rule is structural - the shape's slots bound the text. A rule phrased as "reduce to N sentences" is the wrong lever: it cuts content as readily as prose and cannot tell the two apart. A slot definition like `description: <one line>` states one decision per slot; it is not a length cap.
2. **A tradeoff, rationale, or multi-row caveat forced into table cells that fragment it is a defect, not compliance.** Structure that destroys a dependency is worse than the paragraph it replaced (see `## When prose is the correct form`).
