# Output style and prose contract — shared reference

This file is the single source of truth for milestone-driver's output
contract. Every skill's `## Output style` section and every agent's
`## Communication style` section points here rather than carrying its own
copy, so that text now exists exactly once and can no longer drift between
the seven files that consume it: `skills/setup/SKILL.md`,
`skills/triage/SKILL.md`, `skills/solve-issue/SKILL.md`,
`skills/solve-milestone/SKILL.md`, `agents/triage-reviewer.md`,
`agents/design-reviewer.md`, and `agents/implementer.md`.

It sits here — a peer of the skill folders, not nested inside any one skill's
own directory — because multiple skills and every agent consume it. That is
the same placement, for the same recorded reason, that `skills/notices.md`
already occupies (`skills/notices.md:10-16`): a reference file with no single
owning skill sits one level up instead.

This is a growing list — a new GitHub-facing shape is added as another row in
`## Evidence slots` below, never restated inline at its call site.

## The surface split — read this first

Two surfaces, two rule sets. Conflating them is the defect this file exists to fix.

| Surface | What it is | Governed by |
|---|---|---|
| **Terminal output** | What a skill prints to the operator's console during a run — run boards, gate lines, dispatch notes. Ephemeral; it scrolls away and **never reaches GitHub**. | `## Terminal output` |
| **GitHub-facing prose** | What this plugin *writes* to GitHub — issue comments, PR bodies, Decision Logs, and CHANGELOG entries that become release bodies. Permanent, public, and read later by a human who was not present for the run. | `## GitHub-facing prose` + `## Evidence slots` |

`## Terminal output` governs terminal output **only**. It is a display rule, not a prose contract: citing it as license to compress a Decision Log, or applying "tables, not inline prose" to a PR body whose content is a rationale, is exactly the conflation this split forbids.

**This plugin authors no issue bodies.** Its GitHub write surfaces are issue comments and PR bodies only — issue authoring belongs to the sibling `milestone-feeder`. Every shape in `## Evidence slots` is one of those two.

## Terminal output

Be concise — report status and outcomes flatly, no wall-of-text. Present steps, gates, lists, and options as **tables**, not inline prose. Mark anything that needs a human with 🔴.

**Skills that carry an `## Output spec`** (`solve-issue`, `solve-milestone`): use the templates in `## Output spec` at their prescribed trigger points. Between boards: one-line dispatch notes only — no narration paragraphs. (`setup` and `triage` carry no `## Output spec`; this paragraph does not apply to them.)

## GitHub-facing prose

These rules govern HOW every GitHub-facing shape reads; `## Evidence slots` governs WHAT each one must contain. Adapted from `milestone-feeder`'s `## Prose style` contract (`agents/issue-author.md:120-131`, v0.12.2) to this plugin's surfaces — comments and PR bodies rather than issue bodies. Padding a comment to sound more confident is the failure mode this section exists to kill: in this pipeline confidence has one currency — the grounding citation — not the word count.

1. **Confidence lives in the citation, not the word count.** A grounded decision is one line plus its ref. Adding prose to make a decision *sound* more certain is a contract violation, the same tier as an ungrounded citation.
2. **Fill the shape's slots — and nothing else.** Each shape in `## Evidence slots` names the slots it must carry. A line that fills no slot is scaffolding; cut it. This is the structural replacement for a length rule: the shape bounds the text, a sentence count never does (see `## The two anti-criteria`).
3. **One decision, one line.** Each Decision Log entry, each recorded gap, and each finding resolution is a single declarative sentence; its citation is the rationale — do not append a second sentence restating it.
4. **No filler vocabulary, no hedges.** Delete on sight: "comprehensive", "robust", "seamless", "leverage", "ensure that", "in order to", "it is important to note". Hedges ("should ideally", "as appropriate") bury the decision — record the decision instead.
5. **Never narrate the template.** Section headers and slot names carry the structure; the text under them carries only facts. Do not explain what a section is for or announce what is about to be listed.
6. **Cut pass before posting.** Re-read the whole body before the `gh issue comment` / `gh pr comment` / PR-body write, and delete every sentence whose removal loses no decision, gate, evidence, or citation.

**Guardrail — concision cuts prose, never content.** Every gate, decision point, degradation branch, and citation stays whole; every literal directive, label name, and issue number stays verbatim. Fewer words, same completeness. A shape that lost a slot is not concise, it is incomplete.

## When prose is the correct form

