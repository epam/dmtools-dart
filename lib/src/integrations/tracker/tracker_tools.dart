/// Tracker-generic tool catalog — the Dart-side `tracker_*` family.
///
/// One common surface over every `TrackerClient`-style backend (Jira, GitHub
/// issues, ADO work items), mirroring the Java `TrackerClient` interface
/// (`common/tracker/TrackerClient.java`): agents call the same tool names
/// regardless of which tracker the deployment is configured with
/// (`TRACKER_TYPE`). Routing happens at dispatch time (`TrackerSyncTools`);
/// each backend maps the generic arguments onto its native API (e.g. `key` →
/// Jira `PROJ-123`, ADO work-item id, or GitHub `owner/repo#123`).
///
/// Dart-side extension: Java has no `tracker_*` `@MCPTool`s (only the
/// per-integration `jira_*`/`ado_*` surfaces), so this family is additive —
/// it never replaces or renames a canonical Java tool.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';

/// The nine tracker-generic tool definitions, split into per-group helpers
/// to keep every function under the project's size gate.
List<ToolDefinition> trackerTools() => [
      ..._ticketTools(),
      ..._commentTools(),
      ..._labelTools(),
      ..._statusTool(),
      ..._createTool(),
    ];

/// Ticket read/search/assign tools.
List<ToolDefinition> _ticketTools() => [
      const ToolDefinition(
        name: 'tracker_get_ticket',
        description: 'Get a ticket from the configured tracker (Jira issue, '
            'ADO work item, or GitHub issue) by its key.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(
            name: 'key',
            description: 'Ticket key: Jira "PROJ-123", ADO work-item id, or '
                'GitHub "owner/repo#123".',
          ),
        ],
      ),
      const ToolDefinition(
        name: 'tracker_search',
        description: 'Search tickets in the configured tracker. Jira expects '
            'JQL, ADO WIQL, GitHub an issue-search query.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(name: 'query', description: 'Native tracker search query.'),
        ],
      ),
      const ToolDefinition(
        name: 'tracker_assign_to',
        description: 'Assign a ticket to a user in the configured tracker.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(name: 'key', description: 'Ticket key.'),
          ToolParam(
            name: 'user',
            description: 'Assignee: Jira accountId, ADO user, GitHub login.',
          ),
        ],
      ),
    ];

/// Comment tools.
List<ToolDefinition> _commentTools() => [
      const ToolDefinition(
        name: 'tracker_post_comment',
        description: 'Post a comment on a ticket in the configured tracker.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(name: 'key', description: 'Ticket key.'),
          ToolParam(name: 'comment', description: 'Comment body (markdown).'),
        ],
      ),
      const ToolDefinition(
        name: 'tracker_get_comments',
        description: 'List comments on a ticket in the configured tracker.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(name: 'key', description: 'Ticket key.'),
        ],
      ),
    ];

/// Label tools.
List<ToolDefinition> _labelTools() => [
      const ToolDefinition(
        name: 'tracker_add_label',
        description: 'Add a label to a ticket in the configured tracker.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(name: 'key', description: 'Ticket key.'),
          ToolParam(name: 'label', description: 'Label to add.'),
        ],
      ),
      const ToolDefinition(
        name: 'tracker_remove_label',
        description: 'Remove a label from a ticket in the configured tracker.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(name: 'key', description: 'Ticket key.'),
          ToolParam(name: 'label', description: 'Label to remove.'),
        ],
      ),
    ];

/// Status transition tool.
List<ToolDefinition> _statusTool() => [
      const ToolDefinition(
        name: 'tracker_move_to_status',
        description: 'Move a ticket to a status in the configured tracker. '
            'GitHub maps Done/Closed → closed, Open/Reopened → open.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(name: 'key', description: 'Ticket key.'),
          ToolParam(name: 'status', description: 'Target status name.'),
        ],
      ),
    ];

/// Ticket creation tool.
List<ToolDefinition> _createTool() => [
      const ToolDefinition(
        name: 'tracker_create_ticket',
        description: 'Create a ticket in the configured tracker.',
        integration: 'tracker',
        category: 'tracker',
        params: [
          ToolParam(
            name: 'project',
            description: 'Jira project key, ADO project, or GitHub owner/repo.',
          ),
          ToolParam(
            name: 'type',
            description: 'Issue type (Jira) — ignored where not applicable.',
            required: false,
          ),
          ToolParam(name: 'title', description: 'Ticket title.'),
          ToolParam(
            name: 'description',
            description: 'Ticket body.',
            required: false,
          ),
        ],
      ),
    ];
