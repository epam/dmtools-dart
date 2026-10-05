/// Rate-limit retry semantics for the dio GitHub client (gh-351).
///
/// Dart port of the Java `RetryPolicy.calculateDelayMs` rate-limit branches
/// (Java fix fab5b0ea, "honor GitHub X-RateLimit-Reset wait instead of
/// capping at 60s") onto the dio transport: on HTTP 429 the client reads
/// `Retry-After` / `X-RateLimit-Reset`, waits until reset (never capped at
/// `maxDelayMs`, never aborted), and retries within the attempt budget.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dmtools/dmtools.dart';
import 'package:dmtools/src/js/sync_retry_policy.dart';
import 'package:test/test.dart';

import 'github_test_support.dart';

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);
  xRateLimitResetWaitTests();
  retryAfterWaitTests();
  budgetAndPassThroughTests();
  wiringTests();
}

/// A stubbed transport plus the interceptor wired on top of it.
typedef _RateLimitFixture = ({
  Dio dio,
  GithubRateLimitRetryInterceptor interceptor,
  _StubAdapter adapter,
  List<Duration> sleeps,
});

/// Records every request and answers from [handler].
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;

  /// Requests served so far, in call order.
  final calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Builds a canned [ResponseBody] with [status], [body], and [headers].
ResponseBody _resp(
  int status,
  String body, [
  Map<String, List<String>> headers = const {},
]) =>
    ResponseBody.fromString(body, status, headers: headers);

/// Epoch-seconds `X-RateLimit-Reset` value [seconds] from now.
String _resetSecondsFromNow(int seconds) =>
    '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + seconds}';

/// Java default `RetryPolicy` tuning with jitter-neutral random, so delay
/// assertions are exact.
SyncRetryPolicy _policy({int maxAttempts = 5, int cap = 3600}) =>
    SyncRetryPolicy(
      maxAttempts: maxAttempts,
      baseDelayMs: 1000,
      maxDelayMs: 60000,
      backoffMultiplier: 2.0,
      jitterFactor: 0.3,
      rateLimitMaxWaitSeconds: cap,
    );

/// Builds a Dio over [_StubAdapter] with [GithubRateLimitRetryInterceptor]
/// on top; recorded waits land in `sleeps`.
_RateLimitFixture _fixture({
  required ResponseBody Function(RequestOptions options) handler,
  SyncRetryPolicy? policy,
  int maxAttempts = 5,
}) {
  final adapter = _StubAdapter(handler);
  final dio = Dio()..httpClientAdapter = adapter;
  final sleeps = <Duration>[];
  final interceptor = GithubRateLimitRetryInterceptor(
    dio: dio,
    policy: policy ?? _policy(maxAttempts: maxAttempts),
    maxAttempts: maxAttempts,
    sleep: (duration) async => sleeps.add(duration),
  );
  dio.interceptors.add(interceptor);
  return (dio: dio, interceptor: interceptor, adapter: adapter, sleeps: sleeps);
}

/// 429s once with [headers], then serves [body] with 200.
_RateLimitFixture _thenOk(Map<String, List<String>> headers,
    [String body = '{"ok":true}']) {
  var calls = 0;
  return _fixture(
    handler: (_) => ++calls == 1 ? _resp(429, '', headers) : _resp(200, body),
  );
}

/// X-RateLimit-Reset branch — Java fab5b0ea parity (gh-351).
void xRateLimitResetWaitTests() {
  group('GithubRateLimitRetryInterceptor X-RateLimit-Reset (Java fab5b0ea)',
      () {
    test('honors a long reset wait instead of capping at 60s', () async {
      final f = _thenOk({
        'x-ratelimit-reset': [_resetSecondsFromNow(600)]
      });

      final response = await f.dio.get<String>('https://api.github.com/user');

      expect(response.statusCode, 200);
      expect(response.data, '{"ok":true}');
      expect(f.adapter.calls, hasLength(2));
      final wait = f.sleeps.single;
      expect(
        wait.inMilliseconds,
        inInclusiveRange(595000, 602000),
        reason: 'wait should be ~600s + 1s buffer',
      );
      expect(
        wait.inSeconds > 60,
        isTrue,
        reason: 'the wait must never be capped at maxDelayMs (60s)',
      );
    });

    test('honors a reset only a few seconds out', () async {
      final f = _thenOk({
        'x-ratelimit-reset': [_resetSecondsFromNow(5)]
      });

      await f.dio.get<String>('https://api.github.com/user');

      expect(
        f.sleeps.single.inMilliseconds,
        inInclusiveRange(5000, 7000),
        reason: 'wait should be ~5s + 1s buffer',
      );
    });

    test('caps the wait at the default 3600s rate-limit cap, never aborts',
        () async {
      final f = _thenOk({
        'x-ratelimit-reset': [_resetSecondsFromNow(7200)]
      });

      final response = await f.dio.get<String>('https://api.github.com/user');

      expect(response.statusCode, 200);
      expect(f.sleeps.single, const Duration(seconds: 3600));
    });

    test('waits through repeated 429s until the API recovers', () async {
      var calls = 0;
      final f = _fixture(
        handler: (_) => ++calls <= 3
            ? _resp(429, '', {
                'x-ratelimit-reset': [_resetSecondsFromNow(30)]
              })
            : _resp(200, '{"ok":true}'),
      );

      final response = await f.dio.get<String>('https://api.github.com/user');

      expect(response.statusCode, 200);
      expect(f.adapter.calls, hasLength(4));
      expect(f.sleeps, hasLength(3));
      for (final wait in f.sleeps) {
        expect(
          wait.inMilliseconds,
          inInclusiveRange(29500, 32000),
        );
      }
    });
  });
}

