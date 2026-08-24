---
wave: W2
status: open   # open | in-progress | done
blocked-by: []
blocks: [W3]
items: 13
note: No upstream; doctor wording (W3) settles after the config chain is final.
---

# Phase 6 W2 — Config chain (13 items)

- [ ] **P6-CFG-01** add config.properties tier (project-root
      src/main/resources, classpath fallback) + `setConfigFile()` — dart
      property_reader.dart:130 / java PropertyReader.java:163-241 — S
- [ ] **P6-CFG-02** empty value must NOT block fall-through (Java: non-null
      AND non-empty to accept a tier) — dart property_reader.dart:137 /
      java PropertyReader.java:226 — S
- [ ] **P6-CFG-03** remove the dmtools-local.env tier (Java has none) — dart
      property_reader.dart:141 / java PropertyReader.java:112-161 — S
- [ ] **P6-CFG-04** dmtools.env search order: project root FIRST, then CWD —
      dart property_reader.dart:185 / java PropertyReader.java:122 — S
- [ ] **P6-CFG-05** project-root marker is settings.gradle(.kts), not
      pubspec.yaml — dart property_reader.dart:30,204 / java
      PropertyReader.java:82-105 — S
- [ ] **P6-CFG-06** unreadable dmtools.env: warn + continue (no crash) —
      dart env_file_parser.dart:15 / java PropertyReader.java:125 — S
- [ ] **P6-CFG-07** port `DMTOOLS_CLI_LOG_FILTER` (getCliLogFilter + CLI
      transcript tee) — dart config absent / java
      PropertyReader.java:475 — S
- [ ] **P6-CFG-08** port `getAllProperties()` — dart absent / java
      PropertyReader.java:1025 — S
- [ ] **P6-CFG-09** property/env caching must be process-static (load once),
      not per-instance — dart property_reader.dart:73 / java
      PropertyReader.java:73 — S
- [ ] **P6-CFG-10** list splitting drops trailing empty segments
      (Java `String.split(",")` semantics) — dart
      property_reader_getters.dart:182 / java PropertyReader.java:365 — S
- [ ] **P6-CFG-11** remove invented `getAnthropicApiKey()` (no Java surface)
      — dart property_reader_ai_getters.dart:148 — S
- [ ] **P6-CFG-12** invalid-number getters log Java's warn lines — dart
      property_reader_getters.dart:175 / java PropertyReader.java:360 — S
- [ ] **P6-CFG-13** `=value` line puts empty key (no isNotEmpty skip) — dart
      env_file_parser.dart:26 / java CommandLineUtils.java:530 — S
