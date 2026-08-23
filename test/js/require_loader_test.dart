import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

/// CommonJS `require()` loader tests — Dart port of the Java
/// `JobJavaScriptBridgeCoverageTest` require cases (`requireProxyRequires…`,
/// `requireLoadsModuleFromFilesystemRelativeToScript`, `requireCachesModules`,
/// `requireFailsForMissingModule`) plus `../` normalization and the
/// currentScriptDirectory save/restore contract from Java `loadModule`.
void main() {
  _requireLoadsModuleRelativeToScript();
  _requireNormalizesParentSegments();
  _requireRestoresScriptDirectory();
  _requireCachesModules();
  _requireFailsForMissingModule();
  _requireArgumentValidation();
}

File _writeScript(String basePath, String name, String content) {
  final file = File('$basePath/$name');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file;
}

/// Runs [script] and decodes its `action(params)` JSON result.
dynamic _run(File script, Map<String, dynamic> jobParams) =>
    jsonDecode(const JsJobRunner().runScript(
      scriptPath: script.path,
      jobParams: jobParams,
    )!);

void _requireLoadsModuleRelativeToScript() {
  test('require loads a module relative to the script directory', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_req_rel');
    try {
      _writeScript(
        dir.path,
        'util.js',
        "exports.greet = function(name) { return 'hi ' + name; };",
      );
      final main = _writeScript(dir.path, 'main.js', '''
var util = require('./util.js');
function action(params) { return util.greet(params.jobParams.name); }
''');
      expect(_run(main, {'name': 'module'}), 'hi module');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

void _requireNormalizesParentSegments() {
  test('require resolves ../ segments against the script directory', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_req_up');
    try {
      _writeScript(
        '${dir.path}/lib',
        'deep.js',
        "exports.where = 'deep';",
      );
      final main = _writeScript(dir.path, 'main.js', '''
var deep = require('./lib/deep.js');
var again = require('./lib/../lib/./deep.js');
function action(params) { return deep.where + ':' + again.where; }
''');
      expect(_run(main, {}), 'deep:deep');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

void _requireRestoresScriptDirectory() {
  test('require restores the script directory for nested requires', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_req_nest');
    try {
      // The submodule is in lib/ and itself requires a sibling — only a
      // correct save/set/restore of the script directory resolves it.
      _writeScript(
        '${dir.path}/lib',
        'inner.js',
        "exports.value = 'inner';",
      );
      _writeScript(
        '${dir.path}/lib',
        'outer.js',
        "var inner = require('./inner.js');\n"
            "exports.value = 'outer+' + inner.value;",
      );
      final main = _writeScript(dir.path, 'main.js', '''
var outer = require('./lib/outer.js');
var inner = require('./lib/inner.js');
function action(params) { return outer.value + '|' + inner.value; }
''');
      expect(_run(main, {}), 'outer+inner|inner');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

void _requireCachesModules() {
  test('require caches modules by resolved path', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_req_cache');
    try {
      _writeScript(dir.path, 'counter.js', '''
globalThis.__loadCount = (globalThis.__loadCount || 0) + 1;
exports.count = globalThis.__loadCount;
''');
      final main = _writeScript(dir.path, 'main.js', '''
var first = require('./counter.js');
var second = require('./counter.js');
function action(params) { return first.count + ',' + second.count; }
''');
      expect(_run(main, {}), '1,1');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

void _requireFailsForMissingModule() {
  test('require of a missing module fails with the Java-parity message', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_req_missing');
    try {
      final main = _writeScript(dir.path, 'main.js', '''
var missing = require('./does-not-exist.js');
function action(params) { return 'unreached'; }
''');
      expect(
        () => const JsJobRunner().runScript(
          scriptPath: main.path,
          jobParams: {},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Failed to require module: ./does-not-exist.js'),
              contains('JavaScript file not found'),
            ),
          ),
        ),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

void _requireArgumentValidation() {
  for (final (label, call) in [
    ('zero arguments', 'require()'),
    ('two arguments', "require('./a.js', 'b')"),
  ]) {
    test('require with $label throws the Java-parity validation error', () {
      final dir = Directory.systemTemp.createTempSync('dmtools_req_args');
      try {
        final main = _writeScript(
          dir.path,
          'main.js',
          'function action(params) { return $call; }',
        );
        expect(
          () => const JsJobRunner().runScript(
            scriptPath: main.path,
            jobParams: {},
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(
                'require() expects exactly one argument (module path)',
              ),
            ),
          ),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  }
}
