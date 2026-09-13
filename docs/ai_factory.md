# The AI Factory in dmtools-dart — complete setup reference

This is the operating manual for the autonomous agent loop **as deployed in
this repository**. Where [`factory_setup.md`](factory_setup.md) explains how to
replicate the factory on another repo, this page documents every wire of the
running machine here: workflows, runners, secrets, labels, session and memory
persistence, observability, and the runbook we actually use.

Status: in production since 2026-09-12 — the full loop
(dev → PR → review → rework ×2 → merge, zero human steps) has run end-to-end
on gh-85, and the machine developed and merged a CI feature by itself (gh-50,
PR #57).

---

## 1. The loop

```
human files issue, assigns ai-teammate (or labels agent:dev)
   │
   ▼  ai-teammate-issues.yml (AI Teammate : issue assigned)
guard ─► session restore ─► fa + dmtools install ─► input/gh-<n>/ ─► agent runs
   │                                                          │
   │                                     live harness lines in the run log
   ▼
PR ai/gh-<n> "Closes #<n>" ◄──────────────────────────────────┘
   │
   ▼  hand-off: agent:review
review run ─► outputs/pr_review.json ─► Apply the review verdict
   │
   ├─ APPROVE ─────────────► pr_approved ─► merge-trigger.yml ─► squash ─► issue closes
   └─ REQUEST_CHANGES ─────► agent:rework ─► rework run (same branch)
                                │
                                └─ rounds counted (rework-round-<n>);
                                   cap = MAX_AUTO_REWORK_ROUNDS (2);
                                   past cap ─► needs-human + thread summary
```

Terminal states: **closed issue** (nothing ever runs on it again) and
**`agent:skip`** (hard opt-out, honored at the guard for every entry path —
dev, review, rework and any pipeline-added label all re-enter the same gate).

## 2. Workflows

| Workflow | Role |
|---|---|
| `ai-teammate-issues.yml` | The factory trigger. `on: issues [assigned, labeled]`; one `teammate` job per run. |
| `merge-trigger.yml` | Squash-merges the PR linked to a `pr_approved` issue once required checks are green. Fired by `check_suite completed` and `issues labeled pr_approved`. |
| `quality.yml` | The gates every PR must pass: format → analyze → tests+coverage → crap4dart check/analyze → agents suite. These are the "CI green" the merge trigger waits for. |
| `release-cli.yml` | Dispatch-only release: version bump + tag → AOT builds (linux x64/arm64, macos x64/arm64, windows x64) → GitHub release with checksums. Idempotent: re-dispatching an existing version is a clean no-op. |
| `auto-update-prs.yml` | Keeps open PR branches fresh against main. |

Key `ai-teammate-issues.yml` env (top of the file):

```yaml
AGENT_HANDLE: ai-teammate                     # bot account issues are assigned to
FA_VERSION:      ${{ vars.FA_VERSION      || 'latest' }}   # fa pin (uncached when latest)
DMTOOLS_VERSION: ${{ vars.DMTOOLS_VERSION || 'v0.1.5' }}   # dmtools release tag
MAX_AUTO_REWORK_ROUNDS: 2
concurrency: group ai-teammate-issue-<n>, cancel-in-progress: false
permissions: contents/pr/issues/actions: write
```

## 3. The runner layer (model routing)

A **runner** is a thin child config that pins a provider on top of an agent
config from the `agents/` submodule. Everything else — instructions, lifecycle,
JS actions — is inherited from the parent.

| Runner file (machine-kit/teammate-install/runners/) | Parent (agents/) | Provider | Model | Used for |
|---|---|---|---|---|
| `fa-story-dev.json` | `story_development.json` | zai | glm-5.3-flash | story dev (default path) |
| `fa-bug-dev.json` | `bug_development.json` | zai | glm-5.3-flash | `[BUG]` tickets |
| `fa-review-kimi.json` | `pr_review.json` | kimi | k3 | PR review (stronger reviewer model) |
| `fa-rework-zai.json` | `pr_rework.json` | zai | glm-5.3-flash | rework rounds |

```json
{
  "parent": { "path": "../../../agents/story_development.json" },
  "params": {
    "envVariables": {
      "AI_AGENT_PROVIDER": "fa",
      "FA_PROVIDER_TYPE": "zai",
      "FA_PROVIDER_CONFIG":
        "{\"baseUrl\":\"https://api.z.ai/api/coding/paas/v4\",
          \"model\":\"glm-5.3-flash\",\"apiKeyEnvVar\":\"ZAI_CODE_KEY\"}"
    },
    "inputJql": ""
  }
}
```

The guard maps labels → runner (`case` in the decide step): `agent:rework` →
rework runner, `agent:review` → review runner, assignee/bot or `agent:dev` →
bug-vs-story by title/label. Swapping a model backend means editing one
`FA_PROVIDER_*` blob here — nothing else in the stack knows providers exist.

## 4. Secrets, variables, credentials

**Repo secrets**

| Secret | Consumer |
|---|---|
| `SOURCE_GITHUB_TOKEN` | the agent's own `git`/`gh` operations inside the job (credential helper; push branches, threads, PRs) |
| `ZAI_CODE_KEY` | dev + rework runners (`FA_PROVIDER_CONFIG.apiKeyEnvVar`) |
| `KIMI_REVIEW_KEY` | review runner |

**Repo variables**

| Variable | Meaning |
|---|---|
| `FA_VERSION` | fa release tag (`latest` allowed — then the cache step is skipped) |
| `DMTOOLS_VERSION` | dmtools release tag the run installs |

Rule: each runner names its key via `apiKeyEnvVar`; a repo secret with that
exact name must exist. `run-agent.sh` maps `FA_PROVIDER_API_KEY` into the
named variable **only** inside the fa subprocess scope.

The workflow's own `github.token` handles labels/merges; permissions are
`contents/pull-requests/issues/actions: write`.

## 5. Labels — the state machine

| Label | Set by | Effect |
|---|---|---|
| `agent:dev` | human (or assignee = bot) | dev run |
| `agent:review` | dev run's hand-off step | review run |
| `agent:rework` | verdict step (CHANGES + blockers) | rework run |
| `agent:skip` | human | guard exits — machine bypassed |
| `pr_approved` | verdict step (APPROVE) | merge trigger gate |
| `needs-human` | verdict step (cap exhausted) | escalation, loop disarmed |
| `bug` / `[BUG]` title | human | routes to bug runner |
| `ai_developed`, `ai_pr_reviewed`, `sm_story_rework_triggered` | pipeline | bookkeeping |
| `rework-round-<n>` | verdict step | the cap counter |

Protocol detail that prevents suggestion-loops: a REQUEST_CHANGES verdict with
**zero BLOCKING findings** is honored as approve-with-suggestions — only
correctness findings (broken behavior, failing gates, scope violations) count
as blocking.

## 6. Sessions and memory

**Conversational memory** — fa named sessions, resumed every run:

- name `repo:GH-<n>:group` with groups **dev-write** (bug/story/rework share
  it — rework continues the dev conversation) and **dev-review**;
- derived in `agents/setup/fa-session.sh` from the runner's parent config;
- consumed as `fa --session <name> --session-root <dir>` by
  `agents/scripts/providers/fa.sh`.

**Transport** — the session directory `.dmtools/fa-sessions` rides the git
branch `fa-sess/gh-<n>` (Actions cache saves are denied on issues-event runs):

- restore step (before the run): `git checkout <branch> -- .dmtools/fa-sessions`
  followed by `git restore --staged .dmtools/fa-sessions` — the unstage is
  load-bearing: checkout-from-tree stages what it restores, and staged session
  files would leak into the agent's PR commits;
- persist step (after the run, `if: always()`): snapshot the tree to a temp
  dir, `git switch --orphan fa-sess/gh-<n>`, copy back, `git add -f`, force
  push. The snapshot is load-bearing: `switch --orphan` removes tracked files
  from the working tree.
- `.gitignore` also lists `.dmtools/fa-sessions` — belt and suspenders.

**Project knowledge** — fa's `.fah/memory` is committed to the repo and pushed
after every run; every checkout brings the accumulated knowledge back.

## 7. Observability

Three channels, all live-verified:

1. **Run log, real time** — dmtools mirrors the agent process output to its
   own stderr: `Running: fa …`, every `[bash]`/`[read]`/`[write]` harness
   line, `=== Agent completed ===`. You literally watch the agent think in
   the Actions log.
2. **`fa-trace-gh-<n>-<run_id>` artifact** — the workflow exports
   `FA_LOG_FILE`; `providers/fa.sh` passes it to `fa --log-file` (fa ≥
   0.1.335), teeing the full untruncated transcript (model text + tool
   calls). Empty artifact = the flag was not forwarded (that exact bug:
   dmtools-agents#416).
3. **`Calling tool …` lines** — the dmtools tool bridge logs every MCP tool
   dispatch (`file_read`, `github_reply_to_pr_thread`, …).

Plus `run-output.txt` in the same artifact (dmtools' own captured output) and
the credential-helper trace.

## 8. Operating runbook

| Situation | Action |
|---|---|
| New task | file issue → assign `ai-teammate` (or label `agent:dev`; `[BUG]`/`bug` → bug path) |
| Want a re-review | label `agent:review` on the issue |
| Machine needs a new CLI feature | merge it → dispatch `release-cli.yml` (bump `DMTOOLS_VERSION` var) → done |
| Ticket spinning | close the issue (terminal) or `agent:skip` |
| `needs-human` fired | fix the PR yourself, or re-label `agent:rework` (clears the counter, fresh cap) |
| Verify plumbing without spending tokens | issue with `agent:skip` + `agent:dev` — expect `agent bypassed` in the guard log |
| Smoke the full pipeline | tiny docs-only issue ("create file X with one line") → watch the live log → close PR + issue manually |

Bring-up order for a fresh clone of this setup: skip-guard smoke → tiny dev
task → let the review pass run → done (detailed steps in
[`factory_setup.md`](factory_setup.md) §10).

## 9. Incident runbook (real cases, 2026-09-12)

| Symptom | Root cause | Fix |
|---|---|---|
| `❌ Error in preparePRForReview: {}` | extraGlobals not flattened into the JS `params` object | #90 (Java `JavaScriptExecutor.execute()` parity) |
| `fa-trace` artifact 0 bytes | provider script never passed `--log-file` | dmtools-agents#416 + submodule bump #91 |
| Live agent output invisible in run log | pinned `DMTOOLS_VERSION` predated the stderr-mirror feature | release + `DMTOOLS_VERSION` var bump |
| `fatal: pathspec '.dmtools/fa-sessions' did not match any files` | restore-step staging leaked sessions into the PR branch; `switch --orphan` then deleted the tracked tree | unstage in restore (#89, machine-authored) + snapshot in persist (#100) |
| Red Release CLI run | re-dispatch of an existing version died at `git tag` | #102 — existing tag ⇒ clean no-op with warning |
| Duplicate PRs on one ticket | in-flight runs re-opened PRs after manual cleanup | close the duplicate; closed issue is terminal (no code change needed) |

## 10. Where everything lives

```
.github/workflows/ai-teammate-issues.yml   the factory (guard → run → verdict → persist)
.github/workflows/merge-trigger.yml        pr_approved + green CI → squash-merge
machine-kit/teammate-install/runners/*.json provider pinning (this page §3)
machine-kit/teammate-install/install.sh     dmtools bundle installer (linux/macos/windows)
agents/ (submodule → IstiN/dmtools-agents)  instructions, job configs, run-agent.sh,
                                             providers/fa.sh, setup/fa-session.sh
.dmtools/fa-sessions/ (gitignored)          session tree; transport = fa-sess/gh-<n> branches
.fah/memory/                                fa project memory, committed to the repo
docs/factory_setup.md                       replicate this on another repository
AGENTS.md §8                                session-reuse operating notes (in-repo)
```

The one upstream dependency to watch: the `agents/` submodule pointer moves
via PRs to [IstiN/dmtools-agents](https://github.com/IstiN/dmtools-agents);
fa and quickjs_runtime likewise live in their own repositories (fork + PR,
never vendored).
