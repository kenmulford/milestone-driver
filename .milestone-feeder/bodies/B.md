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
