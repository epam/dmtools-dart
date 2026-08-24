---
wave: W6
status: open   # open | in-progress | done
blocked-by: []
blocks: [W1, W4, W5]
items: 13
note: Gates W1/W4/W5 error surfaces — land P6-BRG-02 early.
---

# Phase 6 W6 — JS bridge (13 items)

- [ ] **P6-BRG-01** schema-driven arg conversion (tryParseArrayStringArg
      with full-JSON-consumption guard, ArrayList→String[] for array params,
      shouldKeepAsList mermaid cases, array→JSON-string re-serialize for
      non-array params) — dart tool_bridge.dart:98 / java
      JobJavaScriptBridge.java:286-604 — L
- [ ] **P6-BRG-02** error contract: every tool failure surfaces as a JS
      Error (`Tool execution failed: ...`) via the `__jsError` sentinel, not
      an error-object return — dart tool_bridge.dart:160 / java
      JobJavaScriptBridge.java:433 — M
- [ ] **P6-BRG-03** `set_env_variable` real implementation (arg count, name
      regex, env present, override store, GitHub client refresh, returns
      true) — dart tool_bridge.dart:129 / java
      JobJavaScriptBridge.java:628 — M
- [ ] **P6-BRG-04** `cli_execute_command` Java contract: single command
      STRING + workingDirectory, 12-command whitelist + CLI_ALLOWED_COMMANDS,
      git-root resolution, env injection, combined-output STRING return,
      SecurityException into JS — dart tool_bridge.dart:192 / java
      CliCommandExecutor.java:81 — L
- [ ] **P6-BRG-05** file tools = Java FileTools exactly (5 tools, string
      returns, recursive dir delete, parent-dir creation, validate_json*) —
      dart tool_bridge.dart:74 / java FileTools.java:59 — M
- [ ] **P6-BRG-06** working-directory sandbox (normalized containment,
      allowed-path patterns, Security violation → null) — dart
      tool_bridge.dart:328 / java FileTools.java:77 — M
- [ ] **P6-BRG-07** jsrunner job context forwarding (ticket/response/
      initiator/inputJql/metadata; jsPath empty → IllegalArgumentException) —
      dart cli_dispatcher.dart:153 / java JSRunner.java:152 — M
- [ ] **P6-BRG-08** JsRunnerJob envelope: raw action() result on success;
      `{"success":false,"error":…,"action":"error"}` on failure; non-map
      jobParams/ticket pass through — dart agent_factory.dart:55 / java
      JavaScriptExecutor.java:118 — M
- [ ] **P6-BRG-09** wrapper ai_chat single-string special case — dart
      tool_wrapper_generator.dart:71 / java
      JobJavaScriptBridge.java:722 — S
- [ ] **P6-BRG-10** DMTOOLS_JS_LOG_TOOL_CALLS verbose wrapper logging — dart
      tool_wrapper_generator.dart:39 / java
      JobJavaScriptBridge.java:713 — S
- [ ] **P6-BRG-11** missing-action error text wrapped as
      `JavaScript execution failed: ...` — dart job_runner.dart:147 / java
      JobJavaScriptBridge.java:777 — S
- [ ] **P6-BRG-12** require() resolves http(s) URLs (SourceCode client) and
      classpath resources; bare-string inline fallback — dart
      require_loader.dart:98 / java JobJavaScriptBridge.java:890 — S
- [ ] **P6-BRG-13** require failure message exactly `Failed to require
      module: <path>` (no cause suffix) — dart require_loader.dart:130 /
      java JobJavaScriptBridge.java:1199 — S
