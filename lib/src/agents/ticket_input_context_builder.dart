/// Builds the input context folder for CliAgent from tracker ticket data.
///
/// Ports Java `TicketInputContextBuilder` and `CliExecutionHelper.createInputContext` —
/// creates `input/<contextId>/` with:
/// - `ticket.md` — the ticket description as markdown
/// - `request.md` — full ticket details as markdown (Java `createInputContext` parity)
/// - `ticket.json` — raw ticket data as JSON
/// - `subtasks/` — one markdown file per subtask (if any)
/// - `comments.md` — ticket comments joined with separators (if any)
/// - `<attachment>` — downloaded ticket attachments (when enabled)
///
/// When no tracker is configured (ticket data is null), creates an empty
/// context folder so the CLI agent can still run without tracker context.
library;

import 'dart:convert';
import 'dart:io';

import '../config/property_reader.dart';
import '../config/property_reader_getters.dart';
import '../js/sync_http_client.dart';

/// Downloads an attachment from [url] and returns the raw bytes, or `null`
/// when the download fails.
typedef AttachmentDownloader = List<int>? Function(String url);

/// Builds the input context folder for CliAgent from tracker ticket data.
///
/// The builder accepts raw tracker JSON (e.g. a Jira REST ticket map) and
/// writes a self-contained markdown + JSON context that `preCliJSAction`
/// scripts and CLI agents can consume without network access.
class TicketInputContextBuilder {
  /// Creates a builder rooted at [workingDirectory].
  ///
  /// [attachmentDownloader] overrides the default HTTP downloader (which
  /// uses [SyncHttpClient] with Jira/ADO auth headers from [propertyReader]).
  TicketInputContextBuilder(
    this.workingDirectory, {
    AttachmentDownloader? attachmentDownloader,
    PropertyReader? propertyReader,
    this.includeAttachments = true,
    this.skipAllAttachments = false,
    this.skipVideoAttachments = false,
  })  : _propertyReader = propertyReader ?? PropertyReader(),
        _attachmentDownloader = attachmentDownloader;

  /// Base directory for the `input/` folder.
  final String workingDirectory;

  /// Whether to download ticket attachments into the input folder.
  final bool includeAttachments;

  /// Whether to skip all ticket attachments.
  final bool skipAllAttachments;

  /// Whether to skip video attachments when [includeAttachments] is true.
  final bool skipVideoAttachments;

  final PropertyReader _propertyReader;
  final AttachmentDownloader? _attachmentDownloader;

  static final RegExp _githubCompositeKey = RegExp(r'^[\w.-]+/[\w.-]+#(\d+)$');
  static final RegExp _githubBareKey = RegExp(r'^#(\d+)$');
  static final RegExp _adoEmbeddedImg = RegExp(
    r'<img\b[^>]*?\bsrc="([^"]*?/_apis/wit/attachments/[^"]*)"[^>]*>',
    caseSensitive: false,
  );

  /// Video file extensions skipped when [skipVideoAttachments] is true
  /// (Java `CliExecutionHelper.VIDEO_EXTENSIONS` parity).
  static const List<String> videoExtensions = [
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
    '.3gp',
    '.ogv',
    '.mpg',
    '.mpeg',
  ];

  /// Returns true if [fileName] has a video file extension
  /// (Java `CliExecutionHelper.isVideoFile` parity).
  static bool isVideoFile(String? fileName) {
    if (fileName == null || fileName.isEmpty) return false;
    final lower = fileName.toLowerCase();
    return videoExtensions.any(lower.endsWith);
  }

  /// Sanitizes an attachment filename by replacing path separators with `_`
  /// (Java `CliExecutionHelper.downloadAttachments` parity).
  static String sanitizeAttachmentFileName(String fileName) =>
      fileName.replaceAll(RegExp(r'[/\\]'), '_');

  /// Maps a ticket/context key to the `input/` subfolder name.
  ///
  /// Mirrors Java `CliExecutionHelper.toInputFolderName`: a GitHub composite
  /// key (`owner/repo#12` or `#12`) becomes the router key `gh-12` so JS
  /// agents and CLI prompts read a single flat `input/gh-12/` folder instead
  /// of a nested `input/owner/repo#12/` path. Other keys are preserved as-is
  /// for backward compatibility.
  static String toInputFolderName(String contextId) {
    final composite = _githubCompositeKey.firstMatch(contextId);
    if (composite != null) return 'gh-${composite.group(1)}';
    final bare = _githubBareKey.firstMatch(contextId);
    if (bare != null) return 'gh-${bare.group(1)}';
    return contextId;
  }

