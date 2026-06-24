# Changelog

Release notes for milestone-driver. Versions before 1.7.0 are documented on the
[GitHub Releases page](https://github.com/kenmulford/milestone-driver/releases).

## v1.13.0 — An optional coherence check before the final review

- **The driver now auto-runs an optional coherence pass before the final code review.** When the milestone-coherence-reviewer companion plugin is installed, `solve-issue` dispatches it read-only over the built change just before the final `/code-review`, as a never-gating post-build coherence pass. It's wired via a new default-filled `coherenceReviewAgent` profile key (`milestone-coherence-reviewer:coherence-reviewer`) and is silently skipped when the companion is absent (absent-means-skip). It heals via follow-ups and never blocks or changes a merge. (#231)
- **Fixed: flaky `shell-tests (bash)` render-daemon teardown.** The `render-daemon` test's idempotent-teardown case asserted process liveness the instant `stop` returned, racing the asynchronous SIGTERM that teardown sends best-effort — so on a loaded CI runner the process could still be alive for a microsecond and the required check would flake (`teardown: ... alive=1`), blocking otherwise-green merges. The test now polls for actual process death with a bounded window and escalates to a guarded SIGKILL only as a diagnostic safety net (which still fails the test if `stop` didn't reap, so a real teardown regression can't hide). Mirrored into the PowerShell twin to keep the golden-matrix pair behavior-identical. Test-infra only — no behavior change to the daemon. (#240)

## v1.12.2 — Triage now catches changes that leave existing users in the dark

_Released 2026-06-23._

**Theme:** Before the driver builds an issue, it triages it for gaps. Until now, that review could wave through an issue that quietly added a new config key, flipped a default, or introduced behavior an existing install would never stumble across on its own — leaving everyone who already set the driver up with no way to discover the change. This release closes that hole: when an issue actually affects existing users or their config, triage now looks for a discovery path — a one-time notice, a "re-run setup" prompt, or a documented upgrade note — and flags the issue if there's none. It's the same discovery-path principle the milestone-feeder already enforced on its own path, now made the default on the driver's main review. A second, internal-only touch-up keeps the driver's hand-maintained git-ignore scratch blocks pointing at all their sibling copies — including the two that live in the companion milestone-feeder plugin.

### ✨ Triage now insists every existing-user-facing change has a way to be found

| Issue | PR | What |
|---|---|---|
| #224 Add an existing-user discovery/migration-path criterion to the driver's triage-reviewer | #226 | When the driver triages an issue, it now checks one more thing: if the issue affects people who already have the driver set up — a new config key, a changed default, a behavior an existing install wouldn't surface on its own — it looks for a way those users would actually find out about the change. That discovery path can be a one-time notice (the pattern the driver already ships), a prompt to re-run setup, or a documented upgrade note. If the issue affects existing users and offers none of those, triage flags it. It's an **Advisory** by default — it tells you the gap and points you at the driver's own one-time-notice pattern as the fix — and only escalates to a **Blocker** when the missing discovery path makes the issue impossible to deliver. A brand-new feature an existing install can't even reach yet is exempt: the check only fires when an already-set-up user would genuinely be affected. "It's non-breaking" on its own isn't a reason to skip it. |
| #223 Extend the 3 KEEP-IN-SYNC markers to name the feeder's setup + plan write sites | #225 | The driver keeps three identical little git-ignore scratch blocks in sync by hand, and each one carries a comment listing where its siblings live so a maintainer editing one is pointed at the rest. Those comments now also name the two matching copies that the companion milestone-feeder plugin writes (at its setup and plan sites), so editing any one copy points you at every copy across both plugins. Comment text only — no behavior change, and nothing a consumer ever sees. |

### Consumer notes (upgrading from v1.12.1)

- **Triage now flags an existing-user-facing change that nobody can discover.** When the driver triages an issue that adds a config key, changes a default, or introduces behavior an existing install wouldn't surface on its own, it checks for a discovery path — a one-time notice, a re-run-setup prompt, or a documented upgrade note. No discovery path and existing users are affected → the issue is flagged as an **Advisory** (escalating to a **Blocker** only if the gap makes the issue un-deliverable). **What's exempt:** a brand-new feature an existing install can't even reach yet. The check fires on impact to an already-set-up user, not on whether a change is "breaking" — "non-breaking" alone doesn't skip it.
- **#223 is internal maintenance only.** It updates the cross-reference comments on the driver's hand-synced git-ignore scratch blocks so they name the matching copies in the companion milestone-feeder plugin. Comment text only — no behavior change, nothing visible in your runs.
- **No schema changes** to `.milestone-config/driver.json` — neither change adds or alters a profile key.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.12.1 — A one-time nudge so upgraders find the new screenshots feature

_Released 2026-06-23._

**Theme:** Last release added opt-in screenshots on your UI pull requests — but you'd only ever hear about it the first time you set the driver up. If you already had the driver configured and just pulled the update, the feature was there and you'd never know. This release fixes that: the next time the driver runs in a repo that has UI screens but no visual-capture set up yet, it prints a short, one-time note telling you the feature exists and how to turn it on. It's a nudge, not a prompt — you can ignore it and nothing changes. It shows at most once per checkout, then never again, and it stays completely silent for repos that already turned visual capture on or that have no UI to screenshot in the first place.

### ✨ Discoverability

| Issue | PR | What |
|---|---|---|
| #219 Add one-time "New in 1.12.0 — optional visual capture" discovery notice to solve-issue + solve-milestone, gitignore the marker | #220 | When the driver works an issue or a milestone, it now prints a one-time, opt-in-framed note pointing you at v1.12.0's optional screenshots — but only when all three are true: your profile has no `visualCapture` block yet, your repo *does* declare UI screens (`uiSurfaceGlobs`), and this checkout hasn't shown the note before. After it prints once, it drops a small marker file and stays quiet from then on. It's silent for repos that already configured visual capture and for repos with no UI surface at all. Same pattern as the existing one-time preflight (1.4.0) and Trello (1.8.0) notices; the marker lives only at `.milestone-config/visualcapture-notice`, with no older fallback location. |

### Consumer notes (upgrading from v1.12.0)

- **You'll see a one-time note if you have UI screens but haven't set up visual capture yet.** The next time the driver runs in such a repo, it tells you the optional screenshots feature exists and how to opt in. It prints at most once per checkout; after that a small marker file silences it for good. It's purely a heads-up — skip it and nothing about your run changes.
- **It stays silent when there's nothing to say:** repos that already have a `visualCapture` block, repos that declare no UI screens (`uiSurfaceGlobs`), and any checkout that already saw the note once.
- **New per-checkout marker file `.milestone-config/visualcapture-notice`** records that the note was shown. It's git-ignored (added to the committed scratch-ignore list), so it never shows up in your `git status` and never gets committed.
- **No schema changes** to `.milestone-config/driver.json` — purely a discovery notice; no new or changed profile keys.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.12.0 — Opt-in screenshots on your UI pull requests

_Released 2026-06-23._

**Theme:** When the driver finishes a UI issue, it holds the pull request open for you to look at the rendered screen yourself — code that passes its tests can still look wrong. Until now, "look at it yourself" meant you started the app, signed in, and navigated to the changed screen by hand. This release lets the driver do that legwork for you and attach the screenshots to the PR, so you open it and just *see* the change. It is strictly opt-in: you tell the driver how to boot your app once, and from then on UI PRs carry before-your-eyes evidence. Leave it unconfigured and nothing changes — no app is booted, no screenshot is taken, and the PR still waits for your manual look exactly as it does today. The screenshots are a convenience, never a gate: a UI issue is still never merged automatically, and if anything in the capture goes wrong the run quietly falls back to the "please test this by hand" note instead of failing.

### ✨ Opt-in visual capture for UI pull requests

| Issue | PR | What |
|---|---|---|
| #208 Render-daemon lifecycle seam — one-per-run app-server boot/reuse | #212 | New `scripts/render-daemon.{sh,ps1}` (a bash + PowerShell 7+ twin), called as `start | status | stop`. It reads `visualCapture.serverCmd` and `visualCapture.readyUrl` straight from your profile, and on `start` either reuses an already-running daemon or boots your app server **once per run** — spawned detached in its own process group, then polled at a `/health`-style ready URL until it answers before returning. `stop` is idempotent and tears down the whole process group (so a compound `cd app && npm run dev`-style command's children die with it, not just the wrapper); a stale or dead state file is cleaned and treated as down, never reused, never an error. State lives in `.milestone-config/.runtime/render-daemon.json`. Dependency-free beyond `jq` (already permitted) and `curl`/`wget` for the probe. CI-gated on both the bash and pwsh shell-test legs. |
| #209 Optional `visualCapture` profile block — schema, validation, setup tier | #213 | Documents the new optional `visualCapture` block in `docs/profile-schema.md` — keys `serverCmd`, `readyUrl`, `signInPath` (all three required when the block is present), plus optional `persona` (default `"super-admin"`), `viewports` (default desktop-only `{ "desktop": { "width": 1440, "height": 900 } }`), and `appearances` (default `["light"]`). Present-with-all-three-required = enabled; a block missing any required key is treated as absent and logged; **absent = behavior byte-unchanged** (absent-means-skip, the same convention as `unitTestCmd` / `integrations.trello`). Adds a Phase-2 **Visual Capture** tier to `setup` that surfaces only when a visual-capture signal is detected, prompts each key with its detected default and skip-consequence, and writes a sparse object (omitted optional keys resolve to defaults at runtime). |
| #210 Capture per-surface visual evidence for UI-issue PRs | #214 | Wires capture into `solve-issue` step 7. For a UI issue on a serial run with a complete `visualCapture` block, the driver boots the render daemon, signs in through your test sign-in seam as the configured persona (substituting `{persona}` into `signInPath`), and — for each surface the building agent reports it changed × each viewport × each appearance — drives **Playwright MCP** to capture a screenshot. The shots are pushed to an orphan `visual-review-assets` branch (so binary blobs never land on your integration branch) and embedded in a single **"👁️ Visual evidence"** PR comment. Hard degradation invariant: absent / incomplete block, or **any** failure along the way (daemon won't boot, sign-in fails, a screen won't render, push fails) → it posts the human-visual-test note instead, never fails the run, and never auto-merges a UI issue. Under `--parallel`, capture is deferred to the serial merge tail (one fixed-port daemon can't safely serve concurrent worktrees). |
| #211 Document the visualCapture seam; retire dead `screenshotCmd` prose | #215 | Removes the never-built, prose-only `screenshotCmd` render-capability language from `docs/profile-schema.md` and `docs/consumer-setup.md`, replacing it with the real `visualCapture` seam. Adds a "One render daemon per run" section and the **three invariants** to `docs/architecture.md`: (1) opt-in / byte-unchanged when absent, (2) never fail the run, (3) never auto-merge a UI issue. |

### Consumer notes (upgrading from v1.11.2)

- **New optional profile block `visualCapture`** in `.milestone-config/driver.json`. Leave it out and **nothing changes** — no app is booted, no screenshot is attempted, no new gate, no prompt, no error. Your UI PRs still open and wait for your manual visual test exactly as before. The feature is invisible until you opt in.
- **Opting in needs two things on your side:** a render capability (a browser driven through Playwright MCP) and a seeded/persona app server the driver can boot — a local instance of your app preloaded with test data and reachable via a passwordless test sign-in. You declare it with three required keys: `serverCmd` (the command that boots your test app server), `readyUrl` (a `/health`-style URL the driver polls until the server is up), and `signInPath` (your persona-templated test sign-in path, e.g. `/dev/sign_in/{persona}`). Optional `persona`, `viewports`, and `appearances` refine which persona, screen sizes, and light/dark appearances get captured; omit them and they default to super-admin, desktop-only, light. If you skip any one of the three required keys, no block is written — the gate just stays at PR-open-for-your-manual-test.
- **New artifact:** `scripts/render-daemon.{sh,ps1}` — boots your app server once per run and reuses it, then tears it down at run end. Dependency-free beyond `jq` (already required) and `curl` or `wget` for the ready probe.
- **New `setup` tier:** when you re-run `milestone-driver:setup` (or first-run bootstrap) and the repo shows a visual-capture signal, setup now offers a **Visual Capture** tier that walks you through the keys. No signal detected → the tier is skipped silently, just like the E2E tier.
- **The three invariants — what opting in can and can't do.** It can only *add* evidence; it can never change a run's outcome. (1) **Opt-in / byte-unchanged:** absent block = today's behavior, exactly. (2) **Never fails the run:** any capture failure degrades to the human-visual-test note. (3) **Never auto-merges a UI issue:** the screenshots are convenience evidence — the PR is still held open with `needs review` for you to test-render and merge yourself. Logic-only PRs still auto-merge on green; a repo with no `uiSurfaceGlobs` has no UI issues and is unaffected.
- **Under `--parallel`:** render capture defers to the serial merge tail — a parallel UI-issue worker opens the PR and applies `needs review` but attaches no screenshots; the serial tail or you capture before merge. (You can inject a per-worktree `PORT` to opt capture back into the parallel phase.)
- **No changes to any existing profile key.** `visualCapture` is purely additive.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.11.2 — Ground the release tail in docs, and make the auto-merge gate real

_Released 2026-06-23._

**Theme:** The driver hands the last step of a release back to you — merging your integration branch into your protected branch, tagging it, and closing the milestone. Two things about that handoff were shaky. The written runbook didn't warn you which way to merge, so a wrong choice quietly broke the *next* release. And on the driver's own repo, the safety net that's supposed to stop a failing change from merging wasn't actually wired up — "green" meant nothing because no tests ran before a merge. This release fixes both halves of the same trust gap: the release process is now documented correctly (so you don't get bitten on the next cut), and the driver now runs its own test suite as a real check before anything merges (so it practices the gate it provisions for you).

### 📖 Document the release tail correctly (`--merge`, not `--squash`)

| Issue | PR | What |
|---|---|---|
| #160 Adopt `--merge` for the release PR + harden the release tail | #204 | Rewrites `docs/consumer-setup.md` § "Releasing to your protected branch" into the complete ordered runbook. **Merge the integration→protected release PR with `--merge`, never `--squash`:** a squash puts a commit on your protected branch that the integration branch never sees, so the two diverge and the *next* release PR conflicts (typically on `.claude-plugin/plugin.json` + `CHANGELOG.md`) — and if your integration branch is PR-locked, you can't just resolve-and-push to fix it; it forces a separate history-only back-merge PR. `--merge` keeps the branches permanently synced instead. The runbook now spells out the full ordered tail — **open + merge the release PR with `--merge` *before* tagging → tag and cut the Release after the merge → close the milestone object → deploy** — with the `--notes`-from-CHANGELOG form (this plugin carries one) and `--generate-notes` as the no-CHANGELOG fallback. Two footguns are called out: **(a)** don't run a bare `gh release create` before the PR merges — it tags the old tip with empty/wrong notes (happened in v1.9.2); **(b)** a PR-locked integration branch blocks direct pushes even for admins. The `solve-milestone` SKILL's "🔴 Your move" recap and Final-summary "next human step" now both name `--merge` + merge-before-tag and point at the runbook. |

### 🧪 Make the driver's own auto-merge gate real

| Issue | PR | What |
|---|---|---|
| #179 Add a CI check on develop so auto-merge gates on tests | #205 | Adds `.github/workflows/ci.yml` (new) — a GitHub Actions workflow that runs the repo's shell test suites on every PR into `develop`. Two `ubuntu-latest` jobs, `shell-tests (bash)` and `shell-tests (pwsh)`, run `tests/extract-version.test` and `tests/ci-preflight-steps.test` (the `.sh` legs and their PowerShell 7+ `.ps1` twins). In the 1.11.0 wave the driver auto-merged PRs to `develop` on "green CI" — but the repo had **no required status check**, so green was vacuous: nothing ran the suite before the merge. This closes that hole on the driver's own repo, dogfooding the gate the suite already provisions for consumer repos. |

### Consumer notes (upgrading from v1.11.1)

- **Documentation-only behavior clarification for #160** — no change to how the driver runs. After it merges every issue and authors the CHANGELOG, the release tail now tells you the correct *way* to merge: `--merge`, not `--squash`. If you've been squash-merging your integration→protected release PRs and hitting recurring conflicts on the next cut, that's the cause — switch to `--merge` and the branches stay synced. The full ordered runbook (merge → tag → close milestone → deploy) lives in `docs/consumer-setup.md` § "Releasing to your protected branch".
- **The CI workflow (#179) is the driver's own dogfooding, not a consumer artifact.** `.github/workflows/ci.yml` gates *this* repo's `develop`; it doesn't change the installed plugin or your repo. The suite still provisions a CI gate for *your* consumer repo separately.
- 🔴 **Operator follow-up (not shipped in this release):** making the two CI checks actually *required* on `develop` is a one-time branch-protection step — adding the check contexts `shell-tests (bash)` and `shell-tests (pwsh)` to the branch's required-checks list (a `gh api -X PUT .../branches/develop/protection` call, preserving `enforce_admins`). The workflow file alone makes the checks *run*; the protection PUT makes a red PR *unmergeable*. This is operator config on the driver's own repo, not part of the installed plugin.
- **No schema changes** to `.milestone-config/driver.json`.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.11.1 — Ground the builder in your project's house docs (anchored retrieval)

_Released 2026-06-22._

**Theme:** The driver writes the code; the feeder plans it. Until now only the feeder read your project's standing docs (your `.project/` house docs — conventions, design system, glossary), so the plugin that *wrote* the code never saw the same source of truth the plugin that *planned* it used. This release closes that gap: the driver's builder and its two pre-build reviewers now receive the exact `.project/` sections an issue cites — pulled **section by section** (anchored retrieval), not whole files — so grounding stays consistent with the plan without ballooning token cost. When you have no `.project/` docs, nothing changes; the feature is invisible until you add them. This is part 2 of 3 of the suite-wide grounding seam.

### ✨ Project-docs grounding via anchored retrieval

| Issue | PR | What |
|---|---|---|
| #183 Add the projectDocs profile key | #190 | New optional `projectDocs` profile key (default `.project/`, absent-means-default), mirroring the feeder; resolved at the solve-issue and triage profile reads. |
| #184 Ship the read-doc-section primitive | #191 | New dependency-free `scripts/read-doc-section.{sh,ps1}` twin: given a doc + a `## anchor`, prints only that section; **fails loud** (non-zero exit) on a missing/renamed anchor — never silent empty grounding. Ships a 5-case test twin. |
| #185 Resolve cited sections once in solve-issue | #192 | solve-issue resolves the issue's cited `.project/<doc>#<section>` anchors once, pulls a superset via the primitive, and passes the sections into the implementer brief. |
| #186 Resolve cited sections once in triage | #193 | triage resolves the cited sections once per issue and passes the **same** sections into both the triage-reviewer and design-reviewer briefs. |
| #187 Wire the implementer | #194 | The implementer's "What you receive" now consumes the provided `.project/` sections; keeps Read/grep for on-demand additional anchors. |
| #188 Wire the triage-reviewer | #195 | The triage-reviewer grounds its five-criteria assessment in the provided `.project/` sections; on-demand reads retained. |
| #189 Wire the design-reviewer | #196 | The design-reviewer grounds its assessment in the provided `.project/` sections; on-demand reads retained. |

### 🧹 Scratch hygiene

| Issue | What |
|---|---|
| #199 Self-ignore per-clone scratch | The driver now ships a **committed** `.milestone-config/.gitignore` that makes its per-clone runtime scratch (`preflight-notice`, `trello-notice`, `triage-cache.json`, `tests-stamp`, plus the `.runtime/` and `worktrees/` dirs) git-invisible in **any** repo the plugin runs in, from the first write, with zero user setup — while the tracked config (`driver.json`, `feeder.json`) stays tracked. The `tests-green` hook (`.sh` + `.ps1`) and the scratch-write steps in `solve-issue` / `solve-milestone` / `triage` self-heal this file when absent, so existing consumer repos pick it up on their next run. Fixes scratch cluttering the consumer's `git status`. |

### Consumer notes (upgrading from v1.11.0)

- **New optional profile key `projectDocs`** in `.milestone-config/driver.json` — a string naming where your project's standing docs live. Default `.project/`; absent-means-default. You do not need to set it unless your house docs live elsewhere.
- **No grounding without docs.** If your repo has no `.project/` directory (or an issue cites no `.project/#section` anchors), every grounding step is a clean no-op — the run proceeds exactly as before, with no error. The feature only activates once you keep house docs under `.project/` and cite their sections in issue bodies.
- **Anchored, never whole-file.** Grounding pulls only the cited `## sections` (plus plausibly-relevant siblings), so per-dispatch token cost scales with cited-section size, not total doc size. A drifted/renamed anchor surfaces as a **loud failure**, not silent empty grounding.
- **New artifact:** `scripts/read-doc-section.{sh,ps1}` (+ `tests/read-doc-section.test.{sh,ps1}`). Dependency-free (POSIX bash / PowerShell 7+ built-ins; no new tooling).
- **Additive to existing gates.** Grounding raises consistency; it changes no gate logic, no five-criteria assessment, and no existing profile key.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.11.0 — Right model for each job: a stronger builder, leaner reviewers

_Released 2026-06-22._

**Theme:** The driver runs several specialized helpers as it works an issue — one that writes the code, and two that check the plan before any code is written. Until now every helper used whatever model the parent session happened to be on. This release assigns each helper to the model tier that fits its job: the **builder** runs on the strongest tier so the code it writes holds up, and the two **pre-build reviewers** run on a leaner, faster tier that an A/B test proved catches the same blocking problems. The result is steadier build quality and less wasted work, at no loss of review rigor.

### ⚙️ Efficiency & quality — model assigned per helper

| Issue | PR | What |
|---|---|---|
| #173 Pin the implementer (code-writer) to the strong tier | #177 | The implementer is the only helper that writes production + test code (test-first, version-correct citations, hard STOP if the approved design doesn't hold). Its model frontmatter changes `inherit` → `opus`, so your code is written by the strong tier regardless of the session model — protecting quality and cutting first-try misses against the driver's ≤2-per-gate retry caps. Also bumps the plugin version to 1.11.0. |
| #176 Pin both pre-build reviewers to the mid tier | #178 | The triage-reviewer and design-reviewer only read and check an issue against five fixed criteria before any code is written; they author nothing. They are the highest-fan-out helpers in a run (~20× triage, ~17× design across a milestone). Both change `inherit` → `sonnet`, so the most-frequent checks run faster and cheaper without weakening the gate. The "genuinely unsure → escalate to Blocker" fail-safe is untouched. |

### 🧪 How we know the leaner reviewers are safe

An A/B test (recorded on the tracking issue) compared models on the reviewers' real job — catching blocking problems before an issue is built:

- **Mid tier (Sonnet): 9 / 9 blocking problems caught — identical to the top tier (Opus 9 / 9).** No real defect slipped through.
- The only cost was one extra false flag on an otherwise-clean issue (a quick human glance, never a missed defect).
- The fastest tier (Haiku) was **disqualified** — it missed a real blocking problem.
- Caveat carried forward: the A/B used text-only fixtures, so the reviewers' repo-grounded dependency/pattern checks weren't exercised. Live-run Blocker recall is being monitored; the reviewers revert to `inherit` if a real Blocker is ever missed.

### 📖 Docs — simpler install

The Quickstart now leads with the **milestone-suite** install path — one marketplace cataloging all three milestone plugins — as the recommended way to install, keeping the per-repo install as a clearly labeled, still-supported alternative. ([#167](https://github.com/kenmulford/milestone-driver/issues/167))

### Consumer notes (upgrading from v1.10.0)

- **No config changes and no schema changes.** Your `.milestone-config/driver.json` is untouched. The only changes are which model each built-in helper uses, plus a README edit.
- **The model pins take effect on your next run automatically** — nothing to set. If you previously relied on the helpers all following your session's model, note the code-writer now always uses the top tier and the two pre-build reviewers always use the mid tier.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v1.10.0 — Deterministic, tested semver extraction for milestone version detection

**Theme:** `solve-milestone` step 3 no longer parses the milestone version by model judgment. A behavior-identical `scripts/extract-version.{sh,ps1}` pair — driven by a shared golden test matrix (`tests/extract-version.cases.tsv`) and two thin runners — deterministically extracts the version from the milestone title (description as fallback) and reports `none` / `ambiguous:<candidates>` on a miss. Step 3 maps that outcome against `versioning` to versioned / version-free / prompt, splitting the previously-identical `absent` vs `true` semantics.

### Consumer notes

- **Behavior change (default `versioning`):** `solve-milestone` now uses a deterministic version extractor. With `versioning` absent (the default), a milestone whose title has no parseable version now **silently runs version-free** instead of parsing-by-judgment/prompting — a consumer relying on the default bump should confirm their milestone titles carry a version, or set `versioning: true` to be prompted on a miss.

### ✨ CI-aware preflight (`preflightCmd: "github-ci"`)

`preflightCmd` now accepts the reserved sentinel `"github-ci"` (alongside today's literal-command mode, unchanged). It auto-derives the preflight gate from the repo's GitHub Actions CI so a cheap CI check (e.g. `npm audit --omit=dev --audit-level=high`) is front-run locally **before** the PR instead of being hand-transcribed and forgotten — closing the gap where an un-transcribed CI check only fails after the PR opens. A behavior-identical `scripts/ci-preflight-steps.{sh,ps1}` pair (golden matrix `tests/fixtures/ci-preflight/` + two runners) parses the local `.github/workflows/*.yml` with a constrained line parser — **no new tool dependency** (no `yq`/`act`/`python`), no network — discovers the PR-gating workflows, and emits each job's `run:` steps in order. `solve-issue` step 6.1 runs them through the existing tool-presence-guard → re-dispatch (cap 2) → park machinery. Skip-rules drop `uses:` steps, secrets / services / deploy, `${{ }}`-interpolated and step-`if:` steps; `working-directory` is honored and `continue-on-error` steps never park. **Loud coverage logging** ("mirrored N, skipped M") and a **silent-under-run guard** (a PR-gating workflow yielding zero runnable steps — e.g. checks behind a `uses:` reusable workflow — is a visible warning, not a clean pass). One optional `ciWorkflow` override narrows discovery to a single workflow. Documented limitations (CI stays the authority): no `uses:`-recursion, no `matrix` expansion, no `act` fidelity, GitHub Actions only. See [#162](https://github.com/kenmulford/milestone-driver/issues/162).

- **No schema break:** `preflightCmd` keeps its literal-command and absent behavior byte-for-byte; `"github-ci"` and the optional `ciWorkflow` key are purely additive.

## v1.9.2 — Make the manual close-the-milestone step explicit

**Theme:** The driver closes a milestone's issues and authors the CHANGELOG, but never closes the GitHub milestone object itself — that stays in the human-owned release tail alongside the `integrationBranch` → `protectedBranch` merge and deploy. This release spells that boundary out and surfaces the exact command, so an operator finishing a clean run isn't left to look up a REST call GitHub gives no first-class command for.

### ✨ Release-tail clarity

| Issue | PR | What |
|---|---|---|
| #153 make the manual close-the-milestone step explicit | #154 | Names closing the GitHub milestone object as a manual, human-only step in both blast-radius statements (`solve-milestone` SKILL + `docs/architecture.md`), and surfaces the `gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed` command in the `🔴 Your move` block and the Final-summary "next human step" bullet — with the caveat that the driver closes the milestone's issues and authors the CHANGELOG but never the milestone itself. |

### Consumer notes (upgrading from v1.9.1)

- **Documentation-only behavior clarification** — no change to how the driver runs. After it merges every issue and authors the CHANGELOG, the release tail now explicitly tells you to close the GitHub milestone object (`gh api -X PATCH repos/{owner}/{repo}/milestones/<number> -f state=closed`) as part of the manual, human-owned release step.
- **No schema changes** to `.milestone-config/driver.json`.
- Milestone #16 also included #152 — locking this repository's own `develop` branch to PR-only to match the governance baseline. That is a change to the author's repo configuration with **no effect on the installed plugin**; it is noted here only for milestone completeness.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none

## v1.9.1 — Finish the `.milestone-config/` relocation: the per-clone runtime markers move out of the repo root

**Theme:** v1.9.0 relocated the **committed** driver profile to `.milestone-config/driver.json`
but left five **per-clone runtime artifacts** still written into the target repo root. This
release moves all five under `.milestone-config/`, dropping the redundant `milestone-driver-`
prefix (the directory already namespaces them), so a fresh run no longer litters the repo
root. Each marker is read **transitionally** — new path first, legacy root as fallback —
and the stale root file is **auto-cleaned on the first write to the new path**, mirroring
the commit-clean two-step read the gate hooks already use for the profile. Existing clones
upgrade silently: no duplicate notice, no cache rebuild, no re-run of an already-green suite.

### ✨ Per-clone runtime markers move under `.milestone-config/`

| Issue | PR | What |
|---|---|---|
| #148 Relocate the 5 remaining root-litter runtime markers | #149 | Move all five per-clone runtime artifacts out of the repo root and under `.milestone-config/`, dropping the `milestone-driver-` prefix: `tests-stamp`, `preflight-notice`, `trello-notice`, `triage-cache.json`, and the `worktrees/` scratch dir. Each persistent marker is read new-path-first with a legacy-root fallback and writes only to the new path (`mkdir -p .milestone-config` / `New-Item -Force` before every write — no writer assumes the dir exists), removing the stale root file on the first new write. The `tests-green` hook (`.sh` + `.ps1`) skips the suite on either path's matching `branch:treeSHA` and clears **both** stamps on red; `triage` reads/writes the cache transitionally on both the `jq` and `ConvertFrom-Json` paths with degradation rules intact; the `preflight-notice` / `trello-notice` one-time markers stay silent if **either** marker exists and clean up the stale root marker when suppressing; the `worktrees/` fleet is a pure path relocation (ephemeral per-run scratch — no fallback read needed). `.sh`/`.ps1` parity preserved. |

### Consumer notes (upgrading from v1.9.0)

- **The five runtime markers now live under `.milestone-config/`.** Existing repos keep working with **no action** — each marker is read from the new `.milestone-config/<marker>` path first and falls back **transitionally** to the legacy root `.milestone-driver-<marker>` so an in-flight clone behaves identically on upgrade (no duplicate preflight/Trello notice, no triage-cache rebuild, no re-run of an already-green unit suite). On the first write to the new path, the stale legacy root file is **automatically removed**.
- **No schema change** and **no config action required.** These markers are per-clone and gitignored — they were never committed. The `.gitignore` adds the five new `.milestone-config/<marker>` paths and **keeps** the legacy root ignores (commented as transitional) so any leftover root file in an existing clone stays ignored until it is cleaned up. The committed `.milestone-config/driver.json` is **not** ignored.
- **Leftover root files self-clean.** A pre-existing `.milestone-driver-tests-stamp` / `-preflight-notice` / `-trello-notice` / `-triage-cache.json` is read once (as the fallback), then removed when the new-path file is first written. A leftover `.milestone-driver-worktrees/` dir is harmless — gitignored and simply unused by the new `.milestone-config/worktrees/` path; remove it at leisure.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v1.9.0 — Suite-wide `.milestone-config/` profile location

**Theme:** The driver profile moves to a canonical `<repo>/.milestone-config/driver.json`,
read transitionally from the legacy root and auto-migrated on the first build — the
precondition the sibling `milestone-feeder` plugin assumes when it reads the driver's
shared keys (`sourceGlobs`, `uiSurfaceGlobs`, `integrationBranch`) from the same directory.
Migration is **commit-clean**: only the commands with a PR path to the integration branch
move the file, so the relocation always lands durably instead of stranding an uncommitted
move on the orchestrator's tree.

### ✨ Canonical `.milestone-config/` profile location

| Issue | PR | What |
|---|---|---|
| #144 Resolve profile from `.milestone-config/driver.json` first | #145 | Resolve the driver profile from `<repo>/.milestone-config/driver.json`, falling back **transitionally** to the legacy root `milestone-driver.json` so gates keep firing on un-migrated repos. All eight gate hooks (`.sh` + `.ps1`) do the two-step read and never mutate (`.ps1` uses the portable multi-arg `Join-Path`). Migration is **commit-clean**: `setup` and `solve-issue` perform the `git mv` (solve-issue on the feature branch at step 3.5, riding the issue PR), `solve-milestone` migrates via its first dispatched build, and `triage` stays read-only — it surfaces a "legacy profile detected" note but never moves the file. Idempotent everywhere; when both files exist `.milestone-config/driver.json` wins (no overwrite, no deletion of the leftover root file). New projects always create at `.milestone-config/driver.json`. |

### Consumer notes (upgrading from v1.8.1)

- **Canonical profile location is now `.milestone-config/driver.json`.** Existing repos keep working with **no action** — the legacy root `milestone-driver.json` is still read transitionally. On the first `setup` or `solve-issue` build, a legacy root profile is automatically **moved** (`git mv`) to `.milestone-config/driver.json`; `solve-milestone` migrates via its first dispatched build, and `triage` is read-only (it only surfaces the detection). When both files exist, `.milestone-config/driver.json` wins and the leftover root file is left untouched for you to remove (no `.gitignore` change is made).
- **No schema change** to the profile — the keys are identical; only the file location moved (and the canonical filename inside the directory is `driver.json`). Add new keys like `preflightCmd` / `integrations.trello` to `.milestone-config/driver.json` going forward.
- **PowerShell gate hooks** now resolve the new path with the portable multi-arg `Join-Path` form (PowerShell 7+).

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v1.8.1 — Surface what the engine already does (and fix the capture defect underneath)

**Theme:** Most of this milestone is making existing capability *visible* — fewer
false triage Blockers, a triage cache that says when it skips, the wave trade-off
surfaced at the setup decision point — sitting on one real reliability repair: the
parallel barrier now reads git/gh ground truth instead of trusting a worker's
free-text handback. Plus a cross-platform gate fix reported from the field.

### ✨ Surfacing the engine's existing behavior

| Issue | PR | What |
|---|---|---|
| #135 setup Integration tier | #141 | Adds an optional **Integration tier** to `/milestone-driver:setup` for `integrationGranularity` (an already-existing schema key that was never prompted), defaulting to `issue`. Choosing `wave` fires a non-blocking precondition prompt — *is `preflightCmd` set? is `unitTestCmd` your full suite?* — surfacing the "one red wave-PR CI blocks the whole Wave" trade-off where the choice is actually made. Default stays `issue`; `"full suite?"` is a human question, not a machine check. |
| #134 visible cache writes | #139 | The best-effort triage cache write no longer fails **silently**: the Bash path emits a stderr line on `jq`-absent and on write-fail, the PowerShell `catch` surfaces a `Write-Warning`, and the Step 5 output line gains a conditional `; cache write skipped this run` clause. The never-gating contract is unchanged — only silence became a visible warning. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #132 barrier reads ground truth | #137 | The `--parallel` Phase 1 barrier now **re-derives each worker's terminal state from git/gh** (the `solve-issue` step-3 probe) instead of trusting the worker's free-text final-message handback — fixing the ~37% handback **tail-drop** and the hand-finish **race**. The handback is demoted to an optimization hint; the happy-path partition is byte-identical. |
| #133 fewer false triage Blockers | #138 | `triage-reviewer` downgrades a choice an established repo convention or sibling pattern already answers from **Blocker** to **Advisory** (criterion 2 carve-out + a severity-rule row), so routine calls no longer trip a manual filtering pass. Genuine ambiguity still escalates to Blocker; no new mechanism (Advisory is already non-gating). |
| #136 Unix gate exec bit | #140 | `hooks/run-hook.cmd` was committed mode `100644`, so on macOS/Linux `/bin/sh -c` couldn't `exec` it (`EACCES`, exit 126) and **every PreToolUse gate was silently inert on Unix**. Now committed `0755`. Cross-platform safe (Unix no-shebang → `ENOEXEC` → `sh` fallback; Windows unchanged). Reported and verified by @gcpeacock-npm. |

### Consumer notes (upgrading from v1.8.0)

- **🔴 macOS/Linux: all gates now actually run.** Before this release, `hooks/run-hook.cmd` shipped non-executable, so every milestone-driver PreToolUse gate (`force-subagent`, `no-bom`, `tests-green`, `no-push`, `no-pr-to-protected`) died with "Permission denied" on Unix and was silently inert. After updating to 1.8.1 the packaged launcher is `0755` and the gates fire. If you applied the `chmod +x` cache workaround, it is no longer needed.
- **New `/milestone-driver:setup` Integration tier** offers `integrationGranularity`. **No schema change** — the key already existed; setup just prompts for it now (default `issue`, absent-means-issue). Existing profiles need no migration.
- **Triage: fewer false Blockers.** Choices an established convention/sibling pattern answers are now Advisory (logged, non-gating) rather than parking the issue — expect fewer manual clarifications.
- **Triage cache writes are now observable** — a skipped/failed write prints a one-line warning instead of nothing; the run is otherwise unchanged (still best-effort, never-gating).
- **`--parallel` is more robust to dropped worker handbacks** — no behavior change on the happy path; the barrier just no longer strands a built branch when a worker's final message drifts off-format.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: none.

## v1.8.0 — Optional Trello board sync + auto-authored release notes

**Theme:** milestone progress optionally mirrors to a Trello board — a card per
milestone that moves through Queue → In Progress → In Review with a per-issue
checklist — and the release notes you are reading now author themselves at
milestone completion. Both are opt-in and best-effort; absent their config, the
loop is byte-unchanged.

### ✨ Trello integration (the #99–#104 family)

| Issue | PR | What |
|---|---|---|
| #99 Profile node + setup tier | #123 | New optional `integrations.trello` profile node (`boardId` required when present; `lists.queue`/`inProgress`/`inReview` default independently to `Queue`/`In Progress`/`In Review`) and an "External integrations" tier added last in `/milestone-driver:setup` (suppressed on auto-bootstrap). Presence enables; absence skips silently. |
| #100 trello-sync.md + run-start resolution | #125 | New `skills/solve-milestone/trello-sync.md` reference (read only when `integrations.trello` is present — zero token cost otherwise) holding all ten sync conventions: best-effort wrapper, availability probe, ensure-list auto-create, card-resolution order (back-link anchor → name-match → create), idempotent `<!-- trello: … -->` back-link, card state machine, and main-thread-only thread safety. Adds the run-start card resolution (SKILL.md step 3.5) and the one-time upgrade notice (step 1.2). |
| #101 Phase 0 hooks | #128 | After triage, posts the triage summary (all-clear or gap table + Wave graph) as a card comment and moves Queue → In Progress when ≥1 issue is buildable; all-parked leaves the card in Queue with an explanatory comment. |
| #102 Loop hooks | #126 | Ticks the card's `#<n>` checklist item when an issue merges (visual-gate holds excluded), under both issue and wave granularity; in `--parallel`, ticks fire in the serial merge tail on the main thread. Per-item best-effort. |
| #103 Finish hooks | #127 | Posts the final-summary card comment (merged / parked / open `needs review` PRs / skipped Trello updates) and moves In Progress → In Review only when zero open issues carry a blocker label; parks-remaining stays In Progress with a comment; a systemic halt posts the comment but does not move. |
| #104 Docs + dogfood | #129 | README "Optional integrations" paragraph and a `docs/consumer-setup.md` "Trello integration (optional)" section: the MCP-prerequisite distinction, both enablement paths, the tracked lifecycle, and the four known limitations — cross-linked to `profile-schema.md` and `trello-sync.md` with no duplication. Dogfood recorded as a manual lifecycle walkthrough on the issue. |

### ✨ Release automation

| Issue | PR | What |
|---|---|---|
| #121 Auto-author the CHANGELOG | #124 | When a `solve-milestone` run ends with every issue merged (no parks, no holds), the orchestrator authors a `## v<version>` CHANGELOG entry as a final doc-only PR to the integration branch — themed `\| Issue \| PR \| What \|` tables (the "What" distilled from each merged PR's summary, title fallback), Consumer notes, and a Post-run audit trail. Idempotent (heading-prefix match), skips on any park/hold, and headed by the milestone title in version-free mode. This entry is the first one it produced. |

### Consumer notes (upgrading from 1.7.0)

- **New optional profile node `integrations.trello`** (additive — no migration).
  Absent → every Trello step skips silently and the loop is byte-unchanged.
  Present → requires the `@delorenj/mcp-server-trello` MCP server loaded in your
  Claude Code session; the plugin itself has no Trello dependency.
- **Enable it** by re-running `/milestone-driver:setup` (the External
  integrations tier is last; existing values pre-fill) or by hand-adding the
  node — see `docs/consumer-setup.md`.
- **New gitignored marker:** `.milestone-driver-trello-notice` at the repo root
  (drives the one-time upgrade notice). Safe to delete.
- **Release notes now author themselves.** A fully-completed milestone run ends
  with a CHANGELOG PR; a run with any park or hold authors nothing (a later
  completing re-run authors them then).

### ⚖️ Post-run audit trail

No `judgment call` PRs this release. All seven PRs (#123–#129) carry a
`## Code Review` section with their findings and resolutions.

## v1.7.0 — Interactive background orchestration, scannable output, triage reuse

**Theme:** the orchestrator no longer clogs the main conversation line, the run is
human-scannable at a glance, and repeat runs stop paying the re-triage tax.
Includes the 1.7.1 triage-reuse milestone, rolled in.

### ✨ Background orchestration (the #89 family)

| Issue | PR | What |
|---|---|---|
| #89 Chunked background dispatch | #112 | The milestone loop dispatches each issue (sequential) or each Wave's workers (`--parallel`) via `Agent(run_in_background: true)`. The main line stays interactive; the operator can redirect between chunks. Standalone `solve-issue` gains an opt-in `--async` token (full pipeline unchanged except the version-bump confirm defaults to patch, logged as a judgment call). |
| #95 Permission pre-flight gate | #109 | Background subagents auto-deny any tool call that would prompt — so before the first background dispatch, the gate verifies the union of readable `permissions.allow` layers (user + project + local) covers the pipeline's tool surface. Gap → 🔴 gap table + synchronous fallback. Workers convert mid-chunk auto-denies to parks. |
| #97 Main-line push notifications | #113 | One notification per event that matters: `⏸️ #N parked — <reason>`, `🌊 Wave N done` (suppressed on the final Wave), `🏁` run complete / `🚨` systemic halt. Emitted by the main line only — a live probe confirmed `PushNotification` does not exist in subagent registries. |

### ✨ Scannable output

| Issue | PR | What |
|---|---|---|
| #96 Output spec | #105 | Shared icon legend + three structured templates: run-start plan board, chunk-boundary status update, final results board. Tables and icons replace free-form narration at every reporting point. |
| #116 Output-spec polish | #118 | The six accepted findings from #105, operator-decided: PR-cell emit rule ("show the PR number if the issue has one, else —"), one `[..]` placeholder convention, `🔴 Your move` casing, definition-before-reference section order, continuous example cast (#201/#202/#203) across all three templates. |

### ✨ Triage reuse (1.7.1, rolled in)

| Issue | PR | What |
|---|---|---|
| #106 Step-0 context handoff | #111 | `solve-issue` step 0 reuses the milestone run's Phase 0 triage result when the caller explicitly supplies it (named-value fields in worker briefs; inline restatement sequentially) — eliminating the intra-run N+1 re-triage. Anything not explicitly supplied falls back to fresh single-issue triage. |
| #107 Per-issue result cache | #110 | `.milestone-driver-triage-cache.json` (gitignored) caches per-issue triage results keyed on change signals (labels, body edit time, comment count, milestone description). Unchanged issues skip agent dispatch across invocations; any change — including upstream edges closing unmerged — forces fresh triage. Absent/corrupt cache degrades to full re-triage. |

### 🔧 Fixes

| Issue | PR | What |
|---|---|---|
| #98 Milestone ID or name | #108 | `solve-milestone 10` and `solve-milestone "1.7.0"` now both resolve (number-first for numeric input, paginated title lookup otherwise, fail-fast table of available milestones). |
| #114 Contradictory gate paragraphs | #117 | Deleted two stale STOP-flavored duplicates left by the 1.6.0 autonomy rewrite — park-don't-prompt is now the single directive at the red-suite cap and the `/code-review`-omission gate. |
| #115 Park-reason lookup + park anchor | #119 | Build-park comments now open with the canonical `🔴 Parked — ` anchor (joining `🔴 Triage` and `🔴 Blocked`), making the final summary's park-reason lookup a pure prefix match: last matching comment, any run (cache hits post no fresh comment). No match → "park reason not recorded" — never a guess. |

### Consumer notes (upgrading from 1.6.0)

- **Allowlist before backgrounding.** Background dispatch activates only when the
  pre-flight gate passes. Run `/fewer-permission-prompts` (or allowlist your
  git/gh/test commands) to enable it; otherwise runs fall back to today's
  synchronous behavior.
- **New gitignored artifact:** `.milestone-driver-triage-cache.json` at the repo
  root. Safe to delete at any time (next run re-triages fresh).
- **Park comments changed shape.** New parks open with `🔴 Parked — `. Issues
  parked by pre-1.7.0 runs report "park reason not recorded (pre-1.7.0 park
  format)" in final summaries — read the issue directly for those.
- **No schema changes** to `milestone-driver.json`. All 1.7.0 behavior works with
  an existing profile.

### ⚖️ Post-run audit trail

Judgment-call PRs for this release: #105, #109, #110, #113, #119 (#115). Each
carries its accepted findings and rationale in its Code Review section.
