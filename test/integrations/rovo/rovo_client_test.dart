import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this._handler);

  final ({int status, String body}) Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final res = _handler(options);
    return ResponseBody.fromString(
      res.body,
      res.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

RovoClient _makeClient(
  ({int status, String body}) Function(RequestOptions req) handler, {
  String mcpUrl = 'https://mcp.atlassian.com/v2/mcp',
  String token = 'base64-creds',
  String authType = 'Basic',
  String? defaultCloudId = 'default-cloud-123',
}) {
  final dio = Dio()..httpClientAdapter = _StatusAdapter(handler);
  final http = RovoHttpClient.custom(
    dio: dio,
    basePath: mcpUrl,
    token: token,
    authType: authType,
    defaultCloudId: defaultCloudId,
  );
  return RovoClient(http);
}

Map<String, dynamic> _decodeRpc(RequestOptions req) =>
    jsonDecode(req.data as String) as Map<String, dynamic>;

String _rpcSuccess(String text) => jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {
        'content': [
          {'type': 'text', 'text': text},
        ],
        'isError': false,
      },
    });

/// Coverage + behavior tests for [RovoClient], [RovoHttpClient],
/// [RovoToolExecutor], and [RovoSyncTools].
void main() {
  tearDown(() {
    PropertyReader.clearOverrides();
    IntegrationClients.resetForTests();
  });
  _httpClientTests();
  _searchAndSummarizeTests();
  _contextTests();
  _askTests();
  _jsonRpcUnwrapTests();
  _executorTests();
  _syncToolsTests();
  _syncToolsErrorTests();
}

void _httpClientTests() {
  group('RovoHttpClient', () {
    test('sends Basic authorization and Accept headers', () async {
      RequestOptions? captured;
      final client = _makeClient((req) {
        captured = req;
        return (status: 200, body: _rpcSuccess('ok'));
      });
      await client.rovoSearch(query: 'test');
      expect(captured, isNotNull);
      expect(captured!.headers['Authorization'], equals('Basic base64-creds'));
      expect(
        captured!.headers['Accept'],
        equals('application/json, text/event-stream'),
      );
      expect(
        captured!.uri.toString(),
        equals('https://mcp.atlassian.com/v2/mcp'),
      );
    });

    test('supports Bearer authorization and pre-prefixed tokens', () async {
      RequestOptions? captured;
      final client = _makeClient(
        (req) {
          captured = req;
          return (status: 200, body: _rpcSuccess('ok'));
        },
        token: 'svc-token',
        authType: 'Bearer',
      );
      await client.rovoSearch(query: 'test');
      expect(captured!.headers['Authorization'], equals('Bearer svc-token'));
    });

    test('PropertyReader factory builds client and throws when unconfigured',
        () {
      PropertyReader.clearOverrides();
      expect(
        () => RovoHttpClient(PropertyReader()),
        throwsA(isA<StateError>()),
      );
      PropertyReader.setOverrides({
        'ROVO_EMAIL': 'dev@example.com',
        'ROVO_API_TOKEN': 'secret',
        'ROVO_CLOUD_ID': 'cloud-xyz',
      });
      final http = RovoHttpClient(PropertyReader());
      expect(http.defaultCloudId, equals('cloud-xyz'));
      expect(http.buildUrl('sub'), equals('$rovoDefaultMcpUrl/sub'));
      final expectedBasic = base64Encode(utf8.encode('dev@example.com:secret'));
      expect(http.authHeaders['Authorization'], equals('Basic $expectedBasic'));
      expect(IntegrationClients.instance.rovo(), isA<RovoClient>());
    });
  });
}

void _searchAndSummarizeTests() {
  group('rovoSearch & rovoSummarize', () {
    test('rovoSearch sends STANDARD search JSON-RPC request', () async {
      late Map<String, dynamic> rpc;
      final client = _makeClient((req) {
        rpc = _decodeRpc(req);
        return (status: 200, body: _rpcSuccess('{"hits":[{"id":"1"}]}'));
      });
      final res = await client.rovoSearch(
        query: 'release checklist',
        cloudId: 'override-cloud',
        targetApp: 'confluence',
        limit: 5,
      );
      expect(res, equals('{"hits":[{"id":"1"}]}'));
      final params = rpc['params'] as Map<String, dynamic>;
      expect(params['name'], equals('search'));
      final args = params['arguments'] as Map<String, dynamic>;
      expect(args['query'], equals('release checklist'));
      expect(args['mode'], equals('STANDARD'));
      expect(args['cloudId'], equals('override-cloud'));
      expect(args['targetApp'], equals('confluence'));
      expect(args['limit'], equals(5));
    });

    test('rovoSummarize sends getConfluenceContent with detail=ai_summary',
        () async {
      late Map<String, dynamic> rpc;
      final client = _makeClient((req) {
        rpc = _decodeRpc(req);
        return (status: 200, body: _rpcSuccess('Page summary text'));
      });
      final res = await client.rovoSummarize(contentId: '98765');
      expect(res, equals('Page summary text'));
      final params = rpc['params'] as Map<String, dynamic>;
      expect(params['name'], equals('getConfluenceContent'));
      final args = params['arguments'] as Map<String, dynamic>;
      expect(args['contentId'], equals('98765'));
      expect(args['detail'], equals('ai_summary'));
      expect(args['cloudId'], equals('default-cloud-123'));
    });
  });
}

