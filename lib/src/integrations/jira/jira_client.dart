/// High-level Jira API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a `@MCPTool`-annotated method on the Java
/// `JiraClient`. Transport is delegated to [JiraHttpClient]; this layer only
/// shapes requests and parses JSON into typed results.
library;

import 'dart:convert';
import 'dart:io';

import 'jira_http_client.dart';

part 'jira_client_batch5.dart';
part 'jira_client_batch6.dart';

/// Jira API methods exposed to the MCP tool runtime.
class JiraClient {
  final JiraHttpClient _http;

  /// Creates a client backed by [_http].
  JiraClient(this._http);

  /// Joins field names into the `fields` query value, defaulting to
  /// `*navigable` (Java default) when none are requested.
  String _joinFields(List<String>? fields) =>
      fields != null && fields.isNotEmpty ? fields.join(',') : '*navigable';

  /// `jira_test` — connectivity check via GET `/rest/api/latest/myself`.
  ///
  /// Returns `success: true` with the user profile on success, or
  /// `success: false` with the error message on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get('myself');
      final user = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'Jira connection successful',
        'user': user['displayName'] ?? '',
        'email': user['emailAddress'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Jira connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `jira_get_ticket` — GET `/rest/api/latest/issue/{key}`.
  ///
  /// [fields] defaults to `*navigable`. Returns `null` for non-object bodies.
  Future<Map<String, dynamic>?> getTicket(
    String key, [
    List<String>? fields,
  ]) async {
    final body = await _http.get(
      'issue/$key',
      queryParams: {'fields': _joinFields(fields)},
    );
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  /// `jira_search_by_jql` — searches by JQL with auto-pagination.
  ///
  /// Tries the Cloud cursor endpoint first (`/rest/api/latest/search/jql`),
  /// paginating via `nextPageToken`. If that returns nothing and signals no
  /// cursor, falls back to the Server/DC offset-based `/search` endpoint.
  Future<List<Map<String, dynamic>>> searchByJql(
    String jql, [
    List<String>? fields,
  ]) async {
    final fieldsParam = _joinFields(fields);
    final result = await _searchCursor(jql, fieldsParam);
    if (result.issues.isEmpty && !result.tokenSeen) {
      return _searchServerOffset(jql, fieldsParam);
    }
    return result.issues;
  }

  /// Runs the Cloud cursor-paginated `search/jql` endpoint.
  Future<({List<Map<String, dynamic>> issues, bool tokenSeen})> _searchCursor(
    String jql,
    String fields,
  ) async {
    final body = await _http.get(
      'search/jql',
      queryParams: {'jql': jql, 'fields': fields},
    );
    final tokenSeen = body.contains('nextPageToken');
    final all = _extractIssues(body);
    var nextToken = _nextToken(body);
    while (nextToken != null) {
      final pageBody = await _http.get('search/jql', queryParams: {
        'jql': jql,
        'fields': fields,
        'nextPageToken': nextToken,
      });
      all.addAll(_extractIssues(pageBody));
      nextToken = _nextToken(pageBody);
    }
    return (issues: all, tokenSeen: tokenSeen);
  }

  /// Parses the `issues` array out of a search response body.
  List<Map<String, dynamic>> _extractIssues(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    return _castObjectList(decoded['issues'] as List? ?? const []);
  }

  /// Extracts `nextPageToken` from a search body, or `null`.
  String? _nextToken(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded['nextPageToken'] as String?;
  }

  /// Server/DC offset-based pagination fallback for `/search`.
  Future<List<Map<String, dynamic>>> _searchServerOffset(
    String jql,
    String fields,
  ) async {
    const maxResults = 100;
    final all = <Map<String, dynamic>>[];
    var startAt = 0;
    var total = 0;
    do {
      final body = await _http.get('search', queryParams: {
        'jql': jql,
        'fields': fields,
        'startAt': startAt.toString(),
        'maxResults': maxResults.toString(),
      });
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final issues = decoded['issues'] as List? ?? [];
      all.addAll(issues.map((i) => i as Map<String, dynamic>));
      total = (decoded['total'] as num?)?.toInt() ?? 0;
      startAt += maxResults;
    } while (startAt < total);
    return all;
  }

  /// `jira_post_comment` — POST `/rest/api/latest/issue/{key}/comment`.
  Future<void> postComment(String key, String comment) async {
    await _http.post(
      'issue/$key/comment',
      body: jsonEncode({'body': comment}),
    );
  }

  /// `jira_add_label` — adds [label] to [key] if not already present.
  Future<void> addLabel(String key, String label) async {
    final labels = await _fetchLabels(key);
    if (labels.contains(label)) return;
    labels.add(label);
    await _setLabels(key, labels);
  }

  /// `jira_remove_label` — removes [label] from [key] if present.
  Future<void> removeLabel(String key, String label) async {
    final labels = await _fetchLabels(key);
    labels.remove(label);
    await _setLabels(key, labels);
  }

  /// Fetches the current labels list for [key].
  Future<List<String>> _fetchLabels(String key) async {
    final body = await _http.get(
      'issue/$key',
      queryParams: {'fields': 'labels'},
    );
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final fields = decoded['fields'] as Map<String, dynamic>? ?? {};
    return List<String>.from(fields['labels'] as List? ?? []);
  }

  /// PUTs the full labels set for [key] using `update.labels[].set`.
  Future<void> _setLabels(String key, List<String> labels) async {
    await _http.put('issue/$key',
        body: jsonEncode({
          'update': {
            'labels': [
              {'set': labels}
            ]
          },
        }));
  }

  /// `jira_move_to_status` — transitions [key] to [statusName].
  ///
  /// Matches by transition name or destination status name (case-insensitive).
  /// Returns the POST response body, or an explanatory string when no
  /// matching transition exists.
  Future<String> moveToStatus(String key, String statusName) =>
      _transitionIssue(key, statusName, null);

  /// Posts a transition for [key] with optional [extraFields] (e.g. resolution).
  Future<String> _transitionIssue(
    String key,
    String statusName,
    Map<String, dynamic>? extraFields,
  ) async {
    final transitionId = await _findTransition(key, statusName);
    if (transitionId == null) {
      return 'No transition found for status: $statusName';
    }
    final body = <String, dynamic>{
      'transition': {'id': transitionId}
    };
    if (extraFields != null) body['fields'] = extraFields;
    return _http.post(
      'issue/$key/transitions',
      body: jsonEncode(body),
    );
  }

  /// Finds a transition id matching [statusName] for [key].
  Future<String?> _findTransition(String key, String statusName) async {
    final transitions = await getTransitions(key);
    final target = statusName.toLowerCase();
    for (final t in transitions) {
      final name = (t['name'] as String?)?.toLowerCase() ?? '';
      final toStatus = t['to'] as Map<String, dynamic>?;
      final toName = (toStatus?['name'] as String?)?.toLowerCase() ?? '';
      if (name == target || toName == target) {
        return t['id'] as String?;
      }
    }
    return null;
  }

  /// `jira_get_comments` — GET `/rest/api/latest/issue/{key}/comment`.
  ///
  /// Returns the `comments` array; an empty list when the body is not an
  /// object or the array is absent.
  Future<List<Map<String, dynamic>>> getComments(String key) async {
    final body = await _http.get('issue/$key/comment');
    return _extractArray(body, 'comments');
  }

  /// `jira_assign` — PUT `/rest/api/latest/issue/{key}/assignee`.
  Future<void> assignTo(String key, String accountId) async {
    await _http.put(
      'issue/$key/assignee',
      body: jsonEncode({'accountId': accountId}),
    );
  }

  /// `jira_update_field` — PUT `/rest/api/latest/issue/{key}`.
  ///
  /// Sets a single [field] to [value] inside the `fields` object.
  Future<void> updateField(String key, String field, Object value) =>
      _putFields(key, {field: value});

  /// `jira_create_ticket` — POST `/rest/api/latest/issue`.
  ///
  /// Creates a ticket in [project] with the given [issueType] name and
  /// [summary]; [description] is included only when provided.
  Future<Map<String, dynamic>> createTicketBasic(
    String project,
    String issueType,
    String summary, [
    String? description,
  ]) async {
    final fields = <String, dynamic>{
      'project': {'key': project},
      'issuetype': {'name': issueType},
      'summary': summary,
    };
    if (description != null) fields['description'] = description;
    final body =
        await _http.post('issue', body: jsonEncode({'fields': fields}));
    return _decodeMap(body);
  }

  /// `jira_get_transitions` — GET `/rest/api/latest/issue/{key}/transitions`.
  ///
  /// Returns the `transitions` array; an empty list when the body is not an
  /// object or the array is absent.
  Future<List<Map<String, dynamic>>> getTransitions(String key) async {
    final body = await _http.get('issue/$key/transitions');
    return _extractArray(body, 'transitions');
  }

  /// `jira_delete_ticket` — DELETE `/rest/api/latest/issue/{key}`.
  Future<void> deleteTicket(String key) async {
    await _http.delete('issue/$key');
  }

  /// `jira_clear_field` — PUT `/rest/api/latest/issue/{key}`.
  ///
  /// Sets a single [field] to `null`, effectively clearing it.
  Future<void> clearField(String key, String field) =>
      _putFields(key, {field: null});

  /// `jira_get_issue_types` — GET `issue/createmeta/{project}/issuetypes`.
  ///
  /// Returns the `issueTypes` array from the create-metadata response.
  Future<List<Map<String, dynamic>>> getIssueTypes(String project) async {
    final body = await _http.get('issue/createmeta/$project/issuetypes');
    return _extractArray(body, 'issueTypes');
  }

  /// `jira_get_fields` — GET `issue/createmeta/{project}/issuetypes`.
  ///
  /// Returns the full create-metadata body so callers can inspect the
  /// available field definitions for [project].
  Future<Map<String, dynamic>> getFields(String project) async {
    final body = await _http.get('issue/createmeta/$project/issuetypes');
    return _decodeMap(body);
  }

  /// `jira_get_components` — GET `project/{project}/components`.
  Future<List<Map<String, dynamic>>> getComponents(String project) async {
    final body = await _http.get('project/$project/components');
    return _decodeList(body);
  }

  /// `jira_get_fix_versions` — GET `project/{project}/versions`.
  Future<List<Map<String, dynamic>>> getFixVersions(String project) async {
    final body = await _http.get('project/$project/versions');
    return _decodeList(body);
  }

  /// `jira_set_fix_version` — PUT `issue/{key}`.
  ///
  /// Replaces the fix-version set with `[{name: versionName}]`.
  Future<void> setFixVersion(String key, String versionName) => _putFields(
        key,
        {
          'fixVersions': [
            {'name': versionName}
          ],
        },
      );

  /// `jira_set_priority` — PUT `issue/{key}`.
  ///
  /// Sets the `priority` field to `{name: priorityName}`.
  Future<void> setPriority(String key, String priorityName) => _putFields(
        key,
        {
          'priority': {'name': priorityName},
        },
      );

  /// `jira_get_subtasks` — parses `fields.subtasks` from the ticket.
  Future<List<Map<String, dynamic>>> getSubtasks(String key) async {
    final ticket = await getTicket(key);
    if (ticket == null) return const [];
    final fields = ticket['fields'] as Map<String, dynamic>? ?? {};
    return _castObjectList(fields['subtasks'] as List? ?? const []);
  }

  /// `jira_update_description` — PUT `issue/{key}`.
  ///
  /// Sets the `description` field to [description].
  Future<void> updateDescription(String key, String description) =>
      _putFields(key, {'description': description});

  /// `jira_create_ticket_with_parent` — POST `issue`.
  ///
  /// Creates a ticket in [project] with a parent link to [parentKey].
  Future<Map<String, dynamic>> createTicketWithParent(
    String project,
    String issueType,
    String summary,
    String parentKey,
  ) async {
    final body = await _http.post(
      'issue',
      body: jsonEncode({
        'fields': {
          'project': {'key': project},
          'issuetype': {'name': issueType},
          'summary': summary,
          'parent': {'key': parentKey},
        },
      }),
    );
    return _decodeMap(body);
  }

  /// Casts every element of [list] to a `Map<String, dynamic>`.
  List<Map<String, dynamic>> _castObjectList(List list) =>
      List<Map<String, dynamic>>.from(
        list.map((e) => e as Map<String, dynamic>),
      );

  /// Decodes a top-level JSON array body into a list of object maps.
  List<Map<String, dynamic>> _decodeList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return _castObjectList(decoded);
  }

  /// Extracts [key]'s array from a JSON object body, or an empty list.
  List<Map<String, dynamic>> _extractArray(String body, String key) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    return _castObjectList(decoded[key] as List? ?? const []);
  }

