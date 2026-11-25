import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  _registerPlainBooleanWithExplanationTests();
  _registerMarkdownBooleanTokenTests();
  _registerMarkdownExplanationTests();
  _registerInvalidBooleanWithExplanationTests();
  _registerBooleanResponseTests();
  _registerStructuredResponseTests();
}

void _registerPlainBooleanWithExplanationTests() {
  group('AIResponseParser.parseBooleanWithExplanation (plain)', () {
    test('parses plain true and false with optional explanation', () {
      final trueWithExpl = AIResponseParser.parseBooleanWithExplanation(
        'true, because it validates the same flow',
      );
      expect(trueWithExpl.value, isTrue);
      expect(trueWithExpl.explanation, 'because it validates the same flow');

      final truePlain = AIResponseParser.parseBooleanWithExplanation('true');
      expect(truePlain.value, isTrue);
      expect(truePlain.explanation, isNull);

      final falsePlain = AIResponseParser.parseBooleanWithExplanation('false');
      expect(falsePlain.value, isFalse);
      expect(falsePlain.explanation, isNull);

      final falseWithTail = AIResponseParser.parseBooleanWithExplanation(
        'false, not related',
      );
      expect(falseWithTail.value, isFalse);
      expect(falseWithTail.explanation, isNull);
    });
  });
}

void _registerMarkdownBooleanTokenTests() {
  group('AIResponseParser.parseBooleanWithExplanation (markdown tokens)', () {
    test('strips markdown wrappers around false and true tokens', () {
      for (final sample in [
        '**false**',
        '*false*',
        '__false__',
        '_false_',
        '`false`',
        '"false"',
        'false.',
        '```\nfalse\n```',
        'Answer: **false**',
      ]) {
        final parsed = AIResponseParser.parseBooleanWithExplanation(sample);
        expect(parsed.value, isFalse, reason: 'Failed for $sample');
        expect(parsed.explanation, isNull);
      }

      for (final sample in [
        '**true**',
        '*true*',
        '__true__',
        '_true_',
        '`true`',
        '"true"',
        'true.',
      ]) {
        final parsed = AIResponseParser.parseBooleanWithExplanation(sample);
        expect(parsed.value, isTrue, reason: 'Failed for $sample');
      }
    });
  });
}

void _registerMarkdownExplanationTests() {
  group(
    'AIResponseParser.parseBooleanWithExplanation (markdown explanations)',
    () {
      test('extracts explanations from markdown-formatted true responses', () {
        final boldWithExpl = AIResponseParser.parseBooleanWithExplanation(
          '**true**, because it validates the login flow',
        );
        expect(boldWithExpl.value, isTrue);
        expect(boldWithExpl.explanation, 'because it validates the login flow');

        final codeWithExpl = AIResponseParser.parseBooleanWithExplanation(
          '`true`, covers the same authentication scenario',
        );
        expect(codeWithExpl.value, isTrue);
        expect(
          codeWithExpl.explanation,
          'covers the same authentication scenario',
        );

        final multilineWithExpl = AIResponseParser.parseBooleanWithExplanation(
          '**True**\nBecause the story modifies the same endpoint.',
        );
        expect(multilineWithExpl.value, isTrue);
        expect(
          multilineWithExpl.explanation,
          'Because the story modifies the same endpoint.',
        );

        final fencedWithExpl = AIResponseParser.parseBooleanWithExplanation(
          '```text\ntrue, related to password reset\n```',
        );
        expect(fencedWithExpl.value, isTrue);
        expect(fencedWithExpl.explanation, 'related to password reset');

        final fallbackTrue = AIResponseParser.parseBooleanWithExplanation(
          'Answer: **true**, matches existing scenario',
        );
        expect(fallbackTrue.value, isTrue);
        expect(fallbackTrue.explanation, 'matches existing scenario');
      });
    },
  );
}

