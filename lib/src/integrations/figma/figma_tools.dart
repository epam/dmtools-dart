/// MCP tool definitions and dispatcher for the Figma integration.
///
/// The catalog ports the Java `FigmaClient` `@MCPTool` surface
/// (`figma_oauth2_*`, `figma_test`, `figma_me`, `figma_get_screen_source`,
/// `figma_download_*`, `figma_get_file_structure`, `figma_get_icons`,
/// `figma_get_image_fills`, `figma_render_nodes`, `figma_get_svg_content`,
/// `figma_get_node_details`, `figma_get_text_content`, `figma_get_styles`,
/// `figma_get_layers*`, `figma_get_node_children`, `figma_list_*`,
/// `figma_get_file_comments`) plus the pre-existing Dart REST-shaped tools
/// (`figma_get_file`, `figma_get_file_nodes`, …) that predate the parity
/// port. The executor routes a tool name + arguments to the matching
/// [FigmaClient] call.
library;

import 'dart:convert';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../../mcp/tool_definition.dart';
import '../../mcp/tool_param.dart';
import 'figma_client.dart';
import 'figma_oauth.dart';

/// Returns all Figma MCP tool definitions.
///
/// Java-catalog tools come first (auth → user → content access →
/// structure analysis); the legacy Dart REST-shaped tools follow.
List<ToolDefinition> figmaTools() => [
      ..._authTools(),
      ..._userTools(),
      ..._downloadTools(),
      ..._discoveryTools(),
      ..._exportTools(),
      ..._contentTools(),
      ..._listingTools(),
      ..._structureAnalysisTools(),
      ..._legacyFileTools(),
      ..._legacyImageCommentTools(),
      ..._legacyStyleTools(),
    ];

