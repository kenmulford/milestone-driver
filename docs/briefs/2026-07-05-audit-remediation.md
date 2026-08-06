# Brief: audit remediation — milestone-driver

**Goal.** Keep the engine (its gating logic audited sound and self-aware) and cut its self-inflicted costs: two monolithic SKILL.mds that load ~19.7k/~15.9k tokens per invocation even for plain sequential runs, ~1,930 tokens of session-start frontmatter, a marketing claim the docs themselves contradict, and one gate (/code-review) with zero mechanical enforcement. Also make the already-correct ground-truth verification resumable across session/context loss.

**Constraints to hold across all items:**
- The existing discipline is the asset: the Phase-1 barrier's distrust-the-handback re-derivation, the triage cache's live-key invalidation, and the resolve-.project/-once-distribute-slices seam must survive every refactor unchanged in behavior.
- All hooks/scripts stay dual-platform (bash + pwsh) with matching tests, and bash must run under macOS system bash 3.2 — no `${var,,}` (this exact construct silently disabled two user-level hooks; audit 2026-07-05).
- Never author application/test code on the main thread; the implementer dispatch model is unchanged.

---

## 1. Progressive-disclosure split of the two monolithic skills

**Evidence:** skills/solve-milestone/SKILL.md is 14,811 words (~19,700 tokens); skills/solve-issue/SKILL.md is 11,918 (~15,850). Both inline every conditional mode — worker mode, async mode, parallel Phase 1/2, md-epic fan-out (solve-issue:323-475 loads Worker+Async+parent-issue detection on a plain sequential run). The repo already demonstrates the right pattern: trello-sync.md (3,144 words) loads only when integrations.trello is configured (solve-milestone:11).

**Work:** Factor each conditional mode into references/ files loaded only when its trigger is detected (worker token → references/worker-mode.md; --async → references/async-mode.md; md-epic label → references/md-epic-fanout.md; parallel wave path → references/parallel-waves.md). Core SKILL.md keeps Before-starting, the numbered sequential procedure, and the autonomy model.

**Acceptance:** a plain sequential solve-issue run loads only the core file; each mode doc loads on exactly its trigger; core files land under the official <500-line SKILL.md guidance; all existing tests pass.

## 2. Trim the three agent frontmatter descriptions (~900 tokens/session back)

**Evidence:** design-reviewer.md 435 words, triage-reviewer.md 376, implementer.md 283 — each with 3 `<example>`/`<commentary>` blocks in frontmatter, loaded every session regardless of use. Combined with 4 skill descriptions, this plugin's session tax is ~1,930 tokens.

**Work:** Cut each to ~60–100 words (purpose + read-only/no-code-authoring constraint + when-to-dispatch); move examples into the body (loads only on dispatch).

**Acceptance:** total agent-description words ≤ 300; dispatch routing unchanged in a triage + solve-issue run.

## 3. Mechanical backstop for the /code-review gate

**Evidence:** docs/profile-schema.md:297 states plainly the plugin ships no PreToolUse hook for code review — the one gate solve-issue calls "a park trigger, not permitted to omit" (solve-issue:196) is entirely self-policed; an orchestrator under pressure can assert "reviewed" and nothing catches it before merge.

**Work:** Add a PreToolUse hook (bash + pwsh + tests, like the existing four) matching `gh pr create` / `gh pr merge` that greps the PR body (or the body file argument) for a `## Code Review` heading and blocks with a clear message otherwise. Deterministic grep, no LLM judgment. Honor the same `CLAUDE_HOOK_DISABLE_*` escape-hatch convention and fail-open posture as the existing hooks, and document it in profile-schema.md's enforcement table.

**Acceptance:** `gh pr create` with a body lacking the heading is blocked (exit 2) in the hook's test suite; with the heading it passes; jq-missing and env-var-disabled paths fail open, matching the other four hooks.

## 4. Unify the three near-identical gate sections into one loop

