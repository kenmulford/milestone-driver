# Design system

<!--
Project doc (.project/). Cite as `.project/design-system.md#<section>`. Machine-readable
design tokens live in `tokens.json` alongside this file. Absent or all-[TBD] →
no design-lens grounding (design-reviewer / coherence-reviewer / wireframing
skip it). Skip this file entirely for repos with no UI surface. Keep ## headings
stable — they are citation anchors.

Captured by milestone-bootstrapper (dogfood #235).
-->

## Not applicable — no UI surface

milestone-driver is a Claude Code plugin with **no UI surface** — it ships markdown
skills, markdown agents, and shell hooks/scripts, and renders nothing. There is no
`uiSurfaceGlobs` key in `.milestone-config/driver.json`, so the engine raises no UI
issues here and the Layer-2 visual gate never fires.

This file is recorded **None** (a captured decision, not a gap): the design-lens
reviewers — `design-reviewer`, `coherence-reviewer`'s design checks, and any
wireframing tool — correctly **skip** this repo. `tokens.json` alongside is recorded
the same way. If this plugin ever grows a rendered surface, replace this section with
the standard design-system anchors (Design tokens / Component inventory / Layout &
responsive rules / Required states / Accessibility baseline / Voice & microcopy).
