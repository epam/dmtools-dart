# GOAL — dmtools-dart

## Mission

Port **DMTools** (Java 17 / GraalJS, `github.com/epam/dm.ai`) to **pure Dart** so the
orchestrator runs cross-platform — CLI, desktop, and mobile — without a JVM.

The JavaScript scripting layer moves from GraalJS (Truffle, JVM-only) to **QuickJS**
(via `dart:ffi`), reusing the proven bridge pattern from
`github.com/IstiN/flutter_js_widget_runtime` (`jsr.*` host-controlled I/O).

Reference implementation (source of truth for behavior and signatures):
`/Users/Uladzimir_Klyshevich/git/dm.ai/dm.ai`

---

## Hard constraints (non-negotiable)

### 1. Signature parity with Java DMTools

All configurations, parameters, CLI commands, tool names, and env variables MUST keep
**exactly the same names and shapes** as in Java DMTools. A config JSON or `dmtools.env`
that works with the Java version MUST work unchanged with the Dart version.

- Job config JSON keys — identical (e.g. `cliCommands`, `preJSAction`,
  `cleanupInputFolder`, `timerIntervalSeconds`), including defaults.
- MCP tool names — identical snake_case (`jira_post_comment`, `cli_execute_command`,
  `github_get_pr`, ...). Tool argument schemas — identical.
- Env variables — identical names (`JIRA_BASE_PATH`, `JIRA_API_TOKEN`, `ADO_PAT`,
  `SOURCE_GITHUB_TOKEN`, `CLI_ALLOWED_COMMANDS`, ...).
- CLI surface — identical commands and flags (`run`, `list`, `doctor`, `interactive`,
  `--version`, `--help`, `--list-jobs`, `<tool_name> <json_args>`,
  `dmtools run <config> [override]`).
- JS scripting API visible to agent scripts — identical globals
  (`jira_*`, `github_*`, `file_*`, `cli_execute_command`, `require`, `set_env_variable`,
  `params.jobParams/ticket/response`, ...). Agent JS files from the Java ecosystem
  must run unmodified (synchronous call style preserved).
- **Full `@MCPTool` coverage**: every method annotated `@MCPTool` in
  `dmtools-mcp-annotations`-processed classes (329 annotations across 27 classes in
  `dmtools-core`) gets a Dart implementation with the same tool name, argument
  schema, and behavior. No "partial registry" releases.
- **The existing agent test suite is a primary acceptance gate** (see below).

### 2. Quality gate: crap4dart from commit #1

`github.com/IstiN/crap4dart` is wired in **before any feature code**:

- `crap4dart.yaml` in repo root (`crap4dart init`), **CRAP threshold = 8.0**
  (the default; do not raise).
- **Pre-commit hook** installed (`crap4dart install`) — runs `check --staged` on
  every commit.
- **CI workflow** (`.github/workflows/quality.yml` via `crap4dart install --ci`) —
  format, `dart analyze`, tests with coverage, `crap4dart check`, `crap4dart analyze`
  on every push/PR. Exit code 2 fails the pipeline.
- `sources: [lib, bin, test]` — test code is held to the same bar.
- Every ported class ships with tests; coverage gate stays enabled
  (`coverage.required: true`).

### 3. No JVM, no GraalVM

Dart only. QuickJS is embedded via `dart:ffi` (not via the `flutter_js` plugin) so
that host calls from JS are **synchronous** — this preserves the sync call style of
all 177 existing agent scripts and works in headless CLI (where Flutter plugins are
unavailable).

---

## Audit facts that shape the port

(From auditing `dmtools-core` + `dmtools-agents`, 2026-08-11.)

- The Java JS sandbox is already bridge-shaped: GraalJS `Context` with
  `allowAllAccess(false)` plus exactly three host primitives:
  `executeToolViaJava(toolName, args)`, `require(path)`, `set_env_variable(name, envVar)`.
- All snake_case tool functions are **generated wrappers** over
  `executeToolViaJava`, produced from `MCPSchemaGenerator` schemas for 16 integrations:
  `jira, ado, ai, confluence, figma, file, cli, teams, sharepoint, kb, mermaid,
  testrail, github, gitlab, bitrise, jenkins` (+ `jira_xray` when the tracker is Xray).
