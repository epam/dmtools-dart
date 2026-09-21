/// Unit + integration tests for [SyncRetryPolicy] and the retry wiring in
/// [SyncHttpClient] (gh-191, P6-JSY-18 — Java `RetryPolicy` parity).
library;

import 'dart:convert';
import 'dart:math';

import 'package:dmtools/src/js/sync_http_client.dart';
import 'package:dmtools/src/js/sync_retry_policy.dart';
import 'package:test/test.dart';

import 'echo_server_helper.dart';

void main() {
  policyConfigTests();
  policyOverrideAndUrlTests();
  policyStatusAndBudgetTests();
  delayMathTests();
  jitterDelayTests();
  retryIntegrationTests();
}

void policyConfigTests() {
  group('SyncRetryPolicy configuration', () {
    test('cloud policy matches RetryPolicyConfig.forJiraCloud', () {
      final policy = SyncRetryPolicy.forJiraCloud();
      expect(policy.maxAttempts, 7);
      expect(policy.baseDelayMs, 2000);
      expect(policy.maxDelayMs, 120000);
      expect(policy.backoffMultiplier, 2.0);
      expect(policy.jitterFactor, 0.4);
    });

    test('environment defaults match RetryPolicyConfig defaults', () {
      final policy = SyncRetryPolicy.fromEnvMap((_) => null);
      expect(policy.maxAttempts, 5);
      expect(policy.baseDelayMs, 1000);
      expect(policy.maxDelayMs, 60000);
      expect(policy.backoffMultiplier, 2.0);
      expect(policy.jitterFactor, 0.3);
      // Per-perform throttle defaults: off, 300ms when enabled (Java
      // BasicJiraClient defaults).
      expect(policy.waitBeforePerform, isFalse);
      expect(policy.sleepTimeRequestMs, 300);
      expect(policy.performDelayMs, 0);
    });

    test('JIRA_WAIT_BEFORE_PERFORM + SLEEP_TIME_REQUEST drive the throttle',
        () {
      final policy = SyncRetryPolicy.fromEnvMap((k) => switch (k) {
            'JIRA_WAIT_BEFORE_PERFORM' => 'true',
            'SLEEP_TIME_REQUEST' => '1500',
            _ => null,
          });
      expect(policy.waitBeforePerform, isTrue);
      expect(policy.sleepTimeRequestMs, 1500);
      expect(policy.performDelayMs, 1500);
      final disabled = SyncRetryPolicy.fromEnvMap((k) => switch (k) {
            'JIRA_WAIT_BEFORE_PERFORM' => 'true',
            _ => null,
          });
      expect(disabled.performDelayMs, 300); // SLEEP_TIME_REQUEST default
      final off = SyncRetryPolicy.fromEnvMap((k) => switch (k) {
            'JIRA_WAIT_BEFORE_PERFORM' => 'false',
            'SLEEP_TIME_REQUEST' => '1500',
            _ => null,
          });
      expect(off.performDelayMs, 0);
    });
  });
}

/// Env overrides and per-URL policy selection.
void policyOverrideAndUrlTests() {
  group('SyncRetryPolicy configuration', () {
    test('environment overrides are honored', () {
      final env = {
        'JIRA_RETRY_MAX_ATTEMPTS': '3',
        'JIRA_RETRY_BASE_DELAY_MS': '50',
        'JIRA_RETRY_MAX_DELAY_MS': '500',
        'JIRA_RETRY_BACKOFF_MULTIPLIER': '3.0',
        'JIRA_RETRY_JITTER_FACTOR': '0.1',
      };
      final policy = SyncRetryPolicy.fromEnvMap((k) => env[k]);
      expect(policy.maxAttempts, 3);
      expect(policy.baseDelayMs, 50);
      expect(policy.maxDelayMs, 500);
      expect(policy.backoffMultiplier, 3.0);
      expect(policy.jitterFactor, 0.1);
    });

    test('JIRA_RETRY_ENABLED=false disables retrying', () {
      final policy = SyncRetryPolicy.fromEnvMap(
          (k) => k == 'JIRA_RETRY_ENABLED' ? 'false' : null);
      expect(policy.maxAttempts, 0);
      expect(policy.shouldRetry(1, 429), isFalse);
    });

    test('forUrl picks the cloud policy for atlassian.net', () {
      final policy =
          SyncRetryPolicy.forUrl('https://x.atlassian.net/rest/api/2/issue');
      expect(policy.maxAttempts, 7);
    });

    test('forUrl picks the cloud policy for JIRA_CLOUD=true', () {
      final policy = SyncRetryPolicy.forUrl(
        'http://jira.local/rest/api/2/issue',
        get: (k) => k == 'JIRA_CLOUD' ? 'true' : null,
      );
      expect(policy.maxAttempts, 7);
    });

    test('forUrl keeps the default policy elsewhere', () {
      final policy = SyncRetryPolicy.forUrl('http://127.0.0.1:1/x');
      expect(policy.maxAttempts, 5);
    });
  });
}

