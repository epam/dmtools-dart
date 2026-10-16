/// Builds the input context folder for CliAgent from tracker ticket data.
///
/// Ports Java `TicketInputContextBuilder` — creates `input/<contextId>/` with:
/// - `ticket.md` — the ticket description as markdown
/// - `ticket.json` — raw ticket data as JSON
/// - `subtasks/` — one markdown file per subtask (if any)
/// - `comments.md` — ticket comments joined with separators (if any)
///
/// When no tracker is configured (ticket data is null), creates an empty
/// context folder so the CLI agent can still run without tracker context.
library;

import 'dart:convert';
import 'dart:io';

/// Builds the input context folder for CliAgent from tracker ticket data.
///
/// The builder accepts raw tracker JSON (e.g. a Jira REST ticket map) and
/// writes a self-contained markdown + JSON context that `preCliJSAction`
/// scripts and CLI agents can consume without network access.
class TicketInputContextBuilder {
  /// Creates a builder rooted at [workingDirectory].
  TicketInputContextBuilder(this.workingDirectory);

  /// Base directory for the `input/` folder.
  final String workingDirectory;

  /// Builds the input context for [contextId] from [ticketData].
  ///
  /// If [ticketData] is null (no tracker configured), creates an empty
  /// `input/<contextId>/` folder. Returns the path to the context folder.
  String build(String contextId, {Map<String, dynamic>? ticketData}) {
    final contextPath = '$workingDirectory/input/$contextId';
    Directory(contextPath).createSync(recursive: true);
    if (ticketData == null) return contextPath;
    _writeTicketFiles(contextPath, ticketData);
    return contextPath;
  }

  // -- File writers ----------------------------------------------------

  /// Writes ticket.md, ticket.json, subtasks/, and comments.md.
  void _writeTicketFiles(String dir, Map<String, dynamic> ticket) {
    File('$dir/ticket.md').writeAsStringSync(_formatMarkdown(ticket));
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
    final key = _stringValue(ticket['key']);
    final summary = _stringValue(fields['summary']);
    final status = _nestedName(fields, 'status');
    final priority = _nestedName(fields, 'priority');
    final description =
        _stringValue(fields['description']) ?? '(no description)';
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
}
