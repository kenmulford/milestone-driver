## Blocker resolution before the park

The branch that reaches this file belongs to the caller, which reads it only for a **MISS-set issue carrying at least one `severity: Blocker` gap** (`skills/triage/SKILL.md (### Step 3.5 — Resolve Blockers before they park)`).

### The dispatch

- **Agent resolution.** `blockerResolverAgent` is a **default-filled** Core key defaulting to `milestone-driver:blocker-resolver` — the same default-fill pattern as `triageAgent` and `designReviewAgent` (`docs/profile-schema.md (Which agent decides whether a triage Blocker)`).
- **One dispatch per issue, never one per gap.** Every Blocker gap on that issue rides in a single brief, and the agent returns one verdict per gap.
- **Concurrent across issues.** Dispatch the qualifying issues in parallel when the tool environment supports it, exactly as Step 3 does.

**Brief the agent with** that issue's `triageAgent` brief, verbatim and already composed in Step 3 — **plus** every gap that agent returned at `severity: Blocker`, each with its `lens`, `type`, `description`, and `to_clear`. Resolve nothing a second time here; Step 3's resolutions are reused as they stand. **The brief MUST also carry the same scratch-hygiene rule as the Step 3 briefs.**

### The agent returns

```
ISSUE: <n>
DOMAIN_SKILLS_INVOKED: <comma-separated exact names> | none
RESOLUTIONS:
  - gap: <the Blocker's `description` line, verbatim>
    verdict: RESOLVED | NEEDS_HUMAN
    resolution: <one line>
    evidence: <citation, recorded line, sibling issue number, or command output — REQUIRED for RESOLVED>
    edit: <the exact edit a builder applies — RESOLVED only>
  - …
```

`RESOLVED` is that agent's default; `NEEDS_HUMAN` is the exception (`agents/blocker-resolver.md (## The verdict rule)`).

### Per-verdict handling, applied before Step 4 aggregates

| Return | Effect |
|---|---|
| `RESOLVED` with a filled `evidence` slot | Drop that Blocker from the issue's gap set; carry its `resolution`, `evidence`, and `edit` to Step 6. |
| `RESOLVED` whose `evidence` slot is empty, **or carries nothing from the admissible evidence set** (`agents/blocker-resolver.md (## Rigor gate)`) — a restatement of the `resolution` line included | Treat as `NEEDS_HUMAN` — an unsourced resolution is a guess. |
| `NEEDS_HUMAN` | Keep the Blocker exactly as the `triageAgent` returned it. |
| A Blocker the return omits | Treat as `NEEDS_HUMAN`. Silence is not a resolution. |

An issue whose Blockers are **all** dropped reaches Step 4 carrying no Blocker gap and aggregates to `issueStates[n].blockers == false`, `label: null` — unparked. An issue with at least one survivor parks on the survivors alone. Advisory gaps pass through untouched: they never gate, so this pass neither reads nor resolves them.

Step 6 posts the outcome — one `🟢 Resolved` comment per issue with at least one dropped Blocker, in the shape at `skills/output-style.md (Resolved comment)` and carrying the return's `DOMAIN_SKILLS_INVOKED` on its own line (**ungated**: `none` never blocks, parks, or fails anything), and a `🔴 Triage` comment covering the survivors only.

### Unparking

An issue this pass unparks returns `clearLabel: true` (every other issue, HIT included, `false`), and the caller removes the ONE park label the issue live-carries — `gh issue edit <n> --remove-label "needs design"`, or `"needs decision"`; never a label it does not carry. Otherwise `skills/solve-milestone/SKILL.md (no blocker label)` still refuses to build it. Triage applies and removes nothing itself.

That `🟢 Resolved` comment closes on the same instruction, naming the label — on a standalone run the human is the caller. Post it only when **no prior comment on the issue opens with `🟢 Resolved`** — key the guard on the opener, never on body equality, because run N+1's resolver reads run N's comment (`agents/blocker-resolver.md (Every recorded comment on the issue)`), so the bodies diverge and a byte-identical test would let the comment accrete forever. Accepted with the dedup — a re-resolve landing `NEEDS_HUMAN` re-parks an issue cleared last run, and a later run's newly-dropped Blocker posts no second comment; the unpark itself rides `clearLabel`, not the comment.

### Degradation (no error, ever)

- **`blockerResolverAgent` absent from the profile** → the bundled default applies and nothing degrades.
- **The agent is unresolvable** — not installed, or not dispatchable in this session → **skip the pass**: every Blocker survives and parks exactly as it does today, one log line, no error, and no park of its own.
- **A dispatch fails, or returns a block that cannot be parsed** → the same skip, scoped to that one issue.

Resolution text is **never cached**. Step 6.5 stores the post-resolution `blockers` value and nothing else from this step, so an invalidated entry re-resolves from scratch instead of replaying a stale verdict.
