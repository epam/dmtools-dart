/// Configuration and capability discovery for building a ticket-based input
/// context folder (`input/<contextId>/`).
///
/// Ports Java `InputContextConfig` and `InputParams` while adding dynamic
/// capability discovery (`PropertyReader` secret/credential checks): a
/// referenced source (Confluence, Figma, Jira, GitHub, ADO) is only fetched
/// when it is both enabled in [InputContextConfig] AND configured via secrets
/// in [PropertyReader].
library;

import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';

/// Configuration for `TicketInputContextBuilder`.
class InputContextConfig {
  /// Creates an [InputContextConfig] with defaults.
  const InputContextConfig({
    this.ticket,
    this.jql,
    this.smart = true,
    this.sources = const [],
    this.depth = 0,
    this.includeComments = true,
    this.includeAttachments = true,
    this.skipVideoAttachments = false,
    this.skipAllAttachments = false,
    this.ignoreClonedByRelationship = true,
    this.confluenceDepth = 1,
    this.confluenceAttachments = true,
    this.includeConfluenceComments = true,
    this.includeParentConfluence = true,
  });

  /// Explicit ticket key (from `input: "PROJ-123"` or `input.ticket`).
  final String? ticket;

  /// Explicit JQL / WIQL / GitHub search query (from `input.jql`).
  final String? jql;

  /// Whether to automatically resolve URLs and references in ticket text.
  final bool smart;

  /// Whitelist of smart sources (`confluence`, `figma`, etc.). Empty = all.
  final List<String> sources;

  /// Linked-ticket traversal depth (`> 0` fetches linked/referenced tickets).
  final int depth;

  /// Whether to write `comments.md`.
  final bool includeComments;

  /// Whether to download ticket attachments into the input folder.
  final bool includeAttachments;

  /// Whether to skip video attachments when [includeAttachments] is true.
  final bool skipVideoAttachments;

  /// Whether to skip all ticket attachments.
  final bool skipAllAttachments;

  /// Whether to ignore tickets linked via "is cloned by" / "clones".
  final bool ignoreClonedByRelationship;

  /// How many levels of linked/child Confluence pages to follow.
  final int confluenceDepth;

  /// Whether to download attachments for fetched Confluence pages.
  final bool confluenceAttachments;

  /// Whether to fetch inline comments for fetched Confluence pages.
  final bool includeConfluenceComments;

  /// Whether to also scan the parent ticket for smart source URLs.
  final bool includeParentConfluence;

  /// Whether linked/referenced tickets should be fetched.
  bool get includeLinkedTickets => depth > 0;

  /// Returns true if [source] (e.g. `confluence`, `figma`) is enabled by the
  /// [sources] whitelist. When [sources] is empty, all sources are enabled.
  bool isSourceEnabled(String source) {
    if (!smart) return false;
    if (sources.isEmpty) return true;
    final lower = source.toLowerCase();
    return sources.any((s) => s.trim().toLowerCase() == lower);
  }

  /// Parses an [InputContextConfig] from a job `params` JSON map (combining
  /// top-level Teammate/CliAgent flags with an optional `input` string or map).
  factory InputContextConfig.fromJson(Map<String, dynamic> json) {
    final rawInput = json['input'];
    final inputMap = rawInput is Map
        ? rawInput.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final ticketFromString = rawInput is String && rawInput.trim().isNotEmpty
        ? rawInput.trim()
        : null;
    final defaultDepth = rawInput is Map || ticketFromString != null ? 1 : 0;
    return InputContextConfig(
      ticket: ticketFromString ?? _str(inputMap['ticket']),
      jql: _str(inputMap['jql']),
      smart: _bool(inputMap, json, 'smart', true),
      sources: _strList(inputMap['sources'] ?? json['sources']),
      depth: _int(inputMap, json, 'depth', defaultDepth),
      includeComments: _bool(inputMap, json, 'includeComments', true),
      includeAttachments: _bool(inputMap, json, 'includeAttachments', true),
      skipVideoAttachments:
          _bool(inputMap, json, 'skipVideoAttachments', false),
      skipAllAttachments: _bool(inputMap, json, 'skipAllAttachments', false),
      ignoreClonedByRelationship:
          _bool(inputMap, json, 'ignoreClonedByRelationship', true),
      confluenceDepth: _int(inputMap, json, 'confluenceDepth', 1),
      confluenceAttachments:
          _bool(inputMap, json, 'confluenceAttachments', true),
      includeConfluenceComments:
          _bool(inputMap, json, 'includeConfluenceComments', true),
      includeParentConfluence:
          _bool(inputMap, json, 'includeParentConfluence', true),
    );
  }
}

