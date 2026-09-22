/// Tests for the failed-CLI-run response contract (gh-192): when the agent
/// fails, the extracted response must be a bounded failure summary — never
/// the full session log — because post-actions publish the response verbatim
/// as PR/ticket comments.
library;

import 'dart:io';

import 'package:dmtools/dmtools.dart';
import 'package:test/test.dart';

void main() {
  boundedLogTests();
  failureSummaryTests();
  failureFallbackTests();
  downstreamMarkerContractTests();
}

// ======================================================================
// boundedLog
// ======================================================================

void boundedLogTests() {
  group('boundedLog', () {
    test('returns short logs unchanged', () {
      const log = 'CLI Command: echo hi\nResponse:\nhi';
      expect(boundedLog('$log\n'), log);
    });

    test('bounds long logs to head + truncation marker + tail', () {
      final lines = List.generate(400, (i) => 'session log line $i');
      final bounded = boundedLog(lines.join('\n'), cap: 4000);
      expect(bounded, contains('session log line 0'));
      expect(bounded, contains('session log line 399'));
      // The middle of the session log must be dropped — only the head and
      // tail windows survive.
      expect(bounded, isNot(contains('session log line 200')));
      expect(bounded, contains('truncated'));
      expect(bounded.length, lessThan(boundedResponseLogCap + 200));
    });

    test('honors a custom cap', () {
      final bounded = boundedLog('a' * 100, cap: 10);
      expect(bounded, startsWith('aaaaa'));
      expect(bounded, endsWith('aaaaa'));
      expect(bounded, contains('truncated'));
    });

    test('returns a log of exactly cap unchanged (no marker)', () {
      final log = 'a' * boundedResponseLogCap;
      expect(boundedLog(log), log);
      expect(boundedLog(log), isNot(contains('truncated')));
    });

    test('a cap+1 log keeps a marker reporting the single omitted character',
        () {
      final bounded = boundedLog('a' * (boundedResponseLogCap + 1));
      expect(bounded, contains('truncated 1 character '));
      expect(bounded, isNot(contains('1 characters')));
    });

    test('never splits a UTF-16 surrogate pair at the head boundary', () {
      // 'aaaa' + 😀 (2 code units) straddles the head cut of cap 10.
      final bounded = boundedLog('aaaa😀${'b' * 20}', cap: 10);
      expect(
        bounded.runes.every((r) => r < 0xD800 || r > 0xDFFF),
        isTrue,
        reason: 'excerpt must not contain lone surrogates',
      );
      expect(bounded.startsWith('aaaa'), isTrue);
    });

    test('never splits a UTF-16 surrogate pair at the tail boundary', () {
      // The tail cut of cap 3 lands between 😀's surrogate pair.
      final bounded = boundedLog('a😀b', cap: 3);
      expect(
        bounded.runes.every((r) => r < 0xD800 || r > 0xDFFF),
        isTrue,
        reason: 'excerpt must not contain lone surrogates',
      );
      expect(bounded.endsWith('b'), isTrue);
    });
  });
}

// ======================================================================
// CliAgent failure response — bounded summary
// ======================================================================

