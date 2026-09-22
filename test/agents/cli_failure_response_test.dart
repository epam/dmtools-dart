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
