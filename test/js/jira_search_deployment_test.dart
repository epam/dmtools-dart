import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'echo_server_helper.dart';

/// Jira search deployment detection: `serverInfo`-driven Cloud vs Server
/// routing and the pagination contract of each surface.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  if (hasPython3()) {
    _testServerSearch();
    _testServerUrlFallbacks();
    _testServerPagination();
    _testServerPaginationRefresh();
    _testCloudSearch();
    _testCloudPaginationStops();
    _testCloudErrors();
  }
}

/// Builds a dispatcher bound to [basePath] on [server].
SyncToolDispatcher _dispatcherFor(EchoServer server, String basePath) {
  PropertyReader.setOverrides({
    'JIRA_BASE_PATH': basePath,
    'JIRA_LOGIN_PASS_TOKEN': 'dGVzdDp0b2tlbg==',
    'JIRA_AUTH_TYPE': 'Basic',
  });
  return SyncToolDispatcher(PropertyReader());
}

/// Server-deployment search: detection via serverInfo / URL fallback and
/// the legacy startAt pagination walk.
void _testServerSearch() {
  group('Jira search deployment (server)', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('Server deployment pages the legacy search by startAt', () {
      final d =
          _dispatcherFor(server, 'http://127.0.0.1:${server.port}/dt-server');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['S-0a', 'S-0b', 'S-2']);
    });

    test('detection is memoized across calls for the same base path', () {
      final d =
          _dispatcherFor(server, 'http://127.0.0.1:${server.port}/dt-server');
      d.execute('jira_search_by_jql', {'jql': 'project = PROJ'});
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['S-0a', 'S-0b', 'S-2']);
    });

    test('server errorMessages surface as a JSON error', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-servererr');
      expect(
        jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!),
        {'error': 'Search failed: ["bad jql"]'},
      );
    });

    test('total == 0 returns an empty result before the walk', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-servertotal0');
      expect(
        jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!),
        isEmpty,
      );
    });
    // Pagination-walk cases live in _testServerPagination.
  });
}

/// Server-deployment URL-pattern fallback cases.
void _testServerUrlFallbacks() {
  group('Jira search deployment (server URL fallbacks)', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('missing deploymentType falls back to the URL pattern', () {
      final d =
          _dispatcherFor(server, 'http://127.0.0.1:${server.port}/dt-missing');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['S-0a', 'S-0b', 'S-2']);
    });

    test('serverInfo failure falls back to the URL pattern', () {
      final d =
          _dispatcherFor(server, 'http://127.0.0.1:${server.port}/dt-error');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['S-0a', 'S-0b', 'S-2']);
    });
  });
}

/// Server-deployment pagination walk cases.
void _testServerPagination() {
  group('Jira search deployment (server pagination)', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    // Walk-refresh cases live in _testServerPaginationRefresh.

    test('total < maxResults stops after the first page', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-serveronepage');
      final issues =
          jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!)
              as List;
      expect(issues.map((i) => i['key']), ['O-0']);
    });

    test('a failed follow-up page surfaces as a JSON error', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-serverperr');
      final decoded =
          jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['error'] as String, contains('500'));
    });

    test('a JSON-null follow-up page ends the walk', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-serverpnull');
      final issues =
          jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!)
              as List;
      expect(issues.map((i) => i['key']), ['SN-0']);
    });
  });
}

/// Server-deployment walk-refresh cases (startAt==total, per-page
/// maxResults/total refresh).
void _testServerPaginationRefresh() {
  group('Jira search deployment (server pagination refresh)', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('startAt == total is not a break — one more page is fetched', () {
      // Java breaks on `startAt > total`, not `>=`: the page at
      // startAt == total is still fetched (E-4) before the walk ends.
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-serverexact');
      final issues =
          jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!)
              as List;
      expect(issues.map((i) => i['key']), ['E-0', 'E-2', 'E-4']);
    });

    test('maxResults/total refresh per page (page2 shrinks maxResults)', () {
      // Page 1: 4 issues, maxResults 4, total 9; page 2: 4 issues,
      // maxResults 2. Advancing by the refreshed maxResults walks startAt
      // 6 then 8, so R-6 and R-8 are included — a stale maxResults would
      // jump straight to startAt 8 and skip R-6.
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-serverrefresh');
      final issues =
          jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!)
              as List;
      expect(
        issues.map((i) => i['key']),
        [
          'R-0a', 'R-0b', 'R-0c', 'R-0d', //
          'R-4a', 'R-4b', 'R-4c', 'R-4d', //
          'R-6', 'R-8',
        ],
      );
    });
  });
}

/// Cloud-deployment search: detection via Cloud deploymentType / the
/// atlassian.net URL fallback and the nextPageToken pagination walk.
void _testCloudSearch() {
  group('Jira search deployment (cloud)', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('Cloud deployment pages search/jql by nextPageToken', () {
      final d =
          _dispatcherFor(server, 'http://127.0.0.1:${server.port}/dt-cloud');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['C-1', 'C-2']);
    });

    test('atlassian.net URL fallback selects the cloud endpoint', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-error/atlassian.net');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['C-1', 'C-2']);
    });

    test('a 404 HTML body surfaces as a JSON error', () {
      final d =
          _dispatcherFor(server, 'http://127.0.0.1:${server.port}/dt-html');
      final result = d.execute('jira_search_by_jql', {'jql': 'project = P'});
      final decoded = jsonDecode(result!); // must parse — never raw HTML
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['error'] as String, contains('404'));
    });

    // Error-contract cases live in _testCloudErrors.
  });
}

/// Cloud-deployment pagination stop-condition cases.
void _testCloudPaginationStops() {
  group('Jira search deployment (cloud pagination stops)', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('an empty issues page stops pagination before the next token', () {
      // The tok2 page is empty but still carries tok3: only the empty
      // issues check may stop here, never the token.
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-cloudempty');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['CE-1']);
    });

    test('a page without an issues field stops pagination', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-cloudnoissues');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['CI-1']);
    });

    test('isLast stops pagination before the next token', () {
      // Page 1 is marked isLast while still carrying tok2: the walk must
      // stop at isLast and never fetch CL-2.
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-cloudlast');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['CL-1']);
    });
  });
}

/// Cloud-deployment error-contract cases.
void _testCloudErrors() {
  group('Jira search deployment (cloud errors)', () {
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() {
      PropertyReader.clearOverrides();
      server.stop();
    });

    test('first-page errorMessages surface as a JSON error', () {
      final d =
          _dispatcherFor(server, 'http://127.0.0.1:${server.port}/dt-clouderr');
      expect(
        jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!),
        {'error': 'Search failed: ["boom cloud"]'},
      );
    });

    test('a JSON-null first page surfaces as a JSON error', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-cloudnull');
      expect(
        jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!),
        {'error': 'Search returned null results'},
      );
    });

    test('a JSON-null follow-up page ends the walk', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-cloudpnull');
      final issues = jsonDecode(
          d.execute('jira_search_by_jql', {'jql': 'project = PROJ'})!) as List;
      expect(issues.map((i) => i['key']), ['CN-1']);
    });

    test('a failed follow-up page surfaces as a pagination error', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-cloudfail');
      final decoded =
          jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['error'] as String, contains('Pagination failed'));
    });

    test('a 404 HTML first page surfaces as a JSON error', () {
      final d = _dispatcherFor(
          server, 'http://127.0.0.1:${server.port}/dt-cloudhtml');
      final decoded =
          jsonDecode(d.execute('jira_search_by_jql', {'jql': 'project = P'})!);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['error'] as String, contains('404'));
    });
  });
}
