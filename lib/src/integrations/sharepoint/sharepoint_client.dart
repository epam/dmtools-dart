/// High-level SharePoint API client — ports the SharePoint MCP tool methods.
///
/// SharePoint targets the same Microsoft Graph API as Teams, so this client
/// reuses [TeamsHttpClient] as its transport (shared bearer auth + base URL).
/// Methods shape requests and parse JSON into typed results.
library;

import 'dart:convert';

import '../teams/teams_http_client.dart';

/// SharePoint API methods exposed to the MCP tool runtime.
class SharepointClient {
  final TeamsHttpClient _http;

  /// Creates a client backed by [_http].
  SharepointClient(this._http);

  /// URL-encodes a drive identifier for safe path-segment use.
  String _encodeId(String id) => Uri.encodeComponent(id);

  /// `sharepoint_test` — connectivity check via GET `me/drive`.
  ///
  /// Returns the OneDrive display name on success, or an error map on
  /// failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final drive = await getDrive();
      return {
        'success': true,
        'message': 'SharePoint connection successful',
        'drive': drive['name'] ?? drive['id'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'SharePoint connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `sharepoint_get_drive` — GET `me/drive`.
  ///
  /// Returns the decoded Graph drive object, or an empty map for non-object
  /// bodies.
  Future<Map<String, dynamic>> getDrive() async {
    final body = await _http.get('me/drive');
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  /// `sharepoint_list_files` — GET `drives/{driveId}/root/children`.
  ///
  /// Returns the decoded Graph response object (contains `value`), or an
  /// empty map for non-object bodies.
  Future<Map<String, dynamic>> listFiles(String driveId) async {
    final body = await _http.get('drives/${_encodeId(driveId)}/root/children');
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  /// `sharepoint_get_file` — GET `drives/{driveId}/items/{itemId}/content`.
  ///
  /// Returns the raw file content as a string.
  Future<String> getFile(String driveId, String itemId) async {
    return _http.get(
      'drives/${_encodeId(driveId)}/items/${_encodeId(itemId)}/content',
    );
  }

  /// `sharepoint_upload_file` — PUT
  /// `drives/{driveId}/items/{folderId}:/{fileName}:/content`.
  ///
  /// Uploads [content] as [fileName] under the folder identified by
  /// [folderId]. Returns the decoded Graph driveItem object, or an empty
  /// map for non-object bodies.
  Future<Map<String, dynamic>> uploadFile(
    String driveId,
    String folderId,
    String fileName,
    String content,
  ) async {
    final result = await _http.put(
      'drives/${_encodeId(driveId)}/items/${_encodeId(folderId)}:/'
      '${_encodeId(fileName)}:/content',
      body: content,
    );
    final decoded = jsonDecode(result);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }

  /// `sharepoint_create_folder` — POST
  /// `drives/{driveId}/items/{parentId}/children`.
  ///
  /// Creates a folder named [name] under the parent item [parentId].
  /// Returns the decoded Graph driveItem object, or an empty map for
  /// non-object bodies.
  Future<Map<String, dynamic>> createFolder(
    String driveId,
    String parentId,
    String name,
  ) async {
    final result = await _http.post(
      'drives/${_encodeId(driveId)}/items/${_encodeId(parentId)}/children',
      body: jsonEncode({
        'name': name,
        'folder': {},
        '@microsoft.graph.conflictBehavior': 'fail',
      }),
    );
    final decoded = jsonDecode(result);
    if (decoded is Map<String, dynamic>) return decoded;
    return const {};
  }
}
