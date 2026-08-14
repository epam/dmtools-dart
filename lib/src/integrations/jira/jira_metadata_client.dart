/// Issue-metadata extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Issue-metadata methods on [JiraClient]: listing the resolutions,
/// priorities, and security levels available to issues.
extension JiraMetadataClient on JiraClient {
  /// `jira_get_resolutions` — GET `resolution`.
  ///
  /// Returns the full list of issue resolution definitions.
  Future<List<Map<String, dynamic>>> getResolutions() async {
    final body = await _http.get('resolution');
    return _decodeList(body);
  }

  /// `jira_get_priorities` — GET `priority`.
  ///
  /// Returns the full list of issue priority definitions.
  Future<List<Map<String, dynamic>>> getPriorities() async {
    final body = await _http.get('priority');
    return _decodeList(body);
  }

  /// `jira_get_security_levels` — GET `securitylevel`.
  ///
  /// Returns the full list of issue security level definitions.
  Future<List<Map<String, dynamic>>> getSecurityLevels() async {
    final body = await _http.get('securitylevel');
    return _decodeList(body);
  }
}
