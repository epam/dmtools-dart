/// High-level GitLab API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a GitLab MCP tool. Transport is delegated to
/// [GitlabHttpClient]; this layer shapes requests and parses JSON into typed
/// results. Project identifiers may be numeric ids or `group/project` paths
/// and are URL-encoded automatically.
library;

import 'dart:convert';

import 'gitlab_http_client.dart';

/// GitLab API methods exposed to the MCP tool runtime.
class GitlabClient {
  final GitlabHttpClient _http;

  /// Creates a client backed by [_http].
  GitlabClient(this._http);

  /// URL-encodes a project id or `group/project` path for path segments.
  String _encodeProject(String project) => Uri.encodeComponent(project);

  /// `gitlab_test` — connectivity check via GET `/api/v4/user`.
  ///
  /// Returns the GitLab user profile on success, or an error map on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get('user');
      final user = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'GitLab connection successful',
        'user': user['name'] ?? user['username'] ?? '',
        'email': user['email'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'GitLab connection failed',
        'error': e.toString(),
      };
    }
  }

  /// Decodes [body] as a JSON object, or `null` if it is not a map.
  Map<String, dynamic>? _asMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  /// Decodes [body] as a list of JSON objects, or empty if not an array.
  List<Map<String, dynamic>> _asList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return List<Map<String, dynamic>>.from(
      decoded.map((i) => i as Map<String, dynamic>),
    );
  }

  /// GETs [path] and returns the JSON object body, or `null` if not a map.
  Future<Map<String, dynamic>?> _getObject(
    String path, [
    Map<String, dynamic>? queryParams,
  ]) async =>
      _asMap(await _http.get(path, queryParams: queryParams));

  /// POSTs [path] with [payload] and returns the JSON object body, or `null`.
  Future<Map<String, dynamic>?> _postObject(
          String path, Object? payload) async =>
      _asMap(await _http.post(path, body: payload));

  /// PUTs [path] with [payload] and returns the JSON object body, or `null`.
  Future<Map<String, dynamic>?> _putObject(
          String path, Object? payload) async =>
      _asMap(await _http.put(path, body: payload));

  /// GETs [path] and returns the JSON array body, or empty if not an array.
  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async =>
      _asList(await _http.get(path, queryParams: queryParams));

  /// `gitlab_get_mr` — GET `/api/v4/projects/{id}/merge_requests/{iid}`.
  ///
  /// [project] is the numeric id or `group/project` path. Returns `null`
  /// for non-object bodies.
  Future<Map<String, dynamic>?> getMr(String project, int iid) => _getObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid',
      );

  /// `gitlab_list_mrs` — GET `/api/v4/projects/{id}/merge_requests`.
  ///
  /// [project] is the numeric id or `group/project` path. [state] filters
  /// by MR state (`opened`, `closed`, `merged`, `all`); defaults to `opened`.
  Future<List<Map<String, dynamic>>> listMrs(
    String project, [
    String state = 'opened',
  ]) =>
      _getList(
        'projects/${_encodeProject(project)}/merge_requests',
        queryParams: {'state': state, 'per_page': 20},
      );

  /// `gitlab_create_mr_note` — POST a note on a merge request.
  ///
  /// Returns the created note object, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> createMrNote(
    String project,
    int iid,
    String body,
  ) =>
      _postObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid/notes',
        jsonEncode({'body': body}),
      );

  /// `gitlab_merge_mr` — PUT `/api/v4/projects/{id}/merge_requests/{iid}`
  /// with `state_event=merge`.
  ///
  /// Returns the updated merge request, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> mergeMr(String project, int iid) =>
      _setMrState(project, iid, 'merge');

  /// `gitlab_close_mr` — PUT `/api/v4/projects/{id}/merge_requests/{iid}`
  /// with `state_event=close`.
  ///
  /// Returns the updated merge request, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> closeMr(String project, int iid) =>
      _setMrState(project, iid, 'close');

  /// PUTs a `state_event` on a merge request — shared by merge/close.
  Future<Map<String, dynamic>?> _setMrState(
    String project,
    int iid,
    String event,
  ) =>
      _putObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid',
        jsonEncode({'state_event': event}),
      );

  /// `gitlab_get_mr_diff` — GET
  /// `/api/v4/projects/{id}/merge_requests/{iid}/changes`.
  ///
  /// Returns the merge request with its `changes` array, or `null` for
  /// non-object bodies.
  Future<Map<String, dynamic>?> getMrDiff(String project, int iid) =>
      _getObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid/changes',
      );

  /// `gitlab_approve_mr` — POST
  /// `/api/v4/projects/{id}/merge_requests/{iid}/approve`.
  ///
  /// Returns the updated merge request, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> approveMr(String project, int iid) =>
      _postObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid/approve',
        null,
      );

  /// `gitlab_unapprove_mr` — POST
  /// `/api/v4/projects/{id}/merge_requests/{iid}/unapprove`.
  ///
  /// Returns the updated merge request, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> unapproveMr(String project, int iid) =>
      _postObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid/unapprove',
        null,
      );

  /// `gitlab_get_mr_notes` — GET
  /// `/api/v4/projects/{id}/merge_requests/{iid}/notes`.
  Future<List<Map<String, dynamic>>> getMrNotes(String project, int iid) =>
      _getList(
        'projects/${_encodeProject(project)}/merge_requests/$iid/notes',
      );

  /// `gitlab_get_mr_approvals` — GET
  /// `/api/v4/projects/{id}/merge_requests/{iid}/approvals`.
  ///
  /// Returns the merge-request approval state, or `null` for non-object
  /// bodies.
  Future<Map<String, dynamic>?> getMrApprovals(String project, int iid) =>
      _getObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid/approvals',
      );

  /// `gitlab_get_mr_discussions` — GET
  /// `/api/v4/projects/{id}/merge_requests/{iid}/discussions`.
  Future<List<Map<String, dynamic>>> getMrDiscussions(
    String project,
    int iid,
  ) =>
      _getList(
        'projects/${_encodeProject(project)}/merge_requests/$iid/discussions',
      );

  /// `gitlab_trigger_mr_discussion_resolve` — PUT
  /// `/api/v4/projects/{id}/merge_requests/{iid}/discussions/{discussionId}`
  /// with `resolved` in the body.
  ///
  /// [resolved] resolves the discussion when true, unresolves it when false.
  /// Returns the updated discussion, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> triggerMrDiscussionResolve(
    String project,
    int iid,
    String discussionId,
    bool resolved,
  ) =>
      _putObject(
        'projects/${_encodeProject(project)}/merge_requests/$iid'
        '/discussions/$discussionId',
        jsonEncode({'resolved': resolved}),
      );

  /// `gitlab_get_issue` — GET `/api/v4/projects/{id}/issues/{iid}`.
  ///
  /// Returns `null` for non-object bodies.
  Future<Map<String, dynamic>?> getIssue(String project, int iid) =>
      _getObject('projects/${_encodeProject(project)}/issues/$iid');

  /// `gitlab_create_issue` — POST `/api/v4/projects/{id}/issues`.
  ///
  /// [description] is optional; when omitted only [title] is sent. Returns
  /// the created issue, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> createIssue(
    String project,
    String title, [
    String? description,
  ]) {
    final payload = <String, dynamic>{'title': title};
    if (description != null) payload['description'] = description;
    return _postObject(
      'projects/${_encodeProject(project)}/issues',
      jsonEncode(payload),
    );
  }

  /// `gitlab_list_issues` — GET `/api/v4/projects/{id}/issues`.
  ///
  /// [state] filters by issue state (`opened`, `closed`, `all`); defaults
  /// to `opened`.
  Future<List<Map<String, dynamic>>> listIssues(
    String project, [
    String state = 'opened',
  ]) =>
      _getList(
        'projects/${_encodeProject(project)}/issues',
        queryParams: {'state': state, 'per_page': 20},
      );

  /// `gitlab_get_pipelines` — GET `/api/v4/projects/{id}/pipelines`.
  Future<List<Map<String, dynamic>>> getPipelines(String project) =>
      _getList('projects/${_encodeProject(project)}/pipelines');

  /// `gitlab_trigger_pipeline` — POST `/api/v4/projects/{id}/pipeline`.
  ///
  /// [ref] is the branch or tag to run the pipeline for. Returns the created
  /// pipeline, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> triggerPipeline(
    String project,
    String ref,
  ) =>
      _postObject(
        'projects/${_encodeProject(project)}/pipeline',
        jsonEncode({'ref': ref}),
      );

  /// `gitlab_get_pipeline` — GET `/api/v4/projects/{id}/pipelines/{id}`.
  ///
  /// Returns `null` for non-object bodies.
  Future<Map<String, dynamic>?> getPipeline(String project, int id) =>
      _getObject('projects/${_encodeProject(project)}/pipelines/$id');

  /// `gitlab_create_branch` — POST
  /// `/api/v4/projects/{id}/repository/branches`.
  ///
  /// [branch] is the new branch name; [ref] is the branch, tag, or commit
  /// to create it from. Returns the created branch, or `null` for
  /// non-object bodies.
  Future<Map<String, dynamic>?> createBranch(
    String project,
    String branch,
    String ref,
  ) =>
      _postObject(
        'projects/${_encodeProject(project)}/repository/branches',
        jsonEncode({'branch': branch, 'ref': ref}),
      );

  /// `gitlab_get_file_content` — GET
  /// `/api/v4/projects/{id}/repository/files/{encodedPath}`.
  ///
  /// [filePath] is URL-encoded for the path segment. [ref] is optional;
  /// when provided it is sent as the `ref` query parameter. Returns `null`
  /// for non-object bodies.
  Future<Map<String, dynamic>?> getFileContent(
    String project,
    String filePath, [
    String? ref,
  ]) =>
      _getObject(
        'projects/${_encodeProject(project)}/repository/files/'
        '${Uri.encodeComponent(filePath)}',
        ref == null ? null : {'ref': ref},
      );

  /// `gitlab_create_tag` — POST
  /// `/api/v4/projects/{id}/repository/tags`.
  ///
  /// [tagName] is the new tag name; [ref] is the branch, tag, or commit to
  /// create it from. Returns the created tag, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> createTag(
    String project,
    String tagName,
    String ref,
  ) =>
      _postObject(
        'projects/${_encodeProject(project)}/repository/tags',
        jsonEncode({'tag_name': tagName, 'ref': ref}),
      );

  /// `gitlab_get_tags` — GET `/api/v4/projects/{id}/repository/tags`.
  Future<List<Map<String, dynamic>>> getTags(String project) =>
      _getList('projects/${_encodeProject(project)}/repository/tags');

  /// `gitlab_get_branches` — GET
  /// `/api/v4/projects/{id}/repository/branches`.
  Future<List<Map<String, dynamic>>> getBranches(String project) =>
      _getList('projects/${_encodeProject(project)}/repository/branches');

  /// `gitlab_get_project_members` — GET `/api/v4/projects/{id}/members`.
  Future<List<Map<String, dynamic>>> getProjectMembers(String project) =>
      _getList('projects/${_encodeProject(project)}/members');

  /// `gitlab_get_group_members` — GET `/api/v4/groups/{id}/members`.
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) =>
      _getList('groups/${Uri.encodeComponent(groupId)}/members');

  /// `gitlab_get_project_details` — GET `/api/v4/projects/{id}`.
  ///
  /// Returns the project object, or `null` for non-object bodies.
  Future<Map<String, dynamic>?> getProjectDetails(String project) =>
      _getObject('projects/${_encodeProject(project)}');

  /// `gitlab_get_project_variables` — GET `/api/v4/projects/{id}/variables`.
  Future<List<Map<String, dynamic>>> getProjectVariables(String project) =>
      _getList('projects/${_encodeProject(project)}/variables');
}