**Evidence:** the unit gate (solve-issue:159-166), E2E gate (168-180), and preflight gate (205-212) all follow the same shape — run check → non-zero → re-dispatch implementer with the failure → cap 2 → park — but are three hand-written sections that have already drifted (the unit gate invokes superpowers:verification-before-completion; the preflight gate doesn't mention it).

**Work:** Resolve the ordered gate list once after implementer dispatch (built from profile flags already read at Before-starting step 1: unit?, e2e?, code-review, preflight?), then a single act→verify→retry(cap 2)→park loop body iterates it. One table of gates, one loop.

**Acceptance:** the three sections collapse to one loop + a gate table; the verification-skill mention applies uniformly; skill body shrinks; gate behavior on a red unit suite is byte-for-byte the same park flow as today.

## 5. Persist the Wave barrier's ground truth: wave-state.json

**Evidence:** the Phase-1 barrier correctly re-derives each worker's terminal state from git+gh (solve-milestone:~397-417) rather than trusting handbacks — but the derived state lives only in session context. A context compression or session restart mid-milestone forces a full re-probe of every issue (solve-issue:363's fallback), or worse, trust of a stale summary.

**Work:** After each worker's re-derivation, append `{issue, wave, status: built-green|parked, pr, isUI}` to `.milestone-config/.runtime/wave-state.json`. Barriers and resumed sessions read the file first and re-verify only entries absent or younger than their PR's last update.

**Acceptance:** killing a solve-milestone run mid-Wave and re-invoking resumes without re-probing completed issues; deleting the file falls back to today's full probe; the file is git-ignored (matches .milestone-config/.runtime convention).

## 6. Deduplicate the triage stale-edge re-checks within a run

**Evidence:** triage's cache (Step 2.5/6.5) is the best state-file pattern in the suite, but the stale-edge invalidation (triage:123-125) re-fetches every referenced dependency's live state on every HIT candidate — the same issues re-queried across consecutive triage calls in one milestone run.

**Work:** Fold the stale-edge result into the cache entry with a short TTL, or a run-scoped memo keyed by issue number, so each dependency is fetched at most once per run.

**Acceptance:** a triage pass over N cached issues sharing M dependencies makes M dependency fetches, not N×M; invalidation behavior on a genuinely changed dependency is unchanged.

## 7. One-time notices: shared table instead of byte-identical blocks

**Evidence:** four notice blocks (preflight, Trello, visual-capture, parallel-default) are hand-copied between solve-milestone (lines ~39-101) and solve-issue (~33-67) with literal "KEEP THIS NOTICE BLOCK BYTE-IDENTICAL" comments — sync enforced by comment, verified by nothing.

**Work:** One data table (marker file, trigger, text) in a shared reference; both skills run the same three-line loop over it.

**Acceptance:** notice text exists once; the byte-identical comments are gone; both skills' Step-1 notices render identically to today.

## 8. Honesty and translation pass (one PR)

- plugin.json description: replace "un-bypassable" with accurate phrasing ("mechanical hooks that block the common bypass paths; env-var override documented") — all four hooks honor `CLAUDE_HOOK_DISABLE_*` and fail open without jq/profile (hooks/*.sh:5; profile-schema.md:281-282 already admits this).
- README.md:138 says "v1.9.0" while plugin.json is 1.15.0 — six releases stale. Drop the version literal; point at CHANGELOG.md.
- Gloss internal jargon on first reader-facing use: `md-epic` in README.md:119 ("short for: this issue is really a multi-milestone feature"), "Phase 1/Phase 2" and "barrier cascade" in docs/architecture.md.
- profile-schema.md visualCapture: one line stating it's a web/HTTP-server shape — native UIs (MAUI/WPF) should omit the block and use the documented PR-open-for-human-test degradation.
- Reformat the Before-starting profile-resolution run-on paragraph (solve-issue:14, solve-milestone:20) as the same style of table already used at solve-issue:84-90.

**Acceptance:** each text lands at the named location; no remaining "un-bypassable" claim; no bare version literal in README prose.

## 9. CI size budgets

**Work:** CI step failing when a core SKILL.md exceeds its post-split ceiling or an agent description exceeds 150 words — the mechanism that keeps items 1–2 from regrowing (the feeder repo's trim regrew 3.4x without one).

**Acceptance:** red on oversized fixture, green on post-split tree.

---

**Out of scope:** a vendor-agnostic external-tracker seam (trello-sync.md stays the single implementation until a second consumer exists — profile-schema.md:68's own rule); any change to model-tiering pins; multi-forge support.

**Build-order hint:** 8 is standalone (wave 1); 2 standalone (wave 1); 1 → 4 → 7 touch the same files, sequence them (waves 2–3); 3, 5, 6 independent (wave 2); 9 last.
