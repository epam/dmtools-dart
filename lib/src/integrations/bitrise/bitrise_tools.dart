/// MCP tool definitions and dispatcher for the Bitrise integration.
///
/// The tool list ports the Bitrise subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [BitriseClient]
/// call.
library;

import 'dart:convert';

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'bitrise_client.dart';

/// Returns all Bitrise MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> bitriseTools() => [
      ..._systemTools(),
      ..._appTools(),
      ..._buildTools(),
      ..._javaParityBuildTools(),
      ..._artifactTools(),
    ];

/// Connectivity-check tool: `bitrise_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'bitrise_test',
        description: 'Test Bitrise connectivity by listing apps',
        integration: 'bitrise',
        category: 'system',
        params: [],
      ),
    ];

/// App tool: `bitrise_get_apps` (Java alias `bitrise_list_apps`).
List<ToolDefinition> _appTools() => [
      ToolDefinition(
        name: 'bitrise_get_apps',
        aliases: ['bitrise_list_apps'],
        description: 'List all Bitrise apps accessible to the token',
        integration: 'bitrise',
        category: 'apps',
        params: [],
      ),
    ];

/// Build tools: `bitrise_get_builds`, `bitrise_get_build_detail`,
/// `bitrise_trigger_build_with_params`, `bitrise_get_workflows`,
/// `bitrise_get_artifacts`, `bitrise_get_artifact_detail` (plus the
/// Java-parity build tools in [_javaParityBuildTools]).
List<ToolDefinition> _buildTools() => [
      _getBuildsTool(),
      _getBuildDetailTool(),
      _triggerBuildWithParamsTool(),
      _getWorkflowsTool(),
      _getArtifactsTool(),
      _getArtifactDetailTool(),
    ];

/// Build-list tool: `bitrise_get_builds`.
ToolDefinition _getBuildsTool() => ToolDefinition(
      name: 'bitrise_get_builds',
      description: 'List builds for a Bitrise app by app slug',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'app_slug',
          description: 'The Bitrise app slug',
          required: true,
        ),
      ],
    );

/// Build-detail tool: `bitrise_get_build_detail`.
ToolDefinition _getBuildDetailTool() => ToolDefinition(
      name: 'bitrise_get_build_detail',
      description: 'Get details of a single Bitrise build',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'app_slug',
          description: 'The Bitrise app slug',
          required: true,
        ),
        ToolParam(
          name: 'build_slug',
          description: 'The Bitrise build slug',
          required: true,
        ),
      ],
    );

/// Parameterized build-trigger tool: `bitrise_trigger_build_with_params`.
ToolDefinition _triggerBuildWithParamsTool() => ToolDefinition(
      name: 'bitrise_trigger_build_with_params',
      description: 'Trigger a Bitrise build with a workflow and environments',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'app_slug',
          description: 'The Bitrise app slug',
          required: true,
        ),
        ToolParam(
          name: 'workflow',
          description: 'The workflow to run',
          required: true,
        ),
        ToolParam(
          name: 'environments',
          description: 'Environment variable objects for the build',
          type: 'array',
          required: false,
        ),
      ],
    );

/// Workflows tool: `bitrise_get_workflows` (Java alias
/// `bitrise_list_workflows`).
ToolDefinition _getWorkflowsTool() => ToolDefinition(
      name: 'bitrise_get_workflows',
      aliases: ['bitrise_list_workflows'],
      description: 'List the workflows available to a Bitrise app',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'app_slug',
          description: 'The Bitrise app slug',
          required: true,
        ),
      ],
    );

/// Artifacts tool: `bitrise_get_artifacts`.
ToolDefinition _getArtifactsTool() => ToolDefinition(
      name: 'bitrise_get_artifacts',
      description: 'List artifacts produced by a Bitrise build',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'app_slug',
          description: 'The Bitrise app slug',
          required: true,
        ),
        ToolParam(
          name: 'build_slug',
          description: 'The Bitrise build slug',
          required: true,
        ),
      ],
    );

