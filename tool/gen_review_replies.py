#!/usr/bin/env python3
"""Generates outputs/review_replies/*.md + outputs/review_replies.json for the
open gh-191 PR review threads (one reply per open threadable thread)."""
import json
import os

CLUSTERS = {
    'lib/src/integrations/jira/markdown_to_jira_markup.dart': """Fixed on this head:

- **Coverage** — `test/js/sync_tools/markdown_to_jira_markup_test.dart` gains the top-level inline-run group: sibling `<b>`/`<i>` chains (2+ items, `_boldItalicChain`), leading-whitespace chain members (`_trimLeadingSpaces`), the `<strong>+<ul>` heading block (`_consecutiveInlineBlock`/`_strongUlBlock`), and the unclosed-`<code>` DOM paths that reach `_codeLanguage`'s three branches (default/empty/explicit class) plus `<pre>` with a class language.
- **Complexity** — the entry point's dispatch was extracted into `_classifyInput` (mixed/html/markdown routing), dropping `markdownToJiraMarkup` from CC 9 to CC 4; CRAP ≥ CC so this could not pass on coverage alone.

Verified with a full-suite coverage run + `crap4dart analyze` (pinned 0.9.5): max CRAP in this file is now ≤ 8.""",

    'lib/src/js/sync_http_client.dart': """Fixed on this head:

- `_parseRawResponse` is now covered by the raw-byte stdout group in `test/js/sync_http_test.dart`: valid body+status bytes, non-ASCII body, missing `\\n` separator (curl exit path), status `000` with stderr, status `000` with empty stderr (body-as-diagnostic fallback), and non-UTF-8 bytes preserved via `bodyBytes`.

Verified with a full-suite coverage run + `crap4dart analyze` (pinned 0.9.5): `_parseRawResponse` no longer appears over threshold.""",

    'lib/src/js/sync_tools/confluence_sync_page_ops.dart': """Fixed on this head:

- **Complexity** — `uploadWithPolicy` (CC 10, CRAP ≥ CC regardless of coverage) was split: the policy branch stays in the main method, the upload tail moved to `_uploadForPolicy` (suffix choice + POST + decode) and `_uploadedAttachment` (wrapper `results[0]` vs bare object).
- **Coverage** — new `ConfluenceSyncTools upload policy` group in `test/js/sync_tools/confluence_sync_tools_test.dart` drives `confluence_upload_attachment` against the echo server: skip-existing, overwrite (`updated`), create, and the failed-POST contract via a new `dt-fail` 500 fixture in `test/js/test_echo_server.py`.
- `_downloadAttachmentsOf` (CC 9) was decomposed into `_attachmentDownloadPath` + `_downloadOneAttachment` in `confluence_sync_downloader.dart`.

Verified with a full-suite coverage run + `crap4dart analyze` (pinned 0.9.5).""",

    'lib/src/js/sync_tools/jira_sync_field_update.dart': """Fixed on this head:

- **Complexity** — `_updateFieldsByName` (CC 10) was split along the reviewer's suggested seams: `_resolveActiveFieldIds` (active filter + best-match fallback), `_singleFieldUpdateResult` (Java's success/failure sentence), and `_multiFieldUpdateResult` (the ✅/❌ loop plus the `Updated N of M fields …` tail). Output bytes are unchanged — the existing Jira field-update suite passes verbatim.

Verified with a full-suite coverage run + `crap4dart analyze` (pinned 0.9.5).""",

    'lib/src/integrations/jira/jira_utils.dart': """Fixed on this head:

- `jiraResponseErrorDetail` now has a dedicated test group (`test/integrations/jira/jira_utils_test.dart`) covering every missing branch: non-JSON body → null, non-object JSON → null, error-less object → null, `errorMessages` joined, plain `errors` keys, the `customfield_*` → `Field …` prefix, `errorMessages`+`errors` combined, and non-string message entries ignored.

Verified with a full-suite coverage run + `crap4dart analyze` (pinned 0.9.5): the function is at 100% line coverage, CRAP = CC ≤ 8.""",

    'lib/src/integrations/confluence/confluence_client.dart': """Fixed on this head:

- **Bug** — `_decodeDioBody` threw `FormatException` on a non-JSON string body (HTML 502 pages, text/plain); it now degrades to `null` like Java's catch-all, so `uploadAttachment` reports the failure instead of crashing. Regression test: `decode: a non-JSON string body yields a null attachment`.
- **Coverage** — the String-body decode branches are covered (`test/integrations/confluence/confluence_java_name_tools_test.dart`): JSON string → attachment, non-object JSON string → null, non-JSON string → null, plus the Map passthrough from the existing upload tests. The test support gained a custom content-type/status adapter to reach these paths.
- **Complexity** — `contentByUrl` (CC 9) was split: the redirect-hop walk moved into `_resolveRef`, leaving the id/display dispatch at CC ≤ 8. A `/display/{space}/{title}` routing test pins the dispatch (title + spaceKey query params asserted).

Verified with a full-suite coverage run + `crap4dart analyze` (pinned 0.9.5).""",
}

GENERAL_BODY = """The CRAP gate is green on this head: every offender from rounds 11–12 is either covered by new tests or had a branch extracted (CC ≥ 9 methods cannot pass at any coverage), and a real non-JSON-string-body crash in `_decodeDioBody` was fixed with a regression test. Verified locally with the CI combination: full-suite `dart test --coverage=coverage` → `format_coverage` → `crap4dart check --all` + `crap4dart analyze` — all green, `dart format --set-exit-if-changed .` clean, `dart analyze` clean."""


def main() -> None:
    raw = json.load(open('input/gh-191/pr_discussions_raw.json'))
    os.makedirs('outputs/review_replies', exist_ok=True)
    open_threads = [
        t for t in raw['threads']
        if not t.get('resolved', True) and t.get('threadId')
    ]
    replies = []
    for i, t in enumerate(sorted(open_threads, key=lambda x: x['index'])):
        path = t.get('path') or ''
        body = CLUSTERS.get(path, GENERAL_BODY)
        rel = f'outputs/review_replies/thread_{i + 1}.md'
        with open(rel, 'w') as f:
            f.write(body + '\n')
        replies.append({
            'inReplyToId': t['rootCommentId'],
            'threadId': t['threadId'],
            'reply': rel,
        })
    with open('outputs/review_replies.json', 'w') as f:
        json.dump({'replies': replies}, f, indent=2)
        f.write('\n')
    print(f'wrote {len(replies)} replies')


if __name__ == '__main__':
    main()
