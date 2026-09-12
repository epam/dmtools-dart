/// PR comment fetching + grouping for the GitHub sync tools.
///
/// Ports the comment side of Java `GitHub.java`:
/// `pullRequestComments` / `pullRequestCommentsFromIssue` pagination and
/// the `GitHubConversation.toJSON()` grouping behind `getPRConversations`.
library;

import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Both comment listings of one PR.
typedef PrCommentPages = ({
  List<Map<String, dynamic>> inline,
  List<Map<String, dynamic>> issue
});

/// Fetches all pages of a comment listing endpoint (100 per page).
///
/// Java `AbstractRestClient.execute` throws a `RestClientException` on
/// any non-OK response — the `pullRequestComments`
/// paging loop breaks only on a null/empty body (the empty last page).
/// Breaking on every non-OK here silently reported 401/403/5xx as
/// "no comments", so a non-OK page surfaces as a [StateError] instead;
/// callers convert it into a sync tool error result.
///
/// Deviation: Java retries retryable codes (429/502/503) before failing;
/// the Dart sync transport ([SyncHttpClient]) does not retry anywhere, so
/// a transient non-OK fails the whole comments fetch immediately —
/// consistent with the rest of the `SyncHttpClient` callers. If Java
/// parity on transient failures ever matters here, the retry belongs in
/// [SyncHttpClient], not in this loop.
List<Map<String, dynamic>> fetchCommentPages({
  required Map<String, String> headers,
  required String urlBase,
}) {
  final out = <Map<String, dynamic>>[];
  for (var page = 1;; page++) {
    final resp = SyncHttpClient.get('$urlBase?per_page=100&page=$page',
        headers: headers);
    if (!resp.isOk) {
      throw StateError('HTTP ${resp.statusCode} fetching comments '
          '(page $page): ${resp.body}');
    }
    final decoded = syncTryDecode(resp.body);
    if (decoded is! List) break;
    out.addAll(decoded.whereType<Map>().cast<Map<String, dynamic>>());
    if (decoded.length < 100) break;
  }
  return out;
}

/// Fetches both comment listings of a PR: inline review comments and
/// issue-style discussion comments.
PrCommentPages prCommentPages({
  required Map<String, String> headers,
  required String inlineUrl,
  required String issueUrl,
}) =>
    (
      inline: fetchCommentPages(headers: headers, urlBase: inlineUrl),
      issue: fetchCommentPages(headers: headers, urlBase: issueUrl),
    );

/// Both PR comment listings, or a sync tool error JSON on a non-OK page.
///
/// Java surfaces a failed comments page as a `RestClientException`
/// (→ tool error), never as an empty "no comments" list.
({String? error, PrCommentPages? pages}) prCommentPagesOrError({
  required Map<String, String> headers,
  required String inlineUrl,
  required String issueUrl,
}) {
  try {
    return (
      error: null,
      pages: prCommentPages(
          headers: headers, inlineUrl: inlineUrl, issueUrl: issueUrl),
    );
  } on StateError catch (e) {
    return (error: syncErr(e.message), pages: null);
  }
}

/// Groups [inline] comments into conversations, appends [issue] entries.
List<Map<String, dynamic>> groupConversations(
  List<Map<String, dynamic>> inline,
  List<Map<String, dynamic>> issue,
) {
  final conversations = <Map<String, dynamic>>[];
  final byRootId = <String, Map<String, dynamic>>{};
  for (final comment in inline) {
    final id = syncAsStr(comment['id']);
    final replyTo = comment['in_reply_to_id'];
    final parent = replyTo == null ? null : byRootId[syncAsStr(replyTo)];
    if (parent == null) {
      final conversation = _conversation(comment);
      byRootId[id] = conversation;
      conversations.add(conversation);
    } else {
      (parent['replies'] as List).add(comment);
      parent['totalComments'] = 1 + (parent['replies'] as List).length;
    }
  }
  conversations.addAll(issue.map(_conversation));
  return conversations;
}

/// Builds one `GitHubConversation.toJSON()` object for [root].
Map<String, dynamic> _conversation(Map<String, dynamic> root) => {
      'path': root['path'],
      'rootComment': root,
      'replies': <dynamic>[],
      'totalComments': 1,
    };
