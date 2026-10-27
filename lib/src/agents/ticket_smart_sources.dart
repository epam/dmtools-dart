/// Smart source downloader for `TicketInputContextBuilder`.
///
/// Discovers and downloads external references (Confluence pages, Figma
/// designs, and linked/referenced Jira, GitHub, and Azure DevOps tickets)
/// into `input/<contextId>/` when the corresponding integration is both
/// enabled in [InputContextConfig] and configured via secrets in
/// [SourceCapabilities].
library;

import 'dart:convert';
import 'dart:io';

import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';
import '../integrations/figma/figma_url.dart';
import '../js/sync_http_client.dart';
import '../js/sync_tools/confluence_sync_tools.dart';
import '../js/sync_tools/figma_sync_tools.dart';
import '../js/sync_tools/jira_sync_tools.dart';
import 'input_context_config.dart';
import 'ticket_input_context_builder.dart';
import 'ticket_reference_extractor.dart';

/// Resolves and writes smart context sources (`confluence/`, `figma/`, and
/// sibling `input/<linkedKey>/` folders) for a ticket.
class TicketSmartSources {
  /// Creates a smart-source resolver backed by [reader].
  TicketSmartSources(
    this.reader, {
    ConfluenceSyncTools? confluenceTools,
    FigmaSyncTools? figmaTools,
    JiraSyncTools? jiraTools,
  })  : capabilities = SourceCapabilities(reader),
        _confluenceTools = confluenceTools ?? ConfluenceSyncTools(reader),
        _figmaTools = figmaTools ?? FigmaSyncTools(reader),
        _jiraTools = jiraTools ?? const JiraSyncTools();

  /// The property reader providing credentials and base URLs.
  final PropertyReader reader;

  /// Capability discovery over [reader].
  final SourceCapabilities capabilities;

  final ConfluenceSyncTools _confluenceTools;
  final FigmaSyncTools _figmaTools;
  final JiraSyncTools _jiraTools;

  /// Set of normalized ticket keys already visited in the current recursive
  /// smart-source resolution pass.
  final Set<String> _visited = <String>{};

  /// Resolves smart sources for [ticketData] into [contextPath] (`input/<id>`)
  /// and sibling `input/<linkedId>/` directories.
  void resolveAll({
    required String workingDirectory,
    required String contextId,
    required String contextPath,
    required Map<String, dynamic> ticketData,
    required InputContextConfig config,
    required TicketInputContextBuilder builder,
  }) {
    if (!config.smart) return;
    _visited.add(_normalizeKey(contextId));
    final ticketKey = _ticketKey(ticketData);
    if (ticketKey != null) _visited.add(_normalizeKey(ticketKey));
    final combinedText = _collectTicketText(ticketData, config);
    _resolveConfluence(contextPath, combinedText, config);
    _resolveFigma(contextPath, combinedText, config);
    if (config.includeLinkedTickets) {
      for (final ignored in _extractIgnoredLinkedKeys(ticketData, config)) {
        _visited.add(_normalizeKey(ignored));
      }
      _resolveLinkedTickets(
        workingDirectory: workingDirectory,
        ticketData: ticketData,
        combinedText: combinedText,
        config: config,
        builder: builder,
        visited: _visited,
      );
    }
  }

  /// Collects text from the ticket (and optionally its parent ticket) for URL
  /// and reference extraction.
  String _collectTicketText(
    Map<String, dynamic> ticketData,
    InputContextConfig config,
  ) {
    final buf = StringBuffer(jsonEncode(ticketData));
    if (config.includeParentConfluence) {
      final parentKey = _extractParentKey(ticketData);
      if (parentKey != null) {
        final parentTicket = fetchTicketByKey(parentKey);
        if (parentTicket != null) {
          buf.write('\n');
          buf.write(jsonEncode(parentTicket));
        }
      }
    }
    return buf.toString();
  }