  /// PUTs a `fields` object to `issue/{key}`.
  Future<void> _putFields(String key, Map<String, dynamic> fields) async {
    await _http.put(
      'issue/$key',
      body: jsonEncode({'fields': fields}),
    );
  }

  /// Decodes a JSON body to a map, defaulting to an empty map.
  Map<String, dynamic> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  // ── Batch 4: remaining Java tools ──────────────────────────────────────

  /// `jira_post_comment_if_not_exists` — POST comment only if absent.
  ///
  /// Fetches existing comments and compares each plain-text body to
  /// [comment]; posts only when no match is found. Returns `true` when a
  /// comment was posted, `false` when it already existed.
  Future<bool> postCommentIfNotExists(String key, String comment) async {
    final existing = await getComments(key);
    for (final c in existing) {
      final body = c['body'];
      if (body is String && body == comment) return false;
    }
    await postComment(key, comment);
    return true;
  }

  /// `jira_update_field_as_adf` — PUT `issue/{key}` via v3 API with ADF body.
  ///
  /// Sets [field] to the ADF document [value] using the `/rest/api/3`
  /// endpoint, which expects Atlassian Document Format for rich-text fields.
  Future<void> updateFieldAsAdf(
    String key,
    String field,
    Map<String, dynamic> value,
  ) async {
    await _http.putV3(
      'issue/$key',
      body: jsonEncode({
        'fields': {field: value}
      }),
    );
  }

