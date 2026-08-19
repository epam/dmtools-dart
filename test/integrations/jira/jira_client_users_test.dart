import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'jira_test_support.dart';

/// User-lookup tests: getAccountByEmail, getUserProfile, getMyProfile
/// — plus executor dispatch.
void main() {
  tearDown(PropertyReader.clearOverrides);
  getAccountByEmailTests();
  getUserProfileTests();
  getMyProfileTests();
  usersExecutorDispatchTests();
}

/// `jira_get_account_by_email` — GET `user/search?username=`.
void getAccountByEmailTests() {
  group('JiraClient.getAccountByEmail', () {
    test('returns the first matching user', () async {
      final f =
          mockJira((o) => routeByPath({'/user/search': _usersListBody}, o));
      final result = await f.client.getAccountByEmail('dev@example.com');
      expect(result['accountId'], '5b10a2844c20165700ede21g');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.queryParameters['username'],
          'dev@example.com');
    });

    test('returns an empty map when no users match', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getAccountByEmail('nobody@example.com'), isEmpty);
    });
  });
}

/// `jira_get_user_profile` — GET `user?accountId=`.
void getUserProfileTests() {
  group('JiraClient.getUserProfile', () {
    test('GETs user by accountId', () async {
      final f = mockJira((o) => routeByPath({'/user': _userBody}, o));
      final result = await f.client.getUserProfile('abc-123');
      expect(result['accountId'], 'abc-123');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.queryParameters['accountId'], 'abc-123');
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getUserProfile('abc-123'), isEmpty);
    });
  });
}

/// `jira_get_my_profile` — GET `myself`.
void getMyProfileTests() {
  group('JiraClient.getMyProfile', () {
    test('GETs the myself endpoint', () async {
      final f = mockJira((o) => routeByPath({'/myself': _userBody}, o));
      final result = await f.client.getMyProfile();
      expect(result['accountId'], 'abc-123');
      expect(f.adapter.calls.single.method, 'GET');
      expect(f.adapter.calls.single.path, endsWith('/myself'));
    });

    test('returns an empty map when the body is not an object', () async {
      final f = mockJira((o) => '[]');
      expect(await f.client.getMyProfile(), isEmpty);
    });
  });
}

/// [JiraToolExecutor.execute] routes user-lookup tool names.
void usersExecutorDispatchTests() {
  group('JiraToolExecutor.execute (users)', () {
    test('routes jira_get_account_by_email', () async {
      final f =
          mockJira((o) => routeByPath({'/user/search': _usersListBody}, o));
      await executor(f)
          .execute('jira_get_account_by_email', {'email': 'dev@example.com'});
      expect(f.adapter.calls.single.queryParameters['username'],
          'dev@example.com');
    });

    test('routes jira_get_user_profile', () async {
      final f = mockJira((o) => routeByPath({'/user': _userBody}, o));
      await executor(f).execute('jira_get_user_profile', {'userId': 'abc-123'});
      expect(f.adapter.calls.single.queryParameters['accountId'], 'abc-123');
    });

    test('routes jira_get_my_profile', () async {
      final f = mockJira((o) => routeByPath({'/myself': _userBody}, o));
      await executor(f).execute('jira_get_my_profile', {});
      expect(f.adapter.calls.single.path, endsWith('/myself'));
    });
  });
}

/// Builds an executor from a mock Jira fixture.
JiraToolExecutor executor(MockJiraFixture f) => JiraToolExecutor(f.client);

/// Canned `user/search` body with one user.
const _usersListBody =
    '[{"accountId":"5b10a2844c20165700ede21g","emailAddress":"dev@example.com"}]';

/// Canned `user` / `myself` body.
const _userBody =
    '{"accountId":"abc-123","displayName":"Dev User","emailAddress":"dev@example.com"}';
