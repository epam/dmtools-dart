/// Batch-5 Jira client methods — split from [JiraClient] for file-size.
part of 'jira_client.dart';

// ── Batch 5 extension on JiraClient ─────────────────────────────────────

/// Batch-5 extension methods on [JiraClient], adding user, attachment,
/// project-management, and workflow-scheme operations.
extension JiraClientBatch5 on JiraClient {
  /// `jira_move_to_status_with_resolution` — POST `issue/{key}/transitions`.
  ///
  /// Like [JiraClient.moveToStatus] but includes a resolution in the
  /// transition body. Returns the POST response body, or an explanatory
  /// string when no matching transition exists.
  Future<String> moveToStatusWithResolution(
    String key,
    String statusName,
    String resolution,
  ) =>
      _transitionIssue(key, statusName, {
        'resolution': {'name': resolution}
      });

  /// `jira_get_account_by_email` — GET `user/search?username={email}`.
  ///
  /// Returns the first matching user, or an empty map when none is found.
  Future<Map<String, dynamic>> getAccountByEmail(String email) async {
    final body = await _http.get(
      'user/search',
      queryParams: {'username': email},
    );
    final decoded = jsonDecode(body);
    if (decoded is List && decoded.isNotEmpty) {
      return decoded.first as Map<String, dynamic>;
    }
    return {};
  }

  /// `jira_get_user_profile` — GET `user?accountId={userId}`.
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final body = await _http.get(
      'user',
      queryParams: {'accountId': userId},
    );
    return _decodeMap(body);
  }

  /// `jira_get_my_profile` — GET `myself`.
  Future<Map<String, dynamic>> getMyProfile() async {
    final body = await _http.get('myself');
    return _decodeMap(body);
  }

  /// `jira_attach_file_to_ticket` — POST `issue/{key}/attachments`.
  ///
  /// Uploads the file at [filePath] as a multipart form part named [fileName].
  Future<Map<String, dynamic>> attachFileToTicket(
    String key,
    String fileName,
    String filePath,
  ) async {
    final bytes = await File(filePath).readAsBytes();
    final body = await _http.postMultipart(
      'issue/$key/attachments',
      fileName: fileName,
      bytes: bytes,
    );
    return _decodeMap(body);
  }

  /// `jira_download_attachment` — GET binary from [url] and save locally.
  ///
  /// Writes the downloaded bytes to [filePath] on the local filesystem.
  Future<void> downloadAttachment(String url, String filePath) async {
    final bytes = await _http.getBytes(url);
    await File(filePath).writeAsBytes(bytes);
  }

  /// `jira_delete_project` — DELETE `project/{key}`.
  ///
  /// Deletes the project only when [confirmDelete] is `true`; otherwise the
  /// call is a no-op (a safety guard against accidental deletion).
  Future<void> deleteProject(String key, bool confirmDelete) async {
    if (!confirmDelete) return;
    await _http.delete('project/$key');
  }

  /// `jira_add_fix_version` — appends [version] via `update.fixVersions`.
  Future<void> addFixVersion(String key, String version) =>
      _mutateFixVersions(key, 'add', version);

  /// `jira_remove_fix_version` — removes [version] via `update.fixVersions`.
  Future<void> removeFixVersion(String key, String version) =>
      _mutateFixVersions(key, 'remove', version);

  /// PUTs an `update.fixVersions` operation ([op] is `add` or `remove`).
  Future<void> _mutateFixVersions(
    String key,
    String op,
    String version,
  ) async {
    await _http.put(
      'issue/$key',
      body: jsonEncode({
        'update': {
          'fixVersions': [
            {
              op: {'name': version}
            }
          ],
        },
      }),
    );
  }

  /// `jira_get_project_board_config` — GET `board/{boardId}/configuration`.
  ///
  /// Looks up the first board for [key] via the Agile API, then fetches its
  /// full configuration. Returns an empty map when no board exists.
  Future<Map<String, dynamic>> getProjectBoardConfig(String key) async {
    final boardId = await _findBoardId(key);
    if (boardId == null) return {};
    final body = await _http.getAgile('board/$boardId/configuration');
    return _decodeMap(body);
  }

  /// Finds the first Agile board id for [key], or `null`.
  Future<int?> _findBoardId(String key) async {
    final body = await _http.getAgile(
      'board',
      queryParams: {'projectKeyOrId': key},
    );
    final decoded = _decodeMap(body);
    final values = decoded['values'] as List? ?? const [];
    if (values.isEmpty) return null;
    return (values.first as Map<String, dynamic>)['id'] as int?;
  }

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
