---
wave: W5
status: open   # open | in-progress | done
blocked-by: [W6]
blocks: []
items: 35
note: W6 error contract (P6-BRG-02) must land first; non-error items may start in parallel.
---

# Phase 6 W5 — ADO / Confluence / Bitrise / Jenkins / AI sync (35 items)

- [ ] **P6-CDS-01** `ado_get_work_item` honors fields (friendly-name
      resolution) + `$expand=relations` default — dart
      ado_sync_tools.dart:120 / java AzureDevOpsClient.java:133 — M
- [ ] **P6-CDS-02** `ado_get_work_item` returns null on errorCode body —
      dart ado_sync_tools.dart:123 / java
      AzureDevOpsClient.java:125 — S
- [ ] **P6-CDS-03** `ado_list_work_items` resolves field names
      (System.Title etc.) in batch fetch — dart ado_sync_tools.dart:152 /
      java AzureDevOpsClient.java:306 — S
- [ ] **P6-CDS-04** confluence sync base appends `/rest/api` only (no
      doubled `/wiki`) — dart confluence_sync_tools.dart:60 / java
      Confluence.java:77 — M
- [ ] **P6-CDS-05** `X-Atlassian-Token: nocheck` on all confluence sync
      requests — dart confluence_sync_tools.dart:61 / java
      AtlassianRestClient.java:24 — S
- [ ] **P6-CDS-06** confluence search = Java
      `confluence_search_content_by_text` (CQL composition, limit 20,
      expand list, GraphQL-first) — dart confluence_sync_tools.dart:70 /
      java Confluence.java:193 — M
- [ ] **P6-CDS-07** confluence_get_page expand list + format=md — dart
      confluence_sync_tools.dart:81 / java Confluence.java:290 — S
- [ ] **P6-CDS-08** update_page applies `prepareBodyForConfluence`
      (`<br>`→\n, link conversion) — dart confluence_sync_tools.dart:107 /
      java Confluence.java:500 — M
- [ ] **P6-CDS-09** update version payload includes `message` — dart
      confluence_sync_tools.dart:215 / java Confluence.java:516 — S
- [ ] **P6-CDS-10** format=md: YAML-macro extraction + export_view
      fallback — dart confluence_sync_tools.dart:436 / java
      Confluence.java:1049 — M
- [ ] **P6-CDS-11** sync-engine page ops: children expand, export_view —
      dart confluence_sync_tools.dart:274 / java Confluence.java:699 — S
- [ ] **P6-CDS-12** page payload reads Java param names (title/parentId/
      body/space) — dart confluence_sync_tools.dart:182 / java
      Confluence.java:437 — S
- [ ] **P6-CDS-13** remove `BITRISE_ALLOW_WRITES` guard (Java has none) —
      dart bitrise_sync_tools.dart:78 / java Bitrise.java:184 — M
- [ ] **P6-CDS-14** bitrise sync surface = full Java toolset (22 tools) —
      dart bitrise_sync_tools.dart:32 / java Bitrise.java — M
- [ ] **P6-CDS-15** jenkins apiJobPath raw segments (no percent-encoding) —
      dart jenkins_sync_tools.dart:100 / java Jenkins.java:103 — S
- [ ] **P6-CDS-16** jenkins sync surface = 7 Java tools incl. trigger +
      queue wait — dart jenkins_sync_tools.dart:26 / java
      Jenkins.java:115 — M
- [ ] **P6-CDS-17** gemini error contract: never throws, returns
      "Error: ..." strings — dart ai_sync_tools.dart:215 / java
      geminiChatViaJs.js:54 — M
- [ ] **P6-CDS-18** gemini URL host hardcoded (env unused) — dart
      ai_sync_tools.dart:221 / java geminiChatViaJs.js:60 — S
- [ ] **P6-CDS-19** openai 200-with-error-body → raw body as content — dart
      ai_sync_tools.dart:244 / java OpenAIClient.java:271 — S
- [ ] **P6-CDS-20** anthropic content as block array — dart
      ai_sync_tools.dart:268 / java AnthropicAIClient.java:226 — S
- [ ] **P6-CDS-21** anthropic auth via ANTHROPIC_CUSTOM_HEADER_NAMES/VALUES
      (no x-api-key invention) — dart ai_sync_tools.dart:275 / java
      AnthropicAIClient.java:100 — M
- [ ] **P6-CDS-22** anthropic response parse: OpenAI choices first, then
      native — dart ai_sync_tools.dart:281 / java
      AnthropicAIClient.java:256 — S
- [ ] **P6-CDS-23** ollama endpoint `{base}/v1/chat/completions` — dart
      ai_sync_tools.dart:291 / java OllamaAIClient.java:276 — M
- [ ] **P6-CDS-24** ollama body: temperature 0.1, options.num_ctx
      (OLLAMA_NUM_CTX), max_tokens (OLLAMA_NUM_PREDICT) — dart
      ai_sync_tools.dart:293 / java OllamaAIClient.java:280 — M
- [ ] **P6-CDS-25** ollama optional Bearer + custom headers — dart
      ai_sync_tools.dart:292 / java OllamaAIClient.java:145 — S
- [ ] **P6-CDS-26** dial endpoint
      `{base}/openai/deployments/{model}/chat/completions` + api-version —
      dart ai_sync_tools.dart:316 / java DialAIClient.java:214 — M
- [ ] **P6-CDS-27** dial auth header `api-key:` — dart ai_sync_tools.dart:317
      / java DialAIClient.java:110 — S
- [ ] **P6-CDS-28** dial body: no model field; gpt-5 token rules;
      temperature/max_tokens 0.1/65536 — dart ai_sync_tools.dart:318 / java
      DialAIClient.java:239 — M
- [ ] **P6-CDS-29** bedrock IAM SigV4 (env keys + default chain) — dart
      ai_sync_tools.dart:331 / java BedrockAIClient.java:102 — M
- [ ] **P6-CDS-30** AI chat retry (RetryUtil) + POST caching — dart
      ai_sync_tools.dart / java OpenAIClient.java:98 — M
- [ ] **P6-CDS-31** systemic: non-2xx throws; `{"error":...}` never a
      success value — dart sync_request_helpers.dart:42 / java
      AbstractRestClient.java — M
- [ ] **P6-CDS-32** ado WIQL empty workItems → `[]` — dart
      ado_sync_tools.dart:139 / java AzureDevOpsClient.java:267 — S
- [ ] **P6-CDS-33** ado batch failure throws (no silent partial) — dart
      ado_sync_tools.dart:144 / java AzureDevOpsClient.java — S
- [ ] **P6-CDS-34** ado nested variables object JSON-serialized
      (org.json form) — dart ado_sync_tools.dart:425 / java
      AzureDevOpsClient.java:1856 — S
- [ ] **P6-CDS-35** ado invalid variables JSON → Java exception text — dart
      ado_sync_tools.dart:398 / java AzureDevOpsClient.java:1853 — S
