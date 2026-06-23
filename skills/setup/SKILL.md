---
name: setup
description: This skill should be used when "milestone-driver:setup" is invoked directly, OR auto-invoked by solve-issue/solve-milestone when the driver profile is absent or missing a required Core key (`integrationBranch`, `protectedBranch`, or `sourceGlobs`). Guides an interactive first-run bootstrap that infers every profile key from repo signals, presents detected defaults with plain-language descriptions, lets the user accept/edit/skip optional keys (stating each skip-consequence), migrates a legacy root `milestone-driver.json` to `.milestone-config/driver.json` on first run and writes the assembled profile there, and returns control so the original task continues — no re-invocation needed.
---

# setup — first-run profile bootstrap

Generate or repair the driver profile through a guided, inference-first flow. Every key is presented with a plain-language description and a detected default. Optional keys state their skip-consequence. No blank prompts — if a default cannot be inferred, an example is shown.

The canonical profile location is `<repo>/.milestone-config/driver.json`. New profiles are always written there. An existing legacy root `<repo>/milestone-driver.json` is **migrated** (moved) to the canonical location by the migration preamble that runs before Phase 1 (see below), so Phase 3 only writes the assembled profile to the canonical path.

**After writing the file, return control to the caller** (solve-issue or solve-milestone) so the original task continues immediately. The user does not need to re-run the command.

## When this runs

- **Auto-invoked** by `solve-issue`/`solve-milestone` when the driver profile is absent or missing a required Core key (`integrationBranch`, `protectedBranch`, or `sourceGlobs`).
- **Direct invocation** (`/milestone-driver:setup`) when onboarding a new repo or repairing an existing profile.

**Migration preamble (run first, before Phase 1).** Run the idempotent migration preamble so Phase 1 pre-fills from the already-migrated canonical file: **Profile resolution & migration.** Resolve the profile: if `<repo>/.milestone-config/driver.json` exists, use it. Else if a legacy root `<repo>/milestone-driver.json` exists, migrate it first — `mkdir -p .milestone-config`; `git mv <repo>/milestone-driver.json <repo>/.milestone-config/driver.json` (when git-tracked, else plain `mv`) — then continue. Else (neither) it is a new project (this skill creates the canonical file in Phase 3). Idempotent: once `.milestone-config/driver.json` exists this is a no-op. When both files exist, `.milestone-config/driver.json` wins — no move, no overwrite, no deletion of the leftover root file. The transitional READ (canonical first, legacy root fallback) covers the gap before the move lands. Because this preamble runs first, by Phase 1 any existing profile is already at the canonical path `.milestone-config/driver.json`.

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
| Visual-capture indicators | A dev/test sign-in seam (e.g. a `/dev/sign_in` route, a `sign_in_as`/test-login helper), a server boot command (`bin/rails server`, `npm run dev`, a `Procfile` `web:` entry), and/or appearance signals (`dark:` Tailwind variants, a theme toggle, `prefers-color-scheme`) |
| Preflight (fast pre-PR checks) command | `.pre-commit-config.yaml` present → `pre-commit run --all-files`; `package.json` `.scripts.lint` → `npm run lint`; `Makefile` `lint`/`check` target → `make lint` / `make check` |
| Stack signals | Language/framework files for `domainSkills` mapping (see table below) |
| Versioning target | Presence of `.claude-plugin/plugin.json` — present → default to versioned; absent → suggest `versioning: false` (version-free) |
| Existing profile | Read `.milestone-config/driver.json` if present, else the legacy root `milestone-driver.json` — pre-fill any already-set keys |

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

Present keys in these tiers: **Core → Testing → E2E → Visual Capture → Preflight → Integration → Release → Enrichment → External integrations**. Within each tier, show one key at a time (or a logical group). For every key:

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

**Tier: Visual Capture** (optional; skip the whole tier if no visual-capture signals were detected in Phase 1 — present it only when a signal is detected, otherwise skip it silently, exactly as the E2E tier is skipped when no E2E signals are detected. The signals are listed in the Phase-1 detection row.)

