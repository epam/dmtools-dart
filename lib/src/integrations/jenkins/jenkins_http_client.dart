/// HTTP client for the Jenkins REST API.
///
/// Auth uses HTTP Basic with credentials built from `JENKINS_USER` +
/// `JENKINS_API_TOKEN` via [PropertyReader]. Endpoints live under the
/// configured `JENKINS_BASE_PATH` (default `http://localhost:8080`).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level Jenkins HTTP transport used by [JenkinsClient].
class JenkinsHttpClient extends BaseHttpClient {
  final String _basicAuth;

  /// Creates a client from [reader]'s Jenkins configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when `JENKINS_USER` or `JENKINS_API_TOKEN` is missing.
  factory JenkinsHttpClient(PropertyReader reader, {Dio? dio}) {
    final basePath = reader.getJenkinsBasePath();
    final user = reader.getJenkinsUser();
    final token = reader.getJenkinsApiToken();
    if (user == null || user.isEmpty) {
      throw StateError('JENKINS_USER is not configured');
    }
    if (token == null || token.isEmpty) {
      throw StateError('JENKINS_API_TOKEN is not configured');
    }
    final basicAuth =
        base64Encode(utf8.encode('${user.trim()}:${token.trim()}'));
    return JenkinsHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: basePath,
      basicAuth: basicAuth,
    );
  }

  JenkinsHttpClient._({
    required super.dio,
    required super.basePath,
    required String basicAuth,
  }) : _basicAuth = basicAuth;

  @override
  Map<String, String> get authHeaders => {
        'Authorization': 'Basic $_basicAuth',
      };

  @override
  String buildUrl(String path) => '$basePath/$path';
}