- Java interop in agent scripts: **1 guarded call** in 177 files
  (`Java.type('java.lang.Thread').sleep(ms)` behind `typeof Java !== 'undefined'`).
- Script module system: CommonJS — `require` ×287, `module.exports` ×234, with a custom
  loader supporting relative paths, module cache, and circular requires
  (`RequireProxy` in `JobJavaScriptBridge.java`). This loader logic must be ported 1:1.
- ES feature usage is modest (`??` ×6, `async` ×3); QuickJS ES2020 covers everything.
- Most-used tools in agent scripts: `jira_post_comment` (132), `cli_execute_command`
  (126), `jira_remove_label` (102), `jira_move_to_status` (93), `file_read` (89),
  `file_write` (64), `jira_search_by_jql` (45), `jira_add_label` (42),
  `jira_get_ticket` (32).
- The MCP surface is annotation-driven: 329 `@MCPTool` annotations across 27 classes,
  processed by `dmtools-annotation-processor` into the schema registry
  (`MCPSchemaGenerator`). The Dart port needs an equivalent build-time registry
  generation (annotated Dart classes → tool schemas), not a hand-maintained list.

## Primary acceptance gate: the dmtools-agents test suite

`dmtools-agents` ships a GraalJS-based unit test suite for the agent scripts
(`agents/js/unit-tests/`, ~115 test files plus `js/test/*.test.js`), executed through
the product itself:

```bash
dmtools run agents/js/unit-tests/run_all.json
```

The suite runs on a custom in-JS framework (`testRunner.js`) providing
`test/suite`, `assert.*`, and — critically — `loadModule(path, requireFn, mocks)`
with mock injection that shadows global dmtools tool functions per module, and
`makeRequire(moduleMap)`.

**Rule: the Dart build must run this suite, unmodified, green.** It is the
end-to-end proof that the QuickJS runtime, the CommonJS loader, the tool bridge,
and the job-context injection are all behaviorally identical to GraalJS. The suite
is wired into CI (as a dedicated job, not part of `dart test`) and must pass before
any phase is called complete. `testRunner.js` itself runs under the ported runtime —
if the framework runs, the runtime is compatible.

When the Dart CLI exists, the exact gate command becomes:

```bash
dart run bin/dmtools.dart run agents/js/unit-tests/run_all.json
```

---

## Scope & phases

### Phase 0 — Repo bootstrap (quality first)

- [ ] `dart create` package layout (`lib/`, `bin/dmtools.dart`, `test/`).
- [ ] `crap4dart init` → review config, keep `crap.threshold: 8.0`.
- [ ] `crap4dart install --ci` → pre-commit hook + `.github/workflows/quality.yml`.
- [ ] GitHub repo connected; first CI run green on the empty skeleton.

**Done when:** an empty Dart skeleton commits through the hook and passes the workflow.

### Phase 1 — Property config (`PropertyReader` / `ApplicationConfiguration` parity)

Reference: `dmtools-core/.../common/utils/PropertyReader.java` (1567 lines),
`common/config/ApplicationConfiguration.java`.

- [ ] Config resolution order identical to Java: real env vars → `dmtools.env` →
      `dmtools-local.env` → defaults; real env always wins (mirrors
      `run-teammate-local.sh` semantics).
- [ ] Thread-local/zone-local overrides (`PropertyReader.getOverrides()` equivalent)
      — required by `CLI_ALLOWED_COMMANDS` and job-level `envVariables`.
- [ ] Every env var getter used by integrations (Jira, ADO, GitHub, GitLab,
      Confluence, Figma, TestRail, AI providers, Bitrise, Jenkins, Teams, SharePoint)
      with identical names and defaults.
- [ ] `set_env_variable(name, envVar)` runtime switching.

**Done when:** a Java `dmtools.env` dropped into a Dart run resolves to the same
effective configuration (unit-tested against fixture env files).

