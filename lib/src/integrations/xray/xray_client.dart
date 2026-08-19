/// High-level Xray API client — ports the Xray test-management MCP tools.
///
/// Xray authenticates with OAuth2 client credentials: [authenticate] POSTs to
/// `/api/v2/authenticate`, receives a JWT, and stores it as a Bearer token for
/// all subsequent API calls. Transport is delegated to [XrayHttpClient].
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level Xray HTTP transport used by [XrayClient].
///
/// Stores the Bearer token obtained from [XrayClient.authenticate] and injects
/// it into every request via [authHeaders]. Before authentication the token is
/// empty and [authHeaders] omits the `Authorization` header so the
/// `/api/v2/authenticate` call can succeed.
class XrayHttpClient extends BaseHttpClient {
  /// Xray OAuth2 client ID from `XRAY_CLIENT_ID`.
  final String clientId;

  /// Xray OAuth2 client secret from `XRAY_CLIENT_SECRET`.
  final String clientSecret;

  String _token;

  /// Creates a client from [reader]'s Xray configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60-second timeouts.
  ///
  /// Throws [StateError] when `XRAY_BASE_PATH`, `XRAY_CLIENT_ID`, or
  /// `XRAY_CLIENT_SECRET` is missing or empty.
  factory XrayHttpClient(PropertyReader reader, {Dio? dio}) {
    final basePath = reader.getXrayBasePath();
    final clientId = reader.getXrayClientId();
    final clientSecret = reader.getXrayClientSecret();
    if (basePath == null || basePath.isEmpty) {
      throw StateError('XRAY_BASE_PATH is not configured');
    }
    if (clientId == null || clientId.isEmpty) {
      throw StateError('XRAY_CLIENT_ID is not configured');
    }
    if (clientSecret == null || clientSecret.isEmpty) {
      throw StateError('XRAY_CLIENT_SECRET is not configured');
    }
    return XrayHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      clientId: clientId,
      clientSecret: clientSecret,
    );
  }

  XrayHttpClient._({
    required super.dio,
    required super.basePath,
    required this.clientId,
    required this.clientSecret,
  }) : _token = '';

  /// Stores the Bearer [token] obtained from the authenticate endpoint.
  void setToken(String token) => _token = token;

  /// Whether a Bearer token has been stored via [setToken].
  bool get isAuthenticated => _token.isNotEmpty;

  @override
  Map<String, String> get authHeaders =>
      _token.isEmpty ? const {} : {'Authorization': 'Bearer $_token'};

  @override
  String buildUrl(String path) => '$basePath/api/v2/$path';
}

/// Xray API methods exposed to the MCP tool runtime.
///
/// Auto-authenticates (using the configured client credentials) on the first
/// API call that requires a Bearer token, so callers can invoke [getTests],
/// [getTestExecutions], [getTestSteps], [getTestPlan], or
/// [createTestExecution] without a manual [authenticate] call.
class XrayClient {
  final XrayHttpClient _http;

  /// Creates a client backed by [_http].
  XrayClient(this._http);

  /// Authenticates with Xray OAuth2 and stores the Bearer token.
  ///
  /// POSTs `{"client_id", "client_secret"}` to `/api/v2/authenticate`.
  /// The response body is a JSON-quoted JWT string; the decoded value is
  /// stored as the Bearer token for all subsequent requests.
  Future<void> authenticate(String clientId, String clientSecret) async {
    final body = await _http.post(
      'authenticate',
      body: jsonEncode({
        'client_id': clientId,
        'client_secret': clientSecret,
      }),
    );
    final token = jsonDecode(body);
    if (token is String) _http.setToken(token);
  }

  /// Authenticates using the configured credentials when not already done.
  Future<void> _ensureAuthenticated() async {
    if (!_http.isAuthenticated) {
      await authenticate(_http.clientId, _http.clientSecret);
    }
  }

  /// `jira_xray_test` — connectivity check via OAuth2 authentication.
  ///
  /// Returns `success: true` on successful authentication, or `success: false`
  /// with the error message on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      await authenticate(_http.clientId, _http.clientSecret);
      return {'success': true, 'message': 'Xray connection successful'};
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Xray connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `jira_xray_get_tests` — POST `/api/v2/tests`.
  ///
  /// Returns the decoded list of test objects matching [testKeys], or an
  /// empty list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getTests(List<String> testKeys) async {
    await _ensureAuthenticated();
    final body =
        await _http.post('tests', body: jsonEncode({'keys': testKeys}));
    return _decodeList(body);
  }

  /// Gets test executions that contain [testKey] — GET
  /// `/api/v2/test/{testKey}/testexecutions`.
  ///
  /// Returns the decoded list of test-execution objects, or an empty list
  /// when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getTestExecutions(String testKey) async {
    await _ensureAuthenticated();
    final body = await _http.get('test/$testKey/testexecutions');
    return _decodeList(body);
  }

  /// `jira_xray_get_test_runs` — GET `/api/v2/testrun?testKey={testKey}`.
  ///
  /// Returns the decoded list of test-run objects for [testKey], or an empty
  /// list when the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getTestRuns(String testKey) async {
    await _ensureAuthenticated();
    final body = await _http.get('testrun', queryParams: {'testKey': testKey});
    return _decodeList(body);
  }

  /// `jira_xray_get_test_steps` — GET `/api/v2/test/{testKey}/steps`.
  ///
  /// Returns the decoded list of test-step objects, or an empty list when
  /// the response body is not a JSON array.
  Future<List<Map<String, dynamic>>> getTestSteps(String testKey) async {
    await _ensureAuthenticated();
    final body = await _http.get('test/$testKey/steps');
    return _decodeList(body);
  }

  /// `jira_xray_get_test_plan` — GET `/api/v2/testplan/{testPlanKey}`.
  ///
  /// Returns the decoded test-plan object, or an empty map when the body is
  /// not a JSON object.
  Future<Map<String, dynamic>> getTestPlan(String testPlanKey) async {
    await _ensureAuthenticated();
    final body = await _http.get('testplan/$testPlanKey');
    return _decodeMap(body) ?? {};
  }

  /// `jira_xray_create_test_execution` — POST `/api/v2/import/execution`.
  ///
  /// Merges [projectKey] into [testExecJson] and imports the execution.
  /// Returns the decoded response object, or an empty map when the body is
  /// not a JSON object.
  Future<Map<String, dynamic>> createTestExecution(
    String projectKey,
    Map<String, dynamic> testExecJson,
  ) async {
    await _ensureAuthenticated();
    final payload = {...testExecJson, 'projectKey': projectKey};
    final body = await _http.post(
      'import/execution',
      body: jsonEncode(payload),
    );
    return _decodeMap(body) ?? {};
  }

  /// `jira_xray_update_test_execution` — POST `/api/v2/testexec/{executionId}`.
  ///
  /// Updates the status of test execution [executionId]. Returns the decoded
  /// response object, or an empty map when the body is not a JSON object.
  Future<Map<String, dynamic>> updateTestExecution(
    String executionId,
    String status,
  ) async {
    await _ensureAuthenticated();
    final body = await _http.post(
      'testexec/$executionId',
      body: jsonEncode({'status': status}),
    );
    return _decodeMap(body) ?? {};
  }

  /// Decodes a JSON array of objects, tolerating non-array bodies.
  List<Map<String, dynamic>> _decodeList(String body) {
    final decoded = jsonDecode(body);
    return decoded is List
        ? [for (final e in decoded) Map<String, dynamic>.from(e as Map)]
        : const [];
  }

  /// Decodes a JSON body to a map, or `null` when not an object.
  Map<String, dynamic>? _decodeMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