  /// Builds the input context for [contextId] from [ticketData].
  ///
  /// If [ticketData] is null (no tracker configured), creates an empty
  /// `input/<folderName>/` folder. Returns the path to the context folder.
  String build(
    String contextId, {
    Map<String, dynamic>? ticketData,
    bool? includeAttachments,
    bool? skipAllAttachments,
    bool? skipVideoAttachments,
  }) {
    final folderName = toInputFolderName(contextId);
    final contextPath = '$workingDirectory/input/$folderName';
    Directory(contextPath).createSync(recursive: true);
    if (ticketData == null) return contextPath;
    _writeTicketFiles(contextPath, ticketData);
    _downloadTicketAttachments(
      contextPath,
      ticketData,
      include: includeAttachments ?? this.includeAttachments,
      skipAll: skipAllAttachments ?? this.skipAllAttachments,
      skipVideo: skipVideoAttachments ?? this.skipVideoAttachments,
    );
    return contextPath;
  }

  // -- File writers ----------------------------------------------------

  /// Writes ticket.md, request.md, ticket.json, subtasks/, and comments.md.
  void _writeTicketFiles(String dir, Map<String, dynamic> ticket) {
    final markdown = _formatMarkdown(ticket);
    File('$dir/ticket.md').writeAsStringSync(markdown);
    File('$dir/request.md').writeAsStringSync(markdown);
    File('$dir/ticket.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(ticket),
    );
    final fields = _mapValue(ticket['fields']);
    _writeSubtasks(dir, fields);
    _writeComments(dir, fields);
  }

  /// Writes each subtask in `fields.subtasks` to `subtasks/<key>.md`.
  void _writeSubtasks(String dir, Map<String, dynamic> fields) {
    final subtasks = _listValue(fields['subtasks']);
    Directory? subtaskDir;
    for (final subtask in subtasks) {
      final st = _mapValue(subtask);
      if (st.isEmpty) continue;
      subtaskDir ??= Directory('$dir/subtasks')..createSync(recursive: true);
      final key = _stringValue(st['key']) ?? 'subtask';
      File('${subtaskDir.path}/$key.md').writeAsStringSync(
        _formatMarkdown(st),
      );
    }
  }

  /// Writes comments.md when the ticket has comments.
  void _writeComments(String dir, Map<String, dynamic> fields) {
    final comments = _resolveComments(fields);
    if (comments.isEmpty) return;
    final buf = StringBuffer('## Comments\n');
    for (final comment in comments) {
      final cm = _mapValue(comment);
      if (cm.isEmpty) continue;
      buf.write('\n---\n\n');
      buf.write(_formatComment(cm));
    }
    File('$dir/comments.md').writeAsStringSync(buf.toString());
  }

  // -- Markdown formatters ---------------------------------------------

  /// Formats a ticket map as a markdown document.
  ///
  /// Extracts `key`, `fields.summary`, `fields.description`,
  /// `fields.status.name`, and `fields.priority.name`, writing the sections
  /// that are present. Missing fields are omitted gracefully.
  String _formatMarkdown(Map<String, dynamic> ticket) {
    final fields = _mapValue(ticket['fields']);
    final key = _stringValue(ticket['key']) ?? _stringValue(ticket['id']);
    final summary =
        _stringValue(fields['summary']) ?? _stringValue(fields['System.Title']);
    final status =
        _nestedName(fields, 'status') ?? _stringValue(fields['System.State']);
    final priority = _nestedName(fields, 'priority') ??
        _stringValue(fields['Microsoft.VSTS.Common.Priority']);
    final description = _stringValue(fields['description']) ??
        _stringValue(fields['System.Description']) ??
        _stringValue(fields['Microsoft.VSTS.TCM.ReproSteps']) ??
        '(no description)';
    return _assembleMarkdown(key, summary, status, priority, description);
  }

  /// Assembles the markdown title, metadata, and description sections.
  String _assembleMarkdown(
    String? key,
    String? summary,
    String? status,
    String? priority,
    String description,
  ) {
    final title = (key != null && summary != null)
        ? '$key: $summary'
        : (key ?? summary ?? 'Ticket');
    final buf = StringBuffer('# $title\n\n');
    if (status != null) buf.write('**Status:** $status  \n');
    if (priority != null) buf.write('**Priority:** $priority  \n');
    if (status != null || priority != null) buf.write('\n');
    buf.write('## Description\n\n$description\n');
    return buf.toString();
  }

