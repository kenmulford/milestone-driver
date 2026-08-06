# Prose that is not a citation

Every line below was measured as a false positive of a naive matcher, and each
is dropped by one of the four discriminator rules.

A closing backtick sits where the citation's space would be: `agents/triage-reviewer.md` (architect lens).
Same shape again: `skills/setup/SKILL.md` (Phase 2), and `package.json` (generic Node).
No slash in the path: build-file-index.ps1 (issue 318).
A placeholder leaves a leading slash: <repo>/.milestone-config/driver.json (the profile).
A version shape: 1.2 (a minor release).
An unbalanced parenthetical runs off the end of src/target.md (opened here but never
closed on that line, so it is prose.
