/// MCP tool definitions and dispatcher for the Jenkins integration.
///
/// The tool list ports the Jenkins subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [JenkinsClient]
/// call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'jenkins_client.dart';

/// Returns all Jenkins MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> jenkinsTools() => [
      ..._systemTools(),
      ..._jobTools(),
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
      params: [
        ToolParam(
          name: 'name',
          description: 'The Jenkins job name',
          required: true,
        ),
      ],
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
  };
}
