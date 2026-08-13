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
      ..._commentReadTools(),
      ..._assignTools(),
      ..._fieldTools(),
      ..._createTools(),
      ..._transitionReadTools(),
      ..._deleteTools(),
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

/// Comment-read tool: `jira_get_comments`.
List<ToolDefinition> _commentReadTools() => [
      ToolDefinition(
        name: 'jira_get_comments',
        description: 'Get all comments on a Jira ticket',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
        ],
      ),
    ];

/// Assignment tool: `jira_assign`.
List<ToolDefinition> _assignTools() => [
      ToolDefinition(
        name: 'jira_assign',
        description: 'Assign a Jira ticket to a user by account ID',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
          ToolParam(
            name: 'accountId',
            description: 'The Atlassian account ID of the assignee',
            required: true,
          ),
        ],
      ),
    ];

/// Field-mutation tools: `jira_update_field` / `jira_clear_field`.
List<ToolDefinition> _fieldTools() => [
      ToolDefinition(
        name: 'jira_update_field',
        description: 'Update a single field on a Jira ticket',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
          ToolParam(
            name: 'field',
            description: 'The field name to update',
            required: true,
          ),
          ToolParam(
            name: 'value',
            description: 'The new value for the field',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'jira_clear_field',
        description: 'Clear (set to null) a single field on a Jira ticket',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
          ToolParam(
            name: 'field',
            description: 'The field name to clear',
            required: true,
          ),
        ],
      ),
    ];

/// Create tool: `jira_create_ticket`.
List<ToolDefinition> _createTools() => [
      ToolDefinition(
        name: 'jira_create_ticket',
        description:
            'Create a basic Jira ticket with summary and optional description',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'project',
            description: 'The project key (e.g. PROJ)',
            required: true,
          ),
          ToolParam(
            name: 'issueType',
            description: 'The issue type name (e.g. Task, Bug)',
            required: true,
          ),
          ToolParam(
            name: 'summary',
            description: 'The ticket summary / title',
            required: true,
          ),
          ToolParam(
            name: 'description',
            description: 'The ticket description',
            required: false,
          ),
        ],
      ),
    ];

/// Transition-read tool: `jira_get_transitions`.
List<ToolDefinition> _transitionReadTools() => [
      ToolDefinition(
        name: 'jira_get_transitions',
        description: 'Get available workflow transitions for a Jira ticket',
        integration: 'jira',
        category: 'workflow',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
        ],
      ),
    ];

/// Delete tool: `jira_delete_ticket`.
List<ToolDefinition> _deleteTools() => [
      ToolDefinition(
        name: 'jira_delete_ticket',
        description: 'Delete a Jira ticket',
        integration: 'jira',
        category: 'ticket_management',
        params: [
          ToolParam(
            name: 'key',
            description: 'The Jira ticket key (e.g. PROJ-123)',
            required: true,
          ),
        ],
      ),
    ];

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
    'jira_get_comments': (a) => _client.getComments(a['key'] as String),
    'jira_assign': (a) => _client.assignTo(
          a['key'] as String,
          a['accountId'] as String,
        ),
    'jira_update_field': (a) => _client.updateField(
          a['key'] as String,
          a['field'] as String,
          a['value'],
        ),
    'jira_create_ticket': (a) => _client.createTicketBasic(
          a['project'] as String,
          a['issueType'] as String,
          a['summary'] as String,
          a['description'] as String?,
        ),
    'jira_get_transitions': (a) => _client.getTransitions(a['key'] as String),
    'jira_delete_ticket': (a) => _client.deleteTicket(a['key'] as String),
    'jira_clear_field': (a) => _client.clearField(
          a['key'] as String,
          a['field'] as String,
        ),
  };
}
