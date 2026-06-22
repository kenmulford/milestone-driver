## Summary
In skills/triage, before the Step 3 triage-reviewer dispatch (SKILL.md:132) and the design-reviewer dispatch (SKILL.md:158), add a resolve-once step: parse the `.project/<doc>#<section>` anchors the issue cites (body + acceptance criteria), pull a SUPERSET of plausibly-relevant sections via the #B read-doc-section primitive, and add those sections to BOTH the triage-reviewer and design-reviewer dispatch briefs. Reviewers never re-read whole files. projectDocs (added by #A, default `.project/`) resolves at SKILL.md:27; the resolved sections join the existing profile pass-through set (SKILL.md:141, and the Step-1 note at SKILL.md:36-37).

## Acceptance criteria
- [ ] Before Step 3 (skills/triage/SKILL.md:132), the orchestrator resolves the `.project/<doc>#<section>` anchors cited in the issue body + acceptance criteria.
- [ ] It pulls a SUPERSET of plausibly-relevant sections via scripts/read-doc-section.sh (the #B primitive) — resolved ONCE per issue, not per-reviewer.
- [ ] The resolved sections are added to BOTH the triage-reviewer dispatch brief (SKILL.md:141) AND the design-reviewer dispatch brief (SKILL.md:164).
- [ ] Reviewers do NOT re-read whole files — pre-resolved sections are supplied.
- [ ] Absent `.project/` directory -> resolve-once is a no-op; both dispatches proceed with no grounding and NO error (graceful degrade).
- [ ] A missing/renamed cited anchor surfaces via the #B primitive's loud (non-zero) failure — not silent empty grounding.
- [ ] Additive: no existing triage step, the cache logic, the five-criteria assessment, or any gate changes beyond adding the resolved-sections input to the two briefs.

## Design (recorded, consistent)
- Edit point: skills/triage/SKILL.md, before Step 3 dispatch (SKILL.md:132) and the design-reviewer dispatch (SKILL.md:158). projectDocs resolves at SKILL.md:27 (added by #A).
- The resolved sections join the existing profile pass-through set already passed to the briefs (sourceGlobs/uiSurfaceGlobs/nonNegotiables at SKILL.md:141; Step-1 pass-through note at SKILL.md:36-37).
- Calls scripts/read-doc-section.sh / .ps1 (#B primitive); pulls a superset to avoid under-grounding.
- Convention followed: extends the existing dispatch-brief composition at SKILL.md:132 (triage-reviewer) and SKILL.md:158 (design-reviewer).
- Degrade: absent projectDocs -> default `.project/`; absent `.project/` dir -> no-op, no error.

## Dependencies
- Depends on #B — calls the read-doc-section primitive scripts/read-doc-section.sh introduced by #B
- Depends on #A — references projectDocs (default .project/), introduced by #A at SKILL.md:27 (soft edge; the `.project/` default makes it non-blocking, Wave order already places #A in Wave 1 ahead of #D in Wave 2 — recorded for completeness per the self-check Advisory)

## Classification
- Surface: logic ; Risk: heavy

> Self-check Advisory notes (not Blockers): (1) the #A projectDocs edge is soft (the hard-coded `.project/` default suffices per efficiency-grounding-plan.md:75); now recorded above. (2) "superset" interpretation: cited anchors + reviewers retain Read for additional anchors (efficiency-grounding-plan.md:46-47, 83-84).
