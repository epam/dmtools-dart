---
wave: W9
status: open   # open | in-progress | done
blocked-by: [W7, W8]
blocks: []
items: 51
note: Registry reflects final toolsets; regenerate the gaps fixture last (P6-REG-51).
---

# Phase 6 W9 — Registry metadata (51 items; REG-46..49 are bulk text syncs)

- [ ] **P6-REG-01** ToolParam.example field + 301 Java example backfills —
      dart tool_param.dart:22 / java MCPParam.java:42 — L
- [ ] **P6-REG-02** remove the 227 invented Dart tools (github 35, ado 26,
      confluence 25, gitlab 23, jira 17, file 16, figma 13, testrail 12,
      sharepoint 12, jenkins 10, teams 9, ai 8, kb 8, bitrise 7, mermaid 4,
      cli 2) — owner mandate: no additions beyond the Java catalog — dart
      default_tool_registry.dart:32 / java generated registry — L
- [ ] **P6-REG-03** restore Java alias sets (tracker_*, source_code_*,
      gitlab MR aliases, xray_test, ado_create/get_work_item) — dart
      tool_registry.dart:19 / java MCPToolProcessor.java:186 — M
- [ ] **P6-REG-04** remove Dart-only aliases (jira_assign, jira_assign_to,
      jira_create_ticket) — dart jira_ticket_tools.dart:122 — S
- [ ] **P6-REG-05** cli_execute_command params [command, workingDirectory] —
      dart cli_tools.dart:34 / java CliCommandExecutor.java:81 — M
- [ ] **P6-REG-06** teams_send_message params [chatName, content,
      contentType] — dart teams_tools.dart:40 / java
      TeamsClient.java:907 — M
- [ ] **P6-REG-07** confluence_create_page params [title, parentId, body,
      space] — dart confluence_tools.dart:87 / java
      Confluence.java:431 — M
- [ ] **P6-REG-08** confluence_download_attachment params [attachment,
      targetDir] — dart confluence_tools.dart:286 / java
      Confluence.java:716 — M
- [ ] **P6-REG-09** testrail_update_case params [case_id, title,
      priority_id, refs] — dart testrail_tools.dart:94 / java
      TestRailClient.java:914 — M
- [ ] **P6-REG-10** testrail_get_case params [case_id, format] — dart
      testrail_tools.dart:42 / java TestRailClient.java:293 — S
- [ ] **P6-REG-11** testrail_delete_case params [case_id] — dart
      testrail_tools.dart:114 / java TestRailClient.java:947 — S
- [ ] **P6-REG-12** testrail_get_case_types no params — dart
      testrail_tools.dart:435 / java TestRailClient.java:1082 — S
- [ ] **P6-REG-13** gitlab MR tools params [workspace, repository,
      pullRequestId(, state/mergeCommitMessage)] — dart
      gitlab_project_tools.dart:17 / java GitLab.java:641 — M
- [ ] **P6-REG-14** gitlab_trigger_pipeline params [workspace, repository,
      ref, variablesJson] — dart gitlab_project_tools.dart:291 / java
      GitLab.java:983 — M
- [ ] **P6-REG-15** gitlab_approve_mr params [workspace, repository,
      pullRequestId] — dart gitlab_project_tools.dart:86 / java
      GitLab.java:842 — S
- [ ] **P6-REG-16** ado_create_work_item params [project, workItemType,
      title, description, fieldsJson] — dart ado_tools.dart:57 / java
      AzureDevOpsClient.java:715 — M
- [ ] **P6-REG-17** ado_get_pr [repository, pullRequestId]; ado_list_prs
      [repository, status] — dart ado_pr_tools.dart:26 / java
      AzureDevOpsClient.java:1266 — S
- [ ] **P6-REG-18** ado_get_work_item [id, fields] — dart ado_tools.dart:50
      / java AzureDevOpsClient.java:109 — S
- [ ] **P6-REG-19** ado PR ids/thread ids/line numbers typed string (9
      tools) + deleteSourceBranch string — dart ado_pr_tools.dart:317 / java
      AzureDevOpsClient.java:1302 — S
- [ ] **P6-REG-20** github_add_inline_comment line/startLine string — dart
      github_agent_tools.dart:169 / java GitHub.java:988 — S
- [ ] **P6-REG-21** gitlab line/jobId/limit string; branch booleans string —
      dart gitlab_tools.dart:226 / java GitLab.java:780 — S
- [ ] **P6-REG-22** jira fix-version params fixVersion (not version) — dart
      jira_fix_version_tools.dart:7 / java JiraClient.java:3182 — S
- [ ] **P6-REG-23** jira scheme assign param ORDER (schemeId, projectId);
      get scheme params projectKey — dart jira_scheme_tools.dart:13 / java
      JiraClient.java:3988 — S
