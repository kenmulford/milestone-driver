# milestone-driver — consumer setup

Adopt milestone-driver in a repository in four steps. The whole point is that the
discipline is mechanical, so most of this is one-time wiring.

## 1. Install the plugin (and its dependency)

Install `milestone-driver` and the required [`superpowers`](#requirements) plugin
in Claude Code (dev-install via `claude --plugin-dir`, or from a marketplace once
published). Confirm both are enabled with `/plugin`.

## 2. Add the project profile

The first time you run `/milestone-driver:solve-issue` or `/milestone-driver:solve-milestone`,
the plugin **auto-invokes `/milestone-driver:setup`** if `milestone-driver.json` is absent
or missing a Core key. The bootstrap infers every key it can from repo signals (default branch,
gitflow layout, project type, test scripts) and presents detected defaults — you accept, edit,
or skip. After writing the file it returns control so the original task continues immediately.

You can also run `/milestone-driver:setup` directly at any time to create or repair the profile.

If your repo has no `.claude-plugin/plugin.json` (or you simply don't want a per-PR version bump), set `versioning: false` for **version-free mode**: the loop then needs no semver-named milestone and bumps nothing. Versioned is the default; a versioned repo whose `plugin.json` goes missing degrades to version-free with a logged note rather than failing.

**Manual authoring (fallback):** Create `milestone-driver.json` at the repo root. Only the
Core keys are required. See [`profile-schema.md`](profile-schema.md) for the full schema.
Minimal example (Core keys only):

```json
{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["src/**", "tests/**"]
}
```

Commit it — the gates read this file, so it must be present in every clone and on CI.

## 3. Restart Claude Code

All four gates (`force-subagent`, `tests-green`, `no-push`, `no-pr-to-protected`)
are plugin `PreToolUse` hooks registered in `hooks/hooks.json`. They **load at
session start** — restart Claude Code after installing or updating the plugin so
the hooks take effect. No separate native-hook installation step is required.

## 4. Add GitHub branch protection (server-side backstop)

The plugin hooks are local gates; protect the `protectedBranch` on the server too
(require PRs, block direct pushes). This is the authoritative backstop if a local
hook is bypassed or absent.

## 5. Point CLAUDE.md at the plugin

Add a short section to the consuming repo's `CLAUDE.md` summarizing the per-issue
flow and the non-negotiables, and pointing at `milestone-driver.json`, so a fresh
session knows the repo is milestone-driver–driven.

## What a run does (the gated flow)

Once wired, `/milestone-driver:solve-milestone <name>` (or `/milestone-driver:solve-issue <n>`) runs a gated pipeline. Two phases matter to you as a consumer:

- **Triage (Phase 0, before any build).** The run first reviews every issue for design gaps and dependency ordering — through an architect lens, plus a front-end lens for any issue touching `uiSurfaceGlobs`. It emits an all-clear or a gap table and posts a `🔴 Triage` comment on each gapped issue. An issue with a blocking gap is **parked** (labeled `needs design` / `needs decision`, left open) and the loop proceeds with the clean, independent issues — it never waits on you mid-run. Clear a park by recording the decision on the issue and re-running. Triage reads the recorded design + source, so it needs no special tooling.
- **Risk-profile right-sizing (decided by triage, applied during build).** Each issue is classified as **light** or **heavy** (default: **heavy**). The profile right-sizes ceremony — it never touches the safety floor. Triage, the `tests-green` hook, and `force-subagent` run unconditionally for both profiles.

  | What changes | Light | Heavy (default) |
  |---|---|---|
  | Implementer verification | Targeted verify in place of full TDD red→green (still verifies — never skips) | Full TDD red→green |
  | E2E gate | Skipped when the issue touches no UI surface | Per step 5 (UI surface + e2eTestCmd) |
  | `/code-review` effort | `low` / `medium` | `high` / `xhigh` |

  **Override labels.** Apply `risk:light` or `risk:heavy` to an issue to force the profile directly (bypasses the automatic rubric). When **both** labels are present, `risk:heavy` wins (safety-first). Absent both labels, the rubric decides with default-heavy-on-ambiguity.

  **What the rubric looks at.** Triage classifies an issue as **heavy** when any of the following is true: a gap of type `contradiction` or `not-buildable`; an undeclared `DEPENDS_ON` edge; a UI surface with a design-review need; the issue body names a shared interface, schema, auth path, or payment path; or genuine ambiguity. An issue is **light** only when none of the above heavy conditions is triggered, all triage criteria are clean, and no shared boundary is named.

- **Visual-review gate (post-build, for UI issues).** An issue whose changes touch `uiSurfaceGlobs` is **not** auto-merged. Its PR is opened and left **open** with a `needs review` label for your visual sign-off. If you've configured a render capability (`e2eEnv`, or a `screenshotCmd`), light + dark screenshots of the new surface are attached to the PR; if not, the gate posts a note that a human visual test is required before merge. Either way the PR waits for you — logic-only issues still auto-merge on green.
- **Preflight gate (post-build, before the PR).** If you set `preflightCmd` in your profile, the run executes your fast pre-PR checks locally at the end of the code-review loop (before the PR opens), so a lint / static-analysis / security failure is caught and fixed up front instead of turning the PR red. CI remains the authority — this just surfaces a red result earlier. Absent → skipped. **First-run notice:** on the first `solve-issue` / `solve-milestone` run where `preflightCmd` isn't set in your profile, the run prints a one-time, plain-English notice introducing it — this mostly matters when upgrading from 1.3.x, whose existing profile means `setup` won't re-run to offer the key. It shows at most once per clone (marker `.milestone-driver-preflight-notice`, gitignored) and is silent once `preflightCmd` is set.

To enable the design-lens triage and the visual gate, set `uiSurfaceGlobs` in your profile (see [`profile-schema.md`](profile-schema.md)); absent, the repo has no UI surfaces and neither runs. See [the layered gating model](../README.md#the-layered-gating-model) for the full three-layer model, the park-don't-prompt runtime, and the label taxonomy.

## Parallel mode and integration granularity (optional)

These two opt-ins (added in 1.5.0) trade speed and CI cost against failure isolation. Both default off, and they are orthogonal: `--parallel` controls **how** issues build, `integrationGranularity` controls **how** they integrate. You can use either, both, or neither.

### `--parallel`: build a Wave's independent issues concurrently

Opt in per run, not in the profile. Add a `--parallel` token to the invocation, or just say "in parallel":

```
/milestone-driver:solve-milestone "<name>" --parallel
```

When active, the run builds the mutually-independent issues within a single dependency Wave at the same time, each in its own git worktree (under a gitignored scratch dir `.milestone-driver-worktrees/`), then integrates them one at a time through a single serial verified merge tail. Only same-Wave issues that are mutually independent parallelize; a dependent issue still waits for its upstream to merge. The merge tail re-verifies each branch against the accumulated integrated state before squash-merging, and auto-resolves only non-overlapping same-file edits; anything non-trivial or red parks `blocked` for you instead of guessing. Concurrency is capped at 4 workers per Wave.

The trade-off: parallel finishes a wide Wave faster, but it runs a worktree fleet and carries merge-conflict and failure-isolation risk that the sequential path does not. The serial merge tail and the park-on-conflict policy bound that risk, but the sequential default is still the lowest-risk choice. Nothing about the blast radius changes: the workers and the tail still merge only to your `integrationBranch`, never to your `protectedBranch`.

#### DB isolation under `--parallel` (consumer responsibility)

A git worktree isolates the **filesystem**, not external services. When `--parallel` builds N issues concurrently, each worker runs `unitTestCmd` in its own worktree directory — but all N workers share the same external services, including the **test database** pointed to by `DATABASE_URL` (or equivalent). `--parallel` does **not** inject DB isolation automatically; the consumer's harness is responsible.

**Failure mode if not isolated.** Concurrent rspec / pytest / dotnet-test runs against a single test DB collide on transactional-fixture state, truncation timing, and PK/sequence counters. The result is flaky reds — and flaky reds from `unitTestCmd` trigger the `tests-green` gate, which blocks the commit and causes `tests-green` false-blocks or misleading parks.

**How to isolate.** Use a per-worker database pattern:

| Stack | Isolation mechanism |
|---|---|
| Ruby / RSpec | [`parallel_tests`](https://github.com/grosser/parallel_tests) gem — sets `TEST_ENV_NUMBER` per worker; configure `database.yml` to suffix the DB name with `ENV['TEST_ENV_NUMBER']` so each worker gets `myapp_test1`, `myapp_test2`, … |
| Python / pytest | [`pytest-xdist`](https://pytest-xdist.readthedocs.io/) with `--dist=loadscope` + a DB-naming fixture that reads `worker_id` from `pytest-xdist`'s `request` fixture and suffixes `DATABASE_URL` |
| .NET / xUnit | Spin up an isolated `TestContainers` DB per test class, or set `DATABASE_URL` per worker via a `GlobalSetup` that appends the worker index |
| Any stack | Set `DATABASE_URL` (or equivalent) per worker to a dedicated per-worker DB name, and ensure `db:test:prepare` (or equivalent) runs for each DB before the suite |

**What the orchestrator does.** When `unitTestCmd` is defined and `--parallel` mode is active, the orchestrator emits a one-time advisory that concurrent unit runs share external services (notably the test DB) unless the consumer's harness isolates per worker, then **proceeds with parallel dispatch**. It does not serialize, and it does not auto-inject DB isolation. This mirrors the per-worktree `PORT` escape-hatch treatment: the notice is informational; the consumer opts in to the correct isolation.

### `integrationGranularity`: integrate per issue or per wave

Set this in the profile (it is a repo-stable choice, not a per-run flag):

```json
{ "integrationGranularity": "wave" }
```

Default `"issue"` is today's model, unchanged: each built issue opens its own PR, gets its own CI run, and merges individually. Set `"wave"` for a repo with long or expensive CI: a whole dependency Wave integrates on one branch `wave/<milestone>-w<N>`, opens one wave PR to your `integrationBranch`, and runs one CI run for the assembled Wave. The merge-tail mechanism is the same; only the target (a wave branch) and the PR-opening (one wave PR) differ. UI issues stay per-issue and held for your visual sign-off even in wave granularity; only the logic issues join the wave branch.

The trade-off: wave granularity costs O(waves) CI runs instead of O(issues), and CI validates the assembled Wave rather than each issue in isolation. But one red wave-PR CI blocks the whole Wave, so you bisect to find the culprit. That is acceptable when your local gates are strong (unit plus static preflight plus `/code-review` plus the tail's re-verify catch most failures before CI); it is not recommended for repos with weak local gates. See [`profile-schema.md`](profile-schema.md) for the key and `solve-milestone`'s integration-granularity section for the orchestrator mechanics.

## Releasing to your protected branch

The loop only ever merges to your `integrationBranch`; promoting to your `protectedBranch` stays **manual and yours** (the `no-push` / `no-pr-to-protected` gates keep the loop off it). When the integration branch is ready to ship:

1. **Merge** `integrationBranch` → `protectedBranch` yourself (open the PR by hand).
2. **Tag and cut the GitHub Release** on `protectedBranch`, so the Releases page tracks what shipped:
   ```
   gh release create v<version> --target <protectedBranch> --generate-notes
   ```
   In a versioned repo, `<version>` is the `.claude-plugin/plugin.json` version the milestone bumped to; `--generate-notes` builds the changelog from the PRs since the previous tag. Version-free repos can tag the date or skip this.
3. **Deploy** on your own schedule.

Cut the Release (step 2) every time: the loop bumps the version on `integrationBranch` but never tags or releases, so skipping it leaves the Releases page stale even though the merge landed.

## Verify the gates

| Test | Expected |
|---|---|
| Main-thread `Edit` to a `sourceGlobs` file | **blocked** (force-subagent) — dispatch the implementer instead |
| The same edit from a dispatched subagent | allowed |
| `git commit` with the unit suite red (staged source) — **when `unitTestCmd` is defined** | **blocked** (tests-green) |
| `git push` to `protectedBranch` | **blocked** (no-push) |
| `gh pr create --base <protectedBranch>` | **blocked** (no-pr-to-protected) |

When `unitTestCmd` is absent, `tests-green` is a no-op — there is no unit gate to verify.

Each gate honors a `CLAUDE_HOOK_DISABLE_*` environment escape hatch for deliberate
human override.

## Requirements

- The `superpowers` plugin (the per-issue inner loop depends on it).
- `gh` (authenticated), `git`.
- `bash` (preferred) or `pwsh` 7+ for the hooks; `jq` is required for the bash path.
