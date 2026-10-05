import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dmtools/src/config/property_reader.dart';
import 'package:dmtools/src/js/sync_http_client.dart';
import 'package:dmtools/src/js/sync_tools/confluence_sync_tools.dart';
import 'package:test/test.dart';

import '../echo_server_helper.dart';

/// gh-348 — ports of the Java `ConfluenceAttachmentRetryTest` (dm.ai
/// 8cbf550d), the `ConfluenceParallel.parallelism()` bounds
/// (`ConfluenceParallelTest`, dm.ai d61a4abd), and end-to-end checks of
/// the parallel pool against the echo server.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  _transientFailureClassification();
  _attachmentRetrySchedule();
  _parallelismBounds();
  if (hasPython3()) {
    _poolBackedDownloads();
    _failingAttachmentCleanup();
  }
}

/// Java `ConfluenceAttachmentRetryTest.rateLimitServerErrorsAndNetwork-
/// FailuresAreRetried` / `clientErrorsAreNotRetried` — over the sync
/// transport's status codes (`0` = network failure).
void _transientFailureClassification() {
  group('isConfluenceTransientAttachmentFailure', () {
    test('rate limits, server errors, and network failures are retried', () {
      for (final code in [429, 503, 500, 408, 0]) {
        expect(isConfluenceTransientAttachmentFailure(code), isTrue,
            reason: 'status $code');
      }
    });

    test('client errors are not retried', () {
      for (final code in [400, 401, 403, 404, 409, 422]) {
        expect(isConfluenceTransientAttachmentFailure(code), isFalse,
            reason: 'status $code');
      }
    });
  });
}

/// The retry loop itself: transient failures back off and retry (4
/// attempts), client errors fail fast, and an eventual success wins.
void _attachmentRetrySchedule() {
  group('fetchConfluenceAttachmentWithRetry', () {
    test('retries transient failures with doubling backoff, then succeeds', () {
      final sleeps = <int>[];
      final resp = fetchConfluenceAttachmentWithRetry(
        'http://x/att',
        const {'Authorization': 'Basic t'},
        fetch: scriptedResponses([
          SyncHttpResponse(503, 'gw'),
          SyncHttpResponse(429, 'rate'),
          SyncHttpResponse(200, 'ok', const {}, [1, 2, 3]),
        ]),
        sleepDelay: sleeps.add,
        baseDelayMs: 100,
        random: _zeroJitter(),
      );
      expect(resp.isOk, isTrue);
      expect(resp.bodyBytes, [1, 2, 3]);
      // Java 8cbf550d schedule: base * 2^(attempt-1) + jitter(base/2).
      expect(sleeps, [100, 200]);
    });

    _retryGiveUpAndFailFastTests();
  });
}

void _retryGiveUpAndFailFastTests() {
  test('gives up after the fourth attempt on persistent failures', () {
    final sleeps = <int>[];
    final resp = fetchConfluenceAttachmentWithRetry(
      'http://x/att',
      const {},
      fetch: scriptedResponses(
          [SyncHttpResponse(0, 'unexpected end of stream')]),
      sleepDelay: sleeps.add,
      baseDelayMs: 10,
      random: _zeroJitter(),
    );
    expect(resp.statusCode, 0);
    // 4 attempts → 3 backoff waits: 10ms, 20ms, 40ms.
    expect(sleeps, [10, 20, 40]);
  });

  test('client errors fail without a retry', () {
    final sleeps = <int>[];
    final resp = fetchConfluenceAttachmentWithRetry(
      'http://x/att',
      const {},
      fetch: scriptedResponses([SyncHttpResponse(404, 'gone')]),
      sleepDelay: sleeps.add,
      baseDelayMs: 10,
      random: _zeroJitter(),
    );
    expect(resp.statusCode, 404);
    expect(sleeps, isEmpty);
  });

  test('network failure then success is retried', () {
    final resp = fetchConfluenceAttachmentWithRetry(
      'http://x/att',
      const {},
      fetch: scriptedResponses([
        SyncHttpResponse(0, 'connection reset'),
        SyncHttpResponse(200, 'ok'),
      ]),
      sleepDelay: (_) {},
      baseDelayMs: 1,
      random: _zeroJitter(),
    );
    expect(resp.isOk, isTrue);
  });
}

/// A fetch stub replaying [responses] in order (wrapping when exhausted).
SyncHttpResponse Function(String, Map<String, String>) scriptedResponses(
  List<SyncHttpResponse> responses,
) {
  var call = 0;
  return (url, headers) => responses[call++ % responses.length];
}

/// Java `ConfluenceParallelTest.parallelismReadsPropertyWithBounds`:
/// default 4, clamped to [1, 16], unparsable → default.
void _parallelismBounds() {
  group('confluenceSyncParallelism', () {
    tearDown(() => PropertyReader.clearOverrides());

    int withOverride(String? value) {
      if (value == null) {
        PropertyReader.setOverrides(const {'CONFLUENCE_PARALLELISM': ''});
      } else {
        PropertyReader.setOverrides({'CONFLUENCE_PARALLELISM': value});
      }
      return confluenceSyncParallelism(PropertyReader());
    }

    test('reads the configured value', () => expect(withOverride('7'), 7));
    test('defaults to 4 when unset or unparsable', () {
      expect(withOverride(null), 4);
      expect(withOverride('abc'), 4);
      expect(withOverride('  '), 4);
    });
    test('clamps to the Java bounds [1, 16]', () {
      expect(withOverride('0'), 1);
      expect(withOverride('-3'), 1);
      expect(withOverride('500'), 16);
    });
  });
}

