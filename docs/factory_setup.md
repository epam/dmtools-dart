# Factory Setup — an autonomous dev→review→merge loop for your GitHub repo with fa

This guide replicates the "dark factory" that runs on this repository
(`dmtools-dart`) on any GitHub repo: a human files an issue, assigns it to the
agent, and the machine takes it from there — development, pull request, code
review, bounded rework, and the final merge — with zero human steps in between.

```
issue assigned/labeled
   │
   ▼
┌─────────────────────────── ai-teammate-issues.yml ───────────────────────────┐
│ guard (decide) → restore fa session → install fa + dmtools → write input/    │
│   → dmtools run <runner>.json → fa agent works (live-streamed to run log)    │
│   → persist session + project memory → hand off to reviewer                  │
└──────────────────────────────────────────────────────────────────────────────┘
   │                                    │
   ▼ dev run                            ▼ review run (agent:review)
PR ai/gh-<n> "Closes #<n>"      verdict from outputs/pr_review.json
   │                                    │
   │                    APPROVE ────────┼──────── REQUEST_CHANGES
   │                        │            │      (blocking findings)
   │                        ▼            ▼
   │              pr_approved label   agent:rework → rework run fixes
   │                        │            │       the same PR branch
   ▼                        ▼            ▼
merge-trigger.yml: green CI + pr_approved → squash-merge → issue auto-closes
                          rework rounds capped (MAX_AUTO_REWORK_ROUNDS);
                          past the cap → needs-human + thread summary
```

Everything below is the concrete wiring, in the order you would set it up.

---

## 1. Components

