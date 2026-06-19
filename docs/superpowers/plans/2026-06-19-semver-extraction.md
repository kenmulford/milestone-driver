# Deterministic Semver Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `solve-milestone` step 3's model-judgment version parse with a deterministic, cross-platform, unit-tested extractor script driven by a shared golden test matrix.

**Architecture:** A behavior-identical `scripts/extract-version.{sh,ps1}` pair reads `{title, description}` JSON on stdin and prints a normalized version on stdout (or empty + a reason on stderr). A single golden TSV (`tests/extract-version.cases.tsv`) is the correctness contract; two thin test runners (`.sh` + `.ps1`) assert their respective impl against it, so both impls match the same golden → parity. `solve-milestone` step 3 invokes the extractor and maps its outcome × the `versioning` profile value to versioned / version-free / prompt.

**Tech Stack:** POSIX bash + `jq` (already a repo dependency); PowerShell 7 (`pwsh`) with built-in `ConvertFrom-Json`. No new third-party dependencies.

## Global Constraints

- **Digits are `[0-9]` only — never `\d`** (`.NET` `\d` is Unicode-aware; bash `[[ =~ ]]` lacks `\d`). Verbatim across both impls.
- **No regex lookahead/lookbehind** (POSIX ERE has none). Boundary checks (reject 5+-part, reject embedded tokens) are post-match code, identical on both sides.
- **Fail-open:** malformed input, missing `jq`, or any internal error → empty stdout + `none` on stderr, exit 0. Never hard-fail.
- **Both impls produce identical output for every golden case.** The shared `cases.tsv` is the contract; if a reference snippet below disagrees with the matrix, the matrix wins.
- **`scripts/**` and `skills/**` are likely under the repo's `sourceGlobs`.** Author them from the implementer subagent (the `force-subagent` gate blocks main-thread edits to `sourceGlobs`); `docs/**` stays orchestrator-editable.
- Output format: leading `v`/`V` stripped; 2-part core gets `.0` appended; 3/4-part kept; pre-release (`-…`) and build (`+…`) suffixes kept verbatim.

---

## File Structure

| File | Responsibility |
|---|---|
| `tests/extract-version.cases.tsv` | Golden matrix: `name⇥title⇥description⇥expected_stdout⇥expected_stderr`. Sole correctness contract. |
| `scripts/extract-version.sh` | Bash extractor. stdin JSON → stdout version-or-empty, stderr `none`/`ambiguous:…`. |
| `scripts/extract-version.ps1` | PowerShell extractor. Behavior-identical to the `.sh`. |
| `tests/extract-version.test.sh` | Reads `cases.tsv`, runs `extract-version.sh` per row, asserts stdout+stderr. Exit ≠0 on any mismatch. |
| `tests/extract-version.test.ps1` | Reads the same `cases.tsv`, runs `extract-version.ps1`, asserts. |
| `skills/solve-milestone/SKILL.md` | Step 3 rewired to invoke the extractor + outcome×`versioning` policy. |
| `docs/profile-schema.md` | Documents the new `absent` vs `true` split. |
| `docs/architecture.md` | Notes deterministic extractor; reconciles the "Plugin version" section. |

---

## Task 1: Golden matrix + bash extractor + bash test runner

**Files:**
- Create: `tests/extract-version.cases.tsv`
- Create: `scripts/extract-version.sh`
- Create: `tests/extract-version.test.sh`

**Interfaces:**
- Produces: the extractor CLI contract used by Task 2 (must match byte-for-byte) and Task 3:
  - **stdin:** JSON `{ "title": <string>, "description": <string|null> }`
  - **stdout:** the normalized version string, or empty
  - **stderr (only when stdout empty):** `none` | `ambiguous:<v1>,<v2>,…` (candidates in first-appearance order, deduped)
  - **exit:** always `0`
- Produces: `tests/extract-version.cases.tsv` golden format, reused verbatim by Task 2.

