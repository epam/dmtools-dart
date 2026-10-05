/// Tests for loud JS-action failure propagation — Java parity ports of
/// epam/dm.ai#580 (`fix(teammate): detect uncaught JS exceptions swallowed
/// by JavaScriptExecutor`) and epam/dm.ai#585 (`fix: rethrow postJSAction
/// uncaught JS exceptions to fail GHA step loudly`).
///
/// Java `Teammate` runs these actions loudly: an uncaught exception in
/// `preCliJSAction` is an unexpected setup failure (skip CLI execution and
/// postJSAction, abort the job after the ticket loop) and an uncaught
/// exception in `postJSAction` fails the job immediately with the full JS
/// error text. Java `CliAgent` (direct cliagent configs) keeps the
/// swallow-and-continue contract — `CliAgent.failOnJsActionErrors` selects
/// the Teammate behavior and `TeammateJob` turns it on.
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  cliAgentDefaultModeTests();
  postJsLoudFailureTests();
  postJsHookOrderTests();
  postJsTicketKeyTests();
  preCliThrowTests();
  preCliBusinessSkipTests();
  preCliSuccessTests();
  preJsAdvisoryLoudTests();
  teammatePreCliAbortTests();
  teammatePreCliMultiTicketTests();
  teammateSingleRunAbortTests();
  teammatePostJsAbortTests();
}

// ======================================================================
// CliAgent — default mode (Java CliAgent parity: swallow & continue)
// ======================================================================

