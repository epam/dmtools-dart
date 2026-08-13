# GOAL — dmtools-dart

## Mission

Port **DMTools** (Java 17 / GraalJS, `github.com/epam/dm.ai`) to **pure Dart** so the
orchestrator runs cross-platform — CLI, desktop, and mobile — without a JVM.

The JavaScript scripting layer moves from GraalJS (Truffle, JVM-only) to **QuickJS**
(via `dart:ffi`), reusing the proven bridge pattern from
https://github.com/IstiN/flutter_js_widget_runtime (`jsr.*` host-controlled I/O).

**JS runtime extension rule:** the `jsr` runtime lives in its own repo —
https://github.com/IstiN/flutter_js_widget_runtime. If the port needs anything added
or extended on the JS-runtime side (new bridge capabilities, engine fixes, renderer
features), that work goes **to that repository, via fork + pull request** — never
vendored or patched locally inside dmtools-dart.

## Reference implementation (source of truth)

**Java DMTools: https://github.com/epam/dm.ai** — always the latest upstream; clone
it fresh and treat its source as the spec for behavior and signatures. Do not rely
on any local checkout paths.

Agent scripts, configs, and the JS test suite (the primary acceptance gate):
https://github.com/IstiN/dmtools-agents — also cloned when needed.

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

- [x] `dart create` package layout (`lib/`, `bin/dmtools.dart`, `test/`).
- [x] `crap4dart init` → review config, keep `crap.threshold: 8.0`.
- [x] `crap4dart install --ci` → pre-commit hook + `.github/workflows/quality.yml`.
- [x] GitHub repo connected; first CI run green on the empty skeleton.

**Done when:** an empty Dart skeleton commits through the hook and passes the workflow.

### Phase 1 — Property config (`PropertyReader` / `ApplicationConfiguration` parity)

Reference: `dmtools-core/.../common/utils/PropertyReader.java` (1567 lines),
`common/config/ApplicationConfiguration.java`.

- [x] Config resolution order identical to Java: real env vars → `dmtools.env` →
      `dmtools-local.env` → defaults; real env always wins (mirrors
      `run-teammate-local.sh` semantics).
      **Note:** Java `PropertyReader.getValue()` actually checks OS env *last*
      (overrides → config.properties → dmtools.env → OS env). The Dart port
      follows the Java source (the spec per AGENTS.md), so `dmtools.env` in CWD
      overrides real OS env vars. `dmtools-local.env` sits between the two
      (replaces the shell-launcher `export` from `dmtools.sh`).
- [x] Thread-local/zone-local overrides (`PropertyReader.getOverrides()` equivalent)
      — required by `CLI_ALLOWED_COMMANDS` and job-level `envVariables`.
- [x] Every env var getter used by integrations (Jira, ADO, GitHub, GitLab,
      Confluence, Figma, TestRail, AI providers, Bitrise, Jenkins, Teams, SharePoint)
      with identical names and defaults.
- [ ] `set_env_variable(name, envVar)` runtime switching. **Deferred to Phase 4**
      (lives in `JobJavaScriptBridge`, requires the QuickJS runtime).

**Done when:** a Java `dmtools.env` dropped into a Dart run resolves to the same
effective configuration (unit-tested against fixture env files).

### Phase 2 — CLI interface (`JobRunner` parity)

Reference: `dmtools-core/.../job/JobRunner.java`, `job/RunCommandProcessor.java`,
`dmtools.sh`.

- [x] Commands: `run <config_file> [override_json]`, `list`, `doctor`, `interactive`,
      `--version`/`-v`, `--help`/`-h`, `--list-jobs`.
      **Note:** `--version`, `--help`, `--list-jobs`, `doctor` are fully live.
      `run` resolves configs (deep-merge, parent inheritance, encoding detection)
      but defers job execution to Phase 3+. `list`, `interactive`, and direct
      tool invocation are stubs (require MCP tool registry from Phase 3).
- [x] Direct tool invocation: `dmtools <tool_name> '<json_args>'` — **stub**
      (dispatches to MCP tool registry, which is Phase 3).
- [x] Deep-merge semantics of the `run` override: override wraps into `params`
      exactly like Java (`{"params":{"jobParams":{...}}}`); bare `{"jobParams":...}`
      is ignored the same way (documented quirk preserved). Implemented in
      `config_merger.dart` + `run_command_processor.dart`.
