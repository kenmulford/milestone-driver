---
name: setup
description: This skill should be used when "milestone-driver:setup" is invoked directly, OR auto-invoked by solve-issue/solve-milestone when milestone-driver.json is absent or missing a required Core key (`integrationBranch`, `protectedBranch`, or `sourceGlobs`). Guides an interactive first-run bootstrap that infers every profile key from repo signals, presents detected defaults with plain-language descriptions, lets the user accept/edit/skip optional keys (stating each skip-consequence), writes milestone-driver.json, and returns control so the original task continues — no re-invocation needed.
version: 0.1.0
---

# setup — first-run profile bootstrap

Generate or repair `milestone-driver.json` through a guided, inference-first flow. Every key is presented with a plain-language description and a detected default. Optional keys state their skip-consequence. No blank prompts — if a default cannot be inferred, an example is shown.

**After writing the file, return control to the caller** (solve-issue or solve-milestone) so the original task continues immediately. The user does not need to re-run the command.

## When this runs

- **Auto-invoked** by `solve-issue`/`solve-milestone` when `milestone-driver.json` is absent or missing a required Core key (`integrationBranch`, `protectedBranch`, or `sourceGlobs`).
- **Direct invocation** (`/milestone-driver:setup`) when onboarding a new repo or repairing an existing profile.

## Procedure

### Phase 1 — Silent project-evaluation pass

Before asking anything, gather signals from the repo. Run these checks silently (no output to the user yet):

| Signal | Command / check |
|---|---|
| Repo default branch | `git symbolic-ref refs/remotes/origin/HEAD` → strip `refs/remotes/origin/`; fall back to `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'` |
| Integration-branch candidates | `git branch -a` — look for `develop`, `dev`, `development`, `integration` |
| Repo layout | List top-level dirs + key files: `package.json`, `*.sln`, `*.csproj`, `Makefile`, `pyproject.toml`, `Cargo.toml` |
| Unit test command | `package.json` → `.scripts.test`; presence of test `.csproj`; `Makefile` targets `test`; `pyproject.toml` `[tool.pytest]`; `Cargo.toml` |
| E2E test indicators | Presence of Appium config, Playwright config (`playwright.config.*`), Selenium project, `run-e2etests.*` script |
| Stack signals | Language/framework files for `domainSkills` mapping (see table below) |
| Existing profile | Read `milestone-driver.json` if present — pre-fill any already-set keys |

**Stack → domainSkills inference table:**

| Detected file | Inferred domainSkills candidate |
|---|---|
| `*.csproj` / `*.sln` with `Maui` | `["maui-skills:*", "maui-current-apis"]` |
| `*.csproj` / `*.sln` (non-MAUI) | omit (no bundled domain skill; implementer falls back to general docs + repo conventions) |
| `package.json` with Angular | `["angular-skills:angular-developer"]` |
| `skills/**` + `agents/**` + `hooks/**` | `["plugin-dev:*", "superpowers:writing-skills"]` |
| `package.json` (generic Node) | omit |
| Python project | omit |

### Phase 2 — Tier-by-tier confirmation

Present keys in four tiers: **Core → Testing → E2E → Enrichment**. Within each tier, show one key at a time (or a logical group). For every key:

- State the plain-language label.
- Show the detected default (or an illustrative example if none was detected).
- For optional keys: state the skip-consequence on the same line.
- Accept, edit, or skip — never leave a field blank without an explicit skip choice.

**Tier: Core** — `integrationBranch`, `protectedBranch`, and `sourceGlobs` are required and cannot be skipped (hard-stop if genuinely unknowable). `implementerAgent` is auto-filled with the bundled default — show it, confirm, move on; it never hard-stops.

| Key | Plain-language label | Inference fallback if not detected |
|---|---|---|
| `protectedBranch` | "Which branch must I never push or PR to? (Your release / default branch.)" | Show `main` as example |
| `integrationBranch` | "Which branch should I open PRs into and merge work onto?" | Show `develop` as example; if no gitflow branch found, ask explicitly |
| `sourceGlobs` | "Which path patterns are 'source' that only the implementer subagent may edit?" | Infer from repo layout (e.g. `["src/**","tests/**"]` for Node; `["YourApp/**","YourApp.Tests/**"]` for .NET; `["skills/**","agents/**","hooks/**"]` for a Claude Code plugin) |
| `implementerAgent` | "Which agent authors the code? (Rarely changed — the bundled default is fine for most repos.)" | Auto-fill `"milestone-driver:implementer"` — show it, confirm, move on |

**Hard-stop condition:** If `protectedBranch`, `integrationBranch`, or `sourceGlobs` genuinely cannot be inferred and the user cannot supply a value, stop with a clear message and do not write a partial profile.

**Tier: Testing** (optional)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `unitTestCmd` | "What command runs your unit tests?" | Skip → "No unit tests — I won't gate commits on them; the implementer verifies behavior another way." |

**Tier: E2E** (optional; skip the whole tier if no E2E signals were detected)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `e2eTestCmd` | "What command runs your end-to-end / UI tests?" | Skip → "No E2E gate." |
| `e2eEnv` | "What device/endpoint should the E2E runner target? (e.g. `{\"endpoint\":\"127.0.0.1:4723\",\"device\":\"Android emulator (AVD)\"}` for Appium)" | Skip → "No E2E environment recorded." |

**Tier: Enrichment** (optional; show inferred values — accept with one keystroke)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `domainSkills` | "Any stack-specific skills the implementer should consult for citations? (e.g. `[\"maui-skills:*\"]` for MAUI)" | Skip → "Implementer relies on general docs + repo conventions only." |
| `nonNegotiables` | "Any hard constraints the implementer must honour? (framework versions, platform targets)" | Skip → "None recorded." |

### Phase 3 — Write and confirm

Assemble the collected keys into a valid JSON object and write to `<repo-root>/milestone-driver.json`. Omit any key the user skipped (do not write `null` or empty values). Print the final file contents so the user can verify.

Writing the file is sufficient for the mechanical gates to read it immediately this session — no commit is required for the gates to function.

```
milestone-driver.json written.

{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["skills/**", "agents/**", "hooks/**"],
  "implementerAgent": "milestone-driver:implementer"
}

Returning to the original task now.
```

### Phase 4 — Return control

Return control to the caller immediately. Do **not** ask the user to re-run `/milestone-driver:solve-issue` or `/milestone-driver:solve-milestone`. The bootstrap is a sub-step, not a restart.

## Non-negotiables

- Never present a blank prompt. Every key shows either a detected default or an illustrative example.
- Skip always states its consequence. A user who skips knows exactly what gate or behavior is affected.
- Do not write a partial profile. Either all three required Core keys (`integrationBranch`, `protectedBranch`, `sourceGlobs`) are present, or no file is written. (`implementerAgent` is auto-filled; the optional keys may be omitted.)
- **Committing the profile:** writing the file is enough for the gates to read it this session. When `setup` is invoked **directly** (`/milestone-driver:setup`), suggest the user commit it (`git add milestone-driver.json && git commit -m "chore: add milestone-driver.json profile"`) so every clone and CI has it. When `setup` is auto-invoked **as a bootstrap sub-step**, leave the commit to the normal flow — do not create a commit on the current branch.
