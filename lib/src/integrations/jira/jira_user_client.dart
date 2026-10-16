/// User and profile extension on [JiraClient] — one domain per file.
part of 'jira_client.dart';

/// User-account methods on [JiraClient]: account lookup by email, profile
/// fetch by account ID, and the current user's own profile.
extension JiraUserClient on JiraClient {
  /// `jira_get_account_by_email` — GET `user/search?username={email}`.
  ///
  /// Returns the first matching user, or an empty map when none is found.
  Future<Map<String, dynamic>> getAccountByEmail(String email) async {
    final body = await _http.get(
      'user/search',
      queryParams: {'username': email},
    );
    final decoded = jsonDecode(body);
    if (decoded is List && decoded.isNotEmpty) {
      return decoded.first as Map<String, dynamic>;
    }
    return {};
  }

  /// `jira_get_user_profile` — GET `user?accountId={userId}`.
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final body = await _http.get(
      'user',
      queryParams: {'accountId': userId},
    );
    return _decodeMap(body);
  }

  /// `jira_get_my_profile` — GET `myself`.
  Future<Map<String, dynamic>> getMyProfile() async {
    final body = await _http.get('myself');
    return _decodeMap(body);
  }
}
