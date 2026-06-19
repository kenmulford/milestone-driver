# Deterministic semver extraction for milestone version detection

- **Issue:** #158
- **Milestone:** 1.10.0
- **Status:** design approved (brainstorming), pending implementation plan
- **Date:** 2026-06-19

## 1. Context & goal

`solve-milestone` step 3 ("Determine the target version") currently parses the milestone
name/description for "a semantically valid version" using model judgment, and **prompts** if it
can't. That is non-deterministic (the model is the parser) and the prompt is at odds with the
skill's unattended ethos.

**Goal:** replace the parse with a **deterministic, cross-platform, unit-tested extractor script**,
and replace the always-prompt fallback with a policy keyed on the `versioning` profile value.

**Determinism boundary (honest):** the *extraction / precedence / ambiguity* logic becomes
engine-deterministic and testable. The model still decides to invoke the script, passes it the
milestone title/description, and reads its stdout. That thin orchestration layer is not
engine-guaranteed; everything the script does is.

## 2. Behavior change

The degrade-vs-prompt **policy lives in step 3**, keyed on `versioning`. The script itself never
prompts — it only reports an outcome.

| `versioning` | clean single version | ambiguous / not found |
|---|---|---|
| `false` | — (version-free, short-circuit; unchanged) | version-free |
| **absent** (default) | versioned, use it | **version-free, silent, logged note** |
| **`true`** (explicit) | versioned, use it | **prompt** (interactive) · **degrade + loud warn** (non-interactive) |

This **splits `absent` vs `true`** semantics, which today are identical. Rationale: explicit `true`
is the consumer asserting "I want versioning," so a miss is a likely misconfiguration worth one
pre-loop prompt; absent is opportunistic. `profile-schema.md` documents the split.

- The `true` prompt fires at **step 3 — before the build loop, on the interactive main thread** —
  so it never collides with the background-agent / `--parallel` auto-deny constraint, and is
  consistent with the existing pre-flight halts (auth, missing profile keys).
