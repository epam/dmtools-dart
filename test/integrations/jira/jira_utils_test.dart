/// Unit tests for the pure Jira helpers in `jira_utils.dart` used by the
/// field-update engine (`jira_update_field`, gh-191 P6-JSY-04).
///
/// `jiraResponseErrorDetail` mirrors Java `checkJiraResponseForErrors`:
/// joined `errorMessages` and `errors` entries (`Field customfield_X: …`
/// for custom fields, `X: …` otherwise), `null` when the body carries no
/// error object or is not JSON.
library;

import 'dart:convert';

import 'package:dmtools/src/integrations/jira/jira_utils.dart';
import 'package:test/test.dart';

void main() {
  group('jiraResponseErrorDetail', () {
    test('non-JSON body yields null', () {
      expect(jiraResponseErrorDetail('<html>502</html>'), isNull);
      expect(jiraResponseErrorDetail(''), isNull);
    });

    test('non-object JSON yields null', () {
      expect(jiraResponseErrorDetail(jsonEncode([1, 2])), isNull);
      expect(jiraResponseErrorDetail('"just a string"'), isNull);
    });

    test('object without error keys yields null', () {
      expect(
        jiraResponseErrorDetail(jsonEncode({'id': '1', 'key': 'PROJ-1'})),
        isNull,
      );
    });

    test('errorMessages list is joined', () {
      expect(
        jiraResponseErrorDetail(jsonEncode({
          'errorMessages': ['first problem', 'second problem'],
        })),
        'first problem; second problem',
      );
    });
  });

  jiraResponseErrorDetailCombinationTests();
}

void jiraResponseErrorDetailCombinationTests() {
  group('jiraResponseErrorDetail: errors map', () {
    test('plain field errors use "field: message"', () {
      expect(
        jiraResponseErrorDetail(jsonEncode({
          'errors': {'summary': 'Summary is required'},
        })),
        'summary: Summary is required',
      );
    });

    test('customfield errors get the "Field" prefix', () {
      expect(
        jiraResponseErrorDetail(jsonEncode({
          'errors': {
            'customfield_10001': 'cannot be set',
          },
        })),
        'Field customfield_10001: cannot be set',
      );
    });

    test('errorMessages and errors combine, messages first', () {
      expect(
        jiraResponseErrorDetail(jsonEncode({
          'errorMessages': ['no transition'],
          'errors': {'labels': 'too many'},
        })),
        'no transition; labels: too many',
      );
    });

    test('non-string message entries are ignored, empty result is null', () {
      expect(
        jiraResponseErrorDetail(jsonEncode({
          'errorMessages': [
            42,
            {'a': 1}
          ],
        })),
        isNull,
      );
    });
  });
}
