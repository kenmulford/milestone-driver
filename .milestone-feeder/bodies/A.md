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
