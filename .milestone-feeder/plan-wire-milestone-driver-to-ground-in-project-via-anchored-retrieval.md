# Milestone plan — Wire milestone-driver to ground in .project/ via anchored (section-level) retrieval

Milestone title (exact): milestone-driver v1.11.1 — grounding seam
Version provenance: explicit
Self-check: PASS — all 7 issues GAPS clean (milestone-driver reviewers; #B/#C/#D carry Advisory-only notes, no Blockers)
Source brief: file:docs/efficiency-grounding-plan.md
Milestone number (GitHub): 20

## Milestone description (Wave order)
Wire the driver's implementer + triage-reviewer + design-reviewer to ground in the project brain (`.project/`) the same way the feeder does — via section-level (anchored) retrieval, so the plugin that writes the code shares one source of truth with the plugin that planned it, without multiplying tokens. Value is consistency/quality first; token cost held down by selective (anchored, never whole-file) retrieval. This repo's slice (part 2/3) of the 3-plugin grounding seam.

## Waves
- Wave 1 (parallel): #A, #B
- Wave 2 (parallel): #C (depends on #B), #D (depends on #B)
- Wave 3 (parallel): #E (depends on #C), #F (depends on #D), #G (depends on #D)

## Issues

### #A — Add the projectDocs profile key to the schema and resolve it (default .project/, absent-means-default)   [logic, risk:light]   [self-check: PASS]
## Summary
Add a `projectDocs` optional key (default `.project/`, absent-means-default) to the Keys table in `docs/profile-schema.md`, mirroring the feeder's identically-named key, and resolve it to `.project/` at the driver's two profile-read points (`skills/solve-issue/SKILL.md:14`, `skills/triage/SKILL.md:27`). Default to `.project/` even when the key is absent. The driver currently reads zero `.project/` docs; this key is the schema+read foundation the rest of the grounding seam builds on. Sibling bootstrapper #38 emits the value; the driver defaults regardless.

## Acceptance criteria
- [ ] A `projectDocs` row is added to the Keys table in docs/profile-schema.md as an OPTIONAL key (not Core), type string, default `.project/`, mirroring the feeder's projectDocs key.
- [ ] When the profile sets projectDocs to a value, that value is used as the project-docs directory.
- [ ] When projectDocs is absent, it defaults to `.project/` (absent-means-default) — documented in the row and applied at both read points.
- [ ] solve-issue (SKILL.md:14) and triage (SKILL.md:27) resolve projectDocs (default `.project/`) alongside the other optional keys read there.
- [ ] Absent `.project/` directory -> no error; consumers degrade gracefully (the key only names the directory; it creates no hard dependency).
- [ ] Additive: no existing Core key, no gate logic, and no other key's behavior changes.

## Design (recorded, consistent)
- Edit docs/profile-schema.md Keys table (header at L89): add the projectDocs optional row. Cite the absent-means-default convention already used by sibling optional keys (e.g. L106 `versioning`, L129 `integrations.trello`).
- Convention followed: mirror the feeder's existing `projectDocs` key (same name, same default `.project/`, same absent-means-default semantics — milestone-feeder/SPEC.md:199).
- Resolve at the two read points: solve-issue/SKILL.md:14 and triage/SKILL.md:27, alongside the optional keys already resolved there (unitTestCmd/e2eTestCmd/domainSkills/nonNegotiables, "skipped cleanly when absent").
- "New keys added only when a real consumer needs them" (L68) is satisfied: this grounding seam is the real consumer.

## Dependencies
- Depends on: none

## Classification
- Surface: logic ; Risk: light

### #B — Ship the dependency-free read-doc-section.sh + .ps1 anchored-retrieval primitive (fail-loud on missing anchor)   [logic, risk:heavy]   [self-check: PASS (2 Advisory)]
## Summary
Add a dependency-free `scripts/read-doc-section.sh` + `scripts/read-doc-section.ps1` twin that, given a Markdown doc path and a `## anchor` heading, prints ONLY that section (from the anchor heading to the next heading of equal-or-higher level). On a missing/renamed anchor or a missing file it FAILS LOUD: non-zero exit + a stderr message — never silent empty output (which would be invisible drift). This is the anchored-retrieval primitive the orchestrators (#C/#D) call so grounding tokens scale with cited-section size, not whole-doc size.

## Acceptance criteria
- [ ] scripts/read-doc-section.sh exists; usage `read-doc-section.sh <doc-path> <anchor>`; prints only the named section.
- [ ] scripts/read-doc-section.ps1 twin exists and behaves IDENTICALLY (same args, same output, same exit codes) — per the dual-script twin convention.
- [ ] Happy path: a valid doc + an existing `## anchor` -> prints from the anchor heading line through the line before the next heading of equal-or-higher level (the section-boundary rule).
- [ ] Missing/renamed anchor -> NON-ZERO exit + a stderr message naming the missing anchor; NO silent empty stdout.
- [ ] Missing file -> NON-ZERO exit + a stderr message.
- [ ] Dependency-free: bash uses only POSIX shell + (optionally) jq; ps1 uses only PowerShell 7+ built-ins. No yq/act/python (per docs/profile-schema.md:123).

## Design (recorded, consistent)
- Mirror the anchor-walk/scan loop in scripts/extract-version.sh (the canonical line-scanning-for-a-heading pattern, scan() at L38-76); the .ps1 twin mirrors scripts/extract-version.ps1's PowerShell idiom.
- Twin convention (Convention followed): scripts/ci-preflight-steps.{sh,ps1} and scripts/extract-version.{sh,ps1} ship behavior-identical bash+ps1 pairs; read-doc-section ships the same pair.
- Section-boundary rule: start at the line matching the requested `## anchor` heading; stop at the next line whose heading level is <= the anchor's level (sibling-or-higher heading); print the lines in between (inclusive of the anchor heading).
- Fail-loud divergence (recorded, intentional): unlike the fail-OPEN degradation extract-version uses on a version miss, this primitive fails CLOSED (non-zero) on a missing anchor — because silent empty grounding is the exact drift this seam must surface.
- Dependency-free constraint: docs/profile-schema.md:123.

## Dependencies
- Depends on: none

## Classification
- Surface: logic ; Risk: heavy

> Self-check Advisory notes (not Blockers — recorded for the implementer; from the triage-reviewer):
> 1. Parity-test artifact: every shipped script pair in scripts/ has a `tests/<name>.test.{sh,ps1}` pair (ci-preflight-steps, extract-version), and extract-version ships a `.cases.tsv` parity contract. Consider shipping `tests/read-doc-section.test.{sh,ps1}` so the "behaves IDENTICALLY" criterion is verifiable rather than asserted (the established scripts/+tests/ parity convention).
> 2. Section-boundary edge cases: pin the EOF-terminates-section behavior (anchor is the last section -> runs to end-of-file) and the duplicate-anchor policy (first match vs fail-loud on ambiguity), so the happy-path scanner has no undefined boundary.

### #C — Resolve cited .project/ sections once in solve-issue before the implementer dispatch and pass them in the brief   [logic, risk:heavy]   [self-check: PASS (2 Advisory)]
## Summary
In skills/solve-issue, before "### 3. Dispatch the implementer" (SKILL.md:98-99), add a resolve-once step: parse which `.project/<doc>#<section>` anchors the issue cites (from the issue body + acceptance criteria), pull a SUPERSET of plausibly-relevant sections via the #B read-doc-section primitive, and add those sections to the implementer dispatch brief. The implementer never re-reads whole files — sections are pre-resolved once in the orchestrator, so grounding tokens scale with cited-section size. projectDocs (added by #A, default `.project/`) names the directory; resolution happens at SKILL.md:14.

## Acceptance criteria
- [ ] Before the implementer dispatch (skills/solve-issue/SKILL.md:98-99), the orchestrator resolves the `.project/<doc>#<section>` anchors cited in the issue body + acceptance criteria.
- [ ] It pulls a SUPERSET of plausibly-relevant sections via scripts/read-doc-section.sh (the #B primitive) — resolved ONCE, not per-subagent.
- [ ] The resolved sections are added to the implementer dispatch brief (the "colleague walking in cold" brief at SKILL.md:99).
- [ ] The implementer does NOT re-read whole files — pre-resolved sections are supplied.
- [ ] Absent `.project/` directory -> resolve-once is a no-op; the dispatch proceeds with no grounding and NO error (graceful degrade).
- [ ] A missing/renamed cited anchor surfaces via the #B primitive's loud (non-zero) failure — not silent empty grounding.
- [ ] Additive: no existing solve-issue step, gate, or the implementer contract changes beyond adding the resolved-sections input to the brief.

## Design (recorded, consistent)
- Edit point: skills/solve-issue/SKILL.md, immediately before "### 3. Dispatch the implementer" (SKILL.md:98-99). projectDocs resolves at SKILL.md:14 (added by #A).
- Calls scripts/read-doc-section.sh / .ps1 (the #B primitive) for each cited anchor; pulls a superset (plausibly-relevant sibling sections) to avoid under-grounding (the recorded mitigation: efficiency-grounding-plan.md:83 "under-retrieval is the real risk — mitigate with a superset").
- Convention followed: extends the existing dispatch-brief assembly at SKILL.md:98-99; mirrors how the brief already carries the issue/plan/profile/file-scope.
- Degrade: absent projectDocs -> default `.project/`; absent `.project/` dir -> no-op, no error.

## Dependencies
- Depends on #B — calls the read-doc-section primitive scripts/read-doc-section.sh introduced by #B
- Depends on #A — references projectDocs (default .project/), introduced by #A at SKILL.md:14 (soft edge; the `.project/` default makes it non-blocking, Wave order already places #A in Wave 1 ahead of #C in Wave 2 — recorded for completeness per the self-check Advisory)

## Classification
- Surface: logic ; Risk: heavy

> Self-check Advisory notes (not Blockers): (1) the #A projectDocs edge was implicit in the original body; now recorded above (Wave order unaffected). (2) "SUPERSET of plausibly-relevant sections" is a recorded heuristic — bias toward over-inclusion of sibling sections + on-demand Read (the plan's recorded convention, efficiency-grounding-plan.md:46-47, :83); no novel decision required.

### #D — Resolve cited .project/ sections once in triage before the triage-reviewer and design-reviewer dispatches and pass them in the briefs   [logic, risk:heavy]   [self-check: PASS (2 Advisory)]
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

### #E — Wire implementer "What you receive" to consume provided .project/ sections; keep Read/grep for on-demand anchor pulls   [logic, risk:light]   [self-check: PASS]
## Summary
Update the "What you receive" section of `agents/implementer.md` (line 32) so the implementer's input list names the `.project/` sections that solve-issue now supplies in its dispatch brief (added by #C). Today the agent grounds only off the issue, the approved plan, the profile, and file scope — it does not know the brief carries pre-extracted `.project/` sections. This adds those sections as a stated input and notes the implementer keeps its existing Read/grep tools for ON-DEMAND pulls of any additional cited anchor not pre-supplied (never under-ground). Purely additive: raises grounding consistency, changes no contract clause and no gate.

## Acceptance criteria
- [ ] The "What you receive" section of agents/implementer.md (line 32) lists the provided `.project/` sections as an input the solve-issue dispatch brief supplies (added alongside the existing inputs, not replacing them).
- [ ] The section states the implementer grounds its implementation in those provided `.project/` sections when present.
- [ ] The section retains the existing Read/grep on-demand capability: the implementer may still pull any ADDITIONAL cited anchor not pre-supplied in the brief — never under-ground.
- [ ] Additive only: no existing contract clause, no decision-log requirement, no gate, and no return shape changes.
- [ ] Empty/absent state: when the dispatch brief carries no `.project/` sections, the new input is simply empty and the implementer proceeds exactly as before — no new required-input precondition, no new failure path.

## Design (recorded, consistent)
- Edit point: the "What you receive" section header at agents/implementer.md:32. Add one input bullet mirroring the existing bullets' form (input list at lines 36-40: issue / approved plan / profile / file scope), naming "the provided `.project/` sections — supplied by the solve-issue dispatch brief (added by #C)".
- On-demand retention: keep the implementer's existing Read/grep tools; the pre-supplied sections are a grounding head-start, not a replacement for on-demand reads of additional anchors.
- Scope boundary: the edit touches ONLY the "What you receive" section; the implementer's contract clauses (TDD, citations, uncommitted-diff, STOP-and-ask gates) are NOT touched.
- Convention followed: existing input-list form in agents/implementer.md "What you receive" (line 32 onward).

## Dependencies
- Depends on #C — consumes the .project/ sections the solve-issue dispatch brief supplies, added by #C

## Classification
- Surface: logic ; Risk: light

### #F — Wire triage-reviewer "What you receive" to consume provided .project/ sections; keep Read/grep for on-demand anchor pulls   [logic, risk:light]   [self-check: PASS]
## Summary
Update the "What you receive" section of `agents/triage-reviewer.md` (line 32) so the triage-reviewer's input list names the `.project/` sections that the triage skill now supplies in its dispatch brief (added by #D). Today the agent grounds only off the issue, recorded design decisions, the milestone description, and the profile — it does not know the brief carries pre-extracted `.project/` sections. This adds those sections as a stated input and notes the reviewer keeps its existing Read/grep tools for ON-DEMAND pulls of any additional cited anchor not pre-supplied (never under-ground). Purely additive: raises grounding consistency, changes no criterion and no gate.

## Acceptance criteria
- [ ] The "What you receive" section of agents/triage-reviewer.md (line 32) lists the provided `.project/` sections as an input the triage dispatch brief supplies (added alongside the existing inputs, not replacing them).
- [ ] The section states the reviewer grounds its five-criteria assessment in those provided `.project/` sections when present.
- [ ] The section retains the existing Read/grep on-demand capability: the reviewer may still pull any ADDITIONAL cited anchor not pre-supplied — never under-ground.
- [ ] Additive only: the five-criteria assessment block (line 43 onward), the severity rule, the structured return block, and every gate are byte-for-byte unchanged.
- [ ] Empty/absent state: when the dispatch brief carries no `.project/` sections, the new input is simply empty and the reviewer proceeds exactly as before — no new required-input precondition, no new failure path.

## Design (recorded, consistent)
- Edit point: the "What you receive" section header at agents/triage-reviewer.md:32 (existing input bullets at lines 34-40). Add one input bullet mirroring the existing form, naming "the provided `.project/` sections — supplied by the triage dispatch brief (added by #D)".
- On-demand retention: keep the reviewer's existing Read/grep tools; the pre-supplied sections are a grounding head-start, not a replacement.
- Scope boundary: the edit touches ONLY the "What you receive" section. The five-criteria assessment beginning at agents/triage-reviewer.md:43 is NOT touched — no criterion, no gate, no return shape changes. The agent remains a read-only verdict function over provided text; it makes no `gh` call of its own.
- Convention followed: existing input-list form in agents/triage-reviewer.md "What you receive" (line 32 onward); the agent's input list mirrors the SKILL dispatch brief one-to-one (skills/triage/SKILL.md:136-141), so adding a fifth bullet keeps that mirror intact.

## Dependencies
- Depends on #D — consumes the .project/ sections the triage dispatch brief supplies, added by #D

## Classification
- Surface: logic ; Risk: light

### #G — Wire design-reviewer "What you receive" to consume provided .project/ sections; keep Read/grep for on-demand anchor pulls   [logic, risk:light]   [self-check: PASS]
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

## Project-docs grounding
- No `.project/` directory exists in the driver repo at plan time — project-docs grounding was ABSENT; every design call is grounded on the brief (docs/efficiency-grounding-plan.md) + verified driver-repo conventions/file:line, never fabricated.
- Degradations:
  - `uiSurfaceGlobs` absent (neither driver file carries it) -> all 7 candidates treated as `logic`; no design-lens distinction drawn; the Pass-2 design-reviewer batch was empty (every triage returned NEEDS_DESIGN_REVIEW: no).
  - `projectDocs` not yet in the profile -> the seam's own degrade contract (absent -> default `.project/`; absent directory -> proceed, no error) is exactly what issues #A/#C/#D encode.
- Advisory notes carried (not Blockers): #B (parity-test artifact; section-boundary EOF/duplicate-anchor edge cases); #C/#D (the soft #A projectDocs edge — now recorded in their Dependencies; the "superset" retrieval heuristic — resolved by the plan's recorded over-inclusion + on-demand-Read convention).

## Needs human input
none

---
This plan file is the build artifact — run `/milestone-feeder:create` to deploy it to GitHub (it ensures the labels, creates-or-adopts the milestone by the exact title above, opens each surviving issue, rewrites the slug references to real issue numbers, and patches the milestone description with the Wave order). `plan` wrote no GitHub state.