- **Non-interactive runs** (scheduled / cron / headless): explicit `true` must **not hang**. When
  `MILESTONE_DRIVER_NONINTERACTIVE=1` is set, explicit `true` degrades to version-free with a loud
  `⚠` warning in the run output and a logged note instead of prompting. (Env-flag mechanism mirrors
  the repo's `CLAUDE_HOOK_DISABLE_*` culture.) Default is interactive → prompt.

## 3. Accepted grammar

The "not too harsh, not too greedy" rules. A candidate token is matched, validated, normalized.

| Rule | Accept | Reject (→ no match) |
|---|---|---|
| Components | 2, 3, or 4 numeric parts | 1 part (`v2`); 5+ parts (`1.2.3.4.5`) |
| Leading `v`/`V` | optional, stripped (`v1.2.3` → `1.2.3`) | — |
| 2-part normalize | `1.9` → `1.9.0` | — |
| 4-part | kept verbatim (`1.2.3.4`) | — |
| Leading zeros | — | `1.02.3`, `2024.06.19` (also filters most dates) |
| Pre-release suffix | kept (`1.2.3-rc.1`, `1.2.3-beta`) | — |
| Build-metadata suffix | kept (`1.2.3+build7`) | — |
| Digits | `[0-9]` only | — |

Each component must match `0` or `[1-9][0-9]*` (no leading zeros). Output is the normalized version
**verbatim** — no reinterpretation of the 4th part or the suffixes.

### Anti-false-positive anchoring

A regex is dumber than the model it replaces; bare numbers in prose (`section 1.2.3 rewrite`) or
date-ish tokens (`2024.6 planning`) would otherwise be grabbed and, under the silent absent-default,
set a wrong target. **Asymmetry that drives the rule:** a false positive silently ships a *wrong*
version; a miss merely degrades to version-free. A miss is recoverable; a silent wrong version is
not. So bare matching is deliberately conservative, and `v`-prefix is the escape hatch for
decorated/embedded versions.

Three tiers (a candidate must clear the tier for its shape):

- **`v`-prefixed** (2/3/4-part): accepted **anywhere** in the title. Intent is explicit.
- **Bare 3- or 4-part:** accepted only when **title-dominant** — anchored at the start or end of the
  trimmed title (not mid-title).
- **Bare 2-part:** accepted only when it is the **entire trimmed title**. 2-part is the most
  date-collision-prone (`2024.6`), so a decorated bare 2-part is rejected.

Keeps `0.3.1`, `0.3.1 hardening`, `Release 1.2.3`, `1.9`, `feeder v0.3.1`. Rejects
`section 1.2.3 rewrite`, `2024.6 planning`, `1.9 planning`. Residual: a non-zero-padded 3-part date
anchored at title start/end (`2024.6.19 retro`) still matches — rare; documented in §8.

## 4. Resolution algorithm (script — never prompts)

Input: `{title, description}`. Output: a resolved version on stdout, or empty + a reason on stderr.

1. **Title** → collect all valid matches (grammar §3, with title-dominance for bare versions).
   - exactly **1 distinct** version → emit it on stdout. Done.
   - **2+ distinct** → emit empty; stderr `ambiguous:<v1>,<v2>,…`.
   - **0** → step 2.
2. **Description** → collect valid matches (grammar §3, no title-dominance — it's prose). Take the
   **first** match → emit it. If **0** → emit empty; stderr `none`.

The description **never prompts on multiples** — always first-match — because milestone descriptions
routinely cite prior versions (the CHANGELOG template's "upgrading from X"), so multi-version there
is normal, not a misconfiguration signal. The only ambiguity-prompt trigger is **2+ distinct in the
title** under explicit `true`.

### Outcome → action (step 3, the skill)

| Script result | `versioning` absent | `versioning: true` |
|---|---|---|
| version emitted | versioned mode | versioned mode |
| empty + `none` | version-free, log | prompt "no version in milestone; enter one or proceed version-free" (or degrade+warn if non-interactive) |
| empty + `ambiguous:…` | version-free, log | prompt, listing the candidates (or degrade+warn if non-interactive) |

## 5. Architecture

| Artifact | Purpose |
|---|---|
| `scripts/extract-version.ps1` + `.sh` | Behavior-identical pair. **stdin JSON** input (`{"title": "...", "description": "..."}`), matching the hooks' stdin pattern (`no-push.{sh,ps1}`) — avoids argv quoting/injection from arbitrary title text (quotes, `$`, backticks, newlines, emoji). stdout = version-or-empty; stderr = `none` / `ambiguous:…`. **Fail-open**: any internal error (incl. malformed JSON) → empty stdout + `none`, exit 0. |
| `tests/extract-version.test.ps1` + `.sh` | Self-contained, dependency-free assertion matrix (§7). Asserts the `.ps1` and `.sh` impls produce **identical** output for every case. Exit non-zero on any mismatch. Run manually now; CI later. |
| `skills/solve-milestone/SKILL.md` step 3 | Invoke the extractor; map outcome × `versioning` → versioned / version-free / prompt per §4. |
| `docs/profile-schema.md` | Document the new `absent` vs `true` split. |
| `docs/architecture.md` | Note detection is a deterministic tested extractor; reconcile the existing "Plugin version" section (line ~21) which documents version-free mode. |

A `run-hook.cmd`-style polyglot launcher is **not** strictly required (this is not a `PreToolUse`
hook), **but** step 3 must not push platform detection (`.ps1` vs `.sh`) onto the model. Resolve in
the plan: either a tiny launcher shim or a documented single invocation that works on both Git-Bash
and pwsh-only Windows. Fail-open if neither interpreter is available → treated as `none`.

## 6. Cross-platform parity rules

The pair runs through **.NET regex** (PowerShell) and **POSIX ERE** (bash). These dialects diverge
exactly on the hard cases, so:

- **`[0-9]` only, never `\d`.** `.NET` `\d` is Unicode-aware; bash `[[ =~ ]]` doesn't support `\d`.
- **No lookahead/lookbehind.** POSIX ERE has none, so the boundary rule (reject 5+-part; reject a
  version embedded in a longer dotted/numeric run) is done as a **post-match boundary check in plain
  code**, identical on both sides — not a regex lookaround.
- The test matrix (§7) **runs both impls and asserts identical output** — otherwise the two drift
  silently. This is the enforcement mechanism for parity.

## 7. Test matrix (representative)

`input (title | desc)` → `expected stdout` / `expected stderr`. Implementation passes all; both
impls identical.

| Title | Desc | stdout | stderr |
|---|---|---|---|
| `0.3.1` | — | `0.3.1` | — |
| `milestone-feeder v0.3.1` | — | `0.3.1` | — |
| `v1.2.3` | — | `1.2.3` | — |
| `1.2.3.4` | — | `1.2.3.4` | — |
| `1.2.3-rc.1` | — | `1.2.3-rc.1` | — |
| `1.2.3+build7` | — | `1.2.3+build7` | — |
| `Release 1.2.3` | — | `1.2.3` | — |
| `section 1.2.3 rewrite` | — | (empty) | `none` |
| `2024.06.19 planning` | — | (empty) | `none` (leading zero) |
| `2024.6 planning` | — | (empty) | `none` (bare 2-part, decorated) |
| `1.9 planning` | — | (empty) | `none` (bare 2-part, decorated) |
| `1.9` | — | `1.9.0` | — (bare 2-part, whole title) |
| `v1` | — | (empty) | `none` |
| `1.2.3.4.5` | — | (empty) | `none` |
| `1.02.3` | — | (empty) | `none` |
| `v1.4.0 / v1.5.0 combo` | — | (empty) | `ambiguous:1.4.0,1.5.0` |
| `Q3 hardening` | `targets 1.4.0; upgrading from 1.3.0` | `1.4.0` | — |
| `Q3 hardening` | `no version here` | (empty) | `none` |
| `feeder v1.2.3` (dup) | `mentions 1.2.3 again` | `1.2.3` | — (1 distinct in title) |

(The plan expands this into the exhaustive committed matrix.)

## 8. Out of scope / accepted risk

- **4-part validity in the target manifest** is the consumer's concern — we emit `1.2.3.4` verbatim;
  whether their `.claude-plugin/plugin.json` accepts it is theirs to fix.
- **`solve-issue` step 6.4** (the bump) consumes the target version **unchanged** — no edits there.
- **Non-zero-padded date false positive** — a 3-part date with no leading zeros, anchored at the
  title start/end (`2024.6.19 retro`), is structurally indistinguishable from a version and still
  matches. Rare (dates are usually zero-padded → caught, or 2-part → caught by the bare-2-part
  whole-title rule). Accepted; `v`-prefixing a real version sidesteps any ambiguity.
- **Description false positives** — first-match in a description could grab a non-target version
  (e.g. `see section 1.2.3`). Accepted: description is fallback-only (title had zero matches) and
  first-match was explicitly approved. Residual risk documented.
- **No CI** — the test matrix runs manually until someone wires it (acceptable per #158).
- **The `absent` default behavior change** (parse/prompt → silent degrade) is the real
  consumer-facing change — needs a CHANGELOG consumer-note so a consumer relying on the default bump
  isn't silently surprised.

## 9. Open questions

None — all design forks resolved during brainstorming (grammar, precedence, degrade-vs-prompt split,
anchoring, parity, where-it-lives).