  /// Formats a single comment as markdown with author/date prefix.
  String _formatComment(Map<String, dynamic> comment) {
    final author = _nestedName(comment, 'author');
    final created = _stringValue(comment['created']);
    final body = _stringValue(comment['body']) ?? '';
    final header = <String>[];
    if (author != null) header.add('**$author**');
    if (created != null) header.add('($created)');
    return header.isEmpty ? body : '${header.join(' ')}:\n\n$body';
  }

  // -- Safe extractors -------------------------------------------------

  /// Resolves comments from `fields.comment.comments` or top-level `comments`.
  List<dynamic> _resolveComments(Map<String, dynamic> fields) {
    final commentField = _mapValue(fields['comment']);
    if (commentField['comments'] is List) {
      return commentField['comments'] as List;
    }
    if (fields['comments'] is List) return fields['comments'] as List;
    return const [];
  }

  /// Returns [value] as a `Map<String, dynamic>`, or an empty map.
  Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  /// Returns [value] as a `List`, or an empty list.
  List<dynamic> _listValue(dynamic value) {
    return value is List ? value : const [];
  }

  /// Returns [value] as a trimmed string, or null when blank.
  String? _stringValue(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Reads the nested `name` field from `map[field]`, or null.
  String? _nestedName(Map<String, dynamic> map, String field) {
    return _stringValue(_mapValue(map[field])['name']);
  }

  // -- Attachment extraction and downloading ---------------------------

  /// Extracts, filters, and downloads ticket attachments into [dir].
  void _downloadTicketAttachments(
    String dir,
    Map<String, dynamic> ticket, {
    required bool include,
    required bool skipAll,
    required bool skipVideo,
  }) {
    if (!include || skipAll) return;
    final attachments = _extractAttachments(ticket);
    if (attachments.isEmpty) return;
    final downloader = _attachmentDownloader ?? _defaultDownloadBytes;
    for (final att in attachments) {
      if (skipVideo && isVideoFile(att.name)) continue;
      _downloadSingleAttachment(dir, att, downloader);
    }
  }

  /// Downloads one attachment and writes it to [dir]; errors are non-fatal.
  void _downloadSingleAttachment(
    String dir,
    ({String name, String url}) att,
    AttachmentDownloader downloader,
  ) {
    final safeName = sanitizeAttachmentFileName(att.name.trim());
    if (safeName.isEmpty || att.url.trim().isEmpty) return;
    try {
      final bytes = downloader(att.url.trim());
      if (bytes == null) return;
      File('$dir/$safeName').writeAsBytesSync(bytes, flush: true);
    } catch (e) {
      stderr.writeln('Failed to download attachment ${att.name}: $e');
    }
  }

  /// Collects attachments from Jira `fields.attachment`, top-level
  /// `attachments`, ADO `relations`, and ADO embedded description images.
  List<({String name, String url})> _extractAttachments(
    Map<String, dynamic> ticket,
  ) {
    final fields = _mapValue(ticket['fields']);
    final result = <({String name, String url})>[];
    _addFieldAttachments(result, _listValue(fields['attachment']));
    _addFieldAttachments(result, _listValue(fields['attachments']));
    _addFieldAttachments(result, _listValue(ticket['attachments']));
    _addAdoRelationAttachments(result, _listValue(ticket['relations']));
    final adoDesc = _stringValue(fields['System.Description']);
    if (adoDesc != null) _addAdoEmbeddedImages(result, adoDesc);
    return result;
  }

  /// Adds Jira-style (`filename`/`content` or `name`/`url`) attachments.
  void _addFieldAttachments(
    List<({String name, String url})> target,
    List<dynamic> rawList,
  ) {
    for (final item in rawList) {
      final map = _mapValue(item);
      final name = _stringValue(map['filename']) ?? _stringValue(map['name']);
      final url = _stringValue(map['content']) ?? _stringValue(map['url']);
      if (name != null && url != null) {
        target.add((name: name, url: url));
      }
    }
  }

  /// Adds ADO `AttachedFile` relations (`relations[].rel == "AttachedFile"`).
  void _addAdoRelationAttachments(
    List<({String name, String url})> target,
    List<dynamic> relations,
  ) {
    for (final item in relations) {
      final rel = _mapValue(item);
      if (_stringValue(rel['rel']) != 'AttachedFile') continue;
      final url = _stringValue(rel['url']);
      if (url == null) continue;
      final attrs = _mapValue(rel['attributes']);
      final name = _stringValue(attrs['name']) ?? _extractAdoFileName(url);
      target.add((name: name, url: url));
    }
  }

  /// Extracts embedded ADO attachment images from HTML description.
  void _addAdoEmbeddedImages(
    List<({String name, String url})> target,
    String html,
  ) {
    for (final match in _adoEmbeddedImg.allMatches(html)) {
      final url = match.group(1)?.trim();
      if (url == null || url.isEmpty) continue;
      final name = _extractAdoEmbeddedFileName(url);
      target.add((name: name, url: url));
    }
  }

  /// Extracts a filename from an ADO relation attachment URL
  /// (Java `Attachment.extractFileNameFromUrl` parity).
  static String _extractAdoFileName(String url) {
    final fromQuery = _fileNameQueryParam(url);
    if (fromQuery != null) return fromQuery;
    final qIdx = url.indexOf('?');
    final clean = qIdx >= 0 ? url.substring(0, qIdx) : url;
    final slash = clean.lastIndexOf('/');
    if (slash >= 0 && slash < clean.length - 1) {
      return clean.substring(slash + 1);
    }
    return 'attachment';
  }

  /// Extracts a filename from an ADO embedded image URL
  /// (Java `WorkItem.extractFileNameFromUrl` parity).
  static String _extractAdoEmbeddedFileName(String url) {
    final fromQuery = _fileNameQueryParam(url);
    if (fromQuery != null) return fromQuery;
    const marker = '/attachments/';
    final idx = url.indexOf(marker);
    if (idx >= 0) {
      final start = idx + marker.length;
      final end = url.indexOf('?', start);
      final id = end >= 0 ? url.substring(start, end) : url.substring(start);
      if (id.isNotEmpty) return 'attachment_$id.png';
    }
    return 'image.png';
  }

  /// Reads `fileName=` from [url]'s query string when present.
  static String? _fileNameQueryParam(String url) {
    const key = 'fileName=';
    final idx = url.indexOf(key);
    if (idx < 0) return null;
    final start = idx + key.length;
    final amp = url.indexOf('&', start);
    final raw = amp >= 0 ? url.substring(start, amp) : url.substring(start);
    final decoded = Uri.decodeQueryComponent(raw).trim();
    return decoded.isEmpty ? null : decoded;
  }

  /// Default HTTP attachment downloader using [SyncHttpClient] and
  /// tracker auth headers from [_propertyReader].
  List<int>? _defaultDownloadBytes(String url) {
    final headers = resolveAuthHeadersForUrl(url, _propertyReader);
    final resp = SyncHttpClient.get(
      url,
      headers: headers,
      followRedirects: true,
    );
    if (!resp.isOk) {
      stderr.writeln(
        'Attachment download failed (HTTP ${resp.statusCode}) for $url',
      );
      return null;
    }
    return resp.bodyBytes;
  }

  /// Resolves auth headers matching [url] against configured trackers in
  /// [reader] (Jira `Authorization` + `X-Atlassian-Token`, or ADO `Basic` PAT).
  static Map<String, String>? resolveAuthHeadersForUrl(
    String url,
    PropertyReader reader,
  ) =>
      _jiraHeadersForUrl(url, reader) ?? _adoHeadersForUrl(url, reader);
}

Map<String, String>? _jiraHeadersForUrl(String url, PropertyReader reader) {
  final token = reader.getJiraLoginPassToken();
  if (token == null || token.isEmpty) return null;
  final base = reader.getJiraBasePath();
  if (!_matchesHost(url, base, allowEmptyBase: true)) return null;
  final authType = reader.getJiraAuthType() ?? 'Basic';
  return {
    'Authorization': '$authType $token',
    'X-Atlassian-Token': 'nocheck',
  };
}

Map<String, String>? _adoHeadersForUrl(String url, PropertyReader reader) {
  final pat = reader.getAdoPatToken();
  if (pat == null || pat.isEmpty) return null;
  final base = reader.getAdoBasePath();
  final urlHost = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  final isAdoHost =
      urlHost.endsWith('dev.azure.com') || urlHost.endsWith('visualstudio.com');
  if (!isAdoHost && !_matchesHost(url, base, allowEmptyBase: false)) {
    return null;
  }
  final basic = base64Encode(utf8.encode(':$pat'));
  return {'Authorization': 'Basic $basic'};
}

bool _matchesHost(
  String url,
  String? configuredBase, {
  required bool allowEmptyBase,
}) {
  final baseHost = configuredBase != null && configuredBase.isNotEmpty
      ? (Uri.tryParse(configuredBase)?.host.toLowerCase() ?? '')
      : '';
  if (baseHost.isEmpty) return allowEmptyBase;
  final urlHost = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return urlHost == baseHost;
}