The `visualCapture` block declares how an automated visual-capture flow boots a seeded/persona app server — a local app instance preloaded with test data and signed in as a test persona, so the capture flow can reach real authed screens — and what it captures. The three required keys (`serverCmd`, `readyUrl`, `signInPath`) must all be supplied for a usable block; the optional keys resolve to their defaults when skipped. Present the keys one at a time, with the detected default and the skip-consequence on the same line:

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `visualCapture.serverCmd` | "What command boots your seeded/test app server? (e.g. `bin/rails server -e test -p 3000`)" | Skip → required: skipping any of the three writes **no `visualCapture` block at all** — the visual gate stays at PR-open-for-human-test. See the Required-key rule below. |
| `visualCapture.readyUrl` | "What `/health`-style URL should the ready probe poll to know the server is up? (e.g. `http://127.0.0.1:3000/health`)" | Skip → required: skipping any of the three writes **no `visualCapture` block at all** — the visual gate stays at PR-open-for-human-test. See the Required-key rule below. |
| `visualCapture.signInPath` | "What is your passwordless test sign-in path, persona-templated? (e.g. `/dev/sign_in/{persona}`)" | Skip → required: skipping any of the three writes **no `visualCapture` block at all** — the visual gate stays at PR-open-for-human-test. See the Required-key rule below. |
| `visualCapture.persona` | "Which seeded persona should capture sign in as? (Default: `super-admin`, so every surface is reachable.)" | Skip → default `"super-admin"` used at runtime. |
| `visualCapture.viewports` | "Which named viewports should I capture? (Default: `{\"desktop\":{\"width\":1440,\"height\":900}}`. Detected an appearance/mobile signal? Add e.g. `\"mobile\":{\"width\":390,\"height\":844}`.)" | Skip → default desktop-only `{\"desktop\":{\"width\":1440,\"height\":900}}` used at runtime. |
| `visualCapture.appearances` | "Which appearances should I capture? (Default: `[\"light\"]`. Detected `dark:` variants / a theme toggle / `prefers-color-scheme`? Suggest `[\"light\",\"dark\"]`.)" | Skip → default single-appearance `[\"light\"]` used at runtime. |

**Required-key rule:** the three required keys (`serverCmd`, `readyUrl`, `signInPath`) must all be supplied together. If the user accepts the tier but skips any one of the three, write **no** `visualCapture` block (a node missing a required key is treated as absent + logged at runtime — there is no point writing it).

**Write rule:** accepting the tier writes only the keys the user supplied as a **sparse object** — omitted optional sub-keys (`persona`, `viewports`, `appearances`) are not written and resolve to their defaults at runtime, mirroring the `integrations.trello.lists` sparse-write rule. Skipping the tier writes **no** `visualCapture` block (no `null`, no empty object). Aborting mid-tier writes **no partial node** — consistent with setup's "do not write a partial profile."

**Tier: Preflight** (optional; present the inferred candidate, or an example such as `pre-commit run --all-files` if none was detected)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `preflightCmd` | "What runs your project's fast pre-PR checks (lint, format, static analysis, security scan)? Runs after `/code-review`, before commit. Give either an explicit command (e.g. `pre-commit run --all-files`, `make lint`, `npm run lint`, `bundle exec standardrb && bundle exec brakeman -q`), **or** the reserved value `github-ci` to auto-derive the gate from your GitHub Actions CI — front-running a cheap CI check locally without hand-transcribing it. With `github-ci`, optionally set `ciWorkflow` to one workflow-file basename (e.g. `ci.yml`) to narrow discovery; omit it to discover all PR-gating workflows." | Skip → "No preflight gate; CI-only lint/scan, caught on the PR instead of locally." |

**Tier: Integration** (optional; pure preference — no Phase-1 inference signal, since granularity is not detectable from repo signals. Show `"issue"` as the default/example.)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `integrationGranularity` | "How should built issues integrate — one PR per issue (default), or one PR per dependency wave?" | Skip → `issue` (each built issue gets its own PR / CI / merge). |

**Wave precondition prompt.** When — and only when — the user selects `"wave"`, fire this informational, **non-blocking** prompt (every wave selection, unconditionally — NOT gated on detected gate-strength):

