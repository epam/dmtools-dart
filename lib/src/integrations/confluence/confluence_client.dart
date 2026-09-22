/// High-level Confluence Cloud API client — ports the top MCP tool methods.
///
/// Each method corresponds to a `@MCPTool`-annotated method on the Java
/// `ConfluenceClient`. Transport is delegated to [ConfluenceHttpClient];
/// this layer shapes requests and parses JSON into typed results.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'confluence_http_client.dart';

import 'confluence_markdown.dart';
import 'confluence_page_url.dart';

part 'confluence_client_transfer.dart';

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

  /// The `CONFLUENCE_DEFAULT_SPACE` value backing the default-space tools
  /// (`confluence_find_content`, `confluence_find_or_create`,
  /// `confluence_content_by_title`); `null` when unset.
  final String? defaultSpace;

  /// Creates a client backed by [_http].
  ConfluenceClient(this._http, {this.defaultSpace});

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
  /// [body]; returns the created page object from the API. [parentId] nests
  /// the page under an ancestor (Java `createPage` overload).
  Future<Map<String, dynamic>> createPage(
    String spaceKey,
    String title,
    String body, {
    String? parentId,
  }) async {
    final responseBody = await _http.post(
      'content',
      body: jsonEncode(_pagePayload(spaceKey, title, body, parentId)),
    );
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  /// Builds the page creation/update payload.
  Map<String, dynamic> _pagePayload(
    String spaceKey,
    String title,
    String body, [
    String? parentId,
  ]) =>
      {
        'type': 'page',
        'title': title,
        'space': {'key': spaceKey},
        if (parentId != null && parentId.isNotEmpty)
          'ancestors': [
            {'id': parentId},
          ],
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

  // ── gh-191: Java-named tools from the frozen gap snapshot ────────────────

  /// `confluence_content_by_title` — GET `content?title=&expand=…` in the
  /// configured default space (Java `contentByTitleInDefaultSpace`).
  ///
  /// Returns the full listing response; [format] `md`/`markdown` converts
  /// every result's storage body to Markdown in place.
  Future<Map<String, dynamic>> contentByTitle(
    String title, [
    String? format,
  ]) async {
    final space = defaultSpace;
    if (space == null) {
      throw StateError('Default space not set');
    }
    return contentByTitleAndSpace(title, space, format);
  }

  /// `confluence_content_by_title_and_space` — GET
  /// `content?title=&spaceKey=&expand=…` (Java `content`).
  Future<Map<String, dynamic>> contentByTitleAndSpace(
    String title,
    String space, [
    String? format,
  ]) async {
    final body = await _http.get('content', queryParams: {
      'expand': 'body.storage,body.export_view,ancestors,version',
      'title': title,
      if (space.isNotEmpty) 'spaceKey': space,
    });
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    _applyFormat(_resultList(decoded), format);
    return decoded;
  }

  /// `confluence_find_content` — first match by title (in [space] or the
  /// configured default space), or `null` (Java `findContent`).
  Future<Map<String, dynamic>?> findContent(
    String title, {
    String? space,
    String? format,
  }) async {
    final effectiveSpace = space ?? defaultSpace;
    if (effectiveSpace == null) {
      throw StateError('Default space not set');
    }
    final listing = await contentByTitleAndSpace(title, effectiveSpace, null);
    final contents = _resultList(listing);
    if (contents.isEmpty) return null;
    _applyFormat([contents.first], format);
    return contents.first;
  }

  /// `confluence_find_or_create` — find by title in the default space or
  /// create under [parentId] (Java `findOrCreate`).
  Future<Map<String, dynamic>> findOrCreate(
    String title,
    String parentId,
    String body,
  ) async {
    final space = defaultSpace;
    if (space == null) {
      throw StateError('Default space not set');
    }
    final existing = await findContent(title, space: space);
    return existing ?? createPage(space, title, body, parentId: parentId);
  }

  /// `confluence_get_children_by_name` — children of the page found by
  /// title in [spaceKey] (Java `getChildrenOfContentByName`).
  Future<List<Map<String, dynamic>>> getChildrenByName(
    String spaceKey,
    String contentName, [
    String? format,
  ]) async {
    final parent = await findContent(contentName, space: spaceKey);
    if (parent == null) {
      throw StateError('Content not found: $contentName');
    }
    final children = await getContentChildren(parent['id'] as String);
    _applyFormat(children, format);
    return children;
  }

  /// `confluence_get_content_attachments` — GET
  /// `content/{contentId}/child/attachment` (Java `getContentAttachments`).
  Future<List<Map<String, dynamic>>> getContentAttachments(String contentId) =>
      getPageAttachments(contentId);

  /// `confluence_get_current_user_profile` — GET `user/current`.
  Future<Map<String, dynamic>> getCurrentUserProfile() async {
    final body = await _http.get('user/current');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_get_user_profile_by_id` — GET `user?accountId={userId}`.
  Future<Map<String, dynamic>> getUserProfileById(String userId) async {
    final body = await _http.get('user', queryParams: {'accountId': userId});
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// `confluence_search_content_by_text` — CQL `(title ~ … OR text ~ …)`
  /// search with the Java expand list (Java `searchContentByText`; the
  /// GraphQL fast path is not ported).
  Future<List<Map<String, dynamic>>> searchContentByText(
    String query, [
    int? limit,
  ]) =>
      _getList(
        'content/search',
        queryParams: {
          'cql':
              '(title ~ "$query" OR text ~ "$query") ORDER BY lastModified ASC',
          'limit': '${limit ?? 20}',
          'expand': 'title,body.excerpt,history,space,body.storage',
        },
      );

  /// `confluence_update_page_with_history` — [updatePage] whose bumped
  /// version message is [historyComment] (Java tool of the same name).
  Future<Map<String, dynamic>> updatePageWithHistory({
    required String contentId,
    required String title,
    required String parentId,
    required String body,
    required String space,
    required String historyComment,
  }) =>
      updatePage(contentId, title, parentId, body, space, historyComment);

  /// `confluence_contents_by_urls` — resolve each URL to its content,
  /// skipping failures like Java (`contentsByUrls`).
  Future<List<Map<String, dynamic>>> contentsByUrls(
    List<String> urlStrings, [
    String? format,
  ]) async {
    final contents = <Map<String, dynamic>>[];
    for (final url in urlStrings) {
      if (url.isEmpty) continue;
      try {
        final content = await contentByUrl(url);
        if (content != null) contents.add(content);
      } on Object {
        continue; // Java logs and continues on per-URL failures.
      }
    }
    _applyFormat(contents, format);
    return contents;
  }

  /// `contentByUrl` — resolves a Confluence page URL to its content object
  /// (Java `contentByUrl`): `/spaces/{s}/pages/{id}[/title]` direct ids,
  /// `/display/{s}/{title}` lookups, `/wiki/x/{key}` and `/l/…` short
  /// links resolved through their 3xx Location. Returns `null` for unknown
  /// URL shapes.
  Future<Map<String, dynamic>?> contentByUrl(String urlString) async {
    final parsed = Uri.tryParse(urlString);
    if (parsed == null) return null;
    final ref = await _resolveRef(parsed);
    if (ref is ConfluencePageIdRef) return getPageById(ref.id);
    if (ref is ConfluenceDisplayRef) {
      final listing = await contentByTitleAndSpace(ref.title, ref.space);
      final contents = _resultList(listing);
      return contents.isEmpty ? null : contents.first;
    }
    return null;
  }

  /// Resolves [uri] through short-link redirect hops (max 5, Java parity):
  /// each 3xx `Location` is followed and re-classified until a direct
  /// page-id / display ref (or an unknown shape) remains. Returns `null`
  /// when a hop fails or the hop budget is exhausted.
  Future<ConfluencePageRef?> _resolveRef(Uri uri) async {
    var current = uri;
    var ref = resolveConfluencePageUrl(current);
    var hops = 0;
    while (ref is ConfluenceRedirectRef && hops < 5) {
      hops++;
      final location = await _resolveRedirect(current);
      if (location == null) return null;
      final next = Uri.tryParse(location);
      if (next == null) return null;
      current = next;
      ref = resolveConfluencePageUrl(current);
    }
    return ref is ConfluenceRedirectRef ? null : ref;
  }

  /// Follows one 3xx hop for [uri], returning the `Location` URL, or `null`
  /// when the response is not a redirect (dio follows redirects by default;
  /// this disables that to mirror Java `resolveRedirect`).
  ///
  /// The probe travels authenticated (instances with anonymous access
  /// disabled answer 302 → login otherwise) and any non-redirect outcome —
  /// including a thrown 4xx/5xx — degrades to `null` so one dead short link
  /// never aborts a whole `downloadPages` call.
  Future<String?> _resolveRedirect(Uri uri) async {
    try {
      final response = await _http.dio.getUri<dynamic>(
        uri,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          headers: _http.headers,
        ),
      );
      final location = response.headers.value('location');
      return (response.statusCode != null &&
              response.statusCode! >= 300 &&
              response.statusCode! < 400 &&
              location != null)
          ? location
          : null;
    } on DioException {
      return null;
    }
  }

  /// Decodes a dio response body that may arrive as String or JSON.
  Map<String, dynamic>? _decodeDioBody(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    }
    return null;
  }

  /// Applies the Java `applyFormat` contract: converts each content's
  /// storage body to Markdown in place when [format] is `md`/`markdown`.
  static void _applyFormat(
      List<Map<String, dynamic>> contents, String? format) {
    final f = format?.toLowerCase();
    if (f != 'md' && f != 'markdown') return;
    for (final content in contents) {
      final body = content['body'];
      final storage = body is Map ? body['storage'] : null;
      if (storage is! Map || storage['value'] is! String) continue;
      body.remove('export_view'); // redundant once Markdown is returned
      storage['value'] =
          confluenceStorageToMarkdown(storage['value'] as String);
      storage['representation'] = 'markdown';
    }
  }

  /// Filesystem-safe file name from a page title.
  static String _sanitizeFileName(String title) =>
      title.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();

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
