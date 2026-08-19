/// Issue-type extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Issue-type methods on [JiraClient]: creating new issue-type definitions.
extension JiraIssueTypeClient on JiraClient {
  /// `jira_create_project_issue_type` — POST `issuetype`.
  ///
  /// Creates a new issue type with [name] and [type]. [description] is
  /// included only when provided. The [projectKey] argument is accepted for
  /// Java signature parity.
  Future<Map<String, dynamic>> createProjectIssueType(
    String projectKey,
    String name,
    String type, [
    String? description,
  ]) async {
    final payload = <String, dynamic>{'name': name, 'type': type};
    if (description != null) payload['description'] = description;
    final body = await _http.post('issuetype', body: jsonEncode(payload));
    return _decodeMap(body);
  }
}