/// Discovers which external integrations have credentials configured in
/// [PropertyReader].
///
/// Ensures that `TicketInputContextBuilder` only attempts to extract and
/// download references (Confluence pages, Figma designs, Jira/GitHub/ADO
/// tickets and attachments) for integrations that are actually connected via
/// secrets.
class SourceCapabilities {
  /// Creates a capability inspector backed by [reader].
  const SourceCapabilities(this.reader);

  /// The property reader inspected for integration credentials.
  final PropertyReader reader;

  /// Whether Confluence (`CONFLUENCE_BASE_PATH` + token) is configured.
  bool get isConfluenceConfigured {
    final base = reader.getConfluenceBasePath()?.trim() ?? '';
    final token = reader.getConfluenceLoginPassToken()?.trim() ?? '';
    return base.isNotEmpty && token.isNotEmpty;
  }

  /// Whether Figma (`FIGMA_TOKEN` or `FIGMA_OAUTH_ACCESS_TOKEN` or OAuth2
  /// refresh credentials) is configured.
  bool get isFigmaConfigured => resolveFigmaToken(reader) != null;

  /// Whether Jira (`JIRA_BASE_PATH` + login/pass token) is configured.
  bool get isJiraConfigured {
    final base = reader.getJiraBasePath()?.trim() ?? '';
    final token = reader.getJiraLoginPassToken()?.trim() ?? '';
    return base.isNotEmpty && token.isNotEmpty;
  }

  /// Whether GitHub (`SOURCE_GITHUB_TOKEN` or `GITHUB_TOKEN`) is configured.
  bool get isGithubConfigured => resolveGithubToken(reader) != null;

  /// Whether Azure DevOps (`ADO_ORGANIZATION` + `ADO_PROJECT` +
  /// `ADO_PAT_TOKEN`) is configured.
  bool get isAdoConfigured {
    final org = reader.getAdoOrganization()?.trim() ?? '';
    final project = reader.getAdoProject()?.trim() ?? '';
    final pat = reader.getAdoPatToken()?.trim() ?? '';
    return org.isNotEmpty && project.isNotEmpty && pat.isNotEmpty;
  }

  /// Resolves the active Figma token (`FIGMA_OAUTH_ACCESS_TOKEN` or
  /// `FIGMA_TOKEN` or `FIGMA_API_KEY`), or `null` when unconfigured.
  static String? resolveFigmaToken(PropertyReader reader) {
    final oauth = reader.getFigmaOAuth2AccessToken()?.trim() ?? '';
    if (oauth.isNotEmpty) return oauth;
    final pat = reader.getFigmaApiKey()?.trim() ?? '';
    if (pat.isNotEmpty) return pat;
    final legacy = reader.getValue('FIGMA_API_KEY')?.trim() ?? '';
    return legacy.isNotEmpty ? legacy : null;
  }

  /// Resolves the active GitHub token (`SOURCE_GITHUB_TOKEN` or
  /// `GITHUB_TOKEN`), or `null` when unconfigured.
  static String? resolveGithubToken(PropertyReader reader) {
    final source = reader.getGithubToken()?.trim() ?? '';
    if (source.isNotEmpty) return source;
    final gh = reader.getValue('GITHUB_TOKEN')?.trim() ?? '';
    return gh.isNotEmpty ? gh : null;
  }
}

String? _str(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

bool _bool(
  Map<String, dynamic> primary,
  Map<String, dynamic> secondary,
  String key,
  bool defaultValue,
) {
  final raw = primary.containsKey(key) && primary[key] != null
      ? primary[key]
      : secondary[key];
  if (raw is bool) return raw;
  if (raw is String) return raw.toLowerCase() == 'true';
  return defaultValue;
}

int _int(
  Map<String, dynamic> primary,
  Map<String, dynamic> secondary,
  String key,
  int defaultValue,
) {
  final raw = primary.containsKey(key) && primary[key] != null
      ? primary[key]
      : secondary[key];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? defaultValue;
  return defaultValue;
}

List<String> _strList(dynamic value) {
  if (value is List) {
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}
