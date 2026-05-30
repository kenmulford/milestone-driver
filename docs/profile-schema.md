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

Keep it minimal and consumer-driven. Only four keys are required; the rest tune
optional gates. **New keys are added only when a real second consumer needs
them — never speculatively.**

## Keys

| Key | Type | Required | Consumed by | Meaning |
|---|---|:---:|---|---|
| `integrationBranch` | string | ✅ | `/milestone-driver:solve-milestone`, `/milestone-driver:solve-issue` | Branch the loop cuts feature branches from and merges PRs into (e.g. `dev`). |
| `protectedBranch` | string | ✅ | `no-push` / `no-pr-to-protected` hooks | Branch the loop must never push or PR to (e.g. `master`). The server-side backstop is GitHub branch protection. |
| `sourceGlobs` | string[] | ✅ | `force-subagent` hook | Globs identifying app/test source. Main-thread edits to these are **blocked**; only the implementer subagent may author them. Docs, plans, and `.claude/**` are exempt by the hook regardless of this list. |
| `unitTestCmd` | string | ✅ | `tests-green` hook, `/milestone-driver:solve-issue` | Command run to prove the unit suite is green. A non-zero exit **blocks the commit**. |
| `e2eTestCmd` | string | — | `/milestone-driver:solve-issue` | E2E runner used at the E2E pre-merge gate. Omit if the repo has no E2E test layer. |
| `implementerAgent` | string | — | `/milestone-driver:solve-issue` | Subagent that authors code. Defaults to the bundled `milestone-driver:implementer`. Override to point at a project-level agent using that agent's own (un-namespaced) name. |
| `domainSkills` | string[] | — | implementer | Stack-specific skill identifiers the implementer consults for citations (e.g. `maui-skills:*` for a .NET MAUI repo). The implementer also uses any docs MCP available in the environment (e.g. Microsoft Learn for .NET) — these are environment-provided, **not required or installed by this plugin**. |
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
| `tests-green` (PreToolUse `Bash(git commit *)`) | `unitTestCmd`, `sourceGlobs` |
| `no-push` (PreToolUse `Bash(git push *)`) | `protectedBranch` |
| `no-pr-to-protected` (PreToolUse `Bash(gh pr create *)`) | `protectedBranch` |

Each gate also honors a `CLAUDE_HOOK_DISABLE_*` environment escape hatch for the
rare case a human operator must override it deliberately.
