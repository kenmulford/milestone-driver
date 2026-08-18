# Remediate handoff — shared reference

The single source of truth for what milestone-driver does with an issue it
parks when the sibling `milestone-feeder` is installed alongside it: the
run-start question, the Auto loop that sends a parked issue through
`/milestone-feeder:remediate`, the attempt cap, and the two branches that park
an issue for good. `skills/solve-issue/SKILL.md` and
`skills/solve-milestone/SKILL.md` read it instead of carrying their own copy,
so the procedure exists exactly once.

It sits here — a peer of the skill folders, not nested inside either skill's
own directory — because two different skills consume it, the placement rule
`skills/notices.md (It sits here — a peer of the skill)` records.

Every read-direct into this file sits behind the feeder-installed gate below,
so it joins no skill's unconditional load closure
(`scripts/check-size-budgets.sh (MEMBERSHIP RULE, and the only one)`).

## The feeder-installed gate

Probe once per run, ahead of the question: is `/milestone-feeder:remediate`
resolvable in this session — the plugin installed, its skill invocable here?

- **Resolvable** → ask the run-start question below.
- **Not resolvable** → **Feeder absent → no question, comment still names the verb as an optional tool, driver degrades silently**. One log line, no error, and no park of its own — the same absent-input skip `skills/triage/blocker-resolver-dispatch.md (The agent is unresolvable)` takes.

The park comment is unchanged either way. It keeps the park-comment shape at
`skills/output-style.md (Park comment)` and the byte-fixed opener
`🔴 Parked — ` (`skills/output-style.md (Openers are parsed downstream)`); with
the feeder absent it names `/milestone-feeder:remediate` as an optional tool
the human may run, and asks for nothing.

## The run-start question

Asked ONCE per run, after the gate passes, verbatim:

```text
Should I send blocked issues through `/milestone-feeder:remediate` automatically, or leave them for you?
```

| Answer | Effect |
|---|---|
| **Auto** | Every issue this run parks enters the loop below. |
| **Leave-them-for-me** | Parking stays exactly what it is today — label, comment, continue. The loop never runs and no issue body is edited. |

**A non-interactive/unattended `solve-milestone` run defaults to Leave-them-for-me - a question nobody can answer must not block the run.** Hold the answer for the whole run; never re-ask per issue.

## The Auto loop

Per parked issue `<n>`, in order:

| Step | Action |
|---|---|
| 1 | Read that issue's `🔴 Triage` comment — the findings `remediate` corrects against. **No such comment → skip this issue**: one log line, no error, nothing edited. |
| 2 | Invoke `/milestone-feeder:remediate <n>`. |
| 3 | **re-run triage on the corrected body, and clear the park label when the re-triage comes back clean** — `gh issue edit <n> --remove-label "needs design"`, or `"needs decision"`; never a label the issue does not carry (`skills/triage/blocker-resolver-dispatch.md (Unparking)`). |
| 4 | Replace the held `issueStates["<n>"]` entry with the clean re-triage's result, so buildability condition (c) passes on that pass (`skills/solve-milestone/SKILL.md (Apply triage-recommended park labels)`). |

**Attempt cap: 1 per issue per run.** An issue that parks a second time in the
same run re-enters no loop and gets no second remediation.

Step 3's re-triage is a genuine cache MISS, not a stale replay: `remediate`
edits the issue body, and that moves `lastEditedAt`, a live-key field
(`scripts/triage-cache.sh (lastEditedAt createdAt comments)`).

## Invocation

Run every step above **on this main line, in-thread, never as a dispatched agent** (`skills/solve-milestone/sequential-loop.md (on this main line, in-thread, never as a dispatched agent)`, `docs/architecture.md` → `## Dispatch topology`). `/milestone-feeder:remediate` dispatches the feeder's remediator agent itself; inside a dispatched caller that agent sits at depth 2, where its completion notification never arrives.

## Park for good

Two branches end the loop for an issue, both leaving its ONE park label intact:

| Branch | Effect |
|---|---|
| `remediate` returns `NEEDS_HUMAN` | The findings need a decision no record answers. |
| The re-triage still comes back dirty | The corrected body did not clear its Blockers. |

The **driver** posts the stop reason, never `remediate` — in the park-comment
shape at `skills/output-style.md (Park comment)`, opener `🔴 Parked — `
byte-unchanged, its evidence slot carrying the `NEEDS_HUMAN` line or the
surviving Blocker, and its unblocks slot the decision a human must record. The
run then continues with independent clean issues.