  String? _extractParentKey(Map<String, dynamic> ticket) {
    final fields = ticket['fields'];
    if (fields is Map) {
      final parent = fields['parent'];
      if (parent is Map && parent['key'] != null) {
        final k = parent['key'].toString().trim();
        if (k.isNotEmpty) return k;
      }
      final adoParent = fields['System.Parent'];
      if (adoParent != null && adoParent.toString().trim().isNotEmpty) {
        return adoParent.toString().trim();
      }
    }
    return _extractAdoParentFromRelations(ticket['relations']);
  }

  String? _extractAdoParentFromRelations(dynamic relations) {
    if (relations is! List) return null;
    for (final item in relations) {
      if (item is! Map) continue;
      if (item['rel'] == 'System.LinkTypes.Hierarchy-Reverse') {
        final url = item['url']?.toString() ?? '';
        final id = url.split('/').last.split('?').first.trim();
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  // -- Confluence -------------------------------------------------------

  void _resolveConfluence(
    String contextPath,
    String text,
    InputContextConfig config,
  ) {
    if (!config.isSourceEnabled('confluence') ||
        !capabilities.isConfluenceConfigured) {
      return;
    }
    final urls = TicketReferenceExtractor.extractConfluenceUrls(
      reader.getConfluenceBasePath(),
      text,
    );
    if (urls.isEmpty) return;
    final outDir = '$contextPath/confluence';
    try {
      _confluenceTools.dispatch('confluence_download_pages', {
        'urlStrings': urls,
        'outputPath': outDir,
        'depth': config.confluenceDepth,
        'downloadAttachments':
            config.confluenceAttachments && !config.skipAllAttachments,
        'includeComments': config.includeConfluenceComments,
      });
    } catch (e) {
      stderr.writeln('Failed to download Confluence pages: $e');
    }
  }

  // -- Figma ------------------------------------------------------------

  void _resolveFigma(
    String contextPath,
    String text,
    InputContextConfig config,
  ) {
    if (!config.isSourceEnabled('figma') || !capabilities.isFigmaConfigured) {
      return;
    }
    final urls = TicketReferenceExtractor.extractFigmaUrls(text);
    if (urls.isEmpty) return;
    final figmaDir = Directory('$contextPath/figma')
      ..createSync(recursive: true);
    var index = 1;
    for (final url in urls) {
      _downloadSingleFigmaRef(figmaDir, url, index++, config);
    }
  }

  void _downloadSingleFigmaRef(
    Directory figmaDir,
    String url,
    int index,
    InputContextConfig config,
  ) {
    final prefix = _figmaSafePrefix(url, index);
    _writeFigmaMetadataJson(figmaDir, prefix, 'structure.json',
        _figmaTools.dispatch('figma_get_file_structure', {'href': url}));
    final nodeId = _tryExtractFigmaNodeId(url);
    if (nodeId != null && nodeId.isNotEmpty) {
      _writeFigmaMetadataJson(figmaDir, prefix, 'layers.json',
          _figmaTools.dispatch('figma_get_layers', {'href': url}));
      _writeFigmaMetadataJson(figmaDir, prefix, 'text.json',
          _figmaTools.dispatch('figma_get_text_content', {'href': url}));
    }
    if (config.includeComments) {
      _writeFigmaMetadataJson(figmaDir, prefix, 'comments.json',
          _figmaTools.dispatch('figma_get_file_comments', {'href': url}));
    }
    if (config.includeAttachments && !config.skipAllAttachments) {
      _downloadFigmaPreviewImage(figmaDir, prefix, url);
    }
  }

  void _writeFigmaMetadataJson(
    Directory figmaDir,
    String prefix,
    String suffix,
    String rawJson,
  ) {
    if (rawJson.isEmpty || rawJson == 'null') return;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded == null) return;
      if (decoded is Map && decoded.length == 1 && decoded['error'] != null) {
        return;
      }
      if (decoded is List && decoded.isEmpty) return;
      File('${figmaDir.path}/${prefix}_$suffix').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(decoded),
      );
    } catch (_) {
      // Ignore malformed responses.
    }
  }

