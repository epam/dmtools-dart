---
wave: W3
status: open   # open | in-progress | done
blocked-by: [W2]
blocks: []
items: 28
note: Doctor/status text depends on the final config getters (W2).
---

# Phase 6 W3 — Runners / CLI / doctor (28 items)

- [ ] **P6-RUN-01** `mcp` first-arg routing to the MCP CLI surface — dart
      cli_dispatcher.dart:64 / java JobRunner.java:175 — M
- [ ] **P6-RUN-02** remove `help` alias — dart cli_dispatcher.dart:70 — S
- [ ] **P6-RUN-03** base64 JobParams fallback for unknown first arg — dart
      cli_dispatcher.dart:58 / java JobRunner.java:210 — M
- [ ] **P6-RUN-04** `interactive`/`i` real implementation — dart
      cli_dispatcher.dart:197 / java JobRunner.java:365 — L
- [ ] **P6-RUN-05** helpText must be byte-identical to Java printHelp — dart
      cli_dispatcher.dart:430 / java JobRunner.java:299-363 — S
- [ ] **P6-RUN-06** `--version` prints the Java version line format — dart
      version.dart:8 / java JobRunner.java:443 — S
- [ ] **P6-RUN-07** `--list-jobs` prints Java class simple names — dart
      job_registry.dart:46 / java JobRunner.java:378 — S
- [ ] **P6-RUN-08** `.js` run mode: encoded arg IS jobParams; `--key`
      overrides ignored — dart run_command_processor.dart:101 / java
      RunCommandProcessor.java:157 — M
- [ ] **P6-RUN-09** encoded-config position: args[2] only — dart
      run_command_processor.dart:57 / java
      RunCommandProcessor.java:76 — S
- [ ] **P6-RUN-10** override values: no throw on invalid `[/{` prefixes;
      trim before prefix test — dart run_command_processor.dart:88 / java
      RunCommandProcessor.java:232 — S
- [ ] **P6-RUN-11** run error texts/streams match Java (stderr, exact
      messages, empty-file checks) — dart run_command_processor.dart:35 /
      java RunCommandProcessor.java:60-155 — S
- [ ] **P6-RUN-12** parent.override/parent.merge directives read from INSIDE
      the parent block, never stripped at top level — dart
      run_command_processor.dart:225 / java ParentConfigResolver.java:86 — M
- [ ] **P6-RUN-13** cliPrompts structured by-section-id merge
      (CliPromptsConfig.merge) — dart run_command_processor.dart:210 / java
      ParentConfigResolver.java:225 — M
- [ ] **P6-RUN-14** all 23 jobs executable (not only cliagent+jsrunner) —
      dart cli_dispatcher.dart:139 / java JobRunner.java:237-297 — L
- [ ] **P6-RUN-15** jsrunner CLI path forwards ticket/response/initiator/
      inputJql/metadata into JS params — dart cli_dispatcher.dart:154 /
      java JSRunner.java:152 — S
- [ ] **P6-RUN-16** JS null result: stderr message + exit 1 (not
      'undefined'/0) — dart cli_dispatcher.dart:165 / java
      JobRunner.java:187 — S
- [ ] **P6-RUN-17** jsPath resolution: classpath resources; http(s) via
      configured SourceCode client (auth, blob→raw) — dart job_runner.dart:227
      / java JobJavaScriptBridge.java:890 — M
- [ ] **P6-RUN-18** tool-call error shape: pretty JSON `{"error":true,...}`
      on STDOUT exit 0 — dart cli_dispatcher.dart:209 / java
      McpCliHandler.java:289 — S
- [ ] **P6-RUN-19** CLI_OUTPUT config + output formatter surface (toon/mini/
      json/md) — dart cli_dispatcher.dart:358 / java
      McpCliHandler.java:222 — M
- [ ] **P6-RUN-20** encoding detector: `+`→space, blank input throws Java
      message, error texts — dart encoding_detector.dart:14 / java
      EncodingDetector.java:29 — S
- [ ] **P6-RUN-21** doctor per-integration status strings — dart
      doctor_command.dart:86 / java ConfigDoctor.java:186 — S
- [ ] **P6-RUN-22** doctor missing-lines text (combined alternatives) — dart
      doctor_command.dart:112 / java ConfigDoctor.java:74 — S
- [ ] **P6-RUN-23** doctor confluence always requires email+token — dart
      doctor_command.dart:129 / java ConfigDoctor.java:79 — S
- [ ] **P6-RUN-24** doctor figma: OAuth refresh + base path checks — dart
      doctor_command.dart:140 / java ConfigDoctor.java:87 — S
- [ ] **P6-RUN-25** doctor AI: bedrock key pair, dial/anthropic extras —
      dart doctor_command.dart:147 / java ConfigDoctor.java:152 — S
- [ ] **P6-RUN-26** doctor teams tenant defaults to 'common' (never
      missing) — dart doctor_command.dart:163 / java
      PropertyReader.java:1240 — S
- [ ] **P6-RUN-27** doctor 14th defaults check + warnings — dart
      doctor_command.dart:96 / java ConfigDoctor.java:64,174 — S
- [ ] **P6-RUN-28** doctor connectivity phase (`<integration>_test` calls +
      status suffixes) — dart doctor_command.dart:82 / java
      DoctorCommand.java:37 — M