  /// Returns every field id whose display name equals [fieldName].
  Future<List<String>> _fieldIdsByName(String fieldName) async {
    final body = await _http.get('field');
    return _decodeList(body)
        .where((f) => f['name'] == fieldName)
        .map((f) => f['id'] as String)
        .toList();
  }

  /// `jira_get_all_fields_with_name` — GET `field`, filter by display name.
  ///
  /// Returns all field definitions (system + custom) whose `name` matches
  /// [fieldName]. The [project] argument is accepted for Java signature
  /// parity.
  Future<List<Map<String, dynamic>>> getAllFieldsWithName(
    String project,
    String fieldName,
  ) async {
    final body = await _http.get('field');
    return _decodeList(body).where((f) => f['name'] == fieldName).toList();
  }

  /// `jira_update_all_fields_with_name` — PUT `issue/{key}`.
  ///
  /// Finds every field id whose display name equals [fieldName] and sets
  /// each to [value] in a single PUT.
  Future<void> updateAllFieldsWithName(
    String key,
    String fieldName,
    Object value,
  ) async {
    final ids = await _fieldIdsByName(fieldName);
    if (ids.isEmpty) return;
    final fields = <String, dynamic>{for (final id in ids) id: value};
    await _putFields(key, fields);
  }

  /// `jira_update_ticket` — PUT `issue/{key}` with raw JSON body.
  ///
  /// Sends [jsonParams] verbatim as the request body — the caller controls
  /// the exact `fields` / `update` structure.
  Future<void> updateTicket(String key, Map<String, dynamic> jsonParams) async {
    await _http.put('issue/$key', body: jsonEncode(jsonParams));
  }

