/// MCP tool definitions and dispatcher for the SharePoint integration.
///
/// The tool list ports the SharePoint subset of the Java `@MCPTool` catalog;
/// the executor routes a tool name + arguments to the matching
/// [SharepointClient] call.
library;

import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'sharepoint_client.dart';

/// Returns all SharePoint MCP tool definitions.
///
/// Tool names and argument schemas mirror the Java `@MCPTool` annotations.
List<ToolDefinition> sharepointTools() => [
      _testTool(),
      _getDriveTool(),
      _listFilesTool(),
      _getFileTool(),
      _uploadFileTool(),
      _createFolderTool(),
      _getDriveItemsTool(),
      _searchDriveTool(),
      _deleteDriveItemTool(),
    ];

/// Connectivity-check tool: `sharepoint_test`.
ToolDefinition _testTool() => ToolDefinition(
      name: 'sharepoint_test',
      description: 'Test SharePoint connectivity by fetching the default drive',
      integration: 'sharepoint',
      category: 'system',
      params: [],
    );

/// Get-drive tool: `sharepoint_get_drive`.
ToolDefinition _getDriveTool() => ToolDefinition(
      name: 'sharepoint_get_drive',
      description: 'Get the current user default SharePoint drive',
      integration: 'sharepoint',
      category: 'files',
      params: [],
    );

/// List-files tool: `sharepoint_list_files`.
ToolDefinition _listFilesTool() => ToolDefinition(
      name: 'sharepoint_list_files',
      description: 'List files in the root of a SharePoint drive by drive id',
      integration: 'sharepoint',
      category: 'files',
      params: [
        ToolParam(
          name: 'drive_id',
          description: 'The SharePoint drive id',
          required: true,
        ),
      ],
    );

/// Get-file tool: `sharepoint_get_file`.
ToolDefinition _getFileTool() => ToolDefinition(
      name: 'sharepoint_get_file',
      description: 'Download the content of a SharePoint file by drive and '
          'item id',
      integration: 'sharepoint',
      category: 'files',
      params: [
        ToolParam(
          name: 'drive_id',
          description: 'The SharePoint drive id',
          required: true,
        ),
        ToolParam(
          name: 'item_id',
          description: 'The SharePoint item id',
          required: true,
        ),
      ],
    );

/// Upload-file tool: `sharepoint_upload_file`.
ToolDefinition _uploadFileTool() => ToolDefinition(
      name: 'sharepoint_upload_file',
      description: 'Upload a file to a SharePoint drive folder',
      integration: 'sharepoint',
      category: 'files',
      params: [
        ToolParam(
          name: 'drive_id',
          description: 'The SharePoint drive id',
          required: true,
        ),
        ToolParam(
          name: 'folder_id',
          description: 'The SharePoint folder item id',
          required: true,
        ),
        ToolParam(
          name: 'file_name',
          description: 'The name for the uploaded file',
          required: true,
        ),
        ToolParam(
          name: 'content',
          description: 'The file content to upload',
          required: true,
        ),
      ],
    );

/// Create-folder tool: `sharepoint_create_folder`.
ToolDefinition _createFolderTool() => ToolDefinition(
      name: 'sharepoint_create_folder',
      description: 'Create a folder under a parent item in a SharePoint drive',
      integration: 'sharepoint',
      category: 'files',
      params: [
        ToolParam(
          name: 'drive_id',
          description: 'The SharePoint drive id',
          required: true,
        ),
        ToolParam(
          name: 'parent_id',
          description: 'The parent item id',
          required: true,
        ),
        ToolParam(
          name: 'name',
          description: 'The new folder name',
          required: true,
        ),
      ],
    );

/// Get-drive-items tool: `sharepoint_get_drive_items`.
ToolDefinition _getDriveItemsTool() => ToolDefinition(
      name: 'sharepoint_get_drive_items',
      description: 'List items in a SharePoint drive folder by drive and '
          'folder id',
      integration: 'sharepoint',
      category: 'files',
      params: [
        ToolParam(
          name: 'drive_id',
          description: 'The SharePoint drive id',
          required: true,
        ),
        ToolParam(
          name: 'folder_id',
          description: 'The SharePoint folder item id',
          required: true,
        ),
      ],
    );

/// Search-drive tool: `sharepoint_search_drive`.
ToolDefinition _searchDriveTool() => ToolDefinition(
      name: 'sharepoint_search_drive',
      description: 'Search a SharePoint drive for items matching a query',
      integration: 'sharepoint',
      category: 'files',
      params: [
        ToolParam(
          name: 'drive_id',
          description: 'The SharePoint drive id',
          required: true,
        ),
        ToolParam(
          name: 'query',
          description: 'The search text to match item names against',
          required: true,
        ),
      ],
    );

/// Delete-drive-item tool: `sharepoint_delete_drive_item`.
ToolDefinition _deleteDriveItemTool() => ToolDefinition(
      name: 'sharepoint_delete_drive_item',
      description: 'Delete an item from a SharePoint drive by drive and '
          'item id',
      integration: 'sharepoint',
      category: 'files',
      params: [
        ToolParam(
          name: 'drive_id',
          description: 'The SharePoint drive id',
          required: true,
        ),
        ToolParam(
          name: 'item_id',
          description: 'The SharePoint item id',
          required: true,
        ),
      ],
    );

/// Executes SharePoint MCP tools by dispatching to [SharepointClient].
class SharepointToolExecutor {
  final SharepointClient _client;

  /// Creates an executor bound to [_client].
  SharepointToolExecutor(this._client);

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown SharePoint tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown SharePoint tool: $toolName');
    }
    return handler(args);
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'sharepoint_test': (_) => _client.testConnection(),
    'sharepoint_get_drive': (_) => _client.getDrive(),
    'sharepoint_list_files': (a) => _client.listFiles(a['drive_id'] as String),
    'sharepoint_get_file': (a) => _client.getFile(
          a['drive_id'] as String,
          a['item_id'] as String,
        ),
    'sharepoint_upload_file': (a) => _client.uploadFile(
          a['drive_id'] as String,
          a['folder_id'] as String,
          a['file_name'] as String,
          a['content'] as String,
        ),
    'sharepoint_create_folder': (a) => _client.createFolder(
          a['drive_id'] as String,
          a['parent_id'] as String,
          a['name'] as String,
        ),
    'sharepoint_get_drive_items': (a) => _client.getDriveItems(
          a['drive_id'] as String,
          a['folder_id'] as String,
        ),
    'sharepoint_search_drive': (a) => _client.searchDrive(
          a['drive_id'] as String,
          a['query'] as String,
        ),
    'sharepoint_delete_drive_item': (a) => _client.deleteDriveItem(
          a['drive_id'] as String,
          a['item_id'] as String,
        ),
  };
}
