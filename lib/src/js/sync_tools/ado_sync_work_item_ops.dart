/// Synchronous ADO ticket-operation executors for the JS agent bridge.
///
/// Ports the tracker-agnostic work-item tools of Java `AzureDevOpsClient`
/// (dm.ai #661/#663) that `js/common/trackers.js` calls: comments, state,
/// assignment, create (+ parent link), link, description/tags/field/priority
/// updates, field-code lookup and file attachment. Pure mapping logic lives
/// in `ado_work_item_ops.dart` (shared with the async client).
library;

import 'dart:convert';
import 'dart:io';

import '../../integrations/ado/ado_work_item_ops.dart';
import '../sync_http_client.dart';
import 'sync_binary_upload.dart';
import 'sync_request_helpers.dart';

/// Connection config for the sync ADO client: `baseUrl` is
/// `{ADO_BASE_PATH}/{org}/{project}/_apis`.
typedef AdoSyncConfig = ({String baseUrl, Map<String, String> headers});

/// Executor receiving resolved [AdoSyncConfig] plus the raw tool args.
typedef AdoSyncExecutor = String Function(
  AdoSyncConfig config,
  Map<String, dynamic> args,
);

const _apiVersion = '7.0';
const _patchType = 'application/json-patch+json';

/// The work-item operation executors keyed by canonical `ado_*` tool name.
final Map<String, AdoSyncExecutor> adoWorkItemOpExecutors = {
  'ado_add_work_item_comment': _addComment,
  'ado_get_work_item_comments': _getComments,
  'ado_move_to_state': (c, a) =>
      _setField(c, a, 'System.State', adoArg(a, ['state', 'statusName'])),
  'ado_get_work_item_type_states': _getWorkItemTypeStates,
  'ado_assign_work_item': (c, a) => _setField(
      c, a, 'System.AssignedTo', adoArg(a, ['userEmail', 'accountId'])),
  'ado_get_user_by_email': _getUserByEmail,
  'ado_update_description': (c, a) => _setField(
      c, a, 'System.Description', adoArg(a, ['description']),
      markdown: _isMarkdown(a)),
  'ado_update_tags': (c, a) =>
      _setField(c, a, 'System.Tags', adoArg(a, ['tags'])),
  'ado_update_field': _updateField,
  'ado_set_priority': _setPriority,
  'ado_create_work_item': _createWorkItem,
  'ado_link_work_items': _linkWorkItems,
  'ado_get_field_code': _getFieldCode,
  'ado_attach_file': _attachFile,
};

String _itemUrl(AdoSyncConfig c, String id) =>
    '${c.baseUrl}/wit/workitems/$id?api-version=$_apiVersion';

Map<String, String> _patchHeaders(AdoSyncConfig c) =>
    {...c.headers, 'Content-Type': _patchType};

/// The organization root (`{base}/{org}`) derived from the project base URL.
String _orgUrl(AdoSyncConfig c) {
  final projectUrl = c.baseUrl.substring(0, c.baseUrl.length - '/_apis'.length);
  return projectUrl.substring(0, projectUrl.lastIndexOf('/'));
}

/// Base URL for the VSSPS host (`{base}/{org}/_apis` for local http test
/// servers, `https://vssps.dev.azure.com/{org}/_apis` otherwise).
String _vsspsUrl(AdoSyncConfig c) {
  final orgUrl = _orgUrl(c);
  if (orgUrl.startsWith('http://')) return '$orgUrl/_apis';
  final orgName = orgUrl.substring(orgUrl.lastIndexOf('/') + 1);
  return 'https://vssps.dev.azure.com/$orgName/_apis';
}

String _idOf(Map<String, dynamic> a) => adoArg(a, ['id', 'key']);

String _patch(AdoSyncConfig c, String id, String patchBody) {
  final resp = SyncHttpClient.patch(
    _itemUrl(c, id),
    headers: _patchHeaders(c),
    body: patchBody,
  );
  if (resp.statusCode == 400) {
    final structured = formatAdoFieldValidationError(resp.body);
    if (structured != null) return structured;
  }
  return syncBodyOrError(resp);
}

String _setField(
  AdoSyncConfig c,
  Map<String, dynamic> a,
  String field,
  String value, {
  bool markdown = false,
}) =>
    _patch(c, _idOf(a), adoFieldsPatch({field: value}, markdown: markdown));

/// Whether the optional `format` arg requests Markdown (see
/// [isAdoMarkdownFormat]).
bool _isMarkdown(Map<String, dynamic> a) => isAdoMarkdownFormat(a['format']);

String _commentsUrl(AdoSyncConfig c, String id) =>
    '${c.baseUrl}/wit/workItems/$id/comments?api-version=$_apiVersion-preview';

/// `ado_add_work_item_comment` — POST `{"text": comment}` (`text` alias);
/// `format=markdown` query param when requested.
String _addComment(AdoSyncConfig c, Map<String, dynamic> a) =>
    syncBodyOrError(SyncHttpClient.post(
      _commentsUrl(c, _idOf(a)) + (_isMarkdown(a) ? '&format=markdown' : ''),
      headers: c.headers,
      body: jsonEncode({
        'text': adoArg(a, ['comment', 'text'])
      }),
    ));

