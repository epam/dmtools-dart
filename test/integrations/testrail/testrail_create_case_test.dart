import 'dart:convert';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

import 'testrail_test_support.dart';

/// Coverage + behavior tests for the section-aware case-creation tools,
/// porting the Java PR "testrail-sections-and-section-aware-case-creation".
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });
  tearDown(PropertyReader.clearOverrides);
  createCaseTests();
  createCaseFieldsTests();
  createCaseSectionFallbackTests();
  createCaseDetailedTests();
  createCaseStepsTests();
  createCaseStepsErrorTests();
}

/// Canned `get_projects` page used for name→ID resolution.
const _projectsBody =
    '{"offset":0,"limit":250,"size":1,"projects":[{"id":5,"name":"My Project"}],'
    '"_links":{"next":null,"prev":null}}';

/// Canned single-page `get_sections` response.
const _sectionsPageBody =
    '{"offset":0,"limit":250,"size":2,"sections":[{"id":10,"name":"Core"},'
    '{"id":11,"name":"Extra"}],"_links":{"next":null,"prev":null}}';

/// Canned `add_case` response body.
const _newCaseBody = '{"id":42,"title":"New case"}';

/// `testrail_create_case` — POST `add_case/{sectionId}`.
void createCaseTests() {
  group('TestRailClient.createCase', () {
    test('POSTs to the explicit section without listing sections', () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'add_case/42': _newCaseBody,
        }, o),
      );
      final result = await f.client.createCase(
        'My Project',
        'New case',
        sectionId: '42',
      );
      expect(result['id'], 42);
      expect(
        f.adapter.calls.every((c) => !c.path.contains('get_sections')),
        isTrue,
      );
      final post = f.adapter.calls.last;
      expect(post.method, 'POST');
      expect(post.path, contains('add_case/42'));
    });

    test('falls back to the first section when section_id is omitted',
        () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'get_sections/5': _sectionsPageBody,
          'add_case/10': _newCaseBody,
        }, o),
      );
      await f.client.createCase('My Project', 'New case');
      expect(f.adapter.calls.last.path, contains('add_case/10'));
    });
  });
}

/// `testrail_create_case` field shaping.
void createCaseFieldsTests() {
  group('TestRailClient.createCase (fields)', () {
    test('shapes description, priority, and refs', () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'add_case/42': _newCaseBody,
        }, o),
      );
      await f.client.createCase(
        'My Project',
        'New case',
        description: '1. Do a thing',
        priorityId: '3',
        refs: 'PROJ-123',
      );
      final body = jsonDecode(f.adapter.calls.last.data as String);
      expect(body, {
        'title': 'New case',
        'custom_preconds': '1. Do a thing',
        'priority_id': 3,
        'refs': 'PROJ-123',
      });
    });

    test('defaults the priority to 2 when invalid', () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'add_case/42': _newCaseBody,
        }, o),
      );
      await f.client.createCase(
        'My Project',
        'New case',
        priorityId: 'high',
      );
      final body = jsonDecode(f.adapter.calls.last.data as String);
      expect(body['priority_id'], 2);
    });
  });
}

/// `testrail_create_case` default-section fallbacks.
void createCaseSectionFallbackTests() {
  group('TestRailClient.createCase (section fallback)', () {
    test('falls back to the default section for an invalid section_id',
        () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'get_sections/5': _sectionsPageBody,
          'add_case/10': _newCaseBody,
        }, o),
      );
      await f.client.createCase('My Project', 'New case', sectionId: 'abc');
      expect(f.adapter.calls.last.path, contains('add_case/10'));
    });

    test('creates a Test Cases section when the project has none', () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'get_sections/5': '{"sections":[]}',
          'add_section/5': '{"id":88}',
          'add_case/88': _newCaseBody,
        }, o),
      );
      await f.client.createCase('My Project', 'New case');
      expect(f.adapter.calls.last.path, contains('add_case/88'));
    });
  });
}

/// `testrail_create_case_detailed` — POST `add_case/{sectionId}`.
void createCaseDetailedTests() {
  group('TestRailClient.createCaseDetailed', () {
    test('converts Markdown tables to the TestRail format', () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'add_case/42': _newCaseBody,
        }, o),
      );
      await f.client.createCaseDetailed(
        'My Project',
        'Detailed case',
        preconditions: 'User is logged out',
        steps: '| Col 1 | Col 2 |\n|---|---|\n| val1 | val2 |',
        expected: 'User is logged in',
        typeId: '7',
        refs: 'PROJ-1',
        labelIds: '7, 8',
        sectionId: '42',
      );
      final body = jsonDecode(f.adapter.calls.last.data as String);
      expect(body['custom_preconds'], 'User is logged out');
      expect(body['custom_steps'], '|||:Col 1|:Col 2\n||val1|val2\n');
      expect(body['custom_expected'], 'User is logged in');
      expect(body['type_id'], 7);
      expect(body['refs'], 'PROJ-1');
      expect(body['labels'], [7, 8]);
      expect(body['priority_id'], 2);
    });

    test('skips invalid type and label IDs', () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'add_case/42': _newCaseBody,
        }, o),
      );
      await f.client.createCaseDetailed(
        'My Project',
        'Detailed case',
        typeId: 'x',
        labelIds: '7, y',
        sectionId: '42',
      );
      final body = jsonDecode(f.adapter.calls.last.data as String);
      expect(body.containsKey('type_id'), isFalse);
      expect(body['labels'], [7]);
    });
  });
}

/// `testrail_create_case_steps` — POST `add_case/{sectionId}`.
void createCaseStepsTests() {
  group('TestRailClient.createCaseSteps', () {
    test('builds separated steps with HTML-converted tables', () async {
      final f = mockTestRail(
        (o) => routeByPath({
          'get_projects': _projectsBody,
          'add_case/42': _newCaseBody,
        }, o),
      );
      await f.client.createCaseSteps(
        'My Project',
        'Steps case',
        preconditions: 'User is logged out',
        stepsJson:
            '[{"content":"| Col 1 | Col 2 |\\n|---|---|\\n| val1 | val2 |",'
            '"expected":"Table shown","refs":"R-1"}]',
        priorityId: '3',
        sectionId: '42',
      );
      final body = jsonDecode(f.adapter.calls.last.data as String);
      expect(body['template_id'], 2);
      expect(body['custom_preconds'], '<p>User is logged out</p>');
      expect(body['custom_steps_separated'], [
        {
          'content': '<table><thead><tr><th>Col 1</th><th>Col 2</th></tr>'
              '</thead><tbody><tr><td>val1</td><td>val2</td></tr></tbody></table>',
          'expected': '<p>Table shown</p>',
          'additional_info': '',
          'refs': 'R-1',
          'markdown_editor_id': 1,
        },
      ]);
      expect(body['priority_id'], 3);
    });
  });
}

/// `testrail_create_case_steps` input validation.
void createCaseStepsErrorTests() {
  group('TestRailClient.createCaseSteps (validation)', () {
    test('rejects a non-array steps_json', () async {
      final f = mockTestRail(
        (o) => routeByPath({'get_projects': _projectsBody}, o),
      );
      expect(
        () => f.client.createCaseSteps(
          'My Project',
          'Steps case',
          stepsJson: '{"content": "not an array"}',
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed steps_json', () async {
      final f = mockTestRail(
        (o) => routeByPath({'get_projects': _projectsBody}, o),
      );
      expect(
        () => f.client.createCaseSteps(
          'My Project',
          'Steps case',
          stepsJson: 'not json',
        ),
        throwsFormatException,
      );
    });
  });
}
