/// Data-export extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Data-export methods on [JiraClient]: bulk-exporting every issue that
/// matches a JQL query.
extension JiraExportClient on JiraClient {
  /// `jira_export_data` — bulk-export every issue matching [jql].
  ///
  /// Delegates to [JiraClient.searchByJql] for full auto-pagination (Cloud
  /// cursor + Server/DC offset), returning all matching issues as a flat
  /// list. Pass [fields] to restrict the exported field set.
  Future<List<Map<String, dynamic>>> exportData(
    String jql, [
    List<String>? fields,
  ]) =>
      searchByJql(jql, fields);
}
