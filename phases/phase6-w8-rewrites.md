---
wave: W8
status: open   # open | in-progress | done
blocked-by: []
blocks: [W9]
items: 9
note: Independent; registry refresh (W9) waits for it.
---

# Phase 6 W8 — Wholesale integration rewrites: Figma / Teams / SharePoint /
Confluence (9 items)

- [ ] **P6-RW-01** figma toolset = Java's 22 URL-driven tools (oauth2,
      me, screen_source, downloads, structure, icons, image_fills, render,
      svg, node details/text/children, layers(+batch), team projects,
      project files, file comments) — dart figma_*.dart / java
      FigmaClient.java:126 — L
- [ ] **P6-RW-02** figma auth: `X-Figma-Token` for PATs; OAuth2 flow with
      token manager — dart figma_http_client.dart:22 / java
      BasicFigmaClient.java:53 — M
- [ ] **P6-RW-03** teams toolset = Java's 28 (send by NAME, chats(+raw/
      recent), messages(+raw/since/by-id), myself, downloads, hosted
      contents, transcripts, sharepoint search/extract, joined
      teams/channels, find_* raw) with Java pagination/limits/filters — dart
      teams_*.dart / java TeamsClient.java:97 — L
- [ ] **P6-RW-04** teams OAuth: browser/device-code/refresh flows, token
      cache, teams_auth_* tools — dart teams_oauth.dart:22 / java
      TeamsAuthTools.java — L
- [ ] **P6-RW-05** sharepoint = Java's 2 sharing-URL tools
      (get_drive_item, download_file; `u!` base64url share id) — dart
      sharepoint_*.dart / java SharePointClient.java:89 — L
- [ ] **P6-RW-06** confluence toolset = Java's 20 (contents_by_urls,
      update_with_history, upload attachments, children_by_name,
      download_pages, find(_or_create), content_by_title(+space),
      user profiles, …) — dart confluence_tools.dart:40 / java
      Confluence.java:81 — L
- [ ] **P6-RW-07** confluence read tools format=md conversion — dart
      confluence_client.dart / java Confluence.java:82 — M
- [ ] **P6-RW-08** confluence_search = GraphQL-first + CQL fallback
      composition — dart confluence_client.dart:164 / java
      Confluence.java:193 — M
- [ ] **P6-RW-09** confluence_download_attachment via `_links.download` —
      dart confluence_client.dart:229 / java Confluence.java:717 — M