  /// `jira_link_issues` — POST `issue/link`.
  ///
  /// Creates an issue link of type [linkType] between [inwardKey] and
  /// [outwardKey].
  Future<void> linkIssues(
    String linkType,
    String inwardKey,
    String outwardKey,
  ) async {
    await _http.post(
      'issue/link',
      body: jsonEncode({
        'type': {'name': linkType},
        'inwardIssue': {'key': inwardKey},
        'outwardIssue': {'key': outwardKey},
      }),
    );
  }

  /// `jira_get_issue_link_types` — GET `issue/link/type`.
  ///
  /// Returns the `issueLinkTypes` array from the link-type listing.
  Future<List<Map<String, dynamic>>> getIssueLinkTypes() async {
    final body = await _http.get('issue/link/type');
    return _extractArray(body, 'issueLinkTypes');
  }

  /// `jira_execute_request` — GET any Jira REST path.
  ///
  /// Performs a GET against [url] (relative to `/rest/api/latest/`) and
  /// returns the decoded JSON object.
  Future<Map<String, dynamic>> executeRequest(String url) async {
    final body = await _http.get(url);
    return _decodeMap(body);
  }

  /// `jira_get_project_details` — GET `project/{projectKey}`.
  ///
  /// Returns the project definition (key, name, lead, styles, …).
  Future<Map<String, dynamic>> getProjectDetails(String projectKey) async {
    final body = await _http.get('project/$projectKey');
    return _decodeMap(body);
  }

  /// `jira_get_project_statuses` — GET `project/{project}/statuses`.
  ///
  /// Returns the per-issue-type status mappings for [project].
  Future<List<Map<String, dynamic>>> getProjectStatuses(String project) async {
    final body = await _http.get('project/$project/statuses');
    return _decodeList(body);
  }
}
