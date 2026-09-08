# machine-kit — the dark-factory merge loop, portable

The CI/automation "machine" proven in dmtools-dart, packaged for other repos:

```
PR → required checks green → Jira label pr_approved → auto-merge
        ↑ branch kept current by auto-update-prs
```

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
  (required-check contexts must match exactly, e.g. `quality`, `agents-suite`,
  `Quality gates`).
- Secrets/vars (same names as dmtools-dart):
  - vars: `JIRA_EMAIL`, `JIRA_BASE_PATH`
  - secrets: `JIRA_API_TOKEN`, `SOURCE_GITHUB_TOKEN`
  - optional: `PAT_TOKEN` (lets auto-update-prs trigger downstream PR CI;
    falls back to `github.token` without it)
- The Jira project's flow must use the `pr_approved` label on tickets whose
  PRs should auto-merge (rules live in `agents/sm_merge.json`).

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
- The dmtools CLI is installed in merge-trigger from
  `--install-repo` (default `epam/dmtools-dart`) latest release — no local
  dependency on the repo being configured.
- Fork PRs never trigger merges (`head_repository` guard), same as dm.ai.
- Reference implementation: dmtools-dart `.github/workflows/` +
  `phases/`… history; the fuse was turned on there 2026-09-08 after
  branch protection landed.
