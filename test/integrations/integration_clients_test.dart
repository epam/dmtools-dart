import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

/// Tests for the process-wide [IntegrationClients] singleton cache.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  setUp(() {
    IntegrationClients.resetForTests();
    PropertyReader.clearOverrides();
  });
  tearDown(() {
    IntegrationClients.resetForTests();
    PropertyReader.clearOverrides();
  });

  cachingBehaviorTests();
  failureAndResetTests();
}

/// The per-integration singletons: same instance, distinct across
/// integrations, built from the PropertyReader chain.
void cachingBehaviorTests() {
  group('IntegrationClients caching', () {
    test('returns the same client instance on every access', () {
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'https://jira.example.com',
        'JIRA_LOGIN_PASS_TOKEN': 'token',
      });

      expect(IntegrationClients.instance.jira(),
          same(IntegrationClients.instance.jira()));
    });

    test('keeps one instance per integration (jira vs testrail)', () {
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'https://jira.example.com',
        'JIRA_LOGIN_PASS_TOKEN': 'token',
        'TESTRAIL_BASE_PATH': 'https://tr.example.com',
        'TESTRAIL_USERNAME': 'dev@example.com',
        'TESTRAIL_API_KEY': 'key',
        'TESTRAIL_PROJECT': 'p1',
      });

      final jira = IntegrationClients.instance.jira();
      final testrail = IntegrationClients.instance.testrail();

      expect(jira, isA<JiraClient>());
      expect(testrail, isA<TestRailClient>());
      expect(jira, isNot(same(testrail)));
    });

    test('resetForTests drops the cached instances', () {
      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'https://jira.example.com',
        'JIRA_LOGIN_PASS_TOKEN': 'token',
      });
      final first = IntegrationClients.instance.jira();

      IntegrationClients.resetForTests();

      expect(IntegrationClients.instance.jira(), isNot(same(first)));
    });
  });
}

/// Missing configuration throws and is not cached as a failure.
void failureAndResetTests() {
  group('IntegrationClients unconfigured integrations', () {
    test('throws StateError while unconfigured', () {
      expect(
        () => IntegrationClients.instance.jira(),
        throwsStateError,
      );
    });

    test('does not cache the failure — access works after config appears', () {
      expect(
        () => IntegrationClients.instance.jira(),
        throwsStateError,
      );

      PropertyReader.setOverrides({
        'JIRA_BASE_PATH': 'https://jira.example.com',
        'JIRA_LOGIN_PASS_TOKEN': 'token',
      });

      expect(IntegrationClients.instance.jira(), isA<JiraClient>());
    });
  });
}
