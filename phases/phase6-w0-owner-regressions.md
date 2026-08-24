---
wave: W0
status: done   # open | in-progress | done
blocked-by: []
blocks: []
items: 2
note: Closed 2026-08-24 (session 1).
---

# Phase 6 W0 — Owner-reported regressions (closed 2026-08-24)

- [x] **P6-W00-01** CLI tool-arg parsing must be Java `McpCliHandler`
      `parseToolArguments`/`mapPositionalArguments`/`extractFormatFlag`
      exactly: positional→schema mapping, bare `key=value`, `--data`
      failure→`data:` string, `--format`/`--md`, `--output/--toon/--mini`
      stripped, `--help`→tool schema, positional-mapping-runs-LAST
      precedence. Removed Dart-only positional-JSON, STDIN reading,
      `--file` reading. dart lib/src/cli/cli_dispatcher.dart / java
      McpCliHandler.java:182-494.
- [x] **P6-W00-02** Jira search pagination loops must match Java exactly
      (cloud: null/errorMessages/isLast/empty-issues/token stops; server:
      `total==0` early return, `startAt>total` break, per-page
      maxResults/total refresh). dart
      lib/src/js/sync_tools/jira_sync_tools.dart / java
      JiraClient.java:487-597.
