/// Scheme extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Scheme methods on [JiraClient]: reading and assigning the issue-type and
/// workflow schemes associated with a project.
extension JiraSchemeClient on JiraClient {
  /// `jira_get_project_issue_type_scheme` — GET `project/{key}/issueTypeScheme`.
  Future<Map<String, dynamic>> getProjectIssueTypeScheme(String key) =>
      _getProjectScheme(key, 'issueTypeScheme');

  /// `jira_assign_issue_type_scheme` — PUT `issuetypescheme/{schemeId}/project`.
  ///
  /// Associates the issue-type scheme [schemeId] with [projectId].
  Future<void> assignIssueTypeScheme(String projectId, String schemeId) =>
      _assignScheme('issuetypescheme', projectId, schemeId);

  /// `jira_get_project_workflow_scheme` — GET `project/{key}/workflowScheme`.
  Future<Map<String, dynamic>> getProjectWorkflowScheme(String key) =>
      _getProjectScheme(key, 'workflowScheme');

  /// `jira_assign_workflow_scheme` — PUT `workflowscheme/{schemeId}/project`.
  ///
  /// Associates the workflow scheme [schemeId] with [projectId].
  Future<void> assignWorkflowScheme(String projectId, String schemeId) =>
      _assignScheme('workflowscheme', projectId, schemeId);

  /// GETs `project/{key}/{scheme}` and returns the decoded map.
  Future<Map<String, dynamic>> _getProjectScheme(
    String key,
    String scheme,
  ) async {
    final body = await _http.get('project/$key/$scheme');
    return _decodeMap(body);
  }

  /// PUTs `{projectId}` to `{schemeType}/{schemeId}/project`.
  Future<void> _assignScheme(
    String schemeType,
    String projectId,
    String schemeId,
  ) async {
    await _http.put(
      '$schemeType/$schemeId/project',
      body: jsonEncode({'projectId': projectId}),
    );
  }
}