| Piece | What it is | Where it lives here |
|---|---|---|
| **Trigger workflow** | Turns issue events into agent runs | `.github/workflows/ai-teammate-issues.yml` |
| **Merge trigger** | Squash-merges `pr_approved` PRs once CI is green | `.github/workflows/merge-trigger.yml` |
| **machine-kit** | Installer, runner configs, templates | `machine-kit/` (in-repo) |
| **agents submodule** | Agent instructions, job configs, `run-agent.sh` (provider layer) | `agents/` → [IstiN/dmtools-agents](https://github.com/IstiN/dmtools-agents) |
| **dmtools CLI** | Job orchestrator: runs the Teammate/CliAgent lifecycle, JS actions, tool bridge | pinned release bundle ([releases](https://github.com/epam/dmtools-dart/releases)) |
| **fa CLI** | The agent harness itself: sessions, tool calls, `--log-file` transcript | [flutter_agent_harness](https://github.com/IstiN/flutter_agent_harness) releases |

The layering is strictly one-directional: the workflow only knows dmtools;
dmtools only knows `run-agent.sh`; `run-agent.sh` only knows the selected
provider (`AI_AGENT_PROVIDER=fa`); fa talks to the model. Swap any layer
without touching the others.

## 2. Prerequisites

- A GitHub repo where the machine may push branches and merge PRs.
- **fa** with model access. Any fa-supported backend works — this factory runs
  `zai` (glm-5.3-flash) for dev/rework and a review-strength model for review.
  fa is self-contained: every "provider" is an `FA_PROVIDER_CONFIG` env blob,
  no per-provider CLIs are installed.
- **dmtools-dart** release bundle (AOT binary + QuickJS `.so`). Pin a version;
  cut a new release when the CLI gains something the machine needs.
- A **SOURCE_GITHUB_TOKEN** (PAT with repo scope) for the agent's own `git`/`gh`
  operations. The workflow's `github.token` is used for labeling/merging; the
  agent inside the job uses the PAT via a credential helper.
- Optional but recommended: a **bot account** (here: `ai-teammate`) that issues
  get assigned to. A plain user account works identically.

## 3. Labels

Create these (exact names matter — the decide gate matches them):

| Label | Meaning |
|---|---|
| `agent:dev` | Run a development pass on the issue (or assign to the bot — same path) |
| `agent:review` | Run a PR review |
| `agent:rework` | Fix the findings on the linked PR (same branch) |
| `agent:skip` | **Hard opt-out**: the machine never runs on this issue (smoke/verification tickets) |
| `pr_approved` | Review verdict APPROVE — the merge trigger's gate |
| `bug` | Routes `[BUG]`-style tickets to the bug agent config |
| `needs-human` | Set when the rework cap is exhausted |

The cycle also maintains bookkeeping labels (`ai_developed`,
`ai_pr_reviewed`, `rework-round-<n>`, `sm_story_rework_triggered`); create
them on first use or let the workflow's `gh issue edit` calls create them.

## 4. Repo variables and secrets

```
gh variable set FA_VERSION      --body v0.1.357     # fa pin ('latest' allowed, then uncached)
gh variable set DMTOOLS_VERSION --body v0.1.10      # dmtools release tag

gh secret set SOURCE_GITHUB_TOKEN   # agent git/gh operations
gh secret set ZAI_CODE_KEY          # named by FA_PROVIDER_CONFIG.apiKeyEnvVar
gh secret set KIMI_REVIEW_KEY       # the review runner's key (whatever its config names)
```

The rule for keys: **each runner config names its key via
`FA_PROVIDER_CONFIG.apiKeyEnvVar`** — create repo secrets with exactly those
names. `run-agent.sh` maps `FA_PROVIDER_API_KEY` into the named variable only
inside the fa subprocess scope.

## 5. Copy the machine into your repo

1. **`machine-kit/`** — copy the whole directory. You will adapt only
   `teammate-install/runners/*.json` (model choice) and `dmtools.env`.
2. **`agents/` submodule** — add
   `git submodule add https://github.com/IstiN/dmtools-agents.git agents`.
   It carries:
   - `instructions/` — the reviewer/dev prompt material (mermaid flows,
     severity classification, checklists);
   - `<role>.json` job configs (`story_development.json`, `pr_review.json`,
     `pr_rework.json`, …) — these run **as-is**;
   - `scripts/run-agent.sh` + `scripts/providers/fa.sh` — the provider layer;
   - `setup/fa-session.sh` — deterministic session naming (below).

## 6. The workflows

Copy `.github/workflows/ai-teammate-issues.yml` and `merge-trigger.yml`.
Things you will likely touch:

- `AGENT_HANDLE: ai-teammate` — your bot's login.
- `MAX_AUTO_REWORK_ROUNDS: 2` — the rework cap before `needs-human`.
- The runner `case` mapping in the decide step:

```yaml
case "$runner" in
  *fa-bug-dev*)      config="agents/bug_development.json"; kind="dev" ;;
  *fa-story-dev*)    config="agents/story_development.json"; kind="dev" ;;
  *fa-review-kimi*)  config="agents/pr_review.json"; kind="review" ;;
  *fa-rework-zai*)   config="agents/pr_rework.json"; kind="dev" ;;
  *)                 config="$runner"; kind="dev" ;;
esac
```

Each runner is a thin child that only overrides the provider env (everything
else is inherited from the parent agent config):

```json
// machine-kit/teammate-install/runners/fa-story-dev.json
{
  "parent": { "path": "../../../agents/story_development.json" },
  "params": {
    "envVariables": {
      "AI_AGENT_PROVIDER": "fa",
      "FA_PROVIDER_TYPE": "zai",
      "FA_PROVIDER_CONFIG":
        "{\"baseUrl\":\"https://api.z.ai/api/coding/paas/v4\",
          \"model\":\"glm-5.3-flash\",
          \"apiKeyEnvVar\":\"ZAI_CODE_KEY\"}"
    },
    "inputJql": ""
  }
}
```

To run the factory on a different model backend, change `FA_PROVIDER_TYPE` +
`FA_PROVIDER_CONFIG` here — nothing else in the stack knows about providers.

Workflow permissions the loop needs:

```yaml
permissions:
  contents: write       # branches, commits, merge
  pull-requests: write  # PRs, review threads
  issues: write         # labels, comments
  actions: write        # cache saves
concurrency:
  group: ai-teammate-issue-${{ github.event.issue.number }}
  cancel-in-progress: false   # serialize writers per ticket
```

## 7. Sessions — how the agent remembers across runs

Each run resumes a deterministic fa session named `repo:GH-<n>:group`:

- bug/story/rework share the **dev-write** group — a rework run continues the
  ticket's dev conversation;
- review has its own **dev-review** group.

CI runners are cattle, so the session directory (`.dmtools/fa-sessions`) rides
a dedicated git branch `fa-sess/gh-<n>`: fetched and checked out before the
run, force-pushed after it (`if: always()` — a failed run's session is exactly
the context the next rework round needs). Two hardening details that cost us
real incidents — keep them:

```bash
# restore: checkout-from-tree STAGES what it restores; unstage so session
# files never leak into the agent's own PR commits
git checkout "refs/remotes/origin/$FA_SESS_BRANCH" -- .dmtools/fa-sessions
git restore --staged .dmtools/fa-sessions

# persist: snapshot around the branch switch — `git switch --orphan` removes
# TRACKED files from the working tree and would otherwise delete the very
# tree you are about to commit
SESS_SNAP="$(mktemp -d)"
cp -a .dmtools/fa-sessions "$SESS_SNAP/"
git switch --orphan "$FA_SESS_BRANCH" ...
cp -a "$SESS_SNAP/fa-sessions" .dmtools/
git add -f .dmtools/fa-sessions
```

Also add `.dmtools/fa-sessions` to `.gitignore` — belt and suspenders against
the same leak.

> Why git branches and not actions/cache? Cache **saves** are denied on
> `issues`-event runs — the job token is cache-read-only there (verified the
> hard way). Plain `git fetch` works from any event type.

fa's **project memory** (`.fah/memory`) is simpler: it is committed to the
repo by the run's persist step, so knowledge accumulates in the repository
itself and every checkout brings it back.

## 8. Observability — see the agent think

Three channels, all verified live:

1. **Run log, live**: dmtools mirrors the child process output line-by-line to
   its own stderr — you watch `Running: fa …`, every `[bash]`/`[read]`/`[write]`
   harness line, and `=== Agent completed ===` in the Actions log in real time.
2. **`fa-trace-*` artifact**: the workflow exports `FA_LOG_FILE`;
   `providers/fa.sh` forwards it as `fa --log-file` (fa ≥ 0.1.335), which tees
   the full untruncated transcript — assistant text and tool calls — to a file
   uploaded as a run artifact. Post-mortem debugging without rerunning.
3. **`Calling tool …` lines**: the dmtools tool bridge logs every MCP tool
   dispatch (`file_read`, `github_resolve_pr_thread`, …) — the machine's own
   hands.

If the trace artifact comes back **0 bytes**, check that the provider script
actually forwards `--log-file` — an empty file means fa was never told to tee
(our exact bug, fixed in dmtools-agents#416).

## 9. The review verdict and the rework cap

The review run writes `outputs/pr_review.json`; the workflow's *Apply the
review verdict* step parses it:

- **APPROVE** → `pr_approved` label → merge-trigger squashes once CI is green
  (a REQUEST_CHANGES with zero BLOCKING findings is honored as
  approve-with-suggestions — suggestions alone never block).
- **REQUEST_CHANGES** with blockers → `agent:rework` → the rework runner fixes
  the same PR branch → the labeled event re-fires this same workflow for
  re-review.
- Every automatic rework round is counted via `rework-round-<n>` labels; after
  `MAX_AUTO_REWORK_ROUNDS` the machine stops re-labeling, adds `needs-human`,
  and posts a summary of unresolved threads. Re-labeling `agent:rework` by
  hand clears the counter and re-arms the loop with a fresh cap.

Closing the issue is terminal — no agent runs on a closed ticket, whatever the
labels say. `agent:skip` is the same hard exit for open tickets.

## 10. First bring-up — do it in this order

1. **Plumbing smoke (no agent)**: create an issue with `agent:skip` +
   `agent:dev`. Expect the guard step to print `agent:skip — agent bypassed`
   and the `teammate` job to be skipped. This proves the workflow, labels and
   gate wiring without spending a token.
2. **Tiny dev task**: file `docs/agent-smoke.txt` style issue ("create a file
   with one line"), label `agent:dev`. Watch the run log for the live harness
   lines (§8). Verify: PR `ai/gh-<n>` appears, `fa-sess/gh-<n>` branch exists,
   the `fa-trace-*` artifact is non-empty.
3. **Review pass**: the dev run hands off automatically; watch the review run
   produce a verdict and the label state machine execute it.
4. Let the smoke PR merge (or close it and the issue — both are clean exits).

## 11. Operating the factory

- **New task**: file an issue, assign to the bot or label `agent:dev`
  (`[BUG]` title or `bug` label routes to the bug config).
- **CLI feature needed by the machine**: merge it, cut a release
  (`release-cli.yml`, workflow_dispatch — idempotent: re-dispatching an
  existing version is a clean no-op), bump `DMTOOLS_VERSION`.
- **Runaway ticket**: close the issue (terminal) or `agent:skip`.
- **Escalation**: `needs-human` means the cap ran out — fix the PR yourself or
  re-arm with `agent:rework`.

## 12. Incidents this design already survived

Ground truth for why the odd-looking parts look odd:

- **Empty fa-trace artifact** — provider script never passed `--log-file`
  (§8; dmtools-agents#416).
- **`fatal: pathspec '.dmtools/fa-sessions' did not match any files`** —
  restore-step staging leaked session files into the PR branch, then
  `git switch --orphan` deleted the now-tracked tree (§7's two hardenings).
- **Actions cache denied on issue events** — job token is cache-read-only
  there; sessions moved to git branches (§7).
- **Red release run on re-dispatch** — `git tag` dying on "already exists";
  the release flow now treats an existing tag as a clean skip.
- **Duplicate PRs from the same ticket** — in-flight runs re-opened PRs after
  manual cleanup; harmless, close the duplicate, the closed issue is terminal.

---

*Wiring reference in this repo: `.github/workflows/ai-teammate-issues.yml`
(the machine), `machine-kit/README.md` (installer), `agents/AGENTS.md`
(agent-side conventions), `AGENTS.md` §8 (session reuse operating manual).*
