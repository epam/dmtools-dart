/// Unit tests for [RunCommandProcessor] (Java `RunCommandProcessor` port).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dmtools/dmtools.dart';
import 'package:dmtools/src/compile/agent_pack_compiler.dart'
    hide AgentPackException;
import 'package:dmtools/src/pack/agent_pack_resolver.dart';
import 'package:test/test.dart';

import '../pack/pack_fixtures.dart';

late Directory _tmp;

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('dmtools_rcp_');
  });

  tearDown(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  _testJobNameMode();
  _testJsFileMode();
  _testConfigFileResolution();
  _testPackTokenWiring();
}

File _writeFile(String name, String content) {
  final f = File('${_tmp.path}/$name');
  f.writeAsStringSync(content);
  return f;
}

String _run(List<String> args) => const RunCommandProcessor().process(args);

void _testJobNameMode() {
  group('job-name mode', () {
    test('builds minimal config for a known job', () {
      final json = jsonDecode(_run(['run', 'codegenerator'])) as Map;
      expect(json['name'], 'codegenerator');
      expect(json['params'], {});
    });

    test('injects CLI overrides into params', () {
      final json =
          jsonDecode(_run(['run', 'teammate', '--model', 'gpt-4'])) as Map;
      expect(json['params']['model'], 'gpt-4');
    });

    test('parses JSON-array override values', () {
      final json =
          jsonDecode(_run(['run', 'teammate', '--list', '[1,2]'])) as Map;
      expect(json['params']['list'], [1, 2]);
    });

    test('parses JSON-object override values', () {
      final json =
          jsonDecode(_run(['run', 'teammate', '--obj', '{"a":"b"}'])) as Map;
      expect(json['params']['obj'], {'a': 'b'});
    });

    test('applies base64-encoded override config', () {
      final encoded = base64.encode(utf8.encode('{"params":{"k":"v"}}'));
      final json = jsonDecode(_run(['run', 'codegenerator', encoded])) as Map;
      expect(json['params']['k'], 'v');
    });
  });
}

void _testJsFileMode() {
  group('.js file mode', () {
    test('builds JSRunner config', () {
      final json = jsonDecode(_run(['run', 'script.js'])) as Map;
      expect(json['name'], 'JSRunner');
      expect(json['params']['jsPath'], 'script.js');
      expect(json['params']['jobParams'], {});
    });

    test('injects overrides into jobParams', () {
      final json =
          jsonDecode(_run(['run', 'script.js', '--key', 'val'])) as Map;
      expect(json['params']['jobParams']['key'], 'val');
    });

    test('injects JSON-array override into jobParams', () {
      final json =
          jsonDecode(_run(['run', 'script.js', '--items', '[1,2,3]'])) as Map;
      expect(json['params']['jobParams']['items'], [1, 2, 3]);
    });

    test('applies base64-encoded config', () {
      final encoded = base64.encode(
        utf8.encode('{"params":{"jobParams":{"extra":"data"}}}'),
      );
      final json = jsonDecode(_run(['run', 'script.js', encoded])) as Map;
      expect(json['params']['jobParams']['extra'], 'data');
    });
  });
}

void _testConfigFileResolution() {
  group('config file resolution', () {
    test('loads a simple JSON config file', () {
      _writeFile('job.json', '{"name":"myjob","params":{"k":"v"}}');
      final json = jsonDecode(_run(['run', '${_tmp.path}/job.json'])) as Map;
      expect(json['name'], 'myjob');
      expect(json['params']['k'], 'v');
    });

    test('throws ArgumentError for a missing file', () {
      expect(
        () => _run(['run', '${_tmp.path}/nope.json']),
        throwsArgumentError,
      );
    });

    test('injects CLI overrides on top of file config', () {
      _writeFile('job.json', '{"name":"job","params":{"a":"1"}}');
      final json =
          jsonDecode(_run(['run', '${_tmp.path}/job.json', '--b', '2'])) as Map;
      expect(json['params']['a'], '1');
      expect(json['params']['b'], '2');
    });
  });

  _testParentResolution();
  _testParentPackResolution();
}

