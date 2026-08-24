/// High-level Confluence Cloud API client — ports the top MCP tool methods.
///
/// Each method corresponds to a `@MCPTool`-annotated method on the Java
/// `ConfluenceClient`. Transport is delegated to [ConfluenceHttpClient];
/// this layer shapes requests and parses JSON into typed results.
library;

import 'dart:convert';

import 'confluence_http_client.dart';

/// The mutable page fields of an update (Java `updatePage` params).
typedef _PageUpdateSpec = ({
  String title,
  String parentId,
  String body,
  String space,
  String historyComment,
});

/// Confluence Cloud API methods exposed to the MCP tool runtime.
class ConfluenceClient {
  final ConfluenceHttpClient _http;

  /// Creates a client backed by [_http].
  ConfluenceClient(this._http);

  /// `confluence_test` — connectivity check via GET `user/current`.
  ///
  /// Returns `success: true` with the user profile on success, or
  /// `success: false` with the error message on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get('user/current');
      final user = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'Confluence connection successful',
        'user': user['displayName'] ?? '',
        'email': user['email'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Confluence connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `confluence_get_page` — GET `content?spaceKey=&title=&expand=body.storage`.
  ///
  /// Returns the first matching page, or `null` when no page is found.
  Future<Map<String, dynamic>?> getPage(
    String spaceKey,
    String title,
  ) async {
    final body = await _http.get(
      'content',
      queryParams: {
        'spaceKey': spaceKey,
        'title': title,
        'expand': 'body.storage',
      },
    );
    final results = _resultList(jsonDecode(body) as Map<String, dynamic>);
    if (results.isEmpty) return null;
    return results.first;
  }

  /// `confluence_create_page` — POST `content`.
  ///
  /// Creates a new page in [spaceKey] with the given [title] and storage-format
  /// [body]; returns the created page object from the API.
  Future<Map<String, dynamic>> createPage(
    String spaceKey,
    String title,
    String body,
  ) async {
    final responseBody = await _http.post(
      'content',
      body: jsonEncode(_pagePayload(spaceKey, title, body)),
    );
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  /// Builds the page creation/update payload.
  Map<String, dynamic> _pagePayload(
    String spaceKey,
    String title,
    String body,
  ) =>
      {
        'type': 'page',
        'title': title,
        'space': {'key': spaceKey},
        'body': {
          'storage': {'value': body, 'representation': 'storage'},
        },
      };

  /// `confluence_update_page` — PUT `content/{id}` with a bumped version.
  ///
  /// Ports the Java `updatePage`: the current version is fetched first and
  /// re-sent as `current + 1`; the page is re-parented under [parentId] and
  /// kept in [space]. An optional [historyComment] lands in the version
  /// message (Java `confluence_update_page_with_history`).
  Future<Map<String, dynamic>> updatePage(
    String contentId,
    String title,
    String parentId,
    String body,
    String space, [
    String historyComment = '',
  ]) async {
    final current = await _fetchVersion(contentId);
    final responseBody = await _http.put(
      'content/$contentId',
      body: jsonEncode(_updatePayload(
        contentId,
        (
          title: title,
          parentId: parentId,
          body: body,
          space: space,
          historyComment: historyComment,
        ),
        current + 1,
      )),
    );
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  /// Fetches the current version number of [contentId] (Java `updatePage`).
  Future<int> _fetchVersion(String contentId) async {
    final body = await _http.get('content/$contentId', queryParams: {
      'expand': 'version',
    });
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final version = decoded['version'] as Map<String, dynamic>?;
    return (version?['number'] as num?)?.toInt() ?? 0;
  }

  /// Builds the page update payload including the bumped version number.
  Map<String, dynamic> _updatePayload(
    String id,
    _PageUpdateSpec page,
    int version,
  ) =>
      {
        'id': id,
        'type': 'page',
        'title': page.title,
        'ancestors': [
          {'id': page.parentId},
        ],
        'space': {'key': page.space},
        'version': {'number': version, 'message': page.historyComment},
        'body': {
          'storage': {'value': page.body, 'representation': 'storage'},
        },
      };

  /// `confluence_search` — GET `content/search?cql=`.
  ///
  /// Returns the list of search results for the given CQL [query].
  Future<List<Map<String, dynamic>>> search(String query) =>
      _getList('content/search', queryParams: {'cql': query});

  /// `confluence_get_spaces` — GET `space`.
  ///
  /// Returns all spaces visible to the authenticated user.
  Future<List<Map<String, dynamic>>> getSpaces() => _getList('space');

  /// `confluence_get_space_by_key` — GET `space/{spaceKey}`.
  ///
  /// Returns the single space identified by [spaceKey].
  Future<Map<String, dynamic>> getSpaceByKey(String spaceKey) async {
    final body = await _http.get('space/$spaceKey');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_update_space` — PUT `space/{spaceKey}`.
  ///
  /// Updates the [name] and [description] of the space with [spaceKey];
  /// returns the updated space object from the API.
  Future<Map<String, dynamic>> updateSpace(
    String spaceKey,
    String name,
    String description,
  ) async {
    final body = await _http.put(
      'space/$spaceKey',
      body: jsonEncode(_spacePayload(name, description)),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_page_by_id` / `confluence_content_by_id` — GET
  /// `content/{id}?expand=body.storage,body.export_view,ancestors,version`.
  ///
  /// Returns the page with [id] including its storage body, export view,
  /// ancestors, and version (the Java `contentById` expand list).
  Future<Map<String, dynamic>> getPageById(String id) async {
    final body = await _http.get(
      'content/$id',
      queryParams: {
        'expand': 'body.storage,body.export_view,ancestors,version'
      },
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_delete_page` — DELETE `content/{id}`.
  ///
  /// Deletes the page with [id]; returns `{}` on an empty response body (the
  /// normal case) or the decoded body otherwise.
  Future<Map<String, dynamic>> deletePage(String id) async {
    final body = await _http.delete('content/$id');
    return body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_page_attachments` — GET `content/{id}/child/attachment`.
  ///
  /// Returns the attachments of the page with [pageId].
  Future<List<Map<String, dynamic>>> getPageAttachments(String pageId) =>
      _getList('content/$pageId/child/attachment');

  /// `confluence_download_attachment` — GET
  /// `content/{pageId}/child/attachment/{attachmentId}/download`.
  ///
  /// Downloads the raw content of [attachmentId] attached to [pageId].
  Future<String> downloadAttachment(String pageId, String attachmentId) {
    return _http.get(
      'content/$pageId/child/attachment/$attachmentId/download',
    );
  }

  /// `confluence_add_label` — POST `content/{id}/label`.
  ///
  /// Adds [label] (global prefix) to the page with [pageId]; returns the
  /// response containing the created label entries.
  Future<Map<String, dynamic>> addLabel(String pageId, String label) async {
    final body = await _http.post(
      'content/$pageId/label',
      body: jsonEncode([_labelPayload(label)]),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_labels` — GET `content/{id}/label`.
  ///
  /// Returns the labels on the page with [pageId].
  Future<List<Map<String, dynamic>>> getLabels(String pageId) =>
      _getList('content/$pageId/label');

  /// `confluence_get_blog_posts` — GET `content?type=blogpost&spaceKey=`.
  ///
  /// Returns the blog posts in the space with [spaceKey].
  Future<List<Map<String, dynamic>>> getBlogPosts(String spaceKey) =>
      _getList('content',
          queryParams: {'type': 'blogpost', 'spaceKey': spaceKey});

  /// `confluence_get_content_children` — GET `content/{id}/child/page`.
  ///
  /// Returns the direct child pages of the page with [id].
  Future<List<Map<String, dynamic>>> getContentChildren(String id) =>
      _getList('content/$id/child/page');

  /// `confluence_move_page` — PUT `content/{pageId}/move`.
  ///
  /// Moves the page with [pageId] to become a child of [targetId]; returns
  /// `{}` on an empty response body or the decoded body otherwise.
  Future<Map<String, dynamic>> movePage(String pageId, String targetId) async {
    final body = await _http.put(
      'content/$pageId/move',
      body: jsonEncode(_movePayload(targetId)),
    );
    return body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_page_history` — GET `content/{pageId}/version`.
  ///
  /// Returns the version history of the page with [pageId].
  Future<List<Map<String, dynamic>>> getPageHistory(String pageId) =>
      _getList('content/$pageId/version');

  /// `confluence_get_permissions` — GET `space/{spaceKey}/content/permission`.
  ///
  /// Returns the content permissions for the space with [spaceKey].
  Future<List<Map<String, dynamic>>> getPermissions(String spaceKey) =>
      _getList('space/$spaceKey/content/permission');

  /// `confluence_add_permission` — POST `space/{spaceKey}/permission`.
  ///
  /// Adds [permission] to the space with [spaceKey]; returns the created
  /// permission entry from the API.
  Future<Map<String, dynamic>> addPermission(
    String spaceKey,
    Map<String, dynamic> permission,
  ) async {
    final body = await _http.post(
      'space/$spaceKey/permission',
      body: jsonEncode(permission),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_space_content` — GET `space/{key}/content/{type}`.
  ///
  /// Returns all content of [contentType] (e.g. `page`) in the space with
  /// [spaceKey], at every depth.
  Future<List<Map<String, dynamic>>> getSpaceContent(
    String spaceKey,
    String contentType,
  ) =>
      _getList('space/$spaceKey/content/$contentType',
          queryParams: {'depth': 'all'});

  /// `confluence_create_space` — POST `space`.
  ///
  /// Creates a new space with [key] and [name]; returns the created space
  /// object from the API.
  Future<Map<String, dynamic>> createSpace(String key, String name) async {
    final body = await _http.post(
      'space',
      body: jsonEncode(_createSpacePayload(key, name)),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_archive_page` — PUT `content/{id}` with status `archived`.
  ///
  /// Archives the page with [id]; returns the response object from the API.
  Future<Map<String, dynamic>> archivePage(String id) async {
    final body = await _http.put(
      'content/$id',
      body: jsonEncode(_statusPayload(id, 'archived')),
    );
    return body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_restore_page` — PUT `content/{id}` with status `current`.
  ///
  /// Restores a previously archived page with [id] back to current; returns
  /// the response object from the API.
  Future<Map<String, dynamic>> restorePage(String id) async {
    final body = await _http.put(
      'content/$id',
      body: jsonEncode(_statusPayload(id, 'current')),
    );
    return body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_page_properties` — GET `content/{id}/property`.
  ///
  /// Returns the content properties of the page with [id].
  Future<List<Map<String, dynamic>>> getPageProperties(String id) =>
      _getList('content/$id/property');

  /// `confluence_set_page_property` — POST `content/{id}/property`.
  ///
  /// Sets the content property [key] to [value] on the page with [id];
  /// returns the created property object from the API.
  Future<Map<String, dynamic>> setPageProperty(
    String id,
    String key,
    Map<String, dynamic> value,
  ) async {
    final body = await _http.post(
      'content/$id/property',
      body: jsonEncode(_propertyPayload(key, value)),
    );
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_group_members` — GET `group/{groupname}/member`.
  ///
  /// Returns the members of the group identified by [groupname].
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupname) =>
      _getList('group/$groupname/member');

  /// `confluence_get_user_by_key` — GET `user?key={key}`.
  ///
  /// Returns the user identified by [key] (the Confluence user key).
  Future<Map<String, dynamic>> getUserByKey(String key) async {
    final body = await _http.get('user', queryParams: {'key': key});
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_watchers` — GET `content/{contentId}/notification`.
  ///
  /// Returns the watchers (notifications) on the content with [contentId].
  Future<List<Map<String, dynamic>>> getWatchers(String contentId) =>
      _getList('content/$contentId/notification');

  /// GET helper: fetches [path] and returns its `results` array as typed maps.
  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    final body = await _http.get(path, queryParams: queryParams);
    return _resultList(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Parses the `results` array from a Confluence list response.
  List<Map<String, dynamic>> _resultList(Map<String, dynamic> decoded) {
    final results = decoded['results'] as List? ?? [];
    return List<Map<String, dynamic>>.from(
      results.map((r) => r as Map<String, dynamic>),
    );
  }

  /// Builds a single global-prefix label entry for POST `content/{id}/label`.
  Map<String, dynamic> _labelPayload(String label) =>
      {'prefix': 'global', 'name': label};

  /// Builds the space-update payload with a plain-text description.
  Map<String, dynamic> _spacePayload(String name, String description) => {
        'name': name,
        'description': {
          'plain': {'value': description, 'representation': 'plain'},
        },
      };

  /// Builds the move payload referencing the target page id.
  Map<String, dynamic> _movePayload(String targetId) => {
        'target': {'id': targetId}
      };

  /// Builds the create-space payload with [key] and [name].
  Map<String, dynamic> _createSpacePayload(String key, String name) =>
      {'key': key, 'name': name};

  /// Builds the status-change payload setting the page [status]
  /// (`archived` or `current`), shared by [archivePage] and [restorePage].
  Map<String, dynamic> _statusPayload(String id, String status) =>
      {'id': id, 'type': 'page', 'status': status};

  /// Builds the content-property payload for POST `content/{id}/property`.
  Map<String, dynamic> _propertyPayload(
    String key,
    Map<String, dynamic> value,
  ) =>
      {'key': key, 'value': value};
}