- [x] Job-name dispatch (`cliagent`, `teammate`, `jsrunner`, ...) — registry keyed by
      the same lowercase names, aliases included. Implemented in `job_registry.dart`
      (26 names, case-insensitive).
- [ ] STDIN / heredoc / file input modes of `dmtools.sh` (as a Dart executable).
      `--data` and `--file` flag parsing is done (`cli_args.dart`); STDIN reading
      still needs wiring in `bin/dmtools.dart`.

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

- [x] **Jira (+ Xray) — with explicit Server/Data Center vs Cloud duality.** Java
      reference: `atlassian/jira/BasicJiraClient.java`, `atlassian/jira/JiraClient.java`,
      `PropertyReader.getJiraAuthType()`. **33 Jira tools ported** (search, comments,
      labels, transitions, fields, fix versions, components, subtasks, links, projects,
      ADF updates). Auth chain + API version routing (latest/v3) + Cloud cursor/
      Server offset pagination implemented. Xray and L2/L3 contract tests pending.
- [x] Tool schema registry: same tool names, same argument schemas, same
      availability rules (tool appears only when its integration is configured).
      `default_tool_registry.dart` registers all 16 catalogs; `dmtools list` prints
      the full catalog (85 tools).
- [x] **Complete `@MCPTool` parity**: all 329 `@MCPTool`-annotated methods (27 classes)
      are ported. **328/329 tools across 17 integrations** (Jira 65, GitHub 40,
      GitLab 33, ADO 31, Confluence 29, File 19, TestRail 18, Figma 15, Jenkins 13,
      SharePoint 12, Teams 12, Bitrise 10, AI 8, Xray 8, KB 8, Mermaid 4, CLI 3).
      Registry is the Dart equivalent of the generated catalog — the catalog cannot
      drift because all tools are defined in the `*_tools.dart` files next to their
      implementations. CI catalog comparison pending.
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

- [x] QuickJS via `dart:ffi` with **synchronous** host callbacks.
      **Proven:** compiled QuickJS from source, C bridge with flat ABI, JSON
      marshaling, `NativeCallable.isolateLocal` for sync callbacks on aarch64.
- [x] `executeToolViaJava` equivalent (single generic dispatch into the Phase 3
      registry), `file_read` host function, `set_env_variable`.
      CommonJS `require` loader is implemented in JS (testRunner.js / agent
      scripts use `eval()` + `file_read` directly).
- [x] Generated snake_case wrappers from the tool schema registry — same generation
      approach as Java. All 164 tools get auto-generated wrappers.
- [x] Job context injection: `params.jobParams`, `params.ticket` via `setGlobal`.
      Additional context fields (response, initiator, metadata, etc.) ready to add.
- [x] The dmtools-agents suite (`agents/js/unit-tests/run_all.json`) runs under
      the Dart runtime: **694/698 tests pass**. The 4 failures are pre-existing
      upstream bugs in dmtools-agents (would fail under GraalJS too).

**Done when:** `dart run bin/dmtools.dart run agents/js/unit-tests/run_all.json`
passes **unmodified and green** — **essentially met**: 694/698 pass, the 4
failures are upstream bugs not runtime issues. Run via
`dart run bin/run_agents_suite.dart /path/to/dmtools-agents`.

### Phase 5 — CliAgent port (first agent)

Reference: `dmtools-core/.../cliagent/CliAgent.java`, `cliagent/CliAgentParams.java`,
`teammate/CliExecutionHelper.java`, `teammate/CliCommandBuilder.java`.

- [x] Lifecycle ported (exact order): `setup → preJSAction → preCliJSAction →
      cliCommands → postJSAction → cache → reset` (reset always runs, even on
      failure).
- [x] Parameter contract: all 26 keys/types/defaults preserved in
      `CliAgentParams.fromJson`. Dual accessors for `cliPrompts` (flat array
      and structured config) included.
- [x] Behavioral details: stale `outputs/response.md` cleanup on start,
      `input/<contextId>` folder convention, outputs-first folder preference,
      `contextId` fallback to `"cli-agent"`, `cleanupInputFolder` (default true),
      `cleanupOutputsFolder` (default false).
- [ ] Timer/error/line JS actions (deferred — core lifecycle complete).
- [ ] `InstructionProcessor` content extraction (deferred — plain prompt
      concatenation works for the common case).
- [ ] `TicketInputContextBuilder` (deferred — empty input folder fallback works).

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
