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
String _updateFieldsByName(
  _JiraSyncConfig config,
  String key,
  String field,
  Object? coerced,
) {
  final listing = _fieldsListing(config, jiraProjectKeyOf(key));
  final fieldIds =
      _resolveActiveFieldIds(findAllJiraFieldsByName(field, listing));
  if (fieldIds.isEmpty) {
    return jsonEncode("No fields found with name '$field'");
  }
  if (fieldIds.length == 1) {
    return _singleFieldUpdateResult(config, key, field, fieldIds.single,
        coerced);
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

/// The single-field outcome: Java's success/failure sentence without the
/// per-field ✅/❌ lines.
String _singleFieldUpdateResult(
  _JiraSyncConfig config,
  String key,
  String field,
  String fieldId,
  Object? coerced,
) {
  final failure = _performFieldUpdate(config, key, fieldId, coerced);
  return jsonEncode(failure == null
      ? "Field '$field' updated successfully on ticket $key"
      : "Failed to update field '$field' on ticket $key");
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
String _fieldsListing(_JiraSyncConfig config, String project) {
  final direct = SyncHttpClient.get(
    '${config.baseUrl}/field',
    headers: config.headers,
  );
  if (direct.isOk) return direct.body;
  final url = '${config.baseUrl}/issue/createmeta'
      '?projectKeys=${Uri.encodeQueryComponent(project)}'
      '&expand=projects.issuetypes.fields';
  return SyncHttpClient.get(url, headers: config.headers).body;
}
