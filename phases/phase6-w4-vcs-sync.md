---
wave: W4
status: open   # open | in-progress | done
blocked-by: [W6]
blocks: []
items: 23
note: W6 error contract (P6-BRG-02) must land first; non-error items may start in parallel.
---

# Phase 6 W4 — GitHub/GitLab sync executors (23 items)

- [ ] **P6-VCS-01** curl `-L` (302 redirect follow) — `github_get_job_logs`
      returns empty today — dart sync_http_client.dart / java
      AbstractRestClient.java:59 — M
- [ ] **P6-VCS-02** `github_get_pr_comments` sorts by `created_at`
      chronologically — dart github_sync_tools.dart:254 / java
      GitHub.java:689 — S
- [ ] **P6-VCS-03** GitHub default headers `Accept:
      application/vnd.github.v3+json`, no api-version header — dart
      github_sync_tools.dart:98 / java GitHub.java:121 — S
- [ ] **P6-VCS-04** GitLab headers `Authorization: Bearer` + `Accept:
      application/json` — dart gitlab_sync_tools.dart:104 / java
      GitLab.java:50 — S
- [ ] **P6-VCS-05** `github_trigger_workflow` invalid inputs JSON throws;
      Java error text — dart github_sync_tools.dart:499 / java
      GitHub.java:407 — S
- [ ] **P6-VCS-06** non-2xx throws (no silent truncation to `[]` on
      pagination) — dart sync_request_helpers.dart:42 / java
      AbstractRestClient.java:381 — M
- [ ] **P6-VCS-07** `gitlab_upload_release_asset`: isFile check; package
      upload failure aborts the link — dart gitlab_release_assets.dart:45 /
      java GitLab.java:1174 — M
- [ ] **P6-VCS-08** `gitlab_download_release_asset`: non-2xx throws;
      returns ABSOLUTE path — dart gitlab_release_assets.dart:98 / java
      GitLab.java:1410 — S
- [ ] **P6-VCS-09** diff-stats return shape = Java's IDiffStats
      serialization — dart github_sync_tools.dart:229 / java
      GitHub.java:1693 — M
- [ ] **P6-VCS-10** `_findReleaseByTagOrName`: empty releases → null (create
      path) — dart github_sync_tools.dart:569 / java GitHub.java:565 — S
- [ ] **P6-VCS-11** inline-comment error text + validation order — dart
      github_sync_tools.dart:360 / java GitHub.java:1014 — S
- [ ] **P6-VCS-12** release upload host hardcoded uploads.github.com;
      file-probed content type; MediaType validation — dart
      github_release_assets.dart:44 / java GitHub.java:606 — S
- [ ] **P6-VCS-13** workflow-run logs: api.github.com host, https-only SSRF
      guard, Java redirect headers/timeouts/error text — dart
      github_workflow_logs.dart:29 / java GitHubWorkflowUtils.java:216 — S
- [ ] **P6-VCS-14** `github_remove_pr_label`: raw label in path (no
      encoding) — dart github_sync_tools.dart:169 / java
      GitHub.java:1489 — S
- [ ] **P6-VCS-15** void tools return null to the agent (add/remove label,
      delete asset) — dart github_sync_tools.dart:162 / java
      GitHub.java:1456 — S
- [ ] **P6-VCS-16** required-param validation
      (`Required parameter 'X' is missing`) on every sync tool — dart
      gitlab_sync_tools.dart:256 / java MCPToolProcessor.java:358 — M
- [ ] **P6-VCS-17** `gitlab_get_mr_diff_text`: `""` on failure +
      isMRChangesError latch — dart gitlab_sync_tools.dart:203 / java
      GitLab.java:446 — S
- [ ] **P6-VCS-18** `gitlab_trigger_pipeline` invalid variables JSON error
      text — dart gitlab_sync_tools.dart:400 / java GitLab.java:994 — S
- [ ] **P6-VCS-19** `gitlab_get_job_logs`: raw jobId string (no int
      coercion) — dart gitlab_sync_tools.dart:357 / java
      GitLab.java:1128 — S
- [ ] **P6-VCS-20** no value trimming (merge_method, ref, body… sent raw) —
      dart github_sync_tools.dart:179 / java GitHub.java:407 — S
- [ ] **P6-VCS-21** remove extra surface (github_create_comment,
      gitlab_create_mr_note alias, legacy arg fallbacks, filePath alias) —
      dart github_sync_tools.dart:142 / java — S
- [ ] **P6-VCS-22** port remaining Java VCS tools into sync surface
      (github_test, list_prs_filtered, commits_from_branches,
      repository_dispatch, release-asset CRUD, pr comments/activities CRUD,
      check runs/commit statuses, workflow run; gitlab_test, approve_mr,
      mr_activities, project/pipeline/cancel jobs, release-asset list) —
      dart absent / java GitHub.java+GitLab.java — L
- [ ] **P6-VCS-23** `gitlab_list_mrs`: empty state passes through; only
      exact open/closed normalized — dart gitlab_sync_tools.dart:152 / java
      GitLab.java:664 — S