### Phase 2 — CLI interface (`JobRunner` parity)

Reference: `dmtools-core/.../job/JobRunner.java`, `job/RunCommandProcessor.java`,
`dmtools.sh`.

- [ ] Commands: `run <config_file> [override_json]`, `list`, `doctor`, `interactive`,
      `--version`/`-v`, `--help`/`-h`, `--list-jobs`.
- [ ] Direct tool invocation: `dmtools <tool_name> '<json_args>'` → dispatches to the
      MCP tool registry, same JSON in/out as Java.
- [ ] Deep-merge semantics of the `run` override: override wraps into `params`
      exactly like Java (`{"params":{"jobParams":{...}}}`); bare `{"jobParams":...}`
      is ignored the same way (documented quirk preserved).
- [ ] Job-name dispatch (`cliagent`, `teammate`, `jsrunner`, ...) — registry keyed by
      the same lowercase names, aliases included.
- [ ] STDIN / heredoc / file input modes of `dmtools.sh` (as a Dart executable).

**Done when:** `dmtools list` prints the same tool catalog as Java for the same env
configuration; golden tests on CLI stdout/stderr and exit codes.

### Phase 3 — Integrations (MCP tool registry parity)

Reference: `dmtools-core/.../job/JobJavaScriptBridge.java` (`exposeMCPToolsUsingGenerated`),
`mcp/MCPSchemaGenerator.java`, integration clients under `atlassian/`, `github/`,
`gitlab/`, `ado/`, `figma/`, `bitrise/`, `jenkins/`, `teams/`, `sharepoint/`,
`testrail/`, `kb/`, `mermaid/`.

**Implementation order: Jira first.** It is the tracker backbone of the whole agent
ecosystem (top-10 most used tools in agent scripts are mostly `jira_*`), and it is
the hardest auth/semantics case — solving it first sets the pattern for everything
after.

- [ ] **Jira (+ Xray) — with explicit Server/Data Center vs Cloud duality.** Java
      reference: `atlassian/jira/BasicJiraClient.java`, `atlassian/jira/JiraClient.java`,
      `PropertyReader.getJiraAuthType()`. Behaviors to reproduce exactly:
  - Auth resolution chain: `JIRA_LOGIN_PASS_TOKEN` (pre-built base64) → else
    `JIRA_EMAIL` + `JIRA_API_TOKEN` → `base64(email:token)`; `JIRA_AUTH_TYPE`
    overrides the Authorization scheme (Cloud: `Basic`; Server/DC PAT: `Bearer`).
  - API version awareness: the Java client mixes `/rest/api/2`, `/rest/api/3`, and
    `/rest/api/latest` per endpoint. Dart must keep the same per-endpoint paths and
    add a Server/Cloud compatibility matrix — Server/DC lacks some `api/3`
    endpoints, Cloud removed some `api/2` ones (user search, `name`-based fields
    vs `accountId`, GDPR-censored payloads).
  - Same auxiliary config: `JIRA_EXTRA_FIELDS`, `JIRA_EXTRA_FIELDS_PROJECT`,
    `JIRA_SEARCH_MAX_RESULTS`, cache flags, `JIRA_WAIT_BEFORE_PERFORM`,
    `SLEEP_TIME_REQUEST`, custom-field-to-name transformation.
  - Contract tests (L2) must include **both** Server and Cloud recorded payloads;
    live integration matrix (L3) gets one Cloud and, when available, one Server/DC
    sandbox entry (`DMTOOLS_IT_JIRA_DEPLOYMENT=cloud|server`).
- [ ] Tool schema registry: same tool names, same argument schemas, same
      availability rules (tool appears only when its integration is configured).
- [ ] **Complete `@MCPTool` parity**: all 329 `@MCPTool`-annotated methods (27 classes)
      are ported. Registry is generated at build time from Dart-side annotations —
      the Dart equivalent of `dmtools-annotation-processor` + `MCPSchemaGenerator` —
      so the catalog can never drift from the implementations. A CI check compares
      the generated Dart tool catalog against the Java one (names + schemas) and
      fails on any missing or mismatched tool.
