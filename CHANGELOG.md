# Changelog

Release notes for milestone-driver. Versions before 1.7.0 are documented on the
[GitHub Releases page](https://github.com/kenmulford/milestone-driver/releases).

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
