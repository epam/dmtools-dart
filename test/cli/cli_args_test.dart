/// Unit tests for [ParsedCliArgs] and the internal arg scanner.
library;

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  _testValueFlags();
  _testBooleanFlags();
  _testPositionalAndMixed();
}

void _testValueFlags() {
  group('value flags', () {
    test('--data <value> (separate form)', () {
      final p = ParsedCliArgs.parse(['--data', 'hello', 'run']);
      expect(p.data, 'hello');
      expect(p.command, 'run');
    });

    test('--file <value> (separate form)', () {
      final p = ParsedCliArgs.parse(['--file', 'config.json', 'run']);
      expect(p.file, 'config.json');
      expect(p.command, 'run');
    });

    test('--output <value> (separate form)', () {
      final p = ParsedCliArgs.parse(['--output', 'json', 'run']);
      expect(p.outputFormat, 'json');
    });

    test('--output=<value> (inline form)', () {
      final p = ParsedCliArgs.parse(['--output=mini', 'run']);
      expect(p.outputFormat, 'mini');
      expect(p.command, 'run');
    });

    test('--output= (empty inline value)', () {
      final p = ParsedCliArgs.parse(['--output=', 'run']);
      expect(p.outputFormat, '');
    });

    test('--data with no following value defaults to empty', () {
      final p = ParsedCliArgs.parse(['--data']);
      expect(p.data, '');
      expect(p.command, '');
    });
  });
}

void _testBooleanFlags() {
  group('boolean flags', () {
    test('--verbose', () {
      final p = ParsedCliArgs.parse(['--verbose', 'run']);
      expect(p.verbose, isTrue);
      expect(p.debug, isFalse);
      expect(p.quiet, isFalse);
      expect(p.command, 'run');
    });

    test('--debug sets both verbose and debug', () {
      final p = ParsedCliArgs.parse(['--debug', 'run']);
      expect(p.verbose, isTrue);
      expect(p.debug, isTrue);
    });

    test('--quiet', () {
      final p = ParsedCliArgs.parse(['--quiet', 'run']);
      expect(p.quiet, isTrue);
      expect(p.verbose, isFalse);
    });

    test('--toon sets outputFormat', () {
      final p = ParsedCliArgs.parse(['--toon', 'run']);
      expect(p.outputFormat, 'toon');
    });

    test('--mini sets outputFormat', () {
      final p = ParsedCliArgs.parse(['--mini', 'run']);
      expect(p.outputFormat, 'mini');
    });
  });
}

void _testPositionalAndMixed() {
  group('positional and mixed args', () {
    test('positional args only', () {
      final p = ParsedCliArgs.parse(['run', 'job.json']);
      expect(p.command, 'run');
      expect(p.positional, ['job.json']);
    });

    test('unknown flag is ignored (not positional)', () {
      final p = ParsedCliArgs.parse(['--unknown', 'run']);
      expect(p.command, 'run');
      expect(p.positional, isEmpty);
    });

    test('unknown inline flag is ignored', () {
      final p = ParsedCliArgs.parse(['--unknown=x', 'run']);
      expect(p.command, 'run');
    });

    test('mix of flags and positionals', () {
      final p = ParsedCliArgs.parse([
        '--verbose',
        'run',
        'job.json',
        '--data',
        'hello',
      ]);
      expect(p.verbose, isTrue);
      expect(p.command, 'run');
      expect(p.positional, ['job.json']);
      expect(p.data, 'hello');
    });

    test('empty args produce empty results', () {
      final p = ParsedCliArgs.parse([]);
      expect(p.command, '');
      expect(p.positional, isEmpty);
      expect(p.data, isNull);
      expect(p.verbose, isFalse);
    });

    test('multiple positional args', () {
      final p = ParsedCliArgs.parse(['run', 'a', 'b', 'c']);
      expect(p.command, 'run');
      expect(p.positional, ['a', 'b', 'c']);
    });
  });
}
