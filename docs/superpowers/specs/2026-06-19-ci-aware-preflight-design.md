# CI-aware preflight (`preflightCmd: "github-ci"`) — design

- **Issue:** TBD (to be filed)
- **Milestone:** TBD (1.10.0 or its own)
- **Status:** design — pending architect review + user approval, then implementation plan
- **Date:** 2026-06-19
- **Prior capture:** `docs/superpowers/notes/2026-06-19-ci-aware-preflight-context.md`

## Problem

milestone-driver's `preflightCmd` is a **hand-transcribed** command a consumer lists in the profile.
Any CI check the consumer didn't transcribe isn't front-run before the PR. Real incident: the
**counseling-reimbursement** repo's CI runs `npm audit --omit=dev --audit-level=high
--package-lock-only`; it's not in `preflightCmd`, so it only failed *in CI*, after the PR opened.

| # | CI check type | What happens | Why it's bad |
|---|---|---|---|
| 1 | Required status check | auto-merge-on-green (solve-issue step 8) correctly **blocks** | Run "completed" but left a red PR → human round-trip (exactly what preflight exists to prevent) |
| 2 | Non-required (just runs) | auto-merge proceeds on the required checks' green | Failure lands on the integration branch **unnoticed** |

## Goal / non-goal

- **Goal:** let a consumer say "run my CI's cheap checks locally before the PR" without
  transcribing them — auto-derive preflight from the repo's CI.
- **Non-goal:** faithfully replicate CI. Running *any* workflow locally is intractable (`uses:`
  actions, runner OS, matrix, secrets, services, deploy). **CI stays the authority.** This only
  front-runs the environment-independent shell checks (audit/lint/typecheck/format/test).

## Design

### 1. Config — a reserved sentinel

`preflightCmd: "github-ci"`. The existing key accepts **either** a literal command (today's
behavior, unchanged) **or** the reserved value `"github-ci"`, which switches to CI-discovery mode.
Mutually exclusive with a literal command — rationale: if a check matters, it's already in CI.
Extensible to future sentinels (e.g. `"github-ci:act"`). No new required key.

### 2. Discovery + scoping

- **Default (zero-config):** discover workflows triggered on `pull_request` (or push to
  `integrationBranch`); within them, take every job's `run:` steps **in order**.
- **Skip-rules** (drop what can't/shouldn't run locally): `uses:` steps; any step referencing
  `secrets`, service containers, or deploy/publish.
- **Optional override:** `ciWorkflow` / `ciJob` profile keys narrow or correct the heuristic when
  it picks the wrong (or too-broad) target.

### 3. Execution + failure policy

- Run non-skipped steps **in order** in the repo root against the feature-branch working tree
  (so `npm ci` precedes `npm audit` — prerequisite steps are handled by ordering, not special-casing).
- **Tool-presence guard:** before a step, if its leading tool isn't on `PATH`, **skip + log**
  "couldn't run locally (`<tool>` absent)". This kills the dominant false-failure (missing toolchain)
  without fragile output-parsing.
- A step that runs and exits non-zero = **real failure** → re-dispatch the implementer (cap 2),
  then park `blocked` — **identical to today's preflight gate** (no new failure machinery).
- **Log every skip/run/result** so the operator sees exactly what was mirrored vs skipped.

### 4. Integration point

Slots into **solve-issue step 6.1** — the existing preflight gate (after `/code-review`, before the
version bump/commit). The discovery component emits an ordered, filtered step list; step 6.1 runs
those steps through the **existing** re-dispatch/cap/park machinery. `solve-milestone` is unaffected
(preflight is per-issue). Absent `preflightCmd` → gate skipped, unchanged.

## Key implementation risk (headline plan-time decision)

**Parsing GitHub Actions YAML has no zero-dependency cross-platform path.** The nonNegotiable
toolchain is "bash (`jq`) + PowerShell 7+". `jq` does not parse YAML, and PowerShell has no built-in
YAML parser. Robustly extracting `run:` / `uses:` / `secrets` / `services` realistically requires a
parser such as **`yq`** — which is a **new tool dependency**, itself a STOP-and-decide gate in
milestone-driver. The plan must resolve this:

| Option | Trade-off |
|---|---|
| Add `yq` dependency | Robust YAML parsing; but a new required tool (consumer must install) — breaks "jq-only" |
| `python3` + PyYAML | Common on dev machines; still a dependency, and PyYAML isn't stdlib |
| Constrained grep/line parser | Zero new dep; fragile against real-world YAML (anchors, multiline `run: |`, flow style) — high false-skip/false-include risk |

This risk does not change the *design* (mechanism/config/scoping/failure policy are sound regardless),
but it gates *feasibility-as-jq-only* and likely forces a dependency decision.

## Boundaries / out of scope

- **GitHub Actions only** (the `"github-ci"` name says so). Other CI providers (GitLab/Circle/Azure)
  are future work.
- **`act`-in-Docker** is a documented **future opt-in** for full-fidelity runner replication — not
  this version.
- **Fidelity gap is documented, not closed:** local toolchain ≠ CI runner; secrets/services/matrix
  are skipped. CI remains authoritative; this only moves cheap red results earlier.

## Open decisions

1. **The YAML-parser dependency** (the headline risk above) — resolve at plan time or pre-decide.
2. **Milestone** — 1.10.0 (alongside #158) or its own.
3. **Follow-up already owed:** `setup/SKILL.md` "absent-means-versioned" staleness from #158 — a
   separate small issue, noted here so it isn't lost.

## Architect review (2026-06-19) — SOUND-WITH-GAPS

Mechanism and failure policy are sound; "park-is-recoverable" justifies the conservative
discrimination. Gaps to resolve before/within the plan:

1. **YAML-dependency is likely a false trichotomy — prefer `gh`-narrow over `yq`.** `gh` is already a
   hard prerequisite; `gh api` / `gh workflow view` can retrieve workflow content, and the design
   only needs a *narrow* extraction (`run:` strings + `shell`/`working-directory`/`if` + a `uses:`
   flag), not full YAML semantics. Reframe the decision as **"narrow extraction via existing `gh`"
   vs "general YAML via `yq`"** — the zero-dep path is viable and fits the plugin ethos.
2. **Biggest risk — silent under-run.** If the real checks live behind a `uses:` reusable workflow /
   composite action, the "drop `uses:`" rule skips exactly what it exists to front-run and reports a
   clean pass — recreating the gap with false confidence. Must detect-and-log this; treat "PR-gating
   workflow found but zero runnable steps extracted" as a **visible warning, not a clean pass**, and
   always log "discovered N steps, skipped M, mirrored these check names."
3. **`run:` extraction under-models execution context.** Add to the skip/handle rules:
   `defaults.run.shell`, `working-directory` (monorepos!), `env:`/`matrix`/`${{ }}` interpolation in
   `run:` (unrunnable as raw text → skip+log), step-level `if:` (e.g. gated on `github.event_name`),
   and `continue-on-error: true` (cannot be a "real failure").
4. **Document residual false-failure classes** (acceptable, since park-is-recoverable): network-
   dependent audits, local-vs-CI version skew, missing lockfile/`node_modules` state.
5. **YAGNI:** ship the zero-config heuristic with **one** optional override key, not two
   (`ciWorkflow` + `ciJob` before a real mis-target violates the schema's "new keys only when a real
   consumer needs them" rule).
6. **Worker-mode nuance (for the gate-integration piece):** a CI-derived step can be server-starting;
   the discovery component must classify each step static-vs-port-binding so `--parallel` worker mode
   routes it correctly (static in-worktree; port-binding deferred to the serial tail).

**Recommended decomposition (hard ordering):** **[A]** resolve extraction/dependency (`gh`-narrow vs
`yq`) — a STOP-and-decide pre-decision/spike → **[B]** the discovery+scoping component (emit ordered,
filtered, static/port-binding-classified step list) → **[C]** thin gate integration at solve-issue
step 6.1 (iterate the list through existing re-dispatch/cap/park machinery).

## Build decision (locked 2026-06-19)

Pragmatic MVP — ship the version that closes the real gap, defer the rest as documented limitations.

- **Extraction:** **`gh`-narrow, NO new dependency.** Retrieve workflow content via the already-required
  `gh`; parse only the narrow surface needed (`run:` strings + `shell` / `working-directory` / `if` +
  a `uses:` flag). No `yq`, no `act`, no `python`.
- **In scope (MVP):** the sentinel `preflightCmd: "github-ci"`; PR-gating-workflow heuristic; in-order
  execution; skip-rules (`uses:`, secrets, services, deploy, plus `${{ }}`-interpolated and step-`if:`
  steps → skip+log; honor `working-directory`; `continue-on-error` steps never count as a real
  failure); tool-presence guard then failure=real→park; **loud coverage logging** ("mirrored N checks,
  skipped M (reasons)") and the **silent-under-run guard** — a PR-gating workflow with zero extracted
  runnable steps (e.g. real checks behind a `uses:` reusable workflow) is a **visible warning, not a
  clean pass**; **one** optional override key (`ciWorkflow`).
- **Deferred (documented limitations, not built):** recursing into `uses:` reusable/composite workflows
  (warn instead), `matrix` expansion, `act`-fidelity, non-GitHub CI, a second `ciJob` override key, and
  per-step static/port-binding classification for `--parallel` worker mode (MVP runs in the static
  preflight slot; document the server-starting-step edge — scope it out via the override if hit).
- **Milestone:** 1.10.0 (alongside #158). **One issue**, not the architect's 3-way decomposition —
  the [A] extraction decision is pre-resolved (gh-narrow) so [B]+[C] are one cohesive build.

## Cross-references

- `skills/solve-issue/SKILL.md` — step 6.1 preflight gate (re-dispatch/cap/park) + step 8 auto-merge.
- `docs/architecture.md` — Preflight (optional) section (front-run CI; CI is authority).
- `docs/profile-schema.md` — the `preflightCmd` key (+ the new `ciWorkflow`/`ciJob` override keys).
