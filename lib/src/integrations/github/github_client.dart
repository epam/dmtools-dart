/// High-level GitHub API client — ports the GitHub subset of the Java MCP tools.
///
/// Each method corresponds to a `@MCPTool`-annotated method on the Java
/// integration client. Transport is delegated to [GithubHttpClient]; this
/// layer only shapes requests and parses JSON into typed results.
library;

import 'dart:convert';

import 'github_http_client.dart';

/// GitHub API methods exposed to the MCP tool runtime.
class GithubClient {
  final GithubHttpClient _http;

  /// Creates a client backed by [_http].
  GithubClient(this._http);

  /// `github_test` — connectivity check via GET `/user`.
  ///
  /// Returns the GitHub user profile on success, or an error map on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final user = await _fetchUser();
      return {
        'success': true,
        'message': 'GitHub connection successful',
        'user': user['login'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'GitHub connection failed',
        'error': e.toString(),
      };
    }
  }

  /// Fetches the authenticated user from GET `/user`.
  Future<Map<String, dynamic>> _fetchUser() async {
    final body = await _http.get('user');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `github_get_pr` — GET `/repos/{owner}/{repo}/pulls/{number}`.
  Future<Map<String, dynamic>> getPr(
    String owner,
    String repo,
    int number,
  ) async {
    final body = await _http.get('repos/$owner/$repo/pulls/$number');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `github_list_prs` — GET `/repos/{owner}/{repo}/pulls`.
  ///
  /// [state] defaults to `open` (GitHub's default) when omitted.
  Future<List<Map<String, dynamic>>> listPrs(
    String owner,
    String repo, [
    String? state,
  ]) async {
    final body = await _http.get(
      'repos/$owner/$repo/pulls',
      queryParams: {'state': state ?? 'open'},
    );
    final decoded = jsonDecode(body) as List;
    return List<Map<String, dynamic>>.from(
      decoded.map((p) => p as Map<String, dynamic>),
    );
  }

  /// `github_create_comment` — POST `/repos/{owner}/{repo}/issues/{number}/comments`.
  ///
  /// Pull-request comments are posted through the issues endpoint, matching
  /// the GitHub REST API (PRs are issues).
  Future<Map<String, dynamic>> createComment(
    String owner,
    String repo,
    int number,
    String body,
  ) async {
    final response = await _http.post(
      'repos/$owner/$repo/issues/$number/comments',
      body: jsonEncode({'body': body}),
    );
    return jsonDecode(response) as Map<String, dynamic>;
  }

  /// `github_get_issue` — GET `/repos/{owner}/{repo}/issues/{number}`.
  Future<Map<String, dynamic>> getIssue(
    String owner,
    String repo,
    int number,
  ) async {
    final body = await _http.get('repos/$owner/$repo/issues/$number');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `github_create_pr` — POST `/repos/{owner}/{repo}/pulls`.
  Future<Map<String, dynamic>> createPr(
    String owner,
    String repo,
    String title,
    String head,
    String base,
  ) async {
    final response = await _http.post(
      'repos/$owner/$repo/pulls',
      body: jsonEncode({
        'title': title,
        'head': head,
        'base': base,
      }),
    );
    return jsonDecode(response) as Map<String, dynamic>;
  }
}
