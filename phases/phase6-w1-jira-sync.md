---
wave: W1
status: in-progress   # open | in-progress | done
blocked-by: [W6]
blocks: []
items: 18
note: W6 error contract (P6-BRG-02) must land first; non-error items may start in parallel.
---

# Phase 6 W1 — Jira sync executor (18 items)

- [x] **P6-JSY-01** 2xx empty/non-JSON body flagged as `{"error":...}` while
      Java returns raw body (`""` for 204; deleteTicket `"Success"`) — dart
      jira_sync_tools.dart:646 / java JiraClient.java:2852-3010 — S
- [ ] **P6-JSY-02** fields-omitted default must be Java
      `getExtendedQueryFields()` (description, issuelinks + 14 defaults +
      JIRA_EXTRA_FIELDS), not `*navigable` — dart jira_sync_tools.dart:666 /
      java BasicJiraClient.java:41-60 — M
- [ ] **P6-JSY-03** `jira_move_to_status` param is `statusName` in Java (Dart
      reads `status`; no-match returns null not error) — dart
      jira_sync_tools.dart:212 / java JiraClient.java:3083 — S
- [ ] **P6-JSY-04** `jira_update_field` must PUT `{update:{field:[{set:v}]}}`
      with `""`→clearField, coerceFieldValue (bool/int/long/double/JSON),
      field-name→ALL customfield ids, per-field PUT + ✅/❌ summary — dart
      jira_sync_tools.dart:212-225 / java JiraClient.java:2379-2481 — L
- [ ] **P6-JSY-05** `jira_update_description` body must be
      `{update:{description:[{set}]}}` — dart jira_sync_tools.dart:238 /
      java JiraClient.java:1435 — S
- [ ] **P6-JSY-06** label add/remove compare case-insensitively
      (equalsIgnoreCase) — dart jira_sync_tools.dart:196,207 / java
      JiraClient.java:342,379 — S
- [ ] **P6-JSY-07** `jira_get_comments` must return the comments ARRAY (not
      envelope) — dart jira_sync_tools.dart:228 / java
      JiraClient.java:987 — S
- [ ] **P6-JSY-08** transitions URL needs `?expand=transitions.fields`;
      return List not envelope — dart jira_sync_tools.dart:244 / java
      JiraClient.java:3068 — S
- [ ] **P6-JSY-09** `jira_post_comment` must convert markdown→Jira markup
      (TextType MARKDOWN) — dart jira_sync_tools.dart:83 / java
      JiraClient.java:1033 + MarkdownToJiraConverter — M
- [ ] **P6-JSY-10** cloud search must check errorMessages (throw) and send
      maxResults when JIRA_MAX_SEARCH_RESULTS set — dart
      jira_sync_tools.dart:108 / java JiraClient.java:494,674 — M
- [ ] **P6-JSY-11** server search: empty list on errorMessages; expand-only
      fields (changelog…) split into `&expand=` — dart
      jira_sync_tools.dart:128 / java JiraClient.java:550-594,1855 — S
- [ ] **P6-JSY-12** search jql param aliases `searchQueryJQL`, `query` —
      dart jira_sync_tools.dart:100 / java JiraClient.java:463 — S
- [ ] **P6-JSY-13** `jira_create_ticket_with_parent` must fetch the parent
      ticket and embed the full object (fail upfront on missing parent) —
      dart jira_sync_tools.dart:297 / java JiraClient.java:1140 — M
- [ ] **P6-JSY-14** create always sets description (even `""`) — dart
      jira_sync_tools.dart:584 / java JiraClient.java:1185 — S
- [ ] **P6-JSY-15** create errors must surface Java's
      `checkJiraResponseForErrors` text — dart jira_sync_tools.dart:575 /
      java JiraClient.java:1199 — S
- [ ] **P6-JSY-16** attach status string is `"Success"` (capital S) — dart
      jira_sync_tools.dart:387 / java JiraClient.java:62 — S
- [ ] **P6-JSY-17** `jira_execute_request` missing from sync handlers (runs
      any path/URL with auth, returns raw string) — dart
      sync_tool_dispatcher.dart:80 / java JiraClient.java:2649 — M
- [ ] **P6-JSY-18** retry policy: 429/503 backoff (RetryPolicy,
      Cloud-tuned), `JIRA_WAIT_BEFORE_PERFORM` + `SLEEP_TIME_REQUEST`, 60s
      connect — dart sync_http_client.dart:38 / java
      JiraClient.java:168-193,2742 — M
