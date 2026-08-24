/// Project administration extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Project-administration methods on [JiraClient]: project deletion,
/// structure copying (components + versions), and full project cloning.
extension JiraProjectClient on JiraClient {
  /// `jira_delete_project` — DELETE `project/{key}`.
  ///
  /// Deletes the project only when [confirmDelete] is `true`; otherwise the
  /// call is a no-op (a safety guard against accidental deletion).
  Future<void> deleteProject(String key, bool confirmDelete) async {
    if (!confirmDelete) return;
    await _http.delete('project/$key');
  }

  /// `jira_restore_project` — POST `project/{key}/restore`.
  ///
  /// Restores a trashed project; reports its key, id, and name from the
  /// restore response, falling back to [key] when the body omits them.
  /// Mirrors Java `restoreProject`.
  Future<Map<String, dynamic>> restoreProject(String key) async {
    final body = await _http.post('project/$key/restore', body: '');
    final result = _decodeMap(body);
    return {
      'success': true,
      'projectKey': result['key'] ?? key,
      'projectId': result['id'] ?? '',
      'projectName': result['name'] ?? '',
      'message': 'Project restored successfully',
    };
  }

  /// `jira_copy_project_structure` — copy components + versions.
  ///
  /// Reads the components and versions of [source] and recreates them in
  /// [target].
  Future<void> copyProjectStructure(String source, String target) async {
    final components = await getComponents(source);
    await _copyNamedEntities(target, 'components', components);
    final versions = await getFixVersions(source);
    await _copyNamedEntities(target, 'versions', versions);
  }

  /// POSTs each entity to `project/{target}/{endpoint}` with name + description.
  Future<void> _copyNamedEntities(
    String target,
    String endpoint,
    List<Map<String, dynamic>> entities,
  ) async {
    for (final e in entities) {
      await _http.post(
        'project/$target/$endpoint',
        body: jsonEncode({
          'name': e['name'],
          'description': e['description'],
        }),
      );
    }
  }

  /// `jira_clone_project` — multi-step project clone.
  ///
  /// Creates the target project from [source] details, then copies the
  /// project structure and syncs the workflow scheme. Returns the created
  /// project definition.
  Future<Map<String, dynamic>> cloneProject(
    String source,
    String target,
    String targetName, [
    String? lead,
  ]) async {
    final details = await getProjectDetails(source);
    final created =
        await _createTargetProject(target, targetName, lead, details);
    await copyProjectStructure(source, target);
    await syncProjectWorkflow(source, target);
    return created;
  }

  /// POSTs the new project definition derived from [sourceDetails].
  Future<Map<String, dynamic>> _createTargetProject(
    String target,
    String targetName,
    String? lead,
    Map<String, dynamic> sourceDetails,
  ) async {
    final payload = <String, dynamic>{
      'key': target,
      'name': targetName,
      'projectTypeKey': sourceDetails['projectTypeKey'] ?? 'software',
      'description': sourceDetails['description'],
      'leadAccountId': lead,
    };
    payload.removeWhere((k, v) => v == null);
    final body = await _http.post('project', body: jsonEncode(payload));
    return _decodeMap(body);
  }
}
