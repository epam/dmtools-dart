# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- CLI installer (`install.sh`): one-line `curl | sh` install of prebuilt
  AOT binaries from GitHub Releases — standalone (no Dart/Flutter needed on
  the target machine), version-pinned installs (`sh -s -- v0.1.0` or
  `DMTOOLS_VERSION`), optional `DMTOOLS_GITHUB_TOKEN` auth for the private
  repo, best-effort sha256 verification, installs to `~/.dmtools/bin`
  (binary + `native/quickjs/libquickjs_bridge.so` beside it) with PATH
  management. Modeled on the Java `dm.ai` installer and IstiN's
  `flutter_agent_harness` `install.sh`.
- `release-cli.yml`: builds `dmtools-<os>-<arch>.tar.gz` bundles
  (linux-x64, macos-x64, macos-arm64) on every `vX.Y.Z` tag or dispatch,
  smoke-tests each bundle on its builder, publishes assets plus
  `dmtools-checksums.sha256`; the compiled-in version is synced from the
  tag so `dmtools --version` always matches the release.
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
