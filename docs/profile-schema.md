# milestone-driver — project profile schema

Each consuming repository supplies a committed profile that adapts the generic
engine to that repo's stack, branch model, and test commands. The plugin's
skills and hooks read this file; nothing in the engine is hard-coded to a
particular stack.

## Location

```
<repo-root>/.claude/milestone-driver.json
```

**Commit it** (do not git-ignore it). The mechanical gates read the profile, so
it must be present in every clone for the gates to behave identically for every
contributor and on CI.

## Design principle

Keep it minimal and consumer-driven. Only four keys are required; the rest tune
optional gates. **New keys are added only when a real second consumer needs
them — never speculatively.**

## Keys

| Key | Type | Required | Consumed by | Meaning |
|---|---|:---:|---|---|
| `integrationBranch` | string | ✅ | `/solve-milestone`, `/solve-issue` | Branch the loop cuts feature branches from and merges PRs into (e.g. `dev`). |
| `protectedBranch` | string | ✅ | `no-push-to-protected` hook | Branch the loop must never push or PR to (e.g. `master`). The server-side backstop is GitHub branch protection. |
| `sourceGlobs` | string[] | ✅ | `force-subagent` hook | Globs identifying app/test source. Main-thread edits to these are **blocked**; only the implementer subagent may author them. Docs, plans, and `.claude/**` are exempt by the hook regardless of this list. |
| `unitTestCmd` | string | ✅ | `tests-green` hook, `/solve-issue` | Command run to prove the unit suite is green. A non-zero exit **blocks the commit**. |
| `e2eTestCmd` | string | — | `/solve-issue` | E2E runner used at the E2E pre-merge gate. Omit if the repo has no E2E test layer. |
| `implementerAgent` | string | — | `/solve-issue` | Subagent that authors code. Defaults to the bundled `implementer`. Override to point at a repo-specific agent. |
| `domainSkills` | string[] | — | implementer | Skill identifiers the implementer must consult for citations (e.g. `maui-skills:*`). MCP tooling (e.g. Microsoft Learn) is part of the implementer's research path by contract; list it here only if you want it surfaced explicitly. |
| `nonNegotiables` | string[] | — | implementer | Stack constraints recorded for the implementer (framework versions, platform targets). |
| `e2eEnv` | object | — | `e2eTestCmd` / implementer | End-to-end test environment for an E2E runner (Appium, Selenium, Playwright, etc.), e.g. `{ "endpoint": "127.0.0.1:4723", "device": "Android emulator (AVD)" }`. |

## Minimal example (required keys only)

```json
{
  "integrationBranch": "dev",
  "protectedBranch": "master",
  "sourceGlobs": ["src/**", "tests/**"],
  "unitTestCmd": "npm test"
}
```

## Full example (PracticingPrayer — consumer #1)

```json
{
  "integrationBranch": "dev",
  "protectedBranch": "master",
  "sourceGlobs": ["PrayerApp/**", "PrayerApp.Tests/**"],
  "unitTestCmd": "dotnet test PrayerApp.Tests/PrayerApp.Tests.csproj",
  "e2eTestCmd": "pwsh ./run-e2etests.ps1",
  "implementerAgent": "implementer",
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
| `force-subagent` (PreToolUse `Edit`/`Write`) | `sourceGlobs` |
| `tests-green` (native `pre-commit`) | `unitTestCmd` |
| `no-push-to-protected` (native `pre-push`) | `protectedBranch` |

Each gate also honors a `CLAUDE_HOOK_DISABLE_*` environment escape hatch for the
rare case a human operator must override it deliberately.