/// `ado_get_work_item_comments` — GET comments, returning the bare array.
String _getComments(AdoSyncConfig c, Map<String, dynamic> a) {
  final body = syncBodyOrError(
      SyncHttpClient.get(_commentsUrl(c, _idOf(a)), headers: c.headers));
  final decoded = syncTryDecode(body);
  if (decoded is Map && decoded['comments'] is List) {
    return jsonEncode(decoded['comments']);
  }
  return body;
}

/// `ado_update_field` — PATCH the field resolved via [resolveAdoFieldName].
String _updateField(AdoSyncConfig c, Map<String, dynamic> a) => _setField(
    c, a, resolveAdoFieldName(adoArg(a, ['field'])), adoArg(a, ['value']),
    markdown: _isMarkdown(a));

/// `ado_set_priority` — PATCH `Microsoft.VSTS.Common.Priority` with a number.
String _setPriority(AdoSyncConfig c, Map<String, dynamic> a) {
  final int number;
  try {
    number = mapAdoPriority(adoArg(a, ['priority']));
  } on ArgumentError catch (e) {
    return syncErr('${e.message}');
  }
  return _patch(
      c, _idOf(a), adoFieldsPatch({'Microsoft.VSTS.Common.Priority': number}));
}

/// `ado_link_work_items` — PATCH an `/relations/-` add on the source item.
String _linkWorkItems(AdoSyncConfig c, Map<String, dynamic> a) {
  final source = adoArg(a, ['sourceId', 'sourceKey']);
  final target = adoArg(a, ['targetId', 'anotherKey']);
  return _link(c, source, target, adoArg(a, ['relationship']));
}

String _link(AdoSyncConfig c, String source, String target, String rel) =>
    _patch(
        c,
        source,
        adoRelationPatch(
          mapAdoRelationship(rel),
          // Java: basePath + "/_apis/wit/workItems/" + targetId (org-scoped).
          '${_orgUrl(c)}/_apis/wit/workItems/$target',
        ));

/// `ado_create_work_item` — JSON-Patch POST, then an optional parent link.
String _createWorkItem(AdoSyncConfig c, Map<String, dynamic> a) {
  final project = adoArg(a, ['project']);
  final type = adoArg(a, ['workItemType', 'issueType', 'type']);
  final fieldsJson = _fieldsJson(a['fieldsJson']);
  if (fieldsJson is String) return syncErr(fieldsJson);
  final base = project.isEmpty
      ? c.baseUrl
      : '${_orgUrl(c)}/${Uri.encodeComponent(project)}/_apis';
  final description = adoArg(a, ['description']);
  final response = syncBodyOrError(SyncHttpClient.post(
    // The type goes into the PATH: 'User Story' has a space, which curl rejects (exit 3) —
    // Java's OkHttp encoded it implicitly.
    '$base/wit/workitems/\$${Uri.encodeComponent(type)}?api-version=$_apiVersion',
    headers: _patchHeaders(c),
    body: adoCreatePatch(adoArg(a, ['title', 'summary']), description,
        fieldsJson as Map<String, dynamic>?,
        markdown: _isMarkdown(a)),
  ));
  final parent = adoArg(a, ['parentId', 'parentKey']).trim();
  if (parent.isEmpty) return response;
  final created = syncTryDecode(response);
  final id = created is Map ? created['id'] : null;
  if (id == null) {
    return syncErr('Work item was created but the response carries no id, '
        'cannot link parent $parent');
  }
  // source = parent, target = child -> Hierarchy-Forward on the parent.
  final linked = _link(c, parent, '$id', 'child');
  return _isError(linked) ? linked : response;
}

/// Whether [body] is a single-key `{"error": …}` envelope.
bool _isError(String body) {
  final decoded = syncTryDecode(body);
  return decoded is Map && decoded.length == 1 && decoded['error'] != null;
}

/// `fieldsJson` as a map, `null` when absent, or an error message string.
Object? _fieldsJson(dynamic raw) {
  if (raw == null || raw == '') return null;
  final decoded = raw is String ? syncTryDecode(raw) : raw;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return 'fieldsJson must be a JSON object';
}

/// `ado_get_field_code` — GET `{org}/{project}/_apis/wit/fields`.
String _getFieldCode(AdoSyncConfig c, Map<String, dynamic> a) {
  final wanted = adoArg(a, ['fieldName']).trim();
  if (wanted.isEmpty) return 'null';
  final project = adoArg(a, ['project']).trim();
  final base = project.isEmpty
      ? c.baseUrl
      : '${_orgUrl(c)}/${Uri.encodeComponent(project)}/_apis';
  final body = syncBodyOrError(SyncHttpClient.get(
    '$base/wit/fields?api-version=$_apiVersion',
    headers: c.headers,
  ));
  if (syncTryDecode(body) is! Map) return 'null';
  return jsonEncode(findAdoFieldCode(body, wanted));
}

