# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- TestRail section-aware case creation, porting Java PR
  [epam/dm.ai#462](https://github.com/epam/dm.ai/pull/462):
  `testrail_get_sections` (`project_name` + optional `suite_id`, paginated,
  always fetched fresh) and the `testrail_create_case`,
  `testrail_create_case_detailed`, `testrail_create_case_steps` tools with an
  optional `section_id` that falls back to the project's default section
  (creating a "Test Cases" section when the project has none). Markdown
  tables in text fields convert to TestRail `|||:Col|Col` format or HTML for
  the Steps template. The L3 suite exercises the new tools against the
  TestRail sandbox (sections read + create/delete round-trips per flavour,
  resolving the project id → name via the Java-parity `getProjects`
  envelope), the nightly integration job gains the missing
  `DMTOOLS_IT_TESTRAIL_SUITE` wiring, and `integration-pr.yml` gains a
  `testrail` matrix leg.
- Generic named tool arguments on the CLI: `dmtools <tool> --key value` and
  `--key=value` map onto the tool's arguments (merged over a positional JSON
  blob), porting the Java `McpCliHandler.parseToolArguments` change from the
  same PR.
- Sync tool dispatch for the full agent-used surface — the dispatcher
  (`lib/src/js/sync_tool_dispatcher.dart`) now routes by prefix to
  self-contained per-integration classes in `lib/src/js/sync_tools/`
  (mirroring the Java integration clients):
  - **Jira** (`jira_sync_tools.dart`): the previous 16 tools plus
    `jira_link_issues`, `jira_attach_file_to_ticket` (multipart),
    `jira_create_ticket_with_parent`, `jira_set_priority`,
    `jira_assign_ticket_to`, `jira_create_ticket_with_json`,
    `jira_get_field_custom_code`; `jira_create_ticket_basic` restored as the
    canonical name (Java `JiraClient` parity) with
    `tracker_create_ticket`/`jira_create_ticket` aliases.
  - **GitHub** (`github_sync_tools.dart` + workflow-log and release-asset
    helpers): 23 executors — PR comments/labels/threads/diff/merge, workflow
    runs (302+ZIP log resolution), draft releases, binary asset upload.
    Existing `github_get_pr`/`github_create_comment` args fixed to the Java
    `workspace`/`repository`/`pullRequestId`/`text` names (agents passed
    these; the old `owner`/`repo`/`number` shape produced
    `GET repos///pulls/0`).
  - **GitLab** (`gitlab_sync_tools.dart`): MR comments/threads/labels/diff/
    merge/rebase, pipelines, statuses, discussions, releases with binary
    asset transfer, accepts both Java (`workspace`/`repository`/
    `pullRequestId`) and legacy (`project`/`iid`/`body`) args.
  - **ADO** (`ado_sync_tools.dart`): PR comments/threads/labels/diff/merge,
    pipelines (list/runs/logs/trigger) alongside the moved work-item tools.
  - **Confluence** (`confluence_sync_tools.dart` + `confluence_markdown.dart`
    + `markdown_confluence_sync.dart`): search/pages/children/update plus the
    full Markdown→storage directory sync engine (`confluence_sync_markdown_
    directory`, port of Java `MarkdownConfluenceSync`) with multipart
    attachments.
  - **Bitrise** (`bitrise_sync_tools.dart`): builds/artifacts with the
    `BITRISE_ALLOW_WRITES` write guard (same knob as the async client).
  - **Jenkins** (`jenkins_sync_tools.dart`): job info + build logs
    (`toApiJobPath` ported 1:1).
  - **AI** (`ai_sync_tools.dart`): per-provider `gemini_ai_chat`,
    `openai_ai_chat`, `anthropic_ai_chat`, `ollama_ai_chat`,
    `dial_ai_chat`, `bedrock_ai_chat` (Java exposes one @MCPTool per
    provider; the dmtools-agents `aiChat.js` helper resolves
    `globalThis[provider + '_ai_chat']` dynamically and falls through on
    error — failures surface as JS errors via the `__jsError` sentinel).
  Canonical tool catalog: 328 → 387 definitions; the Java↔Dart gap snapshot
  shrinks 210 → 159 entries (no agent-script tool call remains uncovered).
