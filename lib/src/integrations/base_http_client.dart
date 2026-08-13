/// Shared HTTP client base for all REST API integrations.
///
/// Provides common get/post/put/delete methods via dio, with each
/// integration overriding [buildUrl] and [authHeaders].
library;

import 'package:dio/dio.dart';

/// Base class for integration HTTP clients.
abstract class BaseHttpClient {
  /// The underlying dio transport.
  final Dio dio;

  /// The configured base URL for this integration.
  final String basePath;

  /// Creates a client with the given [dio] and [basePath].
  const BaseHttpClient({required this.dio, required this.basePath});

  /// Override to provide integration-specific auth headers.
  Map<String, String> get authHeaders => const {};

  /// Returns all headers (auth + content type).
  Map<String, String> get headers => {
        ...authHeaders,
        'Content-Type': 'application/json',
      };

  /// Builds the full URL for a relative path. Override per integration.
  String buildUrl(String path);

  /// Performs a GET request.
  Future<String> get(String path, {Map<String, dynamic>? queryParams}) async {
    final response = await dio.get<String>(
      buildUrl(path),
      queryParameters: queryParams,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Performs a POST request.
  Future<String> post(String path, {Object? body}) async {
    final response = await dio.post<String>(
      buildUrl(path),
      data: body,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Performs a PUT request.
  Future<String> put(String path, {Object? body}) async {
    final response = await dio.put<String>(
      buildUrl(path),
      data: body,
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Performs a DELETE request.
  Future<String> delete(String path) async {
    final response = await dio.delete<String>(
      buildUrl(path),
      options: Options(headers: headers),
    );
    return response.data ?? '';
  }

  /// Closes the underlying HTTP client.
  void close() => dio.close();

  /// Creates a [Dio] with the standard 60-second timeouts.
  static Dio createDefaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
}
