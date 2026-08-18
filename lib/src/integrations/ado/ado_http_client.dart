/// HTTP client for the Azure DevOps REST API.
///
/// Ports the transport layer of the Java DMTools `AzureDevOpsClient`:
/// Basic auth assembled from `ADO_PAT_TOKEN` as `base64(':' + PAT)` (Java
/// `encodePatToken`), the base URL `{ADO_BASE_PATH}/{organization}/{project}/_apis/`,
/// and `api-version=7.0` attached to every request (Java `API_VERSION`).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/property_reader.dart';
import '../../config/property_reader_getters.dart';
import '../base_http_client.dart';

/// Low-level Azure DevOps HTTP transport used by [AdoClient].
class AdoHttpClient extends BaseHttpClient {
  final String _authorization;
  final String _organization;
  final String _project;

  /// REST API version sent on every request (mirrors Java `API_VERSION`).
  static const apiVersion = '7.0';

  /// Creates a client from [reader]'s ADO configuration.
  ///
  /// Pass [dio] to inject a custom HTTP transport (tests); production code
  /// omits it and gets a default [Dio] with 60s timeouts.
  ///
  /// Throws [StateError] when `ADO_ORGANIZATION`, `ADO_PROJECT`, or
  /// `ADO_PAT_TOKEN` is missing or empty.
  factory AdoHttpClient(PropertyReader reader, {Dio? dio}) {
    final organization = reader.getAdoOrganization();
    final project = reader.getAdoProject();
    final pat = reader.getAdoPatToken();
    if (organization == null || organization.isEmpty) {
      throw StateError('ADO_ORGANIZATION is not configured');
    }
    if (project == null || project.isEmpty) {
      throw StateError('ADO_PROJECT is not configured');
    }
    if (pat == null || pat.isEmpty) {
      throw StateError('ADO_PAT_TOKEN is not configured');
    }
    return AdoHttpClient._(
      dio: dio ?? BaseHttpClient.createDefaultDio(),
      basePath: reader.getAdoBasePath(),
      organization: organization,
      project: project,
      authorization: _encodePat(pat),
    );
  }

  AdoHttpClient._({
    required super.dio,
    required super.basePath,
    required String organization,
    required String project,
    required String authorization,
  })  : _organization = organization,
        _project = project,
        _authorization = authorization;

  /// Encodes a PAT as a Basic auth value: `Basic base64(':' + pat)`.
  static String _encodePat(String pat) =>
      'Basic ${base64Encode(utf8.encode(':$pat'))}';

  @override
  Map<String, String> get authHeaders => {'Authorization': _authorization};

  /// Builds a project-scoped URL: `{base}/{organization}/{project}/_apis/{path}`.
  @override
  String buildUrl(String path) =>
      '$basePath/$_organization/$_project/_apis/$path';

  /// Builds an organization-scoped URL: `{base}/{organization}/_apis/{path}`.
  String buildOrgUrl(String path) => '$basePath/$_organization/_apis/$path';

  /// Performs a GET against an org-scoped path, with the API version attached.
  Future<String> getOrg(String path) async {
    final response = await dio.get<String>(
      buildOrgUrl(path),
      queryParameters: {'api-version': apiVersion},
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Performs a GET against the Profile API host
  /// (`app.vssps.visualstudio.com`), which serves PAT-authenticated
  /// profile lookups off the organization host — mirrors Java
  /// `executeProfileRequest` (org-host `_apis/connection-data` rejects
  /// PATs scoped to work items).
  Future<String> getProfile(String path) async {
    final response = await dio.get<String>(
      'https://app.vssps.visualstudio.com/_apis/$path',
      queryParameters: {'api-version': '7.1'},
      options: Options(
        headers: {...headers, 'User-Agent': 'DMTools'},
      ),
    );
    return response.data ?? '';
  }

  /// Performs a GET, merging `api-version` into the query parameters.
  @override
  Future<String> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? extra,
  }) =>
      super.get(
        path,
        queryParams: {...?queryParams, 'api-version': apiVersion},
        extra: extra,
      );

  /// Sends [method] against a project-scoped path, attaching the API version
  /// and Basic auth. [contentType] overrides the default JSON content type
  /// (used for ADO's `application/json-patch+json` work-item operations).
  Future<String> _request(
    String method,
    String path, {
    Object? body,
    String contentType = 'application/json',
  }) async {
    final response = await dio.request<String>(
      buildUrl(path),
      data: body,
      queryParameters: {'api-version': apiVersion},
      options: Options(
        method: method,
        headers: {...authHeaders, 'Content-Type': contentType},
      ),
    );
    return response.data ?? '';
  }

  /// POSTs a JSON body, attaching the API version as a query parameter.
  @override
  Future<String> post(String path, {Object? body}) =>
      _request('POST', path, body: body);

  /// PUTs a JSON body, attaching the API version as a query parameter. Used
  /// to add pull-request reviewers.
  @override
  Future<String> put(String path, {Object? body}) =>
      _request('PUT', path, body: body);

  /// POSTs a JSON Patch document with ADO's `application/json-patch+json`
  /// content type, attaching the API version. Used for work-item creation.
  Future<String> postPatch(String path, {Object? body}) => _request(
        'POST',
        path,
        body: body,
        contentType: 'application/json-patch+json',
      );

  /// PATCHes a JSON body, attaching the API version as a query parameter. Used
  /// to update pull requests (ADO accepts a plain-JSON PATCH for PR fields).
  @override
  Future<String> patch(String path, {Object? body}) =>
      _request('PATCH', path, body: body);

  /// PATCHes a JSON Patch document with ADO's `application/json-patch+json`
  /// content type, attaching the API version. Used for work-item updates.
  Future<String> patchPatch(String path, {Object? body}) => _request(
        'PATCH',
        path,
        body: body,
        contentType: 'application/json-patch+json',
      );
}