void _testParentResolution() {
  group('parent-config resolution', () {
    test('deep-merges parent into child', () {
      _writeFile('parent.json', '{"params":{"k1":"p1","k2":"p2"}}');
      _writeFile('child.json', '''{
        "name":"child",
        "parent":{"path":"parent.json"},
        "params":{"k2":"c2"}
      }''');
      final json = jsonDecode(_run(['run', '${_tmp.path}/child.json'])) as Map;
      expect(json['name'], 'child');
      expect(json['params']['k1'], 'p1');
      expect(json['params']['k2'], 'c2');
    });

    test('concatenates arrays via merge directive', () {
      _writeFile('parent.json', '{"items":["a","b"]}');
      _writeFile('child.json', '''{
        "name":"child",
        "parent":{"path":"parent.json"},
        "merge":["items"],
        "items":["c"]
      }''');
      final json = jsonDecode(_run(['run', '${_tmp.path}/child.json'])) as Map;
      expect(json['items'], ['a', 'b', 'c']);
    });

    test('applies override directive', () {
      _writeFile('parent.json', '{"params":{"k":"parent"}}');
      _writeFile('child.json', '''{
        "name":"child",
        "parent":{"path":"parent.json"},
        "override":["params.k"],
        "params":{"k":"child"}
      }''');
      final json = jsonDecode(_run(['run', '${_tmp.path}/child.json'])) as Map;
      expect(json['params']['k'], 'child');
    });

    test('handles parent block with non-string path', () {
      _writeFile('child.json', '''{
        "name":"child",
        "parent":{"path":123}
      }''');
      final json = jsonDecode(_run(['run', '${_tmp.path}/child.json'])) as Map;
      expect(json['name'], 'child');
      expect(json.containsKey('parent'), isFalse);
    });

    test('handles non-map parent block', () {
      _writeFile('child.json', '{"name":"child","parent":"string"}');
      final json = jsonDecode(_run(['run', '${_tmp.path}/child.json'])) as Map;
      expect(json['name'], 'child');
      expect(json.containsKey('parent'), isFalse);
    });
  });
}

/// Test seam: records the token passed to [AgentPackResolver.resolve] and
/// stops the pack path before any download/unpack happens.
class _RecordingPackResolver extends AgentPackResolver {
  String? capturedToken;

  @override
  bool isPack(String? runArg) => true;

  @override
  ResolvedPack resolve(String runArg, {String? githubToken}) {
    capturedToken = githubToken;
    throw const AgentPackException('recording seam');
  }
}

/// SOURCE_GITHUB_TOKEN wiring into the pack resolver (PR #249 review: the
/// token was never passed to `resolve()`).
void _testPackTokenWiring() {
  group('agent-pack token wiring', () {
    test('passes SOURCE_GITHUB_TOKEN to the pack resolver', () {
      final resolver = _RecordingPackResolver();
      PropertyReader.setOverrides({'SOURCE_GITHUB_TOKEN': 'test-token-123'});
      try {
        expect(
          () => RunCommandProcessor(packResolver: resolver)
              .process(['run', 'pack.zip']),
          throwsA(isA<AgentPackException>()),
        );
        expect(resolver.capturedToken, 'test-token-123');
      } finally {
        PropertyReader.clearOverrides();
      }
    });

    test('passes no usable token when SOURCE_GITHUB_TOKEN is empty', () {
      final resolver = _RecordingPackResolver();
      // An empty override is accepted as-is (Java parity) and must not leak
      // a developer's real env token into the resolver.
      PropertyReader.setOverrides({'SOURCE_GITHUB_TOKEN': ''});
      try {
        expect(
          () => RunCommandProcessor(packResolver: resolver)
              .process(['run', 'pack.zip']),
          throwsA(isA<AgentPackException>()),
        );
        expect(resolver.capturedToken, isNot('test-token-123'));
      } finally {
        PropertyReader.clearOverrides();
      }
    });
  });
}

