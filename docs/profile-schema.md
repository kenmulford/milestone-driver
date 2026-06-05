# milestone-driver — project profile schema

Each consuming repository supplies a committed profile that adapts the generic
engine to that repo's stack, branch model, and test commands. The plugin's
skills and hooks read this file; nothing in the engine is hard-coded to a
particular stack.

> **See also:** [the layered gating model](../README.md#the-layered-gating-model) — how `uiSurfaceGlobs` drives the design-lens triage and the visual-review gate — and [consumer setup](consumer-setup.md) for the run flow these keys feed.

## Location

```
<repo-root>/milestone-driver.json
```

**Commit it.** The mechanical gates read the profile, so it must be present in
every clone for the gates to behave identically for every contributor and on CI.

## Design principle

Keep it minimal and consumer-driven. **Three keys are required** (`integrationBranch`, `protectedBranch`, `sourceGlobs`); the agent keys `implementerAgent`, `triageAgent`, and `designReviewAgent` are **default-filled** (they default to `milestone-driver:implementer`, `milestone-driver:triage-reviewer`, and `milestone-driver:design-reviewer`) so a profile may omit them. All other keys are optional. **New keys are added only when a real second consumer needs them — never speculatively.**

## Key tiers

| Tier | Keys | Required? |
|---|---|:---:|
| **Core** (orchestration + safety) | `integrationBranch`, `protectedBranch`, `sourceGlobs` | ✅ required in file |
| **Core** (default-filled) | `implementerAgent`, `triageAgent`, `designReviewAgent` | optional in file (auto-filled) |
| **Testing** | `unitTestCmd` | Optional |
| **E2E** | `e2eTestCmd`, `e2eEnv` | Optional |
| **Preflight** | `preflightCmd` | Optional |
| **Integration** | `integrationGranularity` | Optional |
| **Triage / Visual** | `uiSurfaceGlobs` | Optional |
| **Release** | `versioning` | Optional |
| **Enrichment** | `domainSkills`, `nonNegotiables` | Optional |

**Note on safety keys:** `integrationBranch`, `protectedBranch`, and `sourceGlobs` are required for safe operation. The hooks fail-open when they are absent (a robustness measure so a hook bug never bricks a repo), but that fail-open is **not** a statement of optionality — without these keys the safety guarantees do not hold. `implementerAgent`, `triageAgent`, and `designReviewAgent` have bundled defaults (`milestone-driver:implementer`, `milestone-driver:triage-reviewer`, `milestone-driver:design-reviewer`) and are auto-filled by the bootstrap; omitting them from the profile is valid and common.

## Keys

| Key | Type | Tier | Plain-language description | Required? |
|---|---|---|---|:---:|
| `integrationBranch` | string | Core | Which branch should PRs be opened into and work merged onto? (e.g. `develop`) | ✅ |
| `protectedBranch` | string | Core | Which branch must never be pushed or PR'd to? (Your release / default branch, e.g. `main`) | ✅ |
| `sourceGlobs` | string[] | Core | Which path patterns are "source" that only the implementer subagent may edit? (e.g. `["src/**","tests/**"]`) | ✅ |
| `implementerAgent` | string | Core | Which agent authors the code? Default: `milestone-driver:implementer` (auto-filled; rarely overridden) | default-filled |
| `triageAgent` | string | Core | Which agent reviews issues for design gaps + dependency ordering (architect lens)? Default: `milestone-driver:triage-reviewer` (auto-filled; rarely overridden) | default-filled |
| `designReviewAgent` | string | Core | Which agent reviews UI-touching issues for UX gaps (front-end lens)? Default: `milestone-driver:design-reviewer` (auto-filled; rarely overridden) | default-filled |
| `unitTestCmd` | string | Testing | What command runs the unit tests? Absent → no unit gate; implementer verifies behavior another way. | — |
| `e2eTestCmd` | string | E2E | What command runs the end-to-end / UI tests? Absent → no E2E gate. | — |
| `e2eEnv` | object | E2E | Device/endpoint for the E2E runner (Appium, Selenium, Playwright), e.g. `{ "endpoint": "127.0.0.1:4723", "device": "Android emulator (AVD)" }`. | — |
| `preflightCmd` | string | Preflight | A single command that runs your project's fast pre-PR checks (lint, format, static analysis, security scan) — the checks your CI runs beyond the test suite. CI runs them regardless; this just surfaces a red result earlier. Absent → preflight gate skipped cleanly. Run after `/code-review`, before commit. | — |
| `integrationGranularity` | `"issue" \| "wave"` (string enum) | Integration | How should built issues integrate? Default `"issue"` — each built issue gets its own PR → CI → merge. `"wave"` — a whole Wave integrates on one branch `wave/<milestone>-w<N>` → one PR → one CI run. | — |
| `uiSurfaceGlobs` | string[] | Triage / Visual | Which path patterns mark UI surfaces? Drives `design-reviewer` dispatch (triage) and the visual-review gate ([#18](https://github.com/kenmulford/milestone-driver/issues/18)), e.g. `["PrayerApp/Views/**","**/*.xaml"]`. Absent → no design-lens review and no visual gate. | — |
| `versioning` | boolean | Release | Should each PR bump a plugin version? Absent or `true` → versioned: the run determines a target version from the milestone and bumps `.claude-plugin/plugin.json` per PR. `false` → version-free: no semver parse, no prompt, no bump (the milestone name need not be a version). Fail-safe: in versioned mode, if `.claude-plugin/plugin.json` is missing the run does not fail — it degrades to version-free with a logged note. | — |
| `domainSkills` | string[] | Enrichment | Stack-specific skill identifiers the implementer consults for citations (e.g. `["maui-skills:*"]`). Absent → general docs + repo conventions only. | — |
| `nonNegotiables` | string[] | Enrichment | Hard constraints the implementer must honour (framework versions, platform targets). Absent → none recorded. | — |

The implementer also uses any docs MCP available in the environment (e.g. Microsoft Learn for .NET) — these are environment-provided, **not required or installed by this plugin**.

**Note on `uiSurfaceGlobs` and the visual-review gate.** `uiSurfaceGlobs` drives two procedural (skill-level) phases — design-lens triage (`design-reviewer`) and the post-build visual-review gate (#18) — not a mechanical hook. Triage reviews the *recorded design + source*, so it needs **no render capability**. Screenshot capture for the visual gate does: it requires a render capability (e.g. `e2eEnv`, or a dedicated `screenshotCmd` if a consumer supplies one). When that capability is **absent, the visual gate degrades to PR-open-for-human-test** — it never fails the build and never auto-merges a UI issue. When `uiSurfaceGlobs` itself is absent, the repo has no UI surfaces: no design-lens review, no visual gate, and logic-only PRs auto-merge normally. See [the layered gating model](../README.md#the-layered-gating-model) for the three-layer model these keys participate in.

**Note on `versioning` and version-free mode.** Default (absent or `true`) is **versioned**: `solve-milestone` determines a target version from the milestone, and each issue's PR bumps `.claude-plugin/plugin.json` to it (`solve-issue` step 6.4). Set `versioning: false` for a repo that does not keep its version in `plugin.json` (or does not want a per-PR bump) — **version-free mode**: `solve-milestone` skips target-version determination entirely (no semver parse, no prompt; the milestone name need not be a version), `solve-issue` skips the bump, and the PR's Code Review section is annotated "version-free — no version bump." **Fail-safe degradation:** in versioned mode, if `.claude-plugin/plugin.json` does not exist, the run **does not fail** — `solve-issue` step 6.4 degrades to version-free with a one-line logged note. So the worst case for a misconfigured versioned repo is a skipped bump, never a halted run.

**Note on `preflightCmd`.** **CI is the authority; `preflightCmd` is a latency optimization.** Your CI runs lint / format / static-analysis / security checks on the PR regardless, so this local gate catches nothing CI would miss — its only value is moving a red result earlier, before the PR, to dodge the fix → push → wait round trip. `solve-issue` runs `preflightCmd` at the end of the `/code-review` resolve loop (step 6.1) — after that loop converges and before the step-6.4 version bump and step-6.5 commit; a non-zero exit re-dispatches the implementer with the failing command + output (its own "at most 2" cap, like every other gate), and a non-converging gate parks `blocked` — behaving like the unit / E2E gates. **Point it at the *fast* gates.** The heavy test suite is already covered by `unitTestCmd`, so a consumer who folds the full suite into `preflightCmd` just pays for it twice — this is guidance, not policed. Example commands: `pre-commit run --all-files`, `make lint`, `npm run lint`, `bundle exec standardrb && bundle exec brakeman -q`.

**Note on `integrationGranularity` and wave granularity.** Default (absent or `"issue"`) is **today's model, byte-unchanged**: each built issue opens its own PR → its own CI run → merges individually. Set `integrationGranularity: "wave"` for a repo with **long or expensive CI**, where O(issues) per-issue CI runs are wasteful: a whole dependency Wave integrates on one branch `wave/<milestone>-w<N>`, opens **one** wave PR → `integrationBranch`, and runs **one** CI run for the assembled Wave — trading O(issues) CI runs for O(waves), and CI-validating the *assembled* Wave (catching integration-level issues an isolated per-issue build misses). The merge-tail **mechanism** (#73 — merge-in + re-verify against accumulated state + bounded auto-resolve) is **unchanged**; only the **target** (the wave branch instead of `integrationBranch`) and **PR-opening** (one wave PR instead of per-issue PRs) differ. **Logic-only carve-out:** the visual-review gate is per-UI-issue, so UI issues in a Wave stay **per-issue / held** (each opens its own `needs review` PR for human visual sign-off); only the logic issues join the wave branch. **Trade-off:** one red wave-PR CI blocks the whole Wave — acceptable because the strong local gates (unit + static preflight + `/code-review` + the tail's re-verify) catch most failures before CI; CI is the backstop. **Not** for repos with weak local gates. **Orthogonal to `--parallel`** (which is *how* issues build; this is *how* they integrate) — the two combine or apply independently. See `solve-milestone`'s `### Integration granularity (issue vs wave)` for the orchestrator mechanics.

## Minimal example (Core keys only)

```json
{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["src/**", "tests/**"]
}
```

The default-filled agent keys (`implementerAgent`, `triageAgent`, `designReviewAgent`) are omitted here; their bundled defaults apply automatically.

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
gitignored `.milestone-driver-tests-stamp` file at the repo root. The stamp holds a
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
