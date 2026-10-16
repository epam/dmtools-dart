/// High-level Jenkins API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a Jenkins MCP tool. Transport is delegated to
/// [JenkinsHttpClient]; this layer shapes requests and parses JSON into typed
/// results. Job names may be folder paths (`team/service`), encoded as
/// Jenkins `job/` segments per path element; POSTs carry the CSRF crumb when
/// the server exposes one.
library;

import 'dart:convert';

import 'jenkins_http_client.dart';

/// Jenkins API methods exposed to the MCP tool runtime.
class JenkinsClient {
  final JenkinsHttpClient _http;

  /// Creates a client backed by [_http].
  JenkinsClient(this._http);

  /// Cached CSRF crumb header (`{field: value}`), or `null` until fetched.
  ///
  /// Jenkins instances with CSRF protection enabled (the default) reject
  /// POSTs without a valid crumb; instances with it disabled answer the
  /// `crumbIssuer` lookup with an error and POSTs proceed crumb-less.
  /// API-token auth is crumb-exempt server-side, so the crumb is strictly
  /// additive coverage.
  Map<String, String>? _crumb;

  /// Converts a job name or folder path into Jenkins REST API segments.
  ///
  /// Ports Java `Jenkins.toApiJobPath`: `folder/job-name` becomes
  /// `job/folder/job/job-name` — each `/`-separated element encoded as its
  /// own `job/` segment (never `%2F`-encoded as one segment).
  String _apiJobPath(String name) {
    final segments =
        name.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent);
    return segments.map((s) => 'job/$s').join('/');
  }

  /// Fetches (once) and returns the CSRF crumb headers for POSTs, or an
  /// empty map when the server has crumbs disabled.
  Future<Map<String, String>> _crumbHeaders() async {
    final cached = _crumb;
    if (cached != null) return cached;
    try {
      final body = await _http.get('crumbIssuer/api/json');
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> &&
          decoded['crumb'] is String &&
          decoded['crumbRequestField'] is String) {
        _crumb = {
          decoded['crumbRequestField'] as String: decoded['crumb'] as String,
        };
      } else {
        _crumb = const {};
      }
    } on Object {
      // crumbIssuer 404/403 → CSRF protection disabled; POST without crumb.
      _crumb = const {};
    }
    return _crumb!;
  }

  /// `jenkins_test` — connectivity check via GET `api/json`.
  ///
  /// Returns the Jenkins node class on success, or an error map on failure.
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final body = await _http.get('api/json');
      final node = jsonDecode(body) as Map<String, dynamic>;
      return {
        'success': true,
        'message': 'Jenkins connection successful',
        'node': node['_class'] ?? '',
        'description': node['description'] ?? '',
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Jenkins connection failed',
        'error': e.toString(),
      };
    }
  }

  /// `jenkins_get_jobs` — GET `api/json?tree=jobs[name,url]`.
  ///
  /// Returns the decoded list of job objects, or an empty list when the body
  /// has no `jobs` array.
  Future<List<Map<String, dynamic>>> getJobs() async {
    final body = await _http.get(
      'api/json',
      queryParams: {'tree': 'jobs[name,url]'},
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final jobs = decoded['jobs'];
    if (jobs is! List) return const [];
    return List<Map<String, dynamic>>.from(
      jobs.map((j) => j as Map<String, dynamic>),
    );
  }

  /// `jenkins_trigger_job` — POST `{jobPath}/build`.
  ///
  /// Triggers an unconditional build of [name]. Returns a success/failure map
  /// since the Jenkins response body is empty. POSTs carry the CSRF crumb
  /// when the server requires one (see [_crumbHeaders]).
  Future<Map<String, dynamic>> triggerJob(String name) async {
    try {
      await _http.post(
        '${_apiJobPath(name)}/build',
        extra: await _crumbHeaders(),
      );
      return {
        'success': true,
        'message': 'Job $name triggered',
        'job': name,
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Failed to trigger job $name',
        'error': e.toString(),
      };
    }
  }

  /// `jenkins_get_build` — GET `job/{name}/{buildNumber}/api/json`.
  ///
  /// Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getBuild(
    String name,
    int buildNumber,
  ) async {
    final body = await _http.get(
      '${_apiJobPath(name)}/$buildNumber/api/json',
    );
    return _decodeMap(body);
  }

  /// `jenkins_get_build_log` — GET `job/{name}/{buildNumber}/consoleText`.
  ///
  /// Returns the raw console log text.
  Future<String> getBuildLog(String name, int buildNumber) async {
    return _http.get('${_apiJobPath(name)}/$buildNumber/consoleText');
  }

  /// `jenkins_get_console_output` — GET
  /// `job/{name}/{buildNumber}/consoleText` with a `Range` header.
  ///
  /// Streams the console text starting at byte offset [startByte] via the
  /// `Range: bytes={startByte}-` request header. Returns the raw text.
  Future<String> getConsoleOutput(
    String name,
    int buildNumber,
    int startByte,
  ) async {
    return _http.get(
      '${_apiJobPath(name)}/$buildNumber/consoleText',
      extra: {'Range': 'bytes=$startByte-'},
    );
  }

  /// `jenkins_get_last_build` — GET `job/{name}/lastBuild/api/json`.
  ///
  /// Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getLastBuild(String name) async {
    final body = await _http.get('${_apiJobPath(name)}/lastBuild/api/json');
    return _decodeMap(body);
  }

  /// `jenkins_get_job_details` — GET `job/{name}/api/json`.
  ///
  /// Requests a trimmed view via `tree=builds[number,result]`. Returns `null`
  /// when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getJobDetails(String name) async {
    final body = await _http.get(
      '${_apiJobPath(name)}/api/json',
      queryParams: {'tree': 'builds[number,result]'},
    );
    return _decodeMap(body);
  }

  /// `jenkins_get_job_builds` — GET
  /// `job/{name}/api/json?tree=builds[number,result,timestamp]{0,N}`.
  ///
  /// Requests the last [limit] builds with their number, result, and
  /// timestamp. Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getJobBuilds(String name, int limit) async {
    final body = await _http.get(
      '${_apiJobPath(name)}/api/json',
      queryParams: {'tree': 'builds[number,result,timestamp]{0,$limit}'},
    );
    return _decodeMap(body);
  }

  /// `jenkins_get_queue` — GET `queue/api/json`.
  ///
  /// Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getQueue() async {
    final body = await _http.get('queue/api/json');
    return _decodeMap(body);
  }

  /// `jenkins_cancel_build` — POST `queue/cancelItem?id={queueId}`.
  ///
  /// Cancels the queued build identified by [queueId]. Returns a
  /// success/failure map since the Jenkins response body is empty. POSTs
  /// carry the CSRF crumb when the server requires one.
  Future<Map<String, dynamic>> cancelBuild(int queueId) async {
    try {
      await _http.post(
        'queue/cancelItem?id=$queueId',
        extra: await _crumbHeaders(),
      );
      return {
        'success': true,
        'message': 'Queue item $queueId cancelled',
        'queueId': queueId,
      };
    } on Object catch (e) {
      return {
        'success': false,
        'message': 'Failed to cancel queue item $queueId',
        'error': e.toString(),
      };
    }
  }

  /// `jenkins_get_build_artifacts` — GET
  /// `job/{name}/{buildNumber}/api/json?tree=artifacts[fileName,relativePath]`.
  ///
  /// Returns the decoded build object (containing an `artifacts` array), or
  /// `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getBuildArtifacts(
    String name,
    int buildNumber,
  ) async {
    final body = await _http.get(
      '${_apiJobPath(name)}/$buildNumber/api/json',
      queryParams: {
        'tree': 'artifacts[fileName,relativePath]',
      },
    );
    return _decodeMap(body);
  }

  /// `jenkins_get_job_config` — GET `job/{name}/config.xml`.
  ///
  /// Returns the raw job configuration XML.
  Future<String> getJobConfig(String name) async {
    return _http.get('${_apiJobPath(name)}/config.xml');
  }

  /// Decodes a JSON body to a map, or `null` when not an object.
  Map<String, dynamic>? _decodeMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