- [ ] **Step 1: Write the golden matrix (the failing test's data)**

Create `tests/extract-version.cases.tsv`. Columns are TAB-separated: `name⇥title⇥description⇥expected_stdout⇥expected_stderr`. Lines starting with `#` and blank lines are ignored. Empty `description` / `expected_stdout` / `expected_stderr` are empty fields.

```tsv
# name	title	description	expected_stdout	expected_stderr
bare_3part_whole	0.3.1		0.3.1	
v_prefix_anywhere	milestone-feeder v0.3.1		0.3.1	
v_prefix_simple	v1.2.3		1.2.3	
four_part_whole	1.2.3.4		1.2.3.4	
prerelease	1.2.3-rc.1		1.2.3-rc.1	
build_meta	1.2.3+build7		1.2.3+build7	
bare_3part_end	Release 1.2.3		1.2.3	
bare_3part_start	0.3.1 hardening		0.3.1	
bare_2part_whole	1.9		1.9.0	
bare_3part_mid	section 1.2.3 rewrite			none
date_zeropad	2024.06.19 planning			none
date_2part_decorated	2024.6 planning			none
bare_2part_decorated	1.9 planning			none
one_part	v1			none
five_part	1.2.3.4.5			none
leading_zero	1.02.3			none
ambiguous_title	v1.4.0 / v1.5.0 combo			ambiguous:1.4.0,1.5.0
dup_same_version	feeder v1.2.3	mentions 1.2.3 again	1.2.3	
desc_fallback	Q3 hardening	targets 1.4.0; upgrading from 1.3.0	1.4.0	
desc_none	Q3 hardening	no version here		none
residual_date	2024.6.19 retro		2024.6.19	
```

(The `residual_date` row encodes the documented accepted false positive — a non-zero-padded 3-part date at title start matches. It is a true expected output, not a defect.)

- [ ] **Step 2: Write the bash test runner**

Create `tests/extract-version.test.sh`:

```bash
#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for extract-version.sh (issue #158).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/extract-version.sh"
CASES="$HERE/extract-version.cases.tsv"
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

pass=0; fail=0
while IFS=$'\t' read -r name title desc exp_out exp_err; do
  case "$name" in ''|\#*) continue;; esac
  json="$(jq -n --arg t "$title" --arg d "$desc" '{title:$t, description:$d}')"
  out="$(printf '%s' "$json" | bash "$SCRIPT" 2>/tmp/ev_err)"; err="$(cat /tmp/ev_err)"
  if [ "$out" = "$exp_out" ] && [ "$err" = "$exp_err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %-22s in[%s|%s] got[out=%s err=%s] want[out=%s err=%s]\n' \
      "$name" "$title" "$desc" "$out" "$err" "$exp_out" "$exp_err" >&2
  fi
done < "$CASES"
echo "extract-version.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
```

- [ ] **Step 3: Run the runner to verify it fails (no extractor yet)**

Run: `bash tests/extract-version.test.sh`
Expected: `FATAL: missing .../scripts/extract-version.sh` and exit 3.

- [ ] **Step 4: Write the bash extractor**

Create `scripts/extract-version.sh`. This is the reference implementation — make `cases.tsv` pass; the matrix is authoritative if any case disagrees.

```bash
#!/usr/bin/env bash
# milestone-driver — deterministic milestone version extractor (issue #158).
# stdin: JSON {title, description?}. stdout: normalized version or empty.
# When empty, stderr is "none" or "ambiguous:<v1>,<v2>,...". Fail-open, exit 0.
set -u
emit_none() { printf 'none' >&2; exit 0; }

input="$(cat)"; [ -z "$input" ] && emit_none
command -v jq >/dev/null 2>&1 || emit_none
title="$(printf '%s' "$input" | jq -r '.title // ""' 2>/dev/null)" || emit_none
desc="$(printf '%s' "$input" | jq -r '.description // ""' 2>/dev/null)"

CAND='[vV]?[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?'

# normalize <token> -> echoes normalized version and returns 0, or returns 1.
normalize() {
  local tok="$1" core suffix; tok="${tok#[vV]}"
  core="${tok%%[-+]*}"; suffix=""
  [ "$core" != "$tok" ] && suffix="${tok:${#core}}"
  local IFS='.'; read -r -a comps <<< "$core"
  local n="${#comps[@]}" c
  [ "$n" -ge 2 ] && [ "$n" -le 4 ] || return 1
  for c in "${comps[@]}"; do [[ "$c" =~ ^(0|[1-9][0-9]*)$ ]] || return 1; done
  [ "$n" -eq 2 ] && core="$core.0"
  printf '%s%s' "$core" "$suffix"
}

# part_count <token> -> numeric components in core (2..4)
part_count() { local t="${1#[vV]}"; t="${t%%[-+]*}"; local IFS='.'; read -r -a a <<< "$t"; echo "${#a[@]}"; }

# scan <text> <anchor>  (anchor=1 apply title tiers; anchor=0 prose/first-match)
# echoes accepted normalized versions, one per line, in order.
scan() {
  local text; text="$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  local anchor="$2" len="${#text}" line off match start mlen end before after hasv n norm
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    off="${line%%:*}"; match="${line#*:}"
    start="$off"; mlen="${#match}"; end="$((start+mlen))"
    # boundary before: separator (not alnum or dot)
    if [ "$start" -gt 0 ]; then before="${text:$((start-1)):1}"; [[ "$before" =~ [0-9A-Za-z.] ]] && continue; fi
    # boundary after: not a digit or dot (rejects a 5th component / trailing digit)
    if [ "$end" -lt "$len" ]; then after="${text:$end:1}"; [[ "$after" =~ [0-9.] ]] && continue; fi
    norm="$(normalize "$match")" || continue
    if [ "$anchor" = "1" ]; then
      case "$match" in [vV]*) hasv=1;; *) hasv=0;; esac
      if [ "$hasv" = "0" ]; then
        n="$(part_count "$match")"
        if [ "$n" -eq 2 ]; then
          [ "$start" -eq 0 ] && [ "$end" -eq "$len" ] || continue   # bare 2-part: whole title only
        else
          [ "$start" -eq 0 ] || [ "$end" -eq "$len" ] || continue   # bare 3/4-part: start or end
        fi
      fi
    fi
    printf '%s\n' "$norm"
  done < <(printf '%s' "$text" | grep -Eob -o "$CAND")
}

# title pass
mapfile -t tv < <(scan "$title" 1)
# distinct, preserve order
declare -a distinct=(); for v in "${tv[@]:-}"; do [ -z "$v" ] && continue
  dup=0; for d in "${distinct[@]:-}"; do [ "$d" = "$v" ] && dup=1 && break; done
  [ "$dup" -eq 0 ] && distinct+=("$v"); done
if [ "${#distinct[@]}" -eq 1 ]; then printf '%s' "${distinct[0]}"; exit 0; fi
if [ "${#distinct[@]}" -ge 2 ]; then
  joined="$(IFS=,; echo "${distinct[*]}")"; printf 'ambiguous:%s' "$joined" >&2; exit 0
fi
# description fallback: first match
mapfile -t dv < <(scan "$desc" 0)
for v in "${dv[@]:-}"; do [ -n "$v" ] && { printf '%s' "$v"; exit 0; }; done
emit_none
```

- [ ] **Step 5: Run the runner to verify all cases pass**

Run: `bash tests/extract-version.test.sh`
Expected: `extract-version.sh: 21 passed, 0 failed` and exit 0. If any `FAIL` line prints, fix the extractor (matrix is authoritative) and re-run.

- [ ] **Step 6: Commit**

```bash
git add tests/extract-version.cases.tsv scripts/extract-version.sh tests/extract-version.test.sh
git commit -m "feat(#158): bash version extractor + golden test matrix"
```

---

## Task 2: PowerShell extractor + pwsh test runner

**Files:**
- Create: `scripts/extract-version.ps1`
- Create: `tests/extract-version.test.ps1`

**Interfaces:**
- Consumes: the CLI contract and `tests/extract-version.cases.tsv` from Task 1 (unchanged).
- Produces: a `.ps1` impl whose output matches the `.sh` for every golden row (parity via shared matrix).

- [ ] **Step 1: Write the pwsh test runner**

Create `tests/extract-version.test.ps1`:

```powershell
#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for extract-version.ps1 (issue #158).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'extract-version.ps1'
$cases = Join-Path $here 'extract-version.cases.tsv'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }
$pass = 0; $fail = 0
foreach ($line in Get-Content $cases) {
  if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
  $f = $line -split "`t"
  $name = $f[0]; $title = $f[1]; $desc = $f[2]
  $expOut = if ($f.Count -gt 3) { $f[3] } else { '' }
  $expErr = if ($f.Count -gt 4) { $f[4] } else { '' }
  $json = @{ title = $title; description = $desc } | ConvertTo-Json -Compress
  $errFile = New-TemporaryFile
  $out = ($json | pwsh -NoProfile -File $script 2> $errFile.FullName)
  $out = ("$out").Trim()
  $err = (Get-Content $errFile.FullName -Raw); $err = if ($null -eq $err) { '' } else { $err.Trim() }
  Remove-Item $errFile.FullName -Force
  if ($out -eq $expOut -and $err -eq $expErr) { $pass++ }
  else { $fail++; Write-Host "FAIL $name in[$title|$desc] got[out=$out err=$err] want[out=$expOut err=$expErr]" }
}
Write-Host "extract-version.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
```

- [ ] **Step 2: Run the runner to verify it fails (no .ps1 extractor yet)**

Run: `pwsh -NoProfile -File tests/extract-version.test.ps1`
Expected: `FATAL: missing .../scripts/extract-version.ps1`, exit 3.

- [ ] **Step 3: Write the pwsh extractor**

Create `scripts/extract-version.ps1` (behavior-identical to the `.sh`; matrix authoritative):

```powershell
#!/usr/bin/env pwsh
# milestone-driver — deterministic milestone version extractor (issue #158).
# stdin: JSON {title, description?}. stdout: normalized version or empty.
# When empty, stderr is "none" or "ambiguous:<v1>,<v2>,...". Fail-open, exit 0.
function Emit-None { [Console]::Error.Write('none'); exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { Emit-None }
try { $o = $raw | ConvertFrom-Json -ErrorAction Stop } catch { Emit-None }
$title = if ($null -ne $o.title) { [string]$o.title } else { '' }
$desc  = if ($null -ne $o.description) { [string]$o.description } else { '' }

$CAND = '[vV]?[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?'

function Normalize([string]$tok) {
  $t = $tok -replace '^[vV]', ''
  $core = $t; $suffix = ''
  $i = $t.IndexOfAny([char[]]@('-','+'))
  if ($i -ge 0) { $core = $t.Substring(0,$i); $suffix = $t.Substring($i) }
  $comps = $core -split '\.'
  if ($comps.Count -lt 2 -or $comps.Count -gt 4) { return $null }
  foreach ($c in $comps) { if ($c -notmatch '^(0|[1-9][0-9]*)$') { return $null } }
  if ($comps.Count -eq 2) { $core = "$core.0" }
  return "$core$suffix"
}
function PartCount([string]$tok) {
  $t = ($tok -replace '^[vV]','')
  $j = $t.IndexOfAny([char[]]@('-','+')); if ($j -ge 0) { $t = $t.Substring(0,$j) }
  return ($t -split '\.').Count
}
function Scan([string]$textIn, [bool]$anchor) {
  $text = $textIn.Trim(); $len = $text.Length; $acc = @()
  foreach ($m in [regex]::Matches($text, $CAND)) {
    $start = $m.Index; $end = $m.Index + $m.Length; $match = $m.Value
    if ($start -gt 0) { if ($text[$start-1] -match '[0-9A-Za-z.]') { continue } }
    if ($end -lt $len) { if ($text[$end] -match '[0-9.]') { continue } }
    $norm = Normalize $match; if ($null -eq $norm) { continue }
    if ($anchor) {
      $hasv = $match -match '^[vV]'
      if (-not $hasv) {
        $n = PartCount $match
        if ($n -eq 2) { if (-not ($start -eq 0 -and $end -eq $len)) { continue } }
        else { if (-not ($start -eq 0 -or $end -eq $len)) { continue } }
      }
    }
    $acc += $norm
  }
  return ,$acc
}

$tv = Scan $title $true
$distinct = @(); foreach ($v in $tv) { if ($distinct -notcontains $v) { $distinct += $v } }
if ($distinct.Count -eq 1) { [Console]::Out.Write($distinct[0]); exit 0 }
if ($distinct.Count -ge 2) { [Console]::Error.Write('ambiguous:' + ($distinct -join ',')); exit 0 }
$dv = Scan $desc $false
if ($dv.Count -ge 1) { [Console]::Out.Write($dv[0]); exit 0 }
Emit-None
```

- [ ] **Step 4: Run the runner to verify all cases pass**

Run: `pwsh -NoProfile -File tests/extract-version.test.ps1`
Expected: `extract-version.ps1: 21 passed, 0 failed`, exit 0.

- [ ] **Step 5: Parity check on a dual-runtime host**

Run both, confirm identical pass counts:
`bash tests/extract-version.test.sh && pwsh -NoProfile -File tests/extract-version.test.ps1`
Expected: both report `21 passed, 0 failed`. Same golden matrix → identical behavior.

- [ ] **Step 6: Commit**

```bash
git add scripts/extract-version.ps1 tests/extract-version.test.ps1
git commit -m "feat(#158): powershell version extractor + pwsh runner (parity via shared matrix)"
```

---

## Task 3: Wire solve-milestone step 3 to the extractor

**Files:**
- Modify: `skills/solve-milestone/SKILL.md` (step 3, "Determine the target version")

**Interfaces:**
- Consumes: the extractor CLI contract (Task 1) and the resolved milestone `{number, title}` already established in Before-starting step 3.

- [ ] **Step 1: Replace step 3's body with the deterministic procedure**

In `skills/solve-milestone/SKILL.md`, replace the `### 3. Determine the target version` section body with the following (keep the heading and the `> Version source vs. version target` / Precedence / Handoff blockquotes that follow it unchanged):

```markdown
Read `versioning` from the profile. **Version-free mode** (`versioning: false`): skip this step entirely — no extraction, no prompt, no target version. Record "version-free run — no version determined or bumped" and proceed to Phase 0.

**Otherwise** (`versioning: true` or absent): determine the target version with the deterministic extractor `scripts/extract-version.{sh,ps1}` (issue #158) — do **not** parse by judgment. Pipe the milestone's title + description as JSON to the extractor (bash where available, else pwsh):

​```bash
gh api "repos/{owner}/{repo}/milestones/<resolved-number>" --jq '{title, description}' \
  | bash scripts/extract-version.sh        # pwsh -NoProfile -File scripts/extract-version.ps1 on pwsh-only hosts
​```

The extractor prints the normalized version on **stdout**, or nothing — with a reason (`none` or `ambiguous:<candidates>`) on **stderr**. Branch on the result × `versioning`:

| Extractor result | `versioning` absent (opportunistic) | `versioning: true` (explicit opt-in) |
|---|---|---|
| version on stdout | **versioned** — hold it as the target for the loop; record it | **versioned** — same |
| empty + `none` | **version-free**, record "no parseable version in milestone — version-free run (logged)" | **prompt** the user: "No version found in milestone '<title>'. Enter a target version, or proceed version-free." |
| empty + `ambiguous:<list>` | **version-free**, record "ambiguous version in title (<list>) — version-free run (logged)" | **prompt**, listing `<list>` as the candidates to choose from |

**Non-interactive runs.** When `MILESTONE_DRIVER_NONINTERACTIVE=1` is set (scheduled / cron / headless), explicit `true` does **not** prompt — it degrades to version-free with a loud `⚠ explicit versioning:true but no parseable version — running version-free` warning and a logged note. The prompt path is interactive-main-thread only; this preserves unattended operation.

The extractor is fail-open: any internal error yields empty + `none`, so a missing interpreter or malformed input degrades exactly like "no version found".
```

- [ ] **Step 2: Verify the wiring by dry-running the extractor against representative inputs**

There is no unit harness for skill prose; verify the invocation the skill documents actually produces the documented outcomes:

```bash
printf '{"title":"v1.4.2 polish","description":""}' | bash scripts/extract-version.sh; echo " <-want 1.4.2"
printf '{"title":"Q3 hardening","description":"no version"}' | bash scripts/extract-version.sh 2>&1; echo " <-want none"
printf '{"title":"v1.4.0 / v1.5.0","description":""}' | bash scripts/extract-version.sh 2>&1; echo " <-want ambiguous:1.4.0,1.5.0"
```
Expected: `1.4.2`, `none`, `ambiguous:1.4.0,1.5.0` respectively.

- [ ] **Step 3: Commit**

```bash
git add skills/solve-milestone/SKILL.md
git commit -m "feat(#158): wire solve-milestone step 3 to deterministic extractor + degrade/prompt policy"
```

---

## Task 4: Documentation — schema split, architecture note, changelog

**Files:**
- Modify: `docs/profile-schema.md` (the `versioning` row)
- Modify: `docs/architecture.md` ("Plugin version" section, ~line 21)
- Modify: `CHANGELOG.md` (consumer note)

**Interfaces:**
- Consumes: the behavior defined in Task 3 (the `absent` vs `true` split).

- [ ] **Step 1: Update the `versioning` row in `docs/profile-schema.md`**

Replace the description cell of the `versioning` row with:

```markdown
Should each PR bump a plugin version? **`false`** → version-free: no extraction, no prompt, no bump (the milestone name need not be a version). **absent (default)** → opportunistic: `solve-milestone` runs the deterministic extractor (`scripts/extract-version.*`, issue #158) against the milestone title (description as fallback); a parseable version is used, otherwise the run silently degrades to version-free with a logged note — never prompts. **`true`** (explicit opt-in) → same extraction, but a miss or an ambiguous title **prompts** the operator (or, under `MILESTONE_DRIVER_NONINTERACTIVE=1`, degrades with a loud warning). This `absent` vs `true` split is intentional: `true` asserts intent to version, so a missing version is treated as a likely misconfiguration. Fail-safe: in versioned mode, a missing `.claude-plugin/plugin.json` degrades to version-free with a logged note rather than failing.
```

- [ ] **Step 2: Update the "Plugin version" section in `docs/architecture.md`**

Replace the sentence beginning "Set `versioning: false` to opt out…" with:

```markdown
Version detection is a deterministic, unit-tested extractor (`scripts/extract-version.{sh,ps1}`, issue #158), not model judgment: it scans the milestone title (description as fallback) for a `v`-optional 2/3/4-part version and normalizes it. `versioning: false` is version-free mode (no extraction, no bump). With `versioning` absent the run is opportunistic — a parseable version is used, otherwise it silently degrades to version-free; with explicit `versioning: true` a miss or ambiguous title prompts the operator (degrades with a warning when non-interactive). Fail-safe: a versioned repo whose `.claude-plugin/plugin.json` is missing degrades to version-free with a logged note rather than failing the run.
```

- [ ] **Step 3: Add a consumer note to `CHANGELOG.md`**

Under the in-progress `1.10.0` section (create the `## v1.10.0 — …` heading if absent, mirroring the existing entry format), add a `### Consumer notes` bullet:

```markdown
- **Behavior change (default `versioning`):** `solve-milestone` now uses a deterministic version extractor. With `versioning` absent (the default), a milestone whose title has no parseable version now **silently runs version-free** instead of parsing-by-judgment/prompting — a consumer relying on the default bump should confirm their milestone titles carry a version, or set `versioning: true` to be prompted on a miss.
```

- [ ] **Step 4: Verify docs render and cross-references resolve**

Run: `git grep -n "extract-version" docs/ skills/`
Expected: references appear in `profile-schema.md`, `architecture.md`, and `skills/solve-milestone/SKILL.md`, all pointing at `scripts/extract-version.*`.

- [ ] **Step 5: Commit**

```bash
git add docs/profile-schema.md docs/architecture.md CHANGELOG.md
git commit -m "docs(#158): document deterministic extractor + absent-vs-true versioning split"
```

---

## Self-Review

**1. Spec coverage** (spec §→ task):
- §2 behavior table / degrade-prompt split → Task 3 Step 1 table + Task 4 Steps 1–2.
- §3 grammar + 3-tier anchoring → Task 1 Step 4 (`normalize`, `part_count`, `scan` anchoring) + matrix rows; Task 2 mirror.
- §4 resolution (title-first, distinct/ambiguous, desc first-match) → Task 1 Step 4 title pass + distinct + fallback; matrix `desc_fallback`/`ambiguous_title`.
- §5 architecture (stdin JSON, fail-open, both scripts + shared golden) → Tasks 1–2; launcher resolved as bash-first/pwsh-fallback invocation in Task 3 Step 1.
- §6 parity rules (`[0-9]`, no lookahead, both-assert) → Global Constraints + Task 2 Step 5.
- §7 test matrix → `cases.tsv` (Task 1 Step 1).
- §8 risks (4-part verbatim, residual date FP, no CI, absent-default change) → `residual_date` row, CHANGELOG note (Task 4 Step 3); 4-part `four_part_whole` row.
- Non-interactive fallback (`MILESTONE_DRIVER_NONINTERACTIVE`) → Task 3 Step 1.

No spec requirement is left without a task.

**2. Placeholder scan:** No "TBD/TODO/handle edge cases" — all code blocks are concrete; the reference impls are explicitly subordinate to the authoritative `cases.tsv`.

**3. Type/name consistency:** CLI contract (stdin JSON `{title, description}`; stdout version; stderr `none`/`ambiguous:…`; exit 0) is identical across Task 1, Task 2, Task 3. Function names `normalize`/`Normalize`, `part_count`/`PartCount`, `scan`/`Scan` are per-language but contract-identical. `cases.tsv` path and column order are referenced identically by both runners. Expected pass count (21) matches the 21 non-comment matrix rows.
