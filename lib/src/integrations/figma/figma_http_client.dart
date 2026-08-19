/// HTTP client for the Figma REST API.
///
/// Ports the transport layer used by the Java DMTools Figma integration:
/// Bearer-token auth assembled from `FIGMA_TOKEN`, the base URL from
/// `FIGMA_BASE_PATH` (default `https://api.figma.com/v1`).
library;

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';
import '../bearer_http_client.dart';

/// Default Figma REST API base path.
const String figmaDefaultBasePath = 'https://api.figma.com/v1';

/// Low-level Figma HTTP transport used by [FigmaClient].
///
/// Token storage, auth headers, and URL building come from
/// [BearerHttpClient]; this class only resolves its configuration.
class FigmaHttpClient extends BearerHttpClient {
  /// Creates a client from [reader]'s Figma configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when `FIGMA_TOKEN` is missing or empty.
  factory FigmaHttpClient(PropertyReader reader, {Dio? dio}) {
    final token = reader.getFigmaApiKey();
    final basePath = reader.getFigmaBasePath() ?? figmaDefaultBasePath;
    if (token == null || token.isEmpty) {
      throw StateError(
        'Figma auth not configured (FIGMA_TOKEN is required)',
      );
    }
    return FigmaHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      token: token,
    );
  }

  const FigmaHttpClient._({
    required super.dio,
    required super.basePath,
    required super.token,
  });
}
