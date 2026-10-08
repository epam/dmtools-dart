/// Pure, transport-free logic for the ADO ticket operations shared by the
/// async [AdoClient] and the synchronous JS-bridge executors.
///
/// Ports `AzureDevOpsClient` (dm.ai #661/#663): `resolveFieldName`,
/// `mapRelationshipType`, `mapPriority`, the JSON-Patch builders and the
/// field-code / attachment lookups.
library;

import 'dart:convert';

/// Reference-name table for common field names (Java `resolveFieldName`).
const _fieldNames = <String, String>{
  'id': 'System.Id',
  'title': 'System.Title',
  'summary': 'System.Title',
  'description': 'System.Description',
  'state': 'System.State',
  'assignedto': 'System.AssignedTo',
  'createdby': 'System.CreatedBy',
  'createddate': 'System.CreatedDate',
  'changeddate': 'System.ChangedDate',
  'workitemtype': 'System.WorkItemType',
  'priority': 'Microsoft.VSTS.Common.Priority',
  'tags': 'System.Tags',
  'areapath': 'System.AreaPath',
  'iterationpath': 'System.IterationPath',
  'storypoints': 'Microsoft.VSTS.Scheduling.StoryPoints',
  'effort': 'Microsoft.VSTS.Scheduling.Effort',
};

/// Maps a human field name to its ADO reference name; names containing a
/// `.` and unknown names pass through unchanged.
String resolveAdoFieldName(String fieldName) {
  if (fieldName.contains('.')) return fieldName;
  return _fieldNames[fieldName.toLowerCase()] ?? fieldName;
}

/// Relationship-name table (Java `mapRelationshipType`).
const _relationships = <String, String>{
  'parent': 'System.LinkTypes.Hierarchy-Reverse',
  'child': 'System.LinkTypes.Hierarchy-Forward',
  'blocks': 'System.LinkTypes.Dependency-Forward',
  'blocked by': 'System.LinkTypes.Dependency-Reverse',
  'blockedby': 'System.LinkTypes.Dependency-Reverse',
  'tested by': 'Microsoft.VSTS.Common.TestedBy-Forward',
  'testedby': 'Microsoft.VSTS.Common.TestedBy-Forward',
  'is tested by': 'Microsoft.VSTS.Common.TestedBy-Forward',
  'istestedby': 'Microsoft.VSTS.Common.TestedBy-Forward',
  'tests': 'Microsoft.VSTS.Common.TestedBy-Forward',
};

/// Maps a relationship name to an ADO relation type; full
/// `System.LinkTypes.*` / `Microsoft.VSTS.Common.*` names pass through and
/// anything else is `System.LinkTypes.Related`.
String mapAdoRelationship(String? relationship) {
  if (relationship == null) return 'System.LinkTypes.Related';
  final lower = relationship.toLowerCase();
  if (lower.startsWith('system.linktypes.') ||
      lower.startsWith('microsoft.vsts.common.')) {
    return relationship;
  }
  return _relationships[lower] ?? 'System.LinkTypes.Related';
}

/// Jira-style priority names (Java `mapPriority`).
const _priorities = <String, int>{
  'blocker': 1,
  'highest': 1,
  'critical': 1,
  'high': 2,
  'major': 2,
  'medium': 3,
  'normal': 3,
  'low': 4,
  'minor': 4,
  'lowest': 4,
  'trivial': 4,
};

/// Maps a priority name or `1`-`4` to the ADO priority number.
///
/// Throws [ArgumentError] (message = Java's text) for blank/unknown input.
int mapAdoPriority(String? priority) {
  if (priority == null || priority.trim().isEmpty) {
    throw ArgumentError('Priority must not be empty');
  }
  final p = priority.trim().toLowerCase();
  final number = RegExp(r'^[1-4]$').hasMatch(p) ? int.parse(p) : _priorities[p];
  if (number == null) {
    throw ArgumentError("Unknown priority '$priority'. Use 1-4 or one of: "
        'Blocker, Highest, Critical, High, Major, Medium, Normal, Low, '
        'Minor, Lowest, Trivial');
  }
  return number;
}

Map<String, dynamic> _addField(String name, Object? value) =>
    {'op': 'add', 'path': '/fields/$name', 'value': value};

/// JSON-Patch body (encoded) setting each entry of [fields] — Java
/// `updateWorkItem`.
String adoFieldsPatch(Map<String, Object?> fields) => jsonEncode([
      for (final e in fields.entries) _addField(e.key, e.value),
    ]);

/// JSON-Patch body for work-item creation: title, optional description,
/// then [fieldsJson] keys (skipping Title/Description/WorkItemType).
String adoCreatePatch(
  String title,
  String? description,
  Map<String, dynamic>? fieldsJson,
) {
  const skipped = {'System.Title', 'System.Description', 'System.WorkItemType'};
  return jsonEncode([
    _addField('System.Title', title),
    if (description != null && description.isNotEmpty)
      _addField('System.Description', description),
    for (final e in (fieldsJson ?? const <String, dynamic>{}).entries)
      if (!skipped.contains(e.key)) _addField(e.key, e.value),
  ]);
}

/// JSON-Patch body adding a relation of [rel] pointing at [url].
String adoRelationPatch(
  String rel,
  String url, {
  Map<String, String>? attributes,
}) =>
    jsonEncode([
      {
        'op': 'add',
        'path': '/relations/-',
        'value': {
          'rel': rel,
          'url': url,
          if (attributes != null) 'attributes': attributes,
        },
      },
    ]);

/// The `referenceName` of the field whose `name` or `referenceName` equals
/// [wanted] (case-insensitive) in a `wit/fields` response body, else `null`.
String? findAdoFieldCode(String? body, String wanted) {
  if (body == null || body.isEmpty) return null;
  final fields = _asMap(jsonDecode(body))?['value'];
  final target = wanted.trim().toLowerCase();
  for (final f in fields is List ? fields.whereType<Map>() : const <Map>[]) {
    if (target == '${f['name']}'.toLowerCase() ||
        target == '${f['referenceName']}'.toLowerCase()) {
      return f['referenceName'] as String?;
    }
  }
  return null;
}

Map? _asMap(dynamic v) => v is Map ? v : null;

/// Whether [workItem] already carries an `AttachedFile` relation named
/// [name] (case-insensitive; Java `WorkItem.getAttachments`).
bool adoHasAttachment(dynamic workItem, String name) {
  final relations = workItem is Map ? workItem['relations'] : null;
  if (relations is! List) return false;
  final wanted = name.toLowerCase();
  for (final r in relations.whereType<Map>()) {
    if (r['rel'] != 'AttachedFile') continue;
    final attrs = r['attributes'];
    final n = attrs is Map ? '${attrs['name'] ?? ''}' : '';
    if (n.toLowerCase() == wanted) return true;
  }
  return false;
}

/// Reads the first present non-null [keys] value of [args] as a string.
String adoArg(Map<String, dynamic> args, List<String> keys) {
  for (final k in keys) {
    final v = args[k];
    if (v != null) return v.toString();
  }
  return '';
}
