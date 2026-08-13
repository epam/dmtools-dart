# AGENTS.md — rules for working in dmtools-dart

Pure Dart port of DMTools (Java/GraalJS → Dart/QuickJS). **Read `GOAL.md` first —
it is the spec.** This file is the operating manual: rules, commands, layout.

---

## 1. Non-negotiable rules

1. **crap4dart is law.** CRAP threshold **8.0** (`crap4dart.yaml`). Pre-commit hook
   runs `crap4dart check --staged`; CI runs `check --all` + `analyze` on every push.
   Never commit on red, never weaken a gate to make code pass.
2. **Signature parity with Java DMTools.** Config JSON keys, tool names
   (snake_case), env variables, CLI commands — identical to the Java version.
   A config or `dmtools.env` that works with Java must work unchanged here.
   When behavior is ambiguous, **the Java source is the spec**; record the decision
   in the commit message.
3. **No JVM, no GraalVM.** Dart only. JS runtime will be QuickJS via `dart:ffi`
   with synchronous host calls (not the `flutter_js` plugin).
4. **Thin `bin/`.** CI coverage is collected with `--report-on lib`, so `bin/` is
   outside LCOV. All logic lives in `lib/`; `bin/` only parses argv and delegates.
5. **Tests ship with code.** Coverage gate is 80% (`gates.test_coverage`).
   Test code is held to the same bar (`sources: [lib, bin, test]`).
6. **Never commit secrets.** `dmtools.env` / `dmtools-local.env` are git-ignored;
   keep them that way. Credentials in tests come only from the standard config
   resolution chain (see GOAL.md → Integration testing strategy).

## 2. Where things are

| Path | What |
|---|---|
| `GOAL.md` | **The spec**: mission, constraints, audit facts, phases 0–5, test strategy |
| `crap4dart.yaml` | Quality gate config (threshold 8.0, sources lib/bin/test) |
| `.github/workflows/quality.yml` | CI: format → analyze → test+coverage → crap4dart |
| `bin/dmtools.dart` | CLI entry (stub; full JobRunner surface = Phase 2) |
| `lib/` | All implementation code |
| `test/` | `dart test` suite (L1 unit; L2 contract fixtures later) |

Java reference implementation (read-only, the spec for behavior):
**https://github.com/epam/dm.ai** — clone it fresh (always the latest upstream);
key files are named per phase in GOAL.md (e.g. `PropertyReader.java`,
`JobRunner.java`, `JobJavaScriptBridge.java`, `cliagent/CliAgent.java`).
Agent scripts and the JS test suite: **https://github.com/IstiN/dmtools-agents**.
JS runtime (`jsr`) extensions go to **https://github.com/IstiN/flutter_js_widget_runtime**
via fork + PR — never vendored here (see GOAL.md).

## 3. Local dev loop

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"   # crap4dart lives here; without it the
                                           # pre-commit hook SKIPS checks silently

dart pub get
dart format .                              # CI fails on unformatted code
dart analyze
dart test --coverage=coverage
dart pub global run coverage:format_coverage \
  --lcov --in coverage --out coverage/lcov.info --report-on lib
crap4dart check --all                      # gates (fast, no network)
crap4dart analyze                          # CRAP scores, threshold 8.0
```

If crap4dart is missing: `dart pub global activate crap4dart`.

## 4. Commit & CI discipline

- Small, focused commits; message states *what* and *why* (and the Java file that
  served as spec, when porting behavior).
- The hook runs only on staged files — CI runs everything, so run the full local
  loop above before pushing.
- CI red = stop and fix; no merging on red.
- `git commit --no-verify` is a code smell; if you use it, say why in the message.

## 5. Current status & next work

**All 5 phases implemented.** 328 MCP tools across 17 integrations (100% of the
328 Java @MCPTool set). QuickJS runtime via dart:ffi with sync callbacks —
dmtools-agents suite passes 694/698 (4 upstream bugs). CliAgent lifecycle fully
ported. `dmtools run`, `list`, `doctor`, `--version`, `--help`, `--list-jobs`
all functional.

**Remaining work** (diminishing returns, in priority order):
1. Sync HTTP dispatch expanded — [SyncHttpClient] + [SyncToolDispatcher] route
   `jira_*` and `github_*` tool calls via curl subprocess within
   NativeCallable callbacks. Jira tools: `jira_get_ticket`,
   `jira_post_comment`, `jira_search_by_jql`, `jira_add_label`,
   `jira_remove_label`, `jira_move_to_status`, `jira_get_comments`,
   `jira_update_field`, `jira_update_description`, `jira_get_transitions`,
   `jira_assign_to` (alias `jira_assign`), `jira_get_my_profile`,
   `jira_delete_ticket`, `jira_create_ticket_basic` (alias
   `jira_create_ticket`). GitHub tools: `github_get_pr`,
   `github_create_comment`. File-system (`file_*`) and CLI (`cli_*`) tools
   delegate to the host bridge via `SyncToolDispatcher.nonHttpHandler`.
2. CliAgent timer/error/line JS actions, InstructionProcessor
3. CI: agents suite job wired (quality.yml updated, continues-on-error until
   sync HTTP dispatch lands)
4. Integration test layer (L2 contract tests, L3 live integration)
5. Tool catalog CI comparison check against Java fixtures

Phase checkboxes live in GOAL.md — tick them as you complete items and keep the
file current when a decision changes the plan.

## 6. Testing layers (so you put each test in the right place)

| Layer | Location | Runs where |
|---|---|---|
| L1 unit | `test/`, mocked | pre-commit + CI quality.yml |
| L2 contract | `test/` with recorded Java fixtures | CI quality.yml |
| L3 live integration | `test/` `@Tags(['integration'])`, creds via env/`dmtools.env` | nightly + manual, excluded by default via `dart_test.yaml` |
| L4 agents suite | external `agents/js/unit-tests/run_all.json` | dedicated CI job from Phase 4 |

The agents suite (`dmtools run agents/js/unit-tests/run_all.json` under the Dart
runtime, unmodified) is the **primary acceptance gate** — see GOAL.md.

## 7. Style notes

- `dart format` defaults; public API documented (public_docs gate enforces it).
- Keep methods small (complexity ≤ 10, body ≤ 60 lines, params ≤ 6 — the gates
  enforce this; design around it rather than fighting it).
- Generated code (`*.g.dart`, `*.freezed.dart`) is gate-excluded by default —
  don't hand-edit, regenerate.
