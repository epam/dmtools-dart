/// MCP tool definitions and dispatcher for the Jenkins integration.
///
/// The tool list ports the Jenkins subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [JenkinsClient]
/// call.
library;

import '../../mcp/tool_args.dart';
import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'jenkins_client.dart';

/// Reusable parameter: Jenkins job name.
const _nameParam = ToolParam(
  name: 'name',
  description: 'The Jenkins job name',
  required: true,
);

/// Reusable parameters: job name plus numeric build number.
final _nameAndBuildParams = [
  _nameParam,
  const ToolParam(
    name: 'buildNumber',
    description: 'The build number',
    type: 'number',
    required: true,
  ),
];

/// Returns all Jenkins MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> jenkinsTools() => [
      ..._systemTools(),
      ..._jobTools(),
      ..._buildTools(),
    ];

/// Connectivity-check tool: `jenkins_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'jenkins_test',
        description: 'Test Jenkins connectivity by fetching the root node',
        integration: 'jenkins',
        category: 'system',
        params: [],
      ),
    ];

/// Job tools: `jenkins_get_jobs`, `jenkins_trigger_job`.
List<ToolDefinition> _jobTools() => [
      _getJobsTool(),
      _triggerJobTool(),
    ];

/// Build tools: `jenkins_get_build`, `jenkins_get_build_log`,
/// `jenkins_get_last_build`.
List<ToolDefinition> _buildTools() => [
      _getBuildTool(),
      _getBuildLogTool(),
      _getLastBuildTool(),
    ];

/// Job-list tool: `jenkins_get_jobs`.
ToolDefinition _getJobsTool() => ToolDefinition(
      name: 'jenkins_get_jobs',
      description: 'List Jenkins jobs with their names and URLs',
      integration: 'jenkins',
      category: 'jobs',
      params: [],
    );

/// Job-trigger tool: `jenkins_trigger_job`.
ToolDefinition _triggerJobTool() => ToolDefinition(
      name: 'jenkins_trigger_job',
      description: 'Trigger a Jenkins job build by job name',
      integration: 'jenkins',
      category: 'jobs',
      params: [_nameParam],
    );

/// Build-detail tool: `jenkins_get_build`.
ToolDefinition _getBuildTool() => ToolDefinition(
      name: 'jenkins_get_build',
      description: 'Get details of a Jenkins job build by build number',
      integration: 'jenkins',
      category: 'builds',
      params: _nameAndBuildParams,
    );

/// Build-log tool: `jenkins_get_build_log`.
ToolDefinition _getBuildLogTool() => ToolDefinition(
      name: 'jenkins_get_build_log',
      description: 'Get the console log of a Jenkins job build',
      integration: 'jenkins',
      category: 'builds',
      params: _nameAndBuildParams,
    );

/// Last-build tool: `jenkins_get_last_build`.
ToolDefinition _getLastBuildTool() => ToolDefinition(
      name: 'jenkins_get_last_build',
      description: 'Get details of the last build of a Jenkins job',
      integration: 'jenkins',
      category: 'builds',
      params: [_nameParam],
    );

/// Executes Jenkins MCP tools by dispatching to [JenkinsClient].
class JenkinsToolExecutor {
  final JenkinsClient _client;

  /// Creates an executor bound to [_client].
  JenkinsToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Jenkins tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Jenkins tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'jenkins_test': (_) => _client.testConnection(),
    'jenkins_get_jobs': (_) => _client.getJobs(),
    'jenkins_trigger_job': (a) => _client.triggerJob(a['name'] as String),
    'jenkins_get_build': (a) => _client.getBuild(
          a['name'] as String,
          requiredInt(a, 'buildNumber'),
        ),
    'jenkins_get_build_log': (a) => _client.getBuildLog(
          a['name'] as String,
          requiredInt(a, 'buildNumber'),
        ),
    'jenkins_get_last_build': (a) => _client.getLastBuild(a['name'] as String),
  };
}
