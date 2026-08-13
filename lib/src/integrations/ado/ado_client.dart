/// High-level Azure DevOps API client — ports the ADO subset of the Java MCP
/// tools.
///
/// Each method corresponds to a Java `@MCPTool`-annotated method (or a
/// net-new PR tool, for which there is no Java client yet). Transport is
/// delegated to [AdoHttpClient]; this layer only shapes requests and parses
/// JSON into typed results.
library;

import 'dart:convert';

import 'ado_http_client.dart';

/// Azure DevOps API methods exposed to the MCP tool runtime.
class AdoClient {
  final AdoHttpClient _http;

  /// Creates a client backed by [_http].
  AdoClient(this._http);

  /// `ado_test` — connectivity check via GET `{org}/_apis/connection-data`.
  ///
  /// Returns `success` + the authenticated user descriptor on success, or a
  /// failure map on error.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.getOrg('connection-data');
      final data = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'Azure DevOps connection successful',
        'authenticatedUser': data['authenticatedUser'],
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Azure DevOps connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `ado_get_work_item` — GET `{org}/{project}/_apis/wit/workitems/{id}`.
  Future<Map<String, dynamic>> getWorkItem(int id) async {
    final body = await _http.get('wit/workitems/$id');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `ado_create_work_item` — POST `{org}/{project}/_apis/wit/workitems/$type`.
  ///
  /// The body is a JSON Patch document (ADO's required wire format) that sets
  /// `System.Title`; the `Content-Type` is `application/json-patch+json`.
  Future<Map<String, dynamic>> createWorkItem(String type, String title) async {
    final body = await _http.postPatch(
      'wit/workitems/\$$type',
      body: jsonEncode([
        {'op': 'add', 'path': '/fields/System.Title', 'value': title},
      ]),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `ado_list_prs` — GET `{org}/{project}/_apis/git/pullrequests`.
  ///
  /// [status] defaults to `active` (ADO's default) when omitted, passed as
  /// `searchCriteria.status`.
  Future<List<Map<String, dynamic>>> listPrs([String? status]) async {
    final body = await _http.get(
      'git/pullrequests',
      queryParams: {'searchCriteria.status': status ?? 'active'},
    );
    return _decodeList(body);
  }

  /// `ado_get_pr` — GET `{org}/{project}/_apis/git/pullrequests/{id}`.
  Future<Map<String, dynamic>> getPr(int id) async {
    final body = await _http.get('git/pullrequests/$id');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `ado_update_work_item` — PATCH `wit/workitems/{id}` with one JSON-Patch
  /// `add` op per entry in [fields]. The request uses ADO's
  /// `application/json-patch+json` content type.
  Future<Map<String, dynamic>> updateWorkItem(
    int id,
    Map<String, dynamic> fields,
  ) async {
    final body = await _http.patchPatch(
      'wit/workitems/$id',
      body: jsonEncode([
        for (final entry in fields.entries)
          {'op': 'add', 'path': '/fields/${entry.key}', 'value': entry.value},
      ]),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `ado_get_work_items` — GET `wit/workitems?ids=1,2,...`.
  Future<List<Map<String, dynamic>>> getWorkItems(List<int> ids) async {
    final body = await _http.get(
      'wit/workitems',
      queryParams: {'ids': ids.join(',')},
    );
    return _decodeList(body);
  }

  /// `ado_list_work_items` — POST `wit/wiql` with the WIQL query [wiql].
  Future<List<Map<String, dynamic>>> listWorkItems(String wiql) async {
    final body = await _http.post(
      'wit/wiql',
      body: jsonEncode({'query': wiql}),
    );
    return _decodeList(body);
  }

  /// `ado_get_work_item_types` — GET `wit/workitemtypes`.
  ///
  /// The [project] argument mirrors the Java tool surface; the request is
  /// scoped to the project configured on this client.
  Future<List<Map<String, dynamic>>> getWorkItemTypes(String project) async {
    final body = await _http.get('wit/workitemtypes');
    return _decodeList(body);
  }

  /// `ado_create_repo` — POST `git/repositories` with `{"name": name}`.
  ///
  /// The [project] argument mirrors the Java tool surface; the request is
  /// scoped to the project configured on this client.
  Future<Map<String, dynamic>> createRepo(String project, String name) async {
    final body = await _http.post(
      'git/repositories',
      body: jsonEncode({'name': name}),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `ado_get_repos` — GET `git/repositories`.
  ///
  /// The [project] argument mirrors the Java tool surface; the request is
  /// scoped to the project configured on this client.
  Future<List<Map<String, dynamic>>> getRepos(String project) async {
    final body = await _http.get('git/repositories');
    return _decodeList(body);
  }

  /// `ado_get_builds` — GET `build/builds`, optionally filtered by
  /// [definitions] (a comma-joined `definitions` query parameter).
  ///
  /// The [project] argument mirrors the Java tool surface; the request is
  /// scoped to the project configured on this client.
  Future<List<Map<String, dynamic>>> getBuilds(
    String project, [
    List<int>? definitions,
  ]) async {
    final queryParams =
        definitions == null ? null : {'definitions': definitions.join(',')};
    final body = await _http.get('build/builds', queryParams: queryParams);
    return _decodeList(body);
  }

  /// `ado_trigger_build` — POST `build/builds` queuing [definitionId].
  Future<Map<String, dynamic>> triggerBuild(int definitionId) async {
    final body = await _http.post(
      'build/builds',
      body: jsonEncode({
        'definition': {'id': definitionId}
      }),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `ado_get_work_item_revisions` — GET `wit/workitems/{id}/revisions`.
  Future<List<Map<String, dynamic>>> getWorkItemRevisions(int id) async {
    final body = await _http.get('wit/workitems/$id/revisions');
    return _decodeList(body);
  }

  /// `ado_get_teams` — GET `projects/{project}/teams` (org-scoped).
  ///
  /// The path carries the project explicitly, so the request targets the
  /// organization-scoped URL rather than the configured project scope.
  Future<List<Map<String, dynamic>>> getTeams(String project) async {
    final body = await _http.getOrg('projects/$project/teams');
    return _decodeList(body);
  }

  /// `ado_get_team_members` — GET
  /// `projects/{project}/teams/{teamId}/members` (org-scoped).
  Future<List<Map<String, dynamic>>> getTeamMembers(
    String project,
    String teamId,
  ) async {
    final body = await _http.getOrg('projects/$project/teams/$teamId/members');
    return _decodeList(body);
  }

  /// `ado_get_project_properties` — GET `projects/{projectId}/properties`
  /// (org-scoped).
  Future<List<Map<String, dynamic>>> getProjectProperties(
    String projectId,
  ) async {
    final body = await _http.getOrg('projects/$projectId/properties');
    return _decodeList(body);
  }

  /// `ado_get_repo_branches` — GET `git/repositories/{repoId}/stats/branches`.
  Future<List<Map<String, dynamic>>> getRepoBranches(
    String project,
    String repoId,
  ) async {
    final body = await _http.get('git/repositories/$repoId/stats/branches');
    return _decodeList(body);
  }

  /// `ado_get_commits` — POST `git/repositories/{repoId}/commitsbatch` with
  /// [searchCriteria] as the JSON body when criteria are supplied, otherwise
  /// GET `git/repositories/{repoId}/commits`.
  Future<List<Map<String, dynamic>>> getCommits(
    String project,
    String repoId, [
    Map<String, dynamic>? searchCriteria,
  ]) async {
    if (searchCriteria == null) {
      return _decodeList(await _http.get('git/repositories/$repoId/commits'));
    }
    return _decodeList(await _http.post(
      'git/repositories/$repoId/commitsbatch',
      body: jsonEncode(searchCriteria),
    ));
  }

  /// `ado_get_pull_request_reviewers` — GET
  /// `git/pullrequests/{prId}/reviewers`.
  Future<List<Map<String, dynamic>>> getPullRequestReviewers(
    String project,
    int prId,
  ) async {
    final body = await _http.get('git/pullrequests/$prId/reviewers');
    return _decodeList(body);
  }

  /// `ado_add_pull_request_reviewer` — PUT
  /// `git/pullrequests/{prId}/reviewers/{reviewerId}`.
  Future<Map<String, dynamic>> addPullRequestReviewer(
    String project,
    int prId,
    String reviewerId,
  ) async {
    final body = await _http.put(
      'git/pullrequests/$prId/reviewers/$reviewerId',
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Decodes a JSON array body into a list of typed maps.
  List<Map<String, dynamic>> _decodeList(String body) =>
      (jsonDecode(body) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
}
