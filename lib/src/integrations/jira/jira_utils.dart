/// Shared Jira utility functions used by multiple call sites.
library;

import 'dart:convert';

/// Finds a transition id in [transitions] matching [statusName].
///
/// Matches by transition name or destination status name (case-insensitive).
/// Used by both the async [JiraClient] and the sync [SyncToolDispatcher] so
/// the matching logic is defined in one place.
String? matchTransitionId(
  List<Map<String, dynamic>> transitions,
  String statusName,
) {
  final target = statusName.toLowerCase();
  for (final t in transitions) {
    final name = (t['name'] as String?)?.toLowerCase() ?? '';
    final toStatus = t['to'] as Map<String, dynamic>?;
    final toName = (toStatus?['name'] as String?)?.toLowerCase() ?? '';
    if (name == target || toName == target) return t['id'] as String?;
  }
  return null;
}

/// A field definition candidate from a Jira `field` listing.
///
/// Ports the Java `MultiFieldUpdateStrategy.CustomField` carrier: the pieces
/// [selectBestJiraField] ranks candidates by.
class JiraFieldCandidate {
  /// Field id, e.g. `customfield_10091`.
  final String id;

  /// Human-readable field name.
  final String name;

  /// Schema type string (e.g. `string`, `number`); empty when absent.
  final String schema;

  /// Whether the field is active (defaults to `true`, as in Java).
  final bool active;

  /// Creates a candidate.
  const JiraFieldCandidate(this.id, this.name, this.schema, this.active);
}

/// Extracts the numeric part of a custom-field [fieldId], or `0`.
///
/// Mirrors Java `MultiFieldUpdateStrategy.extractFieldNumber`.
int extractJiraFieldNumber(String fieldId) =>
    int.tryParse(fieldId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Finds every field in [fieldsJsonResponse] whose name matches [fieldName]
/// (case-insensitive). Malformed/non-array bodies yield an empty list — the
/// Java `findAllFieldsByName` catch-and-log contract.
List<JiraFieldCandidate> findAllJiraFieldsByName(
  String fieldName,
  String fieldsJsonResponse,
) {
  try {
    final decoded = jsonDecodeList(fieldsJsonResponse);
    return decoded
        .map(_asFieldCandidate)
        .where((f) => f.name.toLowerCase() == fieldName.toLowerCase())
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Builds a [JiraFieldCandidate] from a `field` listing entry.
JiraFieldCandidate _asFieldCandidate(Map<String, dynamic> field) {
  final schema = field['schema'];
  return JiraFieldCandidate(
    field['id']?.toString() ?? '',
    field['name']?.toString() ?? '',
    schema is Map ? schema['type']?.toString() ?? '' : '',
    field['active'] is bool ? field['active'] as bool : true,
  );
}

/// Selects the best candidate from [fields] (never mutates the input).
///
/// Mirrors Java `MultiFieldUpdateStrategy.selectBestField`: prefer active
/// fields; for `depend*`/`description*` names prefer text schemas; then the
/// highest `customfield_NNN` number. `null` for an empty list.
JiraFieldCandidate? selectBestJiraField(List<JiraFieldCandidate> fields) {
  if (fields.isEmpty) return null;
  final sorted = [...fields]..sort(_compareFieldCandidates);
  return sorted.first;
}

/// Orders candidates by the Java selection priority (lower sorts first).
int _compareFieldCandidates(JiraFieldCandidate a, JiraFieldCandidate b) {
  if (a.active != b.active) return a.active ? -1 : 1;
  final textOrder = _compareTextFieldPreference(a, b);
  if (textOrder != 0) return textOrder;
  return extractJiraFieldNumber(b.id).compareTo(extractJiraFieldNumber(a.id));
}

/// Text-schema preference order for `depend*`/`description*` names
/// (`0` when equal or not applicable).
int _compareTextFieldPreference(JiraFieldCandidate a, JiraFieldCandidate b) {
  if (!_prefersTextField(a.name)) return 0;
  final aText = _isTextSchema(a.schema);
  final bText = _isTextSchema(b.schema);
  return aText == bText ? 0 : (aText ? -1 : 1);
}

/// Whether [name] activates the Java text-schema preference.
bool _prefersTextField(String name) {
  final lower = name.toLowerCase();
  return lower.contains('depend') || lower.contains('description');
}

/// Whether [schema] is a text-ish schema type.
bool _isTextSchema(String schema) =>
    schema.contains('string') || schema.contains('text');

/// Resolves a relationship name against a Jira `issueLinkType` listing.
///
/// Mirrors Java `JiraClient.getRelationshipByName`: a match on the type name
/// or its inward description maps to `inward`; a match on the outward
/// description maps to `outward`. `null` when nothing matches.
({String direction, String name})? resolveJiraLinkType(
  List<Map<String, dynamic>> linkTypes,
  String relationship,
) {
  final target = relationship.toLowerCase();
  for (final type in linkTypes) {
    final name = type['name']?.toString() ?? '';
    final inward = type['inward']?.toString() ?? '';
    final outward = type['outward']?.toString() ?? '';
    if (target == name.toLowerCase() || target == inward.toLowerCase()) {
      return (direction: 'inward', name: name);
    }
    if (target == outward.toLowerCase()) {
      return (direction: 'outward', name: name);
    }
  }
  return null;
}

/// Decodes a JSON array body, returning `const []` for non-array JSON.
///
/// A JSON *parse* failure rethrows (callers decide the failure contract).
List<Map<String, dynamic>> jsonDecodeList(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return const [];
  return List<Map<String, dynamic>>.from(
    decoded.map((e) => e as Map<String, dynamic>),
  );
}
