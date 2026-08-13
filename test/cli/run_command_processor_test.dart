/// Unit tests for [RunCommandProcessor] (Java `RunCommandProcessor` port).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

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
      final json = jsonDecode(_run([
        'run',
        'teammate',
        '--model',
        'gpt-4',
      ])) as Map;
      expect(json['params']['model'], 'gpt-4');
    });

    test('parses JSON-array override values', () {
      final json = jsonDecode(_run([
        'run',
        'teammate',
        '--list',
        '[1,2]',
      ])) as Map;
      expect(json['params']['list'], [1, 2]);
    });

    test('parses JSON-object override values', () {
      final json = jsonDecode(_run([
        'run',
        'teammate',
        '--obj',
        '{"a":"b"}',
      ])) as Map;
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
      final json = jsonDecode(_run([
        'run',
        'script.js',
        '--key',
        'val',
      ])) as Map;
      expect(json['params']['jobParams']['key'], 'val');
    });

    test('injects JSON-array override into jobParams', () {
      final json = jsonDecode(_run([
        'run',
        'script.js',
        '--items',
        '[1,2,3]',
      ])) as Map;
      expect(json['params']['jobParams']['items'], [1, 2, 3]);
    });

    test('applies base64-encoded config', () {
      final encoded = base64.encode(utf8.encode(
        '{"params":{"jobParams":{"extra":"data"}}}',
      ));
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
      final json = jsonDecode(_run([
        'run',
        '${_tmp.path}/job.json',
        '--b',
        '2',
      ])) as Map;
      expect(json['params']['a'], '1');
      expect(json['params']['b'], '2');
    });
  });

  _testParentResolution();
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