Structure is the default, not the only legal shape. What the rules above ban is a failure mode — padding, narrating the template, hedge stacks, restating the heading — not paragraphs as such.

Prose is the **correct** form when the content carries dependent clauses a table would fragment:

- **A rationale** — why this and not that, where the "not that" is load-bearing.
- **A tradeoff where the tension is the point** — splitting the two halves into separate cells loses the relationship that made it a tradeoff.
- **A caveat qualifying several rows at once** — a condition belonging to the table as a whole has no cell to live in; it goes in a sentence below it.

When in doubt, ask whether the structure preserves the dependency. If it does not, write the sentence.

## Evidence slots

Every GitHub-facing shape carries an explicit **evidence/citation slot, not just a claim slot**. The rationale is the failure mode compression alone creates: a table cell reading `14 of 15` with nowhere to record what was checked is *more* authoritative-looking than the hedged sentence it replaced, not less. The evidence slot is what makes a bad quantifier visible — a `Scope | all 3 controllers | providers_controller.rb:201` row can be checked; a bare `14 of 15` cannot.

Each shape is defined **once, here**. Its call sites point at this section; they do not restate the slots.

**Openers are parsed downstream — never change them.** `🔴 Parked — `, `🔴 Triage`, and `🔴 Blocked` are matched literally by `skills/solve-milestone/SKILL.md:396` ("A format-matching comment is one whose body opens with…") and probed by `skills/solve-milestone/parallel-waves.md:80`. Every shape below restructures what *follows* its opener; the opener itself is byte-fixed.

| Shape | Opener | Required slots |
|---|---|---|
| **Park comment** (`solve-issue`, `md-epic-fanout`) | `🔴 Parked — ` | **reason** (what blocked it, one line) · **evidence** (the `file:line`, command output, gate name, or parser stderr that shows it) · **what unblocks it** (the decision or artifact a human must supply) |
| **Blocked comment** (dependency hold, `solve-milestone`) | `🔴 Blocked — ` | the same three: **reason** · **evidence** (the unmerged upstream issue numbers) · **what unblocks it** (merge the upstream, remove the `blocked` label, re-run) |
| **STOP/PAUSE reason** (`solve-milestone` park step) | `🔴 Parked — ` | the same three, sourced from the implementer's or `solve-issue`'s own return — confirm all three are present before accepting the existing comment |
| **Decision Log entry** (PR body) | — | **choice** · **rationale** · **citation** (doc URL, `file:line`, or skill — never fabricated) · **rejected alternatives** |
| **`## Code Review` section** (PR body) | — | run + effort · finding count · per-finding resolution · **evidence** (the `file:line` each finding named, or the effort level when the count is 0) · park-trigger list |
| **Triage comment** (`triage`) | `🔴 Triage` | a **structured gap list** — one row per Blocker: lens/type · description · **evidence** · `to_clear`. The closing line stays prose ONLY when it carries something the structure does not (the durable-async-note instruction); otherwise it is cut. |
| **Wave PR body** (`parallel-waves`) | — | the Wave's logic issues · **evidence** (per issue: its branch and the gates it passed on the wave branch) |
| **CHANGELOG entry** (becomes the release body) | — | per bucket, one line per issue · **evidence** (the issue number and its merged PR) · Consumer notes · the ⚖️ judgment-call PR list |
| **👁️ Visual evidence / 🤖 AI pre-filter comments** (PR) | `👁️` / `🤖` | per shot: surface × viewport × appearance · **evidence** (the embedded image and its blob link; for a verdict, the named rendered-layout defect — never a subjective judgment) |
| **`to_clear` field** (both reviewer agents; both `triage` return blocks) | — | the decision or artifact a human must record, plus its **evidence** anchor (`file:line`) when one exists. **Structural constraint, not a word count:** one decision, stated as an instruction a human can act on without reading the rest of the block. A `to_clear` carrying two decisions is two gaps. |

## The two anti-criteria

These bind this file and every consumer of it:

1. **No word or sentence cap on any GitHub-facing shape.** The rule is structural — the shape's slots bound the text. A rule phrased as "reduce to N sentences" is the wrong lever: it cuts content as readily as prose and cannot tell the two apart. A slot definition like `description: <one line>` states one decision per slot; it is not a length cap.
2. **A tradeoff, rationale, or multi-row caveat forced into table cells that fragment it is a defect, not compliance.** Structure that destroys a dependency is worse than the paragraph it replaced (see `## When prose is the correct form`).
