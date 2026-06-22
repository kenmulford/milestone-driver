## Summary
Update the "What you receive" section of `agents/implementer.md` (line 32) so the implementer's input list names the `.project/` sections that solve-issue now supplies in its dispatch brief (added by #185). Today the agent grounds only off the issue, the approved plan, the profile, and file scope — it does not know the brief carries pre-extracted `.project/` sections. This adds those sections as a stated input and notes the implementer keeps its existing Read/grep tools for ON-DEMAND pulls of any additional cited anchor not pre-supplied (never under-ground). Purely additive: raises grounding consistency, changes no contract clause and no gate.

## Acceptance criteria
- [ ] The "What you receive" section of agents/implementer.md (line 32) lists the provided `.project/` sections as an input the solve-issue dispatch brief supplies (added alongside the existing inputs, not replacing them).
- [ ] The section states the implementer grounds its implementation in those provided `.project/` sections when present.
- [ ] The section retains the existing Read/grep on-demand capability: the implementer may still pull any ADDITIONAL cited anchor not pre-supplied in the brief — never under-ground.
- [ ] Additive only: no existing contract clause, no decision-log requirement, no gate, and no return shape changes.
- [ ] Empty/absent state: when the dispatch brief carries no `.project/` sections, the new input is simply empty and the implementer proceeds exactly as before — no new required-input precondition, no new failure path.

## Design (recorded, consistent)
- Edit point: the "What you receive" section header at agents/implementer.md:32. Add one input bullet mirroring the existing bullets' form (input list at lines 36-40: issue / approved plan / profile / file scope), naming "the provided `.project/` sections — supplied by the solve-issue dispatch brief (added by #185)".
- On-demand retention: keep the implementer's existing Read/grep tools; the pre-supplied sections are a grounding head-start, not a replacement for on-demand reads of additional anchors.
- Scope boundary: the edit touches ONLY the "What you receive" section; the implementer's contract clauses (TDD, citations, uncommitted-diff, STOP-and-ask gates) are NOT touched.
- Convention followed: existing input-list form in agents/implementer.md "What you receive" (line 32 onward).

## Dependencies
- Depends on #185 — consumes the .project/ sections the solve-issue dispatch brief supplies, added by #185

## Classification
- Surface: logic ; Risk: light