- [ ] HTTP clients for the remaining integrations on `dio` (after Jira): ADO,
      GitHub, GitLab, Confluence, Figma, TestRail, Bitrise, Jenkins, Teams,
      SharePoint, KB, Mermaid.
- [ ] `file_*` tools, `cli_execute_command` with the same whitelist mechanics
      (`git, gh, dmtools, npm, yarn, docker, kubectl, terraform, ansible, aws,
      gcloud, az` + `CLI_ALLOWED_COMMANDS` extension).
- [ ] AI providers: Gemini, OpenAI, DIAL, Bedrock, Ollama — same env-var selection.

**Done when:** the generated Dart tool catalog matches the Java `@MCPTool` catalog
100% (CI comparison green), and contract tests replay recorded Java tool
requests/responses against the Dart implementations (fixtures captured from the Java
version).

### Phase 4 — JS runtime (GraalJS → QuickJS)

- [ ] QuickJS via `dart:ffi` with **synchronous** host callbacks.
- [ ] `executeToolViaJava` equivalent (single generic dispatch into the Phase 3
      registry), `require` CommonJS loader port (cache, relative paths, circular
      requires), `set_env_variable`.
- [ ] Generated snake_case wrappers from the tool schema registry — same generation
      approach as Java.
- [ ] Job context injection: `params.jobParams`, `params.ticket` (same JSON shape as
      `JavaScriptExecutor.convertParametersForJS`), `params.response`, `initiator`,
      `inputJql`, `metadata`, `customParams`, `inputFolderPath`, `workingDirectory`.
- [ ] The dmtools-agents suite (`agents/js/unit-tests/run_all.json`) is added to CI
      as a dedicated job and stays green from this phase on.

**Done when:** `dart run bin/dmtools.dart run agents/js/unit-tests/run_all.json`
passes **unmodified and green** (the primary acceptance gate) — this transitively
proves the runtime, loader, bridge, and mock-injection semantics — and real agent
scripts (`smAgent.js`, `retryMergePR.js`, `checkStoryTestsPassed.js`) run unmodified
against mocked integrations.

### Phase 5 — CliAgent port (first agent)

Reference: `dmtools-core/.../cliagent/CliAgent.java`, `cliagent/CliAgentParams.java`,
`teammate/CliExecutionHelper.java`, `teammate/CliCommandBuilder.java`,
`teammate/InstructionProcessor.java`, `teammate/TicketInputContextBuilder.java`.

Lifecycle (exact order): `setup → preJSAction → preCliJSAction → cliCommands →
postJSAction → cache → reset` (reset always runs, even on failure).

Parameter contract (all keys, types, defaults preserved):

| Key | Type | Default |
|---|---|---|
| `input` | object (`InputParams`) | null |
| `cliCommands` | string[] | required |
| `cliPrompt` | string | null |
| `cliPrompts` | string[] or structured `CliPromptsConfig` | null |
| `cliPromptsByTracker` | map<string, string[]> | null |
| `setup` / `cache` / `reset` | string (shell cmd or `.js`) | null |
| `preCliJSAction` | string (js path) | null |
| `cleanupInputFolder` | bool | **true** |
| `requireCliOutputFile` | bool | false |
| `workingDirectory` | string | cwd |
| `excludedEnvVariables` | string[] | null |
| `excludeEnvVariablesByRegex` | string[] | null |
| `timerJSAction` | string | null |
| `timerIntervalSeconds` | int | **60** |
| `cleanupOutputsFolder` | bool | false |
| `cliExecutionErrorJSAction` | string | null |
| `cliOutputLineJSAction` | string | null |

Plus inherited `TrackerParams` plumbing (`outputType`, `envVariables`, `metadata`,
`initiator`, ...). Backward-compatible dual accessors for `cliPrompts` (flat array
and structured config) are part of the contract.

Behavioral details to preserve: stale `outputs/response.md` cleanup on start,
`input/<contextId>` folder convention, outputs-first folder preference, live-output
accumulation for timer/error/line JS actions, `contextId` fallback to `"cli-agent"`.

