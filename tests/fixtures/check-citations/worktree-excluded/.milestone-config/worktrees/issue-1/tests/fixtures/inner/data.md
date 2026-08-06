# A worktree's own checker test data

This is the case that made the gate go red on a clean tree. The `tests/fixtures/`
exclusion is a REPO-RELATIVE PREFIX, and this file's repo-relative path starts
with `.milestone-config/worktrees/`, so it matched no exclusion and its
deliberately-broken anchor failed the run.

Grounded in `src/target.md (anchor-that-does-not-exist)`.