> "Wave mode blocks the whole wave on one red CI run; it needs strong local gates. Is `preflightCmd` set, and is `unitTestCmd` your full suite (not a subset)? If you want partial-merge — the failing issue isolates, the rest merge — use `issue` (the default)."

`"full suite?"` is posed as a **question to the human**, NOT a check the skill performs — it is not machine-detectable at setup time. The prompt does **not** block: after the user acknowledges, `"wave"` is still written. Selecting `"issue"` (or accepting the default) shows no prompt.

**Write rule:** omit `integrationGranularity` from the written profile when `issue` is chosen (absent-means-issue, same convention as `versioning`); write `integrationGranularity: "wave"` only when wave is explicitly chosen.

**Tier: Release** (optional; default inferred from the `.claude-plugin/plugin.json` presence signal — present → versioned, absent → suggest `versioning: false`)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `versioning` | "Should I bump a plugin version on each PR via `.claude-plugin/plugin.json`? (Inferred default: file present → versioned; absent → suggest version-free.)" | Skip → key omitted → **opportunistic versioning**: the milestone title is parsed for a version; a miss **silently degrades to version-free** (never prompts). Choose explicit `versioning: true` to make a miss/ambiguity **prompt** the operator instead (or degrade with a warning when non-interactive). For explicit version-free, choose the inferred `versioning: false` (the suggested value when no `.claude-plugin/plugin.json` exists). |

**Tier: Enrichment** (optional; show inferred values — accept with one keystroke)

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `domainSkills` | "Any stack-specific skills the implementer should consult for citations? (e.g. `[\"maui-skills:*\"]` for MAUI)" | Skip → "Implementer relies on general docs + repo conventions only." |
| `nonNegotiables` | "Any hard constraints the implementer must honour? (framework versions, platform targets)" | Skip → "None recorded." |

**Tier: External integrations** (optional; presented **only on direct `/milestone-driver:setup` invocations** — suppressed when setup runs as an auto-bootstrap sub-step invoked by solve-issue/solve-milestone)

> **Auto-bootstrap suppression.** When setup is auto-invoked as a bootstrap sub-step (because a required Core key is missing), skip the External integrations tier entirely — never an interactive Trello question mid-run. The External integrations tier appears only when the user runs `/milestone-driver:setup` directly.

**Tier flow (direct invocation only):**

> **Re-run behavior.** If `integrations.trello` already exists in the profile (Phase 1 pre-filled it), show the existing `boardId` as the default in Step 3 (board picker) and the existing `lists` overrides as defaults in Step 4 (list mapping). The user can accept, edit, or re-configure — the full flow still runs, but with existing values pre-filled.

1. **Detect** Trello MCP availability by probing `mcp__trello__get_health`. If the tool is absent or errors:
   - Print: "Trello MCP (`@delorenj/mcp-server-trello`) not available in this session — skipping External integrations tier."
   - Move on to Phase 3.

2. **Offer** the integration with a plain-language label and skip-consequence:
   - Label: "Would you like to configure Trello board integration? (`@delorenj/mcp-server-trello` is available in this session.)"
   - Skip-consequence: "Skip → Trello integration not configured — all Trello sync steps skip silently in future runs."
   - On skip: move on to Phase 3.

3. **Board picker** (on accept): call `mcp__trello__list_boards` to fetch the user's boards. Present board names in a table for selection. Store the selected board's ID as `integrations.trello.boardId`.
   - **On failure (`list_boards` errors):** fall back to manual text entry — prompt: "Enter your Trello board ID directly:" and use the entered value as `boardId`. (The board ID is visible in the Trello board URL.)

4. **List mapping** (after board selection):
   - Attempt to fetch the board's actual lists via `mcp__trello__get_lists`.
   - **On success:** present the board's actual list names for the queue / inProgress / inReview mapping, with the three defaults (`"Queue"`, `"In Progress"`, `"In Review"`) shown as suggestions.
   - **On failure (get_lists errors):** fall back to manual text entry — prompt for each of the three list names using the defaults as suggestions. Note that wrong names are tolerated: the runtime skill auto-creates any missing list (Wave-2 behavior).
   - Defaults accepted → **omit `lists` from the written profile** (absent-means-default, same convention as `versioning`). Only overridden sub-keys are written (sparse object — e.g., only `"queue": "Backlog"` if only queue was changed).
   - User aborts at any point (mid-board-pick or mid-list-mapping) → write no partial `integrations.trello` node (consistent with "do not write a partial profile"). Either the full `boardId` (and any overridden list names) is written, or nothing is written — never a partial node.

