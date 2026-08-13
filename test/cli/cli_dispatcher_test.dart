/// Unit tests for [CliDispatcher].
library;

import 'dart:async';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

late Directory _tmp;
late List<String> _lines;
late CliDispatcher _dispatcher;

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('dmtools_cli_');
    PropertyReader.setOverrides({});
    _lines = [];
    _dispatcher = CliDispatcher(
      writer: _lines.add,
      propertyReader: PropertyReader(basePath: _tmp.path),
      isTty: () => false,
    );
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  _testVersion();
  _testHelp();
  _testListJobs();
  _testDoctor();
  _testRun();
  _testList();
  _testInteractive();
  _testDirectTool();
  _testNoArgs();
  _testDefaults();
}

void _testVersion() {
  group('--version', () {
    test('prints the version banner', () {
      expect(_dispatcher.dispatch(['--version']), 0);
      expect(
        _lines,
        [
          'DMTools $dmtoolsVersion',
          'A comprehensive development management toolkit'
        ],
      );
    });

    test('-v alias matches', () {
      expect(_dispatcher.dispatch(['-v']), 0);
      expect(_lines.first, 'DMTools $dmtoolsVersion');
    });
  });
}

void _testHelp() {
  group('--help', () {
    test('prints the Java help text', () {
      expect(_dispatcher.dispatch(['--help']), 0);
      expect(_lines.join('\n'), CliDispatcher.helpText);
      expect(_lines.join('\n'), startsWith('DMTools CLI Wrapper'));
    });

    test('-h and help aliases match --help', () {
      expect(_dispatcher.dispatch(['-h']), 0);
      final viaH = _lines.join('\n');
      _lines.clear();
      expect(_dispatcher.dispatch(['help']), 0);
      expect(_lines.join('\n'), viaH);
      expect(
        _lines.join('\n'),
        contains('dmtools jira_get_ticket DMC-479 summary,description'),
      );
    });
  });
}

void _testListJobs() {
  group('--list-jobs', () {
    test('prints every display job and the total', () {
      expect(_dispatcher.dispatch(['--list-jobs']), 0);
      expect(_lines.first, 'Available Jobs:');
      expect(_lines[1], '===============');
      expect(_lines[2], '- presalesupport');
      expect(_lines.last, 'Total: 23 jobs available');
      expect(
        _lines.last,
        'Total: ${JobRegistry.displayJobs.length} jobs available',
      );
    });
  });
}

void _testDoctor() {
  group('doctor', () {
    test('prints the configuration check report', () {
      expect(_dispatcher.dispatch(['doctor']), 0);
      final out = _lines.join('\n');
      expect(out, startsWith('DMTools Configuration Check'));
      expect(out, contains('Integrations ready: '));
    });

    test('reflects dmtools.env from the working directory', () {
      File('${_tmp.path}/dmtools.env')
          .writeAsStringSync('SOURCE_GITHUB_TOKEN=ghp_test\n');
      expect(_dispatcher.dispatch(['doctor']), 0);
      expect(
        _lines.join('\n'),
        contains('✓ github - GitHub authentication configured'),
      );
    });
  });
}

void _testRun() {
  group('run', () {
    test('rejects a non-existent config file', () {
      expect(_dispatcher.dispatch(['run', 'job-config.json']), 1);
      expect(_lines, ['Error: Config file not found: job-config.json']);
    });

    test('resolves a known job name with overrides', () {
      expect(
        _dispatcher.dispatch(['run', 'codegenerator', '--param1', 'test']),
        1,
      );
      expect(
        _lines,
        [
          'Config resolved for job: codegenerator (execution requires Phase 3+ '
              'integrations)',
        ],
      );
    });

    test('rejects a non-existent config file with encoded overrides', () {
      expect(_dispatcher.dispatch(['run', 'job.json', 'encoded-blob']), 1);
      expect(_lines, ['Error: Config file not found: job.json']);
    });

    test('rejects run without a target', () {
      expect(_dispatcher.dispatch(['run']), 1);
      expect(_lines.first, contains('Error:'));
    });
  });
}

void _testList() {
  group('list', () {
    test('stubs the MCP tool catalog', () {
      expect(_dispatcher.dispatch(['list']), 1);
      expect(_lines, ['MCP tool catalog requires Phase 3']);
    });

    test('accepts a filter argument (still stubbed)', () {
      expect(_dispatcher.dispatch(['list', 'jira']), 1);
      expect(_lines, ['MCP tool catalog requires Phase 3']);
    });
  });
}

void _testInteractive() {
  group('interactive', () {
    test('stubs interactive mode', () {
      expect(_dispatcher.dispatch(['interactive']), 1);
      expect(_lines, ['Interactive mode requires Phase 4 (terminal picker)']);
    });

    test('i alias matches', () {
      expect(_dispatcher.dispatch(['i']), 1);
      expect(_lines, ['Interactive mode requires Phase 4 (terminal picker)']);
    });
  });
}

void _testDirectTool() {
  group('direct tool invocation', () {
    test('stubs MCP tool execution', () {
      expect(_dispatcher.dispatch(['jira_get_ticket', 'DMC-479']), 1);
      expect(_lines, ['Tool execution requires Phase 3 MCP registry']);
    });

    test('unknown commands fall through to the tool stub', () {
      expect(_dispatcher.dispatch(['frobnicate']), 1);
      expect(_lines, ['Tool execution requires Phase 3 MCP registry']);
    });
  });
}

void _testNoArgs() {
  group('no arguments', () {
    test('prints help when stdout is not a terminal', () {
      expect(_dispatcher.dispatch([]), 0);
      expect(_lines.join('\n'), CliDispatcher.helpText);
    });

    test('routes to the interactive stub on a TTY', () {
      final tty = CliDispatcher(
        writer: _lines.add,
        propertyReader: PropertyReader(basePath: _tmp.path),
        isTty: () => true,
      );
      expect(tty.dispatch([]), 1);
      expect(_lines, ['Interactive mode requires Phase 4 (terminal picker)']);
    });
  });
}

void _testDefaults() {
  group('defaults', () {
    test('writes through print and treats a non-terminal run as help', () {
      final captured = <String>[];
      final code = runZoned(
        () => CliDispatcher().dispatch([]),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => captured.add(line),
        ),
      );
      expect(code, 0);
      expect(captured.join('\n'), CliDispatcher.helpText);
    });

    test('--version uses the default writer', () {
      final captured = <String>[];
      final code = runZoned(
        () => CliDispatcher().dispatch(['--version']),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => captured.add(line),
        ),
      );
      expect(code, 0);
      expect(
        captured,
        [
          'DMTools $dmtoolsVersion',
          'A comprehensive development management toolkit'
        ],
      );
    });
  });
}
