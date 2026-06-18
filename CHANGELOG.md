# Changelog

Release notes for milestone-driver. Versions before 1.7.0 are documented on the
[GitHub Releases page](https://github.com/kenmulford/milestone-driver/releases).

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