Map<String, String> _config(int port) => {
      'CONFLUENCE_BASE_PATH': 'http://127.0.0.1:$port',
      'CONFLUENCE_LOGIN_PASS_TOKEN': 'conf-token',
      'CONFLUENCE_AUTH_TYPE': 'Basic',
      'CONFLUENCE_DEFAULT_SPACE': 'ENG',
    };

/// End-to-end over the booted pool: downloads and URL resolution behave
/// exactly like the inline (unbooted) path — attachments land on disk,
/// credentials never leak to foreign hosts, results keep input order.
void _poolBackedDownloads() {
  group('ConfluenceSyncTools over the booted parallel pool', () {
    late EchoServer server;
    late ConfluenceSyncTools tools;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides(_config(server.port));
      tools = ConfluenceSyncTools(PropertyReader());
      await confluenceSyncWorkerPool.boot();
    });

    tearDown(() {
      confluenceSyncWorkerPool.dispose();
      PropertyReader.clearOverrides();
      server.stop();
    });

    _poolDownloadPagesTest();
    _poolContentsByUrlsTest();
  });
}

void _poolDownloadPagesTest() {
  test('download_pages mirrors pages and attachments through the pool', () {
    {
      final out = Directory.systemTemp.createTempSync('dmtools_dlp_');
      addTearDown(() => out.deleteSync(recursive: true));
      final base = 'http://127.0.0.1:${server.port}';
      final result = tools.dispatch('confluence_download_pages', {
        'urlStrings': ['$base/wiki/spaces/ENG/pages/777/Hi'],
        'outputPath': out.path,
        'depth': 1,
      });
      expect(result, 'Downloaded 1 Confluence page(s) to ${out.path}');
      expect(File('${out.path}/Hi Page.md').readAsStringSync(), 'hi');
      // The worker-side attachment fetch honors the foreign-host rule:
      // evil.txt points at `localhost` (vs the configured 127.0.0.1), so
      // the Confluence credentials must stay home.
      expect(
        File('${out.path}/Hi Page-attachments/shot.png').readAsBytesSync(),
        utf8.encode('PNG-fixture-bytes'),
      );
      expect(
        File('${out.path}/Hi Page-attachments/evil.txt').readAsStringSync(),
        'CLEAN',
      );
    });

    test('contents_by_urls resolves concurrently and keeps input order', () {
      final base = 'http://127.0.0.1:${server.port}';
      final results = jsonDecode(
        tools.dispatch('confluence_contents_by_urls', {
          'urlStrings': [
            '$base/l/dead',
            '$base/wiki/spaces/ENG/pages/777/Hi',
            '$base/definitely-not-a-page-url',
          ],
        }),
      ) as List;
      // The dead short link and the unknown URL degrade to skips (null
      // jobs); the healthy page still resolves in its input position.
      expect(results, hasLength(1));
      expect(results.single['id'], '777');
    });
  });
}

/// gh-348 (dm.ai 8cbf550d): an attachment whose endpoint keeps failing
/// with a transient-class status is retried per the schedule and never
/// leaves a partial file on disk — inline and over the pool.
void _failingAttachmentCleanup() {
  group('download_pages drops failed attachments without partial files', () {
    late EchoServer server;
    late ConfluenceSyncTools tools;

    setUp(() async {
      server = EchoServer();
      await server.start();
      PropertyReader.setOverrides({
        ..._config(server.port),
        // Short backoff so the four-attempt schedule stays fast.
        'CONFLUENCE_ATTACHMENT_RETRY_BASE_DELAY_MS': '5',
      });
      tools = ConfluenceSyncTools(PropertyReader());
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('inline (unbooted pool)', () {
      _expectFlakyPageOnly(tools, server.port);
    });

    test('over the booted parallel pool', () async {
      await confluenceSyncWorkerPool.boot();
      addTearDown(() {
        confluenceSyncWorkerPool.dispose();
        PropertyReader.clearOverrides();
      });
      _expectFlakyPageOnly(tools, server.port);
    });
  });
}

/// Page 666's only attachment answers 500 forever: the page markdown is
/// written, the attachment file is not (and no partial file survives).
void _expectFlakyPageOnly(ConfluenceSyncTools tools, int port) {
  final out = Directory.systemTemp.createTempSync('dmtools_dlf_');
  addTearDown(() => out.deleteSync(recursive: true));
  final base = 'http://127.0.0.1:$port';
  final result = tools.dispatch('confluence_download_pages', {
    'urlStrings': ['$base/wiki/spaces/ENG/pages/666/Flaky'],
    'outputPath': out.path,
    'depth': 1,
  });
  expect(result, 'Downloaded 1 Confluence page(s) to ${out.path}');
  expect(File('${out.path}/Flaky Page.md').readAsStringSync(), 'flaky');
  expect(
    File('${out.path}/Flaky Page-attachments/flaky.png').existsSync(),
    isFalse,
  );
}

/// A [Random] whose jitter is always zero (deterministic backoff math).
Random _zeroJitter() => _ZeroJitterRandom();

class _ZeroJitterRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => 0;
}