- Tool wrappers for aliases — the wrapper generator emits a JS global per
  alias dispatching the canonical name (Java's schema registry exposes
  aliases as dispatchable tools; scripts call e.g.
  `jira_create_ticket_basic` directly).
- CommonJS `require()` loader (`lib/src/js/require_loader.dart`) — 1:1 port
  of the Java `JobJavaScriptBridge` module loader (`RequireProxy` /
  `loadModule` / `resolveModulePath` / `setCurrentScriptDirectory`).
  Implemented as a JS bootstrap prelude over the `file_read` host function
  and `eval()` so module exports can carry functions (the FFI JSON marshaling
  cannot). Java-parity semantics: `./`/`../` resolution against the current
  script directory with `..` normalization, module cache keyed by resolved
  path with a placeholder cached before eval (circular requires terminate),
  the exact Java module wrapper, script-directory save/set/restore in
  `try`/`finally`, `Failed to require module: <path>` on failure with the
  `JavaScript file not found` cause preserved, and the
  `require() expects exactly one argument (module path)` validation.
- JSRunner job context forwarding (`lib/src/agents/agent_factory.dart`) —
  `ticket`, `response`, `initiator`, `inputJql`, `metadata` from the job
  params block now land in the JS `params` object exactly as Java
  `JSRunner.runJobImpl` + `JavaScriptExecutor.withJobContext()`/`.with()`
  place them; missing/blank `jsPath` fails with the Java message
  `jsPath parameter is required`, and script failures return
  `{'success': false, 'error': …}` instead of crashing (Java
  `JavaScriptExecutor.execute()` error-result parity).
- Script source resolution parity (`lib/src/js/job_runner.dart`) — Java
  `loadJavaScriptCode` semantics: http(s) `jsPath` fetches the source
  synchronously (curl-backed [SyncHttpClient]), inline JS (`function`-prefixed,
  `action`-containing, or non-path non-`.js` strings) executes directly, and
  file paths that are missing fail with
  `JavaScript file not found in resources or filesystem: <path>`.
- Action contract and error surfacing — scripts without `action(params)`
  fail with the Java-parity
  `JavaScript code must define an 'action' function` (Java CliAgent JS
  actions use the same `JavaScriptExecutor` contract, so it is enforced on
  both the JSRunner and CliAgent paths); script/action eval exceptions now
  surface as `JavaScript execution failed: <message>` instead of a silent
  `null` result.
- Host-function argument validation with JS-visible errors — FFI host
  functions cannot throw into JS, so `executeToolViaJava` /
  `set_env_variable` validation failures return a `{'__jsError': …}`
  sentinel that a JS bootstrap wrapper rethrows as a real `Error`, matching
  the Java `IllegalArgumentException` messages
  (`executeToolViaJava requires at least 1 argument: toolName`,
  `set_env_variable requires 2 arguments: propertyName, envVarName`).
  `executeToolViaJava(toolName)` with no args object now executes with empty
  args, as in Java.
