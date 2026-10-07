import 'dart:convert';
import 'dart:io';

import 'package:dmtools/dmtools.dart' show PropertyReader, pathIsWithin;
import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

/// CommonJS `require()` loader tests — Dart port of the Java
/// `JobJavaScriptBridgeCoverageTest` require cases (`requireProxyRequires…`,
/// `requireLoadsModuleFromFilesystemRelativeToScript`, `requireCachesModules`,
/// `requireFailsForMissingModule`) plus `../` normalization and the
/// currentScriptDirectory save/restore contract from Java `loadModule`.
void main() {
  _requireLoadsModuleRelativeToScript();
  _loaderHostReadNotReachableAsGlobal();
  _requireNormalizesParentSegments();
  _requireRestoresScriptDirectory();
  _requireCachesModules();
  _requireFailsForMissingModule();
  _requireArgumentValidation();
  _requireLoadsPackModuleWithoutAnyAllowlist();
  _requireLoadsConfiguredPackModule();
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

/// gh-369 review BLOCK: the uncontained host read must not stay reachable
/// as a JS global after the loader installs — otherwise any agent script
/// bypasses the gh-365 containment with one direct call (the reviewer
/// demonstrated reading ~/.dmtools/version.txt, next stop dmtools.env).
void _loaderHostReadNotReachableAsGlobal() {
  test('__loaderReadHost and __loaderFileRead are gone from globalThis', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_req_glob');
    try {
      final main = _writeScript(dir.path, 'main.js', '''
function action(params) {
    return {
        host: typeof __loaderReadHost,
        fileRead: typeof __loaderFileRead,
        require: typeof require
    };
}
''');
      expect(_run(main, {}), {
        'host': 'undefined',
        'fileRead': 'undefined',
        'require': 'function'
      });
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

/// gh-369: the loader is a HOST primitive (Java `loadJavaScriptCode`
/// parity) — it must read module sources with NO allowlist and NO
/// containment, exactly like the live SM tick pulling
/// `~/.dmtools/packs/<pack>/js/…` under a job workdir; while the
/// AGENT-visible `file_read` of the same path stays sandboxed (gh-365).
void _requireLoadsPackModuleWithoutAnyAllowlist() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  final usable = home != null &&
      home.isNotEmpty &&
      !pathIsWithin(home, Directory.systemTemp.path);

  test('require loads a pack module with no allowlist; file_read stays blocked',
      skip: usable ? null : 'no HOME outside the tmpdir to test against', () {
    final packJs = Directory('$home/.dmtools-gh369-test-req/packs/p/js');
    packJs.createSync(recursive: true);
    File('${packJs.path}/configLoader.js')
        .writeAsStringSync('exports.loaded = true;');
    final dir = Directory.systemTemp.createTempSync('dmtools_req_norule');
    try {
      // No DMTOOLS_FILE_READ_ALLOWED_PATHS override anywhere: the live
      // v0.1.41 SM-tick shape.
      final main = _writeScript(dir.path, 'main.js', '''
var loader = require("$home/.dmtools-gh369-test-req/packs/p/js/configLoader.js");
var agentRead = file_read({ path: "$home/.dmtools-gh369-test-req/packs/p/js/configLoader.js" });
function action(params) {
  return loader.loaded === true && (agentRead === null || agentRead === undefined);
}
''');

      expect(_run(main, {}), isTrue);
    } finally {
      Directory('$home/.dmtools-gh369-test-req').deleteSync(recursive: true);
      dir.deleteSync(recursive: true);
    }
  });
}

/// gh-367: a pack-internal require — the SM pack's loader pulls sibling
/// modules from `~/.dmtools/packs/<pack>/js/…`, an absolute path OUTSIDE
/// the repo workdir. The `require` chain reads through the direct host
/// read, so the configured `DMTOOLS_FILE_READ_ALLOWED_PATHS` glob (Java
/// `FileTools` `isAllowedByConfig` parity) admits the sandboxed
/// `file_read` of the same path there too — otherwise the agent-visible
/// read dies while the loader keeps working (gh-369 made the loader
/// host-side).
void _requireLoadsConfiguredPackModule() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  final usable = home != null &&
      home.isNotEmpty &&
      !pathIsWithin(home, Directory.systemTemp.path);

  test('require admits a pack module under the configured dmtools home',
      skip: usable ? null : 'no HOME outside the tmpdir to test against', () {
    final packRoot = Directory('$home/.dmtools-gh367-test-req');
    final packJs = Directory('${packRoot.path}/packs/sm_github-0.1.36/js');
    packJs.createSync(recursive: true);
    File('${packJs.path}/configLoader.js')
        .writeAsStringSync('exports.loaded = true;');
    PropertyReader.setOverrides({
      'DMTOOLS_FILE_READ_ALLOWED_PATHS': '$home/.dmtools-gh367-test-req/**',
    });
    final dir = Directory.systemTemp.createTempSync('dmtools_req_pack');
    try {
      final main = _writeScript(dir.path, 'main.js', '''
var loader = require("$home/.dmtools-gh367-test-req/packs/sm_github-0.1.36/js/configLoader.js");
function action(params) { return loader.loaded === true; }
''');

      expect(_run(main, {}), isTrue);
    } finally {
      PropertyReader.clearOverrides();
      packRoot.deleteSync(recursive: true);
      dir.deleteSync(recursive: true);
    }
  });
}