/// Retryable statuses and the Java attempt budget.
void policyStatusAndBudgetTests() {
  group('SyncRetryPolicy configuration', () {
    test('retryable statuses are 429 and the 502/503/504 family', () {
      final policy = SyncRetryPolicy.fromEnvMap((_) => null);
      for (final status in [429, 502, 503, 504]) {
        expect(policy.isRetryableStatus(status), isTrue, reason: '$status');
      }
      for (final status in [200, 400, 401, 404, 500]) {
        expect(policy.isRetryableStatus(status), isFalse, reason: '$status');
      }
    });

    test('attempt budget matches Java (retry while attempt < maxRetries)', () {
      const policy = SyncRetryPolicy(
        maxAttempts: 5,
        baseDelayMs: 1000,
        maxDelayMs: 60000,
        backoffMultiplier: 2.0,
        jitterFactor: 0.0,
      );
      expect(policy.shouldRetry(1, 429), isTrue);
      expect(policy.shouldRetry(4, 429), isTrue);
      expect(policy.shouldRetry(5, 429), isFalse);
      expect(policy.shouldRetry(1, 404), isFalse);
      expect(policy.shouldRetry(1, 0), isTrue); // connection error
    });
  });
}

void delayMathTests() {
  group('SyncRetryPolicy delay math', () {
    const policy = SyncRetryPolicy(
      maxAttempts: 5,
      baseDelayMs: 1000,
      maxDelayMs: 6000,
      backoffMultiplier: 2.0,
      jitterFactor: 0.0,
    );

    test('exponential backoff doubles per attempt', () {
      expect(policy.statusDelayMs(1), 1000);
      expect(policy.statusDelayMs(2), 2000);
      expect(policy.statusDelayMs(3), 4000);
    });

    test('delay caps at maxDelayMs', () {
      expect(policy.statusDelayMs(4), 6000);
      expect(policy.statusDelayMs(8), 6000);
    });

    test('Retry-After header overrides the backoff', () {
      expect(policy.statusDelayMs(1, {'Retry-After': '2'}), 2000);
      expect(policy.statusDelayMs(3, {'retry-after': '1'}), 1000);
    });

    test('Retry-After above 300s aborts (null)', () {
      expect(policy.statusDelayMs(1, {'Retry-After': '301'}), isNull);
    });

    test('X-RateLimit-Reset computes the wait from now (+1s, capped)', () {
      final now = DateTime.now();
      final reset = ((now.millisecondsSinceEpoch + 4000) / 1000).round();
      final delay = policy.statusDelayMs(1, {'X-RateLimit-Reset': '$reset'});
      expect(delay, greaterThan(0));
      expect(delay, lessThanOrEqualTo(6000));
    });

    test('connection-error schedule doubles from 200ms and caps at 5s', () {
      expect(policy.connectionDelayMs(1), 200);
      expect(policy.connectionDelayMs(2), 400);
      expect(policy.connectionDelayMs(3), 800);
      expect(policy.connectionDelayMs(10), 5000);
    });
  });
}

/// Jitter stays within ±jitterFactor/2 (deterministic Random(42)).
void jitterDelayTests() {
  group('SyncRetryPolicy delay math', () {
    test('jitter stays within ±jitterFactor/2 of the delay', () {
      final jittered = SyncRetryPolicy(
        maxAttempts: 8,
        baseDelayMs: 10000,
        maxDelayMs: 60000,
        backoffMultiplier: 2.0,
        jitterFactor: 0.4,
        random: Random(42),
      );
      // Attempts 1-2 sit under the cap: 10000/20000 ±20%.
      for (var attempt = 1; attempt <= 2; attempt++) {
        final nominal = 10000 * (1 << (attempt - 1));
        final delay = jittered.statusDelayMs(attempt)!;
        expect(delay, greaterThanOrEqualTo(nominal * 0.8));
        expect(delay, lessThanOrEqualTo(nominal * 1.2));
      }
      // Attempt 5 is capped at 60000 and still jitters ±20% around the cap.
      final capped = jittered.statusDelayMs(5)!;
      expect(capped, greaterThanOrEqualTo(48000));
      expect(capped, lessThanOrEqualTo(72000));
    });
  });
}

void retryIntegrationTests() {
  group('SyncHttpClient retry wiring', () {
    late EchoServer server;

    setUpAll(() async {
      server = EchoServer();
      await server.start();
    });

    tearDownAll(() => server.stop());

    test('429 + Retry-After: 0 is retried and the echo answer is returned', () {
      final resp =
          SyncHttpClient.get('http://127.0.0.1:${server.port}/dt-retry/a');
      expect(resp.statusCode, 200);
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      expect(body['path'], '/dt-retry/a');
    });

    test('503 without retry headers is retried with backoff', () {
      final stopwatch = Stopwatch()..start();
      final resp =
          SyncHttpClient.get('http://127.0.0.1:${server.port}/dt-retryfail/b');
      stopwatch.stop();
      expect(resp.statusCode, 200);
      // First attempt pays the 1s base backoff before the retry.
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(900));
    });

    test('persistent 429 exhausts the attempt budget and surfaces 429', () {
      final resp = SyncHttpClient.get(
          'http://127.0.0.1:${server.port}/dt-retryalways/c');
      expect(resp.statusCode, 429);
      // Header names are case-insensitive: the bridge transport lowercases
      // them (dart:io), the curl transport preserves the server's casing.
      final retryAfter = resp.headers.entries
          .firstWhere((e) => e.key.toLowerCase() == 'retry-after')
          .value;
      expect(retryAfter, '0');
    });
  });
}
