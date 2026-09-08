---
id: "n_0002_edac"
type: "note"
title: "Research (2026-09-07) for issue-triggered agents: Java dm.ai has NO GitHub-issue tooling and no issue-driven automation — its GitHub surface (GitHub.java, 33 @MCPTools) is PR/SCM-only, and the trigger hub is Jira (sm.yml polls JQL/labels every 10 min; merge-trigger runs after CI). Dart registry already has 3 Dart-side extras: github_get_issue/github_create_issue/github_close_issue. dmtools-agents has an SCM abstraction in agents/js/common/scm.js (github|gitlab|ado providers over snake_case tools — runs on the Dart bridge) plus githubHelpers.js; Teammate JS actions are jiraHelpers-bound (validateTicketKeyFormat rejects non-Jira keys). CliAgentParams.fromJson already reads every shared Teammate key (cliCommands, cliPrompts(+ByTracker), pre/preCli/postJSAction, timer*, envVariables, metadata, outputType, customParams); Teammate-only keys (inputJql, ticketContextDepth, alwaysPostComments, attachResponseAsFile, skipAIProcessing) are silently ignored — so Teammate→CliAgent config conversion is: swap name to CliAgent, drop inputJql, feed the ticket via input/ticketData from outside. Planned issue-trigger design: GitHub Actions `on: issues: [assigned]` wrapper → reusable ai-teammate.yml → CliAgent config + issue→params.ticket adapter + issue-aware JS actions using scm.js/githubHelpers instead of jiraHelpers."
author: "agent"
date: "2026-09-07T14:34:39.147213Z"
area: "project"
topics: []
source: "agent"
accessCount: 0
importance: 0.5
tags: ["#note", "#source_agent", "architecture", "github", "issues", "teammate", "cliagent", "design"]
---


# Note: n_0002_edac

Research (2026-09-07) for issue-triggered agents: Java dm.ai has NO GitHub-issue tooling and no issue-driven automation — its GitHub surface (GitHub.java, 33 @MCPTools) is PR/SCM-only, and the trigger hub is Jira (sm.yml polls JQL/labels every 10 min; merge-trigger runs after CI). Dart registry already has 3 Dart-side extras: github_get_issue/github_create_issue/github_close_issue. dmtools-agents has an SCM abstraction in agents/js/common/scm.js (github|gitlab|ado providers over snake_case tools — runs on the Dart bridge) plus githubHelpers.js; Teammate JS actions are jiraHelpers-bound (validateTicketKeyFormat rejects non-Jira keys). CliAgentParams.fromJson already reads every shared Teammate key (cliCommands, cliPrompts(+ByTracker), pre/preCli/postJSAction, timer*, envVariables, metadata, outputType, customParams); Teammate-only keys (inputJql, ticketContextDepth, alwaysPostComments, attachResponseAsFile, skipAIProcessing) are silently ignored — so Teammate→CliAgent config conversion is: swap name to CliAgent, drop inputJql, feed the ticket via input/ticketData from outside. Planned issue-trigger design: GitHub Actions `on: issues: [assigned]` wrapper → reusable ai-teammate.yml → CliAgent config + issue→params.ticket adapter + issue-aware JS actions using scm.js/githubHelpers instead of jiraHelpers.

**By:** [[agent]]
**Date:** 2026-09-07T14:34:39.147213Z
**Area:** [[project|project]]
