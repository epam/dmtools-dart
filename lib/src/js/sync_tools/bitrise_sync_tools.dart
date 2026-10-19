/// Synchronous Bitrise tool executors for the JS tool bridge.
///
/// Public counterpart for the dispatcher: each handler resolves its config
/// from [PropertyReader], performs blocking HTTP via [SyncHttpClient], and
/// returns a JSON result string. Tool names, parameters, URL shapes, and the
/// `build_params`/`hook_info` wire format port the Java `Bitrise.java`
/// `@MCPTool` methods (`bitrise_list_builds`, `bitrise_trigger_build`,
/// `bitrise_abort_build`, `bitrise_list_build_artifacts`,
/// `bitrise_get_build_artifact`).
///
/// The account-wide write tools (`bitrise_trigger_build`,
/// `bitrise_abort_build`) port the async client's `BITRISE_ALLOW_WRITES`
/// guard: writes stay disabled unless the real environment opts in.
library;

import 'dart:convert';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../../integrations/bitrise/bitrise_client.dart';
import '../sync_http_client.dart';
import 'sync_request_helpers.dart';

/// Bitrise executors: `bitrise_*` tool name → JSON result.
class BitriseSyncTools {
  final PropertyReader _reader;

  /// Creates Bitrise tooling reading config from [reader].
  BitriseSyncTools(this._reader);

  /// Tool executors; config is resolved inside each handler.
  Map<String, String Function(Map<String, dynamic> args)> get handlers => {
        'bitrise_list_builds': _listBuilds,
        'bitrise_trigger_build': _triggerBuild,
        'bitrise_abort_build': _abortBuild,
        'bitrise_list_build_artifacts': _listBuildArtifacts,
        'bitrise_get_build_artifact': _getBuildArtifact,
      };

  /// Dispatches a Bitrise tool call, mirroring the dispatcher's errors.
  String dispatch(String toolName, Map<String, dynamic> args) {
    final fn = handlers[toolName];
    if (fn == null) return syncErr('Unsupported Bitrise tool: $toolName');
    return fn(args);
  }

  /// Builds Bitrise config, or `null` when the token is missing.
  ///
  /// Mirrors the Java `Bitrise.sign()`: `Authorization: token <PAT>` on
  /// every request; endpoints under `BITRISE_BASE_PATH` (default
  /// `https://api.bitrise.io/v0.1`).
  _Conf? _config() {
    final token = _reader.getBitriseToken();
    if (token == null || token.isEmpty) return null;
    return (
      baseUrl: _reader.getBitriseBasePath(),
      headers: {
        'Authorization': 'token $token',
        'Accept': _json,
        'Content-Type': _json,
      },
    );
  }

  /// `bitrise_list_builds` — GET `apps/{appSlug}/builds` with the optional
  /// workflow/branch/status/limit/next filters (Java `listBuilds`).
  String _listBuilds(Map<String, dynamic> args) => syncWithConfig(
        _config(),
        _notConfiguredError,
        (config) => syncBodyOrError(SyncHttpClient.get(
          '${_buildsPath(config, args)}${_buildListQuery(args)}',
          headers: config.headers,
        )),
      );

  /// `bitrise_trigger_build` — POST `apps/{appSlug}/builds` with
  /// `build_params` + `hook_info` (Java `triggerBuild`); guarded.
  String _triggerBuild(Map<String, dynamic> args) =>
      syncWithConfig(_config(), _notConfiguredError, (config) {
        final guardError = _writesAllowed('bitrise_trigger_build');
        if (guardError != null) return guardError;
        return syncBodyOrError(SyncHttpClient.post(
          _buildsPath(config, args),
          headers: config.headers,
          body: jsonEncode({
            'build_params': _buildParams(args),
            'hook_info': {'type': 'bitrise'},
          }),
        ));
      });

  /// `bitrise_abort_build` — POST `apps/{appSlug}/builds/{buildSlug}/abort`
  /// with the abort body (Java `abortBuild`); guarded.
  String _abortBuild(Map<String, dynamic> args) =>
      syncWithConfig(_config(), _notConfiguredError, (config) {
        final guardError = _writesAllowed('bitrise_abort_build');
        if (guardError != null) return guardError;
        return syncBodyOrError(SyncHttpClient.post(
          '${_buildsPath(config, args)}/${_slug(args['buildSlug'])}/abort',
          headers: config.headers,
          body: jsonEncode(_abortBody(args)),
        ));
      });

  /// `bitrise_list_build_artifacts` — GET
  /// `apps/{appSlug}/builds/{buildSlug}/artifacts` (Java `listBuildArtifacts`).
  String _listBuildArtifacts(Map<String, dynamic> args) => syncWithConfig(
        _config(),
        _notConfiguredError,
        (config) => syncBodyOrError(SyncHttpClient.get(
          _artifactsPath(config, args),
          headers: config.headers,
        )),
      );

