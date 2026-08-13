/// MCP tool definitions and dispatcher for the Bitrise integration.
///
/// The tool list ports the Bitrise subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [BitriseClient]
/// call.
library;

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

/// App tool: `bitrise_get_apps`.
List<ToolDefinition> _appTools() => [
      ToolDefinition(
        name: 'bitrise_get_apps',
        description: 'List all Bitrise apps accessible to the token',
        integration: 'bitrise',
        category: 'apps',
        params: [],
      ),
    ];

/// Build tools: `bitrise_get_builds`, `bitrise_get_build_detail`,
/// `bitrise_trigger_build`, `bitrise_trigger_build_with_params`,
/// `bitrise_get_workflows`, `bitrise_get_artifacts`.
List<ToolDefinition> _buildTools() => [
      _getBuildsTool(),
      _getBuildDetailTool(),
      _triggerBuildTool(),
      _triggerBuildWithParamsTool(),
      _abortBuildTool(),
      _getWorkflowsTool(),
      _getArtifactsTool(),
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

/// Build-trigger tool: `bitrise_trigger_build`.
ToolDefinition _triggerBuildTool() => ToolDefinition(
      name: 'bitrise_trigger_build',
      description: 'Trigger a new build for a Bitrise app by app slug',
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

/// Build-abort tool: `bitrise_abort_build`.
ToolDefinition _abortBuildTool() => ToolDefinition(
      name: 'bitrise_abort_build',
      description: 'Abort an in-progress Bitrise build',
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

/// Workflows tool: `bitrise_get_workflows`.
ToolDefinition _getWorkflowsTool() => ToolDefinition(
      name: 'bitrise_get_workflows',
      description: 'List the workflow build slots for a Bitrise app',
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
    'bitrise_get_build_detail': (a) => _client.getBuildDetail(
          a['app_slug'] as String,
          a['build_slug'] as String,
        ),
    'bitrise_trigger_build': (a) =>
        _client.triggerBuild(a['app_slug'] as String),
    'bitrise_trigger_build_with_params': (a) => _client.triggerBuildWithParams(
          a['app_slug'] as String,
          a['workflow'] as String,
          _optionalEnvList(a, 'environments'),
        ),
    'bitrise_abort_build': (a) => _client.abortBuild(
          a['app_slug'] as String,
          a['build_slug'] as String,
        ),
    'bitrise_get_workflows': (a) =>
        _client.getWorkflows(a['app_slug'] as String),
    'bitrise_get_artifacts': (a) => _client.getArtifacts(
          a['app_slug'] as String,
          a['build_slug'] as String,
        ),
  };
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