- Community files ported from the Java [dm.ai](https://github.com/epam/dm.ai)
  repository: `LICENSE` (Apache-2.0), `SECURITY.md` (vulnerability disclosure
  policy, repo links adapted), `CODE_OF_CONDUCT.md` (Contributor Covenant
  2.1), `CONTRIBUTING.md` (dm.ai structure rewritten for the Dart toolchain —
  `make native`/`dart test`/crap4dart gates instead of Gradle).
- CLI installer (`install.sh`): one-line `curl | sh` install of prebuilt
  AOT binaries from GitHub Releases — standalone (no Dart/Flutter needed on
  the target machine), version-pinned installs (`sh -s -- v0.1.0` or
  `DMTOOLS_VERSION`), optional `DMTOOLS_GITHUB_TOKEN` auth for the private
  repo, best-effort sha256 verification, installs to `~/.dmtools/bin`
  (binary + `native/quickjs/libquickjs_bridge.so` beside it) with PATH
  management. Modeled on the Java `dm.ai` installer and IstiN's
  `flutter_agent_harness` `install.sh`.
- `release-cli.yml`: dm.ai-style **button release** — `workflow_dispatch`
  with an optional custom version; empty input auto-increments the patch
  version from `pubspec.yaml`, commits the bump (pubspec +
  `lib/src/version.dart`), tags `vX.Y.Z`, pushes, and publishes the release
  with a generated changelog. Builds `dmtools-<os>-<arch>.tar.gz` bundles
  (linux-x64, macos-x64, macos-arm64), smoke-tests each bundle on its
  builder, and attaches `install.sh` + `dmtools-checksums.sha256`; the
  compiled-in version is synced from the tag so `dmtools --version` always
  matches the release.
- `install-test.yml`: simulates clean-machine installs across the OS
  matrix and exercises `dmtools --version` / `dmtools list`; `dash -n` +
  `shellcheck` the installer on every PR.

## [0.1.0] — 2026-08-13

Initial feature-complete release. Dart port of [DMTools](https://github.com/epam/dm.ai)
(Java/GraalJS → Dart/QuickJS). All 5 GOAL.md phases implemented.

### Added

#### Phase 1 — Property config
- `PropertyReader` with full resolution chain: overrides → `dmtools.env` → `dmtools-local.env` → OS env → defaults
- All ~120 env var getters with identical names/defaults to Java source
- Auth chains: Jira base64, Confluence Bearer/Basic, Gemini/Bedrock fallback chains, range clamping
- Fixture-based end-to-end tests proving Java `dmtools.env` compatibility

#### Phase 2 — CLI interface
- `dmtools run <config>` — end-to-end: config resolution, deep-merge, AgentFactory dispatch
- `dmtools list [filter]` — prints 325-tool catalog with filtering
- `dmtools doctor` — 13-integration config presence check
- `dmtools <tool_name> '<json_args>'` — direct tool invocation with STDIN/heredoc support
- `dmtools --version`, `--help`, `--list-jobs`, `interactive` (stub)

#### Phase 3 — Integrations (325 tools, 17 integrations)
- Jira (65), GitHub (40), GitLab (31), ADO (31), Confluence (29), File (19),
  TestRail (18), Figma (15), Jenkins (13), SharePoint (12), Teams (11),
  Bitrise (10), AI (8), Xray (8), KB (8), Mermaid (4), CLI (3)
- 100% Java @MCPTool parity (325 Dart tools cover all 328 Java `@MCPTool`
  names — directly, via aliases, or via documented renames — verified by
  `catalog_parity_test.dart`)
- Shared `BaseHttpClient` + `BearerHttpClient` base classes
- AI providers: Gemini, OpenAI, DIAL, Anthropic, Ollama (+ embeddings, summarize, complete)
- L2 contract test framework

#### Phase 4 — JS runtime (QuickJS via dart:ffi)
- QuickJS compiled from source (`native/quickjs/`), C bridge with flat ABI
- Synchronous JS→Dart→JS host callbacks via `NativeCallable.isolateLocal`
- `executeToolViaJava` tool dispatch to Phase 3 registry
- Auto-generated snake_case wrappers for all 325 tools
- Sync HTTP dispatch via curl subprocess (26 tools across 5 integrations)
- **738/738 dmtools-agents tests pass** (primary acceptance gate)

#### Phase 5 — CliAgent
- Full lifecycle: `setup → preJSAction → preCliJSAction → cliCommands → postJSAction → cache → reset`
- 26-field parameter contract with `fromJson` factory
- Timer/error/line JS actions
- `InstructionProcessor`: file path embedding, GitHub PR/Jira key annotation
- `TicketInputContextBuilder`: ticket.md, ticket.json, subtasks/, comments.md

#### Integration tests + CI
- 11 L3 live integration test suites (`test/integration/`)
- `.github/workflows/integration.yml`: nightly + manual, matrix per integration
- `.github/workflows/quality.yml`: dynamic badges, agents suite job
- `dart_test.yaml`: integration tag excluded from default run
- `test/integration/README.md`: all required env secrets documented

### Quality
- 1799 tests passing
- 97.8% line coverage
- Max CRAP 8.0 (threshold enforced by crap4dart)
- All 6 quality gates green (format, analyze, coverage, complexity, method_size, duplication, public_docs)
