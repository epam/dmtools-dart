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

## Current contents

- `jira_integration_test.dart` — Jira smoke-path skeleton (auth → read →
  search → write), gated on `DMTOOLS_IT_JIRA_PROJECT`.
