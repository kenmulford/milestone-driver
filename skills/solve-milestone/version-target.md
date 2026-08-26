# Target-version determination: solve-milestone reference

Loaded by solve-milestone's `### 3. Determine the target version` **only when `versioning` is `true` or absent**. Under `versioning: false` the run is version-free and this file is **never read**. Missing or unreadable at that point is a **systemic failure**: surface it and halt the run per core `SKILL.md`'s `## Autonomy` → "Systemic failures that halt the run".

---

Determine the target version with the deterministic extractor `${CLAUDE_PLUGIN_ROOT}/scripts/extract-version.{sh,ps1}` (issue #158) - do **not** parse by judgment. Pipe the milestone's title + description as JSON to it (bash where available, else pwsh):

```bash
gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '{title, description}' \
  | bash "${CLAUDE_PLUGIN_ROOT}/scripts/extract-version.sh"        # pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/extract-version.ps1" on pwsh-only hosts
```

It prints the normalized version on **stdout**, or nothing - with a reason (`none` or `ambiguous:<candidates>`) on **stderr**. Branch on the result × `versioning`:

| Extractor result | `versioning` absent (opportunistic) | `versioning: true` (explicit opt-in) |
|---|---|---|
| version on stdout | **versioned** - hold it as the target for the loop; record it | **versioned** - same |
| empty + `none` | **version-free**, record "no parseable version in milestone - version-free run (logged)" | **prompt** the user: "No version found in milestone '<title>'. Enter a target version, or proceed version-free." |
| empty + `ambiguous:<list>` | **version-free**, record "ambiguous version in title (<list>) - version-free run (logged)" | **prompt**, listing `<list>` as the candidates to choose from |

**Non-interactive runs.** With `MILESTONE_DRIVER_NONINTERACTIVE=1` set (scheduled / cron / headless), explicit `true` does **not** prompt - it degrades to version-free with a loud `⚠ explicit versioning:true but no parseable version - running version-free` warning and a logged note. The prompt path is interactive-main-thread only. The extractor is fail-open: any internal error yields empty + `none`, degrading exactly like "no version found".

> **In versioned mode:** the version **source** is the milestone (extracted here); the **target** is `.claude-plugin/plugin.json`, whose missing-`plugin.json` fail-safe is applied downstream at `solve-issue` step 6.4 (the bump step), not here. The milestone-derived target version is authoritative - `solve-issue`'s per-issue patch-default + confirm behavior does **not** fire inside a milestone run. The same main thread runs both skills, so the target version comes from the orchestrator's working context - it is **not** passed as a CLI argument to `solve-issue`.
