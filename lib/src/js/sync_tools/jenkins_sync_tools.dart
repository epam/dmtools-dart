/// Synchronous Jenkins tool executors for the JS tool bridge.
///
/// Public counterpart for the dispatcher: each handler resolves its config
/// from [PropertyReader], performs blocking HTTP via [SyncHttpClient], and
/// returns a JSON result string. Tool names, parameters, and URL shapes port
/// the Java `Jenkins.java` `@MCPTool` methods (`jenkins_get_job_info`,
/// `jenkins_get_build_log`), including folder-path job addressing
/// (`folder/job-name` → `job/folder/job/job-name`).
library;

import 'dart:convert';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Jenkins executors: `jenkins_*` tool name → JSON result.
class JenkinsSyncTools {
  final PropertyReader _reader;

  /// Creates Jenkins tooling reading config from [reader].
  JenkinsSyncTools(this._reader);

  /// Tool executors; config is resolved inside each handler.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'jenkins_get_job_info': _getJobInfo,
        'jenkins_get_build_log': _getBuildLog,
      };

  /// Dispatches a Jenkins tool call, mirroring the dispatcher's errors.
  String dispatch(String toolName, Map<String, dynamic> args) {
    final fn = handlers[toolName];
    if (fn == null) return syncErr('Unsupported Jenkins tool: $toolName');
    return fn(args);
  }

  /// Builds Jenkins config, or `null` when user / API token is missing.
  ///
  /// Mirrors the Java `Jenkins.sign()`: HTTP Basic over `JENKINS_USER` +
  /// `JENKINS_API_TOKEN`; base path from `JENKINS_BASE_PATH` (default
  /// `http://localhost:8080`) with any trailing slash stripped.
  _Conf? _config() {
    final user = _reader.getJenkinsUser();
    if (user == null || user.isEmpty) return null;
    final token = _reader.getJenkinsApiToken();
    if (token == null || token.isEmpty) return null;
    var basePath = _reader.getJenkinsBasePath();
    while (basePath.endsWith('/')) {
      basePath = basePath.substring(0, basePath.length - 1);
    }
    final basic = base64Encode(utf8.encode('${user.trim()}:${token.trim()}'));
    return (
      baseUrl: basePath,
      headers: {
        'Authorization': 'Basic $basic',
        'Accept': _json,
        'Content-Type': _json,
      },
    );
  }

  /// `jenkins_get_job_info` — GET `{jobPath}/{buildNumber}/api/json`
  /// (Java `getBuildInfo`).
  String _getJobInfo(Map<String, dynamic> args) =>
      _fetchBuild(args, 'api/json');

  /// `jenkins_get_build_log` — GET `{jobPath}/{buildNumber}/consoleText`
  /// (Java `getBuildLog`); returns the raw console text.
  String _getBuildLog(Map<String, dynamic> args) =>
      _fetchBuild(args, 'consoleText');

  /// GETs one build-scoped endpoint ([suffix]) under the resolved job path.
  String _fetchBuild(Map<String, dynamic> args, String suffix) {
    final config = _config();
    if (config == null) return syncErr('Jenkins not configured');
    final jobPath = apiJobPath(syncAsStr(args['jobPath']));
    final buildNumber = syncAsInt(args['buildNumber']);
    return syncBodyOrError(SyncHttpClient.get(
      '${config.baseUrl}$jobPath$buildNumber/$suffix',
      headers: config.headers,
    ));
  }
}

/// Converts a job name or folder path into Jenkins REST API segments.
///
/// Ports the Java `Jenkins.toApiJobPath`: `folder/job-name` becomes
/// `/job/folder/job/job-name/` — each `/`-separated element encoded as its
/// own `job/` segment (never `%2F`-encoded as one segment). Inputs that
/// already start with `/job/` pass through unchanged (trailing `/` added).
String apiJobPath(String jobPath) {
  if (jobPath.trim().isEmpty) return '/';
  var normalized = jobPath.trim();
  if (normalized.startsWith('job/')) normalized = '/$normalized';
  if (normalized.startsWith('/job/')) {
    return normalized.endsWith('/') ? normalized : '$normalized/';
  }
  final segments =
      normalized.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent);
  final joined = segments.map((s) => '/job/$s').join();
  return '$joined/';
}

// ── Shared helpers ─────────────────────────────────────────────────────────

/// Resolved sync integration config: base URL plus auth headers.
typedef _Conf = ({String baseUrl, Map<String, String> headers});

/// Media type for JSON request/response bodies.
const _json = 'application/json';