void _contextTests() {
  group('rovoContext', () {
    test('sends getGraphContext with objectType, identifier, cloudId',
        () async {
      late Map<String, dynamic> rpc;
      final client = _makeClient((req) {
        rpc = _decodeRpc(req);
        return (status: 200, body: _rpcSuccess('{"nodes":[]}'));
      });
      final res = await client.rovoContext(
        objectType: 'jira:issue',
        identifier: 'DMC-42',
      );
      expect(res, equals('{"nodes":[]}'));
      final params = rpc['params'] as Map<String, dynamic>;
      expect(params['name'], equals('getGraphContext'));
      final args = params['arguments'] as Map<String, dynamic>;
      expect(args['objectType'], equals('jira:issue'));
      expect(args['identifier'], equals('DMC-42'));
      expect(args['cloudId'], equals('default-cloud-123'));
    });
  });
}

void _askTests() {
  group('rovoAsk', () {
    test('returns AGENTIC answer when enabled', () async {
      final modes = <String>[];
      final client = _makeClient((req) {
        final rpc = _decodeRpc(req);
        final args =
            (rpc['params'] as Map<String, dynamic>)['arguments'] as Map;
        modes.add(args['mode'] as String);
        return (status: 200, body: _rpcSuccess('Cited answer [1]'));
      });
      final res = await client.rovoAsk(question: 'How does deployment work?');
      expect(res, equals('Cited answer [1]'));
      expect(modes, equals(['AGENTIC']));
    });

    test('falls back to STANDARD search on HTTP 403 or JSON-RPC 403', () async {
      final modes = <String>[];
      final client = _makeClient((req) {
        final rpc = _decodeRpc(req);
        final args =
            (rpc['params'] as Map<String, dynamic>)['arguments'] as Map;
        final mode = args['mode'] as String;
        modes.add(mode);
        if (mode == 'AGENTIC') {
          return (
            status: 403,
            body: '{"error":"Agentic search is not enabled"}',
          );
        }
        return (
          status: 200,
          body: _rpcSuccess('Fallback standard search hits')
        );
      });
      final res = await client.rovoAsk(question: 'How does deployment work?');
      expect(res, equals('Fallback standard search hits'));
      expect(modes, equals(['AGENTIC', 'STANDARD']));
    });
  });
}