  void _downloadFigmaPreviewImage(
    Directory figmaDir,
    String prefix,
    String url,
  ) {
    try {
      final rawPath =
          _figmaTools.dispatch('figma_download_image_of_file', {'url': url});
      final decoded = jsonDecode(rawPath);
      if (decoded is String && decoded.isNotEmpty) {
        final srcFile = File(decoded);
        if (srcFile.existsSync()) {
          srcFile.copySync('${figmaDir.path}/$prefix.png');
        }
      }
    } catch (_) {
      // Non-fatal: preview image is best-effort.
    }
  }

  String _figmaSafePrefix(String url, int index) {
    try {
      final fileId = figmaParseFileId(figmaCleanHref(url));
      final nodeId = _tryExtractFigmaNodeId(url);
      final suffix = nodeId != null && nodeId.isNotEmpty
          ? '_${nodeId.replaceAll(RegExp(r'[^\w\-]'), '_')}'
          : '';
      return 'design_${fileId}$suffix';
    } catch (_) {
      return 'design_$index';
    }
  }

  String? _tryExtractFigmaNodeId(String url) {
    try {
      return figmaExtractQueryParam(figmaCleanHref(url), 'node-id');
    } catch (_) {
      return null;
    }
  }

  // -- Linked & Referenced Tickets --------------------------------------

  void _resolveLinkedTickets({
    required String workingDirectory,
    required Map<String, dynamic> ticketData,
    required String combinedText,
    required InputContextConfig config,
    required TicketInputContextBuilder builder,
    required Set<String> visited,
  }) {
    final keys =
        _collectLinkedAndReferencedKeys(ticketData, combinedText, config);
    final nextConfig = InputContextConfig(
      smart: config.smart,
      sources: config.sources,
      depth: config.depth - 1,
      includeComments: config.includeComments,
      includeAttachments: config.includeAttachments,
      skipVideoAttachments: config.skipVideoAttachments,
      skipAllAttachments: config.skipAllAttachments,
      ignoreClonedByRelationship: config.ignoreClonedByRelationship,
      confluenceDepth: config.confluenceDepth,
      confluenceAttachments: config.confluenceAttachments,
      includeConfluenceComments: config.includeConfluenceComments,
      includeParentConfluence: false,
    );
    for (final key in keys) {
      if (!visited.add(_normalizeKey(key))) continue;
      final linkedData = fetchTicketByKey(key);
      if (linkedData == null) continue;
      builder.build(
        key,
        ticketData: linkedData,
        config: nextConfig,
      );
    }
  }

  List<String> _collectLinkedAndReferencedKeys(
    Map<String, dynamic> ticketData,
    String text,
    InputContextConfig config,
  ) {
    final keys = <String>{};
    keys.addAll(_extractStructuredIssueLinks(ticketData, config));
    if (capabilities.isJiraConfigured) {
      keys.addAll(_extractJiraKeysFromText(text));
    }
    if (capabilities.isGithubConfigured) {
      keys.addAll(TicketReferenceExtractor.extractGithubIssueKeys(
        text,
        defaultRepo: _defaultGithubRepo(),
      ));
    }
    if (capabilities.isAdoConfigured) {
      keys.addAll(TicketReferenceExtractor.extractAdoWorkItemIds(text));
    }
    return keys.toList(growable: false);
  }

  List<String> _extractIgnoredLinkedKeys(
    Map<String, dynamic> ticket,
    InputContextConfig config,
  ) {
    if (!config.ignoreClonedByRelationship) return const [];
    final results = <String>[];
    final fields = ticket['fields'];
    if (fields is Map && fields['issuelinks'] is List) {
      for (final item in fields['issuelinks'] as List) {
        if (item is! Map || !_isClonedByLink(item)) continue;
        final inward = item['inwardIssue'];
        final outward = item['outwardIssue'];
        final linked =
            inward is Map ? inward : (outward is Map ? outward : null);
        final key = linked?['key']?.toString().trim();
        if (key != null && key.isNotEmpty) results.add(key);
      }
    }
    return results;
  }

