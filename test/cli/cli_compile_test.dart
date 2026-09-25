import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/cli/cli_dispatcher.dart';
import 'package:dmtools/src/config/property_reader.dart';
import 'package:test/test.dart';

/// CLI dispatch tests for `dmtools compile` (dm.ai #595): covers the
/// `_runCompile` path of [CliDispatcher] — argument parsing, version
/// resolution, error exits, and a successful end-to-end pack build.
void main() {
  setUpAll(() => PropertyReader.testIsolation = true);
  tearDownAll(() {
    PropertyReader.testIsolation = false;
    PropertyReader.testEnvironment.clear();
  });

  late Directory tmp;
  late Directory agentRoot;
  late Directory outDir;
  late List<String> lines;
  late CliDispatcher dispatcher;

  setUp(() {
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
  });

  tearDown(() {
    PropertyReader.clearOverrides();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A minimal agent with one JS file + a transitive require.
  File writeAgent() {
    File('${agentRoot.path}/js/common/util.js')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// util\n');
    File('${agentRoot.path}/js/main.js')
        .writeAsStringSync("var u = require('./common/util.js');\n");
    return File('${agentRoot.path}/my_agent.json')
      ..writeAsStringSync(jsonEncode({
        'name': 'Teammate',
        'params': {'jsPath': 'agents/js/main.js'},
      }));
  }

  group('CliDispatcher compile', () {
    test('prints usage and exits 1 when no entry is given', () async {
      expect(await dispatcher.dispatch(['compile']), 1);
      expect(lines.join('\n'), contains('Usage: dmtools compile'));
    });

    test('prints usage and exits 0 on --help', () async {
      expect(await dispatcher.dispatch(['compile', '--help']), 0);
      expect(lines.join('\n'), contains('--version <semver>'));
    });

    test('fails with exit 1 when the entry config does not exist', () async {
      expect(
          await dispatcher.dispatch(['compile', '${tmp.path}/nope.json']), 1);
      expect(lines.join('\n'), contains('entry config not found'));
    });

    test('fails with exit 1 when no version is given', () async {
      final entry = writeAgent();
      expect(await dispatcher.dispatch(['compile', entry.path]), 1);
      expect(lines.join('\n'), contains('--version'));
    });

    test('builds a pack end to end with an explicit version', () async {
      final entry = writeAgent();
      final code = await dispatcher.dispatch([
        'compile',
        entry.path,
        '--agent-root',
        agentRoot.path,
        '--version',
        '1.0.0',
        '--out',
        outDir.path,
      ]);
      expect(code, 0);
      expect(lines.join('\n'), contains('Agent pack built successfully'));
      expect(File('${outDir.path}/my_agent-1.0.0.zip').existsSync(), isTrue);
      expect(File('${outDir.path}/manifest.json').existsSync(), isTrue);
      expect(File('${outDir.path}/my_agent-1.0.0.zip.sha256').existsSync(),
          isTrue);
    });

    test('resolves the version from versions.json when --version is absent',
        () async {
      final entry = writeAgent();
      final versionsFile = File('${tmp.path}/versions.json')
        ..writeAsStringSync(jsonEncode({'my_agent': '2.3.4'}));
      final code = await dispatcher.dispatch([
        'compile',
        entry.path,
        '--agent-root',
        agentRoot.path,
        '--versions-file',
        versionsFile.path,
        '--out',
        outDir.path,
      ]);
      expect(code, 0);
      expect(File('${outDir.path}/my_agent-2.3.4.zip').existsSync(), isTrue);
    });

    test('defaults agent-root to the entry directory when omitted', () async {
      final entry = writeAgent();
      // entry lives in agentRoot, which also contains js/ — the default
      // agent-root (entry's dir) resolves the closure correctly.
      final code = await dispatcher.dispatch(
          ['compile', entry.path, '--version', '1.0.0', '--out', outDir.path]);
      expect(code, 0);
    });
  });
}