/// Artifact-detail tool: `bitrise_get_artifact_detail`.
ToolDefinition _getArtifactDetailTool() => ToolDefinition(
      name: 'bitrise_get_artifact_detail',
      description: 'Get details of a single Bitrise build artifact',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'app_slug',
          description: 'The Bitrise app slug',
          required: true,
        ),
        ToolParam(
          name: 'build_slug',
          description: 'The Bitrise build slug',
          required: true,
        ),
        ToolParam(
          name: 'artifact_slug',
          description: 'The Bitrise artifact slug',
          required: true,
        ),
      ],
    );

/// Java-parity build tools (Java `Bitrise.java` @MCPTool names the agent
/// scripts call): `bitrise_list_builds`, `bitrise_trigger_build`,
/// `bitrise_abort_build`.
List<ToolDefinition> _javaParityBuildTools() => [
      _javaListBuildsTool(),
      _javaTriggerBuildTool(),
      _javaAbortBuildTool(),
    ];

/// Build-list tool (Java name): `bitrise_list_builds`.
ToolDefinition _javaListBuildsTool() => ToolDefinition(
      name: 'bitrise_list_builds',
      description: 'List builds for a Bitrise app. Optionally filter by '
          'workflow, branch or status. Status codes: not_started, '
          'in_progress, success, failed, aborted',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'appSlug',
          description: 'The Bitrise app slug',
          required: true,
        ),
        ToolParam(
          name: 'workflowId',
          description: 'Filter by workflow ID / name',
          required: false,
        ),
        ToolParam(
          name: 'branch',
          description: 'Filter by branch name',
          required: false,
        ),
        ToolParam(
          name: 'status',
          description: 'Filter by status: not_started | in_progress | success '
              '| failed | aborted',
          required: false,
        ),
        ToolParam(
          name: 'limit',
          description: 'Max results to return (default 20, max 100)',
          type: 'number',
          required: false,
        ),
        ToolParam(
          name: 'next',
          description: 'Pagination cursor from previous response paging.next',
          required: false,
        ),
      ],
    );

/// Build-trigger tool (Java name): `bitrise_trigger_build`.
ToolDefinition _javaTriggerBuildTool() => ToolDefinition(
      name: 'bitrise_trigger_build',
      description: 'Trigger a new Bitrise workflow build for an app. Supports '
          'custom branch, environment variables, and workflow selection',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'appSlug',
          description: 'The Bitrise app slug',
          required: true,
        ),
        ToolParam(
          name: 'workflowId',
          description: "Workflow ID to trigger (e.g. 'primary', 'deploy')",
          required: true,
        ),
        ToolParam(
          name: 'branch',
          description: 'Branch to build (defaults to main/master)',
          required: false,
        ),
        ToolParam(
          name: 'commitMessage',
          description: 'Commit message for the build',
          required: false,
        ),
        ToolParam(
          name: 'envVars',
          description: 'JSON array of env var objects: '
              '[{"mapped_to":"KEY","value":"val","is_expand":true}]',
          required: false,
        ),
      ],
    );

/// Build-abort tool (Java name): `bitrise_abort_build`.
ToolDefinition _javaAbortBuildTool() => ToolDefinition(
      name: 'bitrise_abort_build',
      description: 'Abort a running Bitrise build with an optional reason '
          'message',
      integration: 'bitrise',
      category: 'builds',
      params: [
        ToolParam(
          name: 'appSlug',
          description: 'The Bitrise app slug',
          required: true,
        ),
        ToolParam(
          name: 'buildSlug',
          description: 'The build slug to abort',
          required: true,
        ),
        ToolParam(
          name: 'reason',
          description: 'Human-readable reason for aborting the build',
          required: false,
        ),
      ],
    );

