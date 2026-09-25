part of 'confluence_sync_tools.dart';

/// Shared low-level helpers of the Confluence sync executors: blocking HTTP
/// tails, request-payload builders, and the storage→Markdown response
/// formatting shared by the read/write handlers.

/// GETs [url] with the resolved config's auth headers and returns the body
/// verbatim (the shared tail of the read-only handlers).
String _syncGetBody(_Conf config, String url) =>
    syncBodyOrError(SyncHttpClient.get(url, headers: config.headers));

/// The local [path] as a `Directory`, `null` when it does not exist (the
/// shared guard of the directory-consuming handlers).
Directory? _existingDir(String path) {
  final dir = Directory(path);
  return dir.existsSync() ? dir : null;
}

/// GETs `content/{suffix}` with the resolved config's auth headers.
SyncHttpResponse _contentGet(_Conf config, String suffix) =>
    SyncHttpClient.get('${config.baseUrl}/content/$suffix',
        headers: config.headers);

/// Builds the `content` request payload shared by page create/update
/// (Java wire format: [id]/version keys appear only when given).
Map<String, dynamic> _contentPayload({
  String? id,
  required String title,
  required String parentId,
  required String body,
  required String space,
  Map<String, dynamic>? version,
}) =>
    {
      if (id != null) 'id': id,
      'type': 'page',
      'title': title,
      'ancestors': [
        {'id': parentId},
      ],
      'space': {'key': space},
      if (version != null) 'version': version,
      'body': {
        'storage': {'value': body, 'representation': 'storage'},
      },
    };

/// GETs `content/{contentId}?expand=version`.
SyncHttpResponse _versionResponse(_Conf config, String contentId) =>
    SyncHttpClient.get(
      '${config.baseUrl}/content/$contentId?expand=version',
      headers: config.headers,
    );

/// Reads `version.number` from a `?expand=version` response; `null` when
/// the response failed or carries no numeric version.
int? _versionNumberOf(SyncHttpResponse resp) {
  if (!resp.isOk) return null;
  final decoded = syncTryDecode(resp.body);
  if (decoded is! Map) return null;
  final version = decoded['version'];
  if (version is Map && version['number'] is num) {
    return (version['number'] as num).toInt();
  }
  return null;
}

/// The `results` page list of a children response; `null` when the body is
/// not a results object.
List<Map<String, dynamic>>? _childrenResults(String body) {
  final decoded = syncTryDecode(body);
  if (decoded is! Map || decoded['results'] is! List) return null;
  return (decoded['results'] as List)
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList();
}

/// Whether [format] requests Markdown conversion (Java `isMarkdownFormat`).
bool _isMarkdownFormat(dynamic format) {
  final f = format?.toString().toLowerCase() ?? '';
  return f == 'md' || f == 'markdown';
}

/// Applies the Java `applyFormat` contract to a JSON response body string:
/// converts `body.storage.value` to Markdown when requested.
String _applyFormat(String body, dynamic format) {
  if (!_isMarkdownFormat(format)) return body;
  final decoded = syncTryDecode(body);
  if (decoded is! Map<String, dynamic>) return body;
  _convertStorageToMarkdown(decoded);
  return jsonEncode(decoded);
}

/// Converts one content object's storage body to Markdown, in place.
void _convertStorageToMarkdown(Map<String, dynamic> content) {
  final body = content['body'];
  if (body is! Map) return;
  final storage = body['storage'];
  if (storage is! Map || storage['value'] is! String) return;
  body.remove('export_view'); // large, redundant once Markdown is returned
  storage['value'] = confluenceStorageToMarkdown(storage['value'] as String);
  storage['representation'] = 'markdown';
}