  /// `bitrise_get_build_artifact` — GET
  /// `apps/{a}/builds/{b}/artifacts/{artifactSlug}` (Java `getBuildArtifact`).
  String _getBuildArtifact(Map<String, dynamic> args) => syncWithConfig(
        _config(),
        _notConfiguredError,
        (config) => syncBodyOrError(SyncHttpClient.get(
          '${_artifactsPath(config, args)}/${_slug(args['artifactSlug'])}',
          headers: config.headers,
        )),
      );

  /// Builds the `list_builds` query string from optional filters.
  String _buildListQuery(Map<String, dynamic> args) {
    final params = <String>[];
    void add(String key, String? value) {
      if (value != null && value.isNotEmpty) {
        params.add('$key=${Uri.encodeQueryComponent(value)}');
      }
    }

    add('workflow', syncAsStr(args['workflowId']));
    add('branch', syncAsStr(args['branch']));
    final status = _mapBuildStatus(args['status']);
    if (status != null) params.add('status=$status');
    final limit = args['limit'];
    if (limit != null) params.add('limit=${syncAsInt(limit)}');
    add('next', syncAsStr(args['next']));
    return params.isEmpty ? '' : '?${params.join('&')}';
  }

  /// Builds `build_params` from the trigger arguments (Java `triggerBuild`).
  Map<String, dynamic> _buildParams(Map<String, dynamic> args) {
    final params = <String, dynamic>{
      'workflow_id': syncAsStr(args['workflowId']),
    };
    final branch = syncAsStr(args['branch']);
    if (branch.isNotEmpty) params['branch'] = branch;
    final commitMessage = syncAsStr(args['commitMessage']);
    if (commitMessage.isNotEmpty) params['commit_message'] = commitMessage;
    final environments = _parseEnvVars(args['envVars']);
    if (environments != null) params['environments'] = environments;
    return params;
  }

  /// Parses the `envVars` JSON-array string; `null` when absent/invalid
  /// (Java logs and ignores unparsable input).
  List<dynamic>? _parseEnvVars(dynamic envVars) {
    final raw = syncAsStr(envVars);
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Maps a human status name to the Bitrise status code (Java
  /// `mapBuildStatus`); `null` leaves the filter off.
  String? _mapBuildStatus(dynamic status) {
    switch (syncAsStr(status).toLowerCase()) {
      case 'not_started':
        return '0';
      case 'in_progress':
        return '1';
      case 'success':
        return '2';
      case 'failed':
        return '3';
      case 'aborted':
        return '4';
    }
    return syncAsStr(status).isEmpty ? null : syncAsStr(status);
  }

  /// Returns the guard's error JSON for [operation], or `null` when writes
  /// are enabled — port of the async client's `_ensureWritesAllowed`.
  String? _writesAllowed(String operation) {
    final flag =
        BitriseClient.environment['BITRISE_ALLOW_WRITES']?.toLowerCase();
    final allowed = flag == '1' || flag == 'true' || flag == 'yes';
    if (allowed) return null;
    return syncErr(
      '$operation is disabled: Bitrise write operations '
      '(bitrise_trigger_build, bitrise_abort_build) require an explicit '
      'opt-in — set BITRISE_ALLOW_WRITES=1 in the environment',
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

/// Resolved sync integration config: base URL plus auth headers.
typedef _Conf = ({String baseUrl, Map<String, String> headers});

/// Error payload returned when the Bitrise token is missing.
const _notConfiguredError = 'Bitrise not configured';

/// Media type for JSON request/response bodies.
const _json = 'application/json';

/// The app's builds path: `{base}/apps/{appSlug}/builds`.
String _buildsPath(_Conf config, Map<String, dynamic> args) =>
    '${config.baseUrl}/apps/${_slug(args['appSlug'])}/builds';

/// One build's artifacts path: `{buildsPath}/{buildSlug}/artifacts`.
String _artifactsPath(_Conf config, Map<String, dynamic> args) =>
    '${_buildsPath(config, args)}/${_slug(args['buildSlug'])}/artifacts';

/// Builds the abort body: `abort_reason` only when a reason was given.
Map<String, dynamic> _abortBody(Map<String, dynamic> args) {
  final body = <String, dynamic>{
    'abort_with_success': false,
    'skip_notifications': false,
  };
  final reason = syncAsStr(args['reason']);
  if (reason.isNotEmpty) body['abort_reason'] = reason;
  return body;
}

/// URL-encodes an app/build/artifact slug for path-segment use.
String _slug(dynamic value) => Uri.encodeComponent(syncAsStr(value));
