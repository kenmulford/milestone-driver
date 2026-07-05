# milestone-driver — project profile schema

Each consuming repository supplies a committed profile that adapts the generic
engine to that repo's stack, branch model, and test commands. The plugin's
skills and hooks read this file; nothing in the engine is hard-coded to a
particular stack.

> **See also:** [the layered gating model](../README.md#the-layered-gating-model) — how `uiSurfaceGlobs` drives the design-lens triage and the visual-review gate — and [consumer setup](consumer-setup.md) for the run flow these keys feed.

## Location

The canonical profile location is:

```
<repo-root>/.milestone-config/driver.json
```

This is the single canonical home for the driver profile (the suite-wide
`.milestone-config/` config directory that sibling plugins such as
`milestone-feeder` also read from).

**Transitional root read.** For backward compatibility during the upgrade
window, the skills and hooks resolve the profile by reading
`.milestone-config/driver.json` first, and falling back to the legacy root
`<repo-root>/milestone-driver.json` when the canonical file is absent — so a
repo that upgraded but has not yet migrated keeps its gates firing exactly as
before.

**Migration ownership (move, not coexistence).** This is a migration, not
permanent coexistence — but the `git mv` is performed **only by the commands
that have a clean commit path** to `integrationBranch`, so the relocation always
lands in a commit rather than sitting uncommitted on a shared branch:

- **`setup`** migrates the legacy root `milestone-driver.json` to
  `.milestone-config/driver.json` (its migration preamble, before Phase 1) and
  writes the assembled profile there — committed per its existing convention.
- **`solve-issue`** migrates on the **feature branch** (step 3.5, after the
  clean-tree check and branch cut), so the move rides that issue's PR.
- **`solve-milestone`** does **not** `git mv` on its own (orchestrator) working
  tree — that would strand an uncommitted move on `integrationBranch`. It reads
  transitionally and lets the **first `solve-issue` it dispatches** perform the
  move (which rides that issue's PR). An all-parked milestone defers the move to
  the next building run; the transitional read covers the gap.
- **`triage`** is read-only: it mutates nothing, so it performs **no** migration
  move. On detecting the legacy layout it may surface a one-line note ("legacy
  profile detected — will migrate on the next build/setup") but does not move the
  file.
- **Gate hooks** stay non-mutating — they perform the **transitional read only**
  (the read covers the gap before the move lands).

The move is idempotent: once `.milestone-config/driver.json` exists every
command's resolution is a plain read and no move occurs. New projects always
create the profile at `.milestone-config/driver.json`; a fresh profile is never
written to the root.

**Precedence (both present).** If both files exist (a half-migrated or
manually-edited edge), `.milestone-config/driver.json` wins. The migration step
never overwrites an existing `.milestone-config/driver.json` and never
auto-deletes the leftover root `milestone-driver.json` (no destructive
surprise): the leftover stays tracked but unused by resolution, and the operator
removes it. No `.gitignore` change is made.

**Commit it.** The mechanical gates read the profile, so it must be present in
every clone for the gates to behave identically for every contributor and on CI.

## Design principle

Keep it minimal and consumer-driven. **Three keys are required** (`integrationBranch`, `protectedBranch`, `sourceGlobs`); the agent keys `implementerAgent`, `triageAgent`, `designReviewAgent`, and `coherenceReviewAgent` are **default-filled** (they default to `milestone-driver:implementer`, `milestone-driver:triage-reviewer`, `milestone-driver:design-reviewer`, and `milestone-coherence-reviewer:coherence-reviewer`) so a profile may omit them. The first three resolve to always-on bundled agents; `coherenceReviewAgent`'s default points at the separate milestone-coherence-reviewer companion plugin, so its post-build coherence pass runs only when that companion is installed (absent → silently skipped). All other keys are optional. **New keys are added only when a real second consumer needs them — never speculatively.**

> **Risk classification needs no profile key.** The `light` / `heavy` build profile is computed automatically by triage from observable inputs (gap types, dependency edges, issue labels, body signals) and is label-overridable per issue (`risk:light` / `risk:heavy`). No profile key is required or introduced.

## Key tiers

| Tier | Keys | Required? |
|---|---|:---:|
| **Core** (orchestration + safety) | `integrationBranch`, `protectedBranch`, `sourceGlobs` | ✅ required in file |
| **Core** (default-filled) | `implementerAgent`, `triageAgent`, `designReviewAgent`, `coherenceReviewAgent` | optional in file (auto-filled) |
| **Testing** | `unitTestCmd` | Optional |
| **E2E** | `e2eTestCmd`, `e2eEnv` | Optional |
| **Visual capture** | `visualCapture` (`.serverCmd`, `.readyUrl`, `.signInPath`, `.persona`, `.viewports`, `.appearances`) | Optional |
| **Preflight** | `preflightCmd`, `ciWorkflow` | Optional |
| **Integration** | `integrationGranularity` | Optional |
| **Execution** | `parallel`, `maxParallelWorkers` | Optional |
| **Triage / Visual** | `uiSurfaceGlobs` | Optional |
| **Release** | `versioning` | Optional |
| **Enrichment** | `domainSkills`, `nonNegotiables`, `projectDocs` | Optional |
| **External integrations** | `integrations.trello` | Optional |

**Note on safety keys:** `integrationBranch`, `protectedBranch`, and `sourceGlobs` are required for safe operation. The hooks fail-open when they are absent (a robustness measure so a hook bug never bricks a repo), but that fail-open is **not** a statement of optionality — without these keys the safety guarantees do not hold. `implementerAgent`, `triageAgent`, and `designReviewAgent` have bundled defaults (`milestone-driver:implementer`, `milestone-driver:triage-reviewer`, `milestone-driver:design-reviewer`) and are auto-filled by the bootstrap; omitting them from the profile is valid and common. `coherenceReviewAgent` is also default-filled (`milestone-coherence-reviewer:coherence-reviewer`), but unlike the three above it points at a separate companion plugin: its post-build coherence pass runs only when the milestone-coherence-reviewer companion is installed, and is silently skipped otherwise (absent-means-skip).

## Keys

| Key | Type | Tier | Plain-language description | Required? |
|---|---|---|---|:---:|
| `integrationBranch` | string | Core | Which branch should PRs be opened into and work merged onto? (e.g. `develop`) | ✅ |
| `protectedBranch` | string | Core | Which branch must never be pushed or PR'd to? (Your release / default branch, e.g. `main`) | ✅ |
| `sourceGlobs` | string[] | Core | Which path patterns are "source" that only the implementer subagent may edit? (e.g. `["src/**","tests/**"]`) | ✅ |
| `implementerAgent` | string | Core | Which agent authors the code? Default: `milestone-driver:implementer` (auto-filled; rarely overridden) | default-filled |
| `triageAgent` | string | Core | Which agent reviews issues for design gaps + dependency ordering (architect lens)? Default: `milestone-driver:triage-reviewer` (auto-filled; rarely overridden) | default-filled |
| `designReviewAgent` | string | Core | Which agent reviews UI-touching issues for UX gaps (front-end lens)? Default: `milestone-driver:design-reviewer` (auto-filled; rarely overridden) | default-filled |
| `coherenceReviewAgent` | string | Core | Which agent runs the read-only post-build coherence pass before the final `/code-review`? Default: `milestone-coherence-reviewer:coherence-reviewer`. Default-filled; the pass runs only when the coherence-reviewer is present AND configured, and is silently skipped otherwise (absent-means-skip). **Unlike `implementerAgent` / `triageAgent` / `designReviewAgent` — always-on bundled agents — this agent ships in the separate milestone-coherence-reviewer companion plugin, so the pass runs only when that companion is installed; absent → silently skipped.** | default-filled |
| `unitTestCmd` | string | Testing | What command runs the unit tests? Absent → no unit gate; implementer verifies behavior another way. | — |
| `e2eTestCmd` | string | E2E | What command runs the end-to-end / UI tests? Absent → no E2E gate. | — |
| `e2eEnv` | object | E2E | Device/endpoint for the E2E runner (Appium, Selenium, Playwright), e.g. `{ "endpoint": "127.0.0.1:4723", "device": "Android emulator (AVD)" }`. | — |
| `visualCapture` | object | Visual capture | Visual-capture render seam — declares how an automated flow boots a seeded/persona app and what it captures. Presence = enabled; absence = skip (absent-means-skip, same convention as `unitTestCmd` / `integrations.trello`). When present, `serverCmd`, `readyUrl`, and `signInPath` are required; a node missing any of them is treated as absent with a one-line misconfiguration log. Absent → behavior byte-unchanged from the current no-`visualCapture` profile. | — |
| `visualCapture.serverCmd` | string | Visual capture | Command that boots the seeded/persona app server (read by the render daemon, `scripts/render-daemon.sh:94`). **Required when the `visualCapture` node is present**; a node missing it is treated as absent + logged. | — |
| `visualCapture.readyUrl` | string | Visual capture | The full `/health`-style URL the ready probe polls to know the server is up (read by the render daemon, `scripts/render-daemon.sh:95`), e.g. `http://127.0.0.1:3000/health`. **Required when present**; missing → node treated as absent + logged. | — |
| `visualCapture.signInPath` | string | Visual capture | The passwordless test sign-in seam path, persona-templated, e.g. `/dev/sign_in/{persona}`. **Required when present**; missing → node treated as absent + logged. | — |
| `visualCapture.persona` | string | Visual capture | Which seeded persona to sign in as. Optional; default `"super-admin"` (so every surface is reachable). Absent → default used at runtime. | — |
| `visualCapture.viewports` | object | Visual capture | Named viewports to capture, each a `{ "width": <px>, "height": <px> }` object. Optional; default `{ "desktop": { "width": 1440, "height": 900 } }` (desktop-only). Absent → desktop-only default used. | — |
| `visualCapture.appearances` | string[] | Visual capture | Appearances to capture (`"light"`, `"dark"`). Optional; default `["light"]`. Absent → single-appearance (`["light"]`) default used. | — |
| `preflightCmd` | string | Preflight | Either a single literal command that runs your project's fast pre-PR checks (lint, format, static analysis, security scan), **or** the reserved sentinel `"github-ci"` which auto-derives the checks from your GitHub Actions CI (see below). CI runs them regardless; this just surfaces a red result earlier. Absent → preflight gate skipped cleanly. Run after `/code-review`, before commit. | — |
| `ciWorkflow` | string | Preflight | Only meaningful with `preflightCmd: "github-ci"`. The basename of one workflow file (e.g. `"ci.yml"`) to narrow CI discovery to — use when the zero-config heuristic picks the wrong or too-broad workflow. Absent → discover **all** PR-gating workflows. | — |
| `integrationGranularity` | `"issue" \| "wave"` (string enum) | Integration | How should built issues integrate? Default `"issue"` — each built issue gets its own PR → CI → merge. `"wave"` — a whole Wave integrates on one branch `wave/<milestone>-w<N>` → one PR → one CI run. | — |
| `parallel` | boolean | Execution | Should `solve-milestone` build a Wave's mutually-independent issues in parallel? Parallel is the default. **absent** → not yet decided (parallel *unless* `unitTestCmd` is set, in which case the run-start DB-hazard interview decides and records its answer here). **`true`** → force parallel (interview suppressed; operator asserts per-worker isolation). **`false`** → force sequential (standing opt-out). A physical permission-allowlist gap overrides `true` down to sequential (hard barrier). See the note below. | — |
| `maxParallelWorkers` | integer | Execution | The per-Wave concurrent-worker cap — how many independent issues build at once, overriding the previously-hardcoded 4. Optional, **default 4**; omit to get 4, set only to override. Absent or invalid (non-integer, `< 1`) → 4 (fail-open, never an error). Orthogonal to `parallel` (whether vs. how wide); no effect on a sequential run. See the note below. | — |
| `uiSurfaceGlobs` | string[] | Triage / Visual | Which path patterns mark UI surfaces? Drives `design-reviewer` dispatch (triage) and the visual-review gate ([#18](https://github.com/kenmulford/milestone-driver/issues/18)), e.g. `["PrayerApp/Views/**","**/*.xaml"]`. Absent → no design-lens review and no visual gate. | — |
| `versioning` | boolean | Release | Should each PR bump a plugin version? **`false`** → version-free: no extraction, no prompt, no bump (the milestone title need not be a version). **absent (default)** → opportunistic: `solve-milestone` runs the deterministic extractor (`scripts/extract-version.*`, issue #158) against the milestone title (description as fallback); a parseable version is used, otherwise the run silently degrades to version-free with a logged note — never prompts. **`true`** (explicit opt-in) → same extraction, but a miss or an ambiguous title **prompts** the operator (or, under `MILESTONE_DRIVER_NONINTERACTIVE=1`, degrades with a loud warning). This `absent` vs `true` split is intentional: `true` asserts intent to version, so a missing version is treated as a likely misconfiguration. Fail-safe: in versioned mode, a missing `.claude-plugin/plugin.json` degrades to version-free with a logged note rather than failing. | — |
| `domainSkills` | string[] | Enrichment | Stack-specific skill identifiers the implementer consults for citations (e.g. `["maui-skills:*"]`). Absent → general docs + repo conventions only. | — |
| `nonNegotiables` | string[] | Enrichment | Hard constraints the implementer must honour (framework versions, platform targets). Absent → none recorded. | — |
| `projectDocs` | string | Enrichment | Where the project's standing docs live, for grounding (e.g. `.project/`). Default `.project/`; absent-means-default. Absent directory → consumers proceed with no project grounding, no error. | — |
| `integrations.trello` | object | External integrations | Trello board integration node. Presence = enabled; absence = skip (absent-means-skip, same convention as `unitTestCmd`). When present, `boardId` is required; a node without `boardId` is treated as absent with a one-line misconfiguration log. | — |
| `integrations.trello.boardId` | string | External integrations | Trello board ID to track work on. Required when the `integrations.trello` node is present. | — |
| `integrations.trello.lists.queue` | string | External integrations | Name of the "queue" list on the board. Default: `"Queue"`. Case-sensitive — must match the Trello list name exactly. A missing list is auto-created at runtime (Wave-2 behavior, deferred to the trello-sync conventions issue). | — |
| `integrations.trello.lists.inProgress` | string | External integrations | Name of the "in progress" list on the board. Default: `"In Progress"`. Case-sensitive — must match the Trello list name exactly. A missing list is auto-created at runtime (Wave-2 behavior, deferred to the trello-sync conventions issue). | — |
| `integrations.trello.lists.inReview` | string | External integrations | Name of the "in review" list on the board. Default: `"In Review"`. Case-sensitive — must match the Trello list name exactly. A missing list is auto-created at runtime (Wave-2 behavior, deferred to the trello-sync conventions issue). | — |

The implementer also uses any docs MCP available in the environment (e.g. Microsoft Learn for .NET) — these are environment-provided, **not required or installed by this plugin**.

**Note on `uiSurfaceGlobs` and the visual-review gate.** `uiSurfaceGlobs` drives two procedural (skill-level) phases — design-lens triage (`design-reviewer`) and the post-build visual-review gate (#18) — not a mechanical hook. Triage reviews the *recorded design + source*, so it needs **no render capability**. Screenshot capture for the visual gate does: it requires a render capability, which is the `visualCapture` seam (documented below). When `visualCapture` is **absent, the visual gate degrades to PR-open-for-human-test** — it never fails the build and never auto-merges a UI issue. When `uiSurfaceGlobs` itself is absent, the repo has no UI surfaces: no design-lens review, no visual gate, and logic-only PRs auto-merge normally. See [the layered gating model](../README.md#the-layered-gating-model) for the three-layer model these keys participate in.

**Note on `visualCapture`.** `visualCapture` is the dedicated render-capability seam for the visual gate — the object-valued, optional render-capability declaration the gate note above points at. It is shaped on `e2eEnv` (an object-valued optional key) and mirrors the present/absent + sparse-optional-write conventions of `integrations.trello`; note that a *missing required* sub-key disables the whole block (unlike trello's optional-list override). With that one difference flagged:

This block is a web/HTTP-server-boot + URL-polling shape (`serverCmd` boots a server, `readyUrl` polls it); native UI stacks (MAUI, WPF, and similar) have no server or URL to poll and should omit `visualCapture` entirely, relying on the documented behavior above — "the visual gate degrades to PR-open-for-human-test".

- **Absent block → byte-unchanged.** When `visualCapture` is absent, behavior is identical to today's no-`visualCapture` profile — no new gate, no prompt, no error (absent-means-skip, the same convention as `unitTestCmd` / `integrations.trello`).
- **Present but missing a required sub-key → two layers, two behaviors.** A `visualCapture` node present but missing `serverCmd`, `readyUrl`, or `signInPath` is handled differently by the two layers that touch it, and it matters which:
  - **The visual-capture flow/gate (solve-issue step 7, built by #210)** treats the incomplete block as *not configured* and degrades to the PR-open-for-human-test note — the run never fails and a UI issue never auto-merges, mirroring the `integrations.trello`-without-`boardId` graceful-degrade rule.
  - **The render daemon (#208) itself fails loud** if it is driven with an incomplete block: `read_profile` exits nonzero (`read_profile || exit 2`) with `render-daemon: profile is missing visualCapture.serverCmd and/or visualCapture.readyUrl` when either of the two keys it reads is empty (`scripts/render-daemon.sh:97-100,218`, `scripts/render-daemon.ps1:98,260`). The daemon halts rather than silently mis-rendering, so the misconfiguration surfaces.
  In short: the gate degrades gracefully; the daemon, if invoked directly with a bad block, halts loudly. There is no path that silently captures the wrong thing.
- **Present with only optional sub-keys omitted → resolves to defaults.** A block carrying the three required keys but omitting `persona`, `viewports`, and/or `appearances` is valid: each omitted optional sub-key resolves to its default at runtime (`persona` → `"super-admin"`, `viewports` → `{ "desktop": { "width": 1440, "height": 900 } }`, `appearances` → `["light"]`).

**Required vs optional sub-keys.** Required-when-present: `serverCmd`, `readyUrl`, `signInPath`. Optional-with-default: `persona` (`"super-admin"`), `viewports` (`{ "desktop": { "width": 1440, "height": 900 } }`), `appearances` (`["light"]`). The two keys the render daemon (#208) consumes are `serverCmd` and `readyUrl` (`scripts/render-daemon.sh:94-95`); `signInPath`, `persona`, `viewports`, and `appearances` are read by the capture consumer (#210). **Sparse-write shape:** a block written with optional sub-keys at their defaults stores only the keys actually supplied (the same sparse-object rule as `integrations.trello.lists`) — omitted optional sub-keys are not written and resolve to their defaults at runtime.

**Worked example.** A full, valid `visualCapture` block:

```json
{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["app/**", "spec/**"],
  "uiSurfaceGlobs": ["app/views/**", "app/components/**"],
  "visualCapture": {
    "serverCmd": "bin/rails server -e test -p 3000",
    "readyUrl": "http://127.0.0.1:3000/health",
    "signInPath": "/dev/sign_in/{persona}",
    "persona": "super-admin",
    "viewports": {
      "desktop": { "width": 1440, "height": 900 },
      "mobile": { "width": 390, "height": 844 }
    },
    "appearances": ["light", "dark"]
  }
}
```

A minimal valid block supplies only the three required keys and lets the optional sub-keys resolve to their defaults:

```json
{
  "visualCapture": {
    "serverCmd": "bin/rails server -e test -p 3000",
    "readyUrl": "http://127.0.0.1:3000/health",
    "signInPath": "/dev/sign_in/{persona}"
  }
}
```

**Note on `versioning` and version-free mode.** Both `absent` and `true` are **versioned** — `solve-milestone` runs the deterministic extractor (`scripts/extract-version.*`, issue #158) against the milestone title (description as fallback) and each issue's PR bumps `.claude-plugin/plugin.json` to the resolved version (`solve-issue` step 6.4) — but they differ on a **miss**: with `versioning` **absent** (the default) a missing or ambiguous version silently degrades to version-free with a logged note (opportunistic — never prompts); with explicit `versioning: true` it **prompts** the operator (or, under `MILESTONE_DRIVER_NONINTERACTIVE=1`, degrades with a loud warning). Set `versioning: false` for a repo that does not keep its version in `plugin.json` (or does not want a per-PR bump) — **version-free mode**: `solve-milestone` skips version determination entirely (no extraction, no prompt; the milestone title need not be a version), `solve-issue` skips the bump, and the PR's Code Review section is annotated "version-free — no version bump." **Fail-safe degradation:** in versioned mode, if `.claude-plugin/plugin.json` does not exist, the run **does not fail** — `solve-issue` step 6.4 degrades to version-free with a one-line logged note. So the worst case for a misconfigured versioned repo is a skipped bump, never a halted run.

**Note on `parallel` and execution mode.** `parallel` is the standing control for `solve-milestone`'s execution mode — parallel is the default, and this key is how a repo persists or forces a choice. Its three states are **not** a plain on/off:

- **absent = "not yet decided"** (explicitly **not** "off"). Parallel is the intended default *unless* `unitTestCmd` is set — in which case, on the first `solve-milestone` run, the run-start DB-hazard interview asks whether the test harness is safe to run concurrently and **records its answer here** (`true` or `false`) so the question is asked once. With no `unitTestCmd` there is no shared-service hazard, no question, and the key stays absent while the run goes parallel.
- **`true` = force parallel.** The interview is suppressed; the operator asserts per-worker test isolation (or accepts the risk).
- **`false` = force sequential.** The standing opt-out; the interview is suppressed and every run is sequential.

**Barrier precedence (hard override).** `parallel: true` is an operator *assertion*, not a guarantee. A **physical** barrier — a permission-allowlist gap where the session has not allow-listed a tool the background workers need — still overrides `true` **down to sequential**. No config can grant a tool the session has not allow-listed, so this is a hard override, **not** a soft "may run sequentially."

**Write-rule deviation.** Unlike `versioning` and `integrationGranularity`, which follow the **omit-the-default** convention (an omitted key means "use the default"), `parallel` records an **explicit boolean whenever a decision is made** — both `true` and `false` are written (by the `setup` question or the run-start interview). It is omitted **only** when no decision was made (no `unitTestCmd`, so no hazard and no question); omitting it after a decision would re-fire the interview on the next run. This deliberate deviation sits **opposite** its companion `maxParallelWorkers`, which *does* follow omit-the-default (next note) — the two new keys sit on opposite sides of this convention by design. The run-start mode-resolution cascade that reads each value (the interview, the non-interactive degradation, the permission gate) lives in `solve-milestone` and is cross-referenced, not duplicated, here — see `solve-milestone`'s **Resolve execution mode** Before-starting step and `### Parallel mode — Phase 1: concurrent worker dispatch` for the mechanics.

**Note on `maxParallelWorkers` and the concurrency cap.** `maxParallelWorkers` tunes *how wide* a parallel run fans out — the maximum number of mutually-independent issues `solve-milestone` builds concurrently within a Wave (each in its own git worktree). It caps the rolling dispatch window that was previously a hardcoded 4.

- **Follows the omit-the-default convention** — the **opposite** of its companion `parallel`. Omit `maxParallelWorkers` to get **4**; write it **only** to override. Side by side: `maxParallelWorkers` omitted → 4 (omit-the-default, like `versioning` / `integrationGranularity`); but `parallel` writes an explicit boolean on any decision (the write-rule deviation above). The two new keys deliberately sit on opposite sides of this convention.
- **Fail-open.** An **absent or invalid** value — non-integer, or `< 1` — resolves to the default **4**, never an error: the run degrades to the safe default rather than halting.
- **Orthogonal to `parallel`.** `parallel` decides *whether* to parallelize; `maxParallelWorkers` decides *how wide*. It has **no effect on a sequential run** (which builds one issue at a time regardless of the cap). `solve-milestone`'s Phase-1 rolling-window dispatch reads this value — see `### Parallel mode — Phase 1: concurrent worker dispatch` for the mechanics.

**Note on `projectDocs`.** `projectDocs` only names **where the project's standing docs live**, for grounding — it adds no new hard dependency. Default `.project/`; **absent-means-default** (an omitted key resolves to `.project/`, the same convention as the other optional keys). When the resolved `.project/` directory itself is absent, consumers **proceed with no project grounding — no error, no halt**: the key never makes the docs a precondition, it only points at them when they exist. This mirrors the feeder's identically-named `projectDocs` key (string, default `.project/`), so a repo consumed by both tools reads one value from one place.

**Note on bootstrapper-owned keys (`stack`, `stackVersionFile`).** A `driver.json` written by `milestone-bootstrapper` may carry keys this schema does **not** list — currently `stack` and `stackVersionFile`. These are **bootstrapper-owned**: the bootstrapper's own CI-workflow emitter writes them and reads them back to scaffold a per-stack CI setup step, and **milestone-driver neither reads nor validates them** (`solve-issue` reads only the keys above; any unrecognized key is ignored). They are deliberately kept out of this schema because a schema documents what *its* plugin consumes — their canonical definition lives in milestone-bootstrapper's `SPEC.md §6.1`. No driver change is needed to operate on a repo whose `driver.json` carries them. (Contrast `projectDocs`, which *is* in this schema because the driver consumes it.)

**Note on `preflightCmd`.** **CI is the authority; `preflightCmd` is a latency optimization.** Your CI runs lint / format / static-analysis / security checks on the PR regardless, so this local gate catches nothing CI would miss — its only value is moving a red result earlier, before the PR, to dodge the fix → push → wait round trip. `solve-issue` runs `preflightCmd` at the end of the `/code-review` resolve loop (step 6.1) — after that loop converges and before the step-6.4 version bump and step-6.5 commit; a non-zero exit re-dispatches the implementer with the failing command + output (its own "at most 2" cap, like every other gate), and a non-converging gate parks `blocked` — behaving like the unit / E2E gates. **Point it at the *fast* gates.** The heavy test suite is already covered by `unitTestCmd`, so a consumer who folds the full suite into `preflightCmd` just pays for it twice — this is guidance, not policed. Example commands: `pre-commit run --all-files`, `make lint`, `npm run lint`, `bundle exec standardrb && bundle exec brakeman -q`.

**CI-derived preflight (`preflightCmd: "github-ci"`).** Instead of a literal command, set `preflightCmd` to the reserved sentinel `"github-ci"` to **auto-derive** the preflight gate from your GitHub Actions CI — so a cheap CI check (e.g. `npm audit --omit=dev --audit-level=high`) is front-run locally before the PR without hand-transcribing it. The literal-command and absent-`preflightCmd` behaviors are unchanged; `"github-ci"` is mutually exclusive with a literal command (if a check matters it is already in CI). A behavior-identical script pair `scripts/ci-preflight-steps.{sh,ps1}` reads the local `.github/workflows/*.yml` (it never calls the network; **no new tool dependency** — no `yq`/`act`/`python`), discovers the workflows triggered on `pull_request` (or push to `integrationBranch`), and emits each job's `run:` steps in order. **Skip-rules** (skipped + logged): `uses:` steps, steps referencing secrets / service containers / deploy-publish, steps with `${{ }}` interpolation in the `run:`, and steps with a step-level `if:`; `working-directory` is honored, and a `continue-on-error: true` step is emitted but flagged so its failure never parks the issue. `solve-issue` step 6.1 then runs the emitted steps through the existing tool-presence-guard → run → re-dispatch (cap 2) → park-`blocked` machinery, with **loud coverage logging** ("mirrored N checks, skipped M") and a **silent-under-run guard**: a PR-gating workflow that yields zero runnable steps (e.g. its real checks live behind a `uses:` reusable workflow) is surfaced as a **visible warning, not a clean pass**. Narrow to one workflow with the optional `ciWorkflow` key. **Documented limitations (not built — CI stays the authority):** it does not recurse into `uses:` reusable/composite workflows (it warns instead), does not expand `matrix`, does not replicate the CI runner (`act`), and covers GitHub Actions only. Residual false-failure classes are acceptable because a park is recoverable: network-dependent audits, local-vs-CI version skew, and missing-lockfile / `node_modules` state. **Known parallel-execution limitation:** there is no per-step static-vs-port-binding classification (deferred), so on the default parallel path a CI-derived **server-starting** gating step runs inside every concurrent worker and contends for the same port — scope it out with `ciWorkflow` (or run the milestone sequentially via `parallel: false`) when CI has server-starting gating steps. **`continue-on-error` is honored at step scope only** — a job-level `continue-on-error: true` is not modeled, so a failing step in such a job parks on a real failure (job-scope handling deferred).

**Note on `integrationGranularity` and wave granularity.** Default (absent or `"issue"`) is **today's model, byte-unchanged**: each built issue opens its own PR → its own CI run → merges individually. Set `integrationGranularity: "wave"` for a repo with **long or expensive CI**, where O(issues) per-issue CI runs are wasteful: a whole dependency Wave integrates on one branch `wave/<milestone>-w<N>`, opens **one** wave PR → `integrationBranch`, and runs **one** CI run for the assembled Wave — trading O(issues) CI runs for O(waves), and CI-validating the *assembled* Wave (catching integration-level issues an isolated per-issue build misses). The merge-tail **mechanism** (#73 — merge-in + re-verify against accumulated state + bounded auto-resolve) is **unchanged**; only the **target** (the wave branch instead of `integrationBranch`) and **PR-opening** (one wave PR instead of per-issue PRs) differ. **Logic-only carve-out:** the visual-review gate is per-UI-issue, so UI issues in a Wave stay **per-issue / held** (each opens its own `needs review` PR for human visual sign-off); only the logic issues join the wave branch. **Trade-off:** one red wave-PR CI blocks the whole Wave — acceptable because the strong local gates (unit + static preflight + `/code-review` + the tail's re-verify) catch most failures before CI; CI is the backstop. **Not** for repos with weak local gates. **Orthogonal to execution mode (the `parallel` key)** (which is *how* issues build; this is *how* they integrate) — the two combine or apply independently. See `solve-milestone`'s `### Integration granularity (issue vs wave)` for the orchestrator mechanics, and the **Integration** tier of `skills/setup/SKILL.md` (Phase 2) for the setup-time selection step — where choosing `"wave"` fires the non-blocking precondition prompt about local-gate strength.

**Note on execution mode (parallel by default).** Execution mode is **not** a run argument — there is no `--parallel` flag and no "in parallel" trigger. Parallel is the **default** mode for `solve-milestone`: it builds the mutually-independent issues within a Wave concurrently, each in its own git worktree, then integrates them through the serial verified merge tail. At run start `solve-milestone` resolves the mode **once**, through a **barrier cascade**, and drops to **sequential** only when a barrier is present — a `parallel: false` opt-out, a permission-allowlist gap (which forces synchronous, sequential dispatch), or an unresolved test-isolation hazard when `unitTestCmd` is set and `parallel` is absent (the one-time DB-hazard interview). The standing control is the **`parallel` profile key** (above), not a flag. Concurrency is **capped at 4 workers per Wave by default**, now tunable via the **`maxParallelWorkers` key** (above) rather than being hardcoded. Execution mode is orthogonal to `integrationGranularity`: the former is *how* issues build, the latter is *how* they integrate. A habit-typed `--parallel` token on the invocation is harmlessly stripped and ignored (parallel is already the default). See `solve-milestone`'s **Resolve execution mode** Before-starting step, `### Parallel mode — Phase 1: concurrent worker dispatch`, and `### Integration granularity (issue vs wave)` for the mechanics.

**Note on `integrations.trello`.** When `integrations.trello` is absent, every Trello step in every skill skips silently — the established absent-means-skip convention (same as `unitTestCmd`, `preflightCmd`). When present, `boardId` is required; a node without `boardId` is treated as absent with a one-line misconfiguration log. The `lists` key and each of its three sub-keys (`queue`, `inProgress`, `inReview`) are individually optional and default to `"Queue"`, `"In Progress"`, and `"In Review"` respectively — **a profile written with defaults accepted contains only `integrations.trello.boardId` (no `lists` key)**. List-name matching against the Trello board is **case-sensitive**; when the MCP is available at runtime, a missing list is auto-created (Wave-2 behavior, enforced in the trello-sync conventions issue). The `integrations.trello` integration is **best-effort and never-gating**: Trello steps skip with a log if the MCP tools are unavailable at runtime; no issue or PR is ever blocked by a Trello failure.

**MCP prerequisite (integration only).** The Trello integration requires the `@delorenj/mcp-server-trello` MCP server (`mcp__trello__*` tools) in the consumer's Claude Code session. This is a prerequisite of the *integration*, NOT of milestone-driver itself — the plugin functions fully without it. Consumers who do not configure Trello skip silently; the MCP server does not need to be installed for any other milestone-driver feature.

**Partial list-override write shape.** When a consumer overrides only some of the three list names (e.g., only `queue`), the profile stores only the overridden sub-keys as a sparse `lists` object — omitted sub-keys use the defaults at runtime. Example: `"lists": { "queue": "Backlog" }` means `inProgress` and `inReview` use their defaults. This is consistent with absent-means-default: writing only overridden sub-keys rather than all three keeps the profile minimal.

**Setup-time `get_lists` failure.** If the board-list fetch fails during `/milestone-driver:setup` (after board selection), the setup skill falls back to manual text entry of the three list names using the defaults as suggestions. This is safe because the runtime skill auto-creates any list name that does not exist (Wave-2 behavior) — wrong names are tolerated.

## Minimal example (Core keys only)

```json
{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["src/**", "tests/**"]
}
```

The default-filled agent keys (`implementerAgent`, `triageAgent`, `designReviewAgent`, `coherenceReviewAgent`) are omitted here; their defaults apply automatically. The first three are bundled agents that always resolve; `coherenceReviewAgent`'s default is the milestone-coherence-reviewer companion, so its pass runs only when that companion plugin is installed (absent → silently skipped).

## Full example (PracticingPrayer — consumer #1)

```json
{
  "integrationBranch": "dev",
  "protectedBranch": "master",
  "sourceGlobs": ["PrayerApp/**", "PrayerApp.Tests/**"],
  "uiSurfaceGlobs": ["PrayerApp/Views/**", "**/*.xaml"],
  "versioning": false,
  "unitTestCmd": "dotnet test PrayerApp.Tests/PrayerApp.Tests.csproj",
  "e2eTestCmd": "pwsh ./run-e2etests.ps1",
  "implementerAgent": "milestone-driver:implementer",
  "domainSkills": ["maui-skills:*", "maui-current-apis"],
  "nonNegotiables": [
    "MAUI .NET 10 + Community Toolkit",
    "iOS 26.5 / Android API 36"
  ],
  "e2eEnv": {
    "endpoint": "127.0.0.1:4723",
    "device": "Android emulator (AVD)"
  }
}
```

These three keys satisfy the consumer-driven rule above with a real consumer, not speculation: PracticingPrayer (consumer #1) uses `uiSurfaceGlobs` for its XAML views (shown above); `triageAgent` and `designReviewAgent` are auto-filled, so the profile omits them while the bundled triage / visual-review phases consume their defaults. PracticingPrayer runs version-free (`versioning: false`) because its version lives in the `.csproj`, not a `plugin.json`, so the loop bumps nothing and its milestones need no semver name.

## External integrations example — only `queue` overridden; `inProgress` and `inReview` use their defaults.

```json
{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["skills/**", "agents/**", "hooks/**"],
  "integrations": {
    "trello": {
      "boardId": "abc123xyz",
      "lists": {
        "queue": "Backlog"
      }
    }
  }
}
```

## How the gates use the profile

| Gate | Profile keys read |
|---|---|
| `force-subagent` (PreToolUse `Write`/`Edit`/`MultiEdit`/`NotebookEdit`) | `sourceGlobs` |
| `no-bom` (PreToolUse `Write`/`Edit`/`MultiEdit`) | none (content byte-check; reads no profile keys) |
| `tests-green` (PreToolUse `Bash(git commit *)`) | `unitTestCmd` (no-op if absent), `sourceGlobs`; see stamp-skip note below |
| `no-push` (PreToolUse `Bash(git push *)`) | `protectedBranch` |
| `no-pr-to-protected` (PreToolUse `Bash(gh pr create *)`) | `protectedBranch` |

Each gate also honors a `CLAUDE_HOOK_DISABLE_*` environment escape hatch for the
rare case a human operator must override it deliberately.

**`tests-green` stamp-skip.** When `unitTestCmd` is set, `tests-green` maintains a
gitignored `.milestone-config/tests-stamp` file. The stamp holds a
`<branch>:<treeSHA>` key where `treeSHA` is the output of `git write-tree` (the
current staged/index tree). On each qualifying commit, if the stamp exists and its key
matches, the hook logs `staged tree unchanged since last green run — skipping unit suite`
and exits 0 without re-running the suite. On any red run the stamp is deleted so it can
never grant a future skip. If `git write-tree` fails the hook falls back to running the
full suite (safe default). The stamp is keyed on tree content, not wall-clock time, so a
slow suite retains its skip indefinitely for the same staged tree; switching branches
invalidates the skip because the branch is part of the key. The key is the staged
(index) tree, so the skip means the content being committed is unchanged since it last
passed; unstaged working-tree edits are not re-validated by the skip.

> **Enforcement model for `/code-review`:** Review-before-commit is enforced by **audit trail, not a hook**. The plugin ships no PreToolUse hook for code review (see `hooks/hooks.json` — the shipped gates are `force-subagent`, `no-bom`, `tests-green`, `no-push`, `no-pr-to-protected`; none reviews code). Enforcement is twofold: (1) `solve-issue` treats omission as a **park trigger** — it comments the reason on the issue, applies the `blocked` label, and returns (the milestone loop continues); the omission is never silently accepted — and (2) the PR body requires a mandatory `## Code Review` section whose absence is a visible defect on PR review. Consumers should inspect the Code Review section as part of their release checklist before approving the `integrationBranch` → `protectedBranch` merge.
