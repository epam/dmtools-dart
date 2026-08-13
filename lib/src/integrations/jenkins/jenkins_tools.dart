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
      ..._queueTools(),
      ..._configTools(),
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

/// Job tools: `jenkins_get_jobs`, `jenkins_trigger_job`,
/// `jenkins_get_job_details`.
List<ToolDefinition> _jobTools() => [
      _getJobsTool(),
      _triggerJobTool(),
      _getJobDetailsTool(),
    ];

/// Build tools: `jenkins_get_build`, `jenkins_get_build_log`,
/// `jenkins_get_last_build`, `jenkins_get_build_artifacts`.
List<ToolDefinition> _buildTools() => [
      _getBuildTool(),
      _getBuildLogTool(),
      _getLastBuildTool(),
      _getBuildArtifactsTool(),
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

/// Build-artifacts tool: `jenkins_get_build_artifacts`.
ToolDefinition _getBuildArtifactsTool() => ToolDefinition(
      name: 'jenkins_get_build_artifacts',
      description: 'List artifacts produced by a Jenkins job build',
      integration: 'jenkins',
      category: 'builds',
      params: _nameAndBuildParams,
    );

/// Job-details tool: `jenkins_get_job_details`.
ToolDefinition _getJobDetailsTool() => ToolDefinition(
      name: 'jenkins_get_job_details',
      description: 'Get Jenkins job details with recent build results',
      integration: 'jenkins',
      category: 'jobs',
      params: [_nameParam],
    );

/// Queue tools: `jenkins_get_queue`, `jenkins_cancel_build`.
List<ToolDefinition> _queueTools() => [
      ToolDefinition(
        name: 'jenkins_get_queue',
        description: 'Get the current Jenkins build queue',
        integration: 'jenkins',
        category: 'queue',
        params: [],
      ),
      ToolDefinition(
        name: 'jenkins_cancel_build',
        description: 'Cancel a queued Jenkins build by queue ID',
        integration: 'jenkins',
        category: 'queue',
        params: [
          ToolParam(
            name: 'queueId',
            description: 'The queue item ID to cancel',
            type: 'number',
            required: true,
          ),
        ],
      ),
    ];

/// Config tools: `jenkins_get_job_config`.
List<ToolDefinition> _configTools() => [
      ToolDefinition(
        name: 'jenkins_get_job_config',
        description: 'Get the XML configuration of a Jenkins job',
        integration: 'jenkins',
        category: 'config',
        params: [_nameParam],
      ),
    ];

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
    'jenkins_get_job_details': (a) =>
        _client.getJobDetails(a['name'] as String),
    'jenkins_get_queue': (_) => _client.getQueue(),
    'jenkins_cancel_build': (a) =>
        _client.cancelBuild(requiredInt(a, 'queueId')),
    'jenkins_get_build_artifacts': (a) => _client.getBuildArtifacts(
          a['name'] as String,
          requiredInt(a, 'buildNumber'),
        ),
    'jenkins_get_job_config': (a) => _client.getJobConfig(a['name'] as String),
  };
}