| Key | Plain-language label | Skip-consequence |
|---|---|---|
| `integrations.trello.boardId` | "Which Trello board should I track milestone work on? (Select from your boards above.)" | Skip → no Trello integration configured. |
| `integrations.trello.lists.queue` | "What is your 'queue' list name? (Default: `Queue`)" | Skip → default `"Queue"` used at runtime. |
| `integrations.trello.lists.inProgress` | "What is your 'in progress' list name? (Default: `In Progress`)" | Skip → default `"In Progress"` used at runtime. |
| `integrations.trello.lists.inReview` | "What is your 'in review' list name? (Default: `In Review`)" | Skip → default `"In Review"` used at runtime. |

### Phase 3 — Write and confirm

The canonical profile location is `<repo-root>/.milestone-config/driver.json`. The migration preamble (run before Phase 1) has already relocated any legacy root profile, so by Phase 3 there is no migration left to do here — there are only two cases:

- **New project** — neither file present (the preamble found nothing to migrate): create the `.milestone-config/` directory (`mkdir -p .milestone-config`) and write the assembled profile to `.milestone-config/driver.json`. Never write a fresh profile to the root.
- **Existing profile** — `.milestone-config/driver.json` present (the preamble used or migrated it): write the assembled profile to `.milestone-config/driver.json` in place. If a leftover root `milestone-driver.json` is also present (the both-present case the preamble left untouched), `.milestone-config/driver.json` wins: do **not** overwrite the canonical file from the root, and do **not** delete the leftover root file (no destructive surprise — the operator removes it; no `.gitignore` change is made).

Assemble the **full** profile object — every key, both the Phase-1 pre-filled values and the keys the user accepted or edited in Phase 2 — into a valid JSON object, and write that complete object to `.milestone-config/driver.json`. **Drop no accepted key:** a key that was pre-filled in Phase 1 and left unedited in Phase 2 is still written. Omit only a key the user explicitly skipped (do not write `null` or empty values for it). For `versioning`, omit it when versioned is chosen (the default) and write `versioning: false` only when version-free is chosen — the absent-means-default convention, same as the other optional keys. For `integrationGranularity`, follow the same absent-means-default convention: omit it when `issue` is chosen (the default) and write `integrationGranularity: "wave"` only when wave is explicitly chosen. Print the final file contents so the user can verify.

Writing the file is sufficient for the mechanical gates to read it immediately this session — no commit is required for the gates to function.

```
.milestone-config/driver.json written.

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

## Output style

Be concise — report status and outcomes flatly, no wall-of-text. Present steps, gates, lists, and options as **tables**, not inline prose. Mark anything that needs a human with 🔴. (Mirrors the agents' communication-style contract.)

## Non-negotiables

- Never present a blank prompt. Every key shows either a detected default or an illustrative example.
- Skip always states its consequence. A user who skips knows exactly what gate or behavior is affected.
- Do not write a partial profile. Either all three required Core keys (`integrationBranch`, `protectedBranch`, `sourceGlobs`) are present, or no file is written. (`implementerAgent` is auto-filled; the optional keys may be omitted.)
- **Committing the profile:** writing the file is enough for the gates to read it this session. When `setup` is invoked **directly** (`/milestone-driver:setup`), suggest the user commit it (`git add .milestone-config/driver.json && git commit -m "chore: add milestone-driver profile"`) so every clone and CI has it; when a legacy root `milestone-driver.json` was migrated, the `git mv` is already staged and is committed by the same flow (the move and the new file land in one commit). When `setup` is auto-invoked **as a bootstrap sub-step**, leave the commit to the normal flow — do not create a commit on the current branch.
