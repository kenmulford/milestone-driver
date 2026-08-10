# DB-hazard interview: solve-milestone reference

Loaded by solve-milestone's *Resolve execution mode* Before-starting step **only when cascade row 4 or row 4′ is the first match** — `unitTestCmd` set AND `parallel` absent from the profile. Every other row resolves the mode without reading this file. Missing or unreadable once that trigger has fired is a **systemic failure**: surface it and halt the run per core `SKILL.md`'s `## Autonomy` → "Systemic failures that halt the run".

---

**Interactive (row 4).** Prompt:

```text
⚠ This repo runs unitTestCmd, and concurrent builds share external services like your
  test database — a git worktree isolates the filesystem, not the DB. Is your test
  harness isolated per worker (or otherwise safe to run concurrently)?
  [Yes — go parallel] · [No — run sequential]
```

- **Yes** → run **parallel**; write `parallel: true` to `.milestone-config/driver.json`.
- **No** → run **sequential**; write `parallel: false`.
- Either way, print the visible note: _"Recorded `parallel: <value>` in `.milestone-config/driver.json` — change it there anytime."_

**Persistence** is a minimal in-place JSON edit of `.milestone-config/driver.json` adding the `parallel` key, preserving every other key and the file's formatting. It is the orchestrator's own working-tree edit — **not** committed, rides no PR — and, running after the clean-tree check (Before-starting step 4), it is the one intentional uncommitted change the driver made. This is the deliberate write-rule deviation for `parallel` (see `docs/profile-schema.md`): an explicit boolean is written whenever the decision is made — both `true` and `false` — because omitting it would re-fire the interview next run while `unitTestCmd` is present.

**Non-interactive (`MILESTONE_DRIVER_NONINTERACTIVE=1` OR `--driven` present — row 4′):** do **not** prompt. Fall to **sequential** with a loud note — `⚠ unitTestCmd set and no parallel-safety decision recorded — running sequential; set "parallel": true in .milestone-config/driver.json to enable parallel builds.` — and do **NOT** persist a value (no human decision was made). Mirrors the versioning `NONINTERACTIVE` degradation in core `SKILL.md`'s `### 3. Determine the target version`.
