/// HTTP client for the Bitrise REST API.
///
/// Auth uses the Bitrise `token` scheme — `Authorization: token <PAT>` with
/// the token resolved from `BITRISE_TOKEN` via [PropertyReader] (the v0.1 API
/// rejects the `Bearer` scheme, so [BearerHttpClient] cannot be reused here).
/// Endpoints live under the configured `BITRISE_BASE_PATH`
/// (default `https://api.bitrise.io/v0.1`).
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level Bitrise HTTP transport used by [BitriseClient].
///
/// Ports the `sign()` header from Java `Bitrise.java`: every request carries
/// `Authorization: token <PAT>`; [buildUrl] prefixes [path] with [basePath].
class BitriseHttpClient extends BaseHttpClient {
  /// The Bitrise personal access token sent in the auth header.
  final String _token;

  /// Creates a client from [reader]'s Bitrise configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when `BITRISE_TOKEN` is missing.
  factory BitriseHttpClient(PropertyReader reader, {Dio? dio}) {
    final basePath = reader.getBitriseBasePath();
    final token = reader.getBitriseToken();
    if (token == null || token.isEmpty) {
      throw StateError('BITRISE_TOKEN is not configured');
    }
    return BitriseHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      token: token,
    );
  }

  const BitriseHttpClient._({
    required super.dio,
    required super.basePath,
    required String token,
  }) : _token = token;

  @override
  Map<String, String> get authHeaders => {
        'Authorization': 'token $_token',
      };

  @override
  String buildUrl(String path) => '$basePath/$path';
}
