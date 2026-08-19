import 'dart:io';

import 'package:dmtools/src/config/env_file_parser.dart';
import 'package:test/test.dart';

/// Helper that writes [content] to a unique temp file and returns its path.
///
/// Every path created here is tracked and removed in [_cleanupPaths].
final _createdPaths = <String>[];

String _writeEnvFile(String content) {
  final file = File('${Directory.systemTemp.path}/env_parser_test_'
      '${DateTime.now().microsecondsSinceEpoch}_'
      '${_createdPaths.length}.env');
  file.writeAsStringSync(content);
  _createdPaths.add(file.path);
  return file.path;
}

void _cleanupPaths() {
  for (final path in _createdPaths) {
    final f = File(path);
    if (f.existsSync()) {
      f.deleteSync();
    }
  }
  _createdPaths.clear();
}

void main() {
  tearDown(_cleanupPaths);

  _testBasicParsing();
  _testCommentsAndQuotes();
  _testEdgeCases();
  _testSpecialAndRealistic();
}

void _testBasicParsing() {
  group('parseEnvFile basics', () {
    test('parses a simple KEY=VALUE entry', () {
      final path = _writeEnvFile('API_KEY=secret\n');
      expect(parseEnvFile(path), {'API_KEY': 'secret'});
    });

    test('parses multiple entries', () {
      final path = _writeEnvFile(
        'FOO=1\n'
        'BAR=2\n'
        'BAZ=3\n',
      );
      expect(parseEnvFile(path), {'FOO': '1', 'BAR': '2', 'BAZ': '3'});
    });

    test('splits on the FIRST = only (values may contain =)', () {
      final path = _writeEnvFile('URL=http://example.com?a=b&c=d\n');
      expect(parseEnvFile(path), {'URL': 'http://example.com?a=b&c=d'});
    });

    test('trims whitespace around both key and value', () {
      final path = _writeEnvFile('  KEY  =  value  \n');
      expect(parseEnvFile(path), {'KEY': 'value'});
    });

    test('skips lines without =', () {
      final path = _writeEnvFile(
        'JUST_SOME_TEXT\n'
        'KEY=value\n'
        'ANOTHER_ORPHAN\n',
      );
      expect(parseEnvFile(path), {'KEY': 'value'});
    });

    test('skips empty lines', () {
      final path = _writeEnvFile(
        'FOO=1\n'
        '\n'
        '   \n'
        'BAR=2\n',
      );
      expect(parseEnvFile(path), {'FOO': '1', 'BAR': '2'});
    });
  });
}

void _testCommentsAndQuotes() {
  group('comments and quotes', () {
    test('skips comment lines starting with #', () {
      final path = _writeEnvFile(
        '# This is a comment\n'
        'KEY=value\n'
        '# Another comment\n',
      );
      expect(parseEnvFile(path), {'KEY': 'value'});
    });

    test('skips comment lines with leading whitespace before #', () {
      // The line is trimmed before the # check, so indented comments drop too.
      final path = _writeEnvFile(
        '   # indented comment\n'
        'KEY=value\n',
      );
      expect(parseEnvFile(path), {'KEY': 'value'});
    });

    test('does NOT strip inline comments — everything after first = is value',
        () {
      final path = _writeEnvFile('KEY=value # not a comment\n');
      expect(parseEnvFile(path), {'KEY': 'value # not a comment'});
    });

    test('does NOT strip surrounding quotes', () {
      final path = _writeEnvFile('KEY="quoted value"\n');
      expect(parseEnvFile(path), {'KEY': '"quoted value"'});
    });

    test('a line starting with # that also contains = is a comment', () {
      // Starts with # → treated as comment, never split on =.
      final path = _writeEnvFile('# KEY=not_parsed\nKEY=value\n');
      expect(parseEnvFile(path), {'KEY': 'value'});
    });

    test('does not support export prefix', () {
      // export KEY=value is parsed literally: key = "export KEY".
      final path = _writeEnvFile('export KEY=value\n');
      expect(parseEnvFile(path), {'export KEY': 'value'});
    });
  });
}

void _testEdgeCases() {
  group('edge cases', () {
    test('returns empty map for an empty file', () {
      final path = _writeEnvFile('');
      expect(parseEnvFile(path), isEmpty);
    });

    test('returns empty map for a non-existent file', () {
      final bogus =
          '${Directory.systemTemp.path}/definitely_does_not_exist.env';
      expect(parseEnvFile(bogus), isEmpty);
    });

    test('includes a key with an empty value (KEY=)', () {
      final path = _writeEnvFile('EMPTY=\n');
      expect(parseEnvFile(path), {'EMPTY': ''});
    });

    test('includes a key whose value is only whitespace (trimmed to empty)',
        () {
      final path = _writeEnvFile('SPACED=   \n');
      expect(parseEnvFile(path), {'SPACED': ''});
    });

    test('skips a line whose key is empty after trim (=value)', () {
      final path = _writeEnvFile(
        '=orphaned value\n'
        'KEY=value\n',
      );
      expect(parseEnvFile(path), {'KEY': 'value'});
    });

    test('skips a line whose key is whitespace-only before =', () {
      final path = _writeEnvFile(
        '   =value\n'
        'KEY=value\n',
      );
      expect(parseEnvFile(path), {'KEY': 'value'});
    });

    test('a line that is just = is skipped', () {
      final path = _writeEnvFile(
        '=\n'
        'KEY=value\n',
      );
      expect(parseEnvFile(path), {'KEY': 'value'});
    });
  });
}

void _testSpecialAndRealistic() {
  group('special characters and realistic files', () {
    test('parses values with special characters (URLs, base64 tokens)', () {
      final url = 'https://api.example.com/v2/path?token=abc123&user=me';
      final base64Token = 'Bearer dGhpcyBpcyBhIGJhc2U2NCB0b2tlbiBzdHJpbmc=';
      final path = _writeEnvFile(
        'API_URL=$url\n'
        'AUTH_TOKEN=$base64Token\n',
      );
      expect(
        parseEnvFile(path),
        {'API_URL': url, 'AUTH_TOKEN': base64Token},
      );
    });

    test('mixes comments, blanks, and entries in a realistic file', () {
      final path = _writeEnvFile(
        '# dmtools.env\n'
        '\n'
        'DMTOOLS_JIRA_URL=https://jira.example.com\n'
        'DMTOOLS_JIRA_TOKEN=abc==def\n'
        '\n'
        '   # indented note\n'
        'DMTOOLS_DEBUG=true\n'
        'orphan line without equals\n',
      );
      expect(
        parseEnvFile(path),
        {
          'DMTOOLS_JIRA_URL': 'https://jira.example.com',
          'DMTOOLS_JIRA_TOKEN': 'abc==def',
          'DMTOOLS_DEBUG': 'true',
        },
      );
    });

    test('returns a new mutable map each call', () {
      final path = _writeEnvFile('KEY=value\n');
      final first = parseEnvFile(path);
      final second = parseEnvFile(path);
      // Mutating one result must not affect the other.
      first['INJECTED'] = 'x';
      expect(second, {'KEY': 'value'});
      expect(first, {'KEY': 'value', 'INJECTED': 'x'});
    });
  });
}
