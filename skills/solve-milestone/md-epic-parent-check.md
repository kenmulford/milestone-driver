# md-epic parent check: solve-milestone reference

Loaded by solve-milestone's Before-starting step 3.6 **only when that step's parent lookup found a parent issue carrying the `md-epic` label** — a milestone that is one ordered slice of a feature spanning several milestones (`docs/superpowers/specs/2026-07-04-md-epic-driver-fanout-design.md`). No parent, a parent without the label, or a `--driven` run never reaches this file. Missing or unreadable at that point is a **systemic failure**: surface it and halt the run per core `SKILL.md`'s `## Autonomy` → "Systemic failures that halt the run".

---

Prompt the human with exactly three options:

```text
🔴 Milestone "<resolved-title>" belongs to parent issue #<parent-number>, which spans
   multiple milestones in a defined build order. Building just this milestone builds
   only one slice of that feature.
   [Build just this milestone] · [Hand off to solve-issue #<parent-number> — drive the
   whole parent in build order] · [Pause for clarification]
```

- **Build just this milestone** → fall through to core `SKILL.md`'s Before-starting step 4 / step 5 / Phase 0 exactly as the no-prompt branch does.
- **Hand off** → invoke `/milestone-driver:solve-issue <parent-number>` directly (the skill-invokes-skill pattern this skill already uses for `/milestone-driver:triage`) and **stop this run's Before-starting sequence here** — no clean-tree check, no execution-mode resolution, no Phase 0 triage for this milestone under this invocation.
- **Pause for clarification** → halt immediately. No build, no hand-off, no state change.

**Out-of-order safety is reactive only.** If the human builds just this milestone and one of its issues depends on unmerged work from an earlier, not-yet-built milestone in the same parent group, that is not caught proactively: triage's `dependencyGraph` is scoped to this milestone's own issues and has no edge into another milestone. It surfaces through whatever build-time signal it trips (the root-cause gate, a red suite, an implementer-declared architecture conflict), and the dependency-hold comment (`skills/solve-milestone/not-buildable.md (Dependency not yet merged)`) has no cross-milestone upstream to name — expect a less specific park reason.
