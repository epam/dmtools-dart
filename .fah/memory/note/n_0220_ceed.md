---
id: "n_0220_ceed"
type: "note"
title: "Lesson (2026-09-21 fa outage, ~8 min): repinning the dmtools-agents factory ref in dart/fa workflow stubs (machine-sm.yml/ai-teammate.yml) must ALWAYS use the FULL 40-char SHA on both sides of the replace. A sed of the 7-char prefix inside a 40-char SHA produced a nonexistent Frankenstein ref → the caller workflow failed to parse (\"failed to fetch workflow\") → every issues-event run on fa insta-failed and SM ticks died. Fix pattern: `FULL=$(gh api repos/IstiN/dmtools-agents/commits/<short> --jq .sha)` then sed full→full. Also: with a valid workflow, non-machine `issues: [labeled]` events create skipped run-shells (GitHub cannot filter trigger types by label name) — cosmetic only; narrowing the trigger to `assigned` or dropping it (SM dispatches legs via workflow_dispatch) is the only way to zero them."
author: "agent"
date: "2026-09-21T20:28:09.513719Z"
area: "project"
topics: []
source: "agent"
accessCount: 0
importance: 0.5
tags: ["#note", "#source_agent", "lesson", "github-actions", "sed", "factory-pin", "postmortem"]
---


# Note: n_0220_ceed

Lesson (2026-09-21 fa outage, ~8 min): repinning the dmtools-agents factory ref in dart/fa workflow stubs (machine-sm.yml/ai-teammate.yml) must ALWAYS use the FULL 40-char SHA on both sides of the replace. A sed of the 7-char prefix inside a 40-char SHA produced a nonexistent Frankenstein ref → the caller workflow failed to parse ("failed to fetch workflow") → every issues-event run on fa insta-failed and SM ticks died. Fix pattern: `FULL=$(gh api repos/IstiN/dmtools-agents/commits/<short> --jq .sha)` then sed full→full. Also: with a valid workflow, non-machine `issues: [labeled]` events create skipped run-shells (GitHub cannot filter trigger types by label name) — cosmetic only; narrowing the trigger to `assigned` or dropping it (SM dispatches legs via workflow_dispatch) is the only way to zero them.

**By:** [[agent]]
**Date:** 2026-09-21T20:28:09.513719Z
**Area:** [[project|project]]
