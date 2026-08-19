/// MCP tool definitions and dispatcher for the Jira integration.
///
/// The tool list ports the Jira subset of the Java `@MCPTool` catalog; the
/// executor routes a tool name + arguments to the matching [JiraClient] call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'jira_client.dart';

part 'jira_agile_tools.dart';
part 'jira_attachment_tools.dart';
part 'jira_export_tools.dart';
part 'jira_fix_version_tools.dart';
part 'jira_issue_type_tools.dart';
part 'jira_metadata_tools.dart';
part 'jira_project_tools.dart';
part 'jira_scheme_tools.dart';
part 'jira_search_tools.dart';
part 'jira_transition_tools.dart';
part 'jira_user_tools.dart';
part 'jira_watcher_tools.dart';
part 'jira_workflow_tools.dart';
part 'jira_worklog_tools.dart';

/// Reusable parameter: Jira ticket key.
const _keyParam = ToolParam(
  name: 'key',
  description: 'The Jira ticket key (e.g. PROJ-123)',
  required: true,
);

/// Reusable parameter: Jira project key.
const _projectParam = ToolParam(
  name: 'project',
  description: 'The project key (e.g. PROJ)',
  required: true,
);

/// Reusable parameters: JQL query string plus optional field list.
const _jqlSearchParams = [
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
];

/// Builds a Jira tool definition with standard defaults.
///
/// [category] defaults to `'ticket_management'`; override for tools that
/// belong to a different group.
ToolDefinition _jiraTool({
  required String name,
  required String description,
  String category = 'ticket_management',
  List<String> aliases = const [],
  List<ToolParam> params = const [],
}) =>
    ToolDefinition(
      name: name,
      description: description,
      integration: 'jira',
      category: category,
      aliases: aliases,
      params: params,
    );

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
      ..._projectMetaTools(),
      ..._ticketWriteTools(),
      ..._subtaskTools(),
      ..._createWithParentTools(),
      ..._commentIfExistsTools(),
      ..._adfFieldTools(),
      ..._fieldsByNameTools(),
      ..._rawUpdateTools(),
      ..._linkTools(),
      ..._genericRequestTools(),
      ..._projectDetailTools(),
      ..._transitionTools(),
      ..._userTools(),
      ..._attachmentTools(),
      ..._projectLifecycleTools(),
      ..._workflowTools(),
      ..._projectStructureTools(),
      ..._boardConfigTools(),
      ..._schemeTools(),
      ..._issueTypeTools(),
      ..._fixVersionTools(),
      ..._myProfileTools(),
      ..._searchPageTools(),
      ..._attachmentReadTools(),
      ..._worklogTools(),
      ..._watcherTools(),
      ..._metadataTools(),
      ..._exportTools(),
      ..._agileTools(),
    ];

/// Connectivity-check tool: `jira_test`.
List<ToolDefinition> _systemTools() => [
      _jiraTool(
        name: 'jira_test',
        description:
            'Test Jira connectivity by fetching the current user profile',
        category: 'system',
      ),
    ];

