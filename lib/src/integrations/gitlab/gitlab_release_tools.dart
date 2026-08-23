/// Release and release-asset tools — part of the GitLab MCP tool
/// catalog.
///
/// Ports the release and Generic Package Registry asset `@MCPTool`
/// definitions. Parameter names mirror the Java `GitLab.java`
/// `@MCPParam` annotations.
part of 'gitlab_tools.dart';

/// Release tools ported from the Java `GitLab` client (category `releases`)
/// and used by the release artefacts agent scripts:
/// `gitlab_get_or_create_release`.
List<ToolDefinition> _releaseTools() => [
      ToolDefinition(
        name: 'gitlab_get_or_create_release',
        description: 'Find an existing GitLab release by tag, or create one '
            'if it does not exist; useful as a stable artefact storage '
            'release',
        integration: 'gitlab',
        category: 'releases',
        params: [
          _workspaceParam,
          _repositoryParam,
          ToolParam(
              name: 'tagName',
              description: 'The Git tag name for the '
                  'release; reused to find an existing release'),
          ToolParam(
            name: 'releaseName',
            description: 'The human-readable release name; tagName is used '
                'when empty',
            required: false,
          ),
          ToolParam(
            name: 'targetCommitish',
            description: "Optional branch or commit SHA the release's tag "
                'should point to when created; required if the tag does not '
                'already exist',
            required: false,
          ),
          ToolParam(
            name: 'body',
            description: 'Optional Markdown release notes/description',
            required: false,
          ),
        ],
      ),
    ];

/// Release asset tools (continuation of [_releaseTools]; split for the
/// method-size gate): `gitlab_upload_release_asset`,
/// `gitlab_download_release_asset`.
List<ToolDefinition> _releaseAssetTools() => [
      _uploadReleaseAssetTool(),
      _downloadReleaseAssetTool(),
    ];

/// Upload-release-asset tool: `gitlab_upload_release_asset` (Java
/// `uploadReleaseAsset`).
ToolDefinition _uploadReleaseAssetTool() => ToolDefinition(
      name: 'gitlab_upload_release_asset',
      description: 'Upload a local file as a GitLab release asset by '
          'publishing it to the project Generic Package Registry and '
          'attaching it to the release as an asset link; set overwrite to '
          'true to replace an existing asset with the same name',
      integration: 'gitlab',
      category: 'releases',
      params: [
        _workspaceParam,
        _repositoryParam,
        ToolParam(
          name: 'tagName',
          description: 'The tag name of the release returned by '
              'gitlab_get_or_create_release',
        ),
        ToolParam(
          name: 'filePath',
          description: 'Absolute or relative path to the local file to '
              'upload',
        ),
        ToolParam(
          name: 'assetName',
          description: 'Optional asset filename shown in GitLab; defaults '
              'to the local filename',
          required: false,
        ),
        ToolParam(
          name: 'contentType',
          description: 'Optional MIME type; defaults to the detected type '
              'or application/octet-stream',
          required: false,
        ),
        ToolParam(
          name: 'packageName',
          description: "Optional Generic Package Registry package name; "
              "defaults to 'release-assets'",
          required: false,
        ),
        ToolParam(
          name: 'overwrite',
          description: 'If true, delete any existing asset with the same '
              'name before uploading; defaults to false',
          type: 'boolean',
          required: false,
        ),
      ],
    );

/// Download-release-asset tool: `gitlab_download_release_asset` (Java
/// `downloadReleaseAsset`).
ToolDefinition _downloadReleaseAssetTool() => ToolDefinition(
      name: 'gitlab_download_release_asset',
      description: 'Download a GitLab release asset (a file published to '
          'the Generic Package Registry and attached to a release) to a '
          'local file path',
      integration: 'gitlab',
      category: 'releases',
      params: [
        _workspaceParam,
        _repositoryParam,
        ToolParam(
            name: 'tagName',
            description: 'The tag name of the '
                'release'),
        ToolParam(
          name: 'assetName',
          description: 'The name of the asset to download',
        ),
        ToolParam(
          name: 'targetFilePath',
          description: 'Local file path where the downloaded asset should '
              'be saved',
        ),
        ToolParam(
          name: 'packageName',
          description: "Optional Generic Package Registry package name; "
              "defaults to 'release-assets'",
          required: false,
        ),
      ],
    );

/// Parses a JSON `iid` argument into an int (accepts int or numeric string).
int _toInt(Object? value) {
  if (value is int) return value;
  return int.parse(value.toString());
}

/// Parses a JSON `resolved` argument into a bool (accepts bool, int, or string).
bool _toBool(Object? value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return value.toString().toLowerCase() == 'true';
}
