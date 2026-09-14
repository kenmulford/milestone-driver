## Preflight `"github-ci"` sentinel mode

The branch that reaches this file belongs to the caller, which reads `preflightCmd` from the profile and only then reads this file (`skills/solve-issue/SKILL.md (the reserved sentinel)`). Reaching this file therefore means `preflightCmd` is the reserved sentinel `"github-ci"`.

### Sentinel mode

No CI step runs locally under this sentinel. The Preflight row of `### 4. Verification gates` does not apply: no discovery, no local step execution, no cap, no retry, no park. The PR's own CI run is the preflight - step 8's existing wait-for-green merge, with that granularity's existing red-CI handling (the per-issue PR's wait, the wave PR's, or `skills/solve-milestone/milestone-granularity.md § Red CI on the milestone PR`), is what gates the change. `ciWorkflow` is not read under this sentinel: nothing narrows a discovery that no longer runs.

A literal `preflightCmd` string is unaffected by any of the above and still runs locally through the ordinary Preflight row.

`scripts/ci-preflight-steps.{sh,ps1}` still discovers and emits CI-derived steps from `.github/workflows/*.yml` on direct invocation, but nothing in this pipeline calls it any more.
