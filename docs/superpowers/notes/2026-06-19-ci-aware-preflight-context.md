# CI-aware preflight — design context (pre-brainstorm capture)

> **Status: PRE-BRAINSTORM capture of an in-flight discussion — NOT an approved spec.**
> Captured 2026-06-19. This records the substance of a design conversation so it
> survives the session. No decisions here are final; the forks below feed a future
> brainstorm. See "Sequencing" in Open questions for the intended path to a spec.

## Origin / trigger

- In the **counseling-reimbursement** repo, CI runs:
  ```
  npm audit --omit=dev --audit-level=high --package-lock-only
  ```
  It failed.
- That check is **not** in milestone-driver's `preflightCmd` (which a consumer
  hand-lists). So it wasn't front-run locally; the failure only surfaced in CI.

## The gap (precise failure modes)

milestone-driver's `preflightCmd` is a consumer-transcribed list of fast checks.
Any CI check the consumer didn't transcribe isn't front-run before the PR. There
are two failure modes:

| # | CI check type | What happens | Why it's bad |
|---|---|---|---|
| 1 | **Required status check** | solve-issue's auto-merge-on-green (step 8) correctly **BLOCKS** — no bad merge. | The run already "completed" and left a red PR needing a human round-trip. This is exactly what preflight exists to prevent. |
| 2 | **Non-required (just runs)** | Auto-merge proceeds on the required checks' green. | The failure lands on the integration branch **unnoticed**. |

## Why this is aligned with preflight's stated purpose

`docs/architecture.md` (Preflight section) already states preflight's whole job is
"moving a red result earlier, before the PR… CI stays the authority."

Auto-deriving preflight from CI makes preflight **BE** "the cheap CI checks, run
early" — instead of a hand-transcription a consumer forgets to keep in sync.

## Scope pushback (important)

Faithfully running **any** GitHub Actions workflow locally is **intractable**:

- `uses:` marketplace actions
- runner-OS differences
- matrix expansion
- `${{ secrets.* }}`
- service containers
- deploy/publish steps

Trying to run all of it produces **false-failure parks** — a step that fails
locally for environment reasons, not a real defect. That is **worse than the gap**,
because it blocks clean work.

The achievable, honest scope:

> **Discover the PR-gating workflow's shell `run:` steps and execute the
> environment-independent subset locally; CI stays the authority for everything
> else.**

The `npm audit` case is the **IDEAL case** — environment-independent, deterministic,
fast, no secrets, no services (reads `package-lock.json`). The whole
valuable-to-front-run class (audit, lint, typecheck, format, unit) shares those
properties.

## Key design decisions (the forks, for the brainstorm)

| Decision | The fork |
|---|---|
| Discovery source | `.github/workflows/*.yml` only (sentinel name `"github-ci"` fits) **vs** multi-CI (GitLab/Circle/Azure) |
| Which workflow/job | Heuristic (workflows triggered on `pull_request`/push to `integrationBranch`) **vs** explicit `ciWorkflow`/`ciJob` selector |
| What to run | shell `run:` steps only; **SKIP** `uses:` steps, steps referencing `secrets`/`services`, and deploy/publish |
| Env fidelity | best-effort local toolchain (document the gap) **vs** `act`-in-Docker for true fidelity (heavy dependency) |
| False-failure discrimination (the hard part) | distinguish "real check failed" from "couldn't run locally"; the skip-rules above are the mitigation |
| Config shape | `preflightCmd: "github-ci"` sentinel **vs** a new `preflightSource` key (keeps explicit-command mode intact); must coexist with today's explicit-string `preflightCmd` |
| Setup-step dependency | many checks need a setup step first (e.g. `npm ci`); decide whether discovery includes prerequisite `run:` steps |

## Recommendation (current lean)

**Sentinel + skip-rules approach (NOT `act`):**

- Discover + run the environment-independent shell `run:` steps from the PR-gating
  workflow/job.
- CI stays the authority.
- Document the fidelity gap explicitly.
- Offer `act`-in-Docker as a documented **FUTURE opt-in** for full fidelity.

## Cross-references (in milestone-driver)

- `docs/architecture.md` — Preflight (optional) section (preflight's stated
  rationale: front-run CI, CI is authority).
- `skills/solve-issue/SKILL.md` — step 6.1 preflight gate (re-dispatch on non-zero,
  cap 2, park) and step 8 auto-merge-on-green.
- `docs/profile-schema.md` — the `preflightCmd` key.

## Open questions for the brainstorm

- **Exact config shape:** overload `preflightCmd: "github-ci"` vs a dedicated
  `preflightSource` key? How does it coexist with an explicit `preflightCmd` string
  (run both? sentinel-only?).
- **Workflow/job scoping:** how to scope to the right workflow/job deterministically
  (heuristic vs explicit selector vs both).
- **Prerequisite setup steps:** how to handle setup steps (`npm ci`) that the
  env-independent checks depend on.
- **False-failure discrimination policy:** when a discovered step fails, is it a real
  failure → re-dispatch/park, or an environment artifact → skip+log?
- **Non-GitHub CI support** (later?).
- **Sequencing:** this is a fresh milestone-driver feature → its own issue +
  brainstorm → spec → plan, **AFTER** issue #158 (deterministic semver extraction)
  lands.
