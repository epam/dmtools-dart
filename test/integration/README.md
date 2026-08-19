# Test layers

dmtools-dart has four test layers (GOAL.md → Integration testing strategy;
AGENTS.md §6). Each layer has a fixed home and a fixed cadence — put every new
test in the layer it belongs to.

| Layer | What it covers | Where it lives | When it runs |
|---|---|---|---|
| **L1 unit** | Dart tests, everything mocked (HTTP via canned-response adapters, no network) | `test/**` (e.g. `test/config/`, `test/cli/`, `test/integrations/<name>/`) | pre-commit hook + CI `quality.yml`, every push/PR |
| **L2 contract** | Recorded Java tool requests/responses replayed against the Dart clients (fixture parity, not network) | `test/**` with recorded Java fixtures | CI `quality.yml`, every push/PR |
| **L3 live integration** | Real APIs (Jira, ADO, GitHub, GitLab, ...) against sandbox instances | `test/integration/` — this directory, tagged `@Tags(['integration'])` | nightly + manual `workflow_dispatch` (.github/workflows/integration.yml), **never per-PR by default** |
| **L4 agents suite** | The dmtools-agents JS suite (`agents/js/unit-tests/run_all.json`) executed by the product itself under the Dart runtime | external repo `IstiN/dmtools-agents` | dedicated CI job, the primary acceptance gate |

Note the naming split: `test/integrations/` (plural) holds L1/L2 mocked client
and tool tests; `test/integration/` (singular) holds L3 live tests. Nothing in
this directory runs in the default quality loop.

## Running the L3 suite

`dart_test.yaml` declares the `integration` tag with a default `skip`, so a
plain `dart test` (and therefore CI `quality.yml`) never executes these tests —
they load, get marked skipped, and cost nothing.

The default skip is sticky: `-t integration` alone still skips the tag. The
`integration` preset re-enables it, so the opt-in command is:

```bash
# L3 only (needs real credentials):
dart test -P integration -t integration

# Full suite including L3:
dart test -P integration
```

## Mechanics (rules for tests in this directory)

- **Tagging** — every file here starts with a library-level annotation:

  ```dart
  @Tags(['integration'])
  library;
  ```

  The annotation must be on the `library` directive (or before the first
  import). Putting `@Tags(...)` on `main()` compiles with a warning but the
  tag is silently ignored — the runner will then run the test by default and
  `-t integration` will not match it.

- **Credentials** come from the standard resolution chain — real env vars,
  then `dmtools.env`, then `dmtools-local.env` — the same Phase 1
  `PropertyReader` path production uses. Locally that means a git-ignored
  `dmtools.env` with real keys; in CI the same variables arrive as injected
  secrets. No test-specific config files, no hardcoded values anywhere.

- **Sandbox targeting** via `DMTOOLS_IT_*` variables (`DMTOOLS_IT_JIRA_PROJECT`,
  `DMTOOLS_IT_GITHUB_REPO`, `DMTOOLS_IT_ADO_PROJECT`,
  `DMTOOLS_IT_CONFLUENCE_SPACE`, ...). These point tests at throwaway
  projects/repos/spaces; they select *where* to test, never *how* to
  authenticate. A missing target variable skips the test.

- **Skip-or-fail** — missing credentials skip locally. In the CI integration
  job `DMTOOLS_IT_REQUIRE_CREDS=true` turns cred-skips into failures, so the
  suite cannot silently rot when a secret expires.

- **Fixture lifecycle** — every object a test creates is namespaced
  `it-<runId>-...`, created in `setUp`/test body and deleted via
  `addTearDown`. Prefer read-only checks over writes wherever a write is not
  the point of the test.

- **Coverage** — the crap4dart coverage gate measures L1+L2 only, never L3.

## Required credentials per integration

The CI job (`.github/workflows/integration.yml`) injects every variable below
from a same-named GitHub **repository secret**; locally the same names go into a
git-ignored `dmtools.env` (the Phase 1 resolution chain). `DMTOOLS_IT_*`
variables select the **sandbox target** — *where* to test — and a missing one
skips (or, under `DMTOOLS_IT_REQUIRE_CREDS`, fails) the suite. The rest are
**authentication** — *how* to test. Sandbox-only tokens with minimal scopes;
never reuse production credentials here.