void cliAgentDefaultModeTests() {
  group('CliAgent default mode — JS action failures stay advisory', () {
    test(
        'postJSAction uncaught exception does not fail the run '
        '(Java CliAgent parity)', () async {
      final tmp = await _createTempDir();
      try {
        final post =
            _actionJs(tmp, 'post_throw.js', 'throw new Error("boom");');
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..postJSAction = post.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(result['success'], isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test(
        'preCliJSAction uncaught exception does not skip the CLI phase '
        '(Java CliAgent parity)', () async {
      final tmp = await _createTempDir();
      final marker = File('${tmp.path}/marker');
      try {
        final preCli =
            _actionJs(tmp, 'precli_throw.js', 'throw new Error("boom");');
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo ran > marker']
            ..preCliJSAction = preCli.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(result['success'], isTrue);
        expect(marker.existsSync(), isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

// ======================================================================
// CliAgent — loud mode (Java Teammate #580/#585 parity)
// ======================================================================

void postJsLoudFailureTests() {
  group('CliAgent loud mode — postJSAction failure', () {
    test(
        'uncaught exception fails the run with the JS error text '
        '(#585)', () async {
      final tmp = await _createTempDir();
      try {
        final post =
            _actionJs(tmp, 'post_throw.js', 'throw new Error("boom");');
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..postJSAction = post.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          failOnJsActionErrors: true,
        )).run();
        expect(result['success'], isFalse);
        expect(result['postJsActionUncaught'], isTrue);
        final error = result['error'] as String;
        expect(error, contains('postJSAction threw an uncaught exception'));
        expect(error, contains('boom'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

void postJsHookOrderTests() {
  group('CliAgent loud mode — postJSAction hook order', () {
    test(
        'uncaught exception skips the cache hook but still runs reset '
        '(Java runJobImpl finally parity)', () async {
      final tmp = await _createTempDir();
      final cacheLog = '${tmp.path}/cache.log';
      final resetLog = '${tmp.path}/reset.log';
      try {
        final post =
            _actionJs(tmp, 'post_throw.js', 'throw new Error("boom");');
        await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..postJSAction = post.path
            ..cache = 'echo cache >> "$cacheLog"'
            ..reset = 'echo reset >> "$resetLog"'
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          failOnJsActionErrors: true,
        )).run();
        expect(File(cacheLog).existsSync(), isFalse);
        expect((await File(resetLog).readAsString()).trim(), 'reset');
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

void postJsTicketKeyTests() {
  group('CliAgent loud mode — postJSAction ticket key', () {
    test('error message names the ticket key when ticket data is set',
        () async {
      final tmp = await _createTempDir();
      try {
        final post =
            _actionJs(tmp, 'post_throw.js', 'throw new Error("boom");');
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo done']
            ..postJSAction = post.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          ticketData: const {
            'key': 'GH-345',
            'fields': {'summary': 's'},
          },
          failOnJsActionErrors: true,
        )).run();
        expect(result['success'], isFalse);
        expect(result['error'] as String, contains('for ticket GH-345'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

void preCliThrowTests() {
  group('CliAgent loud mode — preCliJSAction uncaught exception', () {
    test(
        'skips CLI execution and postJSAction, marks the run as an '
        'unexpected setup failure (#580)', () async {
      final tmp = await _createTempDir();
      final cliMarker = File('${tmp.path}/cli_marker');
      final postLog = '${tmp.path}/post.log';
      try {
        final preCli = _actionJs(
            tmp, 'precli_throw.js', 'throw new Error("git exploded");');
        final post = _actionJs(
          tmp,
          'post_ok.js',
          'file_write({path: "$postLog", content: "ran"});',
        );
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo ran > cli_marker']
            ..preCliJSAction = preCli.path
            ..postJSAction = post.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          failOnJsActionErrors: true,
        )).run();
        expect(cliMarker.existsSync(), isFalse, reason: 'CLI phase skipped');
        expect(File(postLog).existsSync(), isFalse,
            reason: 'postJSAction skipped');
        // Java parity: the ticket itself is a "Skipped" result item — the
        // job-level abort happens in Teammate after the ticket loop.
        expect(result['success'], isTrue);
        expect(result['response'], 'Skipped: preCliJSAction reported failure');
        expect(result['unexpectedSetupFailure'], isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test(
        'returning {success:false} is a business skip — CLI and '
        'postJSAction skipped, but no unexpected-setup marker (#580)',
        () async {
      final tmp = await _createTempDir();
      final cliMarker = File('${tmp.path}/cli_marker');
      try {
        final preCli = _actionJs(
          tmp,
          'precli_skip.js',
          'return {success: false, reason: "business skip"};',
        );
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo ran > cli_marker']
            ..preCliJSAction = preCli.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          failOnJsActionErrors: true,
        )).run();
        expect(cliMarker.existsSync(), isFalse);
        expect(result['success'], isTrue);
        expect(result['response'], 'Skipped: preCliJSAction reported failure');
        expect(result['unexpectedSetupFailure'], isNull);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test(
        'returning false is a business skip too '
        '(Java isPreCliJSActionFailure parity)', () async {
      final tmp = await _createTempDir();
      final cliMarker = File('${tmp.path}/cli_marker');
      try {
        final preCli = _actionJs(tmp, 'precli_false.js', 'return false;');
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo ran > cli_marker']
            ..preCliJSAction = preCli.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          failOnJsActionErrors: true,
        )).run();
        expect(cliMarker.existsSync(), isFalse);
        expect(result['success'], isTrue);
        expect(result['response'], 'Skipped: preCliJSAction reported failure');
        expect(result['unexpectedSetupFailure'], isNull);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('a successful preCliJSAction leaves the lifecycle untouched',
        () async {
      final tmp = await _createTempDir();
      final cliMarker = File('${tmp.path}/cli_marker');
      try {
        final preCli = _actionJs(tmp, 'precli_ok.js',
            'file_write({path: "${cliMarker.path}", content: "ran"});');
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo ok']
            ..preCliJSAction = preCli.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          failOnJsActionErrors: true,
        )).run();
        expect(result['success'], isTrue);
        expect(result['unexpectedSetupFailure'], isNull);
        expect(result['response'], contains('ok'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('CliAgent loud mode — preJSAction', () {
    test(
        'uncaught exception stays advisory (Java Teammate parity — the '
        'marker is only checked for preCliJSAction and postJSAction)',
        () async {
      final tmp = await _createTempDir();
      final cliMarker = File('${tmp.path}/cli_marker');
      try {
        final pre = _actionJs(tmp, 'pre_throw.js', 'throw new Error("boom");');
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo ran > cli_marker']
            ..preJSAction = pre.path
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
          failOnJsActionErrors: true,
        )).run();
        expect(result['success'], isTrue);
        expect(cliMarker.existsSync(), isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

// ======================================================================
// TeammateJob — job-level loud semantics
// ======================================================================

void teammateJobLoudModeTests() {
  group('TeammateJob — preCliJSAction uncaught exception (#580)', () {
    test(
        'all tickets are attempted, then the job aborts with the '
        'unexpected-setup-failure message', () async {
      final tmp = await _createTempDir();
      final cliLog = '${tmp.path}/cli.log';
      try {
        final preCli = _actionJs(
          tmp,
          'precli_cond.js',
          'if (params.ticket.key === "PROJ-1") '
              'throw new Error("git checkout failed");',
        );
        final job = TeammateJob(
          params: {
            'inputJql': 'key in (PROJ-1, PROJ-2)',
            'cliCommands': ['echo cli >> "$cliLog"'],
            'preCliJSAction': preCli.path,
            'cleanupInputFolder': false,
          },
          workingDirectory: tmp.path,
          ticketSource: (_) async => [hydratedProj1, hydratedProj2],
        );
        final result = await job.run();
        expect(result['success'], isFalse);
        expect(
          result['error'],
          'Teammate job aborted: preCliJSAction threw an unexpected error '
          '(e.g. a git command failure) for ticket(s) [PROJ-1] — see the '
          'warnings logged above for the underlying error(s).',
        );
        // Java parity: a batch run keeps processing every ticket even when
        // one fails setup — the abort lands after the ticket loop.
        expect((await File(cliLog).readAsString()).trim().split('\n'),
            hasLength(1));
        final results = (result['results'] as List).cast<Map>();
        expect(results, hasLength(2));
        expect(results[0]['ticket'], 'PROJ-1');
        expect(
            results[0]['response'], 'Skipped: preCliJSAction reported failure');
        expect(results[1]['ticket'], 'PROJ-2');
        expect(results[1]['success'], isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('multiple failing tickets are all listed in the abort message',
        () async {
      final tmp = await _createTempDir();
      try {
        final preCli =
            _actionJs(tmp, 'precli_throw.js', 'throw new Error("x");');
        final job = TeammateJob(
          params: {
            'inputJql': 'key in (PROJ-1, PROJ-2)',
            'cliCommands': ['echo never'],
            'preCliJSAction': preCli.path,
            'cleanupInputFolder': false,
          },
          workingDirectory: tmp.path,
          ticketSource: (_) async => [hydratedProj1, hydratedProj2],
        );
        final result = await job.run();
        expect(result['success'], isFalse);
        expect(result['error'] as String,
            contains('for ticket(s) [PROJ-1, PROJ-2]'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('issues-driven single run aborts with the same message', () async {
      final tmp = await _createTempDir();
      try {
        Directory('${tmp.path}/input').createSync(recursive: true);
        File('${tmp.path}/input/ticket.md')
            .writeAsStringSync('Do the thing\nbody');
        final preCli =
            _actionJs(tmp, 'precli_throw.js', 'throw new Error("x");');
        final job = TeammateJob(
          params: {
            'metadata': {'contextId': 'gh-345'},
            'cliCommands': ['echo never'],
            'preCliJSAction': preCli.path,
          },
          workingDirectory: tmp.path,
        );
        final result = await job.run();
        expect(result['success'], isFalse);
        expect(result['error'] as String,
            contains('Teammate job aborted: preCliJSAction threw'));
        expect(result['error'] as String, contains('gh-345'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('TeammateJob — postJSAction uncaught exception (#585)', () {
    test(
        'the job fails immediately and remaining tickets are not '
        'processed (Java Teammate parity)', () async {
      final tmp = await _createTempDir();
      final cliLog = '${tmp.path}/cli.log';
      try {
        final post =
            _actionJs(tmp, 'post_throw.js', 'throw new Error("boom");');
        final job = TeammateJob(
          params: {
            'inputJql': 'key in (PROJ-1, PROJ-2)',
            'cliCommands': ['echo cli >> "$cliLog"'],
            'postJSAction': post.path,
            'cleanupInputFolder': false,
          },
          workingDirectory: tmp.path,
          ticketSource: (_) async => [hydratedProj1, hydratedProj2],
        );
        final result = await job.run();
        expect(result['success'], isFalse);
        final error = result['error'] as String;
        expect(error, contains('postJSAction threw an uncaught exception'));
        expect(error, contains('PROJ-1'));
        expect(error, contains('boom'));
        // Java parity: the RuntimeException propagates out of runJobImpl —
        // the second ticket is never attempted.
        expect((await File(cliLog).readAsString()).trim().split('\n'),
            hasLength(1));
        final results = (result['results'] as List).cast<Map>();
        expect(results, hasLength(1));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

const hydratedProj1 = {
  'key': 'PROJ-1',
  'fields': {'summary': 'One', 'description': 'First.'},
};

const hydratedProj2 = {
  'key': 'PROJ-2',
  'fields': {'summary': 'Two', 'description': 'Second.'},
};

/// Writes a JS hook script wrapped in the action() contract enforced by
/// [JsJobRunner.runScript] (Java `JobJavaScriptBridge` parity).
File _actionJs(Directory dir, String name, String body) =>
    File('${dir.path}/$name')
      ..writeAsStringSync('function action(params) { $body }');

Future<Directory> _createTempDir() async =>
    Directory.systemTemp.createTemp('loud_js_fail_test');
