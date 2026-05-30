# milestone-driver — project profile schema

Each consuming repository supplies a committed profile that adapts the generic
engine to that repo's stack, branch model, and test commands. The plugin's
skills and hooks read this file; nothing in the engine is hard-coded to a
particular stack.

## Location

```
<repo-root>/milestone-driver.json
```

**Commit it.** The mechanical gates read the profile, so it must be present in
every clone for the gates to behave identically for every contributor and on CI.

## Design principle

Keep it minimal and consumer-driven. **Three keys are required** (`integrationBranch`, `protectedBranch`, `sourceGlobs`); `implementerAgent` is **default-filled** (defaults to `milestone-driver:implementer`) so a profile may omit it. All other keys are optional. **New keys are added only when a real second consumer needs them — never speculatively.**

## Key tiers

| Tier | Keys | Required? |
|---|---|:---:|
| **Core** (orchestration + safety) | `integrationBranch`, `protectedBranch`, `sourceGlobs` | ✅ required in file |
| **Core** (default-filled) | `implementerAgent` | optional in file (auto-filled) |
| **Testing** | `unitTestCmd` | Optional |
| **E2E** | `e2eTestCmd`, `e2eEnv` | Optional |
| **Enrichment** | `domainSkills`, `nonNegotiables` | Optional |

**Note on safety keys:** `integrationBranch`, `protectedBranch`, and `sourceGlobs` are required for safe operation. The hooks fail-open when they are absent (a robustness measure so a hook bug never bricks a repo), but that fail-open is **not** a statement of optionality — without these keys the safety guarantees do not hold. `implementerAgent` has a bundled default (`milestone-driver:implementer`) and is auto-filled by the bootstrap; omitting it from the profile is valid and common.

## Keys

| Key | Type | Tier | Plain-language description | Required? |
|---|---|---|---|:---:|
| `integrationBranch` | string | Core | Which branch should PRs be opened into and work merged onto? (e.g. `develop`) | ✅ |
| `protectedBranch` | string | Core | Which branch must never be pushed or PR'd to? (Your release / default branch, e.g. `main`) | ✅ |
| `sourceGlobs` | string[] | Core | Which path patterns are "source" that only the implementer subagent may edit? (e.g. `["src/**","tests/**"]`) | ✅ |
| `implementerAgent` | string | Core | Which agent authors the code? Default: `milestone-driver:implementer` (auto-filled; rarely overridden) | default-filled |
| `unitTestCmd` | string | Testing | What command runs the unit tests? Absent → no unit gate; implementer verifies behavior another way. | — |
| `e2eTestCmd` | string | E2E | What command runs the end-to-end / UI tests? Absent → no E2E gate. | — |
| `e2eEnv` | object | E2E | Device/endpoint for the E2E runner (Appium, Selenium, Playwright), e.g. `{ "endpoint": "127.0.0.1:4723", "device": "Android emulator (AVD)" }`. | — |
| `domainSkills` | string[] | Enrichment | Stack-specific skill identifiers the implementer consults for citations (e.g. `["maui-skills:*"]`). Absent → general docs + repo conventions only. | — |
| `nonNegotiables` | string[] | Enrichment | Hard constraints the implementer must honour (framework versions, platform targets). Absent → none recorded. | — |

The implementer also uses any docs MCP available in the environment (e.g. Microsoft Learn for .NET) — these are environment-provided, **not required or installed by this plugin**.

## Minimal example (Core keys only)

```json
{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["src/**", "tests/**"]
}
```

`implementerAgent` is omitted here; the bundled default applies automatically.

## Full example (PracticingPrayer — consumer #1)

```json
{
  "integrationBranch": "dev",
  "protectedBranch": "master",
  "sourceGlobs": ["PrayerApp/**", "PrayerApp.Tests/**"],
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

## How the gates use the profile

| Gate | Profile keys read |
|---|---|
| `force-subagent` (PreToolUse `Write`/`Edit`/`MultiEdit`/`NotebookEdit`) | `sourceGlobs` |
| `tests-green` (PreToolUse `Bash(git commit *)`) | `unitTestCmd` (no-op if absent), `sourceGlobs` |
| `no-push` (PreToolUse `Bash(git push *)`) | `protectedBranch` |
| `no-pr-to-protected` (PreToolUse `Bash(gh pr create *)`) | `protectedBranch` |

Each gate also honors a `CLAUDE_HOOK_DISABLE_*` environment escape hatch for the
rare case a human operator must override it deliberately.
