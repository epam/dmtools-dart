/// HTTP client for the TestRail REST API.
///
/// Ports the transport layer used by the Java DMTools TestRail integration:
/// Basic auth assembled from `TESTRAIL_USERNAME` + `TESTRAIL_API_KEY` as
/// `base64(username:apikey)`, the base URL from `TESTRAIL_BASE_PATH`, and the
/// project identifier from `TESTRAIL_PROJECT`.
///
/// TestRail routes API endpoints through an unusual `index.php?/api/v2/`
/// prefix: the `?` is part of the route, so additional query parameters are
/// appended with `&` directly in the [BaseHttpClient.buildUrl] path string
/// rather than through dio's `queryParameters` (which would re-encode the
/// route).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level TestRail HTTP transport used by [TestRailClient].
class TestRailHttpClient extends BaseHttpClient {
  final String _authHeader;

  /// The TestRail username (email) from `TESTRAIL_USERNAME`.
  ///
  /// Doubles as the email lookup for the connectivity check and is exposed
  /// for the higher-level client.
  final String username;

  /// The TestRail project identifier from `TESTRAIL_PROJECT`.
  final String projectId;

  /// Creates a client from [reader]'s TestRail configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when any required key (`TESTRAIL_BASE_PATH`,
  /// `TESTRAIL_USERNAME`, `TESTRAIL_API_KEY`, `TESTRAIL_PROJECT`) is missing
  /// or empty.
  factory TestRailHttpClient(PropertyReader reader, {Dio? dio}) {
    final basePath = _require(
      reader.getTestRailBasePath(),
      'TESTRAIL_BASE_PATH',
    );
    final username = _require(
      reader.getTestRailUsername(),
      'TESTRAIL_USERNAME',
    );
    final apiKey = _require(reader.getTestRailApiKey(), 'TESTRAIL_API_KEY');
    final project = _require(
      reader.getTestRailProject(),
      'TESTRAIL_PROJECT',
    );
    final creds = '$username:$apiKey';
    return TestRailHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      authHeader: 'Basic ${base64Encode(utf8.encode(creds))}',
      username: username,
      projectId: project,
    );
  }

  TestRailHttpClient._({
    required super.dio,
    required super.basePath,
    required String authHeader,
    required this.username,
    required this.projectId,
  }) : _authHeader = authHeader;

  @override
  Map<String, String> get authHeaders => {'Authorization': _authHeader};

  @override
  String buildUrl(String path) => '$basePath/index.php?/api/v2/$path';
}

/// Returns [value], or throws [StateError] when null/empty.
String _require(String? value, String configKey) {
  if (value == null || value.isEmpty) {
    throw StateError('$configKey is not configured');
  }
  return value;
}
