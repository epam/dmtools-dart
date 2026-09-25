import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/cli/cli_dispatcher.dart';
import 'package:dmtools/src/config/property_reader.dart';
import 'package:test/test.dart';

/// CLI dispatch tests for `dmtools compile` (dm.ai #595): covers the
/// `_runCompile` path of [CliDispatcher] — argument parsing, version
/// resolution, error exits, and a successful end-to-end pack build.

/// Per-test fixture: a temp workspace with a writable [dispatcher] and the
/// directories the compile scenarios need.
class _CompileFixture {
  _CompileFixture() {
    tmp = Directory.systemTemp.createTempSync('dmtools_compile_cli_');
    agentRoot = Directory('${tmp.path}/agents')..createSync();
    outDir = Directory('${tmp.path}/dist');
    PropertyReader.setOverrides({});
    lines = [];
    dispatcher = CliDispatcher(
      writer: lines.add,
      propertyReader: PropertyReader(basePath: tmp.path),
      isTty: () => false,
    );
  }

  late Directory tmp;
  late Directory agentRoot;
  late Directory outDir;
  late List<String> lines;
  late CliDispatcher dispatcher;

  void dispose() {
    PropertyReader.clearOverrides();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }

  /// A minimal agent with one JS file + a transitive require.
  File writeAgent() {
    File('${agentRoot.path}/js/common/util.js')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// util\n');
    File(
      '${agentRoot.path}/js/main.js',
    ).writeAsStringSync("var u = require('./common/util.js');\n");
    return File('${agentRoot.path}/my_agent.json')
      ..writeAsStringSync(
        jsonEncode({
          'name': 'Teammate',
          'params': {'jsPath': 'agents/js/main.js'},
        }),
      );
  }
}

_CompileFixture f = _CompileFixture();

void _registerUsageAndErrorTests() {
  group('CliDispatcher compile — usage & errors', () {
    test('prints usage and exits 1 when no entry is given', () async {
      expect(await f.dispatcher.dispatch(['compile']), 1);
      expect(f.lines.join('\n'), contains('Usage: dmtools compile'));
    });

    test('prints usage and exits 0 on --help', () async {
      expect(await f.dispatcher.dispatch(['compile', '--help']), 0);
      expect(f.lines.join('\n'), contains('--version <semver>'));
    });

    test('fails with exit 1 when the entry config does not exist', () async {
      expect(
        await f.dispatcher.dispatch(['compile', '${f.tmp.path}/nope.json']),
        1,
      );
      expect(f.lines.join('\n'), contains('entry config not found'));
    });

    test('fails with exit 1 when no version is given', () async {
      final entry = f.writeAgent();
      expect(await f.dispatcher.dispatch(['compile', entry.path]), 1);
      expect(f.lines.join('\n'), contains('--version'));
    });
  });
}

void _registerPackBuildTests() {
  group('CliDispatcher compile — pack build', () {
    test('builds a pack end to end with an explicit version', () async {
      final entry = f.writeAgent();
      final code = await f.dispatcher.dispatch([
        'compile',
        entry.path,
        '--agent-root',
        f.agentRoot.path,
        '--version',
        '1.0.0',
        '--out',
        f.outDir.path,
      ]);
      expect(code, 0);
      expect(f.lines.join('\n'), contains('Agent pack built successfully'));
      expect(File('${f.outDir.path}/my_agent-1.0.0.zip').existsSync(), isTrue);
      expect(File('${f.outDir.path}/manifest.json').existsSync(), isTrue);
      expect(
        File('${f.outDir.path}/my_agent-1.0.0.zip.sha256').existsSync(),
        isTrue,
      );
    });

    test(
      'resolves the version from versions.json when --version is absent',
      () async {
        final zip = await _compileWithVersionsJson(f);
        expect(zip.existsSync(), isTrue);
      },
    );

    test('defaults agent-root to the entry directory when omitted', () async {
      final entry = f.writeAgent();
      // entry lives in agentRoot, which also contains js/ — the default
      // agent-root (entry's dir) resolves the closure correctly.
      final code = await f.dispatcher.dispatch([
        'compile',
        entry.path,
        '--version',
        '1.0.0',
        '--out',
        f.outDir.path,
      ]);
      expect(code, 0);
    });
  });
}

/// versions.json is the default version source when --version is omitted:
/// compiles the pack with the version declared for the agent and returns
/// the built zip for the caller to assert on.
Future<File> _compileWithVersionsJson(_CompileFixture f) async {
  final entry = f.writeAgent();
  final versionsFile = File('${f.tmp.path}/versions.json')
    ..writeAsStringSync(jsonEncode({'my_agent': '2.3.4'}));
  final code = await f.dispatcher.dispatch([
    'compile',
    entry.path,
    '--agent-root',
    f.agentRoot.path,
    '--versions-file',
    versionsFile.path,
    '--out',
    f.outDir.path,
  ]);
  expect(code, 0);
  return File('${f.outDir.path}/my_agent-2.3.4.zip');
}

void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  setUp(() => f = _CompileFixture());
  tearDown(() => f.dispose());

  _registerUsageAndErrorTests();
  _registerPackBuildTests();
}
