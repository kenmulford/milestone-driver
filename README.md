# milestone-driver

Systematize the development process in the context of git flow.

milestone-driver is a Claude Code plugin. A milestone is the largest body of work. Issues go under milestones. You hand it a GitHub milestone and it works the issues to merged PRs, and each issue is solved in a consistent, controlled manner: it triages the design for gaps, finds the root cause, has a subagent write the change test-first, reviews the diff, opens a PR, and merges to your integration branch when CI is green.

The point is quality. The bigger the ask of AI, the worse the quality is. By keeping every issue small and running it through the same controlled procedure, milestone-driver keeps quality in the forefront while letting large bodies of work be automated.

UI issues stop for your visual sign-off. Anything risky, like a design gap or a one-way-door decision, parks with a label instead of guessing. Your release branch is never touched. That stays your call, behind your manual deploy.

## What makes it different

Issue-to-PR assistants take one big swing at a task. milestone-driver decomposes a milestone into issues and runs each small issue through the same mechanical gates. The body of work scales up without the per-step ask scaling up, and every merge is bounded to an integration branch you control.

## Quickstart

Install the plugin. It pulls in the required superpowers dependency:

```
/plugin marketplace add kenmulford/milestone-driver
/plugin install milestone-driver@milestone-driver
```

Restart Claude Code after install so the plugin hooks load.

Add a `milestone-driver.json` profile at your repo root. The minimum is three keys:

```json
{
  "integrationBranch": "develop",
  "protectedBranch": "main",
  "sourceGlobs": ["src/**"]
}
```

Run it on a whole milestone, or on a single issue:

```
/milestone-driver:solve-milestone "1.4.0"
/milestone-driver:solve-issue 58
```

No profile yet? On the first run the setup skill bootstraps one with you. Full setup walkthrough: [docs/consumer-setup.md](docs/consumer-setup.md). Every profile key: [docs/profile-schema.md](docs/profile-schema.md).

## When to use it

- You have a milestone of issues that can be built mostly independently.
- You want each issue built the same disciplined way, not improvised per run.
- You want an audit trail you can review after an unattended run: a Decision Log on every PR, and labels on the borderline calls.
- You want the work bounded to an integration branch, with the release to your protected branch staying manual.

## How it works

milestone-driver runs three stages in order. Every stage is gated, so no single step asks the model to hold too much at once.

1. Triage. Before any code, it reviews every issue for design gaps and dependency order. Clean issues build. Gapped issues park with a comment and a label.
2. Build loop. It works the issues in dependency order. For each one it locks an approach, dispatches a subagent to write it test-first, runs your unit and E2E suites, reviews the diff, and opens a PR.
3. Merge. Logic-only issues auto-merge to your integration branch when CI is green. UI issues stay open for your visual sign-off. Risky issues park instead of guessing.

Discipline is enforced by local hooks, not by trust. Commits are blocked on red tests, pushes to your protected branch are blocked, and source edits are forced through subagents so the main thread only orchestrates.

The full architecture, the gating model, the label taxonomy, and the mechanical gates live in [docs/architecture.md](docs/architecture.md).

## Requirements

- The superpowers plugin. The per-issue inner loop is built on it, and it is auto-installed as a dependency on install, provided you have the official marketplace added.
- GitHub CLI (`gh`), authenticated, for issue, PR, and milestone operations.
- git, with the repo using a gitflow-style integration branch.
- bash (preferred) or PowerShell 7+ for the hooks. `jq` is required for the bash path.

## Status

v1.4.0, self-hosted. milestone-driver drives its own releases through its committed `milestone-driver.json`. First external-consumer wiring is in progress.

## Docs

- [docs/consumer-setup.md](docs/consumer-setup.md): full setup and wiring.
- [docs/profile-schema.md](docs/profile-schema.md): every profile key.
- [docs/architecture.md](docs/architecture.md): how the engine and the gates work.

## License

[MIT](LICENSE) (provisional, finalized at publishing time).
