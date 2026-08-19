/// L2 contract test framework — replays recorded Java tool invocations
/// against the Dart implementation over a mocked HTTP transport.
///
/// A **contract fixture** is a JSON file under `test/fixtures/contract/`
/// capturing one Java tool call:
///
/// ```json
/// {
///   "tool_name": "jira_get_ticket",
///   "request_args": {"ticket_id": "PROJ-1"},
///   "java_api_endpoint": "/rest/api/latest/issue/PROJ-1",
///   "java_http_method": "GET",
///   "expected_response": { "…the tool's parsed output…" },
///   "mock_response_body": "…optional raw API body the mock serves…"
/// }
/// ```
///
/// See `test/fixtures/contract/README.md` for the full format and how to
/// regenerate fixtures from real Java recordings.
///
/// The framework is integration-agnostic: each integration's contract test
/// supplies a [ContractReplay] closure that wires its own mock transport and
/// invokes the Dart client with the fixture's `request_args`. [runContractCases]
/// drives every matching fixture through that closure and asserts the Dart
/// output equals the fixture's `expected_response`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Replays one fixture against a Dart client, returning the tool's output.
typedef ContractReplay = Future<Object?> Function(ContractFixture fixture);

/// One recorded Java tool invocation, loaded from a contract fixture file.
class ContractFixture {
  /// Creates a fixture from its constituent parts.
  ContractFixture({
    required this.toolName,
    required this.requestArgs,
    required this.expectedResponse,
    required this.javaApiEndpoint,
    required this.javaHttpMethod,
    this.mockResponseBody,
  });

  /// Parses a fixture from its decoded JSON map.
  factory ContractFixture.fromJson(Map<String, dynamic> json) {
    final endpoint = _required(json, 'java_api_endpoint') as String;
    return ContractFixture(
      toolName: _required(json, 'tool_name') as String,
      requestArgs: _asArgs(_required(json, 'request_args')),
      expectedResponse: _required(json, 'expected_response'),
      javaApiEndpoint: endpoint,
      javaHttpMethod: _required(json, 'java_http_method') as String,
      mockResponseBody: json['mock_response_body'] as String?,
    );
  }

  /// Loads and parses the fixture at [path] (relative to CWD).
  factory ContractFixture.fromFile(String path) {
    final raw =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    return ContractFixture.fromJson(raw);
  }

  /// The MCP tool name, e.g. `jira_get_ticket`.
  final String toolName;

  /// Arguments the tool was invoked with (the `request_args` map).
  final Map<String, dynamic> requestArgs;

  /// The tool-level output the Dart port must reproduce.
  final Object expectedResponse;

  /// The upstream REST endpoint the Java tool called.
  final String javaApiEndpoint;

  /// The HTTP verb the Java tool used (`GET`, `POST`, …).
  final String javaHttpMethod;

  /// Optional raw API body the mock transport serves. When absent the mock
  /// serves a JSON encoding of [expectedResponse].
  final String? mockResponseBody;

  /// The body the mocked HTTP transport should return for this fixture.
  String get mockBody => mockResponseBody ?? jsonEncode(expectedResponse);

  /// The fixture's file basename, for readable test names.
  String label(String path) => '${_basenameNoExt(path)} ($toolName)';
}

/// A canned-response [HttpClientAdapter] that answers every request with a
/// fixed body and HTTP 200. Integrations use it to build mock clients.
class CannedBodyAdapter implements HttpClientAdapter {
  /// Creates an adapter that always returns [body].
  CannedBodyAdapter(this.body);

  /// The response body served for every request.
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: const {
        Headers.contentTypeHeader: ['application/json']
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Loads every `*.json` fixture in [dir] whose tool is in [tools] and runs
/// each through [replay], asserting the Dart output equals the expected.
///
/// Call this from an integration contract test's `main()`; it registers one
/// [test] per fixture. [dir] is relative to the project root (the CWD when
/// `dart test` runs), e.g. `'test/fixtures/contract'`.
void runContractCases(
  String dir,
  Set<String> tools,
  ContractReplay replay,
) {
  for (final path in _fixtureFiles(dir)) {
    final fixture = ContractFixture.fromFile(path);
    if (!tools.contains(fixture.toolName)) continue;
    test(fixture.label(path), () async {
      final actual = await replay(fixture);
      expect(actual, equals(fixture.expectedResponse));
    });
  }
}

/// Returns the sorted list of `*.json` files in [dir], or an empty list when
/// the directory does not yet exist (the framework can be dropped in before
/// any recordings are present).
List<String> _fixtureFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.path)
      .toList()
    ..sort();
}

/// Reads a required key from a fixture map, throwing a clear error if absent.
Object _required(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw FormatException('contract fixture missing required key "$key"');
  }
  return value;
}

/// Coerces the `request_args` value into a `Map<String, dynamic>`.
Map<String, dynamic> _asArgs(Object raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.cast<String, dynamic>();
  throw const FormatException('request_args must be a JSON object');
}

/// Returns the file's basename without its extension.
String _basenameNoExt(String path) {
  final base = path.split(Platform.pathSeparator).last;
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? base : base.substring(0, dot);
}
