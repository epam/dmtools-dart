import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/js/async_job_pool.dart';
import 'package:dmtools/src/js/engine_factory.dart';
import 'package:dmtools/src/js/job_runner.dart';
import 'package:quickjs_runtime/quickjs_runtime.dart';
import 'package:test/test.dart';

/// Cross-runtime conformance: `test/fixtures/cross_runtime_conformance.js`
/// is byte-identical with the epam/dm.ai Java test resource and the
/// quickjs_runtime fixture. QuickJS (this test, through the real product
/// wiring — [JsJobRunner], the dmtools worker pool, and the opt-in
/// `nodeCompat` layer installed by `wireEngine` on the main engine AND
/// worker engines) and GraalJS (`JsCrossRuntimeConformanceTest` in
/// dm.ai) must produce the identical result.
///
/// Protocol (identical on every runtime — see the fixture header):
/// the bridge calls `action(params)` (sync surface + `runAsync`
/// parallel execution; promise reactions drain at the end of each eval);
/// the timers family (`actionTimers` + one `drainTimers` pass) is driven
/// through the product's own engine factory below.
///
/// The worker adapter builds a fresh engine per job, so dispatched
/// functions see `require('path')`, `Buffer`, and `TextEncoder` exactly
/// like the main script does.

/// The canned transport every runtime's harness installs for the
/// fixture's `conformance://ping` fetch call (JSON string return, same
/// contract as the production httpFetch hook).
const String cannedFetchResponse =
    '{"status":200,"headers":{"x":"y"},"body":"pong"}';

String? cannedFetch(String requestJson) {
  final url = jsonDecode(requestJson)['url'] as String?;
  if (url == 'conformance://ping') return cannedFetchResponse;
  return jsonEncode({
    'status': 404,
    'headers': <String, String>{},
    'body': 'no conformance route',
  });
}

/// Expected `action(params)` result — kept verbatim from the
/// quickjs_runtime conformance test (change only in lockstep).
const Map<String, dynamic> expected = {
  'globalAlias': true,
  'processType': 'object',
  'envIsObject': true,
  'cwdIsString': true,
  'joined': 'a/b/c.txt',
  'baseName': 'z.md',
  'assertOk': true,
  'formatted': 'answer=42',
  'utf8ByteLen': 10,
  'utf8RoundTrip': true,
  'base64': true,
  'clockIsNumber': true,
  'uuidShape': true,
  'randomFilled': true,
  'cloneDeep': true,
  'buffer': {
    'typeofFn': true,
    'isUint8Array': true,
    'b64': 'aGVsbG8=',
    'hexRoundTrip': true,
    'latin1Hex': '68ff',
    'utf8ByteLen': 12,
    'le': 1,
    'be': 9,
    'slice': 'bc',
    'copyRoundTrip': true,
    'isBufferTrue': true,
    'isBufferFalse':
        true, // fixture value: `B.isBuffer(new Uint8Array(4)) === false`
  },
  'url': {
    'href': 'https://example.com/a/b?q=1&x=%20#frag',
    'origin': 'https://example.com',
    'pathname': '/a/b',
    'search': '?q=1&x=%20',
    'hash': '#frag',
    'q': '1',
    'xDecoded': ' ',
    'getAllA': '1|2',
    'bDecoded': 'x y',
    'appendForm': 'k=a+b',
    'canParse': true,
  },
  'utilExtras': {
    'inspectString': "'hi'",
    'inspectNumber': '42',
    'isArray': true,
    'isString': true,
    'hasTime': true,
  },
  'osProcess': {
    'osEolType': 'string',
    'osPlatformType': 'string',
    'osArchType': 'string',
    'osHomedirType': 'string',
    'nextTickType': 'function',
    'hrtimeType': 'function',
    'argvIsArray': true,
    'pidIsNumber': true,
    'exitIsFunction': true,
  },
  'intl': {
    'numberFormat': true,
    'dateTimeFormat': true,
    'canonicalLocales': true,
  },
  'events': {
    'got': 't1,o',
    'emitReturnNoListener': true,
    'hasOff': true,
    'listenerCount': 1,
  },
  'fetchShapes': {
    'fetchTypeof': 'function',
    'headerGet': 'b',
    'headerHas': true,
    'responseType': 'function',
    'callStatus': 200,
    'callHeader': 'y',
    'callBody': true,
  },
  'stubGuards': true,
  'parallel': {
    'sum': 5050,
    'workerBase': 'parallel.js',
    'workerUtf8': 4,
    'workerBuffer': 'b2s=',
    'allValues': ['first', 'second'],
  },
};

/// The timers protocol result (steps 3-5 of the fixture header): one
/// ready drain pass runs immediates before due timeouts; the microtask
/// fired at the end of the actionTimers eval.
const Map<String, dynamic> expectedTimers = {
  'log': ['sync', 'p1', 'imm', 't0', 'iv'],
};

void main() {
  late AsyncJobPool pool;

  setUp(() async {
    pool = AsyncJobPool(workers: 2);
    await pool.boot();
  });

  tearDown(() => pool.dispose());

  _conformanceResultTests(() => pool);
  _timersProtocolTests();
  _knobsOffTests(() => pool);
}

void _conformanceResultTests(AsyncJobPool Function() pool) {
  test('conformance script produces the identical cross-runtime result', () {
    final runner = JsJobRunner();
    final result = runner.runScript(
      scriptPath: 'test/fixtures/cross_runtime_conformance.js',
      jobParams: const {'parallelWorkers': 2, 'nodeCompat': true},
      config: JsRunConfig(pool: pool(), httpFetch: cannedFetch),
    );
    final decoded = jsonDecode(result!) as Map<String, dynamic>;
    expect(decoded, equals(expected));
  });
}

void _timersProtocolTests() {
  test('timers protocol through the product engine factory', () {
    final rt = QuickjsRuntime();
    try {
      final handle = wireEngine(
        rt,
        EngineSpec(
          context: EngineContext(jobParams: const {'nodeCompat': true}),
          httpFetch: cannedFetch,
          // the fixture's timer family runs under the same drain mode the
          // product uses (block — headless CLI, "setTimeout as sleep")
        ),
      );
      rt.setGlobal('params', {
        'jobParams': {'nodeCompat': true},
      });
      final errors = <String?>[];
      rt.eval(
        File('test/fixtures/cross_runtime_conformance.js').readAsStringSync(),
        filename: 'cross_runtime_conformance.js',
        errMsg: errors,
      );
      if (errors.isNotEmpty) throw StateError(errors.first!);
      rt.eval('actionTimers(params)', errMsg: errors);
      if (errors.isNotEmpty) throw StateError(errors.first!);
      final stats = handle!.drainTimers();
      expect(stats, isNotNull);
      expect(
        jsonDecode(rt.eval('globalThis.__timersOut')!) as Map<String, dynamic>,
        equals(expectedTimers),
      );
    } finally {
      rt.close();
    }
  });
}

void _knobsOffTests(AsyncJobPool Function() pool) {
  test('knobs off: the same script fails (no runAsync, no console)', () {
    final runner = JsJobRunner();
    expect(
      () => runner.runScript(
        scriptPath: 'test/fixtures/cross_runtime_conformance.js',
        jobParams: const {},
        config: JsRunConfig(pool: pool()),
      ),
      throwsA(anything),
    );
  });
}