/// `ado_get_work_item_type_states` — GET
/// `{org}/{project}/_apis/wit/workitemtypes/{type}/states?api-version=7.0`.
String _getWorkItemTypeStates(AdoSyncConfig c, Map<String, dynamic> a) {
  final type = adoArg(a, ['workItemType', 'issueType', 'type']).trim();
  if (type.isEmpty) return syncErr('workItemType must not be empty');
  final project = adoArg(a, ['project']).trim();
  final base = project.isEmpty
      ? c.baseUrl
      : '${_orgUrl(c)}/${Uri.encodeComponent(project)}/_apis';
  final encodedType = Uri.encodeComponent(type);
  return syncBodyOrError(SyncHttpClient.get(
    '$base/wit/workitemtypes/$encodedType/states?api-version=$_apiVersion',
    headers: c.headers,
  ));
}

/// `ado_attach_file` — idempotent upload + `AttachedFile` relation.
String _attachFile(AdoSyncConfig c, Map<String, dynamic> a) {
  final id = _idOf(a);
  final name = adoArg(a, ['name']);
  final filePath = adoArg(a, ['filePath']);
  final file = File(filePath);
  if (!file.existsSync()) return syncErr('File does not exist: $filePath');
  final existing = syncTryDecode(syncBodyOrError(SyncHttpClient.get(
      '${c.baseUrl}/wit/workitems/$id?\$expand=relations'
      '&api-version=$_apiVersion',
      headers: c.headers)));
  if (!adoHasAttachment(existing, name)) {
    final url = _upload(c, name, file);
    if (url == null) {
      return syncErr('ADO attachment upload returned no url for $name');
    }
    final linked = _patch(c, id,
        adoRelationPatch('AttachedFile', url, attributes: {'name': name}));
    if (_isError(linked)) return linked;
  }
  return jsonEncode({'status': 'success', 'id': id, 'name': name});
}

/// Uploads [file] as an ADO attachment, returning its url (or `null`).
String? _upload(AdoSyncConfig c, String name, File file) {
  final resp = syncCurlUpload(
    '${c.baseUrl}/wit/attachments?fileName=${Uri.encodeQueryComponent(name)}'
    '&api-version=$_apiVersion',
    {...c.headers, 'Content-Type': 'application/octet-stream'},
    file,
    tempPrefix: 'dmtools_ado_upload_',
  );
  final decoded = syncTryDecode(syncBodyOrError(resp));
  final url = decoded is Map ? decoded['url'] : null;
  return url is String && url.isNotEmpty ? url : null;
}

/// `ado_get_user_by_email` — paginated Graph `/_apis/graph/users` with an
/// Identities `/_apis/identities` fallback (dm.ai #814).
String _getUserByEmail(AdoSyncConfig c, Map<String, dynamic> a) {
  final email = adoArg(a, ['email']).trim();
  if (email.isEmpty) return syncErr('email must not be empty');
  final vssps = _vsspsUrl(c);
  final graphUser = _searchGraphUsersSync(c, vssps, email);
  if (graphUser != null) return jsonEncode(graphUser);
  return _findUserViaIdentitiesSync(c, vssps, email);
}

Map<String, dynamic>? _searchGraphUsersSync(
    AdoSyncConfig c, String vssps, String email) {
  final seen = <String>{};
  String? token;
  for (var page = 0; page < 100; page++) {
    final q = token == null
        ? ''
        : '&continuationToken=${Uri.encodeQueryComponent(token)}';
    final resp = SyncHttpClient.get(
        '$vssps/graph/users?api-version=7.1-preview.1$q',
        headers: c.headers);
    if (!resp.isOk) return null;
    final hdr = resp.headers['X-MS-ContinuationToken'] ??
        resp.headers['x-ms-continuationtoken'];
    final parsed = parseAdoGraphUsersPage(resp.body, email, headerToken: hdr);
    if (parsed.user != null) return parsed.user;
    final next = parsed.nextToken;
    if (next == null || !seen.add(next)) return null;
    token = next;
  }
  return null;
}

String _findUserViaIdentitiesSync(AdoSyncConfig c, String vssps, String email) {
  final q = Uri.encodeQueryComponent(email);
  final resp = SyncHttpClient.get(
    '$vssps/identities?searchFilter=MailAddress&filterValue=$q&api-version=7.1-preview.1',
    headers: c.headers,
  );
  if (resp.isOk) {
    final parsed = parseAdoIdentitiesFallback(resp.body, email);
    if (parsed.user != null) return jsonEncode(parsed.user);
    if (parsed.graphDescriptor != null) {
      final g = SyncHttpClient.get(
        '$vssps/graph/users/${parsed.graphDescriptor}?api-version=7.1-preview.1',
        headers: c.headers,
      );
      if (g.isOk) return g.body;
    }
  }
  return syncErr('User not found with email: $email');
}
