/// Data-export tool definitions and dispatch — one domain per file.
part of 'jira_tools.dart';

/// Generic data-export tool: `jira_export_data`.
List<ToolDefinition> _exportTools() => [
      _jiraTool(
        name: 'jira_export_data',
        description: 'Export all Jira issue data matching a JQL query',
        category: 'search',
        params: _jqlSearchParams,
      ),
    ];

/// Export dispatch entries, provided via a library-private extension so the
/// main [JiraToolExecutor] file stays within the line-count gate.
extension _JiraExportToolExecutor on JiraToolExecutor {
  /// Routes the export tool names to their [JiraClient] calls.
  Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _exportHandlers() => {
            'jira_export_data': (a) => _client.exportData(
                  a['jql'] as String,
                  _optionalStringList(a, 'fields'),
                ),
          };
}
