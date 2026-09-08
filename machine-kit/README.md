# machine-kit — the dark-factory merge loop, portable

The CI/automation "machine" proven in dmtools-dart, packaged for other repos.
**The tracker is the repo's own GitHub issues** — no Jira, no external services:

```
issue labeled pr_approved → linked PR → required checks green (branch
protection CLEAN) → squash-merge → label removed → comment on issue
        ↑ branch kept current by auto-update-prs
```

Link a PR to its issue either way:
- `Closes #NN` / `Fixes #NN` / `Resolves #NN` in the PR body, or
- branch named `NN-…` (e.g. `42-fix-foo`).

## Components

| Piece | What it does | Source |
|---|---|---|
| Gate workflow | Language-specific quality checks (the repo's own CI) | per-repo |
| `auto-update-prs.yml` | After each push to main, updates open PR branches (strict up-to-date needs this) | templates/ |
| `merge-trigger.yml` | On a green gate run, executes `agents/sm_merge.json` (JSRunner): JQL rules find tickets labeled `pr_approved` and run their merge configs (`retry_merge.json` → `js/retryMergePR.js`, scm.js-based merge + Jira comments) | templates/ |
| `agents/` submodule | IstiN/dmtools-agents — sm_merge.json, retryMergePR.js, checkWipLabel.js | added by setup.sh, pinned |
| Branch protection | Required checks (strict), enforce-admins, **no review requirement** (the machine merges), no force-push/deletes | setup.sh `protect` |
| `MERGE_TRIGGER_ENABLED` var | Fuse: merge-trigger skips itself until `true` | setup.sh `protect --enable-fuse` |

## Prerequisites (target repo)

- `gh` CLI authenticated with **admin** on the target repo.
- The gate workflow runs on `pull_request` and its **job names** are known
  (required-check contexts must match exactly, e.g. `quality`,
  `Quality gates`).
- No secrets required — `github.token` suffices (issues + PR write + merge).
  Recommended: `PAT_TOKEN` so auto-update-prs re-runs CI on branches it
  refreshes (pushes made with `github.token` do not trigger workflows;
  without a PAT, refreshed PRs stay BEHIND until their next commit).
- Workflow: engineer opens issue → works on `NN-…` branch → PR with
  `Closes #NN` → CI green → puts `pr_approved` on the **issue** → the
  machine merges on the next gate run.

## Runbook

```bash
# 1. Land the wiring via PR (works even when main is already protected):
machine-kit/setup.sh workflows ~/git/<repo> \
  --gate-workflow CI \
  --checks "quality,agents-suite"
# → review + merge the PR

# 2. Arm it (branch protection + fuse + prerequisites check):
machine-kit/setup.sh protect <owner>/<repo> \
  --checks "quality,agents-suite" --enable-fuse
```

`protect` prints any missing secrets/vars as ready-to-run `gh` commands.

## Notes

- `@@GATE_WORKFLOW_NAME@@` is the **workflow** `name:` (what `workflow_run`
  matches), while `--checks` are **job** names (what branch protection
  matches). They are different identifiers on purpose.
- Fork PRs never trigger merges (`head_repository` guard), same as dm.ai.
- History note: the first iteration drove merges from Jira tickets
  (`agents/sm_merge.json` + `retry_merge.js`, `MERGE_TRIGGER_ENABLED` fuse);
  it was replaced by this GitHub-issues flow on 2026-09-08 — the fuse
  variable name carried over. The Jira variant lives in dmtools-dart git
  history (`.github/workflows/merge-trigger.yml` before the switch).
