part of 'jira_sync_tools.dart';

/// The `jira_update_field` engine (Java `updateField`, gh-191 P6-JSY-04).
///
/// Split out of `jira_sync_tools.dart` (crap4dart `loc` gate): pure
/// functions over [_JiraSyncConfig] that share the executor library's
/// helpers (`_asStr`, `_err`, `_putBody`, `_failureDetail`, …).

/// `jira_update_field` body: `""` clears the field
/// (`{fields:{field:null}}`, Java `clearField`); strings are coerced to
/// bool/int/double/JSON; `customfield_*` ids and system fields PUT
/// `{update:{field:[{set:v}]}}` directly; any other field name resolves to
/// ALL active customfields with that name and updates each with a `✅`/`❌`
/// per-field summary.
String _updateFieldFor(_JiraSyncConfig config, Map<String, dynamic> args) {
  final key = _asStr(args['key']);
  final field = _asStr(args['field']);
  final value = args['value'];
  if (value is String && value.isEmpty) {
    return _putBody(
        config,
        '${config.baseUrl}/issue/$key',
        jsonEncode({
          'fields': {field: null},
        }));
  }
  final coerced = coerceJiraFieldValue(value);
  if (field.startsWith('customfield_') ||
      systemJiraFields.contains(field.toLowerCase())) {
    final failure = _performFieldUpdate(config, key, field, coerced);
    if (failure != null) return _err(failure);
    return jsonEncode("Field '$field' updated successfully on ticket $key");
  }
  return _updateFieldsByName(config, key, field, coerced);
}

/// PUTs the update-verb payload for one field id.
///
/// Returns `null` on success, otherwise the failure detail (transport
/// error, HTTP status, or embedded Jira error object — Java
/// `validateFieldUpdateResponse`).
String? _performFieldUpdate(
  _JiraSyncConfig config,
  String key,
  String fieldId,
  Object? value,
) {
  final resp = SyncHttpClient.put(
    '${config.baseUrl}/issue/$key',
    headers: config.headers,
    body: jsonEncode({
      'update': {
        fieldId: [
          {'set': value},
        ],
      },
    }),
  );
  if (resp.statusCode == 0) return 'HTTP request failed: ${resp.body}';
  if (!resp.isOk) return _failureDetail('HTTP ${resp.statusCode}', resp);
  return jiraResponseErrorDetail(resp.body);
}

/// Resolves every active customfield id named [field] (Java
/// `getAllFieldCustomCodes` over the field listing, falling back to the
/// best-match single field) and updates each, mirroring the Java
/// `✅`/`❌` summary contract.
///
/// gh-403: resolution failures (field listing failed, no field with the
/// name) return an `{"error": …}` envelope — never a plain sentence the
/// caller cannot tell apart from a silent no-op.
String _updateFieldsByName(
  _JiraSyncConfig config,
  String key,
  String field,
  Object? coerced,
) {
  final listing = _fieldsListing(config, jiraProjectKeyOf(key));
  if (listing.error != null) {
    return _err("Failed to resolve field '$field': ${listing.error}");
  }
  final fieldIds = _resolveActiveFieldIds(
    findAllJiraFieldsByName(field, listing.body!),
  );
  if (fieldIds.isEmpty) {
    return _err("No fields found with name '$field'");
  }
  if (fieldIds.length == 1) {
    return _singleFieldUpdateResult(
        config, key, field, fieldIds.single, coerced);
  }
  return _multiFieldUpdateResult(config, key, field, fieldIds, coerced);
}

/// The active customfield ids among [matches] (Java
/// `getAllFieldCustomCodes`), falling back to the best-match single field
/// when none is active. Empty when [matches] itself is empty.
List<String> _resolveActiveFieldIds(List<JiraFieldCandidate> matches) {
  final fieldIds = [
    for (final f in matches)
      if (f.active) f.id,
  ];
  if (fieldIds.isNotEmpty) return fieldIds;
  final best = selectBestJiraField(matches);
  return best == null ? const [] : [best.id];
}

/// The single-field outcome: Java's success sentence, or an `{"error": …}`
/// envelope carrying the HTTP status and the full Jira error body.
///
/// gh-403: the failure detail used to be computed and then discarded for a
/// detail-free sentence ("Failed to update field 'X' on ticket Y").
String _singleFieldUpdateResult(
  _JiraSyncConfig config,
  String key,
  String field,
  String fieldId,
  Object? coerced,
) {
  final failure = _performFieldUpdate(config, key, fieldId, coerced);
  if (failure != null) {
    return _err("Failed to update field '$field' on ticket $key: $failure");
  }
  return jsonEncode("Field '$field' updated successfully on ticket $key");
}

/// The multi-field outcome: one `✅`/`❌` line per field, then the Java
/// `Updated N of M fields …` tail (with the failed count when non-zero).
String _multiFieldUpdateResult(
  _JiraSyncConfig config,
  String key,
  String field,
  List<String> fieldIds,
  Object? coerced,
) {
  final results = StringBuffer();
  var successCount = 0;
  for (final fieldId in fieldIds) {
    final failure = _performFieldUpdate(config, key, fieldId, coerced);
    if (failure == null) {
      successCount++;
      results.write('✅ Updated $fieldId\n');
    } else {
      results.write('❌ Failed $fieldId: $failure\n');
    }
  }
  results.write('\nUpdated $successCount of ${fieldIds.length} fields '
      "with name '$field' for ticket $key");
  final failureCount = fieldIds.length - successCount;
  if (failureCount > 0) results.write(' ($failureCount failed)');
  return jsonEncode(results.toString());
}