/// Ticket-read tool: `jira_get_ticket`.
List<ToolDefinition> _ticketTools() => [
      _jiraTool(
        name: 'jira_get_ticket',
        description: 'Get a Jira ticket by key',
        aliases: ['tracker_get_ticket'],
        params: [
          _keyParam,
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
      _jiraTool(
        name: 'jira_search_by_jql',
        description: 'Search Jira issues by JQL query',
        category: 'search',
        params: _jqlSearchParams,
      ),
    ];

/// Comment tool: `jira_post_comment`.
List<ToolDefinition> _commentTools() => [
      _jiraTool(
        name: 'jira_post_comment',
        description: 'Post a comment on a Jira ticket',
        params: [
          _keyParam,
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
      _jiraTool(
        name: 'jira_add_label',
        description: 'Add a label to a Jira ticket',
        params: [
          _keyParam,
          ToolParam(
            name: 'label',
            description: 'The label to add',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_remove_label',
        description: 'Remove a label from a Jira ticket',
        params: [
          _keyParam,
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
      _jiraTool(
        name: 'jira_move_to_status',
        description: 'Transition a Jira ticket to a target status',
        category: 'workflow',
        params: [
          _keyParam,
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
      _jiraTool(
        name: 'jira_get_comments',
        description: 'Get all comments on a Jira ticket',
        params: [_keyParam],
      ),
    ];

/// Assignment tool: `jira_assign`.
List<ToolDefinition> _assignTools() => [
      _jiraTool(
        name: 'jira_assign',
        description: 'Assign a Jira ticket to a user by account ID',
        params: [
          _keyParam,
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
      _jiraTool(
        name: 'jira_update_field',
        description: 'Update a single field on a Jira ticket',
        params: [
          _keyParam,
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
      _jiraTool(
        name: 'jira_clear_field',
        description: 'Clear (set to null) a single field on a Jira ticket',
        params: [
          _keyParam,
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
      _jiraTool(
        name: 'jira_create_ticket',
        aliases: ['jira_create_ticket_basic'],
        description:
            'Create a basic Jira ticket with summary and optional description',
        params: [
          _projectParam,
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
      _jiraTool(
        name: 'jira_get_transitions',
        description: 'Get available workflow transitions for a Jira ticket',
        category: 'workflow',
        params: [_keyParam],
      ),
    ];

/// Delete tool: `jira_delete_ticket`.
List<ToolDefinition> _deleteTools() => [
      _jiraTool(
        name: 'jira_delete_ticket',
        description: 'Delete a Jira ticket',
        params: [_keyParam],
      ),
    ];

/// Project-metadata read tools: issue types, fields, components, versions.
List<ToolDefinition> _projectMetaTools() => [
      _jiraTool(
        name: 'jira_get_issue_types',
        description: 'Get available issue types for a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
      _jiraTool(
        name: 'jira_get_fields',
        description: 'Get available fields for a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
      _jiraTool(
        name: 'jira_get_components',
        description: 'Get all components for a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
      _jiraTool(
        name: 'jira_get_fix_versions',
        description: 'Get all fix versions for a Jira project',
        category: 'project_management',
        params: [_projectParam],
      ),
    ];

/// Ticket field-mutation tools: fix version, priority, description.
List<ToolDefinition> _ticketWriteTools() => [
      _jiraTool(
        name: 'jira_set_fix_version',
        description: 'Set the fix version on a Jira ticket',
        params: [
          _keyParam,
          ToolParam(
            name: 'fixVersion',
            description: 'The fix version name to set',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_set_priority',
        description: 'Set the priority on a Jira ticket',
        params: [
          _keyParam,
          ToolParam(
            name: 'priority',
            description: 'The priority name to set',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_update_description',
        description: 'Update the description of a Jira ticket',
        params: [
          _keyParam,
          ToolParam(
            name: 'description',
            description: 'The new description text',
            required: true,
          ),
        ],
      ),
    ];

/// Subtask read tool: `jira_get_subtasks`.
List<ToolDefinition> _subtaskTools() => [
      _jiraTool(
        name: 'jira_get_subtasks',
        description: 'Get all subtasks of a Jira ticket',
        params: [_keyParam],
      ),
    ];

/// Create-with-parent tool: `jira_create_ticket_with_parent`.
List<ToolDefinition> _createWithParentTools() => [
      _jiraTool(
        name: 'jira_create_ticket_with_parent',
        description: 'Create a new Jira ticket linked to a parent ticket',
        params: [
          _projectParam,
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
            name: 'parentKey',
            description: 'The key of the parent ticket',
            required: true,
          ),
        ],
      ),
    ];

/// Comment-if-not-exists tool: `jira_post_comment_if_not_exists`.
List<ToolDefinition> _commentIfExistsTools() => [
      _jiraTool(
        name: 'jira_post_comment_if_not_exists',
        description: 'Post a comment only if it does not already exist',
        params: [
          _keyParam,
          ToolParam(
            name: 'comment',
            description: 'The comment text to post',
            required: true,
          ),
        ],
      ),
    ];

/// ADF field update tool: `jira_update_field_as_adf`.
List<ToolDefinition> _adfFieldTools() => [
      _jiraTool(
        name: 'jira_update_field_as_adf',
        description: 'Update a Jira ticket field with an ADF document',
        params: [
          _keyParam,
          ToolParam(
            name: 'field',
            description: 'The field name to update',
            required: true,
          ),
          ToolParam(
            name: 'value',
            description: 'The ADF document to set as the field value',
            type: 'object',
            required: true,
          ),
        ],
      ),
    ];

/// Field-by-name tools: search field definitions by display name and update
/// every matching field on a ticket.
List<ToolDefinition> _fieldsByNameTools() => [
      _jiraTool(
        name: 'jira_get_all_fields_with_name',
        description: 'Find all Jira field definitions matching a display name',
        category: 'project_management',
        params: [
          _projectParam,
          ToolParam(
            name: 'fieldName',
            description: 'The display name to search for',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_update_all_fields_with_name',
        description: 'Update every field matching a display name on a ticket',
        params: [
          _keyParam,
          ToolParam(
            name: 'fieldName',
            description: 'The display name of the fields to update',
            required: true,
          ),
          ToolParam(
            name: 'value',
            description: 'The new value for the fields',
            required: true,
          ),
        ],
      ),
    ];

/// Raw update tool: `jira_update_ticket`.
List<ToolDefinition> _rawUpdateTools() => [
      _jiraTool(
        name: 'jira_update_ticket',
        description: 'Update a Jira ticket with raw JSON parameters',
        params: [
          _keyParam,
          ToolParam(
            name: 'jsonParams',
            description: 'Raw JSON object to send as the update body',
            type: 'object',
            required: true,
          ),
        ],
      ),
    ];

/// Issue link tools: create link + list link types.
List<ToolDefinition> _linkTools() => [
      _jiraTool(
        name: 'jira_link_issues',
        description: 'Create a link between two Jira tickets',
        params: [
          ToolParam(
            name: 'linkType',
            description: 'The link type name (e.g. Blocks, Relates)',
            required: true,
          ),
          ToolParam(
            name: 'inwardKey',
            description: 'The key of the inward issue',
            required: true,
          ),
          ToolParam(
            name: 'outwardKey',
            description: 'The key of the outward issue',
            required: true,
          ),
        ],
      ),
      _jiraTool(
        name: 'jira_get_issue_link_types',
        description: 'Get all available Jira issue link types',
        category: 'project_management',
      ),
    ];

/// Generic request tool: `jira_execute_request`.
List<ToolDefinition> _genericRequestTools() => [
      _jiraTool(
        name: 'jira_execute_request',
        description:
            'Execute a GET request against an arbitrary Jira REST path',
        category: 'system',
        params: [
          ToolParam(
            name: 'url',
            description: 'The REST path relative to /rest/api/latest/',
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
    ..._coreHandlers(),
    ..._projectMetaHandlers(),
    ..._ticketWriteHandlers(),
    ..._commentIfExistsHandlers(),
    ..._adfFieldHandlers(),
    ..._fieldsByNameHandlers(),
    ..._rawUpdateHandlers(),
    ..._linkHandlers(),
    ..._genericRequestHandlers(),
    ..._projectHandlers(),
    ..._transitionHandlers(),
    ..._userHandlers(),
    ..._attachmentHandlers(),
    ..._workflowHandlers(),
    ..._schemeHandlers(),
    ..._issueTypeHandlers(),
    ..._fixVersionHandlers(),
    ..._searchPageHandlers(),
    ..._worklogHandlers(),
    ..._watcherHandlers(),
    ..._metadataHandlers(),
    ..._exportHandlers(),
    ..._agileHandlers(),
  };

  /// Dispatch entries for the core Jira ticket tools.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)> _coreHandlers() =>
      {
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
        'jira_get_transitions': (a) =>
            _client.getTransitions(a['key'] as String),
        'jira_delete_ticket': (a) => _client.deleteTicket(a['key'] as String),
        'jira_clear_field': (a) => _client.clearField(
              a['key'] as String,
              a['field'] as String,
            ),
      };

  /// Dispatch entries for the project-metadata read tools.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _projectMetaHandlers() => {
            'jira_get_issue_types': (a) =>
                _client.getIssueTypes(a['project'] as String),
            'jira_get_fields': (a) => _client.getFields(a['project'] as String),
            'jira_get_components': (a) =>
                _client.getComponents(a['project'] as String),
            'jira_get_fix_versions': (a) =>
                _client.getFixVersions(a['project'] as String),
          };

  /// Dispatch entries for the ticket write, subtask, and create-with-parent
  /// tools.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _ticketWriteHandlers() => {
            'jira_set_fix_version': (a) => _client.setFixVersion(
                  a['key'] as String,
                  a['fixVersion'] as String,
                ),
            'jira_set_priority': (a) => _client.setPriority(
                  a['key'] as String,
                  a['priority'] as String,
                ),
            'jira_get_subtasks': (a) => _client.getSubtasks(a['key'] as String),
            'jira_update_description': (a) => _client.updateDescription(
                  a['key'] as String,
                  a['description'] as String,
                ),
            'jira_create_ticket_with_parent': (a) =>
                _client.createTicketWithParent(
                  a['project'] as String,
                  a['issueType'] as String,
                  a['summary'] as String,
                  a['parentKey'] as String,
                ),
          };

  /// Dispatch entries for the comment-if-not-exists tool.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _commentIfExistsHandlers() => {
            'jira_post_comment_if_not_exists': (a) =>
                _client.postCommentIfNotExists(
                  a['key'] as String,
                  a['comment'] as String,
                ),
          };

  /// Dispatch entries for the ADF field-update tool.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _adfFieldHandlers() => {
            'jira_update_field_as_adf': (a) => _client.updateFieldAsAdf(
                  a['key'] as String,
                  a['field'] as String,
                  a['value'] as Map<String, dynamic>,
                ),
          };

  /// Dispatch entries for the field-by-name tools.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _fieldsByNameHandlers() => {
            'jira_get_all_fields_with_name': (a) =>
                _client.getAllFieldsWithName(
                  a['project'] as String,
                  a['fieldName'] as String,
                ),
            'jira_update_all_fields_with_name': (a) =>
                _client.updateAllFieldsWithName(
                  a['key'] as String,
                  a['fieldName'] as String,
                  a['value'],
                ),
          };

  /// Dispatch entries for the raw-update tool.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _rawUpdateHandlers() => {
            'jira_update_ticket': (a) => _client.updateTicket(
                  a['key'] as String,
                  a['jsonParams'] as Map<String, dynamic>,
                ),
          };

  /// Dispatch entries for the issue-link tools.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)> _linkHandlers() =>
      {
        'jira_link_issues': (a) => _client.linkIssues(
              a['linkType'] as String,
              a['inwardKey'] as String,
              a['outwardKey'] as String,
            ),
        'jira_get_issue_link_types': (_) => _client.getIssueLinkTypes(),
      };

  /// Dispatch entries for the generic request tool.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _genericRequestHandlers() => {
            'jira_execute_request': (a) =>
                _client.executeRequest(a['url'] as String),
          };
}