- [ ] **P6-REG-24** jira attach/download param names (ticketKey, name,
      contentType, filePath; href) — dart jira_attachment_tools.dart:7 /
      java JiraClient.java:2698 — S
- [ ] **P6-REG-25** jira project tool param names (sourceProjectKey,
      newProjectKey, projectKey); drop invented lead — dart
      jira_project_tools.dart:29 / java JiraClient.java:4293 — S
- [ ] **P6-REG-26** jira projectKey→project renames (issue type, agile) —
      dart jira_issue_type_tools.dart:7 / java
      JiraClient.java:4027 — S
- [ ] **P6-REG-27** jira_create_ticket_basic description required=true —
      dart jira_ticket_tools.dart:173 / java JiraClient.java:1248 — S
- [ ] **P6-REG-28** jira_get_comments 2nd param ticket; statusName renames —
      dart jira_ticket_tools.dart:44 / java JiraClient.java:1026 — S
- [ ] **P6-REG-29** jira_search_by_jql jql aliases [searchQueryJQL, query] —
      dart jira_ticket_tools.dart:34 / java JiraClient.java:455 — S
- [ ] **P6-REG-30** jira_search_by_page/with_pagination required flags +
      startAt type number — dart jira_search_tools.dart:7 / java
      JiraClient.java:596 — S
- [ ] **P6-REG-31** jira project/value params typed object — dart
      jira_ticket_tools.dart:239 / java JiraClient.java:1070 — S
- [ ] **P6-REG-32** jira_update_ticket param jsonParams — dart
      jira_ticket_tools.dart:406 / java JiraClient.java:1541 — S
- [ ] **P6-REG-33** jira workflow tool params (projectKey,
      statusDefinitions; sourceProjectKey/targetProjectKey) — dart
      jira_workflow_tools.dart:7 / java JiraClient.java:4500 — S
- [ ] **P6-REG-34** xray steps/preconditionIssueIds typed object — dart
      xray_tools.dart:292 / java XrayClient.java:1592 — S
- [ ] **P6-REG-35** figma_get_styles param href — dart
      figma_tools.dart:161 / java FigmaClient.java:1082 — S
- [ ] **P6-REG-36** jenkins jobPath name renames; parametersJson param —
      dart jenkins_tools.dart:128 / java Jenkins.java:187 — M
- [ ] **P6-REG-37** ai chat category "" (not 'chat') — dart
      ai_tools.dart:62 / java provider clients — S
- [ ] **P6-REG-38** confluence categories (page_management/attachments) —
      dart confluence_tools.dart:110 / java Confluence.java:459 — S
- [ ] **P6-REG-39** file tool categories "" — dart file_tools.dart:40 /
      java FileTools.java:59 — S
- [ ] **P6-REG-40** jira category corrections (ticket_management,
      workflow, project_management, system) — dart
      jira_ticket_tools.dart:44 / java JiraClient.java:1026 — S
- [ ] **P6-REG-41** jira attachment/user/workflow category corrections —
      dart jira_attachment_tools.dart:24 / java JiraClient.java:3413 — S
- [ ] **P6-REG-42** xray get_test_steps category test_retrieval — dart
      xray_tools.dart:77 / java XrayClient.java:1505 — S
- [ ] **P6-REG-43** gitlab_trigger_pipeline category ci — dart
      gitlab_project_tools.dart:291 / java GitLab.java:983 — S
- [ ] **P6-REG-44** testrail_get_case_types category case_types — dart
      testrail_tools.dart:435 / java TestRailClient.java:1082 — S
- [ ] **P6-REG-45** teams_send_message category communication — dart
      teams_tools.dart:40 / java TeamsClient.java:907 — S
- [ ] **P6-REG-46** jira tool description text sync (20 tools; incl. the
      full jira_post_comment markup guide) — dart jira_*_tools.dart / java
      annotations — M
- [ ] **P6-REG-47** github tool description text sync (8 tools) — dart
      github_*_tools.dart / java annotations — M
- [ ] **P6-REG-48** remaining tool description sync (ado 5, bitrise 6,
      confluence 3, figma 1, gitlab 4, jenkins 2, xray 1, teams 1, testrail
      3, cli whitelist text) — dart *_tools.dart / java annotations — M
- [ ] **P6-REG-49** param description sync (100 params) — dart
      *_tools.dart / java annotations — M
- [ ] **P6-REG-50** port the 10 folded Java tools under their own names
      (*_ai_chat_with_files ×6, *_list_models ×2, vertex_ai_gemini_chat ×2)
      and teams_get_team_channels_raw; drop the folding deviations — dart
      ai_tools.dart / java provider clients — M
- [ ] **P6-REG-51** regenerate `test/fixtures/java_mcp_tool_gaps.txt` from
      the fresh Java clone after W7–W9 land; catalog parity test must show
      zero gaps — dart test/fixtures / java — S