**Done when:** a real CliAgent config JSON from the Java ecosystem runs under Dart
with identical observable behavior (files created, commands executed, JS actions
fired in order).

### Later phases (out of initial scope, listed for direction)

Teammate, JSRunner, TestCasesGenerator and the remaining JobRunner jobs; MCP server
mode; GitHub Actions workflow compatibility (`ai-teammate.yml`).

---

## Integration testing strategy

Live-API tests are a separate, opt-in layer — they must never slow down or
destabilize the default quality loop.

### Test layers

| Layer | What | When it runs |
|---|---|---|
| L1 unit | Dart tests, everything mocked | pre-commit + CI `quality.yml` |
| L2 contract | Recorded Java tool requests/responses replayed against Dart clients | CI `quality.yml` |
| L3 **live integration** | Real APIs (Jira, ADO, GitHub, ...) against sandbox instances | nightly + manual (`workflow_dispatch`), never per-PR by default |
| L4 agents suite | `agents/js/unit-tests/run_all.json` under the Dart runtime | CI dedicated job (from Phase 4) |

### Mechanics

- Live tests live under `test/` tagged `@Tags(['integration'])` with a
  `dart_test.yaml` that **excludes the tag by default**; run explicitly via
  `dart test -t integration`.
- **Credentials come from the standard resolution chain** — real env vars first,
  then `dmtools.env`, then `dmtools-local.env` (the Phase 1 config layer, same path
  production uses). Locally the expected setup is a git-ignored `dmtools.env` with
  real keys; in CI the same variables arrive as injected secrets. No test-specific
  config files, no hardcoded values anywhere.
- **Sandbox targeting** via test-scoped overrides: `DMTOOLS_IT_JIRA_PROJECT`,
  `DMTOOLS_IT_GITHUB_REPO`, `DMTOOLS_IT_ADO_PROJECT`, `DMTOOLS_IT_CONFLUENCE_SPACE`,
  etc. These point tests at throwaway projects/repos/spaces; they select *where*
  to test, never *how to authenticate*.
- **Skip-or-fail policy**: missing credentials → test skips locally. In the CI
  integration job, `DMTOOLS_IT_REQUIRE_CREDS=true` turns cred-skips into failures,
  so the suite cannot silently rot when a secret expires.
- **Fixture lifecycle**: every created object is namespaced `it-<runId>-...`,
  created in setUp, deleted in tearDown. A standalone sweeper (`bin/it_sweep.dart`)
  deletes leaked `it-*` objects older than N hours; CI runs it after the suite.
- **CI shape** (`.github/workflows/integration.yml`): nightly schedule +
  `workflow_dispatch`, matrix per integration (jira / ado / github / gitlab / ...),
  secrets injected as env vars, `concurrency` group per integration to prevent
  parallel writes to the same sandbox. One red integration does not block others.
- **Token hygiene**: sandbox-only tokens with minimal scopes, stored as GitHub
  secrets; test output scrubbed of credential material; read-only checks preferred
  over write checks where a write is not the point of the test.
- **Recording mode**: the same live runs can regenerate L2 contract fixtures
  (`DMTOOLS_IT_RECORD=true`), keeping contract tests fresh against real API
  responses — this replaces manual fixture capture from the Java version over time.

### Coverage expectations (per integration)

Smoke path first: auth → read (get ticket / get PR) → search (JQL/list) → write
(post comment, add label, transition) → cleanup. Each smoke maps 1:1 to the most
used tools from the audit (`jira_post_comment`, `jira_search_by_jql`,
`jira_move_to_status`, `github_get_pr`, ...). Deeper edge cases grow only when a
bug demands them — the crap4dart coverage gate measures L1+L2, not L3.

---

## Working agreements

- Small commits; the pre-commit hook is law (bypass via `--no-verify` is a code
  smell, not a workflow).
- CI red = stop and fix, no merging on red.
- When Java behavior is ambiguous, the Java source is the spec; record the decision
  in the commit message.
- Generated code (`*.g.dart`, `*.freezed.dart`) is excluded from gates via
  crap4dart defaults — keep it that way.
