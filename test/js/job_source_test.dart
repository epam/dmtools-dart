import 'dart:convert';
import 'dart:io';

import 'package:dmtools/src/agents/agent_factory.dart';
import 'package:dmtools/src/js/job_runner.dart';
import 'package:test/test.dart';

import 'echo_server_helper.dart';

/// Script-source resolution, action contract, host-function validation, and
/// JSRunner context forwarding — Dart port of the Java
/// `JobJavaScriptBridgeCoverageTest` cases (`executeJavaScriptRequires…`,
/// `executeJavaScriptThrowsForMissingResourceAndFile`,
/// `executeToolViaJavaProxyRequiresToolName`,
/// `setEnvVariableProxyRequiresTwoArguments`,
/// `executeJavaScriptLoadsScriptFromFilesystem`) plus the
/// `JavaScriptExecutor`/`JSRunner` parameter-forwarding contract.
void main() {
  _actionContract();
  _missingFile();
  _hostFunctionValidation();
  _inlineSource();
  _urlSource();
  _jsRunnerContext();
  _jsRunnerJobFailures();
}

String? _runSource(String source) =>
    const JsJobRunner().runScript(scriptPath: source, jobParams: {});

/// Expects [source] to fail with a [StateError] whose message matches
/// [message] — each call site wraps this in a visible `expect` so the
/// test_assertions gate sees an assertion.
Matcher _failureWith(Object message) =>
    throwsA(isA<StateError>().having((e) => e.message, 'message', message));

void _actionContract() {
  group('action contract', () {
    test('script without an action function fails (Java parity)', () {
      expect(
        () => _runSource('var x = 1;'),
        _failureWith(contains("must define an 'action' function")),
      );
    });

    test('script eval exceptions surface with the Java-parity prefix', () {
      expect(
        () => _runSource(
          'function action(params) { return callToUndefinedFunction(); }',
        ),
        _failureWith(contains('JavaScript execution failed')),
      );
    });

    test('action body exceptions surface as evaluation failures', () {
      expect(
        () =>
            _runSource("function action(params) { throw new Error('boom'); }"),
        _failureWith(allOf(
          contains('JavaScript execution failed'),
          contains('boom'),
        )),
      );
    });
  });
}

void _missingFile() {
  test('missing script file fails with the Java-parity message', () {
    final dir = Directory.systemTemp.createTempSync('dmtools_src_missing');
    try {
      expect(
        () => const JsJobRunner().runScript(
          scriptPath: '${dir.path}/no/such/script.js',
          jobParams: {},
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('JavaScript file not found'),
        )),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}

void _hostFunctionValidation() {
  group('host function argument validation', () {
    test('executeToolViaJava with no arguments throws in JS', () {
      expect(
        () => _runSource(
          'function action(params) { return executeToolViaJava(); }',
        ),
        _failureWith(contains(
          'executeToolViaJava requires at least 1 argument: toolName',
        )),
      );
    });

    test('set_env_variable with one argument throws in JS', () {
      expect(
        () => _runSource(
          "function action(params) { set_env_variable('ONLY_ONE'); "
          "return 'unreached'; }",
        ),
        _failureWith(contains(
          'set_env_variable requires 2 arguments: propertyName, envVarName',
        )),
      );
    });

    test('set_env_variable with two arguments returns success', () {
      expect(
        _runSource("function action(params) { "
            "return set_env_variable('SOME_PROP', 'PATH').success; }"),
        'true',
      );
    });
  });
}

void _inlineSource() {
  group('inline jsPath', () {
    test('function-prefixed source executes as inline code', () {
      expect(
        _runSource('function action(params) { return "inline-ok"; }'),
        '"inline-ok"',
      );
    });

    test('bare word source falls back to inline code (Java parity)', () {
      // No '/', no '.js' suffix, not function-prefixed: loadJavaScriptCode
      // treats it as inline JS, and the action contract still applies.
      expect(
        () => _runSource('params'),
        _failureWith(contains("must define an 'action' function")),
      );
    });
  });
}

void _urlSource() {
  group('URL jsPath', () {
    // The live-server test needs the Python fixture subprocess: curl blocks
    // the isolate, so an in-process HttpServer could never answer.
    if (!hasPython3()) return;
    late EchoServer server;

    setUp(() async {
      server = EchoServer();
      await server.start();
    });

    tearDown(() => server.stop());

    test('http URL source is fetched and executed', () {
      final url = 'http://127.0.0.1:${server.port}/script.js';
      expect(_runSource(url), '"from-url"');
    });
  });

  test('unreachable URL fails mentioning the URL', () {
    final url = 'http://127.0.0.1:1/script.js';
    expect(
      () => _runSource(url),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        allOf(contains('Failed to load JS from source code'), contains(url)),
      )),
    );
  });
}

void _jsRunnerContext() {
  group('JsRunnerJob', () {
    Directory tempDir() => Directory.systemTemp.createTempSync('dmtools_jsr');

    test('forwards job context into the JS params object', () {
      final dir = tempDir();
      try {
        final script = File('${dir.path}/ctx.js')..writeAsStringSync(_ctxJs);
        final result = JsRunnerJob(_fullContextParams(script.path)).run();
        expect(result['success'], isTrue);
        final ctx = jsonDecode(result['result'] as String) as Map;
        expect(ctx, {
          'jobParams': 'v',
          'ticket': 'PROJ-1',
          'response': 'ai-response',
          'initiator': 'user@example.com',
          'inputJql': 'project = X',
          'metadata': 'ctx-1',
        });
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

void _jsRunnerJobFailures() {
  group('JsRunnerJob failures', () {
    Directory tempDir() => Directory.systemTemp.createTempSync('dmtools_jsrf');

    test('missing jsPath fails with the Java-parity message', () {
      expect(
        JsRunnerJob({'jobParams': {}}).run(),
        {
          'success': false,
          'error': contains('jsPath parameter is required'),
        },
      );
      expect(
        JsRunnerJob({'jsPath': '   '}).run(),
        {
          'success': false,
          'error': contains('jsPath parameter is required'),
        },
      );
    });

    test('script failure becomes an error result, not a crash', () {
      final dir = tempDir();
      try {
        final script = File('${dir.path}/boom.js')
          ..writeAsStringSync(
            "function action(params) { throw new Error('kaboom'); }",
          );
        final result = JsRunnerJob({'jsPath': script.path}).run();
        expect(result['success'], isFalse);
        expect(result['error'] as String, contains('kaboom'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

/// Script echoing every forwarded context field from `params`.
const String _ctxJs = '''
function action(params) {
  return {
    jobParams: params.jobParams.k,
    ticket: params.ticket.key,
    response: params.response,
    initiator: params.initiator,
    inputJql: params.inputJql,
    metadata: params.metadata.contextId
  };
}
''';

/// A JSRunner params block carrying every context field.
Map<String, dynamic> _fullContextParams(String jsPath) => {
      'jsPath': jsPath,
      'jobParams': {'k': 'v'},
      'ticket': {'key': 'PROJ-1'},
      'response': 'ai-response',
      'initiator': 'user@example.com',
      'inputJql': 'project = X',
      'metadata': {'contextId': 'ctx-1'},
    };
