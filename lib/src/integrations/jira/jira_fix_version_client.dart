/// Fix-version extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// Fix-version mutation methods on [JiraClient]: appending and removing
/// versions on a ticket's fix-version set.
extension JiraFixVersionClient on JiraClient {
  /// `jira_add_fix_version` — appends [version] via `update.fixVersions`.
  Future<void> addFixVersion(String key, String version) =>
      _mutateFixVersions(key, 'add', version);

  /// `jira_remove_fix_version` — removes [version] via `update.fixVersions`.
  Future<void> removeFixVersion(String key, String version) =>
      _mutateFixVersions(key, 'remove', version);

  /// PUTs an `update.fixVersions` operation ([op] is `add` or `remove`).
  Future<void> _mutateFixVersions(
    String key,
    String op,
    String version,
  ) async {
    await _http.put(
      'issue/$key',
      body: jsonEncode({
        'update': {
          'fixVersions': [
            {
              op: {'name': version}
            }
          ],
        },
      }),
    );
  }
}