/// OAuth2 tools: `figma_oauth2_get_auth_url` / `figma_oauth2_exchange_code`.
List<ToolDefinition> _authTools() => [
      ToolDefinition(
        name: 'figma_oauth2_get_auth_url',
        description: 'Generates the Figma OAuth2 authorization URL for the '
            'initial authorization code flow. Open the returned URL in a '
            'browser, authorize the app, and copy the code parameter from '
            'the redirect URL. Then call figma_oauth2_exchange_code to get '
            'access and refresh tokens. Requires FIGMA_CLIENT_ID and '
            'FIGMA_CLIENT_SECRET to be configured.',
        integration: 'figma',
        category: 'auth',
        params: [
          ToolParam(
            name: 'redirectUri',
            description: 'Redirect URI registered in your Figma OAuth app '
                '(e.g. http://localhost:8080/callback). If omitted, uses '
                'FIGMA_REDIRECT_URI env variable.',
            required: false,
          ),
          ToolParam(
            name: 'state',
            description: 'Random state string for CSRF protection',
            required: false,
          ),
          ToolParam(
            name: 'scope',
            description: 'Optional OAuth scope list (space-separated), e.g. '
                'file_content:read file_metadata:read. If omitted, uses '
                'FIGMA_SCOPE (or FIGMA_OAUTH_SCOPES) env or default minimal '
                'read scope.',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_oauth2_exchange_code',
        description: 'Exchanges a Figma OAuth2 authorization code for access '
            'and refresh tokens. Use the code from the redirect URL after '
            'completing the browser authorization flow started by '
            'figma_oauth2_get_auth_url. Store FIGMA_OAUTH_REFRESH_TOKEN '
            'from the response in your dmtools.env to enable automatic '
            'token refresh.',
        integration: 'figma',
        category: 'auth',
        params: [
          ToolParam(
            name: 'code',
            description: 'Authorization code received from Figma OAuth2 '
                'redirect',
            required: true,
          ),
          ToolParam(
            name: 'redirectUri',
            description: 'Same redirect URI used in figma_oauth2_get_auth_'
                'url. If omitted, uses FIGMA_REDIRECT_URI env variable.',
            required: false,
          ),
        ],
      ),
    ];

/// User tools: `figma_test` / `figma_me`.
List<ToolDefinition> _userTools() => [
      ToolDefinition(
        name: 'figma_test',
        description: "Test Figma connectivity by fetching the current user's "
            'profile',
        integration: 'figma',
        category: 'system',
        params: [],
      ),
      ToolDefinition(
        name: 'figma_me',
        description: 'Gets current user information from the Figma API using '
            'the /me endpoint. Returns user details including id, handle, '
            'and email. Can also be used to verify API connectivity.',
        integration: 'figma',
        category: 'user',
        params: [],
      ),
    ];

/// Shared `href` parameter (Figma design URL).
ToolParam _hrefParam() => ToolParam(
      name: 'href',
      description: 'Figma design URL',
      required: true,
    );

/// Download tools (Java `category = "content_access"`).
List<ToolDefinition> _downloadTools() => [
      ToolDefinition(
        name: 'figma_get_screen_source',
        description: 'Get screen source content by URL. Returns the image '
            'URL for the specified Figma design node.',
        integration: 'figma',
        category: 'content_access',
        params: [
          ToolParam(
            name: 'url',
            description: 'Figma design URL with node-id parameter',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_download_node_image',
        description: 'Download image of specific node/component. Useful for '
            'visual preview of design pieces before processing structure.',
        integration: 'figma',
        category: 'content_access',
        params: [
          _hrefParam(),
          ToolParam(
            name: 'nodeId',
            description: 'Node ID to download',
            required: true,
          ),
          ToolParam(
            name: 'format',
            description: 'Image format: png or jpg',
            required: false,
          ),
          ToolParam(
            name: 'scale',
            description: 'Scale factor: 1, 2, or 4',
            type: 'number',
            required: false,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_download_image_of_file',
        description: 'Download image by URL as File type. Converts Figma '
            'design URL to downloadable image file.',
        integration: 'figma',
        category: 'file_management',
        params: [_hrefParam()],
      ),
    ];

/// File discovery tools (Java `category = "content_access"`).
List<ToolDefinition> _discoveryTools() => [
      ToolDefinition(
        name: 'figma_get_file_structure',
        description: 'Get full JSON structure of a Figma design file by URL. '
            'Returns the complete document tree (nodes, frames, components, '
            'text, styles). Response is large by design — intended for '
            'pre-CLI artifact preparation and file output, not inline AI '
            'context. If the URL contains node-id, returns only that '
            'subtree.',
        integration: 'figma',
        category: 'content_access',
        params: [_hrefParam()],
      ),
      ToolDefinition(
        name: 'figma_get_icons',
        description: 'Find and extract all exportable visual elements '
            '(vectors, shapes, graphics, text) from Figma design by URL. '
            'Focuses on actual visual elements to avoid complex component '
            'references.',
        integration: 'figma',
        category: 'content_access',
        params: [_hrefParam()],
      ),
      ToolDefinition(
        name: 'figma_get_image_fills',
        description: 'Get original image fill URLs for all imageRefs in a '
            'Figma file. Resolves imageRef placeholders to actual '
            'downloadable S3 URLs. Use after inspecting file structure to '
            'download original photos/images embedded by the designer.',
        integration: 'figma',
        category: 'content_access',
        params: [_hrefParam()],
      ),
      ToolDefinition(
        name: 'figma_render_nodes',
        description: 'Render multiple Figma nodes as images in a single '
            'batched API call. Automatically batches up to 100 node IDs per '
            'request. Returns map of nodeId to render URL. Use for '
            'exporting many icons or frames efficiently.',
        integration: 'figma',
        category: 'content_access',
        params: [
          _hrefParam(),
          ToolParam(
            name: 'nodeIds',
            description: "Comma-separated node IDs to render (e.g. '1:2,3:4,"
                "5:6')",
            required: true,
          ),
          ToolParam(
            name: 'format',
            description: 'Export format: png, jpg, svg, pdf. Default: png',
            required: false,
          ),
        ],
      ),
    ];

/// Node export tools (Java `category = "content_access"`).
List<ToolDefinition> _exportTools() => [
      ToolDefinition(
        name: 'figma_download_image_as_file',
        description: 'Download image as file by node ID and format. Use this '
            'after figma_get_icons to download actual icon files.',
        integration: 'figma',
        category: 'content_access',
        params: [
          _hrefParam(),
          ToolParam(
            name: 'nodeId',
            description: 'Node ID to export (from figma_get_icons result)',
            required: true,
          ),
          ToolParam(
            name: 'format',
            description: 'Export format',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_get_svg_content',
        description: 'Get SVG content as text by node ID. Use this after '
            'figma_get_icons to get SVG code for vector icons.',
        integration: 'figma',
        category: 'content_access',
        params: [
          _hrefParam(),
          ToolParam(
            name: 'nodeId',
            description: 'Node ID to export as SVG (from figma_get_icons '
                'result)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_get_node_details',
        description: 'Get detailed properties for specific node(s) including '
            'colors, fonts, text, dimensions, and styles. Returns small '
            'focused response.',
        integration: 'figma',
        category: 'content_access',
        params: [
          _hrefParam(),
          ToolParam(
            name: 'nodeIds',
            description: 'Comma-separated node IDs (max 10)',
            required: true,
          ),
        ],
      ),
    ];

/// Text/style/children content tools (Java `category = "content_access"`).
List<ToolDefinition> _contentTools() => [
      ToolDefinition(
        name: 'figma_get_text_content',
        description: 'Extract text content from text nodes. Returns map of '
            'nodeId to text content.',
        integration: 'figma',
        category: 'content_access',
        params: [
          _hrefParam(),
          ToolParam(
            name: 'nodeIds',
            description: 'Comma-separated text node IDs (max 20)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_get_styles',
        description: 'Get design tokens (colors, text styles) defined in '
            'Figma file.',
        integration: 'figma',
        category: 'content_access',
        params: [_hrefParam()],
      ),
      ToolDefinition(
        name: 'figma_get_node_children',
        description: 'Get immediate children IDs and basic info for a node. '
            'Non-recursive, returns only direct children.',
        integration: 'figma',
        category: 'content_access',
        params: [_hrefParam()],
      ),
    ];

/// Team/project listing tools (Java `category = "content_access"`).
List<ToolDefinition> _listingTools() => [
      ToolDefinition(
        name: 'figma_list_team_projects',
        description: 'List all projects within a Figma team, so a team-level '
            'files listing URL (which is not a single design file and cannot '
            'be passed to file-specific tools like figma_get_layers) can be '
            'broken down into browsable projects. Accepts either a raw '
            'numeric team ID or any Figma URL containing a /team/<teamId> '
            'path segment.',
        integration: 'figma',
        category: 'content_access',
        params: [
          ToolParam(
            name: 'teamIdOrUrl',
            description: 'Numeric Figma team ID, or a Figma URL containing '
                "'/team/<teamId>' (e.g. a team files-listing URL)",
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_list_project_files',
        description: 'List all design files within a Figma project, '
            "returning each file's key, name, and thumbnail so a specific "
            'file URL can be built for use with file-specific tools like '
            'figma_get_layers or figma_get_file_structure. Use '
            'figma_list_team_projects first to discover project IDs from a '
            'team. Accepts either a raw numeric project ID or any Figma URL '
            'containing a /project/<projectId> path segment.',
        integration: 'figma',
        category: 'content_access',
        params: [
          ToolParam(
            name: 'projectIdOrUrl',
            description: 'Numeric Figma project ID, or a Figma URL '
                "containing '/project/<projectId>'",
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_get_file_comments',
        description: 'Get all comments left on a Figma design file, '
            'including comment text, author, and creation date. Accepts '
            'either a raw Figma file key or a full Figma design file URL.',
        integration: 'figma',
        category: 'content_access',
        params: [_hrefParam()],
      ),
    ];

/// Structure-analysis tools (Java `category = "structure_analysis"`).
List<ToolDefinition> _structureAnalysisTools() => [
      ToolDefinition(
        name: 'figma_get_layers',
        description: 'Get first-level layers (direct children) to understand '
            'structure. Returns layer names, IDs, types, sizes. Essential '
            'first step before getting details.',
        integration: 'figma',
        category: 'structure_analysis',
        params: [_hrefParam()],
      ),
      ToolDefinition(
        name: 'figma_get_layers_batch',
        description: 'Get layers for multiple nodes at once. More efficient '
            'for analyzing multiple screens/containers. Returns map of '
            'nodeId to layers.',
        integration: 'figma',
        category: 'structure_analysis',
        params: [
          _hrefParam(),
          ToolParam(
            name: 'nodeIds',
            description: 'Comma-separated node IDs (max 10)',
            required: true,
          ),
        ],
      ),
    ];

/// Legacy file/node lookup tools that predate the Java parity port.
List<ToolDefinition> _legacyFileTools() => [
      ToolDefinition(
        name: 'figma_get_file',
        description: 'Get a Figma file by key',
        integration: 'figma',
        category: 'files',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_get_file_nodes',
        description: 'Get specific nodes from a Figma file',
        integration: 'figma',
        category: 'files',
        params: [
          _keyParam(),
          ToolParam(
            name: 'node_ids',
            description: 'Comma-separated node IDs to fetch',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_get_node',
        description: 'Get a single node from a Figma file',
        integration: 'figma',
        category: 'files',
        params: [
          _keyParam(),
          ToolParam(
            name: 'node_id',
            description: 'The node ID to fetch',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_get_image',
        description: 'Export a Figma node as an image',
        integration: 'figma',
        category: 'images',
        params: [
          _keyParam(),
          ToolParam(
            name: 'node_id',
            description: 'The node ID to export as an image',
            required: true,
          ),
        ],
      ),
    ];

/// Legacy image/comment/component tools that predate the Java parity port.
List<ToolDefinition> _legacyImageCommentTools() => [
      ToolDefinition(
        name: 'figma_export_image',
        description: 'Export nodes from a Figma file as images',
        integration: 'figma',
        category: 'images',
        params: [
          _keyParam(),
          ToolParam(
            name: 'format',
            description: 'Image format: jpg, png, or svg (default png)',
            required: false,
          ),
          ToolParam(
            name: 'scale',
            description: 'Zoom factor for rasterized exports (default 1)',
            required: false,
            type: 'number',
          ),
        ],
      ),
      ToolDefinition(
        name: 'figma_get_comments',
        description: 'Get comments on a Figma file',
        integration: 'figma',
        category: 'comments',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_post_comment',
        description: 'Post a comment on a Figma file',
        integration: 'figma',
        category: 'comments',
        params: [_keyParam(), _messageParam()],
      ),
      ToolDefinition(
        name: 'figma_get_components',
        description: 'Get components from a Figma file',
        integration: 'figma',
        category: 'components',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_get_file_components',
        description:
            'Get components from a Figma file (alias of get_components)',
        integration: 'figma',
        category: 'components',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_get_component_sets',
        description: 'Get component sets from a Figma file',
        integration: 'figma',
        category: 'components',
        params: [_keyParam()],
      ),
    ];

/// Legacy style/variable/library tools that predate the Java parity port.
List<ToolDefinition> _legacyStyleTools() => [
      ToolDefinition(
        name: 'figma_get_style',
        description: 'Get a style from a Figma file',
        integration: 'figma',
        category: 'styles',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_get_variable_collections',
        description: 'Get variable collections from a Figma file',
        integration: 'figma',
        category: 'variables',
        params: [_keyParam()],
      ),
      ToolDefinition(
        name: 'figma_get_library_components',
        description: 'Get components from a Figma team library',
        integration: 'figma',
        category: 'library',
        params: [_libraryKeyParam()],
      ),
    ];

/// Shared `key` parameter (Figma file key).
ToolParam _keyParam() => ToolParam(
      name: 'key',
      description: 'The Figma file key',
      required: true,
    );

/// Shared `library_key` parameter (Figma team library key).
ToolParam _libraryKeyParam() => ToolParam(
      name: 'library_key',
      description: 'The Figma team library key',
      required: true,
    );

/// Shared `message` parameter (comment text).
ToolParam _messageParam() => ToolParam(
      name: 'message',
      description: 'The comment message text',
      required: true,
    );

/// Executes Figma MCP tools by dispatching to [FigmaClient].
class FigmaToolExecutor {
  final FigmaClient _client;
  final PropertyReader _reader;
  final FigmaOAuth2Exchange _exchange;

  /// Creates an executor bound to [_client].
  ///
  /// [_reader] resolves the OAuth2 tool configuration (client id/secret,
  /// redirect URI, scopes); [_exchange] performs the token POST (inject a
  /// mock in tests). Both default to production implementations.
  FigmaToolExecutor(
    this._client, [
    PropertyReader? reader,
    FigmaOAuth2Exchange? exchange,
  ])  : _reader = reader ?? PropertyReader(),
        _exchange = exchange ?? FigmaOAuth2Exchange();

  /// Executes [toolName] with [args], returning the tool's result.
  ///
  /// Throws [ArgumentError] for an unknown Figma tool name.
  Future<dynamic> execute(String toolName, Map<String, dynamic> args) {
    final handler = _handlers[toolName];
    if (handler == null) {
      throw ArgumentError('Unknown Figma tool: $toolName');
    }
    return handler(args);
  }

  /// `figma_oauth2_get_auth_url` — Java `oauth2GetAuthUrl`: resolves
  /// config, fills in random state, returns the authorization URL JSON.
  Future<String> _oauth2GetAuthUrl(Map<String, dynamic> args) async {
    final clientId = _reader.getFigmaClientId() ?? '';
    if (clientId.isEmpty) {
      return _oauthError('FIGMA_CLIENT_ID is not configured');
    }
    final clientSecret = _reader.getFigmaClientSecret() ?? '';
    if (clientSecret.isEmpty) {
      return _oauthError('FIGMA_CLIENT_SECRET is not configured');
    }
    final redirectError = _oauthError(
      'redirectUri is required (or set FIGMA_REDIRECT_URI in dmtools.env)',
    );
    var redirectUri = _asOptional(args['redirectUri']);
    if (redirectUri == null) {
      redirectUri = _reader.getFigmaRedirectUri();
    }
    if (redirectUri == null || redirectUri.isEmpty) {
      return redirectError;
    }
    var state = _asOptional(args['state']);
    state ??= _randomState();
    final scope = _asOptional(args['scope']) ?? _reader.getFigmaOAuth2Scopes();
    final authUrl = figmaBuildAuthorizationUrl(
      clientId: clientId,
      redirectUri: redirectUri,
      state: state,
      scope: scope,
    );
    return _oauthResult({
      'authorization_url': authUrl,
      'instructions': 'Open this URL in your browser, authorize the app, '
          "then copy the 'code' query parameter from the redirect URL and "
          'call figma_oauth2_exchange_code.',
      'state': state,
    });
  }

  /// `figma_oauth2_exchange_code` — Java `oauth2ExchangeCode`.
  Future<String> _oauth2ExchangeCode(Map<String, dynamic> args) async {
    final clientId = _reader.getFigmaClientId() ?? '';
    final clientSecret = _reader.getFigmaClientSecret() ?? '';
    if (clientId.isEmpty || clientSecret.isEmpty) {
      return _oauthError(
        'FIGMA_CLIENT_ID and FIGMA_CLIENT_SECRET must be configured',
      );
    }
    var redirectUri = _asOptional(args['redirectUri']);
    if (redirectUri == null) {
      redirectUri = _reader.getFigmaRedirectUri();
    }
    if (redirectUri == null || redirectUri.isEmpty) {
      return _oauthError(
        'redirectUri is required (or set FIGMA_REDIRECT_URI in dmtools.env)',
      );
    }
    try {
      final tokens = await _exchange.exchangeCode(
        code: args['code'] as String,
        redirectUri: redirectUri,
        clientId: clientId,
        clientSecret: clientSecret,
      );
      return _oauthResult({
        'access_token': tokens.accessToken,
        'refresh_token': tokens.refreshToken,
        'expires_in': tokens.expiresIn,
        'instructions': 'Add FIGMA_OAUTH_REFRESH_TOKEN=${tokens.refreshToken}'
            ' to your dmtools.env to enable automatic token refresh. You '
            'can also set FIGMA_OAUTH_ACCESS_TOKEN=${tokens.accessToken} '
            'for immediate use (expires in ${tokens.expiresIn}s).',
      });
    } on Object catch (failure) {
      return _oauthError('Token exchange failed: $failure');
    }
  }

  /// Random hex state for OAuth CSRF protection — Java
  /// `Long.toHexString(doubleToLongBits(random))` parity via
  /// [figmaRandomState].
  String _randomState() => figmaRandomState();

  /// JSON error envelope for the OAuth tools.
  String _oauthError(String message) => jsonEncode({'error': message});

  /// Encodes one OAuth tool result.
  String _oauthResult(Map<String, dynamic> result) => jsonEncode(result);

  /// Optional string argument: `null` or blank → `null`.
  String? _asOptional(dynamic value) {
    final str = value?.toString() ?? '';
    return str.isEmpty ? null : str;
  }

  /// Tool-name → handler dispatch table, mirroring the Java method routing.
  late final Map<String, Future<dynamic> Function(Map<String, dynamic>)>
      _handlers = {
    'figma_oauth2_get_auth_url': _oauth2GetAuthUrl,
    'figma_oauth2_exchange_code': _oauth2ExchangeCode,
    'figma_test': (_) => _client.testConnection(),
    'figma_me': (_) => _client.meJson(),
    'figma_get_screen_source': (a) =>
        _client.getImageOfSource(a['url'] as String),
    'figma_download_node_image': (a) => _client.downloadNodeImage(
          a['href'] as String,
          a['nodeId'] as String,
          format: a['format'] as String?,
          scale: (a['scale'] as num?)?.toInt(),
        ),
    'figma_download_image_of_file': (a) =>
        _client.convertUrlToFile(a['href'] as String),
    'figma_get_file_structure': (a) =>
        _client.getFileStructure(a['href'] as String),
    'figma_get_icons': (a) => _client.getIcons(a['href'] as String),
    'figma_get_image_fills': (a) => _client.getImageFills(a['href'] as String),
    'figma_render_nodes': (a) => _client.renderNodes(
          a['href'] as String,
          a['nodeIds'] as String,
          format: a['format'] as String?,
        ),
    'figma_download_image_as_file': (a) => _client.downloadIconFile(
          a['href'] as String,
          a['nodeId'] as String,
          a['format'] as String,
        ),
    'figma_get_svg_content': (a) =>
        _client.getSvgContent(a['href'] as String, a['nodeId'] as String),
    'figma_get_node_details': (a) =>
        _client.getNodeDetails(a['href'] as String, a['nodeIds'] as String),
    'figma_get_text_content': (a) =>
        _client.getTextContent(a['href'] as String, a['nodeIds'] as String),
    'figma_get_styles': (a) => _client.getDesignStyles(a['href'] as String),
    'figma_get_layers': (a) => _client.getLayers(a['href'] as String),
    'figma_get_layers_batch': (a) =>
        _client.getLayersBatch(a['href'] as String, a['nodeIds'] as String),
    'figma_get_node_children': (a) =>
        _client.getNodeChildren(a['href'] as String),
    'figma_list_team_projects': (a) =>
        _client.listTeamProjects(a['teamIdOrUrl'] as String),
    'figma_list_project_files': (a) =>
        _client.listProjectFiles(a['projectIdOrUrl'] as String),
    'figma_get_file_comments': (a) =>
        _client.getFileComments(a['href'] as String),
    // Legacy Dart REST-shaped tools.
    'figma_get_file': (a) => _client.getFile(a['key'] as String),
    'figma_get_file_nodes': (a) => _client.getFileNodes(
          a['key'] as String,
          a['node_ids'] as String,
        ),
    'figma_get_node': (a) => _client.getNode(
          a['key'] as String,
          a['node_id'] as String,
        ),
    'figma_get_image': (a) => _client.getImage(
          a['key'] as String,
          a['node_id'] as String,
        ),
    'figma_get_comments': (a) => _client.getComments(a['key'] as String),
    'figma_post_comment': (a) => _client.postComment(
          a['key'] as String,
          a['message'] as String,
        ),
    'figma_get_components': (a) => _client.getComponents(a['key'] as String),
    'figma_get_file_components': (a) =>
        _client.getComponents(a['key'] as String),
    'figma_get_component_sets': (a) =>
        _client.getComponentSets(a['key'] as String),
    'figma_get_style': (a) => _client.getStyle(a['key'] as String),
    'figma_get_variable_collections': (a) =>
        _client.getVariableCollections(a['key'] as String),
    'figma_get_library_components': (a) =>
        _client.getLibraryComponents(a['library_key'] as String),
    'figma_export_image': (a) => _client.exportImage(
          a['key'] as String,
          format: a['format'] as String?,
          scale: (a['scale'] as num?)?.toDouble(),
        ),
  };
}
