import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dmtools/src/compile/agent_pack_compiler.dart';
import 'package:test/test.dart';

/// Tests for [AgentPackCompiler] (dm.ai #595): closure walking, path
/// normalization, transitive JS scanning, deterministic zip, manifest schema.
/// Java parity: `AgentPackCompilerTest`.
void main() {
  setUp(() {
    agentRoot = Directory.systemTemp.createTempSync('pack_agents_');
    outDir = Directory.systemTemp.createTempSync('pack_dist_');
  });

  tearDown(() {
    agentRoot.deleteSync(recursive: true);
    outDir.deleteSync(recursive: true);
  });

  closureTests();
  referenceKindTests();
  manifestTests();
  scriptsTests();
  prefixNormalizationTests();
  commentStripperTests();
}

late Directory agentRoot;
late Directory outDir;

/// Writes [content] to [relativePath] under the agent root; returns the file.
File write(String relativePath, String content) {
  final file = File('${agentRoot.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file;
}

/// A minimal agent referencing one JS file with a relative require.
File writeSimpleAgent() {
  write('js/common/util.js', '// util\n');
  write('js/main.js', "var u = require('./common/util.js');\n");
  return write(
      'my_agent.json',
      jsonEncode({
        'name': 'Teammate',
        'params': {'jsPath': 'agents/js/main.js'},
      }));
}

/// Reads all zip entry names.
List<String> zipNames(File zipFile) {
  final archive = ZipDecoder().decodeBytes(zipFile.readAsBytesSync());
  return archive.files.map((f) => f.name).toList();
}

PackResult compileAgent(File entry, {String version = '1.0.0'}) =>
    AgentPackCompiler(agentRoot.path).compile(entry, version, 'abc123', outDir);

/// Closure walking: transitive requires, missing-file negatives.
void closureTests() {
  group('AgentPackCompiler closure', () {
    test('includes entry and transitive JS', () {
      final result = compileAgent(writeSimpleAgent());
      expect(result.zipFile.existsSync(), isTrue);
      expect(result.manifestFile.existsSync(), isTrue);
      expect(result.shaFile.existsSync(), isTrue);

      final names = zipNames(result.zipFile);
      expect(names, contains('my_agent.json'));
      expect(names, contains('js/main.js'));
      expect(names, contains('js/common/util.js')); // transitive require
      expect(names, contains('manifest.json'));
      expect(names, isNot(contains('agents/js/main.js'))); // prefix stripped
    });

    test('missing referenced file fails with the exact path', () {
      final entry = write(
          'broken.json',
          jsonEncode({
            'name': 'X',
            'params': {'jsPath': 'agents/js/does_not_exist.js'},
          }));
      expect(
        () => compileAgent(entry),
        throwsA(isA<AgentPackException>().having(
            (e) => e.message, 'message', contains('does_not_exist.js'))),
      );
      expect(outDir.listSync(), isEmpty); // nothing written on failure
    });
  });
}

/// Reference-kind handling: URLs and classpath: refs are skipped.
void referenceKindTests() {
  group('AgentPackCompiler reference kinds', () {
    test('URL and classpath references are ignored', () {
      write('js/main.js', '// main\n');
      final entry = write(
          'mixed.json',
          jsonEncode({
            'name': 'X',
            'params': {
              'preJSAction': 'js/main.js',
              'postJSAction': 'https://github.com/user/repo/blob/main/x.js',
              'timerJSAction': 'classpath:js/timer.js',
            },
          }));
      expect(compileAgent(entry).zipFile.existsSync(), isTrue);
    });

    test('require inside a JSDoc comment is not matched', () {
      write('js/common/commentMarkup.js',
          '/**\n * var m = require("./common/commentMarkup.js");\n */\n');
      write('js/main.js', "var c = require('./common/commentMarkup.js');\n");
      final entry = write(
          'commented.json',
          jsonEncode({
            'name': 'X',
            'params': {'jsPath': 'agents/js/main.js'},
          }));
      final names = zipNames(compileAgent(entry).zipFile);
      expect(names, contains('js/common/commentMarkup.js'));
    });
  });
}

/// Manifest schema and deterministic-zip invariants.
void manifestTests() {
  group('AgentPackCompiler manifest', () {
    test('carries agent, version, files with sha256+mode', () {
      final result = compileAgent(writeSimpleAgent(), version: '1.2.0');
      final manifest = jsonDecode(result.manifestFile.readAsStringSync())
          as Map<String, dynamic>;

      expect(manifest['agent'], 'my_agent');
      expect(manifest['version'], '1.2.0');
      expect(manifest['sourceCommit'], 'abc123');
      expect(manifest['defaultEntry'], 'my_agent.json');
      expect(manifest.containsKey('minDmtoolsVersion'), isTrue);

      final files = manifest['files'] as List;
      final main = files.firstWhere((f) => (f as Map)['path'] == 'js/main.js')
          as Map<String, dynamic>;
      expect((main['sha256'] as String).length, 64);
      expect(main['mode'], '0644');
    });

    test('repeated builds are byte-identical', () {
      final entry = writeSimpleAgent();
      final out1 = Directory.systemTemp.createTempSync('d1_');
      final out2 = Directory.systemTemp.createTempSync('d2_');
      final r1 = AgentPackCompiler(agentRoot.path)
          .compile(entry, '1.0.0', 'abc', out1);
      final r2 = AgentPackCompiler(agentRoot.path)
          .compile(entry, '1.0.0', 'abc', out2);
      expect(r1.zipFile.readAsBytesSync(), r2.zipFile.readAsBytesSync());
      out1.deleteSync(recursive: true);
      out2.deleteSync(recursive: true);
    });
  });
}

/// scripts/ subtree embedding and exec-mode recording.
void scriptsTests() {
  group('AgentPackCompiler scripts', () {
    test('any scripts reference embeds the whole scripts subtree', () {
      write('scripts/run-agent.sh', '#!/bin/bash\necho hi\n');
      write('scripts/providers/_common.sh', '# common\n');
      write('scripts/providers/claude.sh', '# claude\n');
      final entry = write(
          'with_scripts.json',
          jsonEncode({
            'name': 'X',
            'params': {
              'cliCommands': ['./agents/scripts/run-agent.sh']
            },
          }));
      final names = zipNames(compileAgent(entry).zipFile);
      expect(names, contains('scripts/run-agent.sh'));
      expect(names, contains('scripts/providers/_common.sh'));
      expect(names, contains('scripts/providers/claude.sh'));
    });

    test('shell scripts carry 0755 mode in the manifest', () {
      write('scripts/run-agent.sh', '#!/bin/bash\necho hi\n');
      final entry = write(
          'mode_agent.json',
          jsonEncode({
            'name': 'X',
            'params': {
              'cliCommands': ['./agents/scripts/run-agent.sh']
            },
          }));
      final manifest =
          jsonDecode(compileAgent(entry).manifestFile.readAsStringSync())
              as Map<String, dynamic>;
      final files = manifest['files'] as List;
      final sh =
          files.firstWhere((f) => (f as Map)['path'] == 'scripts/run-agent.sh')
              as Map;
      expect(sh['mode'], '0755');
    });
  });
}

/// Path-duality normalization and parent-chain inclusion.
void prefixNormalizationTests() {
  group('AgentPackCompiler normalization', () {
    test('parent.path chain config is included in the pack', () {
      write('js/base.js', '// base\n');
      write(
          'base_config.json',
          jsonEncode({
            'name': 'Base',
            'params': {'jsPath': 'agents/js/base.js'},
          }));
      final entry = write(
          'child_config.json',
          jsonEncode({
            'name': 'Child',
            'parent': {
              'path': 'agents/base_config.json',
              'override': ['params.agentParams']
            },
            'params': <String, dynamic>{},
          }));
      final names = zipNames(compileAgent(entry).zipFile);
      expect(names, contains('base_config.json'));
      expect(names, contains('js/base.js'));
    });

    test('agents/ and plain prefixes both normalize', () {
      write('js/a.js', '// a\n');
      write('js/b.js', '// b\n');
      final entry = write(
          'dual.json',
          jsonEncode({
            'name': 'Dual',
            'params': {
              'preJSAction': 'agents/js/a.js',
              'postJSAction': 'js/b.js',
            },
          }));
      final names = zipNames(compileAgent(entry).zipFile);
      expect(names, contains('js/a.js'));
      expect(names, contains('js/b.js'));
      expect(names, isNot(contains('agents/js/a.js')));
    });

    test('AGENTS.md and LICENSE are included when present', () {
      final entry = writeSimpleAgent();
      write('AGENTS.md', '# Agents\n');
      write('LICENSE', 'Apache-2.0\n');
      final names = zipNames(compileAgent(entry).zipFile);
      expect(names, contains('AGENTS.md'));
      expect(names, contains('LICENSE'));
    });
  });
}

/// The comment-aware JS scanner (JSDoc/commented requires must not match).
void commentStripperTests() {
  group('stripJsComments', () {
    test('strips line and block comments, keeps strings', () {
      const src = '''
// line comment
var url = "https://example.com/a//b"; /* block */ var x = 1;
/* multi
   line */
var s = 'not // a comment';
''';
      final stripped = AgentPackCompiler.stripJsComments(src);
      expect(stripped, isNot(contains('line comment')));
      expect(stripped, isNot(contains('block')));
      expect(stripped, contains('https://example.com/a//b')); // string kept
      expect(stripped, contains('not // a comment'));
      expect(stripped, contains('var x = 1;'));
    });

    test('keeps escaped quotes inside strings', () {
      const src = 'var s = "a\\"// not a comment";';
      expect(AgentPackCompiler.stripJsComments(src), src);
    });
  });
}
