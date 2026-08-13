/// High-level Jenkins API client — ports the top-used MCP tool methods.
///
/// Each method corresponds to a Jenkins MCP tool. Transport is delegated to
/// [JenkinsHttpClient]; this layer shapes requests and parses JSON into typed
/// results. Job names are URL-encoded automatically.
library;

import 'dart:convert';

import 'jenkins_http_client.dart';

/// Jenkins API methods exposed to the MCP tool runtime.
class JenkinsClient {
  final JenkinsHttpClient _http;

  /// Creates a client backed by [_http].
  JenkinsClient(this._http);

  /// URL-encodes a job name for safe path-segment use.
  String _encodeJob(String name) => Uri.encodeComponent(name);

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

  /// `jenkins_trigger_job` — POST `job/{name}/build`.
  ///
  /// Triggers an unconditional build of [name]. Returns a success/failure map
  /// since the Jenkins response body is empty.
  Future<Map<String, dynamic>> triggerJob(String name) async {
    try {
      await _http.post('job/${_encodeJob(name)}/build');
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
      'job/${_encodeJob(name)}/$buildNumber/api/json',
    );
    return _decodeMap(body);
  }

  /// `jenkins_get_build_log` — GET `job/{name}/{buildNumber}/consoleText`.
  ///
  /// Returns the raw console log text.
  Future<String> getBuildLog(String name, int buildNumber) async {
    return _http.get('job/${_encodeJob(name)}/$buildNumber/consoleText');
  }

  /// `jenkins_get_last_build` — GET `job/{name}/lastBuild/api/json`.
  ///
  /// Returns `null` when the response body is not a JSON object.
  Future<Map<String, dynamic>?> getLastBuild(String name) async {
    final body = await _http.get('job/${_encodeJob(name)}/lastBuild/api/json');
    return _decodeMap(body);
  }

  /// Decodes a JSON body to a map, or `null` when not an object.
  Map<String, dynamic>? _decodeMap(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