  List<String> _extractStructuredIssueLinks(
    Map<String, dynamic> ticket,
    InputContextConfig config,
  ) {
    final results = <String>[];
    final fields = ticket['fields'];
    if (fields is Map && fields['issuelinks'] is List) {
      for (final item in fields['issuelinks'] as List) {
        if (item is! Map) continue;
        if (config.ignoreClonedByRelationship && _isClonedByLink(item)) {
          continue;
        }
        final inward = item['inwardIssue'];
        final outward = item['outwardIssue'];
        final linked =
            inward is Map ? inward : (outward is Map ? outward : null);
        final key = linked?['key']?.toString().trim();
        if (key != null && key.isNotEmpty) results.add(key);
      }
    }
    if (ticket['relations'] is List) {
      for (final rel in ticket['relations'] as List) {
        if (rel is! Map || rel['rel'] == 'AttachedFile') continue;
        final url = rel['url']?.toString() ?? '';
        final m =
            RegExp(r'/workItems/(\d+)', caseSensitive: false).firstMatch(url);
        if (m != null) results.add(m.group(1)!);
      }
    }
    return results;
  }

  bool _isClonedByLink(Map<dynamic, dynamic> link) {
    final type = link['type'];
    if (type is! Map) return false;
    final inward = type['inward']?.toString().toLowerCase() ?? '';
    final outward = type['outward']?.toString().toLowerCase() ?? '';
    final name = type['name']?.toString().toLowerCase() ?? '';
    return inward.contains('cloned by') ||
        outward.contains('cloned by') ||
        name == 'cloners';
  }

  List<String> _extractJiraKeysFromText(String text) {
    final ignoreRaw = reader.getValue('JIRA_IGNORE_TICKET_PREFIXES') ?? '';
    final allowRaw = reader.getValue('JIRA_ALLOWED_TICKET_PREFIXES') ?? '';
    final ignore = ignoreRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final allow = allowRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return TicketReferenceExtractor.extractJiraKeys(
      text,
      ignorePrefixes: ignore,
      allowedPrefixes: allow,
    );
  }

