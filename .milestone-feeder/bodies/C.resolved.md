## Summary
In skills/solve-issue, before "### 3. Dispatch the implementer" (SKILL.md:98-99), add a resolve-once step: parse which `.project/<doc>#<section>` anchors the issue cites (from the issue body + acceptance criteria), pull a SUPERSET of plausibly-relevant sections via the #184 read-doc-section primitive, and add those sections to the implementer dispatch brief. The implementer never re-reads whole files — sections are pre-resolved once in the orchestrator, so grounding tokens scale with cited-section size. projectDocs (added by #183, default `.project/`) names the directory; resolution happens at SKILL.md:14.

## Acceptance criteria
- [ ] Before the implementer dispatch (skills/solve-issue/SKILL.md:98-99), the orchestrator resolves the `.project/<doc>#<section>` anchors cited in the issue body + acceptance criteria.
- [ ] It pulls a SUPERSET of plausibly-relevant sections via scripts/read-doc-section.sh (the #184 primitive) — resolved ONCE, not per-subagent.
- [ ] The resolved sections are added to the implementer dispatch brief (the "colleague walking in cold" brief at SKILL.md:99).
- [ ] The implementer does NOT re-read whole files — pre-resolved sections are supplied.
- [ ] Absent `.project/` directory -> resolve-once is a no-op; the dispatch proceeds with no grounding and NO error (graceful degrade).
- [ ] A missing/renamed cited anchor surfaces via the #184 primitive's loud (non-zero) failure — not silent empty grounding.
- [ ] Additive: no existing solve-issue step, gate, or the implementer contract changes beyond adding the resolved-sections input to the brief.

## Design (recorded, consistent)
- Edit point: skills/solve-issue/SKILL.md, immediately before "### 3. Dispatch the implementer" (SKILL.md:98-99). projectDocs resolves at SKILL.md:14 (added by #183).
- Calls scripts/read-doc-section.sh / .ps1 (the #184 primitive) for each cited anchor; pulls a superset (plausibly-relevant sibling sections) to avoid under-grounding (the recorded mitigation: efficiency-grounding-plan.md:83 "under-retrieval is the real risk — mitigate with a superset").
- Convention followed: extends the existing dispatch-brief assembly at SKILL.md:98-99; mirrors how the brief already carries the issue/plan/profile/file-scope.
- Degrade: absent projectDocs -> default `.project/`; absent `.project/` dir -> no-op, no error.

## Dependencies
- Depends on #184 — calls the read-doc-section primitive scripts/read-doc-section.sh introduced by #184
- Depends on #183 — references projectDocs (default .project/), introduced by #183 at SKILL.md:14 (soft edge; the `.project/` default makes it non-blocking, Wave order already places #183 in Wave 1 ahead of #185 in Wave 2 — recorded for completeness per the self-check Advisory)

## Classification
- Surface: logic ; Risk: heavy

> Self-check Advisory notes (not Blockers): (1) the #183 projectDocs edge was implicit in the original body; now recorded above (Wave order unaffected). (2) "SUPERSET of plausibly-relevant sections" is a recorded heuristic — bias toward over-inclusion of sibling sections + on-demand Read (the plan's recorded convention, efficiency-grounding-plan.md:46-47, :83); no novel decision required.
