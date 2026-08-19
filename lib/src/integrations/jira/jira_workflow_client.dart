/// Project-workflow extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Project-workflow methods on [JiraClient]: creating project-scoped
/// workflows and copying workflow schemes between projects.
extension JiraWorkflowClient on JiraClient {
  /// `jira_setup_project_workflow` — POST `workflow`.
  ///
  /// Creates a workflow scoped to project [target] using the statuses and
  /// transitions described in [statusesJson].
  Future<Map<String, dynamic>> setupProjectWorkflow(
    String target,
    Map<String, dynamic> statusesJson,
  ) async {
    final payload = <String, dynamic>{
      'scope': {
        'type': 'project',
        'project': {'key': target},
      },
      ...statusesJson,
    };
    final body = await _http.post('workflow', body: jsonEncode(payload));
    return _decodeMap(body);
  }

  /// `jira_sync_project_workflow` — copy the workflow scheme across projects.
  ///
  /// Reads the workflow scheme associated with [source] and assigns it to
  /// [target]; does nothing when [source] has no scheme id.
  Future<void> syncProjectWorkflow(String source, String target) async {
    final scheme = await getProjectWorkflowScheme(source);
    final schemeId = scheme['id']?.toString();
    if (schemeId == null) return;
    await assignWorkflowScheme(target, schemeId);
  }
}
