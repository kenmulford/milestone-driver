---
name: setup
description: This skill should be used when "milestone-driver:setup" is invoked directly, OR auto-invoked by solve-issue/solve-milestone when milestone-driver.json is absent or missing a required Core key (`integrationBranch`, `protectedBranch`, or `sourceGlobs`). Guides an interactive first-run bootstrap that infers every profile key from repo signals, presents detected defaults with plain-language descriptions, lets the user accept/edit/skip optional keys (stating each skip-consequence), writes milestone-driver.json, and returns control so the original task continues — no re-invocation needed.
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
| Preflight (fast pre-PR checks) command | `.pre-commit-config.yaml` present → `pre-commit run --all-files`; `package.json` `.scripts.lint` → `npm run lint`; `Makefile` `lint`/`check` target → `make lint` / `make check` |
| Stack signals | Language/framework files for `domainSkills` mapping (see table below) |
| Versioning target | Presence of `.claude-plugin/plugin.json` — present → default to versioned; absent → suggest `versioning: false` (version-free) |
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

Present keys in these tiers: **Core → Testing → E2E → Preflight → Release → Enrichment**. Within each tier, show one key at a time (or a logical group). For every key:

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

**Tier: Preflight** (optional; present the inferred candidate, or an example such as `pre-commit run --all-files` if none was detected)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `preflightCmd` | "What command runs your project's fast pre-PR checks (lint, format, static analysis, security scan)? Runs after `/code-review`, before commit. (e.g. `pre-commit run --all-files`, `make lint`, `npm run lint`, `bundle exec standardrb && bundle exec brakeman -q`)" | Skip → "No preflight gate; CI-only lint/scan, caught on the PR instead of locally." |

**Tier: Release** (optional; default inferred from the `.claude-plugin/plugin.json` presence signal — present → versioned, absent → suggest `versioning: false`)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `versioning` | "Should I bump a plugin version on each PR via `.claude-plugin/plugin.json`? (Inferred default: file present → versioned; absent → suggest version-free.)" | Skip → key omitted → **versioned** (absent-means-versioned). For explicit version-free, choose the inferred `versioning: false` (the suggested value when no `.claude-plugin/plugin.json` exists). |

**Tier: Enrichment** (optional; show inferred values — accept with one keystroke)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `domainSkills` | "Any stack-specific skills the implementer should consult for citations? (e.g. `[\"maui-skills:*\"]` for MAUI)" | Skip → "Implementer relies on general docs + repo conventions only." |
| `nonNegotiables` | "Any hard constraints the implementer must honour? (framework versions, platform targets)" | Skip → "None recorded." |

### Phase 3 — Write and confirm

Assemble the collected keys into a valid JSON object and write to `<repo-root>/milestone-driver.json`. Omit any key the user skipped (do not write `null` or empty values). For `versioning`, omit it when versioned is chosen (the default) and write `versioning: false` only when version-free is chosen — the absent-means-default convention, same as the other optional keys. Print the final file contents so the user can verify.

Writing the file is sufficient for the mechanical gates to read it immediately this session — no commit is required for the gates to function.

```
milestone-driver.json written.

{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["skills/**", "agents/**", "hooks/**"],
  "implementerAgent": "milestone-driver:implementer"
}
```

### Phase 4 — Provision the runtime label taxonomy

After the profile is written (Phase 3) and before returning control, ensure all six runtime taxonomy labels exist in the target repo. This step runs both during direct `/milestone-driver:setup` invocations and any time setup is auto-invoked as a bootstrap sub-step.

#### Taxonomy (single source of truth)

| Label | Color (hex) | Description |
|---|---|---|
| `in progress` | `1D76DB` | Branch open with partial or parked work; not yet done |
| `blocked` | `B60205` | Can't proceed; waiting on something external (unmerged dependency, unverified E2E) |
| `needs design` | `5319E7` | Design direction required before building |
| `needs decision` | `D93F0B` | Non-design human decision required |
| `needs review` | `0E8A16` | Built; awaiting human review/merge (e.g. a UI PR awaiting visual sign-off) |
| `judgment call` | `FBCA04` | Borderline autonomous call — audit post-run |

#### Reconcile the existing `judgment-call` label

Run this step FIRST, before bulk provisioning. This repo (and consumer repos bootstrapped from it) may have a legacy label named `judgment-call` or `⚠ judgment-call`. Renaming it here preserves all existing issue/PR associations before the provisioning block below runs:

```
# If the legacy label exists, rename it (preserves all issue/PR associations):
gh label edit "judgment-call"    --name "judgment call" --color FBCA04
# or, if the legacy name includes the warning prefix:
gh label edit "⚠ judgment-call" --name "judgment call" --color FBCA04
```

If neither legacy label exists, the rename step errors harmlessly — no action needed. The provisioning block below then upserts the canonical color/description onto the renamed label, or creates `judgment call` fresh if no legacy existed. Either path is idempotent: running the full sequence again when `judgment call` already exists changes nothing.

#### Idempotent provisioning

Use `gh label create --force` for all six labels. The `--force` flag upserts: it creates the label if absent and updates color/description if the label already exists. Re-runs produce no duplicates. The `judgment call` row updates the just-reconciled label (or creates it fresh if no legacy existed).

```
gh label create "in progress"    --color 1D76DB --description "Branch open with partial or parked work; not yet done" --force
gh label create "blocked"        --color B60205 --description "Can't proceed; waiting on something external (unmerged dependency, unverified E2E)" --force
gh label create "needs design"   --color 5319E7 --description "Design direction required before building" --force
gh label create "needs decision" --color D93F0B --description "Non-design human decision required" --force
gh label create "needs review"   --color 0E8A16 --description "Built; awaiting human review/merge (e.g. a UI PR awaiting visual sign-off)" --force
gh label create "judgment call"  --color FBCA04 --description "Borderline autonomous call — audit post-run" --force
```

These commands are identical on bash and PowerShell 7+. Run them as a flat list (no shell loop required), which keeps them portable across both platforms.

#### Apply-time label helper (for consuming skills)

The `gh label create --force` idiom above is the **canonical apply-time label helper** that `triage` (#27), `solve-milestone` (#28), and `solve-issue` (#29) must call before applying any taxonomy label at runtime. Concretely: immediately before each `gh issue edit --add-label "<name>"` call, the consuming skill runs:

```
gh label create "<name>" --color <hex> --description "<desc>" --force
```

using the color and description from the taxonomy table above. This guarantees that a fresh consumer repo that has never run `/milestone-driver:setup` still receives the label on first use — no separate setup gate is required before labeling can work.

### Phase 5 — Return control

Return control to the caller immediately. Do **not** ask the user to re-run `/milestone-driver:solve-issue` or `/milestone-driver:solve-milestone`. The bootstrap is a sub-step, not a restart.

## Non-negotiables

- Never present a blank prompt. Every key shows either a detected default or an illustrative example.
- Skip always states its consequence. A user who skips knows exactly what gate or behavior is affected.
- Do not write a partial profile. Either all three required Core keys (`integrationBranch`, `protectedBranch`, `sourceGlobs`) are present, or no file is written. (`implementerAgent` is auto-filled; the optional keys may be omitted.)
- **Committing the profile:** writing the file is enough for the gates to read it this session. When `setup` is invoked **directly** (`/milestone-driver:setup`), suggest the user commit it (`git add milestone-driver.json && git commit -m "chore: add milestone-driver.json profile"`) so every clone and CI has it. When `setup` is auto-invoked **as a bootstrap sub-step**, leave the commit to the normal flow — do not create a commit on the current branch.
