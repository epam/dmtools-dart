import 'dart:convert';

import 'package:quickjs_runtime/quickjs_runtime.dart';
import 'package:test/test.dart';

/// Spike tests proving the QuickJS FFI bridge works end-to-end: eval, JSON
/// marshaling, synchronous JS→Dart→JS host callbacks, globals, and a
/// CommonJS-style require pattern. These validate the Phase 4 runtime.
void main() {
  _testEvalBasics();
  _testHostCallbacks();
  _testGlobalsAndRequire();
}

void _testEvalBasics() {
  group('eval basics', () {
    test('returns JSON number result', () {
      final rt = QuickjsRuntime();
      expect(rt.eval('1 + 2'), '3');
      rt.close();
    });

    test('returns JSON string result', () {
      final rt = QuickjsRuntime();
      expect(rt.eval('"hello"'), '"hello"');
      rt.close();
    });

    test('returns JSON object result', () {
      final rt = QuickjsRuntime();
      final result = rt.eval('({a: 1, b: "x"})');
      final decoded = jsonDecode(result!);
      expect(decoded['a'], 1);
      expect(decoded['b'], 'x');
      rt.close();
    });
  });
}

void _testHostCallbacks() {
  group('host callbacks', () {
    test('synchronous JS→Dart→JS round-trip', () {
      final rt = QuickjsRuntime();
      rt.registerHostFunction('double_it', (argsJson) {
        final args = jsonDecode(argsJson);
        return jsonEncode({'result': args['value'] * 2});
      });
      final result = rt.eval('double_it({value: 21})');
      final decoded = jsonDecode(result!);
      expect(decoded['result'], 42);
      rt.close();
    });

    test('no-argument host function', () {
      final rt = QuickjsRuntime();
      rt.registerHostFunction('get_answer', (_) {
        return jsonEncode({'answer': 42});
      });
      final result = rt.eval('get_answer()');
      final decoded = jsonDecode(result!);
      expect(decoded['answer'], 42);
      rt.close();
    });

    test('undefined return becomes null', () {
      final rt = QuickjsRuntime();
      rt.registerHostFunction('noop', (_) => null);
      expect(rt.eval('noop()'), isNull);
      rt.close();
    });
  });
}

void _testGlobalsAndRequire() {
  group('globals and require', () {
    test('setGlobal injects value readable from JS', () {
      final rt = QuickjsRuntime();
      rt.setGlobal('params', {
        'jobParams': {'key': 'TEST-1'}
      });
      final result = rt.eval('params.jobParams.key');
      expect(jsonDecode(result!), 'TEST-1');
      rt.close();
    });

    test('CommonJS require pattern via eval + host fn', () {
      final rt = QuickjsRuntime();
      rt.registerHostFunction('file_read', (argsJson) {
        final args = jsonDecode(argsJson);
        if (args['path'] == './math.js') {
          return jsonEncode({
            'content':
                'module.exports = { add: function(a, b) { return a + b; } };',
          });
        }
        return null;
      });
      const code = '''
        var module = {exports: {}};
        var exports = module.exports;
        eval(file_read({path: "./math.js"}).content);
        module.exports.add(2, 3)
      ''';
      final result = rt.eval(code);
      expect(jsonDecode(result!), 5);
      rt.close();
    });
  });
}