/// Artifact tools (Java `Bitrise.java` names): `bitrise_list_build_artifacts`
/// / `bitrise_get_build_artifact`.
List<ToolDefinition> _artifactTools() => [
      ToolDefinition(
        name: 'bitrise_list_build_artifacts',
        description: 'List all artifacts produced by a Bitrise build (APKs, '
            'IPAs, logs, test results, etc.)',
        integration: 'bitrise',
        category: 'artifacts',
        params: [
          ToolParam(
            name: 'appSlug',
            description: 'The Bitrise app slug',
            required: true,
          ),
          ToolParam(
            name: 'buildSlug',
            description: 'The build slug',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'bitrise_get_build_artifact',
        description: 'Get details and expiring download URL for a specific '
            'Bitrise build artifact',
        integration: 'bitrise',
        category: 'artifacts',
        params: [
          ToolParam(
            name: 'appSlug',
            description: 'The Bitrise app slug',
            required: true,
          ),
          ToolParam(
            name: 'buildSlug',
            description: 'The build slug',
            required: true,
          ),
          ToolParam(
            name: 'artifactSlug',
            description: 'The artifact slug',
            required: true,
          ),
        ],
      ),
    ];

/// Executes Bitrise MCP tools by dispatching to [BitriseClient].
class BitriseToolExecutor {
  final BitriseClient _client;

  /// Creates an executor bound to [_client].
  BitriseToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Bitrise tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Bitrise tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'bitrise_test': (_) => _client.testConnection(),
    'bitrise_get_apps': (_) => _client.getApps(),
    'bitrise_get_builds': (a) => _client.getBuilds(a['app_slug'] as String),
    'bitrise_list_builds': (a) =>
        _client.getBuilds((a['appSlug'] ?? a['app_slug']) as String),
    'bitrise_get_build_detail': (a) => _client.getBuildDetail(
          a['app_slug'] as String,
          a['build_slug'] as String,
        ),
    'bitrise_trigger_build': (a) => _client.triggerBuildWithParams(
          (a['appSlug'] ?? a['app_slug']) as String,
          (a['workflowId'] ?? a['workflow'] ?? '') as String,
          _optionalEnvList(a, 'environments') ?? _envVarsList(a['envVars']),
        ),
    'bitrise_trigger_build_with_params': (a) => _client.triggerBuildWithParams(
          a['app_slug'] as String,
          a['workflow'] as String,
          _optionalEnvList(a, 'environments'),
        ),
    'bitrise_abort_build': (a) => _client.abortBuild(
          (a['appSlug'] ?? a['app_slug']) as String,
          (a['buildSlug'] ?? a['build_slug']) as String,
        ),
    'bitrise_get_workflows': (a) =>
        _client.getWorkflows(a['app_slug'] as String),
    'bitrise_get_artifacts': (a) => _client.getArtifacts(
          a['app_slug'] as String,
          a['build_slug'] as String,
        ),
    'bitrise_list_build_artifacts': (a) => _client.getArtifacts(
          (a['appSlug'] ?? a['app_slug']) as String,
          (a['buildSlug'] ?? a['build_slug']) as String,
        ),
    'bitrise_get_artifact_detail': (a) => _client.getArtifactDetail(
          a['app_slug'] as String,
          a['build_slug'] as String,
          a['artifact_slug'] as String,
        ),
    'bitrise_get_build_artifact': (a) => _client.getArtifactDetail(
          (a['appSlug'] ?? a['app_slug']) as String,
          (a['buildSlug'] ?? a['build_slug']) as String,
          (a['artifactSlug'] ?? a['artifact_slug']) as String,
        ),
  };
}

/// Parses a JSON-array `envVars` string into environments, or `null`.
List<Map<String, dynamic>>? _envVarsList(dynamic envVars) {
  if (envVars is List) return _coerceEnvList(envVars);
  if (envVars is String && envVars.isNotEmpty) {
    try {
      final decoded = jsonDecode(envVars);
      if (decoded is List) return _coerceEnvList(decoded);
    } on FormatException {
      // Unparsable envVars are ignored (Java logs and continues).
    }
  }
  return null;
}

/// Maps decoded entries to environment maps, dropping non-map items.
List<Map<String, dynamic>>? _coerceEnvList(List decoded) {
  final items = decoded.whereType<Map>().map(Map<String, dynamic>.from);
  return items.isEmpty ? null : items.toList();
}

/// Extracts an optional environments list from [args], or `null`.
List<Map<String, dynamic>>? _optionalEnvList(
  Map<String, dynamic> args,
  String key,
) {
  final value = args[key];
  if (value is! List) return null;
  return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
