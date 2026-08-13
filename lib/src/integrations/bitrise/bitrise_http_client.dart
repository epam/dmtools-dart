/// HTTP client for the Bitrise REST API.
///
/// Auth uses a Bearer token resolved from `BITRISE_TOKEN` via [PropertyReader].
/// Endpoints live under the configured `BITRISE_BASE_PATH`
/// (default `https://api.bitrise.io/v0.1`).
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';
import '../bearer_http_client.dart';

/// Low-level Bitrise HTTP transport used by [BitriseClient].
///
/// Token storage, auth headers, and URL building come from
/// [BearerHttpClient]; this class only resolves its configuration.
class BitriseHttpClient extends BearerHttpClient {
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
    required super.token,
  });
}