void _registerInvalidBooleanWithExplanationTests() {
  group('AIResponseParser.parseBooleanWithExplanation (fallback)', () {
    test(
      'logs warning and returns false instead of throwing on invalid input',
      () {
        final warnings = <String>[];
        final invalid = AIResponseParser.parseBooleanWithExplanation(
          'maybe',
          warnWriter: warnings.add,
        );
        expect(invalid.value, isFalse);
        expect(invalid.explanation, isNull);

        final empty = AIResponseParser.parseBooleanWithExplanation(
          '   ',
          warnWriter: warnings.add,
        );
        expect(empty.value, isFalse);
        expect(empty.explanation, isNull);

        final nullResp = AIResponseParser.parseBooleanWithExplanation(
          null,
          warnWriter: warnings.add,
        );
        expect(nullResp.value, isFalse);
        expect(nullResp.explanation, isNull);

        expect(warnings.length, 3);
        expect(warnings.first, contains('No valid boolean value found'));
      },
    );
  });
}

void _registerBooleanResponseTests() {
  group('AIResponseParser.parseBooleanResponse', () {
    test('parses plain, markdown-wrapped, and embedded boolean tokens', () {
      expect(AIResponseParser.parseBooleanResponse('... true ...'), isTrue);
      expect(AIResponseParser.parseBooleanResponse('... false ...'), isFalse);
      expect(AIResponseParser.parseBooleanResponse('**true**'), isTrue);
      expect(AIResponseParser.parseBooleanResponse('**false**'), isFalse);
      expect(AIResponseParser.parseBooleanResponse('__true__'), isTrue);
      expect(AIResponseParser.parseBooleanResponse('__false__'), isFalse);
      expect(AIResponseParser.parseBooleanResponse('`true`'), isTrue);
      expect(AIResponseParser.parseBooleanResponse('`false`'), isFalse);
      expect(AIResponseParser.parseBooleanResponse('isTrueValue'), isTrue);
      expect(AIResponseParser.parseBooleanResponse('isFalseValue'), isFalse);
    });

    test('logs warning and returns false on unparseable or empty input', () {
      final warnings = <String>[];
      expect(
        AIResponseParser.parseBooleanResponse(
          '... invalid ...',
          warnWriter: warnings.add,
        ),
        isFalse,
      );
      expect(
        AIResponseParser.parseBooleanResponse('', warnWriter: warnings.add),
        isFalse,
      );
      expect(
        AIResponseParser.parseBooleanResponse(null, warnWriter: warnings.add),
        isFalse,
      );
      expect(warnings.length, 3);
    });
  });
}

void _registerStructuredResponseTests() {
  group('AIResponseParser JSON & code helpers', () {
    test('parseResponseAsJSONArray and parseResponseAsJSONObject', () {
      final arr = AIResponseParser.parseResponseAsJSONArray(
        '... ["item1", "item2"] ...',
      );
      expect(arr, ['item1', 'item2']);
      expect(
        () => AIResponseParser.parseResponseAsJSONArray('invalid'),
        throwsFormatException,
      );
      expect(
        () => AIResponseParser.parseResponseAsJSONArray(null),
        throwsFormatException,
      );

      final obj = AIResponseParser.parseResponseAsJSONObject(
        '... {"key": "value"} ...',
      );
      expect(obj['key'], 'value');
      expect(
        () => AIResponseParser.parseResponseAsJSONObject('invalid'),
        throwsFormatException,
      );
      expect(
        () => AIResponseParser.parseResponseAsJSONObject(null),
        throwsFormatException,
      );
    });

    test('parseCodeResponse extracts fenced block or trims plain text', () {
      expect(
        AIResponseParser.parseCodeResponse('```dart\nfinal x = 1;\n```'),
        'final x = 1;',
      );
      expect(
        AIResponseParser.parseCodeResponse('  plain code  '),
        'plain code',
      );
      expect(
        () => AIResponseParser.parseCodeResponse(''),
        throwsArgumentError,
      );
      expect(
        () => AIResponseParser.parseCodeResponse(null),
        throwsArgumentError,
      );
    });
  });
}
