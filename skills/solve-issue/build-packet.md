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
| `## Edit points` | Per file: each symbol that changes, under a `path (anchor)` heading, its current code quoted from `Base`, then the code it becomes. A new file: its path and its full declarations. |
| `## Calls` | Every existing symbol the new code calls or conforms to: its declaration quoted from `Base` under a `path (anchor)` heading. |
| `## Tests` | Every test as code in its named file, plus the declaration of each test helper and fixture it uses, quoted from `Base`. |
| `## Design` | Each design-source section the issue cites, quoted. Copy strings are byte-exact. |
| `## Rules` | Each `.project/` section the change depends on that `common.md` does not carry, quoted under its `<doc>#<heading>`. |
| `## Verified facts` | Each framework or platform fact the change depends on, with its source: a docs URL for the version in use, a `domainSkills` name, or a probe's printed output. |
| `## Decisions` | Decision Log entries, one per line: choice · rationale · citation · rejected alternatives. |
| `## Verify` | The exact commands, with absolute paths. |
| `## Out of scope` | What the implementer does not touch. |

### Omission

- `## Tests` is omitted when the implementer's `risk:light` clause applies (`agents/implementer.md (skip the red→green ceremony)`).
- `## Design` is omitted when the issue cites no design source.
- Every other section is required. A required section with nothing to carry holds the single line `none`.

### Section rules

- `## Rules` quotes only the `.project/` sections that `.milestone-config/.runtime/plans/common.md` does not already carry. A section already in `common.md` is never repeated.
- `## Decisions` uses the Decision Log entry shape at `skills/output-style.md#Evidence slots`.
- Every quoted declaration sits under a `### <path> (<anchor>)` heading in the anchor form at `skills/citation-format.md#The four forms`, so it resolves through `scripts/resolve-citation.sh` and `scripts/resolve-citation.ps1` against `Base`.
- A quote is a fenced block copied byte-exact from its file at `Base`.