void failureSummaryTests() {
  group('CliAgent failure response', () {
    test(
        'failed agent run without response.md yields a bounded failure '
        'summary, not the full session log', () async {
      final tmp = await _createTempDir();
      try {
        // A realistic failed run: a large multi-line session log followed by
        // a non-zero exit (2+ commands, so batch accumulation is covered).
        final session =
            List.generate(400, (i) => 'session log line $i').join('\n');
        await File('${tmp.path}/session.log').writeAsString(session);
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = [
              'cat "${tmp.path}/session.log"',
              'echo "provider crash detail" && exit 7',
            ]
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        final response = result['response'] as String;
        expect(response, contains('CLI command failed'));
        expect(response, contains('exit code 7'));
        // Downstream classification contract (gh-192 review): the vendored
        // post-actions (pushReworkChanges/developTicketAndCreatePR in the
        // pinned agents pack) sniff params.response for established
        // interruption markers — 'outputs/response.md missing' must appear
        // verbatim so a failed run is retried, never announced as completed.
        expect(response, contains('outputs/response.md missing'));
        // Head of the log survives: the failing command line.
        expect(response, contains('session.log'));
        // Tail of the log survives: the actual failure detail.
        expect(response, contains('provider crash detail'));
        expect(response, contains('session log line 399'));
        // The middle of the session log is dropped.
        expect(response, isNot(contains('session log line 200')));
        expect(response.length, lessThan(boundedResponseLogCap + 400));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('failed run that still wrote response.md keeps the file content',
        () async {
      final tmp = await _createTempDir();
      try {
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = [
              'mkdir -p outputs && '
                  'printf "partial summary" > outputs/$responseFileName && '
                  'exit 7',
            ]
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        expect(result['response'], 'partial summary');
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

// ======================================================================
// CliAgent failure response — fallback contracts
// ======================================================================

void failureFallbackTests() {
  group('CliAgent failure response fallbacks', () {
    test('successful run without response.md keeps the full log fallback',
        () async {
      final tmp = await _createTempDir();
      try {
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['echo hello_world']
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        final response = result['response'] as String;
        expect(response, contains('CLI Command: echo hello_world'));
        expect(response, contains('hello_world'));
        expect(response, isNot(contains('CLI command failed')));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('successful run without response.md cannot publish an unbounded log',
        () async {
      final tmp = await _createTempDir();
      try {
        // An agent that "succeeds" but skips the output file: the same
        // megabyte-comment failure mode, one branch over (gh-192 review).
        final session =
            List.generate(400, (i) => 'session log line $i').join('\n');
        await File('${tmp.path}/session.log').writeAsString(session);
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['cat "${tmp.path}/session.log"']
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        final response = result['response'] as String;
        expect(response, contains('session log line 0'));
        expect(response, contains('session log line 399'));
        expect(response, isNot(contains('session log line 200')));
        expect(response, contains('truncated'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test(
        'monitored path: timeout-style failure keeps the error marker in the '
        'excerpt head, drops the transcript middle', () async {
      final tmp = await _createTempDir();
      try {
        final session =
            List.generate(400, (i) => 'session log line $i').join('\n');
        await File('${tmp.path}/session.log').writeAsString(session);
        // The production rework job (pr_rework.json) configures timerJSAction,
        // which routes execution through executeCommandsWithCallbacks — a
        // different commandResponses format than the buffered path.
        final result =
            await const CliExecutionHelper().executeCommandsWithCallbacks(
          ['cat "${tmp.path}/session.log"', 'exit 124'],
          workingDirectory: tmp.path,
          callbacks: const CliExecutionCallbacks(
            errorHandler: _noopErrorHandler,
            timerIntervalSeconds: 0,
          ),
        );
        expect(result.hasFatalError, isTrue);
        final excerpt = boundedLog(result.commandResponses);
        // Head window survives: the monitored-path failure marker the
        // vendored JS matches on, wherever the run's size lands it.
        expect(excerpt, contains('Command failed (exit code 124)'));
        expect(excerpt, contains('session log line 399'));
        expect(excerpt, isNot(contains('session log line 200')));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test(
        'requireCliOutputFile keeps the interruption marker but bounds the log',
        () async {
      final tmp = await _createTempDir();
      try {
        final session =
            List.generate(400, (i) => 'session log line $i').join('\n');
        await File('${tmp.path}/session.log').writeAsString(session);
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = [
              'cat "${tmp.path}/session.log"',
              'exit 7',
            ]
            ..requireCliOutputFile = true
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        final response = result['response'] as String;
        expect(
          response,
          startsWith('CLI command executed but did not produce output file'),
        );
        expect(response, contains('session log line 399'));
        expect(response, isNot(contains('session log line 200')));
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}

/// Creates a unique temporary directory.
Future<Directory> _createTempDir() async {
  return Directory.systemTemp.createTemp('cli_failure_response_test_');
}

/// No-op error hook — enables the monitored execution path.
void _noopErrorHandler(String errorMessage) {}

void downstreamMarkerContractTests() {
  group('CliAgent failure response ↔ vendored post-action contract', () {
    test(
        'the failed-run summary embeds a marker the pinned agents pack '
        'classifies as interrupted', () async {
      final tmp = await _createTempDir();
      try {
        final result = await (CliAgent(
          params: CliAgentParams()
            ..cliCommands = ['exit 7']
            ..cleanupInputFolder = false,
          workingDirectory: tmp.path,
        )).run();
        final response = result['response'] as String;
        expect(response, contains('outputs/response.md missing'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('the pinned post-action matcher still recognizes the embedded marker',
        () {
      // pushReworkChanges.js classifies params.response by text-sniffing
      // (params.currentCliHasFatalError is never set by the Dart runtime).
      // Pin both halves of the contract: the summary carries the token and
      // the vendored matcher (agents/ submodule at the pinned SHA) lists it.
      final matcherSource =
          File('agents/js/pushReworkChanges.js').readAsStringSync();
      expect(
        matcherSource,
        contains("text.indexOf('outputs/response.md missing')"),
        reason: 'agents/js/pushReworkChanges.js must keep matching '
            "'outputs/response.md missing' — the Dart runtime embeds it in "
            'every failed-run summary so vendored post-actions retry the '
            'run instead of announcing it as completed (gh-192)',
      );
    });
  });
}
