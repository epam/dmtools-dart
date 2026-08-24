---
wave: W7
status: open   # open | in-progress | done
blocked-by: []
blocks: [W9]
items: 29
note: Independent of the sync layer; registry refresh (W9) waits for it.
---

# Phase 6 W7 — Integrations layer: Jira engine, Xray, TestRail (29 items)

- [ ] **P6-INT-01** integrations-layer search: extended default fields +
      up-front isCloudJira branching (Server search works without the
      cursor-404 dance) — dart jira_client.dart:38 / java
      JiraClient.java:455-594 — M
- [ ] **P6-INT-02** GET file cache (md5 files, DMTOOLS_CACHE_ENABLED,
      JIRA_CLEAR_CACHE) + RetryPolicy + JIRA_WAIT_BEFORE_PERFORM + non-2xx
      POST/PUT body return — dart base_http_client.dart:36 / java
      JiraClient.java:2720 — L
- [ ] **P6-INT-03** `jira_update_field` full engine (resolution, coercion,
      multi-PUT, summary text) — dart jira_client.dart:260 / java
      JiraClient.java:2379 — L
- [ ] **P6-INT-04** `jira_update_field_as_adf`: ADF.normalize + update-verb
      body — dart jira_client.dart:448 / java
      JiraClient.java:2192 — M
- [ ] **P6-INT-05** JIRA_TRANSFORM_CUSTOM_FIELDS_TO_NAMES (default ON):
      customfield_XXX → names with ` (id)` dedup — dart jira_client.dart /
      java JiraClient.java:1658 — L
- [ ] **P6-INT-06** `jira_get_subtasks`: type resolution + Cloud JQL /
      Server dedicated endpoint + memoized fallback — dart
      jira_client.dart:356 / java JiraClient.java:866 — M
- [ ] **P6-INT-07** `jira_get_issue_types`/`jira_get_fields`: createmeta +
      Cloud/Server parse branching; getFields via global `field` — dart
      jira_client.dart:307 / java JiraClient.java:3517 — M
- [ ] **P6-INT-08** `jira_post_comment_if_not_exists`: case-insensitive
      compare + markdown conversion — dart jira_client.dart:434 / java
      JiraClient.java:956 — S
- [ ] **P6-INT-09** integrations label ops case-insensitive + set-verb —
      dart jira_client.dart:169 / java JiraClient.java:323 — S
- [ ] **P6-INT-10** transitions `?expand=transitions.fields`; null on no
      match — dart jira_client.dart:211 / java
      JiraClient.java:3068 — S
- [ ] **P6-INT-11** `jira_execute_request`: any URL, raw string return —
      dart jira_client.dart:612 / java JiraClient.java:2648 — M
- [ ] **P6-INT-12** attachments: skip same-name, contentType param, Success
      envelope; download caches to md5 file, returns File — dart
      jira_attachment_client.dart:10 / java JiraClient.java:2660 — M
- [ ] **P6-INT-13** scheme tools: `/rest/api/3/issuetypescheme/project?
      projectId={id}` + workflowscheme equivalents + classic/next-gen
      fallbacks; assign PUT body `{projectIds:[id]}` — dart
      jira_scheme_client.dart:6 / java JiraClient.java:3895 — M
- [ ] **P6-INT-14** project lifecycle: delete with enableUndo + confirm
      string; copy_structure copies types+workflow; clone next-gen mirror
      with template key — dart jira_project_client.dart:11 / java
      JiraClient.java:4237 — L
- [ ] **P6-INT-15** workflow tools: v3 bulk status creation + workflow
      update with transitions/migrations — dart jira_workflow_client.dart:6 /
      java JiraClient.java:4500 — L
- [ ] **P6-INT-16** create_project_issue_type exists-skip + PROJECT scope;
      board-config composite shape — dart jira_issue_type_client.dart:6 /
      java JiraClient.java:4027 — M
- [ ] **P6-INT-17** `jira_search_with_pagination`: Java params only (no
      maxResults=100, no *navigable default) — dart jira_search_client.dart:32
      / java JiraClient.java:596 — S
- [ ] **P6-INT-18** remove invented Jira tools (watchers, resolutions,
      priorities, security levels, worklogs, export_data, board_issues,
      sprints, get_attachments) — dart jira_*_client.dart / java catalog — M
- [ ] **P6-INT-19** `jira_get_all_fields_with_name` shape
      ({fieldName, fieldIds, count, warning}) — dart jira_client.dart:475 /
      java JiraClient.java:2571 — S
- [ ] **P6-INT-20** xray 503/'backup' retry (3 attempts, 1s/2s) — dart
      xray_client.dart:404 / java XrayRestClient.java:272 — S
- [ ] **P6-INT-21** xray XRAY_PARALLEL_* enrichment (batch/threads/delay,
      sorted keys, 429 handling) — dart xray_client.dart:459 / java
      XrayClient.java:1040 — M
- [ ] **P6-INT-22** xray token 1h expiry + refresh buffer; /api/v2 base
      normalization — dart xray_client.dart:109 / java
      XrayRestClient.java:150 — S
- [ ] **P6-INT-23** remove invented xray REST tools; get_test_steps via
      GraphQL getTests — dart xray_client.dart:149 / java
      XrayClient.java — M
- [ ] **P6-INT-24** xray GraphQL literal escaping + setTestSteps fallback
      chain — dart xray_client.dart:621 / java XrayClient.java:365 — S
- [ ] **P6-INT-25** testrail_test = get_projects count — dart
      testrail_client.dart:31 / java TestRailClient.java:130 — S
- [ ] **P6-INT-26** testrail param names case_id etc.; update_case field
      contract — dart testrail_client.dart:55 / java
      TestRailClient.java:294 — M
- [ ] **P6-INT-27** testrail read-side format=md conversion
      (TESTRAIL_DEFAULT_FORMAT) — dart testrail_client.dart / java
      TestRailClient.java:294 — M
- [ ] **P6-INT-28** testrail toolset to Java's (missing suites/search/
      by-refs/labels/link-to-requirement; remove invented) — dart
      testrail_tools.dart:506 / java TestRailClient.java — L
- [ ] **P6-INT-29** testrail_get_case_types global (no projectId) — dart
      testrail_tools.dart:435 / java TestRailClient.java:1082 — S