| Integration | Secret (env var) | Purpose |
|---|---|---|
| **Jira** | `JIRA_BASE_PATH` | REST API base URL (e.g. `https://<site>.atlassian.net`) |
| | `JIRA_EMAIL` | Account email — Basic auth username |
| | `JIRA_API_TOKEN` | API token — Basic auth password |
| | `DMTOOLS_IT_JIRA_PROJECT` | Sandbox project key the tests target (gate var) |
| | `DMTOOLS_IT_JIRA_ISSUE_TYPE` | Issue type for the throwaway `it-*` ticket (default `Task`) |
| **GitHub** | `SOURCE_GITHUB_TOKEN` | Access token (Bearer) |
| | `DMTOOLS_IT_GITHUB_REPO` | Sandbox repo `owner/name` the tests target |
| **GitLab** | `GITLAB_TOKEN` | Access token (`PRIVATE-TOKEN` header) |
| | `DMTOOLS_IT_GITLAB_PROJECT` | Sandbox project id/path the tests target |
| **Confluence** | `CONFLUENCE_BASE_PATH` | REST API base URL |
| | `CONFLUENCE_EMAIL` | Account email — Basic auth username |
| | `CONFLUENCE_API_TOKEN` | API token — Basic auth password |
| | `DMTOOLS_IT_CONFLUENCE_SPACE` | Sandbox space key the tests target |
| **Azure DevOps** | `ADO_ORGANIZATION` | DevOps organization name |
| | `ADO_PROJECT` | Project (doubles as the test target) |
| | `ADO_PAT_TOKEN` | Personal access token (`Basic :PAT`) |
| **Figma** | `FIGMA_TOKEN` | Personal access token (`FIGMA_OAUTH_ACCESS_TOKEN` also accepted) |
| | `DMTOOLS_IT_FIGMA_FILE` | Sandbox file key the tests target |
| **TestRail** | `TESTRAIL_BASE_PATH` | REST API base URL |
| | `TESTRAIL_USERNAME` | Username (Basic auth `username:apikey`) |
| | `TESTRAIL_API_KEY` | API key |
| | `DMTOOLS_IT_TESTRAIL_PROJECT` | Sandbox project the tests target |
| **Bitrise** | `BITRISE_TOKEN` | Personal access token (Bearer) |
| | `BITRISE_APP_SLUG` | App slug the tests target |
| **Jenkins** | `JENKINS_BASE_PATH` | Base URL (default `http://localhost:8080`) |
| | `JENKINS_USER` | Username — Basic auth |
| | `JENKINS_API_TOKEN` | API token — Basic auth |
| **Microsoft Teams** | `TEAMS_CLIENT_ID` | Entra ID app (client) registration ID |
| | `TEAMS_TENANT_ID` | Entra ID tenant ID |
| | `TEAMS_REFRESH_TOKEN` | Refresh token for the Entra app (OAuth) |
| **SharePoint** | — | Matrix slot reserved; the live test and its Microsoft Graph credentials land with the Phase 3 SharePoint port. |

Non-secret runtime control:

- `DMTOOLS_IT_REQUIRE_CREDS` — set to `true` in the CI job so a missing gate
  variable fails the suite instead of silently skipping it (see Mechanics →
  Skip-or-fail). Not a secret; set as a plain env var.

## Current contents

- `jira_integration_test.dart` — Jira smoke path via CLI tool dispatch
  (`ToolBridge.execute` → `SyncToolDispatcher`): creates a throwaway
  `it-<runId>-smoke` ticket, then auth (`jira_get_ticket`) → search
  (`jira_search_by_jql`) → labels (`jira_add_label`/`jira_remove_label`) →
  comment (`jira_post_comment`) → transition (`jira_move_to_status`) →
  delete in `tearDownAll`. Gated on `DMTOOLS_IT_JIRA_PROJECT`; the throwaway
  ticket's issue type is `DMTOOLS_IT_JIRA_ISSUE_TYPE` (default `Task`).
- `ado_integration_test.dart` — Azure DevOps smoke path (auth → list work items
  WIQL → get work item), gated on `DMTOOLS_IT_ADO_PROJECT`.
- `figma_integration_test.dart` — Figma smoke path (auth → get file → get
  components), gated on `DMTOOLS_IT_FIGMA_FILE`.
- `testrail_integration_test.dart` — TestRail smoke path (auth → get cases →
  get case), gated on `DMTOOLS_IT_TESTRAIL_PROJECT`; the suite under test is
  selected by `DMTOOLS_IT_TESTRAIL_SUITE`.
- `gitlab_integration_test.dart` — GitLab smoke-path skeleton (auth → get MR
  → list MRs → note → cleanup), gated on `DMTOOLS_IT_GITLAB_PROJECT`.
- `confluence_integration_test.dart` — Confluence smoke-path skeleton (auth →
  search CQL → get page → create page → cleanup), gated on
  `DMTOOLS_IT_CONFLUENCE_SPACE`.
- `github_integration_test.dart` — GitHub smoke path (auth → list PRs → get
  PR → create comment → get issue → cleanup comment), gated on
  `DMTOOLS_IT_GITHUB_REPO` (`owner/repo`); auth via `SOURCE_GITHUB_TOKEN`.
