/// High-level TestRail API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a TestRail API endpoint. Transport is delegated
/// to [TestRailHttpClient]; this layer only shapes requests and parses JSON
/// into typed results.
library;

import 'dart:convert';

import 'testrail_http_client.dart';
import 'testrail_markdown.dart';

/// TestRail API methods exposed to the MCP tool runtime.
class TestRailClient {
  final TestRailHttpClient _http;

  /// Project name → project ID resolution cache (Java `projectIdCache`).
  final Map<String, int> _projectIdCache = {};

  /// Project ID → default section ID cache (Java `defaultSectionCache`).
  final Map<int, int> _defaultSectionCache = {};

  /// Creates a client backed by [_http].
  TestRailClient(this._http);

  /// `testrail_test` — connectivity check via GET `get_user_by_email`.
  ///
  /// Uses the configured username as the email lookup. Returns `success: true`
  /// with the user name on success, or `success: false` with the error on
  /// failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get(
        'get_user_by_email&email=${_http.username}',
      );
      final user = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'TestRail connection successful',
        'user': user['name'] ?? '',
        'email': user['email'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'TestRail connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `testrail_get_case` — GET `get_case/{id}`.
  ///
  /// Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getCase(int id) async {
    return _decodeMap(await _http.get('get_case/$id'));
  }

  /// `testrail_get_cases` — GET `get_cases/{projectId}&suite_id={suiteId}`.
  ///
  /// The project ID comes from the configured `TESTRAIL_PROJECT`.
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getCases(int suiteId) async =>
      _getList('get_cases/${_http.projectId}&suite_id=$suiteId');

  /// `testrail_add_result` — POST `add_result/{testId}`.
  ///
  /// Sets [statusId] and [comment] on the new result for test [testId].
  Future<Map<String, dynamic>> addResult(
    int testId,
    int statusId,
    String comment,
  ) =>
      _postForMap(
        'add_result/$testId',
        {'status_id': statusId, 'comment': comment},
      );

  /// `testrail_get_runs` — GET `get_runs/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getRuns(int projectId) async =>
      _getList('get_runs/$projectId');

  /// `testrail_get_projects` — paginated GET `get_projects`.
  ///
  /// Aggregates every page into a single envelope (`offset`/`limit`/`size`/
  /// `projects`/`_links`), mirroring the Java `getProjects` shape. Section-
  /// and case-creation callers use it to resolve project ids to names.
  Future<Map<String, dynamic>> getProjects() async {
    final projects = await _collectPages('get_projects', 'projects');
    return {
      'offset': 0,
      'limit': 250,
      'size': projects.length,
      'projects': projects,
      '_links': {'next': null, 'prev': null},
    };
  }

  /// `testrail_get_sections` — paginated GET `get_sections/{projectId}`.
  ///
  /// Resolves [projectName] to a project ID, then pages through every
  /// section, optionally filtered by [suiteId] (required for projects with
  /// multiple suites). Always fetched fresh — never cached — so newly created
  /// sections are visible immediately.
  Future<List<Map<String, dynamic>>> getSectionsByProjectName(
    String projectName, {
    String? suiteId,
  }) async {
    final projectId = await _getProjectId(projectName);
    var basePath = 'get_sections/$projectId';
    if (suiteId != null && suiteId.isNotEmpty) {
      basePath = '$basePath&suite_id=$suiteId';
    }
    return _collectPages(basePath, 'sections');
  }

  /// `testrail_add_case` — POST `add_case/{sectionId}`.
  ///
  /// Creates a new test case with [title] under [sectionId].
  Future<Map<String, dynamic>> addCase(int sectionId, String title) =>
      _postForMap('add_case/$sectionId', {'title': title});

  /// `testrail_update_case` — POST `update_case/{id}`.
  ///
  /// Updates test case [id] with the provided [fields] map.
  Future<Map<String, dynamic>> updateCase(
    int id,
    Map<String, dynamic> fields,
  ) =>
      _postForMap('update_case/$id', fields);

  /// `testrail_delete_case` — POST `delete_case/{id}`.
  ///
  /// Deletes test case [id]. Returns the decoded response, or an empty map.
  Future<Map<String, dynamic>> deleteCase(int id) =>
      _postForMap('delete_case/$id', const {});

  /// `testrail_get_milestones` — GET `get_milestones/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getMilestones(int projectId) async =>
      _getList('get_milestones/$projectId');

  /// `testrail_get_plans` — GET `get_plans/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getPlans(int projectId) async =>
      _getList('get_plans/$projectId');

  /// `testrail_add_run` — POST `add_run/{projectId}`.
  ///
  /// Creates a new test run named [name] under [projectId].
  Future<Map<String, dynamic>> addRun(int projectId, String name) =>
      _postForMap('add_run/$projectId', {'name': name});

  /// `testrail_update_run` — POST `update_run/{runId}`.
  ///
  /// Renames the test run [runId] to [name].
  Future<Map<String, dynamic>> updateRun(int runId, String name) =>
      _postForMap('update_run/$runId', {'name': name});

  /// `testrail_get_case_types` — GET `get_case_types/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getCaseTypes(int projectId) async =>
      _getList('get_case_types/$projectId');

  /// `testrail_get_priorities` — GET `get_priorities`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getPriorities() async =>
      _getList('get_priorities');

  /// `testrail_get_statuses` — GET `get_statuses`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getStatuses() async =>
      _getList('get_statuses');

  /// `testrail_get_references` — GET `get_references/{projectId}`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getReferences(int projectId) async =>
      _getList('get_references/$projectId');

  /// `testrail_get_templates` — GET `get_templates`.
  ///
  /// Returns an empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getTemplates() async =>
      _getList('get_templates');

  /// Creates a case in TestRail: resolves the target section, then POSTs
  /// [caseData] to `add_case/{sectionId}`.
  Future<Map<String, dynamic>> _createCaseIn(
    String projectName,
    String? sectionId,
    Map<String, dynamic> caseData,
  ) async {
    final projectId = await _getProjectId(projectName);
    final effectiveSectionId = await _resolveSectionId(projectId, sectionId);
    return _postForMap('add_case/$effectiveSectionId', caseData);
  }

  /// `testrail_create_case` — POST `add_case/{sectionId}`.
  ///
  /// Creates a basic test case under [sectionId] (or the project's default
  /// section when omitted); [description] lands in `custom_preconds` and
  /// [priorityId] defaults to 2 (Medium) when missing or unparsable.
  Future<Map<String, dynamic>> createCase(
    String projectName,
    String title, {
    String? description,
    String? priorityId,
    String? refs,
    String? sectionId,
  }) async {
    final caseData = <String, dynamic>{'title': title};
    _setIfNotEmpty(caseData, 'custom_preconds', description);
    caseData['priority_id'] = _parsePriorityId(priorityId);
    _setIfNotEmpty(caseData, 'refs', refs);
    return _createCaseIn(projectName, sectionId, caseData);
  }

  /// `testrail_create_case_detailed` — POST `add_case/{sectionId}`.
  ///
  /// Creates a case with `custom_preconds`/`custom_steps`/`custom_expected`
  /// text fields; Markdown tables in those fields are auto-converted to
  /// TestRail's `|||:Col|Col` format.
  Future<Map<String, dynamic>> createCaseDetailed(
    String projectName,
    String title, {
    String? preconditions,
    String? steps,
    String? expected,
    String? priorityId,
    String? typeId,
    String? refs,
    String? labelIds,
    String? sectionId,
  }) async {
    final caseData = _baseCaseData(title, preconditions: preconditions);
    _setConverted(caseData, 'custom_steps', steps);
    _setConverted(caseData, 'custom_expected', expected);
    _applyCommonFields(
      caseData,
      priorityId: priorityId,
      typeId: typeId,
      refs: refs,
      labelIds: labelIds,
    );
    return _createCaseIn(projectName, sectionId, caseData);
  }

  /// `testrail_create_case_steps` — POST `add_case/{sectionId}`.
  ///
  /// Creates a case on the 'Test Case (Steps)' template (template_id=2):
  /// [stepsJson] is a JSON array of
  /// `{"content": "...", "expected": "..."}` step objects, and Markdown
  /// tables in text fields are auto-converted to HTML.
  Future<Map<String, dynamic>> createCaseSteps(
    String projectName,
    String title, {
    String? preconditions,
    required String stepsJson,
    String? priorityId,
    String? typeId,
    String? refs,
    String? labelIds,
    String? sectionId,
  }) async {
    final caseData = _baseCaseData(
      title,
      preconditions: preconditions,
      html: true,
    )..['template_id'] = 2;
    caseData['custom_steps_separated'] = _parseStepsJson(stepsJson);
    _applyCommonFields(
      caseData,
      priorityId: priorityId,
      typeId: typeId,
      refs: refs,
      labelIds: labelIds,
    );
    return _createCaseIn(projectName, sectionId, caseData);
  }

  /// GETs [path] and decodes the JSON array response.
  Future<List<Map<String, dynamic>>> _getList(String path) async =>
      _decodeList(await _http.get(path));

  /// Resolves a project name to its ID via `get_projects` pagination.
  ///
  /// Every project seen along the way is cached; throws [StateError] when the
  /// name never appears.
  Future<int> _getProjectId(String projectName) async {
    final cached = _projectIdCache[projectName];
    if (cached != null) return cached;
    const basePath = 'get_projects';
    String? nextPagePath = _buildPagedPath(basePath, 250, 0);
    while (nextPagePath != null) {
      final response = _decodeMap(await _http.get(nextPagePath)) ??
          const <String, dynamic>{};
      final projects = _asListOfMaps(response['projects']);
      if (projects.isEmpty) break;
      for (final project in projects) {
        final name = project['name'];
        final id = (project['id'] as num?)?.toInt();
        if (name is String && id != null) _projectIdCache[name] = id;
      }
      final match = _projectIdCache[projectName];
      if (match != null) return match;
      nextPagePath = _nextPagePath(response, basePath, 250, projects.length);
    }
    throw StateError('Project not found: $projectName');
  }

  /// Resolves an explicit [sectionId] or falls back to the default section.
  ///
  /// An unparsable [sectionId] falls back to the default section, mirroring
  /// the Java `resolveSectionId` behaviour.
  Future<int> _resolveSectionId(int projectId, String? sectionId) async {
    if (sectionId != null && sectionId.isNotEmpty) {
      final parsed = int.tryParse(sectionId);
      if (parsed != null) return parsed;
    }
    return _getDefaultSectionId(projectId);
  }

  /// Returns the project's first section, creating a "Test Cases" section
  /// when the project has none.
  Future<int> _getDefaultSectionId(int projectId) async {
    final cached = _defaultSectionCache[projectId];
    if (cached != null) return cached;
    final response =
        _decodeMap(await _http.get('get_sections/$projectId')) ?? const {};
    final sections = _asListOfMaps(response['sections']);
    final id = sections.isNotEmpty
        ? (sections.first['id'] as num?)?.toInt()
        : await _createDefaultSection(projectId);
    if (id == null) {
      throw StateError('No section ID for project $projectId');
    }
    _defaultSectionCache[projectId] = id;
    return id;
  }

  /// Creates the fallback "Test Cases" section and returns its ID.
  Future<int> _createDefaultSection(int projectId) async {
    final created =
        await _postForMap('add_section/$projectId', {'name': 'Test Cases'});
    return (created['id'] as num?)?.toInt() ?? -1;
  }

  /// Pages through a TestRail collection endpoint.
  ///
  /// [baseApiPath] is the API route (e.g. `/get_sections/5`), [itemKey] the
  /// response field holding the page items (`sections`, `projects`, …).
  /// Follows `_links.next` when present, otherwise falls back to the
  /// limit/offset heuristic.
  Future<List<Map<String, dynamic>>> _collectPages(
    String baseApiPath,
    String itemKey, {
    int limit = 250,
  }) async {
    final items = <Map<String, dynamic>>[];
    String? nextPagePath = _buildPagedPath(baseApiPath, limit, 0);
    while (nextPagePath != null) {
      final response = _decodeMap(await _http.get(nextPagePath)) ??
          const <String, dynamic>{};
      final page = _asListOfMaps(response[itemKey]);
      if (page.isEmpty) break;
      items.addAll(page);
      nextPagePath = _nextPagePath(response, baseApiPath, limit, page.length);
    }
    return items;
  }

  /// Computes the next page path from `_links.next` or the offset heuristic.
  String? _nextPagePath(
    Map<String, dynamic> response,
    String baseApiPath,
    int limit,
    int currentPageItemCount,
  ) {
    if (response.containsKey('_links')) {
      return _normalizePagedApiPath(_extractNextPageLink(response['_links']));
    }
    if (currentPageItemCount < limit) return null;
    final offset = (response['offset'] as num?)?.toInt() ?? 0;
    return _buildPagedPath(baseApiPath, limit, offset + limit);
  }

  /// Extracts the non-null `next` link from a `_links` object.
  String? _extractNextPageLink(Object? links) {
    if (links is! Map) return null;
    final next = links['next'];
    if (next is! String || next.trim().isEmpty || next == 'null') return null;
    return next;
  }

  /// Strips the API prefix from an absolute or relative paged URL, returning
  /// a route relative to the API root (no leading slash, matching
  /// [TestRailHttpClient.buildUrl] conventions).
  String? _normalizePagedApiPath(String? pathOrUrl) {
    if (pathOrUrl == null) return null;
    final normalized = _stripApiPrefix(pathOrUrl.trim());
    return normalized.startsWith('/') ? normalized.substring(1) : normalized;
  }

  /// Removes the known API prefixes from a TestRail `_links.next` URL.
  String _stripApiPrefix(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      const relativePrefix = '/api/v2';
      final apiIndex = url.indexOf(relativePrefix);
      return apiIndex >= 0
          ? url.substring(apiIndex + relativePrefix.length)
          : url;
    }
    for (final prefix in const ['/index.php?/api/v2', '/api/v2']) {
      if (url.startsWith(prefix)) return url.substring(prefix.length);
    }
    return url;
  }

  /// Appends TestRail's `&limit=&offset=` paging parameters.
  String _buildPagedPath(String baseApiPath, int limit, int offset) =>
      '$baseApiPath&limit=$limit&offset=$offset';

  /// Builds the base case payload with a converted preconditions field.
  Map<String, dynamic> _baseCaseData(
    String title, {
    String? preconditions,
    bool html = false,
  }) {
    final data = <String, dynamic>{'title': title};
    if (preconditions != null && preconditions.isNotEmpty) {
      data['custom_preconds'] = html
          ? convertMarkdownTablesToHtml(preconditions)
          : convertMarkdownTablesToTestRailFormat(preconditions);
    }
    return data;
  }

  /// Sets [key] to the TestRail-format conversion of [value] when non-empty.
  void _setConverted(
    Map<String, dynamic> caseData,
    String key,
    String? value,
  ) {
    if (value != null && value.isNotEmpty) {
      caseData[key] = convertMarkdownTablesToTestRailFormat(value);
    }
  }

  /// Applies the priority/type/refs/labels fields shared by the create tools.
  void _applyCommonFields(
    Map<String, dynamic> caseData, {
    String? priorityId,
    String? typeId,
    String? refs,
    String? labelIds,
  }) {
    caseData['priority_id'] = _parsePriorityId(priorityId);
    if (typeId != null && typeId.isNotEmpty) {
      final parsed = int.tryParse(typeId);
      if (parsed != null) caseData['type_id'] = parsed;
    }
    _setIfNotEmpty(caseData, 'refs', refs);
    final labels = _parseLabelIds(labelIds);
    if (labels.isNotEmpty) caseData['labels'] = labels;
  }

  /// Parses a priority ID, defaulting to 2 (Medium) when missing/invalid.
  int _parsePriorityId(String? priorityId) {
    if (priorityId != null && priorityId.isNotEmpty) {
      return int.tryParse(priorityId) ?? 2;
    }
    return 2;
  }

  /// Parses a comma-separated label ID list, skipping invalid entries.
  List<int> _parseLabelIds(String? labelIds) {
    if (labelIds == null || labelIds.isEmpty) return const [];
    return labelIds
        .split(',')
        .map((id) => int.tryParse(id.trim()))
        .whereType<int>()
        .toList();
  }

  /// Parses a Steps-template `steps_json` array into payload step objects.
  List<Map<String, dynamic>> _parseStepsJson(String stepsJson) {
    final decoded = _tryDecodeSteps(stepsJson);
    return [
      for (final step in decoded)
        if (step is Map<String, dynamic>) _convertStep(step),
    ];
  }

  /// Converts one parsed step, HTML-converting its Markdown tables.
  Map<String, dynamic> _convertStep(Map<String, dynamic> input) => {
        'content': convertMarkdownTablesToHtml(_optStr(input['content'])),
        'expected': convertMarkdownTablesToHtml(_optStr(input['expected'])),
        'additional_info': _optStr(input['additional_info']),
        'refs': _optStr(input['refs']),
        'markdown_editor_id': 1,
      };

  /// Decodes [stepsJson], requiring a JSON array.
  List<dynamic> _tryDecodeSteps(String stepsJson) {
    try {
      final decoded = jsonDecode(stepsJson);
      if (decoded is List) return decoded;
    } on FormatException {
      // fall through to the error below
    }
    throw FormatException(
      'Invalid steps_json format. Expected JSON array: '
      '[{"content":"...","expected":"..."}, ...]',
    );
  }

  /// Returns [value] as a string, mapping null to the empty string.
  String _optStr(Object? value) => value is String ? value : '';

  /// Sets [key] to [value] when it is a non-empty string.
  void _setIfNotEmpty(Map<String, dynamic> data, String key, String? value) {
    if (value != null && value.isNotEmpty) data[key] = value;
  }

  /// Casts a decoded JSON value to a list of object maps, else `const []`.
  List<Map<String, dynamic>> _asListOfMaps(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map<String, dynamic>) item,
    ];
  }

  /// POSTs [payload] to [path] and returns the decoded object, or `{}`.
  ///
  /// TestRail occasionally answers writes with `200 OK` and an empty body
  /// (observed on `add_case`); rather than surfacing a bare `FormatException`
  /// from [jsonDecode], fail with the offending route spelled out.
  Future<Map<String, dynamic>> _postForMap(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final body = await _http.post(path, body: jsonEncode(payload));
    if (body.trim().isEmpty) {
      throw StateError('TestRail returned an empty body for POST $path');
    }
    return _decodeMap(body) ?? {};
  }

  /// Decodes a JSON body to a map, or `null` when not an object.
  Map<String, dynamic>? _decodeMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Decodes a JSON array of objects, tolerating non-array bodies.
  List<Map<String, dynamic>> _decodeList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return List<Map<String, dynamic>>.from(
      decoded.map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }
}
