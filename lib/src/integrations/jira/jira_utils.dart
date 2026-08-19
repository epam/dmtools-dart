/// Shared Jira utility functions used by multiple call sites.
library;

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