/// Retry-After branch on a genuine 429 — Java fab5b0ea parity (gh-351).
void retryAfterWaitTests() {
  group('GithubRateLimitRetryInterceptor 429 Retry-After (Java fab5b0ea)', () {
    test('Retry-After of 600s is honored, not aborted', () async {
      final f = _thenOk({
        'retry-after': ['600']
      });

      await f.dio.get<String>('https://api.github.com/user');

      expect(
        f.sleeps.single.inMilliseconds,
        inInclusiveRange(570000, 630000),
        reason: 'wait should be ~600s with jitter',
      );
      expect(
        f.sleeps.single.inSeconds > 60,
        isTrue,
        reason: 'the wait must never be capped at maxDelayMs (60s)',
      );
    });

    test('Retry-After above the rate-limit cap is capped, not aborted',
        () async {
      final f = _thenOk({
        'retry-after': ['7200']
      });

      await f.dio.get<String>('https://api.github.com/user');

      expect(f.sleeps.single, const Duration(seconds: 3600));
    });

    test('Retry-After takes precedence over X-RateLimit-Reset', () async {
      final f = _thenOk({
        'retry-after': ['10'],
        'x-ratelimit-reset': [_resetSecondsFromNow(600)],
      });

      await f.dio.get<String>('https://api.github.com/user');

      expect(f.sleeps.single, const Duration(seconds: 10));
    });
  });
}

/// Attempt budget, error pass-through, and header-less fallback.
void budgetAndPassThroughTests() {
  group('GithubRateLimitRetryInterceptor budget & pass-through', () {
    test('persistent 429 exhausts the budget and surfaces the 429', () async {
      final f = _fixture(
        handler: (_) => _resp(429, '', {
          'retry-after': ['1']
        }),
      );

      await expectLater(
        f.dio.get<String>('https://api.github.com/user'),
        throwsA(
          isA<DioException>()
              .having((e) => e.response?.statusCode, 'status', 429),
        ),
      );
      expect(f.adapter.calls, hasLength(5), reason: 'budget = 5 attempts');
      expect(f.sleeps, hasLength(4));
    });

    test('non-429 errors pass through untouched', () async {
      final f = _fixture(handler: (_) => _resp(500, 'boom'));

      await expectLater(
        f.dio.get<String>('https://api.github.com/user'),
        throwsA(
          isA<DioException>()
              .having((e) => e.response?.statusCode, 'status', 500),
        ),
      );
      expect(f.adapter.calls, hasLength(1));
      expect(f.sleeps, isEmpty);
    });

    test('429 without rate-limit headers falls back to capped backoff',
        () async {
      var calls = 0;
      final f = _fixture(
        handler: (_) => ++calls == 1 ? _resp(429, '') : _resp(200, 'ok'),
      );

      final response = await f.dio.get<String>('https://api.github.com/user');

      expect(response.statusCode, 200);
      expect(f.sleeps.single, const Duration(seconds: 1),
          reason: 'header-less 429 falls back to the 1s base backoff delay');
    });
  });
}

/// Factory wiring: interceptor attached to every GithubHttpClient transport
/// and the RATE_LIMIT_MAX_WAIT_SECONDS cap resolved from PropertyReader.
void wiringTests() {
  group('GithubHttpClient rate-limit wiring (gh-351)', () {
    test('factory attaches the interceptor to injected transports too', () {
      final f = mockGithubHttp((_) => '{}');

      expect(
        f.http.dio.interceptors.whereType<GithubRateLimitRetryInterceptor>(),
        hasLength(1),
      );
    });

    test('RATE_LIMIT_MAX_WAIT_SECONDS override configures the cap', () {
      PropertyReader.setOverrides({
        'SOURCE_GITHUB_TOKEN': 't',
        'RATE_LIMIT_MAX_WAIT_SECONDS': '300',
      });

      final http = GithubHttpClient(PropertyReader(), dio: Dio());
      final interceptor = http.dio.interceptors
          .whereType<GithubRateLimitRetryInterceptor>()
          .single;

      expect(interceptor.policy.rateLimitMaxWaitSeconds, 300);
    });

    test('invalid RATE_LIMIT_MAX_WAIT_SECONDS falls back to 3600s', () {
      for (final value in ['abc', '0', '-10', '']) {
        PropertyReader.setOverrides({
          'SOURCE_GITHUB_TOKEN': 't',
          'RATE_LIMIT_MAX_WAIT_SECONDS': value,
        });

        final http = GithubHttpClient(PropertyReader(), dio: Dio());
        final interceptor = http.dio.interceptors
            .whereType<GithubRateLimitRetryInterceptor>()
            .single;

        expect(
          interceptor.policy.rateLimitMaxWaitSeconds,
          3600,
          reason: "value '$value' should resolve to the default cap",
        );
      }
    });

    test('end-to-end: 429 Retry-After then 200 via GithubHttpClient.get',
        () async {
      var calls = 0;
      final adapter = _StubAdapter(
        (_) => ++calls == 1
            ? _resp(429, '', {
                'retry-after': ['1']
              })
            : _resp(200, '{"login":"octo"}'),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      PropertyReader.setOverrides({'SOURCE_GITHUB_TOKEN': 't'});

      final http = GithubHttpClient(PropertyReader(), dio: dio);
      final body = await http.get('user');

      expect(body, '{"login":"octo"}');
      expect(adapter.calls, hasLength(2));
    });
  });
}