/// Fetches the field listing with the Java fallback chain: GET `field`;
/// on failure GET `issue/createmeta` with the project filter and fields
/// expansion.
///
/// Returns the listing [body], or the [error] detail when both legs fail
/// (gh-403: the failure used to flow into the name matcher and collapse to
/// a bare "No fields found with name …").
({String? body, String? error}) _fieldsListing(
  _JiraSyncConfig config,
  String project,
) {
  final direct = SyncHttpClient.get(
    '${config.baseUrl}/field',
    headers: config.headers,
  );
  if (direct.isOk) return (body: direct.body, error: null);
  final url = '${config.baseUrl}/issue/createmeta'
      '?projectKeys=${Uri.encodeQueryComponent(project)}'
      '&expand=projects.issuetypes.fields';
  final fallback = SyncHttpClient.get(url, headers: config.headers);
  if (fallback.isOk) return (body: fallback.body, error: null);
  return (
    body: null,
    error: '${_failureDetail('HTTP ${direct.statusCode}', direct)}; '
        'createmeta fallback: '
        '${_failureDetail('HTTP ${fallback.statusCode}', fallback)}',
  );
}

/// `jira_get_issue_types` engine (Java `JiraClient.getIssueTypes`, gh-479).
///
/// 1. `GET issue/createmeta?projectKeys=<project>&expand=projects.issuetypes.fields`
///    - extracts `projects[0].issuetypes` (or `issueTypes`) or top-level list.
/// 2. Fallback on error or empty result (Jira Server / Data Center):
///    - `GET project/<project>` (`issueTypes` / `issuetypes` list)
///    - `GET issuetype` (top-level list).
String _getIssueTypesFor(_JiraSyncConfig config, Map<String, dynamic> args) {
  final project = _asStr(args['project']);
  final metaUrl = '${config.baseUrl}/issue/createmeta'
      '?projectKeys=${Uri.encodeQueryComponent(project)}'
      '&expand=projects.issuetypes.fields';
  final metaResp = SyncHttpClient.get(metaUrl, headers: config.headers);
  if (metaResp.isOk) {
    final fromMeta = _extractCreateMetaIssueTypes(metaResp.body);
    if (fromMeta != null && fromMeta.isNotEmpty) {
      return jsonEncode(fromMeta);
    }
  }
  return _getServerIssueTypesFallback(config, project, metaResp);
}

/// Extracts the issue-types array from a `createmeta` response body, or
/// `null` when the body is neither a top-level list nor a `projects` object.
List<dynamic>? _extractCreateMetaIssueTypes(String body) {
  final decoded = _tryDecode(body);
  if (decoded is List) return decoded;
  if (decoded is! Map<String, dynamic>) return null;
  final projects = decoded['projects'];
  if (projects is List) return _extractFirstProjectIssueTypes(projects);
  return _extractDirectIssueTypesList(decoded);
}

List<dynamic> _extractFirstProjectIssueTypes(List<dynamic> projects) {
  if (projects.isEmpty) return const [];
  final first = projects.first;
  if (first is Map) {
    final types = _extractDirectIssueTypesList(first);
    if (types != null) return types;
  }
  return const [];
}

List<dynamic>? _extractDirectIssueTypesList(Map<dynamic, dynamic> map) {
  final direct = map['issuetypes'] ?? map['issueTypes'] ?? map['values'];
  return direct is List ? direct : null;
}

/// Jira Server / Data Center fallback for `jira_get_issue_types`: tries
/// `GET project/<project>` (`issueTypes`), then `GET issuetype`.
String _getServerIssueTypesFallback(
  _JiraSyncConfig config,
  String project,
  SyncHttpResponse metaResp,
) {
  final fromProject = _fetchProjectIssueTypes(config, project);
  if (fromProject != null) return jsonEncode(fromProject);
  final fromGlobal = _fetchGlobalIssueTypes(config);
  if (fromGlobal != null) return jsonEncode(fromGlobal);
  if (!metaResp.isOk) return _bodyOrError(metaResp);
  return jsonEncode(const <Object?>[]);
}

List<dynamic>? _fetchProjectIssueTypes(_JiraSyncConfig config, String project) {
  if (project.isEmpty) return null;
  final resp = SyncHttpClient.get(
    '${config.baseUrl}/project/${Uri.encodeComponent(project)}',
    headers: config.headers,
  );
  if (!resp.isOk) return null;
  final decoded = _tryDecode(resp.body);
  return decoded is Map ? _extractDirectIssueTypesList(decoded) : null;
}

List<dynamic>? _fetchGlobalIssueTypes(_JiraSyncConfig config) {
  final resp = SyncHttpClient.get(
    '${config.baseUrl}/issuetype',
    headers: config.headers,
  );
  if (!resp.isOk) return null;
  final decoded = _tryDecode(resp.body);
  return decoded is List ? decoded : null;
}