  /// Fetches a ticket by key (`PROJ-123`, `owner/repo#42`, `gh-42`, `#42`, or
  /// ADO numeric ID) when the corresponding integration is configured.
  Map<String, dynamic>? fetchTicketByKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    if (_looksLikeGithubKey(trimmed)) {
      return capabilities.isGithubConfigured
          ? _fetchGithubTicket(trimmed)
          : null;
    }
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return capabilities.isAdoConfigured ? _fetchAdoTicket(trimmed) : null;
    }
    if (RegExp(r'^[A-Z][A-Z0-9]+-\d+$').hasMatch(trimmed)) {
      return capabilities.isJiraConfigured ? _fetchJiraTicket(trimmed) : null;
    }
    return null;
  }

  bool _looksLikeGithubKey(String key) =>
      RegExp(r'^(?:[\w.-]+/[\w.-]+#\d+|#\d+|gh-\d+)$', caseSensitive: false)
          .hasMatch(key);

  Map<String, dynamic>? _fetchJiraTicket(String key) {
    try {
      final raw = _jiraTools.dispatch('jira_get_ticket', {'key': key});
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['error'] == null) {
        return {'key': key, ...decoded};
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _fetchAdoTicket(String id) {
    try {
      final org = reader.getAdoOrganization();
      final project = reader.getAdoProject();
      final pat = reader.getAdoPatToken();
      if (org == null || project == null || pat == null) return null;
      final base = reader.getAdoBasePath();
      final basic = base64Encode(utf8.encode(':$pat'));
      final url =
          '$base/$org/$project/_apis/wit/workitems/$id?\$expand=relations&api-version=7.0';
      final resp = SyncHttpClient.get(
        url,
        headers: {'Authorization': 'Basic $basic'},
      );
      if (!resp.isOk) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;
      _attachAdoComments(decoded, '$base/$org/$project/_apis', id, basic);
      return decoded;
    } catch (_) {
      return null;
    }
  }

  void _attachAdoComments(
    Map<String, dynamic> item,
    String baseUrl,
    String id,
    String basicAuth,
  ) {
    try {
      final resp = SyncHttpClient.get(
        '$baseUrl/wit/workItems/$id/comments?api-version=7.0-preview',
        headers: {'Authorization': 'Basic $basicAuth'},
      );
      if (!resp.isOk) return;
      final decoded = jsonDecode(resp.body);
      final rawList = decoded is Map ? decoded['comments'] : null;
      if (rawList is! List || rawList.isEmpty) return;
      final fields = (item['fields'] is Map)
          ? Map<String, dynamic>.from(item['fields'] as Map)
          : <String, dynamic>{};
      fields['comments'] = [
        for (final c in rawList.whereType<Map>())
          {
            'author': {
              'name': (c['createdBy'] is Map)
                  ? (c['createdBy'] as Map)['displayName']
                  : null,
            },
            'created': c['createdDate'],
            'body': c['text'] ?? '',
          },
      ];
      item['fields'] = fields;
    } catch (_) {}
  }

  Map<String, dynamic>? _fetchGithubTicket(String rawKey) {
    final token = SourceCapabilities.resolveGithubToken(reader);
    if (token == null) return null;
    final parsed = _parseGithubCoords(rawKey);
    if (parsed == null) return null;
    final (repo, number) = parsed;
    final base = reader.getGithubBasePath();
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
    };
    final issueResp = SyncHttpClient.get('$base/repos/$repo/issues/$number',
        headers: headers);
    if (!issueResp.isOk) return null;
    final issue = jsonDecode(issueResp.body);
    if (issue is! Map<String, dynamic>) return null;
    final commentsResp = SyncHttpClient.get(
      '$base/repos/$repo/issues/$number/comments',
      headers: headers,
    );
    final rawComments =
        commentsResp.isOk ? jsonDecode(commentsResp.body) : const [];
    final commentList = rawComments is List ? rawComments : const [];
    return _hydrateGithubIssue(issue, commentList, number);
  }

  Map<String, dynamic> _hydrateGithubIssue(
    Map<String, dynamic> issue,
    List<dynamic> comments,
    String number,
  ) =>
      {
        'key': 'GH-$number',
        'fields': {
          'summary': issue['title'],
          'description': issue['body'] ?? '',
          'status': {'name': issue['state']},
          'comment': {
            'comments': [
              for (final c in comments.whereType<Map>())
                {
                  'author': {
                    'name':
                        (c['user'] is Map) ? (c['user'] as Map)['login'] : null,
                  },
                  'created': c['created_at'],
                  'body': c['body'] ?? '',
                },
            ],
          },
        },
      };

  (String, String)? _parseGithubCoords(String rawKey) {
    final comp = RegExp(r'^([\w.-]+/[\w.-]+)#(\d+)$').firstMatch(rawKey);
    if (comp != null) return (comp.group(1)!, comp.group(2)!);
    final bare =
        RegExp(r'^(?:#|gh-)(\d+)$', caseSensitive: false).firstMatch(rawKey);
    if (bare != null) {
      final repo = _defaultGithubRepo();
      if (repo != null) return (repo, bare.group(1)!);
    }
    return null;
  }

  String? _defaultGithubRepo() {
    final repo = reader.getValue('DMTOOLS_TRACKER_REPO') ??
        reader.getValue('GITHUB_REPOSITORY') ??
        reader.getGithubRepository();
    if (repo != null && repo.contains('/')) return repo.trim();
    return null;
  }

  String? _ticketKey(Map<String, dynamic> ticket) {
    final k = ticket['key'] ?? ticket['id'];
    return k?.toString().trim();
  }

  String _normalizeKey(String key) {
    final folder = TicketInputContextBuilder.toInputFolderName(key.trim());
    return folder.toUpperCase();
  }
}
