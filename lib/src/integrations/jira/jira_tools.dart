/// MCP tool definitions and dispatcher for the Jira integration.
///
/// The tool list ports the Jira subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [JiraClient] call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'jira_client.dart';

/// Returns all Jira MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> jiraTools() => [
      ..._systemTools(),
      ..._ticketTools(),
      ..._searchTools(),
      ..._commentTools(),
      ..._labelTools(),
      ..._statusTools(),
    ];

/// Connectivity-check tool: `jira_test`.
List<ToolDefinition> _systemTools() => [
      ToolDefinition(
        name: 'jira_test',
        description:
            'Test Jira connectivity by fetching the current user profile',
        integration: 'jira',
        category: 'system',
        params: [],
      ),
    ];

/// Ticket-read tool: `jira_get_ticket`.
List<ToolDefinition> _ticketTools() => [
      ToolDefinition(
        name: 'jira_get_ticket',
        description: 'Get a Jira ticket by key',
        integration: 'jira',
        category: 'ticket_management',
        aliases: ['tracker_get_ticket'],
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
          ToolParam(
            name: 'fields',
            description: 'Comma-separated field names to return',
            type: 'array',
            required: false,
          ),
        ],
      ),
    ];

/// JQL search tool: `jira_search_by_jql`.
List<ToolDefinition> _searchTools() => [
      ToolDefinition(
        name: 'jira_search_by_jql',
        description: 'Search Jira issues by JQL query',
        integration: 'jira',
        category: 'search',
        params: [
          ToolParam(
            name: 'jql',
            description: 'The JQL query string',
            required: true,
          ),
          ToolParam(
            name: 'fields',
            description: 'Comma-separated field names to return',
            type: 'array',
            required: false,
          ),
        ],
      ),
    ];

/// Comment tool: `jira_post_comment`.
List<ToolDefinition> _commentTools() => [
      ToolDefinition(
        name: 'jira_post_comment',
        description: 'Post a comment on a Jira ticket',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
          ToolParam(
            name: 'comment',
            description: 'The comment text to post',
            required: true,
          ),
        ],
      ),
    ];

/// Label-mutation tools: `jira_add_label` / `jira_remove_label`.
List<ToolDefinition> _labelTools() => [
      ToolDefinition(
        name: 'jira_add_label',
        description: 'Add a label to a Jira ticket',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
          ToolParam(
            name: 'label',
            description: 'The label to add',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'jira_remove_label',
        description: 'Remove a label from a Jira ticket',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
          ToolParam(
            name: 'label',
            description: 'The label to remove',
            required: true,
          ),
        ],
      ),
    ];

/// Workflow-transition tool: `jira_move_to_status`.
List<ToolDefinition> _statusTools() => [
      ToolDefinition(
        name: 'jira_move_to_status',
        description: 'Transition a Jira ticket to a target status',
        integration: 'jira',
        category: 'workflow',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
          ToolParam(
            name: 'status',
            description: 'The target status or transition name',
            required: true,
          ),
        ],
      ),
    ];

/// Reads an optional string-array argument as `List<String>?`.
List<String>? _optionalStringList(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is List) return value.cast<String>();
  if (value is String) return value.split(',');
  return null;
}

/// Executes Jira MCP tools by dispatching to [JiraClient].
class JiraToolExecutor {
  final JiraClient _client;

  /// Creates an executor bound to [_client].
  JiraToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Jira tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Jira tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'jira_test': (_) => _client.testConnection(),
    'jira_get_ticket': (a) => _client.getTicket(
          a['key'] as String,
          _optionalStringList(a, 'fields'),
        ),
    'jira_search_by_jql': (a) => _client.searchByJql(
          a['jql'] as String,
          _optionalStringList(a, 'fields'),
        ),
    'jira_post_comment': (a) => _client.postComment(
          a['key'] as String,
          a['comment'] as String,
        ),
    'jira_add_label': (a) => _client.addLabel(
          a['key'] as String,
          a['label'] as String,
        ),
    'jira_remove_label': (a) => _client.removeLabel(
          a['key'] as String,
          a['label'] as String,
        ),
    'jira_move_to_status': (a) => _client.moveToStatus(
          a['key'] as String,
          a['status'] as String,
        ),
  };
}
