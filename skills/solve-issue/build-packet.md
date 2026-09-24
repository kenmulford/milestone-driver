## Build packet contract

The build packet is the file an implementer builds one issue from. One packet per issue.

### Path

`.milestone-config/.runtime/plans/issue-<n>.md`, inside the `.runtime/` rule of the committed `.milestone-config/.gitignore`. It sits beside `.milestone-config/.runtime/plans/common.md`, which `scripts/assemble-common.sh (Writes <out-file> holding, in order)` writes once per run.

### Header

The first three lines, in this order:

```
Issue: #<n>
Base: <sha>
Worktree: <absolute path>
```

`Base:` is the worktree HEAD the planner read (`git -C <worktree> rev-parse HEAD`). Every quote in the packet is copied from the file at `Base`.

### Sections

After the header, these `##` sections, in this order:

| Section | Contents |
|---|---|
| `## Files` | Table: path, then `edit` or `new`. This is the issue's expected file scope. |
| `## Edit points` | Per changed symbol: quoted current lines and anchor, then the target signature and one intent line, no bodies. A new file: path and public signatures only. |
| `## Calls` | Every existing symbol the new code calls or conforms to: its declaration quoted from `Base` under a `path (anchor)` heading. |
| `## Tests` | Per test, its file, name, one assertion, and the quoted declaration of each helper or fixture it uses. No test code. |
| `## Design` | Each design-source section the issue cites, quoted. Copy strings are byte-exact. |
| `## Rules` | Each `.project/` section the change depends on that `common.md` does not carry, quoted under its `<doc>#<heading>`. |
| `## Verified facts` | Each framework or platform fact the change depends on, with its source: a docs URL for the version in use, a `domainSkills` name, or a probe's printed output. |
| `## Decisions` | One line per choice the implementer otherwise makes, in the Decision Log entry shape at `skills/output-style.md#Evidence slots`. Restates none of its slots. |
| `## Verify` | Exact commands, plus any command needed to produce a file, run by the implementer, never the planner. |
| `## Out of scope` | What the implementer does not touch. |

### Omission

- Required: `## Files`, `## Edit points`, `## Tests` (`risk:light` omits it), `## Verify`, `## Out of scope`. An empty required section holds one line: `none`.
- Optional: `## Calls`, `## Design`, `## Rules`, `## Verified facts`, `## Decisions`, omitted entirely when empty.
- Maximum packet size: 12288 bytes.

### Section rules

- `## Rules` quotes only the `.project/` sections that `.milestone-config/.runtime/plans/common.md` does not already carry. A section already in `common.md` is never repeated.
- `## Decisions` uses the Decision Log entry shape at `skills/output-style.md#Evidence slots`.
- Every quoted declaration sits under a `### <path> (<anchor>)` heading in the anchor form at `skills/citation-format.md#The four forms`, so it resolves through `scripts/resolve-citation.sh` and `scripts/resolve-citation.ps1` against `Base`.
- A new file sits under `### <path> (new)`, its public signatures beneath; approval skips it.
- Approval is `scripts/check-packet.sh` and `scripts/check-packet.ps1`, which read only lines outside fenced blocks.
- A quote is a fenced block copied byte-exact from its file at `Base`.
