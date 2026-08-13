/// Shared base for Bearer-token authenticated integration HTTP clients.
///
/// Integrations that authenticate with a single bearer token (Bitrise, Figma)
/// extend this class instead of re-implementing [authHeaders] and [buildUrl].
/// Integrations whose auth differs — GitHub's extra `Accept` header, GitLab's
/// `PRIVATE-TOKEN`, Jira/Confluence's Basic+PAT duality — extend
/// [BaseHttpClient] directly.
library;

import 'base_http_client.dart';

/// Base class for integrations that authenticate with a single bearer token.
///
/// Stores the token and emits `Authorization: Bearer …` via [authHeaders];
/// [buildUrl] prefixes [path] with [basePath].
abstract class BearerHttpClient extends BaseHttpClient {
  final String _token;

  /// Creates a bearer-auth client bound to [dio] and [basePath].
  const BearerHttpClient({
    required super.dio,
    required super.basePath,
    required String token,
  }) : _token = token;

  @override
  Map<String, String> get authHeaders => {
        'Authorization': 'Bearer $_token',
      };

  @override
  String buildUrl(String path) => '$basePath/$path';
}