/// `parent.path` pointing at an agent pack (local .zip / URL / registry ref):
/// the parent is unpacked, its own chain resolved inside the pack, and its
/// pack-relative paths rewritten to absolute cache paths before the merge.
void _testParentPackResolution() {
  group('parent-config from agent pack', () {
    test('local pack zip parent merges and rewrites paths to the cache', () {
      final zip = _buildParentPack();
      final packsRoot = Directory('${_tmp.path}/packs');
      final resolver = AgentPackResolver(packsRoot: packsRoot);
      _writeFile('child.json', '''{
        "name":"child",
        "parent":{"path":"${zip.path.replaceAll('\\', '/')}"},
        "params":{"fromChild":"yes"}
      }''');
      final json = jsonDecode(
        RunCommandProcessor(packResolver: resolver)
            .process(['run', '${_tmp.path}/child.json']),
      ) as Map;
      expect(json['params']['fromParent'], 'yes');
      expect(json['params']['fromChild'], 'yes');
      final jsPath = json['params']['jsPath'] as String;
      expect(
        jsPath.startsWith(packsRoot.path),
        isTrue,
        reason: 'parent jsPath is rewritten into the pack cache: $jsPath',
      );
      expect(File(jsPath).existsSync(), isTrue);
    });

    test('registry-ref parent (<agent>@latest) resolves and merges', () async {
      final zip = _buildParentPack();
      final zipBytes = zip.readAsBytesSync();
      final server = await startRegistryServer({
        '/parent_agent-1.0.0.zip': zipBytes,
        '/parent_agent-1.0.0.zip.sha256': utf8.encode(
          '${sha256.convert(zipBytes)}  parent_agent-1.0.0.zip',
        ),
        '/catalog.json': utf8.encode(jsonEncode({'parent_agent': '1.0.0'})),
      });
      try {
        final packsRoot = Directory('${_tmp.path}/packs');
        final resolver = AgentPackResolver(
          packsRoot: packsRoot,
          registryBaseUrl: 'http://127.0.0.1:${server.port}',
        );
        _writeFile('child.json', '''{
          "name":"child",
          "parent":{"path":"parent_agent@latest"},
          "params":{"fromChild":"yes"}
        }''');
        final json = jsonDecode(
          RunCommandProcessor(packResolver: resolver)
              .process(['run', '${_tmp.path}/child.json']),
        ) as Map;
        expect(json['params']['fromParent'], 'yes');
        expect(json['params']['fromChild'], 'yes');
        final jsPath = json['params']['jsPath'] as String;
        expect(
          jsPath.startsWith(packsRoot.path),
          isTrue,
          reason: 'registry parent jsPath is rewritten into the pack cache',
        );
        expect(File(jsPath).existsSync(), isTrue);
      } finally {
        server.isolate.kill();
      }
    });

    test('pack parent with #entry override uses the overridden entry', () {
      final zip = _buildParentPack(withAltEntry: true);
      final packsRoot = Directory('${_tmp.path}/packs');
      final resolver = AgentPackResolver(packsRoot: packsRoot);
      _writeFile('child.json', '''{
        "name":"child",
        "parent":{"path":"${zip.path.replaceAll('\\', '/')}#alt.json"}
      }''');
      final json = jsonDecode(
        RunCommandProcessor(packResolver: resolver)
            .process(['run', '${_tmp.path}/child.json']),
      ) as Map;
      expect(json['params']['altEntry'], 'yes');
      expect(
        json['params']['fromParent'],
        isNull,
        reason: 'the default entry config is not loaded',
      );
    });

    test('non-pack parent paths still resolve from the filesystem', () {
      _writeFile('parent.json', '{"params":{"k":"p"}}');
      _writeFile(
        'child.json',
        '{"name":"child","parent":{"path":"parent.json"}}',
      );
      final json = jsonDecode(_run(['run', '${_tmp.path}/child.json'])) as Map;
      expect(json['params']['k'], 'p');
    });
  });
}

/// Builds a real parent pack zip with `js/helper.js` and an entry config.
File _buildParentPack({bool withAltEntry = false}) {
  final agentRoot = Directory('${_tmp.path}/parent_agent_root')
    ..createSync(recursive: true);
  File('${agentRoot.path}/js/helper.js')
    ..createSync(recursive: true)
    ..writeAsStringSync('// helper\n');
  final params = <String, dynamic>{
    'jsPath': 'agents/js/helper.js',
    'fromParent': 'yes',
  };
  final entryMap = <String, dynamic>{
    'name': 'ParentAgent',
    if (withAltEntry)
      // Referencing alt.json via parent pulls it into the pack closure, so
      // the `#alt.json` entry override has a file to load.
      'parent': {'path': 'agents/alt.json'},
    'params': params,
  };
  final entry = File('${agentRoot.path}/parent_agent.json')
    ..writeAsStringSync(jsonEncode(entryMap));
  if (withAltEntry) {
    File('${agentRoot.path}/alt.json').writeAsStringSync(
      jsonEncode({
        'name': 'ParentAgent',
        'params': {'altEntry': 'yes'},
      }),
    );
  }
  final dist = Directory('${_tmp.path}/parent_dist')
    ..createSync(recursive: true);
  return AgentPackCompiler(agentRoot.path)
      .compile(entry, '1.0.0', 'deadbeef', dist)
      .zipFile;
}
