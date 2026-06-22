## Summary
Update the "What you receive" section of `agents/design-reviewer.md` (line 32) so the design-reviewer's input list names the `.project/` sections that the triage skill now supplies in its design-reviewer dispatch brief (added by #D). Today the agent's input list (lines 36-38) names only the issue, recorded design decisions, and uiSurfaceGlobs pointers — it does not know the brief carries pre-extracted `.project/` sections. This adds those sections as a stated input and notes the reviewer keeps its existing Read/grep tools for ON-DEMAND pulls of any additional cited anchor not pre-supplied (never under-ground). Purely additive: raises grounding consistency, changes no criterion and no gate.

## Acceptance criteria
- [ ] The "What you receive" section of agents/design-reviewer.md (line 32) lists the provided `.project/` sections as an input the triage dispatch brief supplies — added alongside the existing input bullets at lines 36-38, not replacing them.
- [ ] The section states the reviewer grounds its five-criteria assessment in those provided `.project/` sections when present (e.g., a UI issue citing `.project/design-system.md#data-tables` arrives with THAT section's text in the brief — not the whole file, not nothing).
- [ ] The section retains the existing Read/grep on-demand capability (currently at agents/design-reviewer.md:40): the reviewer may still read implicated surfaces and pull any ADDITIONAL cited anchor not pre-supplied — never under-ground.
- [ ] Additive only: the five-criteria assessment block (agents/design-reviewer.md:42 onward), the severity rule, the structured return block, and every gate are byte-for-byte unchanged.
- [ ] Empty/absent state: when the dispatch brief carries no `.project/` sections, the new input is simply empty and the reviewer proceeds exactly as before — no new required-input precondition, no new failure path.

## Design (recorded, consistent)
- Edit point: the "What you receive" section header at agents/design-reviewer.md:32. Add one input bullet to the existing list (lines 36-38) naming "the provided `.project/` sections — supplied by the triage design-reviewer dispatch brief (added by #D)". Mirror the existing bullet form.
- On-demand retention: keep the existing sentence at agents/design-reviewer.md:40 ("You may read the implicated UI surface files (read-only)...") and extend its intent to cover pulling any ADDITIONAL cited anchor not pre-supplied.
- Scope boundary: the edit touches ONLY the "What you receive" section (line 32 through the line-40 read-tools note). The five-criteria assessment beginning at agents/design-reviewer.md:42, the severity rule, the rigor gate, and the structured return block are NOT touched. The agent remains a read-only verdict function over provided text; it makes no `gh` call of its own.
- Convention followed: existing input-list bullet form at agents/design-reviewer.md:36-38; existing read-tools note at :40; five-criteria block boundary at :42.

## Dependencies
- Depends on #D — consumes the .project/ sections the triage design-reviewer dispatch brief supplies, added by #D

## Classification
- Surface: logic ; Risk: light