void _jsonRpcUnwrapTests() {
  group('unwrapJsonRpcResponse & error handling', () {
    test('handles SSE data lines, plain text, error objects, and isError', () {
      const sse = 'event: message\n'
          'data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"SSE hello"}]}}\n\n';
      expect(RovoClient.unwrapJsonRpcResponse(sse), equals('SSE hello'));
      expect(
        RovoClient.unwrapJsonRpcResponse('plain text'),
        equals('plain text'),
      );
      expect(RovoClient.unwrapJsonRpcResponse('{invalid'), equals('{invalid'));
      expect(
        RovoClient.unwrapJsonRpcResponse('{"jsonrpc":"2.0","result":["a"]}'),
        equals('["a"]'),
      );
      expect(
        RovoClient.unwrapJsonRpcResponse(
          '{"jsonrpc":"2.0","result":{"content":[{"type":"image"},"raw"]}}',
        ),
        equals('{"type":"image"}\nraw'),
      );
      expect(
        () => RovoClient.unwrapJsonRpcResponse(
          '{"jsonrpc":"2.0","error":{"code":403,"message":"Forbidden"}}',
        ),
        throwsA(isA<RovoForbiddenException>()),
      );
      expect(
        () => RovoClient.unwrapJsonRpcResponse(
          '{"jsonrpc":"2.0","error":{"code":-32600,"message":"Bad req"}}',
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => RovoClient.unwrapJsonRpcResponse(
          '{"jsonrpc":"2.0","result":{"isError":true,"content":[{"type":"text","text":"fatal"}]}}',
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        const RovoForbiddenException('msg').toString(),
        contains('RovoForbiddenException: msg'),
      );
    });
  });
}

void _executorTests() {
  group('RovoToolExecutor & rovoTools', () {
    test('defines 4 tools and dispatches all 4 tools', () async {
      expect(rovoTools().map((d) => d.name), [
        'rovo_search',
        'rovo_summarize',
        'rovo_context',
        'rovo_ask',
      ]);
      final client = _makeClient((req) {
        final rpc = _decodeRpc(req);
        final params = rpc['params'] as Map<String, dynamic>;
        return (status: 200, body: _rpcSuccess('tool:${params['name']}'));
      });
      final exec = RovoToolExecutor(client);
      expect(
        await exec.execute('rovo_search', {'query': 'q', 'limit': '3'}),
        equals('tool:search'),
      );
      expect(
        await exec.execute('rovo_search', {'query': 'q', 'limit': 2}),
        equals('tool:search'),
      );
      expect(
        await exec.execute('rovo_summarize', {'contentId': '10'}),
        equals('tool:getConfluenceContent'),
      );
      expect(
        await exec.execute(
          'rovo_context',
          {'objectType': 'jira:issue', 'identifier': 'KEY-1'},
        ),
        equals('tool:getGraphContext'),
      );
      expect(
        await exec.execute('rovo_ask', {'question': 'why?'}),
        equals('tool:search'),
      );
      expect(
        () => exec.execute('rovo_unknown', {}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

void _syncToolsTests() {
  group('RovoSyncTools dispatch', () {
    test('dispatches all 4 tools and falls back on 403', () {
      PropertyReader.setOverrides({
        'ROVO_LOGIN_PASS_TOKEN': 'tok',
        'ROVO_CLOUD_ID': 'cid-1',
      });
      final modes = <String>[];
      final sync = RovoSyncTools(
        PropertyReader(),
        post: (url, {headers, body}) {
          final rpc = jsonDecode(body!) as Map<String, dynamic>;
          final params = rpc['params'] as Map<String, dynamic>;
          final args = params['arguments'] as Map<String, dynamic>;
          final mode = args['mode'] as String?;
          if (mode != null) modes.add(mode);
          if (mode == 'AGENTIC') {
            return SyncHttpResponse(
              403,
              'Agentic search is not enabled for this user or site',
            );
          }
          return SyncHttpResponse(200, _rpcSuccess('sync:${params['name']}'));
        },
      );
      expect(
        sync.dispatch(
          'rovo_search',
          {'query': 'hello', 'targetApp': 'jira', 'limit': 5},
        ),
        equals('sync:search'),
      );
      expect(
        sync.dispatch('rovo_summarize', {'contentId': '123'}),
        equals('sync:getConfluenceContent'),
      );
      expect(
        sync.dispatch(
          'rovo_context',
          {'objectType': 'jira:issue', 'identifier': 'KEY-1'},
        ),
        equals('sync:getGraphContext'),
      );
      expect(
        sync.dispatch('rovo_ask', {'question': 'how?'}),
        equals('sync:search'),
      );
      expect(modes, equals(['STANDARD', 'AGENTIC', 'STANDARD']));
    });
  });
}

void _syncToolsErrorTests() {
  group('RovoSyncTools error handling', () {
    test('returns JSON errors for unconfigured, unknown, or HTTP errors', () {
      PropertyReader.clearOverrides();
      final unconfigured = RovoSyncTools(PropertyReader());
      expect(
        unconfigured.dispatch('rovo_search', {'query': 'q'}),
        contains('Rovo not configured'),
      );
      expect(
        unconfigured.dispatch('rovo_unknown', {}),
        contains('Unsupported Rovo tool'),
      );
      PropertyReader.setOverrides({'ROVO_LOGIN_PASS_TOKEN': 'tok'});
      var statusOverride = 0;
      final sync = RovoSyncTools(
        PropertyReader(),
        post: (url, {headers, body}) =>
            SyncHttpResponse(statusOverride, 'fail'),
      );
      expect(
        sync.dispatch('rovo_search', {'query': 'hello'}),
        contains('HTTP request failed'),
      );
      statusOverride = 500;
      expect(
        sync.dispatch('rovo_search', {'query': 'hello'}),
        contains('HTTP 500'),
      );
    });
  });
}
