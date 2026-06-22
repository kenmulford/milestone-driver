## Summary
Update the "What you receive" section of `agents/triage-reviewer.md` (line 32) so the triage-reviewer's input list names the `.project/` sections that the triage skill now supplies in its dispatch brief (added by #186). Today the agent grounds only off the issue, recorded design decisions, the milestone description, and the profile — it does not know the brief carries pre-extracted `.project/` sections. This adds those sections as a stated input and notes the reviewer keeps its existing Read/grep tools for ON-DEMAND pulls of any additional cited anchor not pre-supplied (never under-ground). Purely additive: raises grounding consistency, changes no criterion and no gate.

## Acceptance criteria
- [ ] The "What you receive" section of agents/triage-reviewer.md (line 32) lists the provided `.project/` sections as an input the triage dispatch brief supplies (added alongside the existing inputs, not replacing them).
- [ ] The section states the reviewer grounds its five-criteria assessment in those provided `.project/` sections when present.
- [ ] The section retains the existing Read/grep on-demand capability: the reviewer may still pull any ADDITIONAL cited anchor not pre-supplied — never under-ground.
- [ ] Additive only: the five-criteria assessment block (line 43 onward), the severity rule, the structured return block, and every gate are byte-for-byte unchanged.
- [ ] Empty/absent state: when the dispatch brief carries no `.project/` sections, the new input is simply empty and the reviewer proceeds exactly as before — no new required-input precondition, no new failure path.

## Design (recorded, consistent)
- Edit point: the "What you receive" section header at agents/triage-reviewer.md:32 (existing input bullets at lines 34-40). Add one input bullet mirroring the existing form, naming "the provided `.project/` sections — supplied by the triage dispatch brief (added by #186)".
- On-demand retention: keep the reviewer's existing Read/grep tools; the pre-supplied sections are a grounding head-start, not a replacement.
- Scope boundary: the edit touches ONLY the "What you receive" section. The five-criteria assessment beginning at agents/triage-reviewer.md:43 is NOT touched — no criterion, no gate, no return shape changes. The agent remains a read-only verdict function over provided text; it makes no `gh` call of its own.
- Convention followed: existing input-list form in agents/triage-reviewer.md "What you receive" (line 32 onward); the agent's input list mirrors the SKILL dispatch brief one-to-one (skills/triage/SKILL.md:136-141), so adding a fifth bullet keeps that mirror intact.

## Dependencies
- Depends on #186 — consumes the .project/ sections the triage dispatch brief supplies, added by #186

## Classification
- Surface: logic ; Risk: light
